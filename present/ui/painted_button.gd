class_name PaintedButton
extends Control
## 瓶画题字式的按钮（主菜单）：平时是直接写在陶土上的黑字；鼠标移上去 / 键盘选中时，一道黑釉色带从左刷到字后面，
## 字变成象牙色（黑绘陶瓶"留白"的画法），色带两头各一个小回纹钩。键盘：方向键在按钮间移动，回车 / 空格按下。

signal pressed

const INK: Color = Color("120c0a")
const IVORY: Color = Color("eadbb8")

@export var text: String = "":
	set(v):
		text = v
		update_minimum_size()
		queue_redraw()
@export var font: Font = null
@export var font_size: int = 30:
	set(v):
		font_size = v
		update_minimum_size()
		queue_redraw()
## 主按钮（开始 / 继续）：字大一号，平时左边带一个小黑叶
@export var primary: bool = false

var _hover: bool = false
## 色带刷出的进度（0..1），有个很短的刷开动画
var _k: float = 0.0


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void:
		_hover = true
		grab_focus()
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _font() -> Font:
	return font if font != null else get_theme_default_font()


func _get_minimum_size() -> Vector2:
	var f: Font = _font()
	if f == null:
		return Vector2(200, 48)
	var sz: Vector2 = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	return Vector2(sz.x + 64.0, float(font_size) * 1.55)


func _on() -> bool:
	return _hover or has_focus()


func _process(dt: float) -> void:
	var want: float = 1.0 if _on() else 0.0
	if not is_equal_approx(_k, want):
		_k = move_toward(_k, want, dt / 0.12)
		queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	var mb: InputEventMouseButton = ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and Rect2(Vector2.ZERO, size).has_point(mb.position):
		pressed.emit()
		accept_event()
	elif ev.is_action_pressed(&"ui_accept"):
		pressed.emit()
		accept_event()


func _draw() -> void:
	var f: Font = _font()
	if f == null:
		return
	var h: float = size.y
	var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x0: float = 30.0
	var e: float = _k * _k * (3.0 - 2.0 * _k)
	if e > 0.001 and (tw + 48.0) * e > 24.0:
		# 黑釉色带：两头略收、上下边缘有一点笔触起伏（确定性，不闪）
		var left: float = 6.0
		var right: float = left + (tw + 48.0) * e
		var top: float = h * 0.14
		var bot: float = h * 0.88
		var pts: PackedVector2Array = []
		var n: int = 12
		for i: int in n + 1:
			var x: float = lerpf(left + 6.0, right - 6.0, float(i) / n)
			pts.append(Vector2(x, top + sin(i * 1.7 + 0.4) * 1.3))
		pts.append(Vector2(right, h * 0.5))
		for i: int in range(n, -1, -1):
			var x2: float = lerpf(left + 6.0, right - 6.0, float(i) / n)
			pts.append(Vector2(x2, bot + sin(i * 2.3 + 1.1) * 1.3))
		pts.append(Vector2(left, h * 0.5))
		draw_colored_polygon(pts, INK)
		# 两头的小回纹钩（象牙刻线）
		if e > 0.95:
			_hook(Vector2(left + 12.0, h * 0.5), 1.0)
			_hook(Vector2(right - 12.0, h * 0.5), -1.0)
	elif primary:
		# 主按钮平时左边一片小黑叶，提示"从这里开始"
		var c: Vector2 = Vector2(14.0, h * 0.52)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-8, 0), c + Vector2(0, -5), c + Vector2(9, 0), c + Vector2(0, 5)]), INK)
	var col: Color = INK.lerp(IVORY, e)
	var base: float = h * 0.5 + float(font_size) * 0.36
	draw_string(f, Vector2(x0, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _hook(c: Vector2, dir: float) -> void:
	var s: float = 5.0
	var pts: PackedVector2Array = [c + Vector2(-s * dir, s), c + Vector2(-s * dir, -s), c + Vector2(s * dir, -s), c + Vector2(s * dir, s * 0.3), c + Vector2(0, s * 0.3), c + Vector2(0, -s * 0.2)]
	draw_polyline(pts, IVORY, 1.6, true)
