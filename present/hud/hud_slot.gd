@tool
class_name HudSlot
extends Control
## HUD 的一块"槽位"（hud.tscn 里的子节点）：在编辑器里拖动 / 缩放它，运行时那一块 HUD 就跟着平移 / 缩放
## （HudView 按槽位相对默认位置的变换来画）；把槽位设成不可见 = 运行时不画这一块。
## 只在编辑器里画一个半透明框和名字，游戏里什么都不画。


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Engine.is_editor_hint():
		resized.connect(queue_redraw)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var c: Color = Color(1.0, 0.78, 0.3)
	draw_rect(Rect2(Vector2.ZERO, size), Color(c, 0.10))
	draw_rect(Rect2(Vector2.ZERO, size), Color(c, 0.85), false, 2.0)
	var f: Font = ThemeDB.fallback_font
	draw_string(f, Vector2(6, 18), String(name), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(c, 0.95))
