@tool
class_name HubSwing
extends Node2D
## 吊灯轻轻摆：整个节点（链子、灯身、灯光、光晕）绕链子顶端摆动。挂在 Lamp* 节点上；摆放时的位置就是静止位置。
## 链子顶端 = 子节点 Chain（Line2D）的第一个点，没有链子时用 pivot_y。编辑器里勾上 preview 才摆（默认静止，方便摆放）。

## 摆幅（度）
@export var amplitude: float = 1.6
## 一个来回的秒数
@export var period: float = 4.2
## 相位（秒），几盏灯错开
@export var phase: float = 0.0
## 没有 Chain 时，悬挂点相对本节点的 y
@export var pivot_y: float = -500.0
## 编辑器里也摆起来看看
@export var preview: bool = false:
	set(v):
		preview = v
		if not v and _has_rest:
			position = _rest
			rotation = 0.0

var _rest: Vector2 = Vector2.ZERO
var _has_rest: bool = false
var _t: float = 0.0


func _ready() -> void:
	_rest = position
	_has_rest = true


## 编辑器预览摆动时，存场景前先放回静止位置（不把摆到一半的位置存进 .tscn）
func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE and _has_rest and preview:
		position = _rest
		rotation = 0.0


func _pivot() -> Vector2:
	var ch: Line2D = get_node_or_null("Chain") as Line2D
	if ch != null and ch.points.size() > 0:
		return ch.points[0]
	return Vector2(0.0, pivot_y)


func _process(dt: float) -> void:
	if Engine.is_editor_hint() and not preview:
		return
	_t += dt
	var a: float = deg_to_rad(amplitude) * sin(TAU * (_t + phase) / maxf(0.1, period))
	# 绕悬挂点 p 转 a：节点原点从 rest 挪到 rest + p − p.rotated(a)
	var p: Vector2 = _pivot()
	rotation = a
	position = _rest + p - p.rotated(a)
