@tool
class_name BackRidge
extends DepthLayer
## 后景山肩（"瓶画层叠"第二层，docs/v05/art-bible.md §4，效果图 concept/depth_a2 / c1 / d1 / e1）：
## 同一座山在路后面隆起的肩部。轮廓 = 地形轻平滑（6 米）+ 大平滑和它的差（夹在 −dev_down_m..dev_up_m 之内，长陡坡上山肩比路缓、
## 在路的下坡一侧多露出来；夹住是为了坡脚 / 坎上不会一下抬得太高或埋进路里）+ 抬高（缓坡 lift_m、陡坡再加 lift_steep_m、平地 lift_foot_m）
## 再加一点起伏（roll_*）；近山顶时收下去（山顶后面只有天）。陡坡上平滑后的山肩比路缓，在路的下坡一侧露出来；
## 山脚城镇平地处变成向后退去的田野带（着色器画田垄、树篱）。
## 山肩里叠着几道小山（band_n 道，一档一档变深，每道底部一层薄雾）：顶边深度 = k · band_m + 起伏 hump()，
## 着色器（depth_ridge.gdshader）和装饰摆放用同一个公式，装饰就站在这些顶边上（第 0 排在山肩轮廓上）。
## 子节点（main.tscn 里，编辑器可见）：FarMist（远景和山肩之间的雾，MistBand follow_ridge）、Fill（山肩平涂，depth_ridge.gdshader）、
## Decor（沿山肩按海拔段撒的装饰，depth_sprite.gdshader 染淡）、Lamps（夜里远处村落的零星灯，不染色）。
## 装饰素材读 assets/native/ridge2/manifest.json（r2_<段>_<名>），没到位时用 FALLBACK 顶替。轮廓、网格、装饰摆放按地形缓存。

const MANIFEST: String = "res://assets/native/ridge2/manifest.json"
## 清单没到位时顶替的现有素材（格式同清单；height_m 是实际尺寸，画出来再乘 decor_scale）
const FALLBACK: Array = [
	{"key": "w2_olive_tree", "band": "foot", "kind": "tree", "height_m": 5.0, "weight": 3.0, "cluster": 3},
	{"key": "w2_olive_tree_b", "band": "foot", "kind": "tree", "height_m": 4.7, "weight": 2.0, "cluster": 3},
	{"key": "cypress", "band": "foot", "kind": "tree", "height_m": 8.3, "weight": 1.6, "cluster": 2},
	{"key": "w2_house", "band": "foot", "kind": "house", "height_m": 5.8, "weight": 0.5, "cluster": 1},
	{"key": "w2_haystack", "band": "foot", "kind": "farm", "height_m": 2.3, "weight": 0.6, "cluster": 2},
	{"key": "w2_olive_tree", "band": "low", "kind": "tree", "height_m": 5.0, "weight": 2.5, "cluster": 3},
	{"key": "w2_olive_tree_c", "band": "low", "kind": "tree", "height_m": 4.7, "weight": 2.0, "cluster": 3},
	{"key": "cypress", "band": "low", "kind": "tree", "height_m": 8.3, "weight": 1.4, "cluster": 2},
	{"key": "w2_grapevine", "band": "low", "kind": "vine", "height_m": 2.5, "weight": 1.0, "cluster": 3},
	{"key": "w2_house", "band": "low", "kind": "house", "height_m": 5.8, "weight": 0.35, "cluster": 1},
	{"key": "cypress", "band": "mid", "kind": "tree", "height_m": 9.0, "weight": 3.0, "cluster": 3},
	{"key": "w2_shrub", "band": "mid", "kind": "shrub", "height_m": 2.5, "weight": 1.5, "cluster": 2},
	{"key": "w2_olive_tree_b", "band": "mid", "kind": "tree", "height_m": 4.5, "weight": 0.8, "cluster": 2},
	{"key": "end_summit_rock", "band": "mid", "kind": "rock", "height_m": 3.6, "weight": 1.0, "cluster": 2},
	{"key": "w2_house", "band": "mid", "kind": "house", "height_m": 5.0, "weight": 0.25, "cluster": 1},
	{"key": "snow_pine", "band": "high", "kind": "tree", "height_m": 8.3, "weight": 3.0, "cluster": 3},
	{"key": "end_summit_rock", "band": "high", "kind": "rock", "height_m": 4.7, "weight": 1.6, "cluster": 2},
	{"key": "cypress", "band": "high", "kind": "tree", "height_m": 7.6, "weight": 0.5, "cluster": 2},
	{"key": "w2_shrine_bronze", "band": "high", "kind": "shrine", "height_m": 5.0, "weight": 0.15, "cluster": 1},
	{"key": "end_summit_rock", "band": "summit", "kind": "rock", "height_m": 5.4, "weight": 2.0, "cluster": 3},
	{"key": "snow_pine", "band": "summit", "kind": "tree", "height_m": 7.2, "weight": 1.0, "cluster": 2},
	{"key": "w2_column", "band": "summit", "kind": "ruin", "height_m": 7.6, "weight": 0.6, "cluster": 3},
	{"key": "fallen_column", "band": "summit", "kind": "ruin", "height_m": 2.5, "weight": 0.5, "cluster": 1},
]
## 夜里会亮灯的：kind 是这些，或 key 里带这些词（清单的 kind 目前一律是 "ridge"）
const LAMP_WORDS: PackedStringArray = ["house", "hut", "village", "shrine", "temple", "farm"]
const STEP: float = 2.0
const CHUNK: int = 32
const DEPTH: float = 400.0
const PAD: float = 0.3

@export_group("轮廓")
## 缓坡上抬高多少（米）；陡坡（平滑后坡度 0.3 → 0.9）再加多少；山脚平地（田野带）抬高多少
@export_range(0.0, 40.0, 0.1) var lift_m: float = 2.0
@export_range(0.0, 40.0, 0.1) var lift_steep_m: float = 4.0
@export_range(0.0, 40.0, 0.1) var lift_foot_m: float = 2.6
## 大平滑半径（米）：越大山肩越圆、长陡坡上越比路缓；和轻平滑的差夹在 [−dev_down_m, dev_up_m]（软夹）
@export_range(2.0, 120.0, 1.0) var smooth_m: float = 30.0
@export_range(0.0, 20.0, 0.1) var dev_up_m: float = 2.5
@export_range(0.0, 20.0, 0.1) var dev_down_m: float = 1.5
## 轮廓起伏（一个个小山包）的幅度（米）；平地上 × 0.6
@export_range(0.0, 20.0, 0.1) var roll_amp_m: float = 1.3
## 起伏的两个波长（米）：轮廓和小山顶边共用
@export_range(4.0, 400.0, 0.5) var hump_a: float = 37.0
@export_range(4.0, 400.0, 0.5) var hump_b: float = 16.3
## 近山顶时往下收：从山顶前多少米开始收、收到山顶时比地形低多少米
@export_range(0.0, 400.0, 1.0) var summit_fade_m: float = 140.0
@export_range(0.0, 200.0, 1.0) var summit_drop_m: float = 40.0

@export_group("小山")
## 山肩里叠几道小山、每道的间距（米）、顶边起伏幅度（米；平地上 × 0.3，压扁成田块）
@export_range(0, 6) var band_n: int = 4
@export_range(0.3, 6.0, 0.05) var band_m: float = 1.3
@export_range(0.0, 3.0, 0.05) var band_amp: float = 0.55

@export_group("装饰")
## 每组装饰之间的间距（米，随机）；越往下（越近）的小山上间距 × face_gap_k^排号
@export_range(0.5, 60.0, 0.5) var decor_gap_min: float = 2.0
@export_range(0.5, 120.0, 0.5) var decor_gap_max: float = 8.0
@export_range(0.5, 4.0, 0.05) var face_gap_k: float = 1.25
## 成组的机会（成组时 2..清单 cluster 个）
@export_range(0.0, 1.0, 0.01) var cluster_chance: float = 0.45
## 整体大小倍率（远处的东西要小：清单里是实际尺寸）、大小随机幅度、每往下一道小山放大多少
@export_range(0.05, 3.0, 0.01) var decor_scale: float = 0.19
@export_range(0.0, 0.6, 0.01) var size_jitter: float = 0.18
@export_range(0.0, 1.0, 0.01) var row_grow: float = 0.15
## 装饰站在第几道小山的顶边上（0 = 山肩轮廓）：最多排到这一道
@export_range(0, 6) var decor_rows: int = 3

@export_group("夜")
## 有灯的人家占比、灯的大小（屏幕像素）
@export_range(0.0, 1.0, 0.01) var lamp_share: float = 0.6
@export_range(0.5, 8.0, 0.1) var lamp_px: float = 2.8

## 山肩轮廓（层空间，米）：profile_x0 起每 profile_step 米一个点；profile_rev 每次重建 +1（FarMist 据此重建）
var profile: PackedFloat32Array = []
var profile_x0: float = 0.0
var profile_step: float = STEP
var profile_rev: int = 0
var _slope: PackedFloat32Array = []   # 1 − 平地程度（每个采样点）
var _ground: PackedFloat32Array = []  # 地形原始高度（每个采样点，按海拔挑素材）
var _world: World = null
var _key: Array = []
var _chunks: Array[ArrayMesh] = []
var _chunk_x: PackedFloat32Array = []
## 装饰摆放：rows[r] = 按 x 排序的 [{x, base, h, key, flip, kind, lamp}]
var rows: Array = []
var _vis: Vector2 = Vector2.ZERO
var _night: float = 0.0
var _zs: float = 1.0
var _t: float = 0.0
var fill: Node2D
var decor: Node2D
var lamps: Node2D
var far_mist: MistBand


func _ready() -> void:
	fill = _child("Fill")
	decor = _child("Decor")
	lamps = _child("Lamps")
	far_mist = get_node_or_null("FarMist") as MistBand
	if Engine.is_editor_hint():
		return
	if not fill.draw.is_connected(_draw_fill):
		fill.draw.connect(_draw_fill)
	if not decor.draw.is_connected(_draw_decor):
		decor.draw.connect(_draw_decor)
	if not lamps.draw.is_connected(_draw_lamps):
		lamps.draw.connect(_draw_lamps)


func _child(nm: String) -> Node2D:
	var n: Node2D = get_node_or_null(nm) as Node2D
	if n == null:
		n = Node2D.new()
		n.name = nm
		add_child(n)
	return n


func depth_sync(wv: WorldView) -> void:
	super(wv)
	if wv.sim == null or wv.sim.world == null:
		return
	_t = wv.t
	var key: Array = [wv.sim.world.length, lift_m, lift_steep_m, lift_foot_m, smooth_m, dev_up_m, dev_down_m, roll_amp_m, hump_a, hump_b, summit_fade_m, summit_drop_m,
		band_n, band_m, band_amp, decor_gap_min, decor_gap_max, face_gap_k, cluster_chance, decor_scale, size_jitter, row_grow, decor_rows, band_blend]
	if _world != wv.sim.world or key != _key:
		_world = wv.sim.world
		_key = key
		rebuild(_world)
	_vis = visible_x(12.0)
	_night = wv.sim.night_k()
	_zs = 1.0 / maxf(1e-4, wv.cam.zoom.x * factor)
	var sky: Array[Color] = DepthLayer.sky_pair(wv)
	# 山肩在画面中下部：天色取天顶到地平线的 75% 处
	var sky_c: Color = sky[0].lerp(sky[1], 0.75)
	var tint: Color = BackgroundView.tint_at(wv.sim.tod(), _night)
	var pxs: float = WorldView.px_per_logical(wv)
	for n: Node2D in [fill, decor]:
		var m: ShaderMaterial = n.material as ShaderMaterial
		if m != null:
			m.set_shader_parameter(&"sky", sky_c)
			m.set_shader_parameter(&"tod_tint", tint)
			m.set_shader_parameter(&"px_scale", pxs)
	if far_mist != null:
		far_mist.depth_sync(wv)
	fill.queue_redraw()
	decor.queue_redraw()
	lamps.queue_redraw()


## 按地形算轮廓、网格、装饰摆放（换天 / 改参数时调；测试也直接调）
func rebuild(w: World) -> void:
	_world = w
	profile_x0 = w.left_end - 1500.0
	profile_step = STEP
	var n: int = int((w.summit_x + 1500.0 - profile_x0) / STEP) + 1
	var ysm: PackedFloat32Array = DepthLayer.smooth_profile(w, profile_x0, STEP, n, smooth_m)
	var ys6: PackedFloat32Array = DepthLayer.smooth_profile(w, profile_x0, STEP, n, 6.0)
	profile = PackedFloat32Array()
	profile.resize(n)
	_slope = PackedFloat32Array()
	_slope.resize(n)
	_ground = PackedFloat32Array()
	_ground.resize(n)
	for i: int in n:
		var x: float = profile_x0 + i * STEP
		var yr: float = w.y_at_x(x)
		_ground[i] = yr
		var fk: float = DepthLayer.foot_k_at(yr)
		_slope[i] = 1.0 - fk
		var sl: float = absf(ysm[mini(n - 1, i + 1)] - ysm[maxi(0, i - 1)]) / (2.0 * STEP)
		var steep: float = DepthLayer._smooth(0.3, 0.9, sl)
		var lift: float = lerpf(lift_m + lift_steep_m * steep, lift_foot_m, fk)
		var roll: float = roll_amp_m * lerpf(1.0, 0.6, fk) * (hump(x, 0.0) - 0.5) * 2.0
		var sk: float = DepthLayer._smooth(w.summit_x - summit_fade_m, w.summit_x, x)
		profile[i] = ys6[i] + soft_clamp(ysm[i] - ys6[i], dev_down_m, dev_up_m) + (lift + roll) * (1.0 - sk) - summit_drop_m * sk
	profile_rev += 1
	_build_mesh()
	_place_decor(w)
	var m: ShaderMaterial = fill.material as ShaderMaterial if fill != null else null
	if m != null:
		m.set_shader_parameter(&"band_m", band_m)
		m.set_shader_parameter(&"band_amp", band_amp)
		m.set_shader_parameter(&"band_n", float(band_n))
		m.set_shader_parameter(&"hump_a", hump_a)
		m.set_shader_parameter(&"hump_b", hump_b)


## 软夹：v 夹到 (−lo, hi)，越靠近边界越收（tanh）
static func soft_clamp(v: float, lo: float, hi: float) -> float:
	if v >= 0.0:
		return hi * tanh(v / hi) if hi > 1e-4 else 0.0
	return lo * tanh(v / lo) if lo > 1e-4 else 0.0


## 起伏（0..1，圆顶、尖谷：一个个小山包）。和 depth_ridge.gdshader 的 hump() 同一公式
func hump(x: float, k: float) -> float:
	return 0.6 * pow(absf(sin(x * TAU / hump_a + 0.7 + k * 1.7)), 0.7) + 0.4 * pow(absf(sin(x * TAU / hump_b + 2.1 + k * 2.9)), 0.7)


## 第 k 道小山顶边在轮廓线下方的深度（米；k = 0 是轮廓线本身）。和着色器一致：逐道算、不许比上一道浅于 0.25 米
func band_depth(x: float, k: int) -> float:
	if k <= 0:
		return 0.0
	var amp: float = band_amp * lerpf(0.3, 1.0, DepthLayer.sample(_slope, profile_x0, profile_step, x))
	var top: float = 0.0
	for i: int in range(1, k + 1):
		top = maxf(i * band_m + amp * (hump(x, float(i)) - 0.5) * 2.0, top + 0.25)
	return top


## 层空间 x 处的山肩轮廓高度（米）
func ridge_y(x: float) -> float:
	return DepthLayer.sample(profile, profile_x0, profile_step, x)


func _build_mesh() -> void:
	_chunks.clear()
	_chunk_x = []
	var n: int = profile.size()
	var i0: int = 0
	while i0 < n - 1:
		var i1: int = mini(n - 1, i0 + CHUNK)
		var v: PackedVector2Array = []
		var uv: PackedVector2Array = []
		var cols: PackedColorArray = []
		for i: int in range(i0, i1):
			var xa: float = profile_x0 + i * STEP
			var xb: float = xa + STEP
			var ya: float = profile[i]
			var yb: float = profile[i + 1]
			var q: Array[Vector2] = [Vector2(xa, -(ya + PAD)) * PPM, Vector2(xb, -(yb + PAD)) * PPM,
				Vector2(xb, -(yb - DEPTH)) * PPM, Vector2(xa, -(ya - DEPTH)) * PPM]
			var u: Array[Vector2] = [Vector2(xa, -PAD), Vector2(xb, -PAD), Vector2(xb, DEPTH), Vector2(xa, DEPTH)]
			var c: Array[Color] = [Color(_slope[i], 0, 0), Color(_slope[i + 1], 0, 0), Color(_slope[i + 1], 0, 0), Color(_slope[i], 0, 0)]
			for k: int in [0, 1, 2, 0, 2, 3]:
				v.append(q[k])
				uv.append(u[k])
				cols.append(c[k])
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_COLOR] = cols
		var m: ArrayMesh = ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_chunks.append(m)
		_chunk_x.append(profile_x0 + i0 * STEP)
		i0 = i1
	_chunk_x.append(profile_x0 + (n - 1) * STEP)


## 沿山肩撒装饰：第 0 排在山肩轮廓上，第 r 排站在第 r 道小山的顶边上（越往下越近：稍大、稍稀）。
## 按海拔段（交错混合）挑清单条目，偶尔成组。
func _place_decor(w: World) -> void:
	rows = []
	var bands: Dictionary = DepthLayer.by_band(DepthLayer.load_manifest(MANIFEST, FALLBACK))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(w.length * 1000.0) + 17
	var x_lo: float = w.left_end - 220.0
	var x_hi: float = w.summit_x + 160.0
	for r: int in mini(decor_rows, band_n) + 1:
		var list: Array[Dictionary] = []
		var gk: float = pow(face_gap_k, r)
		var sk: float = decor_scale * (1.0 + row_grow * r)
		var x: float = x_lo + rng.randf() * decor_gap_max
		while x < x_hi:
			var alt: float = w.y_at_x(x)
			var fk: float = DepthLayer.foot_k_at(alt)
			var band: StringName = DepthLayer.band_name(alt, fk, rng.randf(), band_blend)
			var e: Dictionary = DepthLayer.pick_weighted(bands.get(band, [] as Array[Dictionary]), rng.randf())
			var adv: float = rng.randf_range(decor_gap_min, decor_gap_max) * gk
			if e.is_empty() or (r > 0 and bool(e["floating"])):
				x += adv
				continue
			var cnt: int = 1
			if int(e["cluster"]) > 1 and rng.randf() < cluster_chance:
				cnt = rng.randi_range(2, int(e["cluster"]))
			var cx: float = x
			for k: int in cnt:
				var h: float = float(e["height_m"]) * sk * (1.0 + rng.randf_range(-size_jitter, size_jitter))
				var key: StringName = e["key"]
				var wd: float = h * SpriteDB.aspect(key)
				var it: Dictionary = {"x": cx, "h": h, "w": wd, "key": key, "flip": rng.randf() < 0.5, "float": bool(e["floating"]),
					"row": r, "lamp": has_lamp(e) and rng.randf() < lamp_share, "ph": rng.randf() * TAU}
				it["base"] = _decor_base(it, r)
				list.append(it)
				cx += wd * rng.randf_range(0.45, 0.8)
			x = cx + adv
		rows.append(list)


## 这种装饰夜里会不会亮灯（人家、神龛）
static func has_lamp(e: Dictionary) -> bool:
	var k: String = (String(e["kind"]) + " " + String(e["key"])).to_lower()
	for wd: String in LAMP_WORDS:
		if k.contains(wd):
			return true
	return false


## 装饰的底边高度（层空间米）：站在第 r 道小山的顶边上，两端里低的那头再沉一点（坡上不悬空）；云飘在轮廓线上方
func _decor_base(it: Dictionary, r: int) -> float:
	var x: float = it["x"]
	if bool(it["float"]):
		return ridge_y(x) + float(it["h"]) * (0.8 + 0.6 * fposmod(float(it["ph"]), 1.0))
	var hw: float = float(it["w"]) * 0.3
	var y: float = INF
	for xx: float in [x - hw, x, x + hw]:
		y = minf(y, ridge_y(xx) - band_depth(xx, r))
	return y - float(it["h"]) * 0.05


func _draw_fill() -> void:
	if _chunks.is_empty():
		return
	for i: int in _chunks.size():
		if _chunk_x[i + 1] < _vis.x or _chunk_x[i] > _vis.y:
			continue
		fill.draw_mesh(_chunks[i], null)


## 二分：x 有序的数组里第一个 x ≥ v 的下标
static func lower_bound(list: Array, v: float) -> int:
	var lo: int = 0
	var hi: int = list.size()
	while lo < hi:
		var m: int = (lo + hi) >> 1
		if float((list[m] as Dictionary)["x"]) < v:
			lo = m + 1
		else:
			hi = m
	return lo


func _draw_decor() -> void:
	for list: Array in rows:
		var i: int = lower_bound(list, _vis.x - 10.0)
		while i < list.size():
			var it: Dictionary = list[i]
			i += 1
			var x: float = it["x"]
			if x > _vis.y + 10.0:
				break
			var tex: Texture2D = SpriteDB.tex_plain(it["key"])   # depth_sprite 着色器按单图 0–1 坐标淡出，不能用图集
			if tex == null:
				continue
			var h: float = float(it["h"]) * PPM
			var wd: float = float(it["w"]) * PPM
			decor.draw_set_transform(Vector2(x * PPM, -float(it["base"]) * PPM), 0.0, Vector2(-1.0 if bool(it["flip"]) else 1.0, 1.0))
			decor.draw_texture_rect(tex, Rect2(-wd / 2.0, -h, wd, h), false)
	decor.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 夜里远处人家的零星灯（暖色小方点 + 光晕，按各自延迟逐盏亮起、轻轻闪）
func _draw_lamps() -> void:
	if _night < 0.3:
		return
	for list: Array in rows:
		var i: int = lower_bound(list, _vis.x)
		while i < list.size():
			var it: Dictionary = list[i]
			i += 1
			if float(it["x"]) > _vis.y:
				break
			if not bool(it["lamp"]):
				continue
			var on: float = clampf((_night - 0.35 - 0.4 * fposmod(float(it["ph"]), 1.0)) / 0.15, 0.0, 1.0)
			if on <= 0.0:
				continue
			var a: float = on * 0.75 * (0.85 + 0.15 * sin(_t * 1.3 + float(it["ph"])))
			var c: Vector2 = Vector2(float(it["x"]) + float(it["w"]) * 0.12 * (1.0 if bool(it["flip"]) else -1.0), -(float(it["base"]) + float(it["h"]) * 0.32)) * PPM
			var sz: float = lamp_px * _zs
			lamps.draw_texture_rect(Glow.tex(), Rect2(c - Vector2(sz, sz) * 3.0, Vector2(sz, sz) * 6.0), false, Color(Palette.GOLD, a * 0.3))
			lamps.draw_rect(Rect2(c - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(Palette.GOLD, a))


## 测试 / 调试用：当前画了几块山肩网格
func visible_chunks() -> int:
	var c: int = 0
	for i: int in _chunks.size():
		if not (_chunk_x[i + 1] < _vis.x or _chunk_x[i] > _vis.y):
			c += 1
	return c
