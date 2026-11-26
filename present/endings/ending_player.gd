class_name EndingPlayer
extends Control
## 结局演出播放器（= proto/js/endings.js createEndingPlayer + showEndingCard）。
## 用法：
##   var ep: EndingPlayer = EndingPlayer.new()
##   ep.setup(&"sunrise", sim)        # add_child 之前调用
##   ep.finished.connect(...)         # 结局卡确认（或 show_card = false 时演完）后发出
##   add_child(ep)
## 规则（同网页）：
##   · 全屏，自己吃掉点击 / 空格 / 回车 / Esc；开演 1.5 秒后才能跳过；
##   · 假结局（有 reveal）先跳到"揭示"，揭示至少露面 1 秒后才能再跳；
##   · 演完多停 0.35 秒，然后弹结局卡；结局卡打开 0.6 秒后按钮 / 回车 / 空格确认。
## 只读 sim（story.flags、stone.stuck、day、run_stats、content），从不写。
## 画面在 EndingScenes（静态绘制函数），画布上下文是 EndCanvas；陶瓶拉远 / 揭示碎片用一个离屏 SubViewport。

signal finished

## 开演多少秒后允许跳过
const SKIP_AT: float = 1.5
## 演完后停留
const HOLD: float = 0.35

## false：演完直接发 finished，不弹结局卡
var show_card: bool = true
## false：不自动推进时间（截图工具用 seek 控制）
var auto_advance: bool = true

var id: StringName = &"sunrise"
var sim: SimGame = null
var def: StoryDefs.Ending = null
## 演出时间（秒）
var t: float = 0.0
## dur + reveal
var total: float = 0.0
## 演出已结束（之后显示结局卡）
var done: bool = false
var flags: Dictionary = {}
## 本代碾得最多的物件类型（日出浮雕带，最多 6 个）
var types: PackedStringArray = []
## 粘在石头上的物件类型（真结局）
var stuck: PackedStringArray = []
var day: int = 0
## EndingScenes.shards 的缓存
var cracks: Dictionary = {}

var _cues: Array[Dictionary] = []
var _card: EndingCard = null
var _emitted: bool = false
var _off_vp: SubViewport = null
var _off_canvas: OffCanvas = null
var _off_mode: StringName = &""
var _off_t: float = 0.0


## 离屏画布（SubViewport 里的一层 Control）：画 EndingScenes.draw_offscreen
class OffCanvas:
	extends Control
	var player: EndingPlayer

	func _draw() -> void:
		if player != null:
			player._draw_off(self)


func setup(p_id: StringName, p_sim: SimGame) -> void:
	sim = p_sim
	id = p_id
	var by_id: Dictionary = sim.content.ending_by_id if sim != null and sim.content != null else {}
	if by_id.has(p_id):
		def = by_id[p_id]
	elif by_id.has(&"sunrise"):
		id = &"sunrise"
		def = by_id[&"sunrise"]
	if def == null:
		# 没有内容库（不该发生）：给一个空壳，避免崩
		def = StoryDefs.Ending.new()
		def.id = id
		def.kind = &"normal"
		def.dur = 1.0
	total = def.dur + def.reveal
	if sim != null and sim.story != null:
		flags = sim.story.flags
	day = sim.day if sim != null else 0
	var ct: Dictionary = flags.get("crush_types", {}) if flags.get("crush_types", {}) is Dictionary else {}
	types = top_types(ct, 6)
	stuck = stuck_types()
	_cues.clear()
	for c: Dictionary in def.cues:
		var cd: Dictionary = c.duplicate()
		cd["fired"] = false
		_cues.append(cd)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if def == null:
		setup(id, sim)
	_off_vp = SubViewport.new()
	_off_vp.disable_3d = true
	_off_vp.transparent_bg = false
	_off_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_off_vp.size = Vector2i(maxi(1, roundi(size.x)), maxi(1, roundi(size.y)))
	_off_canvas = OffCanvas.new()
	_off_canvas.player = self
	_off_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_off_vp.add_child(_off_canvas)
	add_child(_off_vp)
	resized.connect(_on_resized)
	_on_resized()
	# 同网页：开演时停掉滚石声和合唱
	Sfx.play(&"rumble", [0, 0])
	Sfx.play(&"chorus", [0])


func _on_resized() -> void:
	cracks = {}
	if _off_vp != null:
		_off_vp.size = Vector2i(maxi(1, roundi(size.x)), maxi(1, roundi(size.y)))
		_off_canvas.position = Vector2.ZERO
		_off_canvas.size = size
	queue_redraw()


# —————————— 数据（= topTypes / stuckTypes） ——————————

func _obj_ok(k: String) -> bool:
	if sim == null or sim.content == null:
		return false
	return (sim.content.object_by_id.has(StringName(k)) or sim.content.object_by_id.has(k)) and SpriteDB.has(StringName(k))


## 碾得最多的 n 种物件（不足用默认表补齐）
func top_types(m: Dictionary, n: int) -> PackedStringArray:
	var rows: Array[Dictionary] = []
	var i: int = 0
	for k: Variant in m.keys():
		var ks: String = str(k)
		if _obj_ok(ks):
			rows.append({"k": ks, "v": float(m[k]), "i": i})
			i += 1
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var va: float = a["v"]
		var vb: float = b["v"]
		return va > vb or (va == vb and int(a["i"]) < int(b["i"])))
	var out: PackedStringArray = []
	for r: Dictionary in rows:
		out.append(str(r["k"]))
	for k: String in EndingScenes.DEF_TYPES:
		if out.size() < n and not out.has(k) and SpriteDB.has(StringName(k)):
			out.append(k)
	return out.slice(0, n)


## 粘在石头上的物件（最近 14 个；不足 8 个用碾碎排行补到 12 个）
func stuck_types() -> PackedStringArray:
	var out: PackedStringArray = []
	if sim != null and sim.stone != null:
		var st: Array[Dictionary] = sim.stone.stuck
		var from: int = maxi(0, st.size() - 14)
		for j: int in range(from, st.size()):
			var ty: String = str(st[j].get("type", ""))
			if ty != "" and SpriteDB.has(StringName(ty)):
				out.append(ty)
	if out.size() < 8:
		var ct: Dictionary = flags.get("crush_types", {}) if flags.get("crush_types", {}) is Dictionary else {}
		for k: String in top_types(ct, 10):
			if out.size() < 12:
				out.append(k)
	return out


## 左上角的标签（endings.json kind_label）
func kind_label() -> String:
	var raw: Dictionary = _raw()
	var kl: Dictionary = raw.get("kind_label", {})
	var kdef: Dictionary = {"normal": Loc.t("ending_player.ending", "结局"), "true": Loc.t("ending_player.true_ending", "真结局"), "fake": Loc.t("ending_player.ending", "结局"), "normal-bad": Loc.t("ending_player.ending_overdue", "结局 · 逾期")}
	var k: String = String(def.kind)
	return Loc.t("ending.kind_label." + k, str(kl.get(k, kdef.get(k, Loc.t("ending_player.ending", "结局")))))


func _raw() -> Dictionary:
	if sim == null or sim.content == null:
		return {}
	var v: Variant = sim.content.raw.get("story/endings.json", {})
	return v if v is Dictionary else {}


# —————————— 时间轴 ——————————

func _process(dt: float) -> void:
	if done:
		return
	if auto_advance:
		advance(dt)
	_update_offscreen()
	queue_redraw()


## 推进 dt 秒（单帧最多 0.1 秒，同网页）
func advance(dt: float) -> void:
	if done:
		return
	t += clampf(dt, 0.0, 0.1)
	_fire_cues()
	if t >= total + HOLD:
		_end()


## 截图 / 测试用：直接跳到某个时刻（之前的声音提示视为已播放；超过 total + HOLD 则结束演出）
func seek(p_t: float) -> void:
	if done:
		return
	t = maxf(0.0, p_t)
	for c: Dictionary in _cues:
		if float(c["t"]) <= t:
			c["fired"] = true
	if t >= total + HOLD:
		_end()
		return
	_update_offscreen()
	queue_redraw()


func _fire_cues() -> void:
	for c: Dictionary in _cues:
		if not bool(c["fired"]) and t >= float(c["t"]):
			c["fired"] = true
			Sfx.play(StringName(c["sfx"]), c.get("args", []) as Array)


## 跳过（点击 / 空格 / 回车 / Esc）
func skip() -> void:
	if done or t < SKIP_AT:
		return
	if def.kind == &"fake" and t < def.dur:
		# 假结局：跳到揭示
		t = def.dur
		for c: Dictionary in _cues:
			if float(c["t"]) < def.dur:
				c["fired"] = true
		_update_offscreen()
		queue_redraw()
		return
	if def.kind == &"fake" and t < def.dur + 1.0:
		# 揭示是笑点：连按时至少让它露面 1 秒
		return
	_end()


## 自动测试：立即结束（不等结局卡），发出 finished
func skip_all() -> void:
	done = true
	if _card != null:
		_card.queue_free()
		_card = null
	_emit_finished()


func _end() -> void:
	if done:
		return
	done = true
	t = minf(t, total)
	# 最后一帧继续留在结局卡下面（陶瓶画板仍要离屏纹理）
	_update_offscreen()
	queue_redraw()
	if show_card:
		_card = EndingCard.create()
		_card.setup(def, sim, flags, _raw())
		_card.confirmed.connect(_emit_finished)
		add_child(_card)
	else:
		_emit_finished()


func _emit_finished() -> void:
	if _emitted:
		return
	_emitted = true
	finished.emit()


## 当前的结局卡（没弹出时为 null）
func card() -> EndingCard:
	return _card


# —————————— 离屏画布 ——————————

func _update_offscreen() -> void:
	var req: Dictionary = EndingScenes.offscreen(self, minf(t, total))
	_set_off_mode(req["mode"], float(req["t"]))


func _set_off_mode(mode: StringName, ti: float) -> void:
	if _off_vp == null:
		return
	var changed: bool = mode != _off_mode or ti != _off_t
	_off_mode = mode
	_off_t = ti
	_off_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED if mode == &"" else SubViewport.UPDATE_ALWAYS
	if changed:
		_off_canvas.queue_redraw()


## 离屏纹理（没在用时为 null）
func off_texture() -> Texture2D:
	if _off_vp == null or _off_mode == &"":
		return null
	return _off_vp.get_texture()


func _draw_off(ci: CanvasItem) -> void:
	if _off_mode == &"":
		return
	var c: EndCanvas = EndCanvas.new(ci, size.x, size.y)
	EndingScenes.draw_offscreen(c, size.x, size.y, self, _off_mode, _off_t)


# —————————— 绘制与输入 ——————————

func _draw() -> void:
	var W: float = size.x
	var H: float = size.y
	if W < 2.0 or H < 2.0:
		return
	var c: EndCanvas = EndCanvas.new(self, W, H)
	var tt: float = minf(t, total)
	if def.reveal > 0.0 and tt >= def.dur:
		EndingScenes.draw_reveal(c, W, H, tt - def.dur, self)
	else:
		EndingScenes.draw_scene(id, c, W, H, tt, self)
	c.reset()
	EndingScenes.draw_chrome(c, W, H, self)


func _gui_input(ev: InputEvent) -> void:
	var mb: InputEventMouseButton = ev as InputEventMouseButton
	if mb != null and mb.pressed:
		accept_event()
		if not done:
			skip()


func _input(ev: InputEvent) -> void:
	if done:
		return
	var k: InputEventKey = ev as InputEventKey
	if k == null or not k.pressed:
		return
	if k.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		get_viewport().set_input_as_handled()
		if not k.echo:
			skip()
