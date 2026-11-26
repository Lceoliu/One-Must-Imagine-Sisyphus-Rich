class_name PaintedStone
extends Control
## 主菜单坡脚下的一块石头（"直接体验滚下山"）：画游戏里那块带金色裂纹的黑石头，底边贴在本控件底部（= 地平线）。
## 鼠标移上去 / 键盘选中：石头外一圈象牙刻线，名字下面一道刻线；按下发 pressed。

signal pressed

const INK: Color = Color("120c0a")
const IVORY: Color = Color("eadbb8")

## 石头在画面上的半径（像素）、名字、拿来体验的石头半径（米）
@export var radius_px: float = 30.0
@export var label: String = ""
@export var stone_r: float = 0.9
@export var font: Font = null
@export var font_size: int = 17

var _hover: bool = false
var _tex: Texture2D = null


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_tex = SpriteDB.tex(&"boulder_etched")
	mouse_entered.connect(func() -> void:
		_hover = true
		grab_focus()
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _get_minimum_size() -> Vector2:
	# 点击区至少要盖住下面的名字（英文名比中文长）
	var face: Font = font if font != null else get_theme_default_font()
	var label_w: float = face.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return Vector2(maxf(maxf(radius_px * 2.0 + 16.0, 96.0), label_w + 12.0), radius_px * 2.0 + float(font_size) * 2.2)


func _gui_input(ev: InputEvent) -> void:
	var mb: InputEventMouseButton = ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and Rect2(Vector2.ZERO, size).has_point(mb.position):
		pressed.emit()
		accept_event()
	elif ev.is_action_pressed(&"ui_accept"):
		pressed.emit()
		accept_event()


func _draw() -> void:
	var on: bool = _hover or has_focus()
	var ground: float = size.y - float(font_size) * 1.9
	var c: Vector2 = Vector2(size.x * 0.5, ground - radius_px * 0.94)
	if on:
		draw_arc(c, radius_px + 6.0, 0.0, TAU, 48, IVORY, 2.0, true)
	if _tex != null:
		var d: float = radius_px * 2.0
		draw_texture_rect(_tex, Rect2(c - Vector2(d, d) * 0.5, Vector2(d, d)), false)
	else:
		draw_circle(c, radius_px, INK)
	var f: Font = font if font != null else get_theme_default_font()
	if f == null:
		return
	var tw: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var ty: float = size.y - float(font_size) * 0.45
	draw_string(f, Vector2(size.x * 0.5 - tw * 0.5, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)
	if on:
		draw_line(Vector2(size.x * 0.5 - tw * 0.5, ty + 5.0), Vector2(size.x * 0.5 + tw * 0.5, ty + 5.0), INK, 2.0)
