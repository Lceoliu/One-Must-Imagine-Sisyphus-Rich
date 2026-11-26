@tool
class_name MistBand
extends Node2D
## 层间雾带（docs/v05/art-bible.md §4，借 depth_b1）：沿一条基线的横向柔雾，底部最浓、向上渐隐，颜色取天色（夜里冷雾）。
## - follow_ridge = false：基线 = 地形（平滑 smooth_m 米），画在世界空间里，放在 BackRidge 之后、Terrain 之前：
##   路面以下的部分被山体挡住，只露出路面上方那一截，把后景山肩和路面分开。
## - follow_ridge = true：作为 BackRidge 的子节点，基线 = 山肩轮廓（层空间），画在山肩之前：远景和山肩之间的雾。
## 网格按 CHUNK 米分块缓存（换天 / 换地形才重建），每帧只画屏幕内的块。材质（depth_mist.gdshader）里调颜色、浓度、疏密。

const PPM: float = 100.0
const STEP: float = 2.0
const CHUNK: int = 32

## 基线跟山肩（父节点 BackRidge 的轮廓）还是跟地形
@export var follow_ridge: bool = false
## 雾带在基线上方多高（米）、基线下方垫多少（米，被前面的层挡住，只为让最浓处落在基线上）
@export_range(0.5, 40.0, 0.1) var height_m: float = 3.6
@export_range(0.0, 10.0, 0.1) var below_m: float = 1.0
## 基线整体上下挪（米）
@export_range(-10.0, 10.0, 0.1) var offset_m: float = 0.0
## 跟地形时的平滑半径（米）：雾带比路面的折角圆一些
@export_range(0.0, 40.0, 0.5) var smooth_m: float = 6.0

var _world: World = null
var _built_for: Array = []
var _chunks: Array[ArrayMesh] = []
var _chunk_x: PackedFloat32Array = []
var _vis: Vector2 = Vector2.ZERO


## 每帧（WorldView → 本节点；follow_ridge 时由父节点 BackRidge 转调）：换了地形就重建网格，更新天色，重画
func depth_sync(wv: WorldView) -> void:
	if wv.sim == null or wv.sim.world == null:
		return
	var key: Array = _profile_key(wv.sim.world)
	if _world != wv.sim.world or key != _built_for:
		_world = wv.sim.world
		_built_for = key
		_build()
	var m: ShaderMaterial = material as ShaderMaterial
	if m != null:
		var sky: Array[Color] = DepthLayer.sky_pair(wv)
		m.set_shader_parameter(&"sky", sky[1])
		m.set_shader_parameter(&"tod_tint", BackgroundView.tint_at(wv.sim.tod(), wv.sim.night_k()))
	if follow_ridge and get_parent() is DepthLayer:
		_vis = (get_parent() as DepthLayer).visible_x(20.0)
	else:
		var vp: Vector2 = wv.get_viewport_rect().size
		var vh: float = vp.y / maxf(1e-4, wv.cam.zoom.y) / PPM
		var cx: float = wv.cam.position.x / PPM
		var hw: float = vh * vp.x / maxf(1.0, vp.y) * 0.5
		_vis = Vector2(cx - hw - 20.0, cx + hw + 20.0)
	queue_redraw()


## 网格依赖的参数（编辑器 / 测试改了参数时重建）
func _profile_key(w: World) -> Array:
	var rk: Variant = get_parent().get(&"profile_rev") if follow_ridge else 0
	return [w.length, height_m, below_m, offset_m, smooth_m, follow_ridge, rk]


## 基线：[起点 x, 步长, 高度表]（米）
func _baseline() -> Array:
	if follow_ridge:
		var par: Node = get_parent()
		var tab: Variant = par.get(&"profile")
		if tab is PackedFloat32Array and not (tab as PackedFloat32Array).is_empty():
			return [float(par.get(&"profile_x0")), float(par.get(&"profile_step")), tab]
		return []
	var x0: float = _world.left_end - 1500.0
	var x1: float = _world.summit_x + 1500.0
	var n: int = int((x1 - x0) / STEP) + 1
	return [x0, STEP, DepthLayer.smooth_profile(_world, x0, STEP, n, smooth_m)]


func _build() -> void:
	_chunks.clear()
	_chunk_x = []
	var b: Array = _baseline()
	if b.is_empty():
		return
	var x0: float = b[0]
	var st: float = b[1]
	var tab: PackedFloat32Array = b[2]
	var n: int = tab.size()
	var i0: int = 0
	while i0 < n - 1:
		var i1: int = mini(n - 1, i0 + CHUNK)
		var v: PackedVector2Array = []
		var uv: PackedVector2Array = []
		for i: int in range(i0, i1):
			var xa: float = x0 + i * st
			var xb: float = xa + st
			var ya: float = tab[i] + offset_m
			var yb: float = tab[i + 1] + offset_m
			var q: Array[Vector2] = [Vector2(xa, -(ya - below_m)) * PPM, Vector2(xb, -(yb - below_m)) * PPM,
				Vector2(xb, -(yb + height_m)) * PPM, Vector2(xa, -(ya + height_m)) * PPM]
			var u: Array[Vector2] = [Vector2(xa, 0.0), Vector2(xb, 0.0), Vector2(xb, 1.0), Vector2(xa, 1.0)]
			for k: int in [0, 1, 2, 0, 2, 3]:
				v.append(q[k])
				uv.append(u[k])
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_TEX_UV] = uv
		var m: ArrayMesh = ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_chunks.append(m)
		_chunk_x.append(x0 + i0 * st)
		i0 = i1
	_chunk_x.append(x0 + (n - 1) * st)


func _draw() -> void:
	var _pt: int = Prof.t()
	_draw_impl()
	Prof.add(&"mist.draw", _pt)


func _draw_impl() -> void:
	if _chunks.is_empty():
		return
	for i: int in _chunks.size():
		if _chunk_x[i + 1] < _vis.x or _chunk_x[i] > _vis.y:
			continue
		draw_mesh(_chunks[i], null)


## 测试 / 调试用：当前画了几块
func visible_chunks() -> int:
	var c: int = 0
	for i: int in _chunks.size():
		if not (_chunk_x[i + 1] < _vis.x or _chunk_x[i] > _vis.y):
			c += 1
	return c
