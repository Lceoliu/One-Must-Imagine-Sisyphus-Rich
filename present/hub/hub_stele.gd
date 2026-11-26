@tool
class_name HubStele
extends Sprite2D
## 提喀的盘口碑：金线 = 昨天的纪录（占登顶高度的比例），众神的羊拐骨钉在 金线 × mults 的位置。
## 刻度槽在碑上的范围：从碑底往上 groove_from 到 groove_to（占碑高的比例）。下注玩法还没做。

@export var chip_keys: PackedStringArray = ["chip2_thanatos", "chip2_ares", "chip2_hera", "chip2_athena", "chip2_hades"]
@export var chip_mults: PackedFloat32Array = [0.12, 0.6, 1.0, 1.08, 1.9]
@export var chip_height: float = 40.0
@export var groove_from: float = 0.167
@export var groove_to: float = 0.753
## 编辑器预览用的纪录比例
@export var preview_record: float = 0.46:
	set(v):
		preview_record = v
		queue_redraw()


## 刻度上比例 f（0 山脚 → 1 山顶）的位置（本节点坐标）
func groove_y(f: float) -> float:
	var h: float = float(texture.get_height()) if texture != null else 100.0
	return -h * (groove_from + clampf(f, 0.0, 1.0) * (groove_to - groove_from))


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var w: float = float(texture.get_width()) if texture != null else 50.0
	var y: float = groove_y(preview_record)
	draw_line(Vector2(-w * 0.25, y), Vector2(w * 0.25, y), Color(1.0, 0.75, 0.25), 6.0)
	for i: int in chip_mults.size():
		draw_circle(Vector2(-w * 0.18 if i % 2 == 0 else w * 0.18, groove_y(preview_record * chip_mults[i])), w * 0.07, Color(0.9, 0.6, 0.3, 0.8))
