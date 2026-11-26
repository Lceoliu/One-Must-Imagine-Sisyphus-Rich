@tool
class_name HubParallax
extends Node2D
## 夜宴的一层视差。子节点按"镜头正对它时出现在哪"来摆（编辑器里看到的就是那个位置）；
## 运行时 HubView 每帧调 apply(镜头中心 x)：子节点 x = factor·摆放 x + (1 − factor)·镜头中心。
## factor < 1 远景（走得慢），1 = 主层，> 1 近景（走得快）。

## 视差系数
@export var factor: float = 1.0
var _base: Dictionary = {}   # 子节点 → 摆放时的 x


func apply(center_x: float) -> void:
	if Engine.is_editor_hint():
		return
	for c: Node in get_children():
		var n: Node2D = c as Node2D
		if n == null:
			continue
		if not _base.has(n):
			_base[n] = n.position.x
		n.position.x = factor * float(_base[n]) + (1.0 - factor) * center_x
