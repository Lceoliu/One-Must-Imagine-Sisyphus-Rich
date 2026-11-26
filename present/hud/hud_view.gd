class_name HudView
extends Control
## HUD（移植 render.js drawHUD 的布局与信息；画法按 Godot 重写）。
## 左上日晷与钟点；顶部三块陶片（金钱 / 海拔 / 石重），摇到命运后金钱下面多一块命运；右侧海拔柱；夜里连碾；底部提示缎带；横幅与闪光。
## 每一块的位置由 hud.tscn 里的槽位（HudSlot）决定：槽位相对 default_slot() 的平移 / 缩放会套到那一块的绘制上；
## 槽位不可见 = 不画那一块。用 HudView.create() 建（带槽位）；.new() 建的没有槽位，全按默认位置画。
## 分层缓存（2026-10-16，每帧全画要 1.5 毫秒）：各块画在 hud.tscn 的各层（*Layer）上，每帧只比一下它依赖的数值，变了才重画那一层；
## 有动画的块（滚动、闪烁、白闪）动画期间照常每帧画。自己身上每帧只画别的文件（赐福 / 剧情 / 宝瓶）的 draw_hud。

const GOLD: Color = Color("f0b93a")
const GOLD_HI: Color = Color("ffe08a")
const FR: float = 14.0

var sim: SimGame = null
var fxv: FxView = null
var t: float = 0.0
var mix: float = 0.0
var display_money: float = 0.0
var display_night: float = 0.0
var money_pop: float = 0.0
## 命运计数刚加过：闪一下（秒）
var moira_pop: float = 0.0
var banner: Dictionary = {}
var flash_a: float = 0.0
var flash_col: Color = Color.WHITE
var flash_at: Vector2 = Vector2(NAN, NAN)
var toasts: Array[Dictionary] = []
var wv: WorldView = null
## 赐福画面（流派 HUD、赐福排）；main 设置
var boons: BoonView = null
## 剧情画面（名字标签、旁白、屏外提示）；main 设置
var story_view: StoryView = null
## 命运宝瓶转盘；main 设置
var chest_view: ChestView = null
## 金钱里程表的状态（render.js makeOdo）
var _odo: Dictionary = {"cols": [], "str": "", "val": 0.0, "dir": 1.0, "flash": 0.0, "init": false, "old": "", "xf": 1.0, "now": 0.0}
## 金光裂纹 {t, lvl, pts, br}；空 = 没有
var _crack: Dictionary = {}
var _prev_night: float = -1.0
## 槽位名 → HudSlot（hud.tscn）
var _slots: Dictionary = {}
## 屏幕边框层（hud.tscn 的 FrameLayer）和它上次重画时的窗口大小、昼夜混合
var _frame_layer: Control = null
var _frame_vp: Vector2 = Vector2.ZERO
var _frame_mix: float = -1.0
## 当前的界面大小倍率（Settings.ui_scale，_apply_ui_scale 里同步）
var _ui_k: float = 1.0
## 当前画到哪个 CanvasItem 上（画某一层时是那一层，其余时候是自己）
var _cv: CanvasItem = null
## 层名 → 层（hud.tscn）；层名 → 上次重画时的依赖值
var _layers: Dictionary = {}
var _keys: Dictionary = {}
## 各层重画时认的昼夜混合（变化超过 0.003 才算变，同 FrameLayer）
var _mix_q: float = -1.0
## 里程表数字宽（字号 → 宽）
var _odo_dw: Dictionary = {}
## 柱上标记的缓存：_marks_fp（标记依赖的 sim 状态）变了、或满 1 秒才重算 _marks()
var _marks_cache: Array = []
var _marks_fp: Array = []
var _marks_at: float = -1e9
## 英文钟点框的宽（_dial_shard_w 按语言缓存）
var _dial_w: float = 156.0
var _dial_w_loc: String = ""
## 钟点（按晷针的 tod 档位缓存 Tod.clock_of）
var _clk_tod: float = NAN
var _clk: Dictionary = {}
## 里程表单字宽（字号 → {字 → 宽}）
var _odo_cw: Dictionary = {}
## 月相的两块多边形（按圆心、半径、相位缓存）
var _moon_key: Array = []
var _moon: Dictionary = {}

const SCENE: String = "res://present/hud/hud.tscn"
const SLOTS: PackedStringArray = ["Dial", "Top", "Column", "Combo", "Hint", "Toasts", "Banner", "SchoolLines", "BoonRow", "Wheel"]
## 画在自己之前（show_behind_parent）/ 之后的层，按绘制顺序；外部 draw_hud 夹在两组中间
const BEHIND: Array[StringName] = [&"StaticLayer", &"DialLayer", &"NeedleLayer", &"DialFxLayer", &"TopLayer", &"TopSubLayer", &"TopAltLayer", &"TopStoneLayer", &"TopMoiraLayer",
	&"RecordLayer", &"ColumnLayer", &"PointerLayer", &"ComboLayer"]
const FRONT: Array[StringName] = [&"HintLayer", &"ToastLayer", &"BannerLayer", &"FlashLayer"]
const LAYER_PROF: Dictionary = {&"StaticLayer": &"hud.static", &"DialLayer": &"hud.dial", &"NeedleLayer": &"hud.dial", &"DialFxLayer": &"hud.dial",
	&"TopLayer": &"hud.top", &"TopSubLayer": &"hud.top", &"TopAltLayer": &"hud.top", &"TopStoneLayer": &"hud.top", &"TopMoiraLayer": &"hud.top",
	&"RecordLayer": &"hud.column", &"ColumnLayer": &"hud.column", &"PointerLayer": &"hud.column", &"ComboLayer": &"hud.combo",
	&"HintLayer": &"hud.rest", &"ToastLayer": &"hud.rest", &"BannerLayer": &"hud.rest", &"FlashLayer": &"hud.rest"}


static func create() -> HudView:
	return (load(SCENE) as PackedScene).instantiate() as HudView


## 每一块的默认位置（视口 vp 下）。hud.tscn 里各槽位的锚点和偏移就是照这个摆的：没动过的槽位变换是单位矩阵。
static func default_slot(slot: StringName, vp: Vector2) -> Rect2:
	match slot:
		&"Dial":
			return Rect2(16, 16, 240, 100)
		&"Top":
			var bw: float = minf(640.0, vp.x - 360.0)
			var bx: float = clampf(vp.x / 2.0 - bw / 2.0, 252.0, vp.x - 100.0 - bw)
			return Rect2(bx, FR + 8.0, bw, 62.0)
		&"Column":
			return Rect2(vp.x - 124.0, 34.0, 110.0, vp.y - 76.0)
		&"Combo":
			return Rect2(vp.x / 2.0 - 130.0, 64.0, 260.0, 180.0)
		&"Hint":
			return Rect2(vp.x / 2.0 - 420.0, vp.y - 56.0, 840.0, 28.0)
		&"Toasts":
			return Rect2(vp.x / 2.0 - 400.0, vp.y * 0.3 - 22.0, 800.0, 120.0)
		&"Banner":
			return Rect2(vp.x / 2.0 - 380.0, vp.y * 0.3 - 80.0, 760.0, 160.0)
		&"SchoolLines":
			return Rect2(vp.x / 2.0 - 300.0, 222.0, 600.0, 70.0)
		&"BoonRow":
			return Rect2(16.0, vp.y - 140.0, 560.0, 110.0)
		&"Wheel":
			return Rect2(vp.x / 2.0 - 160.0, vp.y * 0.42 - 100.0, 320.0, 200.0)
	return Rect2()


## 槽位的变换：把默认位置映射到槽位当前的位置和大小
func slot_xf(slot: StringName) -> Transform2D:
	var s: Control = _slots.get(slot)
	if s == null:
		return Transform2D.IDENTITY
	var d: Rect2 = default_slot(slot, size)
	var r: Rect2 = s.get_rect()
	if d.size.x <= 0.0 or d.size.y <= 0.0:
		return Transform2D.IDENTITY
	var k: Vector2 = Vector2(r.size.x / d.size.x, r.size.y / d.size.y)
	return Transform2D(0.0, k, 0.0, r.position - d.position * k)


## 开始画某一块：槽位隐藏时返回 false（不画）；否则套上槽位变换。画完调 end_slot()
func begin_slot(slot: StringName) -> bool:
	if not _vis(slot):
		return false
	_cv.draw_set_transform_matrix(slot_xf(slot))
	return true


func end_slot() -> void:
	_cv.draw_set_transform_matrix(Transform2D.IDENTITY)


func _vis(slot: StringName) -> bool:
	var s: Control = _slots.get(slot)
	return s == null or s.visible


## 金币飞向的目标（套上 Top 槽位的变换）
func money_target() -> Vector2:
	return slot_xf(&"Top") * money_anchor(size) * _ui_k


## 屏幕坐标（主视口的逻辑坐标，wv.to_screen 给的就是这个）→ HUD 自己的坐标。
## HUD 层整个按界面大小缩放过（_apply_ui_scale），跟随世界的东西直接拿屏幕坐标画在 HUD 上会跟着缩放跑偏，要先换回来
func screen_to_hud(s: Vector2) -> Vector2:
	if not is_inside_tree():
		return s / _ui_k
	return get_global_transform_with_canvas().affine_inverse() * s


func _init() -> void:
	_cv = self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_layer = get_node_or_null("FrameLayer") as Control
	if _frame_layer != null:
		_frame_layer.draw.connect(_on_frame_draw)
	for n: String in SLOTS:
		var s: Control = get_node_or_null(n) as Control
		if s != null:
			_slots[StringName(n)] = s
	for n: StringName in BEHIND + FRONT:
		var l: Control = get_node_or_null(String(n)) as Control
		if l != null:
			_layers[n] = l
			l.draw.connect(_on_layer_draw.bind(n))


func _on_layer_draw(n: StringName) -> void:
	var _pt: int = Prof.t()
	_cv = _layers[n]
	_paint(n)
	_cv = self
	Prof.add(LAYER_PROF[n], _pt)


## 画一层的内容（画到 _cv 上）
func _paint(n: StringName) -> void:
	if sim == null or sim.world == null:
		return
	var vp: Vector2 = size
	match n:
		&"StaticLayer":
			if begin_slot(&"Dial"):
				_draw_dial_base()
			if begin_slot(&"Top"):
				_draw_top_base(vp)
			if begin_slot(&"Column"):
				_draw_column_base(vp)
		&"DialLayer":
			if begin_slot(&"Dial"):
				_draw_dial()
		&"NeedleLayer":
			if begin_slot(&"Dial"):
				_draw_needle()
		&"DialFxLayer":
			if begin_slot(&"Dial"):
				_draw_dial_fx()
		&"TopLayer":
			if begin_slot(&"Top"):
				_draw_top(vp)
		&"TopSubLayer":
			if begin_slot(&"Top"):
				_draw_top_sub(vp)
		&"TopAltLayer":
			if begin_slot(&"Top"):
				_draw_top_alt(vp)
		&"TopStoneLayer":
			if begin_slot(&"Top"):
				_draw_top_stone(vp)
		&"TopMoiraLayer":
			if begin_slot(&"Top"):
				_draw_top_moira(vp)
		&"RecordLayer":
			if begin_slot(&"Column"):
				_draw_column_record(vp)
		&"ColumnLayer":
			if begin_slot(&"Column"):
				_draw_column_marks(vp)
		&"PointerLayer":
			if begin_slot(&"Column"):
				_draw_column_pointer(vp)
		&"ComboLayer":
			if sim.phase == &"night" and begin_slot(&"Combo"):
				_draw_combo(vp)
		&"HintLayer":
			if begin_slot(&"Hint"):
				_draw_hint(vp)
		&"ToastLayer":
			if begin_slot(&"Toasts"):
				_draw_toasts(vp)
		&"BannerLayer":
			if begin_slot(&"Banner"):
				_draw_banner(vp)
		&"FlashLayer":
			_draw_flash(vp)
	end_slot()


## 依赖值变了才重画这一层
func _want(n: StringName, key: Array) -> void:
	var l: CanvasItem = _layers.get(n)
	if l != null and key != _keys.get(n):
		_keys[n] = key.duplicate(true)
		l.queue_redraw()


## 每帧：算出各层依赖的数值，和上次重画时比
func _sync_layers() -> void:
	if _layers.is_empty():
		return
	if absf(mix - _mix_q) > 0.003:
		_mix_q = mix
	var vp: Vector2 = size
	var ok: bool = sim.world != null
	var night: bool = mix > 0.5
	var base: Array = [ok, vp, _mix_q, night]
	_want(&"StaticLayer", base + [_vis(&"Dial"), _vis(&"Top"), _vis(&"Column"), ok and _moira_shown()])
	if not ok:
		for n: StringName in BEHIND + FRONT:
			if n != &"StaticLayer":
				_want(n, base)
		return
	# 日晷：字（日数、钟点；傍晚钟点闪烁时每帧画）、晷针（角度按 0.0001 天取档，针尖挪不到 0.02 像素）
	var tod: float = sim.tod()
	var tq: float = snappedf(tod, 0.0001)
	var clk: Dictionary = _clock(tod)
	var dk: Array = base + [_vis(&"Dial"), sim.day, sim.phase, sim.exhausted > 0 and not sim.stats.no_stamina, String(clk["label"]), String(clk["text"])]
	if sim.phase == &"day" and tod > 0.85 and tod <= 1.0:
		dk.append(t)
	_want(&"DialLayer", dk)
	# 夜里星星闪烁、白天正午金点呼吸时每帧画；月相按日数
	_want(&"NeedleLayer", base + [_vis(&"Dial"), t if night else tq])
	_want(&"DialFxLayer", base + [_vis(&"Dial"), sim.day, t if not night and sim.story.noon_mark() else -1.0])
	# 顶部陶片：金钱数字（里程表滚动、闪光、裂纹时每帧画）、下面的小字、海拔、石重（升级闪光时每帧画）、命运（刚加过时每帧画）
	var at_night: bool = mix > 0.5 and sim.night_total_valid
	var h: float = _col_h()
	var rolling: bool = _odo_rolling()
	_want(&"TopLayer", base + [_vis(&"Top"), t if rolling or float(_odo["flash"]) > 0.0 or not _crack.is_empty() else String(_odo["str"])])
	_want(&"TopSubLayer", base + [_vis(&"Top"), at_night, sim.money if at_night else 0.0, rolling, t if not _crack.is_empty() else -1.0])
	_want(&"TopAltLayer", base + [_vis(&"Top"), at_night, int(h), int(sim.record)])
	_want(&"TopStoneLayer", base + [_vis(&"Top"), sim.stone.r, t if sim.tier_flash > 0.0 else -1.0])
	var shown: bool = _moira_shown()
	_want(&"TopMoiraLayer", base + [_vis(&"Top"), shown, sim.moira if shown else 0.0, t if shown and moira_pop > 0.0 else -1.0])
	# 海拔柱：纪录一层、标记 / 名字 / 赌注一层、指针和小人一层
	var y0: float = FR + 50.0
	var y1: float = vp.y - FR - 58.0
	var yh: float = _col_y(h, y0, y1)
	_want(&"RecordLayer", base + [_vis(&"Column"), sim.record])
	var marks: Array = _marks_cached()
	var nxt: Dictionary = _next_mark(marks, h)
	var ck: Array = base + [_vis(&"Column"), marks, nxt.get("alt", -1.0)]
	if not nxt.is_empty() and String(nxt.get("label", "")) != "":
		ck.append(_label_y(nxt, yh, y0, y1))
	var bt: Dictionary = sim.bet
	if _bet_on():
		ck.append_array([float(bt["h"]), float(bt.get("odds", 0.0))])
	_want(&"ColumnLayer", ck)
	_want(&"PointerLayer", base + [_vis(&"Column"), yh])
	# 连碾
	var mk: Array = base + [_vis(&"Combo")]
	if sim.phase == &"night" and sim.combo >= 2:
		mk.append_array([sim.combo, sim.combo_pulse, sim.stats.combo_cap, sim.stats.combo_step])
	_want(&"ComboLayer", mk)
	# 底部提示（文字依赖的输入变了才重画）、飘字 / 横幅 / 白闪（有的时候每帧画）
	_want(&"HintLayer", base + [_vis(&"Hint")] + _hint_inputs())
	_want(&"ToastLayer", base + [_vis(&"Toasts"), t if not toasts.is_empty() else -1.0])
	_want(&"BannerLayer", base + [_vis(&"Banner"), t if not banner.is_empty() else -1.0])
	_want(&"FlashLayer", base + [t if flash_a > 0.003 else -1.0])


## 屏幕边框层的重画（缓存：几百格回纹每帧重画要 2 毫秒多，2026-10-15 实测）
func _on_frame_draw() -> void:
	var _pt: int = Prof.t()
	_draw_frame(_frame_layer, _frame_layer.size)
	Prof.add(&"hud.frame", _pt)


func _sync_frame_layer() -> void:
	if _frame_layer != null and (size != _frame_vp or absf(mix - _frame_mix) > 0.003):
		_frame_vp = size
		_frame_mix = mix
		_frame_layer.queue_redraw()


## 金币飞向的 HUD 目标点（德拉克马图标中心）
static func money_anchor(vp: Vector2) -> Vector2:
	var bw: float = minf(640.0, vp.x - 360.0)
	var bx: float = clampf(vp.x / 2.0 - bw / 2.0, 252.0, vp.x - 100.0 - bw)
	return Vector2(bx + 30.0, FR + 8.0 + 29.0)


func on_events(list: Array[SimEvent]) -> void:
	for e: SimEvent in list:
		match e.kind:
			&"banner":
				banner = {"text": e.text, "sub": e.sub, "life": e.a, "t": 0.0, "y": e.b, "size": e.c}
			&"flash":
				flash_a = maxf(flash_a, e.a * Settings.flash_strength)
				flash_col = e.color
				flash_at = Vector2(e.x, e.y)
			&"moira":
				moira_pop = 1.0
			&"toast":
				toasts.append({"text": String(e.data.get("text", "")), "t": 0.0, "life": float(e.data.get("life", 3.2)), "color": e.data.get("color", Color("f1e3c8"))})
			&"phase":
				if e.data.get("phase", &"") == &"day":
					banner = {}


## 界面大小（设置 → 画面）：整个 HUD 层按比例缩放，HUD 自己的尺寸 = 屏幕 / 比例，槽位照常按锚点排
func _apply_ui_scale() -> void:
	var layer: CanvasLayer = get_parent() as CanvasLayer
	if layer == null:
		return
	var k: float = clampf(Settings.ui_scale, 0.8, 1.3)
	var want: Vector2 = get_viewport_rect().size / k
	if k == _ui_k and size.is_equal_approx(want):
		return
	_ui_k = k
	layer.scale = Vector2(k, k)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = want


func _process(dt: float) -> void:
	var _pt: int = Prof.t()
	_process_impl(dt)
	Prof.add(&"hud.process", _pt)


func _process_impl(dt: float) -> void:
	_apply_ui_scale()
	if sim == null:
		return
	t += dt
	moira_pop = maxf(0.0, moira_pop - dt * 1.2)
	var target: float = 0.0 if sim.phase == &"day" else (1.0 if sim.night_k() > 0.5 else 0.0)
	mix += (target - mix) * minf(1.0, dt * 4.0)
	_sync_frame_layer()
	var m: float = sim.money
	if absf(m - display_money) > 0.5:
		display_money += (m - display_money) * (1.0 - exp(-8.0 * dt))
	else:
		display_money = m
	var coll: float = fxv.collected if fxv != null else 0.0
	display_night += (coll - display_night) * (1.0 - exp(-6.0 * dt))
	var at_night: bool = mix > 0.5 and sim.night_total_valid
	var big_val: float = display_night if at_night else display_money
	_odo_set(("+" if at_night else "") + NumFmt.fmt(big_val), big_val, dt)
	if at_night:
		var prev: float = maxf(0.0, _prev_night)
		for th: Array in [[1, 1e3], [2, 1e4], [3, 1e5]]:
			if prev < float(th[1]) and display_night >= float(th[1]):
				_make_crack(int(th[0]))
		_prev_night = display_night
	else:
		_prev_night = -1.0
	if not _crack.is_empty():
		_crack["t"] = float(_crack["t"]) + dt
		if float(_crack["t"]) > 1.2:
			_crack = {}
	if not banner.is_empty():
		banner["t"] = float(banner["t"]) + dt
		if float(banner["t"]) > float(banner["life"]):
			banner = {}
	flash_a = maxf(0.0, flash_a - dt * 2.2)
	for i: int in range(toasts.size() - 1, -1, -1):
		toasts[i]["t"] = float(toasts[i]["t"]) + dt
		if float(toasts[i]["t"]) > float(toasts[i]["life"]):
			toasts.remove_at(i)
	_sync_layers()
	queue_redraw()


func _c(key: String) -> Color:
	return Palette.hud(key, mix)


func _text(s: String, pos: Vector2, size: int, col: Color, font: Font = null, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, outline: int = 0) -> void:
	var f: Font = font if font != null else Fonts.serif(600)
	var p: Vector2 = pos
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		var tw: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		p.x -= tw if align == HORIZONTAL_ALIGNMENT_RIGHT else tw / 2.0
	if outline > 0:
		_cv.draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, outline, Color(0, 0, 0, 0.8 * col.a))
	_cv.draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, col)


## 一行小字放不下 max_w 就逐级缩字号（最小 9）：英文的「Best 1000 · Summit 1000」「weight 252.0K talents」原来会冲出框（2026-11-25）
func _text_fit(s: String, pos: Vector2, size: int, col: Color, max_w: float, font: Font = null) -> void:
	var f: Font = font if font != null else Fonts.serif(600)
	var fs: int = size
	while fs > 9 and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 1
	_text(s, pos, fs, col, font)


## 给外部画面（SchoolView 等）用的描边文字
func text_at(s: String, pos: Vector2, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	_text(s, pos, size, col, Fonts.serif(700), align, -1.0, 4)


## 陶片（釉面块 + 米色描边 + 下沿点饰）
func _shard(r: Rect2) -> void:
	var pts: PackedVector2Array = [r.position + Vector2(9, 0), r.position + Vector2(r.size.x - 6, 0), r.position + Vector2(r.size.x, 9),
		r.position + Vector2(r.size.x - 1, r.size.y - 10), r.position + Vector2(r.size.x - 10, r.size.y), r.position + Vector2(7, r.size.y),
		r.position + Vector2(0, r.size.y - 7), r.position + Vector2(1, 8)]
	var off: PackedVector2Array = []
	for p: Vector2 in pts:
		off.append(p + Vector2(1.5, 3))
	_cv.draw_colored_polygon(off, _c("core"))
	var cols: PackedColorArray = []
	for p: Vector2 in pts:
		cols.append(_c("glaze_top").lerp(_c("glaze_bot"), clampf((p.y - r.position.y) / r.size.y * 1.6, 0.0, 1.0)))
	_cv.draw_polygon(pts, cols)
	pts.append(pts[0])
	_cv.draw_polyline(pts, _c("edge"), 1.3, true)
	_cv.draw_line(r.position + Vector2(12, 6.5), r.position + Vector2(r.size.x - 12, 6.5), _c("line_dim"), 1.0)
	var x: float = r.position.x + 14.0
	while x < r.position.x + r.size.x - 12.0:
		_cv.draw_rect(Rect2(x, r.position.y + r.size.y - 7.0, 1.6, 1.6), _c("line_dim"))
		x += 9.0


func _draw() -> void:
	var _pt: int = Prof.t()
	_draw_impl()
	Prof.add(&"hud.draw", _pt)


func _draw_impl() -> void:
	if sim == null or sim.world == null:
		return
	var vp: Vector2 = size
	# 屏幕边框画在单独的 FrameLayer 上（hud.tscn，show_behind_parent），只在窗口大小或昼夜颜色变了才重画；没有这层时照旧每帧画
	if _frame_layer == null:
		_draw_frame(self, vp)
	# 各块在 hud.tscn 的层上按需重画；缺哪层就照旧每帧画在自己身上
	for n: StringName in BEHIND:
		if not _layers.has(n):
			_paint(n)
	var _pt: int = Prof.t()
	if boons != null:
		boons.draw_hud(self, sim, vp)
	if story_view != null:
		story_view.draw_hud(self, sim, vp, wv)
	Prof.add(&"hud.boons_story", _pt)
	_pt = Prof.t()
	if chest_view != null and (sim.phase == &"night" or sim.phase == &"night_end") and begin_slot(&"Wheel"):
		chest_view.draw_hud(self, sim, vp)
	end_slot()
	Prof.add(&"hud.chest", _pt)
	for n: StringName in FRONT:
		if not _layers.has(n):
			_paint(n)


## 白闪（盖在整个 HUD 最上面）
func _draw_flash(vp: Vector2) -> void:
	if flash_a > 0.003:
		if not is_nan(flash_at.x) and wv != null:
			var s: Vector2 = screen_to_hud(wv.to_screen(flash_at.x, flash_at.y))
			Glow.draw(_cv, s, vp.y * 0.7, Color(flash_col, flash_a))
		else:
			_cv.draw_rect(Rect2(Vector2.ZERO, vp), Color(flash_col, flash_a))


## 屏幕边框：暗角 + 四边回纹带（回纹朝内）+ 外缘黑线 + 内侧双刻线 + 四角八瓣玫瑰（= render.js drawFrameInner）
func _draw_frame(cv: CanvasItem, vp: Vector2) -> void:
	var night_k: float = mix
	var frame_c: Color = Palette.world("frame", night_k)
	var frame_line: Color = Palette.world("frame_line", night_k)
	# 暗角：四边各一条从边缘到内侧平滑淡出的渐变带（顶点色插值，不会出现一格一格的色阶）
	var vig: Color = Color(0.1, 0.07, 0.055, 0.3).lerp(Color(0, 0, 0.04, 0.45), night_k)
	var d: float = minf(vp.x, vp.y) * 0.21
	var c0: Color = Color(vig, vig.a)
	var c1: Color = Color(vig, 0.0)
	var mid: Color = Color(vig, vig.a * 0.32)
	for band: Array in [[Vector2(0, 0), Vector2(vp.x, 0), Vector2(vp.x, d), Vector2(0, d)],
			[Vector2(0, vp.y), Vector2(vp.x, vp.y), Vector2(vp.x, vp.y - d), Vector2(0, vp.y - d)],
			[Vector2(0, 0), Vector2(0, vp.y), Vector2(d, vp.y), Vector2(d, 0)],
			[Vector2(vp.x, 0), Vector2(vp.x, vp.y), Vector2(vp.x - d, vp.y), Vector2(vp.x - d, 0)]]:
		# 每条带分两段（边缘 → 1/3 处 → 内侧），淡出更接近平方曲线，比一段线性更柔
		var a0: Vector2 = band[0]
		var a1: Vector2 = band[1]
		var b1: Vector2 = band[2]
		var b0: Vector2 = band[3]
		var m0: Vector2 = a0.lerp(b0, 0.33)
		var m1: Vector2 = a1.lerp(b1, 0.33)
		cv.draw_polygon(PackedVector2Array([a0, a1, m1, m0]), PackedColorArray([c0, c0, mid, mid]))
		cv.draw_polygon(PackedVector2Array([m0, m1, b1, b0]), PackedColorArray([mid, mid, c1, c1]))
	cv.draw_rect(Rect2(0, 0, vp.x, FR), frame_c)
	cv.draw_rect(Rect2(0, vp.y - FR, vp.x, FR), frame_c)
	cv.draw_rect(Rect2(0, 0, FR, vp.y), frame_c)
	cv.draw_rect(Rect2(vp.x - FR, 0, FR, vp.y), frame_c)
	# 回纹：所有格子的粗线段攒成一批三角形，一次画完（逐格 draw_polyline 一屏要 900 多次绘制调用，2026-10-15 实测）
	var u: float = FR / 14.0
	var tri: PackedVector2Array = []
	var x: float = 0.0
	while x < vp.x:
		_meander(tri, Vector2(x, 0.0), u, false)
		_meander(tri, Vector2(x, vp.y), u, true)
		x += FR
	var y: float = 0.0
	while y < vp.y:
		_meander_v(tri, Vector2(0.0, y), u, false)
		_meander_v(tri, Vector2(vp.x, y), u, true)
		y += FR
	var cols: PackedColorArray = []
	cols.resize(tri.size())
	cols.fill(frame_line)
	RenderingServer.canvas_item_add_triangle_array(cv.get_canvas_item(), PackedInt32Array(), tri, cols)
	cv.draw_rect(Rect2(1, 1, vp.x - 2, vp.y - 2), frame_c, false, 2.0)
	cv.draw_rect(Rect2(FR + 0.75, FR + 0.75, vp.x - 2.0 * FR - 1.5, vp.y - 2.0 * FR - 1.5), _c("line"), false, 1.5)
	cv.draw_rect(Rect2(FR + 4.5, FR + 4.5, vp.x - 2.0 * FR - 9.0, vp.y - 2.0 * FR - 9.0), _c("line_dim"), false, 1.0)
	for oc: Vector2 in [Vector2(0, 0), Vector2(vp.x - 32.0, 0), Vector2(0, vp.y - 32.0), Vector2(vp.x - 32.0, vp.y - 32.0)]:
		_corner(cv, oc, frame_c)


const MEANDER: PackedVector2Array = [Vector2(1.5, 12), Vector2(1.5, 2), Vector2(11.5, 2), Vector2(11.5, 9), Vector2(5.5, 9), Vector2(5.5, 5.5), Vector2(8.5, 5.5)]


## 一格回纹（横带）攒进三角形批次：flip = 底边（上下翻转）
static func _meander(tri: PackedVector2Array, o: Vector2, u: float, flip: bool) -> void:
	var sy: float = -1.0 if flip else 1.0
	var out: PackedVector2Array = []
	for q: Vector2 in MEANDER:
		out.append(o + Vector2(q.x * u, q.y * u * sy))
	_thick_polyline(tri, out, 1.7 * u)
	_thick_polyline(tri, PackedVector2Array([o + Vector2(0, 12.0 * u * sy), o + Vector2(14.0 * u, 12.0 * u * sy)]), 1.7 * u)


## 一格回纹（竖带）攒进三角形批次：flip = 右边
static func _meander_v(tri: PackedVector2Array, o: Vector2, u: float, flip: bool) -> void:
	var sx: float = -1.0 if flip else 1.0
	var out: PackedVector2Array = []
	for q: Vector2 in MEANDER:
		out.append(o + Vector2(q.y * u * sx, q.x * u))
	_thick_polyline(tri, out, 1.7 * u)
	_thick_polyline(tri, PackedVector2Array([o + Vector2(12.0 * u * sx, 0), o + Vector2(12.0 * u * sx, 14.0 * u)]), 1.7 * u)


## 粗折线拆成一段段矩形（每段两个三角形）；中间的拐点两边各伸出半个线宽，直角拐弯处补齐成方角（线是不透明色，重叠不显）
static func _thick_polyline(tri: PackedVector2Array, pts: PackedVector2Array, w: float) -> void:
	var hw: float = w * 0.5
	var last: int = pts.size() - 1
	for i: int in last:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var d: Vector2 = (b - a).normalized()
		if i > 0:
			a -= d * hw
		if i < last - 1:
			b += d * hw
		var n: Vector2 = Vector2(-d.y, d.x) * hw
		tri.append_array([a + n, b + n, b - n, a + n, b - n, a - n])


## 四角：32px 方块 + 双框 + 八瓣玫瑰
func _corner(cv: CanvasItem, o: Vector2, frame_c: Color) -> void:
	var S: float = 32.0
	cv.draw_rect(Rect2(o, Vector2(S, S)), frame_c)
	cv.draw_rect(Rect2(o + Vector2(1.6, 1.6), Vector2(S - 3.2, S - 3.2)), _c("line"), false, 1.2)
	cv.draw_rect(Rect2(o + Vector2(4.5, 4.5), Vector2(S - 9.0, S - 9.0)), _c("edge"), false, 1.0)
	var c: Vector2 = o + Vector2(S / 2.0, S / 2.0)
	for i: int in 8:
		var a: float = i / 8.0 * TAU
		var pts: PackedVector2Array = []
		for k: int in 13:
			var th: float = k / 12.0 * TAU
			pts.append(c + Vector2(6.4 + cos(th) * 4.4, sin(th) * 2.1).rotated(a))
		cv.draw_colored_polygon(pts, _c("edge") if i % 2 == 1 else _c("line"))
	cv.draw_circle(c, 2.8, frame_c)
	cv.draw_circle(c, 1.5, _c("line"))


## 左上：日晷（ui_sundial 只当底盘；盘面 06–18 刻度、12 点金色刻点、晷针影子）/ 夜里月相盘；旁边一块陶片写"第 N 日 + 钟点"
## 分四层画：底盘（StaticLayer）→ 字（DialLayer）→ 晷针 / 星星（NeedleLayer）→ 正午金点 / 月相（DialFxLayer）
func _dial_rect() -> Rect2:
	var P: float = FR + 10.0
	return Rect2(P - 8.0, FR + 2.0, 110.0, 110.0 / 1.1325)


func _dial_shard_rect() -> Rect2:
	var P: float = FR + 10.0
	return Rect2(P + 76.0, FR + 12.0, _dial_shard_w(), 62.0)


## 钟点框的宽：中文固定 156；英文的时段名长（Afternoon 08:20 要 173），按最长的标签加钟点算，免得钟点压到框线（2026-11-25）
func _dial_shard_w() -> float:
	if not Loc.is_en():
		return 156.0
	if _dial_w_loc != Loc.locale():
		_dial_w_loc = Loc.locale()
		var lw: float = Fonts.serif(600).get_string_size(_breath_label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		for tod: float in [0.0, 0.5, 0.7, 0.95, 1.2]:
			lw = maxf(lw, Fonts.serif(600).get_string_size(String(Tod.clock_of(tod)["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
		var tw: float = Fonts.cinzel(700).get_string_size("00:00", HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_dial_w = maxf(156.0, ceilf(44.0 + lw + 6.0 + tw + 12.0))
	return _dial_w


## 体力耗尽时钟点前的标签
func _breath_label() -> String:
	return Loc.t("hud_view.catch_breath", "喘口气…")


## 日晷底盘 / 月相盘的盘子（只随窗口和昼夜变）
func _draw_dial_base() -> void:
	var d: Rect2 = _dial_rect()
	_shard(_dial_shard_rect())
	var night: bool = mix > 0.5
	if not night:
		var fx: float = d.position.x + d.size.x * 132.0 / 265.0
		var fy: float = d.position.y + d.size.y * 117.0 / 234.0
		var rx: float = d.size.x * 112.0 / 265.0
		var ry: float = d.size.y * 80.0 / 234.0
		var base: Texture2D = SpriteDB.tex(&"ui_sundial")
		if base != null:
			# 只取盘心以下的侧壁（素材里画好的晷针尖被盘面盖住）
			var k0: float = 117.0 / 234.0
			_cv.draw_texture_rect_region(base, Rect2(d.position.x, fy, d.size.x, d.end.y - fy),
				Rect2(0, base.get_height() * k0, base.get_width(), base.get_height() * (1.0 - k0)))
		var sc: Vector2 = Vector2(1.0, ry / rx)
		var ctr: Vector2 = Vector2(fx, fy)
		_cv.draw_colored_polygon(_ellipse(ctr, rx * 1.1, ry * 1.12, 0.0, TAU), Color("4a3622"))
		_cv.draw_colored_polygon(_ellipse(ctr, rx * 0.97, ry * 0.97, 0.0, TAU), Color("5a4430"))
		_cv.draw_colored_polygon(_sector_e(ctr, rx * 0.94, sc, PI, PI * 1.5), Color("7d6143"))
		_cv.draw_colored_polygon(_sector_e(ctr, rx * 0.94, sc, PI * 1.5, TAU), Color("c6a676"))
		var rim: PackedVector2Array = _ellipse(ctr, rx * 0.97, ry * 0.97, 0.0, TAU)
		rim.append(rim[0])
		_cv.draw_polyline(rim, Color("120c0a"), 1.3, true)
		for h: int in range(6, 19):
			var a: float = PI + PI * (h - 6) / 12.0
			var big: bool = h % 3 == 0
			var dir: Vector2 = Vector2(cos(a), sin(a)) * sc
			_cv.draw_line(ctr + dir * rx * (0.68 if big else 0.78), ctr + dir * rx * 0.92, Color("e9d3a8") if h < 12 else Color("120c0a"), 2.0 if big else 1.1, true)
	else:
		# 月相盘：深蓝圆盘 + 点饰外圈（星星和月相在 DialFxLayer）
		var c2: Vector2 = Vector2(d.position.x + d.size.x * 0.5, d.position.y + d.size.y * 0.52)
		var r: float = 36.0
		_cv.draw_circle(c2, r + 4.0, Color("081129"))
		_cv.draw_arc(c2, r + 4.0, 0.0, TAU, 48, _c("line"), 1.4, true)
		_cv.draw_arc(c2, r - 2.0, 0.0, TAU, 48, _c("line_dim"), 1.0, true)
		for i: int in 16:
			var aa: float = i / 16.0 * TAU
			_cv.draw_rect(Rect2(c2 + Vector2(cos(aa), sin(aa)) * (r + 1.0) - Vector2(0.9, 0.9), Vector2(1.8, 1.8)), _c("line"))


## 白天：晷针影子；夜里：几颗闪烁的星（NeedleLayer）
func _draw_needle() -> void:
	var d: Rect2 = _dial_rect()
	if mix > 0.5:
		var c2: Vector2 = Vector2(d.position.x + d.size.x * 0.5, d.position.y + d.size.y * 0.52)
		var r: float = 36.0
		for i: int in 5:
			var aa2: float = i * 1.7 + 0.4
			var rr: float = r * (0.45 + (i % 3) * 0.14)
			_cv.draw_rect(Rect2(c2 + Vector2(cos(aa2), sin(aa2)) * rr, Vector2(1.6, 1.6)), Color(223.0 / 255.0, 232.0 / 255.0, 245.0 / 255.0, 0.7 * (0.45 + 0.35 * sin(t * 1.6 + i * 2.0))))
		return
	var tod: float = sim.tod()
	var fx: float = d.position.x + d.size.x * 132.0 / 265.0
	var fy: float = d.position.y + d.size.y * 117.0 / 234.0
	var rx: float = d.size.x * 112.0 / 265.0
	var ry: float = d.size.y * 80.0 / 234.0
	var sc: Vector2 = Vector2(1.0, ry / rx)
	var ctr: Vector2 = Vector2(fx, fy)
	var ap: float = PI + PI * clampf(tod, 0.0, 1.0)
	var tip: Vector2 = ctr + Vector2(cos(ap), sin(ap)) * sc * rx * 0.86
	_cv.draw_line(ctr, tip, Color(241.0 / 255.0, 227.0 / 255.0, 200.0 / 255.0, 0.55), 5.2, true)
	_cv.draw_line(ctr, tip, Color("120c0a"), 3.0, true)
	_cv.draw_circle(ctr, 3.0, Color("120c0a"))


## 第 N 日 + 希腊数字 + 钟点（DialLayer）
func _draw_dial() -> void:
	var ds: Rect2 = _dial_shard_rect()
	var tod: float = sim.tod()
	var tx: float = ds.position.x + 44.0
	var day_txt: String = Loc.t("hud_view.day", "第 %d 日") % sim.day
	_text(day_txt, Vector2(tx, ds.position.y + 26.0), 20, _c("cream"), Fonts.serif(700))
	var dtw: float = Fonts.serif(700).get_string_size(day_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	if tx + dtw + 6.0 < ds.end.x - 22.0:
		_text(NumFmt.greek_num(sim.day), Vector2(tx + dtw + 6.0, ds.position.y + 26.0), 11, _c("edge"), Fonts.greek())
	var clk: Dictionary = _clock(tod)
	var late: bool = sim.phase == &"day" and tod > 0.85 and tod <= 1.0
	var la: float = (0.6 + 0.4 * absf(sin(t * 3.2))) if late else 1.0
	var col: Color = Color("b0705a", la) if late else _c("cream")
	var lab: String = String(clk["label"])
	if sim.phase == &"day" and sim.exhausted > 0 and not sim.stats.no_stamina:
		lab = _breath_label()
	_text(lab, Vector2(tx, ds.position.y + 49.0), 14, col if late else _c("dim"), Fonts.serif(600))
	var lw: float = Fonts.serif(600).get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_text(String(clk["text"]), Vector2(tx + lw + 6.0, ds.position.y + 50.0), 18, col, Fonts.cinzel(700))


## 白天：正午金点（普罗米修斯还没见时呼吸闪光）；夜里：按日数变化的月相（盖在星星上）（DialFxLayer）
func _draw_dial_fx() -> void:
	var d: Rect2 = _dial_rect()
	if mix <= 0.5:
		var fx: float = d.position.x + d.size.x * 132.0 / 265.0
		var fy: float = d.position.y + d.size.y * 117.0 / 234.0
		var ry: float = d.size.y * 80.0 / 234.0
		var noon: Vector2 = Vector2(fx, fy - ry * 0.85)
		if sim.story.noon_mark():
			var br: float = 0.5 + 0.5 * sin(t * 4.0)
			Glow.draw(_cv, noon, 16.0, Color(GOLD_HI, 0.35 + 0.35 * br))
			var pm: Texture2D = SpriteDB.tex(&"god_prometheus")
			if pm != null:
				var pc: Vector2 = Vector2(noon.x + 20.0, d.position.y + 8.0)
				_cv.draw_circle(pc, 11.0, Color("120c0a"))
				_cv.draw_texture_rect(pm, Rect2(pc - Vector2(10, 10), Vector2(20, 20)), false)
				_cv.draw_arc(pc, 11.0, 0.0, TAU, 24, GOLD, 1.2, true)
		_cv.draw_circle(noon, 3.4, GOLD)
		_cv.draw_arc(noon, 3.4, 0.0, TAU, 12, Color("120c0a"), 1.0, true)
	else:
		var c2: Vector2 = Vector2(d.position.x + d.size.x * 0.5, d.position.y + d.size.y * 0.52)
		var r: float = 36.0
		_moon_phase(c2, r * 0.52, float((sim.day + 1) % 8) / 8.0, Color("dfe8f5"), Color("0b1636"))


## 椭圆上的点（a0 → a1）
func _ellipse(c: Vector2, rx: float, ry: float, a0: float, a1: float) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	var n: int = 48
	for i: int in n:
		var a: float = lerpf(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## 压扁的扇形（日晷盘面）
func _sector_e(c: Vector2, r: float, sc: Vector2, a0: float, a1: float) -> PackedVector2Array:
	var pts: PackedVector2Array = [c]
	for i: int in 25:
		var a: float = lerpf(a0, a1, i / 24.0)
		pts.append(c + Vector2(cos(a), sin(a)) * sc * r)
	return pts


## 月相（phase 0 新月 → 0.5 满月 → 1）：= render.js drawMoonPhase；两块多边形按圆心、半径、相位缓存
func _moon_phase(c: Vector2, r: float, phase: float, lit: Color, dark: Color) -> void:
	var mk: Array = [c, r, phase]
	if mk != _moon_key:
		_moon_key = mk
		var waxing: bool = phase < 0.5
		var half: PackedVector2Array = []
		for i: int in 25:
			var a: float = -PI / 2.0 + PI * i / 24.0
			half.append(c + Vector2(cos(a) * r * (1.0 if waxing else -1.0), sin(a) * r))
		var k: float = cos(phase * TAU)
		_moon = {"half": half, "k": k, "ell": _ellipse(c, absf(k) * r + 0.01, r, 0.0, TAU)}
	_cv.draw_circle(c, r, dark)
	_cv.draw_colored_polygon(_moon["half"] as PackedVector2Array, lit)
	_cv.draw_colored_polygon(_moon["ell"] as PackedVector2Array, dark if float(_moon["k"]) > 0.0 else lit)
	_cv.draw_arc(c, r, 0.0, TAU, 32, Color(223.0 / 255.0, 232.0 / 255.0, 245.0 / 255.0, 0.5), 1.0, true)


func _sector(c: Vector2, r: float, a0: float, a1: float) -> PackedVector2Array:
	var pts: PackedVector2Array = [c]
	var n: int = maxi(2, int(absf(a1 - a0) / 0.1))
	for i: int in n + 1:
		var a: float = lerpf(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## 顶部的陶片底子（StaticLayer）：三块 + 摇到命运后金钱下面那块
func _draw_top_base(vp: Vector2) -> void:
	var bw: float = minf(640.0, vp.x - 360.0)
	var bx: float = clampf(vp.x / 2.0 - bw / 2.0, 252.0, vp.x - 100.0 - bw)
	var by: float = FR + 8.0
	var bh: float = 62.0
	var x_a: float = bx + bw * 0.40
	var x_b: float = bx + bw * 0.67
	_shard(Rect2(bx, by, x_a - bx - 2.0, bh))
	_shard(Rect2(x_a + 2.0, by, x_b - x_a - 4.0, bh))
	_shard(Rect2(x_b + 2.0, by, bx + bw - x_b - 2.0, bh))
	if _moira_shown():
		_shard(Rect2(bx, by + bh + 4.0, 168.0, 30.0))


func _moira_shown() -> bool:
	return sim.moira > 0.0 or float(sim.run_stats.get("moira_total", 0.0)) > 0.0


## 顶部陶片的横向位置：[bx, bw, x_a, x_b]（金钱 | 海拔 | 石重 的分界）
static func _top_x(vp: Vector2) -> PackedFloat64Array:
	var bw: float = minf(640.0, vp.x - 360.0)
	var bx: float = clampf(vp.x / 2.0 - bw / 2.0, 252.0, vp.x - 100.0 - bw)
	return PackedFloat64Array([bx, bw, bx + bw * 0.40, bx + bw * 0.67])


## ① 金钱（里程表滚动数字；夜里显示今夜碾得，跨 1千/1万/10万 金光裂纹）（TopLayer）
func _draw_top(vp: Vector2) -> void:
	var tx: PackedFloat64Array = _top_x(vp)
	var bx: float = tx[0]
	var x_a: float = tx[2]
	var by: float = FR + 8.0
	var bh: float = 62.0
	var r0: Rect2 = Rect2(bx, by, x_a - bx - 2.0, bh)
	if float(_odo["flash"]) > 0.0:
		_cv.draw_rect(r0.grow(-3.0), Color(GOLD, float(_odo["flash"]) * 0.22))
	var coin: Texture2D = SpriteDB.tex(&"coin_drachma")
	if coin != null:
		_cv.draw_texture_rect(coin, Rect2(bx + 14.0, by + bh / 2.0 - 18.0, 32.0, 32.0), false)
	var num_r: float = x_a - 18.0
	_draw_odo(num_r, by + 36.0, 27, 30.0, num_r - (bx + 52.0), Color("fff3c4") if not _crack.is_empty() else GOLD_HI)


## ① 金钱下面的小字 + 金光裂纹（TopSubLayer）
func _draw_top_sub(vp: Vector2) -> void:
	var tx: PackedFloat64Array = _top_x(vp)
	var bx: float = tx[0]
	var x_a: float = tx[2]
	var by: float = FR + 8.0
	var bh: float = 62.0
	var r0: Rect2 = Rect2(bx, by, x_a - bx - 2.0, bh)
	var at_night: bool = mix > 0.5 and sim.night_total_valid
	var num_r: float = x_a - 18.0
	var sub_a: float = 0.3 if _odo_rolling() else 1.0
	_text((Loc.t("hud_view.tonight_s_take_purse", "今夜碾得 · 囊中 ") + NumFmt.fmt(sim.money)) if at_night else Loc.t("hud_view.drachmas", "德拉克马 · ΔΡΑΧΜΑΙ"), Vector2(num_r, by + 54.0), 11, Color(_c("dim"), _c("dim").a * sub_a), null, HORIZONTAL_ALIGNMENT_RIGHT)
	if not _crack.is_empty():
		_draw_crack(r0)


## ② 海拔（TopAltLayer）
func _draw_top_alt(vp: Vector2) -> void:
	var x_a: float = _top_x(vp)[2]
	var by: float = FR + 8.0
	var bh: float = 62.0
	var at_night: bool = mix > 0.5 and sim.night_total_valid
	var h: float = _col_h()
	if Loc.is_en():
		# Cinzel 只有大写，"320 M" 在英文里挨着 K/M 金额容易读成 3.2 亿：数字用 Cinzel，单位 m 换成有小写的衬线体
		var alt_s: String = "%d" % int(h)
		_text(alt_s, Vector2(x_a + 44.0, by + 34.0), 23, _c("cream"), Fonts.cinzel(700))
		_text("m", Vector2(x_a + 44.0 + Fonts.cinzel(700).get_string_size(alt_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 23).x + 4.0, by + 34.0), 19, _c("cream"), Fonts.serif(600))
	else:
		_text("%d m" % int(h), Vector2(x_a + 44.0, by + 34.0), 23, _c("cream"), Fonts.cinzel(700))
	_text_fit((Loc.t("hud_view.drop_best", "起滚 · 纪录 %d") % int(sim.record)) if at_night else (Loc.t("hud_view.best_summit", "纪录 %d · 顶 %d") % [int(sim.record), int(World.SUMMIT)]), Vector2(x_a + 44.0, by + 54.0), 11, _c("dim"), _top_x(vp)[3] - x_a - 44.0 - 12.0)
	_mountain(Vector2(x_a + 26.0, by + bh / 2.0 - 1.0), 11.0)


## ③ 石重 / 尺寸等级（TopStoneLayer）
func _draw_top_stone(vp: Vector2) -> void:
	var tx: PackedFloat64Array = _top_x(vp)
	var bx: float = tx[0]
	var bw: float = tx[1]
	var x_b: float = tx[3]
	var by: float = FR + 8.0
	var bh: float = 62.0
	var r: float = sim.stone.r
	var ti: int = sim.size_tier(r)
	var flash: float = sim.tier_flash
	var rr: float = 5.0 + 9.0 * clampf(log(maxf(r, 0.3) / 0.6) / log(25.0), 0.0, 1.0)
	if flash > 0.0:
		_cv.draw_rect(Rect2(x_b + 4.0, by + 3.0, bx + bw - x_b - 8.0, bh - 6.0), Color(GOLD, flash * 0.3))
	_boulder_icon(Vector2(x_b + 27.0, by + bh / 2.0), rr * (1.0 + flash * 0.3), flash > 0.05)
	var fs3: int = roundi(18.0 * (1.0 + flash * 0.2))
	_text(Loc.t("hud_view.size_class", "%s级") % String(sim.content.size_tiers[ti]["name"]), Vector2(x_b + 46.0, by + 31.0), fs3, GOLD_HI if flash > 0.05 else _c("cream"), Fonts.serif(700))
	_text_fit(Loc.t("hud_view.m_weight_talents", "径%sm · %s 塔兰同") % [Js.to_fixed(r * 2.0, 1), NumFmt.fmt_talent(r)], Vector2(x_b + 46.0, by + 54.0), 11, _c("dim"), bx + bw - x_b - 46.0 - 12.0)


## ④ 命运（摇到第一个之后才出现）：金钱那块下面挂一小块（TopMoiraLayer）
func _draw_top_moira(vp: Vector2) -> void:
	if not _moira_shown():
		return
	var mr: Rect2 = Rect2(_top_x(vp)[0], FR + 8.0 + 62.0 + 4.0, 168.0, 30.0)
	if moira_pop > 0.0:
		_cv.draw_rect(mr.grow(-3.0), Color(GOLD, moira_pop * 0.25))
	MoiraIcon.draw(_cv, Vector2(mr.position.x + 20.0, mr.position.y + 15.0), 10.0, 1.0, moira_pop > 0.5)
	_text(NumFmt.fmt(sim.moira), Vector2(mr.position.x + 38.0, mr.position.y + 22.0), 18, GOLD_HI if moira_pop > 0.0 else _c("cream"), Fonts.serif(700))
	_text(Loc.t("hud_view.fate", "命运"), Vector2(mr.end.x - 10.0, mr.position.y + 21.0), 11, _c("dim"), null, HORIZONTAL_ALIGNMENT_RIGHT)


## 小图标：石球（陶土嵌色 + 两道裂纹）
func _boulder_icon(c: Vector2, rr: float, gold: bool) -> void:
	_cv.draw_circle(c, rr, _c("inlay"))
	_cv.draw_arc(c, rr, 0.0, TAU, 24, GOLD_HI if gold else _c("ink"), 1.2, true)
	var w: float = maxf(0.8, rr * 0.12)
	_cv.draw_polyline(PackedVector2Array([c + Vector2(-rr * 0.6, -rr * 0.2), c + Vector2(-rr * 0.1, rr * 0.15), c + Vector2(rr * 0.3, -rr * 0.35)]), _c("ink"), w)
	_cv.draw_line(c + Vector2(rr * 0.05, rr * 0.55), c + Vector2(rr * 0.45, rr * 0.25), _c("ink"), w)


# ———————————————— 里程表数字（= render.js odoSet / drawOdo）————————————————
## 数字等宽；只有最高的变化位滚动，其余直接替换；同一列 0.12 秒内再变也直接替换；格式变了（跨进"万"）整串交叉淡入 0.2 秒
static func _shape_of(s: String) -> String:
	var out: String = ""
	for ch: String in s:
		out += "0" if ch >= "0" and ch <= "9" else ch
	return out


func _odo_set(s: String, val: float, dt: float) -> void:
	var o: Dictionary = _odo
	o["now"] = float(o["now"]) + dt
	var cols: Array = o["cols"]
	if not bool(o["init"]):
		cols.clear()
		for ch: String in s:
			cols.append({"ch": ch, "prev": ch, "k": 1.0, "last": -9.0})
		o["str"] = s
		o["val"] = val
		o["init"] = true
		return
	if s != String(o["str"]):
		o["dir"] = 1.0 if val >= float(o["val"]) else -1.0
		if _shape_of(s) != _shape_of(String(o["str"])):
			o["old"] = o["str"]
			o["xf"] = 0.0
			cols.clear()
			for ch: String in s:
				cols.append({"ch": ch, "prev": ch, "k": 1.0, "last": o["now"]})
		else:
			var top: bool = true
			for i: int in s.length():
				var col: Dictionary = cols[i]
				if String(col["ch"]) == s[i]:
					continue
				var quick: bool = not top or float(o["now"]) - float(col["last"]) < 0.12 or float(o["xf"]) < 1.0
				col["prev"] = col["ch"]
				col["ch"] = s[i]
				col["k"] = 1.0 if quick else 0.0
				col["last"] = o["now"]
				top = false
		o["str"] = s
	if floorf(val) > floorf(float(o["val"])):
		o["flash"] = maxf(float(o["flash"]), 0.55)
	o["val"] = val
	for col2: Dictionary in cols:
		col2["k"] = minf(1.0, float(col2["k"]) + dt / 0.2)
	o["xf"] = minf(1.0, float(o["xf"]) + dt / 0.2)
	o["flash"] = maxf(0.0, float(o["flash"]) - dt / 0.3)


func _odo_rolling() -> bool:
	if float(_odo["xf"]) < 1.0:
		return true
	for c: Dictionary in _odo["cols"]:
		if float(c["k"]) < 1.0:
			return true
	return false


## 右对齐画里程表；滚动位上下错开 lineH，用裁剪框（draw_set_clip 没有，用逐字 alpha 近似：超出行高的那半淡出）
func _draw_odo(xr: float, y: float, fs: int, line_h: float, max_w: float, col: Color) -> void:
	var f: Font = Fonts.cinzel(700)
	var dw: float = _odo_dw.get(fs, -1.0)
	if dw < 0.0:
		dw = 0.0
		for dgt: int in 10:
			dw = maxf(dw, f.get_string_size(str(dgt), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		_odo_dw[fs] = dw
	var cols: Array = _odo["cols"]
	var widths: Array[float] = []
	var total: float = 0.0
	for c: Dictionary in cols:
		var ch: String = String(c["ch"])
		var w: float = dw if ch >= "0" and ch <= "9" else maxf(dw * 0.35, _odo_w(ch, fs))
		widths.append(w)
		total += w
	var sc: float = minf(1.0, max_w / maxf(1.0, total))
	var fs2: int = maxi(8, int(fs * sc))
	var xf: float = float(_odo["xf"])
	if xf < 1.0 and String(_odo["old"]) != "":
		_text(String(_odo["old"]), Vector2(xr, y), fs2, Color(col, 1.0 - xf), f, HORIZONTAL_ALIGNMENT_RIGHT)
	var x: float = xr
	var dir: float = float(_odo["dir"])
	for i: int in range(cols.size() - 1, -1, -1):
		var c: Dictionary = cols[i]
		var w2: float = widths[i] * sc
		var cx: float = x - w2 / 2.0
		var k: float = float(c["k"])
		var cc: Color = Color(col, col.a * xf)
		if k >= 1.0:
			_odo_char(String(c["ch"]), Vector2(cx, y), fs2, cc)
		else:
			var e: float = (1.0 - pow(1.0 - k, 3.0)) * line_h * dir
			_odo_char(String(c["prev"]), Vector2(cx, y - e), fs2, Color(cc, cc.a * (1.0 - k)))
			_odo_char(String(c["ch"]), Vector2(cx, y + dir * line_h - e), fs2, Color(cc, cc.a * k))
		x -= w2


## 里程表单字宽（Cinzel 700，按字和字号缓存）
func _odo_w(ch: String, fs: int) -> float:
	var by_fs: Dictionary = _odo_cw.get(fs, {})
	if by_fs.is_empty():
		_odo_cw[fs] = by_fs
	var w: float = by_fs.get(ch, -1.0)
	if w < 0.0:
		w = Fonts.cinzel(700).get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		by_fs[ch] = w
	return w


## 里程表的一个字，居中在 c.x（= _text 居中，字宽走缓存）
func _odo_char(ch: String, c: Vector2, fs: int, col: Color) -> void:
	_cv.draw_string(Fonts.cinzel(700), Vector2(c.x - _odo_w(ch, fs) / 2.0, c.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col)


## 金光裂纹（跨过 1千 / 1万 / 10万 时）：折线存成陶片内的相对坐标
func _make_crack(lvl: int) -> void:
	var pts: PackedVector2Array = []
	var x: float = 0.12 + randf() * 0.2
	var y: float = 0.0
	pts.append(Vector2(x, y))
	while y < 1.0:
		x += 0.06 + randf() * 0.12
		y += 0.18 + randf() * 0.22
		pts.append(Vector2(minf(0.97, x), minf(1.0, y)))
	var bi: int = 1 + randi() % maxi(1, pts.size() - 2)
	var br: PackedVector2Array = [pts[bi]]
	var bxx: float = pts[bi].x
	var byy: float = pts[bi].y
	for i: int in 3:
		bxx += 0.08 + randf() * 0.1
		byy += (randf() - 0.6) * 0.3
		br.append(Vector2(minf(0.98, bxx), clampf(byy, 0.0, 1.0)))
	_crack = {"t": 0.0, "lvl": lvl, "pts": pts, "br": br}


func _draw_crack(r: Rect2) -> void:
	var k: float = float(_crack["t"])
	var a: float = k / 0.08 if k < 0.08 else maxf(0.0, 1.0 - (k - 0.08) / 1.1)
	var lvl: int = int(_crack["lvl"])
	_cv.draw_rect(r.grow(-3.0), Color(GOLD, a * (0.16 + 0.06 * lvl)))
	for key: String in ["pts", "br"]:
		var line: PackedVector2Array = []
		for q: Vector2 in (_crack[key] as PackedVector2Array):
			line.append(r.position + Vector2(q.x * r.size.x, q.y * r.size.y))
		_cv.draw_polyline(line, Color(GOLD, a * 0.5), 1.6 + lvl * 0.5 + 4.0, true)
		_cv.draw_polyline(line, Color(GOLD_HI, a), 1.6 + lvl * 0.5, true)
	var core: PackedVector2Array = []
	for q2: Vector2 in (_crack["pts"] as PackedVector2Array):
		core.append(r.position + Vector2(q2.x * r.size.x, q2.y * r.size.y))
	_cv.draw_polyline(core, Color("fff6d8", a), 0.8, true)


# ———————————————— 右侧：海拔刻度柱（爱奥尼柱：柱头卷涡、齿饰柱身、柱础）+ 标记 + 小人 ————————————————
const ALT_BANDS: Array[Array] = [[0.0, "Α"], [120.0, "Β"], [350.0, "Γ"], [650.0, "Δ"], [850.0, "Ε"], [950.0, "Ζ"]]


## 柱子本身（StaticLayer）：山花、柱头、柱身齿饰、刻度、分段字母、柱础
func _draw_column_base(vp: Vector2) -> void:
	var cx: float = vp.x - FR - 30.0
	var y0: float = FR + 50.0
	var y1: float = vp.y - FR - 58.0
	var sw: float = 20.0
	var tw: float = 8.0
	var ink: Color = _c("ink")
	var line: Color = _c("line")
	# 柱顶小山花（代表山顶）
	var ped: PackedVector2Array = [Vector2(cx - 16.0, y0 - 16.0), Vector2(cx, y0 - 29.0), Vector2(cx + 16.0, y0 - 16.0)]
	_cv.draw_colored_polygon(ped, ink)
	ped.append(ped[0])
	_cv.draw_polyline(ped, line, 1.1, true)
	_cv.draw_circle(Vector2(cx, y0 - 20.5), 2.2, _c("edge"))
	# 柱头：顶板 + 卷涡
	_cv.draw_rect(Rect2(cx - 18.0, y0 - 15.0, 36.0, 4.5), ink)
	_cv.draw_rect(Rect2(cx - 18.0, y0 - 15.0, 36.0, 4.5), line, false, 1.1)
	_cv.draw_rect(Rect2(cx - 12.0, y0 - 10.5, 24.0, 7.0), ink)
	for sgn: float in [-1.0, 1.0]:
		var vc: Vector2 = Vector2(cx + sgn * 13.0, y0 - 6.0)
		_cv.draw_circle(vc, 5.0, ink)
		_cv.draw_arc(vc, 5.0, 0.0, TAU, 20, line, 1.1, true)
		_cv.draw_arc(vc, 2.8, 0.0, PI * 1.5, 14, line, 1.1, true)
		_cv.draw_circle(vc, 0.9, line)
	_cv.draw_line(Vector2(cx - 10.0, y0 - 1.5), Vector2(cx + 10.0, y0 - 1.5), line, 1.1)
	# 柱身 + 两侧齿饰 + 凹槽
	_cv.draw_rect(Rect2(cx - sw / 2.0, y0, sw, y1 - y0), ink)
	_cv.draw_rect(Rect2(cx - sw / 2.0 + 0.5, y0 + 0.5, sw - 1.0, y1 - y0 - 1.0), line, false, 1.0)
	var yy: float = y0 + 4.0
	while yy < y1 - 3.0:
		_cv.draw_rect(Rect2(cx - sw / 2.0 + 2.0, yy, 2.6, 2.6), _c("line_dim"))
		_cv.draw_rect(Rect2(cx + sw / 2.0 - 4.6, yy, 2.6, 2.6), _c("line_dim"))
		yy += 6.0
	_cv.draw_rect(Rect2(cx - tw / 2.0, y0 + 2.0, tw, y1 - y0 - 4.0), _c("track"))
	_cv.draw_line(Vector2(cx - tw / 2.0 + 0.5, y0 + 2.0), Vector2(cx - tw / 2.0 + 0.5, y1 - 2.0), Color(0, 0, 0, 0.6), 1.0)
	for a: int in range(0, int(World.SUMMIT) + 1, 100):
		var y: float = roundf(_col_y(float(a), y0, y1)) + 0.5
		var big: bool = a % 500 == 0
		_cv.draw_line(Vector2(cx - sw / 2.0 - (6.0 if big else 3.5), y), Vector2(cx - sw / 2.0, y), line, 1.0)
		_cv.draw_line(Vector2(cx + sw / 2.0, y), Vector2(cx + sw / 2.0 + (6.0 if big else 3.5), y), line, 1.0)
	# 海拔分段：分界线 + 段中希腊字母小章
	for i: int in ALT_BANDS.size():
		var b0: float = ALT_BANDS[i][0]
		var top: float = ALT_BANDS[i + 1][0] if i + 1 < ALT_BANDS.size() else World.SUMMIT
		if b0 > 0.0:
			var yb: float = roundf(_col_y(b0, y0, y1)) + 0.5
			_cv.draw_line(Vector2(cx - sw / 2.0 + 1.0, yb), Vector2(cx + sw / 2.0 - 1.0, yb), _c("edge"), 1.6)
		var ym: float = _col_y((b0 + top) / 2.0, y0, y1)
		var dc: Vector2 = Vector2(cx - sw / 2.0 - 13.0, ym)
		_cv.draw_circle(dc, 7.0, ink)
		_cv.draw_arc(dc, 7.0, 0.0, TAU, 20, _c("edge"), 1.0, true)
		_text(String(ALT_BANDS[i][1]), dc + Vector2(0, 4.0), 10, _c("cream"), Fonts.greek(), HORIZONTAL_ALIGNMENT_CENTER)
	# 柱础
	for rr: Rect2 in [Rect2(cx - 13.0, y1, 26.0, 4.0), Rect2(cx - 17.0, y1 + 4.0, 34.0, 6.0), Rect2(cx - 21.0, y1 + 10.0, 42.0, 5.0)]:
		_cv.draw_rect(rr, ink)
		_cv.draw_rect(rr.grow(-0.5), line, false, 1.0)


## 海拔柱上的 y（柱顶 y0 = 山顶，柱底 y1 = 0 m）
static func _col_y(a: float, y0: float, y1: float) -> float:
	return y1 - (clampf(a, 0.0, World.SUMMIT) / World.SUMMIT) * (y1 - y0)


## 柱上指针所在的海拔（夜里是起滚处）
func _col_h() -> float:
	return sim.start_alt if sim.phase == &"night" or sim.phase == &"night_end" else sim.altitude()


## 柱子右侧的标记（祭坛、商人、普罗米修斯、石碑……）
func _marks() -> Array:
	return sim.boons.marks() + sim.story.marks() + sim.meta_rules.stele_marks()


## 标记的缓存：依赖的 sim 状态（祭坛点亮、剧情旗标和 NPC、日数、代数、石碑）没变就用上次的；保险起见满 1 秒也重算一次
func _marks_cached() -> Array:
	var fp: Array = [sim.boons.done, sim.story.flags, sim.story.npcs, sim.day, sim.demo, sim.run.get("gen", 1),
		sim.meta.get("seen_merchant", false), sim.meta.get("steles", [])]
	if fp != _marks_fp or t - _marks_at > 1.0:
		_marks_fp = fp.duplicate(true)
		_marks_at = t
		_marks_cache = _marks()
	return _marks_cache


## 钟点：只在分钟数或黄昏 / 夜的标签变了才重算 Tod.clock_of
func _clock(tod: float) -> Dictionary:
	var mins: float = floorf(360.0 + maxf(0.0, tod) * 720.0) if tod <= 1.0 else floorf(minf(1440.0, 1080.0 + (tod - 1.0) * 720.0))
	var b: float = mins + (0.25 if tod >= Tod.SUNSET else 0.0) + (0.5 if tod > 1.06 else 0.0)
	if b != _clk_tod:
		_clk_tod = b
		_clk = Tod.clock_of(tod)
	return _clk


## 头顶上最近的下一个标记（空 = 没有）
static func _next_mark(marks: Array, h: float) -> Dictionary:
	var nxt: Dictionary = {}
	for m: Dictionary in marks:
		if float(m.get("alt", 0.0)) > h + 0.5 and (nxt.is_empty() or float(m["alt"]) < float(nxt["alt"])):
			nxt = m
	return nxt


## 下一个标记的名字写在哪一行（离指针太近时让到指针上方）
static func _label_y(nxt: Dictionary, yh: float, y0: float, y1: float) -> float:
	var ny: float = _col_y(float(nxt["alt"]), y0, y1)
	return minf(ny, yh - 16.0) if absf(ny - yh) < 16.0 else ny


## 提喀的赌注：白天、今天押的、还没兑现
func _bet_on() -> bool:
	var bt: Dictionary = sim.bet
	return not sim.demo and not bt.is_empty() and int(bt.get("day", -1)) == sim.day and not bool(bt.get("paid", false)) and sim.phase == &"day"


## 纪录以下的槽烧成陶色 + 小桂冠套在柱上（RecordLayer）
func _draw_column_record(vp: Vector2) -> void:
	var cx: float = vp.x - FR - 30.0
	var y0: float = FR + 50.0
	var y1: float = vp.y - FR - 58.0
	var tw: float = 8.0
	var yr: float = _col_y(sim.record, y0, y1)
	if sim.record > 0.0:
		_cv.draw_rect(Rect2(cx - tw / 2.0 + 1.0, yr, tw - 2.0, y1 - 2.0 - yr), Color(_c("fill"), 0.85))
	var lau: Texture2D = SpriteDB.tex(&"ui_laurel")
	if lau != null and sim.record > 1.0:
		var lw: float = 30.0
		var lh: float = lw / SpriteDB.aspect(&"ui_laurel")
		_cv.draw_texture_rect(lau, Rect2(cx - lw / 2.0, yr - lh * 0.55, lw, lh), false)


## 标记、下一个标记的名字、提喀的赌注（ColumnLayer）
func _draw_column_marks(vp: Vector2) -> void:
	var cx: float = vp.x - FR - 30.0
	var y0: float = FR + 50.0
	var y1: float = vp.y - FR - 58.0
	var ink: Color = _c("ink")
	var line: Color = _c("line")
	# 标记（祭坛、商人、普罗米修斯、石碑……）：柱子右侧的小圆章；只给"下一个"写名字
	var h: float = _col_h()
	var marks: Array = _marks_cache if not _layers.is_empty() else _marks()
	var nxt: Dictionary = _next_mark(marks, h)
	var mx: float = cx + 20.0
	var mr: float = 8.0
	for m: Dictionary in marks:
		var my: float = _col_y(float(m.get("alt", 0.0)), y0, y1)
		var gold_m: bool = bool(m.get("gold", false))
		_cv.draw_line(Vector2(cx + 10.0, my + 0.5), Vector2(mx - mr, my + 0.5), GOLD if gold_m else line, 1.0)
		_cv.draw_circle(Vector2(mx, my), mr, ink)
		var tex: Texture2D = SpriteDB.tex(StringName(String(m.get("sprite", ""))))
		if tex != null:
			var key: StringName = StringName(String(m.get("sprite", "")))
			var s2: float = (mr - 1.0) * 2.3
			var w2: float = s2 * minf(1.4, SpriteDB.aspect(key))
			_cv.draw_texture_rect(tex, Rect2(mx - minf(w2, (mr - 1.0) * 2.0) / 2.0, my - (mr - 1.0), minf(w2, (mr - 1.0) * 2.0), (mr - 1.0) * 2.0), false)
		else:
			_cv.draw_colored_polygon(PackedVector2Array([Vector2(mx, my - 3.5), Vector2(mx + 3.0, my), Vector2(mx, my + 3.5), Vector2(mx - 3.0, my)]), GOLD if gold_m else line)
		_cv.draw_arc(Vector2(mx, my), mr, 0.0, TAU, 20, GOLD if gold_m else _c("edge"), 1.6 if m == nxt else 1.0, true)
	var yh: float = _col_y(h, y0, y1)
	if not nxt.is_empty() and String(nxt.get("label", "")) != "":
		var ly: float = _label_y(nxt, yh, y0, y1)
		_text("%s %dm" % [String(nxt["label"]), roundi(float(nxt["alt"]))], Vector2(cx - 60.0, ly + 4.0), 11, GOLD_HI if bool(nxt.get("gold", false)) else _c("cream"), Fonts.serif(600), HORIZONTAL_ALIGNMENT_RIGHT, -1.0, 3)
	# 提喀的赌注（白天、还没兑现）：一道金线横穿柱子 + 筹码 + 「押 120 m ×2.10」，一直写着
	var bt: Dictionary = sim.bet
	if _bet_on():
		var by: float = _col_y(float(bt["h"]), y0, y1)
		_cv.draw_line(Vector2(cx - 16.0, by), Vector2(cx + 16.0, by), GOLD_HI, 2.0)
		var chip: Texture2D = SpriteDB.tex(&"chip2_player")
		if chip != null:
			var cw: float = 18.0
			_cv.draw_texture_rect(chip, Rect2(cx - 16.0 - cw - 2.0, by - cw * 0.45, cw, cw / maxf(0.1, SpriteDB.aspect(&"chip2_player"))), false)
		_text(Loc.t("hud_view.bet_m", "押 %d m ×%s") % [roundi(float(bt["h"])), Js.to_fixed(float(bt.get("odds", 0.0)), 2)], Vector2(cx - 40.0, by + 4.0), 11, GOLD_HI, Fonts.serif(700), HORIZONTAL_ALIGNMENT_RIGHT, -1.0, 3)


## 当前：金点 + 指针 + 西西弗斯小剪影（钳在柱顶以内）（PointerLayer）
func _draw_column_pointer(vp: Vector2) -> void:
	var cx: float = vp.x - FR - 30.0
	var y0: float = FR + 50.0
	var y1: float = vp.y - FR - 58.0
	var ink: Color = _c("ink")
	var yh: float = _col_y(_col_h(), y0, y1)
	_cv.draw_rect(Rect2(cx - 10.0, yh - 1.0, 20.0, 2.0), GOLD)
	_cv.draw_circle(Vector2(cx, yh), 3.6, GOLD_HI)
	_cv.draw_arc(Vector2(cx, yh), 3.6, 0.0, TAU, 12, ink, 1.0, true)
	_cv.draw_colored_polygon(PackedVector2Array([Vector2(cx - 14.0, yh), Vector2(cx - 22.0, yh - 4.5), Vector2(cx - 22.0, yh + 4.5)]), GOLD)
	var fig_key: StringName = &"sit" if mix > 0.5 else &"push_0"
	var fig: Texture2D = SpriteDB.tex(fig_key)
	if fig != null:
		var fh: float = 20.0
		var fw: float = fh * SpriteDB.aspect(fig_key)
		var fy: float = clampf(yh, y0 + fh * 0.62, y1)
		var fxp: float = cx - 46.0
		_cv.draw_texture_rect(fig, Rect2(fxp - fw / 2.0 - 1.0, fy - fh * 0.62 - 1.0, fw + 2.0, fh + 2.0), false, Color(_c("cream"), 0.5))
		_cv.draw_texture_rect(fig, Rect2(fxp - fw / 2.0, fy - fh * 0.62, fw, fh), false)


func _mountain(c: Vector2, s: float) -> void:
	var pts: PackedVector2Array = [c + Vector2(-s, s * 0.62), c + Vector2(-s * 0.25, -s * 0.7), c + Vector2(s * 0.12, -s * 0.12), c + Vector2(s * 0.42, -s * 0.48), c + Vector2(s, s * 0.62)]
	_cv.draw_colored_polygon(pts, _c("inlay"))
	pts.append(pts[0])
	_cv.draw_polyline(pts, _c("ink"), 1.2)


func _draw_combo(vp: Vector2) -> void:
	var combo: int = sim.combo
	if combo < 2:
		return
	var st: Stats = sim.stats
	var mult: float = minf(st.combo_cap, 1.0 + st.combo_step * maxf(0.0, combo - 1))
	var y: float = FR + 8.0 + 62.0 + 70.0
	var s: float = 1.0 + sim.combo_pulse * 0.35
	var heat: float = clampf((mult - 1.0) / 2.0, 0.0, 1.0)
	if heat > 0.15:
		Glow.draw(_cv, Vector2(vp.x / 2.0, y), 110.0 * s, Color(GOLD_HI, minf(1.0, (heat - 0.15) * 1.1 + sim.combo_pulse * 0.4) * 0.55))
	var lau: Texture2D = SpriteDB.tex(&"ui_laurel")
	if lau != null:
		var lw: float = 116.0 * s
		var lh: float = lw / SpriteDB.aspect(&"ui_laurel")
		_cv.draw_texture_rect(lau, Rect2(vp.x / 2.0 - lw / 2.0, y - lh * 0.52, lw, lh), false, Color(1, 1, 1, 0.6 + 0.4 * minf(1.0, combo / 12.0)))
	var fs: int = roundi((38.0 if combo >= 100 else 46.0) * s)
	_text(str(combo), Vector2(vp.x / 2.0, y + fs * 0.35), fs, GOLD_HI if heat > 0.5 else Color("f1e3c8"), Fonts.cinzel(900), HORIZONTAL_ALIGNMENT_CENTER, -1.0, 6)
	_text(Loc.t("hud_view.crush_combo", "连碾 ×%s") % Js.to_fixed(mult, 1), Vector2(vp.x / 2.0, y + 52.0), 16, Color("f1e3c8"), Fonts.serif(700), HORIZONTAL_ALIGNMENT_CENTER, -1.0, 4)


## 提示缎带文字依赖的输入（变了才重算文字、重画）
func _hint_inputs() -> Array:
	if Settings.hint_mode == 2 or (Settings.hint_mode == 0 and sim.day > 2):
		return [false]
	var inp: Array = [Settings.hint_mode, sim.day, _narration_on(), sim.phase]
	if sim.phase == &"day":
		inp.append_array([sim.stats.hold_push, Settings.auto_push, Settings.bindings.get("push_left"), Settings.bindings.get("push_right"), Settings.bindings.get("end_day")])
	elif sim.phase == &"night":
		inp.append_array([sim.slam_left, sim.next_slam_pay(), Settings.bindings.get("strike")])
	return inp


## 底部提示缎带的文字（"" = 不显示）
func _hint_text() -> String:
	# 同屏文字预算（2026-10-15）：底部同时只留一行。操作提示只在前两天显示；旁白出现时先让给旁白
	# 设置里的"操作提示"：只在前两天（默认）/ 一直显示 / 关闭
	if Settings.hint_mode == 2 or (Settings.hint_mode == 0 and sim.day > 2) or _narration_on():
		return ""
	var st: Stats = sim.stats
	var hint: String = ""
	if sim.phase == &"day":
		var lk: String = Settings.short_label("push_left")
		var rk: String = Settings.short_label("push_right")
		hint = (Loc.t("hud_view.hold_push", "按住 %s 持续推") % rk if st.hold_push else Loc.t("hud_view.alternate_tiles_overhead_steady", "跟着头顶陶片交替按 %s / %s，节奏稳定推得更快") % [lk, rk]) + Loc.t("hud_view.clock_out_early", " · %s 提前收工") % Settings.short_label("end_day")
		if Settings.auto_push:
			hint = Loc.t("hud_view.auto_push", "自动推石中 · ") + hint
	elif sim.phase == &"night":
		hint = Loc.t("hud_view.heavy_crush_as_gold", "%s：金圈收缩到石头边缘时「重压」 · 腾空时「砸地」%s（剩 %d）") % [Settings.short_label("strike"),
			(" +" + NumFmt.fmt(sim.next_slam_pay())) if sim.slam_left > 0 and sim.next_slam_pay() > 0.0 else "", sim.slam_left]
	return hint


func _draw_hint(vp: Vector2) -> void:
	var hint: String = _hint_text()
	if hint == "":
		return
	var fs: int = 15
	var f: Font = Fonts.serif(600)
	var tw: float = f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var rw: float = tw + 64.0
	var rh: float = fs + 13.0
	var rx: float = vp.x / 2.0 - rw / 2.0
	var ry: float = vp.y - FR - 14.0 - rh / 2.0
	var pts: PackedVector2Array = [Vector2(rx, ry - rh / 2.0), Vector2(rx + rw, ry - rh / 2.0), Vector2(rx + rw - 9.0, ry), Vector2(rx + rw, ry + rh / 2.0), Vector2(rx, ry + rh / 2.0), Vector2(rx + 9.0, ry)]
	_cv.draw_colored_polygon(pts, Color(_c("ink"), 0.76))
	pts.append(pts[0])
	_cv.draw_polyline(pts, _c("edge"), 1.0)
	_text(hint, Vector2(vp.x / 2.0, ry + fs * 0.35), fs, _c("cream"), f, HORIZONTAL_ALIGNMENT_CENTER)


## 底部旁白（present/story/story_view.gd 画）正在显示
func _narration_on() -> bool:
	if sim.story == null:
		return false
	var nr: Dictionary = sim.story.narr
	if nr.is_empty():
		return false
	var k: float = sim.t - float(nr["at"])
	return k > -0.3 and k < float(nr["life"])


func _draw_toasts(vp: Vector2) -> void:
	var y: float = vp.y * 0.30
	for to: Dictionary in toasts:
		var k: float = float(to["t"]) / float(to["life"])
		var a: float = minf(1.0, float(to["t"]) / 0.25) * minf(1.0, (1.0 - k) * 4.0)
		_text(String(to["text"]), Vector2(vp.x / 2.0, y), 18, Color(to["color"] as Color, a), Fonts.serif(700), HORIZONTAL_ALIGNMENT_CENTER, -1.0, 4)
		y += 30.0


## 横幅：米色卷轴 + 墨字（标题 + 副标题）
func _draw_banner(vp: Vector2) -> void:
	if banner.is_empty():
		return
	var bt: float = banner["t"]
	var life: float = banner["life"]
	var a: float = minf(1.0, bt / 0.2) * minf(1.0, (life - bt) / 0.4)
	if a <= 0.0:
		return
	var yf: float = float(banner["y"])
	var cy: float = vp.y * (yf if not is_nan(yf) else 0.3)
	var fs: int = int(banner["size"]) if float(banner["size"]) > 0.0 else 44
	var title: String = banner["text"]
	var sub: String = banner["sub"]
	var f: Font = Fonts.serif(900)
	var tw: float = f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var sw: float = Fonts.serif(700).get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x if sub != "" else 0.0
	# 卷轴整张拉伸，两头的轴各占约 17%：英文字长，按标题和副标题较宽的那个再多留出轴的位置（中文保持原来的宽度）
	var w: float = maxf(maxf(tw, sw) * (1.25 if Loc.is_en() else 1.0) + 120.0, 360.0)
	var h: float = fs * 1.4 + (30.0 if sub != "" else 8.0)
	var pop: float = 1.0 + 0.08 * maxf(0.0, 1.0 - bt / 0.15)
	var r: Rect2 = Rect2(vp.x / 2.0 - w * pop / 2.0, cy - h * pop / 2.0, w * pop, h * pop)
	var scroll: Texture2D = SpriteDB.tex(&"ui_scroll")
	if scroll != null:
		_cv.draw_texture_rect(scroll, r.grow_individual(60.0, 26.0, 60.0, 26.0), false, Color(1, 1, 1, a))
	else:
		_cv.draw_rect(r, Color("e9d3a8", a * 0.95))
		_cv.draw_rect(r, Color("8a3f17", a), false, 2.0)
	var ink: Color = Color("2a1a10", a)
	_text(title, Vector2(vp.x / 2.0, r.position.y + fs * 1.05 * pop), roundi(fs * pop), ink, f, HORIZONTAL_ALIGNMENT_CENTER)
	if sub != "":
		_text(sub, Vector2(vp.x / 2.0, r.position.y + fs * 1.05 * pop + 30.0), 18, Color("4a3020", a), Fonts.serif(700), HORIZONTAL_ALIGNMENT_CENTER)
