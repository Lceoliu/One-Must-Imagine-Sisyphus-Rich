class_name ChestView
extends RefCounted
## 命运宝瓶的画面（= 网页 coins.js drawWorld 的宝瓶部分 + drawWheel + 命运加成计时）：
## 世界里：宝瓶落地、轻轻上下浮、打开后淡出，四周一团呼吸的金光；
## 屏幕上：三个转轮（克罗托 / 拉刻西斯 / 阿特洛波斯）依次停下，每格是德拉克马或命运（线轴，MoiraIcon），
## 揭晓"命运 +N / 三女神点头 / 迈达斯之触"；迈达斯生效时在连碾下方计时。只读 sim.chests；转轮滚动是纯表现。

const GOLD: Color = Color("f0b93a")
const GOLD_HI: Color = Color("ffe08a")
## 不是 const：文字要按当前语言取（Loc.t），所以每次建界面时现算
var MOIRAI: PackedStringArray = [Loc.t("chest_view.clotho", "克罗托"), Loc.t("chest_view.lachesis", "拉刻西斯"), Loc.t("chest_view.atropos", "阿特洛波斯")]

## 当前转盘的表现状态（随 sim 的 wheel 换新）
var _wheel_ch: Dictionary = {}
var _sym: Array[int] = [0, 0, 0]
var _stops: Array[float] = [0.5, 0.85, 1.25]
## 转轮的声音（= 网页 coins.js updateWheel）：已经响过"咔"的格数、上一次"嗒"的时刻
var _snd_stopped: int = 0
var _snd_tick_t: float = 0.0


# ———————————————— 世界（金色层）————————————————
func draw_world(c: CanvasItem, sim: SimGame, vr: Vector2, t: float) -> void:
	var PPM: float = WorldView.PPM
	for ch: Dictionary in sim.chests.chests:
		var x: float = float(ch["x"])
		if x < vr.x - 10.0 or x > vr.y + 10.0:
			continue
		var open: bool = ch["state"] == &"open"
		var key: StringName = &"ui_amphora_open" if open else &"ui_amphora"
		var hm: float = maxf(0.6, float(ch["h"])) * (0.75 if open else 1.0)
		var a: float = clampf(1.0 - (float(ch["t"]) - 2.4) / 0.8, 0.0, 1.0) if open else 1.0
		var base: Vector2 = WorldView.p(x, float(ch["y"]))
		var pulse: float = 1.0 + 0.12 * sin(t * 5.0 + x)
		Glow.draw(c, base + Vector2(0.0, -hm * PPM * 0.5), hm * PPM * 1.1 * pulse, Color(GOLD, (0.5 if open else 0.65) * a))
		var tex: Texture2D = SpriteDB.tex(key)
		if tex == null:
			continue
		var bob: float = 0.0 if open or ch["state"] != &"idle" else absf(sin(t * 3.0 + x)) * hm * 0.06
		# 落在坡上的陶瓮：倾角封顶、底贴地（WorldView.ground_fit）；还在空中飞的照原样
		var hp: float = hm * PPM
		var wp: float = hp * SpriteDB.aspect(key)
		var g: Vector3 = WorldView.ground_fit(sim.world, x, wp / PPM * 0.6, 0.03, WorldView.PROP_TILT, true)
		var on_ground: bool = absf(float(ch["y"]) - sim.world.y_at_x(x)) < 0.3
		var at: Vector2 = WorldView.p(x, g.y) if on_ground else base
		c.draw_set_transform(at, -g.z if on_ground else 0.0, Vector2.ONE)
		c.draw_texture_rect(tex, Rect2(-wp / 2.0, -hp - bob * PPM, wp, hp), false, Color(1, 1, 1, a))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ———————————————— 屏幕 ————————————————
func draw_hud(h: HudView, sim: SimGame, vp: Vector2) -> void:
	var cs: ChestSystem = sim.chests
	if not cs.wheel.is_empty():
		_draw_wheel(h, cs.wheel, vp, sim.is_night())
	elif cs.midas_t > 0.0:
		var y: float = HudView.FR + 8.0 + 62.0 + 70.0 + 86.0 + 40.0
		h.text_at(Loc.t("chest_view.midas_touch_s", "迈达斯之触 · %ss") % Js.to_fixed(cs.midas_t, 1), Vector2(vp.x / 2.0, y), 17, GOLD_HI, HORIZONTAL_ALIGNMENT_CENTER)


## 三格的结果就是 sim 摇出来的转轮（0 德拉克马 / 1 命运）；前两格都是命运时第三格多转一会儿吊胃口
func _setup(w: Dictionary) -> void:
	_wheel_ch = w["ch"]
	var reels: Array = _wheel_ch.get("reels", [])
	for i: int in 3:
		_sym[i] = int(reels[i]) if i < reels.size() else 0
	var tease: bool = _sym[0] == 1 and _sym[1] == 1
	# 模拟在 1.4 秒结算：第三格要在那之前停
	_stops = [0.5, 0.85, 1.36 if tease else 1.2]
	_snd_stopped = 0
	_snd_tick_t = 0.0


func _reel_pos(t: float, i: int) -> float:
	var u: float = clampf(t / _stops[i], 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - u, 3.0)
	return _sym[i] + (12.0 + 6.0 * i) * (1.0 - e)


## 转动时每 75ms 一声棘轮"嗒"，每格停下一声"咔"（越往后越重）；由绘制驱动，只看转轮自己的时间 t
func _wheel_sound(t: float, stopped: int) -> void:
	while _snd_stopped < stopped:
		Sfx.play(&"reelStop", [_snd_stopped])
		_snd_stopped += 1
	if stopped < 3 and t - _snd_tick_t > 0.075:
		_snd_tick_t = t
		Sfx.play(&"reelTick")


func _draw_wheel(h: HudView, w: Dictionary, vp: Vector2, night: bool) -> void:
	if w["ch"] != _wheel_ch:
		_setup(w)
	var t: float = float(w["t"])
	var end: float = float(w["end"])
	var box: float = 72.0
	var gap: float = 16.0
	var cx: float = vp.x / 2.0
	var cy: float = vp.y * 0.42
	var u: float = minf(1.0, t / 0.22)
	var open: float = 1.0 + 2.2 * pow(u - 1.0, 3.0) + 1.2 * pow(u - 1.0, 2.0)
	var close: float = clampf((end - t) / 0.25, 0.0, 1.0) if t > end - 0.25 else 1.0
	var sy: float = maxf(0.001, open * close)
	var pw: float = box * 3.0 + gap * 2.0 + 44.0
	var ph: float = box + 92.0
	h.draw_set_transform_matrix(h.slot_xf(&"Wheel") * Transform2D(0.0, Vector2(1.0, sy), 0.0, Vector2(cx, cy)))
	var panel: Rect2 = Rect2(-pw / 2.0, -ph / 2.0 - 12.0, pw, ph)
	h.draw_rect(panel, Color(0.02, 0.03, 0.07, 0.88) if night else Color(0.07, 0.047, 0.04, 0.88))
	h.draw_rect(panel.grow(-0.5), Color("3b5c94") if night else Color("c8642a"), false, 1.5)
	h.text_at(Loc.t("chest_view.fate_urn", "命运宝瓶"), Vector2(0.0, -ph / 2.0 + 12.0), 19, GOLD_HI, HORIZONTAL_ALIGNMENT_CENTER)
	var frame: Texture2D = SpriteDB.tex(&"ui_key")
	var stopped: int = 0
	for k: int in 3:
		if t >= _stops[k]:
			stopped += 1
	_wheel_sound(t, stopped)
	for i: int in 3:
		var x: float = (i - 1) * (box + gap)
		var y: float = 6.0
		var is_stopped: bool = stopped > i
		var dt_stop: float = t - _stops[i]
		var pop: float = (1.0 + 0.12 * sin(dt_stop / 0.18 * PI)) if is_stopped and dt_stop < 0.18 else 1.0
		var c0: Vector2 = Vector2(x, y)
		if frame != null:
			var fs: float = (box + 12.0) * pop
			h.draw_texture_rect(frame, Rect2(c0 - Vector2(fs, fs) / 2.0, Vector2(fs, fs)), false)
		else:
			h.draw_rect(Rect2(c0 - Vector2(box, box) / 2.0, Vector2(box, box)), Color("e9d3a8"), false, 1.0)
		var win: float = box * 0.62 * pop
		h.draw_rect(Rect2(c0 - Vector2(win, win) / 2.0, Vector2(win, win)), Color("0b1430") if night else Color("2a1810"))
		var p: float = _reel_pos(t, i)
		var base: int = int(floorf(p))
		var frac: float = p - base
		for j: int in range(-1, 2):
			var sym: int = posmod(base + j, 2)
			var yy: float = (j - frac) * win * 0.95
			if absf(yy) > win * 0.5:
				continue
			var r: float = win * 0.38
			# 窗口外的部分按距离淡出（代替裁剪）
			var a: float = clampf(1.0 - (absf(yy) - (win * 0.5 - r)) / r, 0.0, 1.0)
			if is_stopped and sym == 1 and j == 0:
				Glow.draw(h, c0 + Vector2(0.0, yy), r * 2.0, Color(GOLD, 0.6))
			if sym == 1:
				MoiraIcon.draw(h, c0 + Vector2(0.0, yy), r * 0.95, a, is_stopped and j == 0 and _sym.count(1) == 3)
				continue
			var tex: Texture2D = SpriteDB.tex(&"coin_drachma")
			if tex != null:
				h.draw_texture_rect(tex, Rect2(c0 + Vector2(-r, yy - r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, a))
			else:
				h.draw_circle(c0 + Vector2(0.0, yy), r, Color(GOLD, a))
		h.text_at(MOIRAI[i], Vector2(x, y + box / 2.0 + 20.0), 13, Color("dfe8f5") if night else Color("f1e3c8"), HORIZONTAL_ALIGNMENT_CENTER)
	h.draw_set_transform_matrix(h.slot_xf(&"Wheel"))
	# 揭晓文字（不随展开缩放，单独淡入）
	if stopped >= 3:
		var res: int = int(w["res"])
		var k2: float = clampf((t - _stops[2]) / 0.2, 0.0, 1.0) * close
		var val: float = float(_wheel_ch.get("given", 0.0))
		var mo: float = float(_wheel_ch.get("moira", 0.0))
		var title: String = Loc.t("chest_view.fates_nod", "三女神点头") if res == 1 else (Loc.t("chest_view.midas_touch", "迈达斯之触") if res == 2 else Loc.t("chest_view.fate", "命运 +%s") % NumFmt.fmt(mo))
		var sub: String = Loc.t("chest_view.fate", "命运 +%s") % NumFmt.fmt(mo) if res == 1 else (Loc.t("chest_view.double_pay_everything_crushed", "+%s · 8 秒内碾碎之物皆化为金 ×2") % NumFmt.fmt(val) if res == 2 else Loc.t("chest_view.drachmas", "德拉克马 +%s") % NumFmt.fmt(val))
		var y2: float = cy + 80.0
		h.text_at(title, Vector2(cx, y2 + 10.0), 30 if res != 0 else 26, Color(GOLD_HI if res != 0 else Color("f1e3c8"), k2), HORIZONTAL_ALIGNMENT_CENTER)
		h.text_at(sub, Vector2(cx, y2 + 38.0), 16, Color(GOLD, k2), HORIZONTAL_ALIGNMENT_CENTER)
