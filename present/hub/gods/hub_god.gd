@tool
class_name HubGod
extends Node2D
## 夜宴里会动的神：一张立绘 + Skeleton2D 骨骼蒙皮。每位神一个场景（present/hub/gods/<id>.tscn），在 hub.tscn 里实例化。
## 场景结构：
##   Shadow    脚下的接地阴影
##   Skeleton  Skeleton2D，下面是 Bone2D 骨头（编辑器里能拖；改完点检查器里的「重建网格与权重」）
##   Body      Polygon2D 蒙皮网格（按立绘透明通道自动生成，权重按"沿身体走到骨头的距离"自动算；也能在 UV 编辑器里手刷权重）
##   Anim      AnimationPlayer：idle（循环）+ 若干动作；轨道是骨头的 rotation / scale / position，在动画面板里改
## 原点 = 脚底中点（和原来 Sprite2D 的摆法一样，position 就是脚下那一点）；朝向反过来用 scale.x 取负。
## 运行时：待机动画随机起点和速度（同一种神不会齐步）；每隔一阵随机做个动作；西西弗斯走近时低头看他；和他说话时做 talk 动作。

## 测试 / 预览工具里置 true：不自己推进动画，由调用方 seek
static var frozen: bool = false

## 动画走到 strike_anim 的第 strike_at 秒时发出（赫菲斯托斯的锤子落下 → 夜宴让锻造炉的光闪一下）
signal struck

## 对应 hub.json 的 speakers / 站点 who（说话时找到自己做动作）
@export var who: String = ""
## 立绘（PNG）；Body 用的是它加上自动法线的 CanvasTexture
@export var texture: Texture2D
## 网格格子大小（贴图像素）。越小越贴合、顶点越多
@export_range(4, 48) var cell: int = 12
## 看向西西弗斯时转动的骨头
@export var head: NodePath
## 西西弗斯走近时头转的角度（度）；正负号 = 低头的方向（画像朝右时为正）
@export var look_deg: float = 4.0
## 多近开始看他（世界像素）
@export var look_range: float = 600.0
@export var idle_anim: StringName = &"idle"
## 随机做的动作（Anim 里的动画名）
@export var gestures: PackedStringArray = []
## 和西西弗斯说话时做的动作（空 = 随机挑一个 gestures）
@export var talk_anim: StringName = &""
## 两次随机动作之间隔多久（秒，范围）
@export var gesture_every: Vector2 = Vector2(7.0, 16.0)
## 打击节拍：哪个动画、第几秒（-1 = 没有）；到点发 struck 信号
@export var strike_anim: StringName = &""
@export var strike_at: float = -1.0
@export_tool_button("重建网格与权重", "Skeleton2D") var rebuild_button: Callable = rebuild

## HubView 每帧写入：西西弗斯的世界 x（NAN = 不在场）
var player_x: float = NAN
var _anim: AnimationPlayer = null
var _head: Bone2D = null
var _look: float = 0.0
var _look_applied: float = 0.0
var _next: float = 0.0
var _near: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func rebuild() -> void:
	RigBuilder.build(self)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_rng.seed = hash(name) ^ int(global_position.x)
	_anim = get_node_or_null("Anim") as AnimationPlayer
	_head = get_node_or_null(head) as Bone2D if not head.is_empty() else null
	if _anim == null:
		return
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_anim.animation_finished.connect(_on_finished)
	if _anim.has_animation(idle_anim):
		_anim.play(idle_anim)
		_anim.seek(_rng.randf() * _anim.current_animation_length, true)
		_anim.speed_scale = _rng.randf_range(0.9, 1.1)
	_next = _rng.randf_range(gesture_every.x * 0.4, gesture_every.y)


func _process(dt: float) -> void:
	if Engine.is_editor_hint() or frozen or _anim == null:
		return
	# 头的偏移是叠在动画上的：先撤掉上一帧加的，再推进动画，再加新的
	if _head != null:
		_head.rotation -= _look_applied
	var pos0: float = _anim.current_animation_position
	_anim.advance(dt)
	if strike_at >= 0.0 and _anim.current_animation == String(strike_anim):
		var pos1: float = _anim.current_animation_position
		if (pos0 < strike_at and pos1 >= strike_at) or (pos1 < pos0 and (pos0 < strike_at or pos1 >= strike_at)):
			struck.emit()
	_next -= dt
	if _next <= 0.0:
		_next = _rng.randf_range(gesture_every.x, gesture_every.y)
		if _anim.current_animation == String(idle_anim):
			gesture()
	var target: float = 0.0
	if not is_nan(player_x):
		var d: float = absf(player_x - global_position.x)
		var k: float = 1.0 - smoothstep(look_range * 0.35, look_range, d)
		target = deg_to_rad(look_deg) * k
		# 刚走近时有一半机会冲他做个动作（举杯、点头……）
		var near: bool = d < look_range * 0.45
		if near and not _near and _anim.current_animation == String(idle_anim) and _rng.randf() < 0.5:
			gesture()
		_near = near
	_look = lerpf(_look, target, 1.0 - exp(-dt * 2.5))
	if _head != null:
		_head.rotation += _look
		_look_applied = _look


## 随机做一个动作（没有动作就什么也不做）
func gesture(anim_name: StringName = &"") -> void:
	if _anim == null:
		return
	var nm: StringName = anim_name
	if nm == &"" and not gestures.is_empty():
		nm = StringName(gestures[_rng.randi() % gestures.size()])
	if nm == &"" or not _anim.has_animation(nm):
		return
	_anim.play(nm, 0.35)


## 西西弗斯来说话 / 买东西时
func react() -> void:
	gesture(talk_anim)


func _on_finished(anim_name: StringName) -> void:
	if anim_name != idle_anim and _anim.has_animation(idle_anim):
		_anim.play(idle_anim, 0.5)
