class_name AltarShow
extends Control
## 赐福祭坛点亮的神降演出（立绘和各行字的位置在 altar_show.tscn）：四周压墨 → 回纹腰带在赐福名和立绘之间展开 → 立绘升起 → 赐福名盖章 → 等确认 → 淡出。
## 版面是画面正中的一列（20%–84%）：希腊名、赐福名、回纹腰带、立绘、效果和台词、「E 继续」（用户：整体重心要在中间，腰带放在立绘上方）。
## payload（BoonSystem._light）：{god, kicker, name, hi, lo, line, cn, greek}。字出齐后停住、底下出现「E 继续」，
## 玩家按交谈键 / 重压键（空格）/ 回车 / Esc / 点鼠标才淡出（不会自己结束，用户：自动结束根本看不清）。
## 字出齐之前（READY 秒内）的按键一律不理：祭坛是推石途中点亮的，那时手正按着推石和重压键。

signal finished

const SCENE: String = "res://present/ui/altar_show.tscn"

## 字出齐、开始接受确认的时刻；确认后淡出的时长
const READY: float = 1.6
const OUT: float = 0.5

var m: ModalRequest
var _t: float = 0.0
var _done: bool = false
## 按了确认的时刻（-1 = 还没按）
var _out_t: float = -1.0
var _prompt: Label
var _portrait: TextureRect
var _name: Label
var _greek: Label
var _hi: Label
var _lo: Label
var _line: Label
var _title: Label


static func create() -> AltarShow:
	return SceneCache.make(SCENE) as AltarShow


func setup(p_m: ModalRequest) -> void:
	m = p_m


func _ready() -> void:
	var p: Dictionary = m.payload
	_portrait = %Portrait
	_portrait.texture = SpriteDB.tex(StringName("god_" + String(p.get("god", ""))))
	_greek = %Greek
	_greek.text = String(p.get("greek", ""))
	_name = %Name
	_name.text = Loc.t("altar_show.name_quoted", "「%s」") % String(p.get("name", ""))
	_hi = %Hi
	_hi.text = String(p.get("hi", ""))
	_lo = %Lo
	_lo.text = String(p.get("lo", ""))
	_line = %Line
	_line.text = Loc.t("altar_show.quoted", "「%s」") % String(p.get("line", ""))
	_title = %TitleLine
	_title.text = Loc.t("altar_show.blessing", "%s · %s的赐福") % [String(p.get("kicker", Loc.t("altar_show.altar", "赐福祭坛"))), String(p.get("cn", ""))]
	_prompt = %Prompt
	_prompt.text = Loc.t("altar_show.continue", "%s  继续") % Settings.short_label("interact")
	_animate()


static func _ease(k: float) -> float:
	return 1.0 - pow(1.0 - clampf(k, 0.0, 1.0), 3.0)


static func _seg(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


## 淡出系数：按确认之前一直是 1
func _fade() -> float:
	return 1.0 if _out_t < 0.0 else 1.0 - _ease(clampf((_t - _out_t) / OUT, 0.0, 1.0))


func _animate() -> void:
	var t: float = _t
	var fade: float = _fade()
	var kr: float = _ease(_seg(t, 0.4, 1.2))
	_portrait.modulate.a = kr * fade
	_portrait.scale = Vector2.ONE * (0.9 + 0.1 * kr)
	_portrait.pivot_offset = _portrait.size / 2.0
	var ks: float = _ease(_seg(t, 0.9, 1.25))
	_name.modulate.a = ks * fade
	_name.scale = Vector2.ONE * (1.6 - 0.6 * ks)
	_name.pivot_offset = Vector2(_name.size.x / 2.0, 30.0)
	_greek.modulate.a = _ease(_seg(t, 0.6, 1.0)) * fade
	var kt: float = _ease(_seg(t, 1.2, 1.6)) * fade
	for l: Label in [_hi, _lo, _line, _title]:
		l.modulate.a = kt
	# 「E 继续」：字出齐后出现，轻轻呼吸
	_prompt.modulate.a = _ease(_seg(t, READY, READY + 0.4)) * fade * (0.75 + 0.25 * sin(t * 3.0))
	queue_redraw()


func _process(dt: float) -> void:
	_t += dt
	_animate()
	if not _done and _out_t >= 0.0 and _t - _out_t >= OUT:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()


## 确认：字出齐之后才收，收了开始淡出
func confirm() -> void:
	if _t < READY or _out_t >= 0.0:
		return
	_out_t = _t
	Sfx.play(&"click")


func _gui_input(ev: InputEvent) -> void:
	var mb: InputEventMouseButton = ev as InputEventMouseButton
	if mb != null and mb.pressed:
		confirm()


func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.is_pressed() or ev.is_echo():
		return
	get_viewport().set_input_as_handled()
	var k: InputEventKey = ev as InputEventKey
	if ev.is_action_pressed(&"interact") or ev.is_action_pressed(&"strike") or k.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		confirm()


func _draw() -> void:
	var W: float = size.x
	var H: float = size.y
	var t: float = _t
	var ink: float = 0.85 * _ease(_seg(t, 0.0, 0.3)) * _fade()
	# 四周压墨（中心留一块亮）：整屏墨 + 中心一团反向柔光做不出来，这里叠三层由外向内渐淡的墨框
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiKit.INK, ink * 0.55))
	for i: int in 3:
		var inset: float = (i + 1) * minf(W, H) * 0.08
		var a: float = ink * 0.15
		draw_rect(Rect2(0, 0, W, inset), Color(UiKit.INK, a))
		draw_rect(Rect2(0, H - inset, W, inset), Color(UiKit.INK, a))
		draw_rect(Rect2(0, 0, inset, H), Color(UiKit.INK, a))
		draw_rect(Rect2(W - inset, 0, inset, H), Color(UiKit.INK, a))
	Glow.draw(self, Vector2(W / 2.0, H * 0.51), H * 0.34, Color(UiKit.GOLD, 0.16 * _ease(_seg(t, 0.4, 1.2)) * _fade()))
	# 回纹腰带：赐福名和立绘之间，从中间往两边展开
	var kb: float = _ease(_seg(t, 0.3, 0.7)) * _fade()
	if kb > 0.0:
		var w: float = W * 0.3 * _ease(_seg(t, 0.3, 0.7))
		var x0: float = W * 0.5 - w * 0.5
		var y: float = H * 0.335
		var h: float = clampf(H * 0.03, 18.0, 30.0)
		var col: Color = Color(UiKit.CREAM, kb)
		draw_rect(Rect2(x0, y - h / 2.0, w, h), Color(UiKit.INK, kb))
		draw_line(Vector2(x0, y - h / 2.0 + 2.0), Vector2(x0 + w, y - h / 2.0 + 2.0), col, maxf(1.5, h * 0.09))
		draw_line(Vector2(x0, y + h / 2.0 - 2.0), Vector2(x0 + w, y + h / 2.0 - 2.0), col, maxf(1.5, h * 0.09))
		var u: float = h * 0.7
		var n: int = int(w / u)
		for i: int in n:
			var x: float = x0 + i * u + u * 0.15
			var s: float = u * 0.7
			var pts: PackedVector2Array = [Vector2(x, y + u * 0.32), Vector2(x, y - u * 0.32), Vector2(x + s, y - u * 0.32),
				Vector2(x + s, y + u * 0.1), Vector2(x + s * 0.35, y + u * 0.1), Vector2(x + s * 0.35, y - u * 0.08)]
			draw_polyline(pts, col, maxf(1.5, h * 0.09))
