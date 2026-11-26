@tool
class_name HubHelpers
extends Marker2D
## 门口等明天的帮手（= 已经买下的「众」）：从这个标记往右排，先斯巴达（推石）再辅助幽魂；
## 买了三头犬，SleepingDog 节点藏起来，醒着的那只站到队尾。编辑器里画出预计的站位。

@export var spacing: float = 85.0:
	set(v):
		spacing = v
		queue_redraw()
@export var max_each: int = 3:
	set(v):
		max_each = v
		queue_redraw()
@export var helper_height: float = 300.0
@export var spartans: PackedStringArray = ["hp2_spartan_idle", "hp2_spartan_salute"]
@export var ghosts: PackedStringArray = ["gh_help_water", "gh_help_fan", "gh_help_lamp"]
@export var dog_awake: String = "hub_cerberus_guard"
@export var dog_height: float = 230.0


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	for i: int in max_each * 2 + 1:
		var c: Color = Color(1.0, 0.8, 0.4) if i < max_each else (Color(0.7, 0.85, 1.0) if i < max_each * 2 else Color(0.9, 0.6, 0.4))
		draw_rect(Rect2(i * spacing - 25.0, -helper_height, 50.0, helper_height), Color(c, 0.5), false, 1.5)
