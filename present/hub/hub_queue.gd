@tool
class_name HubQueue
extends Marker2D
## 冥府之门前排队的幽魂（今晚被碾死的村民）：从这个标记往右排 slots 个，每 interval 秒最前面那个走到 into_x 淡出进门。
## 人数 = 今晚碾死的活物数（最多 max_souls）。编辑器里画出排队的格子和进门点。

@export var slots: int = 6:
	set(v):
		slots = v
		queue_redraw()
@export var spacing: float = 110.0:
	set(v):
		spacing = v
		queue_redraw()
## 进门点（相对这个标记的 x，一般是负数：往左走进门）
@export var into_x: float = -1180.0:
	set(v):
		into_x = v
		queue_redraw()
@export var interval: float = 5.5
@export var max_souls: int = 40
@export var ghost_height: float = 300.0
## 幽魂的精灵（轮换）
@export var keys: PackedStringArray = ["gh_shepherd", "gh_potter", "gh_oldwoman", "gh_baker", "gh_soldier", "gh_mother"]


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var c: Color = Color(0.7, 0.85, 1.0)
	for i: int in slots:
		draw_rect(Rect2(i * spacing - 30.0, -ghost_height, 60.0, ghost_height), Color(c, 0.12))
		draw_rect(Rect2(i * spacing - 30.0, -ghost_height, 60.0, ghost_height), Color(c, 0.6), false, 1.5)
	draw_line(Vector2(into_x, 0), Vector2(into_x, -ghost_height), Color(c, 0.9), 3.0)
	draw_string(ThemeDB.fallback_font, Vector2(into_x + 6.0, -ghost_height + 18.0), "进门点", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, c)  # i18n: skip（编辑器里画的辅助标签）
