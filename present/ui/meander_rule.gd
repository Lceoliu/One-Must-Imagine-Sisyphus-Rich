@tool
class_name MeanderRule
extends Control
## 一道回纹细线（陶瓶风格的分隔线）：标题下面、牌匾里分节用。颜色默认黑釉。

@export var color: Color = Color(0.0705882, 0.0470588, 0.0392157, 0.85):
	set(v):
		color = v
		queue_redraw()
@export var unit: float = 12.0


func _draw() -> void:
	var x: float = 0.0
	var h: float = size.y
	while x + unit <= size.x + 0.5:
		var pts: PackedVector2Array = [Vector2(x + 1, h - 1), Vector2(x + 1, 1.5), Vector2(x + unit * 0.75, 1.5), Vector2(x + unit * 0.75, h * 0.7),
			Vector2(x + unit * 0.38, h * 0.7), Vector2(x + unit * 0.38, h * 0.42), Vector2(x + unit * 0.55, h * 0.42)]
		draw_polyline(pts, color, 1.5)
		draw_line(Vector2(x, h - 1), Vector2(x + unit, h - 1), color, 1.5)
		x += unit
