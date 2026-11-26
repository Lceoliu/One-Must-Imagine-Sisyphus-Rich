class_name DawnShot
extends CanvasLayer
## 天亮的运镜（纯表现，不影响模拟——播放时 main 把模拟暂停）：从黑里淡入，镜头先停在最左边的冥府大门，
## 再一路往右扫过山脚的城镇全景、一边拉近，最后落到西西弗斯和石头上（= 白天镜头的起点），然后交还给正常跟随。
## 大门 → 城镇 → 西西弗斯是一条连续的曲线：只在起步和落位时缓入缓出，经过城镇不停，只放慢到 town_pace。
## 空格 / 回车 / 推石键 / 鼠标左键跳过（快进到结尾）。第一天也播：让玩家一开始就知道左边有冥府大门、看到整个城镇。
## 场景 present/world/dawn_shot.tscn：Fade（黑幕）、Hint（右下角"跳过"提示）。

signal finished

## 各段时长（秒）：黑幕淡开、停在大门、扫过城镇、落到西西弗斯
@export var fade_t: float = 1.0
@export var hold_t: float = 1.3
@export var town_t: float = 2.2
@export var land_t: float = 3.8
## 大门那一镜的视野高是门高的几倍；城镇那一镜的视野高（米）
@export var gate_view_k: float = 1.7
@export var town_view_h: float = 24.0
## 经过城镇时的速度（相对于平均速度；1 = 不放慢，越小在城镇上空停留越久，但不会停下）
@export_range(0.2, 1.5, 0.05) var town_pace: float = 1.1
## 跳过时快进的倍速
@export var skip_speed: float = 6.0

var _world: WorldView = null
var _keys: Array[Vector4] = []        # (x, y, 视野高, 到这一帧的时刻)
var _t: float = 0.0
var _speed: float = 1.0
var _done: bool = true

@onready var _fade: ColorRect = $Fade
@onready var _hint: Label = $Hint


static func create() -> DawnShot:
	return SceneCache.make("res://present/world/dawn_shot.tscn") as DawnShot


## 按今天的地形排好镜头：大门 → 城镇中间 → 白天镜头的起点（sim 的镜头目标加上构图偏移）
func play(world: WorldView, sim: SimGame) -> void:
	_world = world
	var w: World = sim.world
	var gate: Dictionary = sim.gate
	var gx: float = float(gate.get("x", w.gate_x)) + 4.0
	var gh: float = float(gate.get("h", 24.0))
	var vps: Vector2 = world.get_viewport_rect().size
	var aspect: float = vps.x / maxf(1.0, vps.y)
	var fo: Vector2 = WorldView.frame_offset(w, sim.cam_tx, sim.cam_ty, sim.cam_view_h, aspect)
	var end: Vector3 = Vector3(sim.cam_tx + fo.x, sim.cam_ty + fo.y, sim.cam_view_h)
	var gate_vh: float = gh * gate_view_k
	var town_x: float = (gx + minf(end.x, 0.0)) * 0.5
	var t1: float = fade_t * 0.5 + hold_t
	var t2: float = t1 + town_t
	var t3: float = t2 + land_t
	_keys = [Vector4(gx, gate_vh * 0.42, gate_vh, 0.0), Vector4(gx, gate_vh * 0.42, gate_vh, t1),
		Vector4(town_x, w.y_at_x(town_x) + town_view_h * 0.34, town_view_h, t2), Vector4(end.x, end.y, end.z, t3)]
	_t = 0.0
	_speed = 1.0
	_done = false
	_fade.color.a = 1.0
	_hint.visible = true
	_apply()


func skip() -> void:
	_speed = skip_speed


## 立刻停下（不再接管镜头）；外面随后把它释放
func stop() -> void:
	_done = true
	set_process(false)
	if _world != null:
		_world.cine = Vector3(NAN, NAN, NAN)


func playing() -> bool:
	return not _done


func _process(dt: float) -> void:
	if _done:
		return
	_t += dt * _speed
	_fade.color.a = 1.0 - smoothstep(0.0, fade_t, _t)
	_apply()
	if _t >= _keys[_keys.size() - 1].w:
		_done = true
		_hint.visible = false
		_fade.color.a = 0.0
		if _world != null:
			_world.cine = Vector3(NAN, NAN, NAN)
		finished.emit()


## 镜头位置：关键帧之间用三次埃尔米特曲线连起来。停住的帧（和前一帧相同，比如大门那一镜）、第一帧、最后一帧速度为 0；
## 中间经过的帧（城镇）速度不为 0，按前后两帧的走向定（某个分量在这里折返时那个分量速度取 0，不冲过头），再乘 town_pace
func _apply() -> void:
	if _world == null or _keys.size() < 2:
		return
	var k: int = 0
	while k < _keys.size() - 2 and _t > _keys[k + 1].w:
		k += 1
	var a: Vector4 = _keys[k]
	var b: Vector4 = _keys[k + 1]
	var h: float = maxf(0.001, b.w - a.w)
	var u: float = clampf((_t - a.w) / h, 0.0, 1.0)
	var pa: Vector3 = _pt(a)
	var pb: Vector3 = _pt(b)
	var ma: Vector3 = _vel(k)
	var mb: Vector3 = _vel(k + 1)
	var u2: float = u * u
	var u3: float = u2 * u
	var p: Vector3 = pa * (2.0 * u3 - 3.0 * u2 + 1.0) + ma * h * (u3 - 2.0 * u2 + u) + pb * (-2.0 * u3 + 3.0 * u2) + mb * h * (u3 - u2)
	_world.cine = Vector3(p.x, p.y, exp(p.z))


## 关键帧的 (x, y, ln 视野高)：视野高按对数插值，拉近拉远的速度均匀
func _pt(q: Vector4) -> Vector3:
	return Vector3(q.x, q.y, log(q.z))


## 第 i 个关键帧处的速度（每秒）
func _vel(i: int) -> Vector3:
	if i <= 0 or i >= _keys.size() - 1:
		return Vector3.ZERO
	var p0: Vector3 = _pt(_keys[i - 1])
	var p1: Vector3 = _pt(_keys[i])
	var p2: Vector3 = _pt(_keys[i + 1])
	if p0.is_equal_approx(p1) or p1.is_equal_approx(p2):
		return Vector3.ZERO
	var d0: Vector3 = (p1 - p0) / maxf(0.001, _keys[i].w - _keys[i - 1].w)
	var d1: Vector3 = (p2 - p1) / maxf(0.001, _keys[i + 1].w - _keys[i].w)
	var v: Vector3 = Vector3.ZERO
	for c: int in 3:
		# 单调：前后两段同向才有速度，且不超过两段平均斜率的 3 倍（不冲过头）
		if d0[c] * d1[c] > 0.0:
			v[c] = signf(d0[c]) * minf((absf(d0[c]) + absf(d1[c])) * 0.5 * town_pace, 3.0 * minf(absf(d0[c]), absf(d1[c])))
	return v
