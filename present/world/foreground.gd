@tool
class_name Foreground
extends DepthLayer
## 前景（"瓶画层叠"最近的一层，docs/v05/art-bible.md §4）：比路面更近的暗色大剪影，略虚、低对比、不抢镜；
## 从西西弗斯、石头前面掠过时失焦（像电影镜头焦点在人身上：更虚、只轻微变透，depth_sprite.gdshader 逐像素做）。
## 少而克制（参考 concept/depth_a2.png：只在画面角落出现一两组，中间留空）：沿 x 隔很远（gap_*）才放一组，
## 一组 = 一个主件（树、岩堆、断柱，清单 role = anchor）+ 脚边 0..side_max 个小件（龙舌兰、蓟、石块，role = side）。
## 按海拔段从 assets/native/fg2/manifest.json（f2_<段>_<名>）挑，没到位时用 FALLBACK 顶替；摆放按地形缓存。
## 位置（2026-10-14 定）：底边永远在画面底边以下（被画框截住，读作"站在画外的近处"），任何时候都看不到它站在什么上——
## 不要把底边藏进山体饰带下的黑釉里：刻线照样画出来，树根、石块就悬在黑色里（用户："树悬浮在虚空上"）。
## 运动是真视差：每件刚进画面（左边缘越过画面右边缘）时，定下它的底边在路面以下多深（在画面右边缘那一竖条正好沉到画面底边以下 sink 个物件高），
## 之后这个深度不变——镜头沿坡往上走，它和路面一起往左下流（快 factor 倍），坡上越往左路面越低，它就越沉，最后从画面底边沉出去。
## 保险：底边任何时候都不高过画面底边（镜头拉远、往回滚这些情况）；顶最多高出路面 rise_max_m（不挡人）；整件都落在饰带下的黑釉里的不画。
## 陡坡（> steep_deg）：画面右下是一大块黑色山体，普通大小的近景进来时整个在黑里，所以陡坡上只摆高而窄的大件（柏树、石笋、枯树），
## 按坡度放大到树冠伸出黑釉、衬在陶土饰带上（show_* 米），不配脚边小件。

const MANIFEST: String = "res://assets/native/fg2/manifest.json"
## 清单没到位时顶替的现有素材（格式同清单；height_m = 层空间高度，画面上再乘深度系数）
const FALLBACK: Array = [
	{"key": "w2_olive_tree", "band": "low", "role": "anchor", "height_m": 5.0, "weight": 1.0},
	{"key": "w2_shrub", "band": "low", "role": "side", "height_m": 1.4, "weight": 1.0},
	{"key": "end_summit_rock", "band": "high", "role": "anchor", "height_m": 2.6, "weight": 1.0},
	{"key": "fallen_column", "band": "summit", "role": "anchor", "height_m": 1.8, "weight": 1.0},
]
const STEP: float = 2.0

@export_group("摆放")
## 相邻两组之间的空档（层空间米，随机；画面宽约合层空间 18 米，平均一屏不到一组）
@export_range(1.0, 200.0, 0.5) var gap_min_m: float = 14.0
@export_range(1.0, 300.0, 0.5) var gap_max_m: float = 30.0
## 主件脚边配小件的机会、最多几个；小件中心离主件中心多远（占主件宽的比例）
@export_range(0.0, 1.0, 0.01) var side_chance: float = 0.75
@export_range(0, 3) var side_max: int = 2
@export_range(0.0, 1.0, 0.01) var side_off_min: float = 0.2
@export_range(0.0, 1.0, 0.01) var side_off_max: float = 0.42
## 大小倍率、随机幅度
@export_range(0.1, 4.0, 0.01) var size_mul: float = 1.0
@export_range(0.0, 0.6, 0.01) var size_jitter: float = 0.2

@export_group("高度")
## 进入画面时底边沉到画面底边以下几个物件高（随机；越大露得越少）
@export_range(0.0, 1.0, 0.01) var sink_min: float = 0.05
@export_range(0.0, 1.0, 0.01) var sink_max: float = 0.3
## 露出来的部分最多高出路面多少米（画面上，物件整个宽度上都算）：只从西西弗斯脚边、石头底下掠过，不挡住人
@export_range(0.0, 10.0, 0.05) var rise_max_m: float = 0.9
## 坡度（度，按前后 slope_span_m 米平均）超过 steep_deg 算陡坡：只摆高而窄（宽 / 高 ≤ tall_aspect）的大件，按坡度放大
@export_range(0.0, 90.0, 0.5) var steep_deg: float = 25.0
@export_range(1.0, 60.0, 0.5) var slope_span_m: float = 12.0
@export_range(0.2, 2.0, 0.01) var tall_aspect: float = 0.8
## 陡坡大件放大时按这个构图估算：画面中线处路面在画面底边以上几成视野高（白天镜头大约这么多）
@export_range(0.0, 1.0, 0.01) var frame_path_k: float = 0.22
## 陡坡大件进入画面时伸出黑釉多少米（随机）、最多放大几倍（再大贴图太糊，宁可不放）
@export_range(0.0, 10.0, 0.1) var show_min_m: float = 3.0
@export_range(0.0, 10.0, 0.1) var show_max_m: float = 4.8
@export_range(1.0, 6.0, 0.1) var scale_max: float = 3.0
## 饰带厚（米，垂直地表量）= 山体着色器的 band_m + band_h_m；饰带以下是黑釉
@export_range(0.0, 20.0, 0.05) var glaze_m: float = 3.55
## 路面线平滑多少米
@export_range(0.0, 60.0, 0.5) var smooth_m: float = 4.0
## 视野拉远时前景跟着放大一点：zoom_k = lerp(1, 视野高 / view_ref_h, view_gain)
@export_range(5.0, 60.0, 0.5) var view_ref_h: float = 13.0
@export_range(0.0, 1.0, 0.01) var view_gain: float = 0.5
## 物件底部渐隐的比例（物件高的几成）：任何时候都看不到一条硬底边
@export_range(0.0, 0.8, 0.01) var base_fade: float = 0.3

@export_group("显示")
## 虚化：额外模糊半径（屏幕像素）、mip 偏移（档）
@export_range(0.0, 8.0, 0.1) var blur_px: float = 1.1
@export_range(0.0, 4.0, 0.05) var mip_bias: float = 0.5

@export_group("虚焦")
## 西西弗斯、石头、正在交互的物件从前景后面经过时，前景物件"失焦"（像电影镜头焦点在人身上）：
## 越近虚化越重（额外模糊 defocus_px 屏幕像素），只轻微变透（最低 min_alpha）
## 西西弗斯：完全淡出的半径（米，以身体中心算）、渐变宽度（米）
@export_range(0.0, 10.0, 0.1) var fade_sis_m: float = 1.7
@export_range(0.0, 10.0, 0.1) var fade_soft_m: float = 2.2
## 石头：完全淡出的半径 = 石头半径 × fade_stone_k + 0.4 米
@export_range(0.0, 4.0, 0.05) var fade_stone_k: float = 1.15
## 交互物件（神龛、赐福祭坛、剧情人物）：西西弗斯走到 fade_obj_near_m 米以内时也淡出，半径 fade_obj_m 米（以物件中段算）
@export_range(0.0, 30.0, 0.5) var fade_obj_near_m: float = 9.0
@export_range(0.0, 10.0, 0.1) var fade_obj_m: float = 2.4
## 失焦时额外的模糊半径（屏幕像素）、最低不透明度
@export_range(0.0, 40.0, 0.5) var defocus_px: float = 14.0
@export_range(0.0, 1.0, 0.01) var min_alpha: float = 0.78
## HUD 关键区域（画面比例坐标）：底部提示条、右侧海拔柱
@export var hud_zones: Array[Rect2] = [Rect2(0.3, 0.9, 0.4, 0.1), Rect2(0.955, 0.0, 0.045, 1.0)]
## 区域边缘渐变宽（画面高的比例）
@export_range(0.0, 0.3, 0.005) var zone_soft: float = 0.04

## 摆放：按 x 排序的 [{x, key, h, w, flip, band, z, cid}]（层空间米，h、w 未乘 zoom_k；z = 0 主件 / 1 小件，cid = 第几组）
var items: Array[Dictionary] = []
var _ground: PackedFloat32Array = []
var _g_x0: float = 0.0
var _world: World = null
var _key: Array = []
var _vis: Vector2 = Vector2.ZERO
## 本帧要画的（layout_visible 的结果）
var _draw_list: Array[Dictionary] = []
## 每件进入可见范围时定下的深度：items 下标 → 底边在所在那一竖条路面以下多少（画布像素）；离开可见范围就忘掉
var _depth: Dictionary = {}
var _last_cam: Vector2 = Vector2(INF, INF)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func depth_sync(wv: WorldView) -> void:
	super(wv)
	var sim: SimGame = wv.sim
	if sim == null or sim.world == null:
		return
	var key: Array = [sim.world.length, gap_min_m, gap_max_m, side_chance, side_max, side_off_min, side_off_max, size_mul, size_jitter, smooth_m, band_blend, sink_min, sink_max, steep_deg, slope_span_m, tall_aspect, frame_path_k, show_min_m, show_max_m, scale_max, glaze_m]
	if _world != sim.world or key != _key:
		_world = sim.world
		_key = key
		_depth.clear()
		rebuild(_world)
	var zk: float = zoom_k(view_h)
	_vis = visible_x(12.0 * zk)
	_draw_list = layout_visible(zk)
	var m: ShaderMaterial = material as ShaderMaterial
	if m != null:
		_push_material(m, wv)
	queue_redraw()


## 视野拉远时的放大系数
func zoom_k(vh: float) -> float:
	return maxf(0.6, lerpf(1.0, vh / view_ref_h, view_gain))


## 按地形摆放（换天 / 改参数时调；测试也直接调）：一组一个主件 + 脚边几个小件，组和组之间空 gap_* 米
func rebuild(w: World) -> void:
	_world = w
	_g_x0 = w.left_end - 400.0
	var n: int = int((w.summit_x + 400.0 - _g_x0) / STEP) + 1
	_ground = DepthLayer.smooth_profile(w, _g_x0, STEP, n, smooth_m)
	items = []
	var bands: Dictionary = DepthLayer.by_band(DepthLayer.load_manifest(MANIFEST, FALLBACK))
	# 陡坡用的高而窄的主件：先挑本段的，本段没有就从所有段里挑
	var tall_all: Array[Dictionary] = []
	for bk: Variant in bands:
		for e0: Dictionary in _role(bands[bk] as Array[Dictionary], &"anchor"):
			if _is_tall(e0) and not tall_all.any(func(q: Dictionary) -> bool: return q["key"] == e0["key"]):
				tall_all.append(e0)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(w.length * 1000.0) + 91
	var x: float = w.left_end - 300.0 + rng.randf() * gap_max_m
	var cid: int = 0
	while x < w.summit_x + 300.0:
		var alt: float = w.y_at_x(x)
		var band: StringName = DepthLayer.band_name(alt, DepthLayer.foot_k_at(alt), rng.randf(), band_blend)
		var list: Array[Dictionary] = bands.get(band, [] as Array[Dictionary])
		# 一组占几米宽：按起点和往后 6 米里更陡的那处算（宽件的中心别落到陡处）
		var slope: float = maxf(slope_deg_at(x), slope_deg_at(x + 6.0))
		var steep: bool = slope > steep_deg
		var anchors: Array[Dictionary] = _role(list, &"anchor")
		# 陡坡：按估算的构图放大——进入画面时底边在画面底边，树冠伸出黑釉 show 米；只在放大 scale_max 倍以内够得着的高而窄的件里挑
		var need: float = (steep_need_m(slope) + rng.randf_range(show_min_m, show_max_m)) / factor if steep else 0.0
		if steep:
			var ok_band: Array[Dictionary] = anchors.filter(func(q: Dictionary) -> bool: return _is_tall(q) and _size_base(q) * scale_max >= need)
			anchors = ok_band if not ok_band.is_empty() else tall_all.filter(func(q: Dictionary) -> bool: return _size_base(q) * scale_max >= need)
		var main: Dictionary = DepthLayer.pick_weighted(anchors, rng.randf())
		var gap: float = rng.randf_range(gap_min_m, gap_max_m)
		if main.is_empty():
			x += gap
			continue
		var h: float = maxf(_size(main, rng), need)
		var wd: float = h * SpriteDB.aspect(main["key"])
		var cx: float = x + wd * 0.5
		var right: float = x + wd
		var sink: float = rng.randf_range(sink_min, sink_max)
		items.append({"x": cx, "key": main["key"], "h": h, "w": wd, "flip": rng.randf() < 0.5, "band": band, "z": 0, "cid": cid, "sink": sink, "steep": steep})
		if steep:
			cid += 1
			x = right + gap
			continue
		var sides: Array[Dictionary] = _role(list, &"side")
		var cnt: int = rng.randi_range(1, side_max) if not sides.is_empty() and rng.randf() < side_chance else 0
		var dir: float = -1.0 if rng.randf() < 0.5 else 1.0
		var used: Array[StringName] = [main["key"]]
		for k: int in cnt:
			# 同一组里不重复同一张图（三个一模一样的柱头排在一起像复制粘贴）
			var pool: Array[Dictionary] = sides.filter(func(q: Dictionary) -> bool: return not used.has(q["key"]))
			if pool.is_empty():
				break
			var e: Dictionary = DepthLayer.pick_weighted(pool, rng.randf())
			used.append(e["key"])
			var h2: float = minf(_size(e, rng), h * 0.8)
			var w2: float = h2 * SpriteDB.aspect(e["key"])
			var sx: float = cx + dir * (wd * rng.randf_range(side_off_min, side_off_max) + w2 * 0.2)
			items.append({"x": sx, "key": e["key"], "h": h2, "w": w2, "flip": rng.randf() < 0.5, "band": band, "z": 1, "cid": cid,
				"sink": clampf(sink + rng.randf_range(-0.05, 0.1), sink_min, sink_max)})
			right = maxf(right, sx + w2 * 0.5)
			dir = -dir
		cid += 1
		x = right + gap
	items.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["x"]) < float(q["x"]))


## 清单里某种角色（anchor / side）的条目
static func _role(list: Array[Dictionary], role: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in list:
		if e.get("role", &"anchor") == role:
			out.append(e)
	return out


func _size(e: Dictionary, rng: RandomNumberGenerator) -> float:
	return _size_base(e) * (1.0 + rng.randf_range(-size_jitter, size_jitter))


func _size_base(e: Dictionary) -> float:
	return float(e["height_m"]) * size_mul


## 高而窄（宽 / 高 ≤ tall_aspect）
func _is_tall(e: Dictionary) -> bool:
	return SpriteDB.aspect(e["key"]) <= tall_aspect


## 陡坡上进入画面时（画面右边）路面在画面底边以上多高、减去饰带厚：大件的画面高至少要这么多，树冠才伸得出黑釉（米，按 view_ref_h 的构图估算）
func steep_need_m(slope_deg: float) -> float:
	var t: float = tan(deg_to_rad(slope_deg))
	var path_right: float = frame_path_k * view_ref_h + view_ref_h * 16.0 / 9.0 * 0.5 * t
	return path_right - glaze_m * sqrt(1.0 + t * t)


## 世界 x 处的路面高（平滑 smooth_m 后，米）
func ground_y(x: float) -> float:
	return DepthLayer.sample(_ground, _g_x0, STEP, x)


## 世界 x 处前后 slope_span_m 米的平均坡度（度，取绝对值）
func slope_deg_at(x: float) -> float:
	var hs: float = slope_span_m * 0.5
	return rad_to_deg(atan(absf(ground_y(x + hs) - ground_y(x - hs)) / maxf(0.01, slope_span_m)))


## 世界 x 处"饰带"的竖直厚度（米）：垂直地表的 glaze_m 换成竖直方向（÷ cos 坡角）
func band_v(x: float) -> float:
	var k: float = (ground_y(x + 1.0) - ground_y(x - 1.0)) * 0.5
	return glaze_m * sqrt(1.0 + k * k)


## 本帧可见的前景。横向按视差（factor）走；竖向：底边 = 它所在那一竖条的路面 + 进入可见范围时定下的深度（_depth，之后不变 → 真视差），
## 再保证不高过画面底边、顶最多高出路面 rise_max_m；整件在画面底边以下、或整件落在饰带下的黑釉里的不画。
## 返回 [{key, rect, pos, flip, a}]：pos、rect 在层空间画布像素里；主件先画、小件后画（挡在主件脚边）。
func layout_visible(zk: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var bottom_edge: float = cam_center.y + view_h * PPM * 0.5
	var right_edge: float = cam_center.x + view_h * view_aspect * PPM * 0.5
	# 镜头一下跳很远（换天、运镜切回、读档）：之前定下的深度都作废
	if _last_cam.distance_to(cam_center) > view_h * PPM * 0.5:
		_depth.clear()
	_last_cam = cam_center
	var seen: Dictionary = {}
	var i: int = BackRidge.lower_bound(items, _vis.x)
	while i < items.size():
		var idx: int = i
		var it: Dictionary = items[i]
		i += 1
		var x: float = it["x"]
		if x > _vis.y:
			break
		# 陡坡大件跟着视野整体缩放（构图里它要从画面底边伸到饰带，视野拉远时差的距离按视野高同比变大）
		var zki: float = view_h / view_ref_h if bool(it.get("steep", false)) else zk
		var h: float = float(it["h"]) * zki
		var wd: float = float(it["w"]) * zki
		var hs: float = h * PPM * factor
		# 画面上它所在的那一竖条（世界 x）和那里的路面（画布 y）
		var xw: float = DepthLayer.layer_to_world(Vector2(x * PPM, 0.0), cam_center, factor).x / PPM
		var road: float = -ground_y(xw) * PPM
		var half: float = wd * factor * 0.5
		if not _depth.has(idx):
			# 还没进画面（左边缘还在画面右边外面）：先不定深度，不画
			if xw * PPM - half * PPM > right_edge:
				continue
			# 进画面这一刻：底边在画面右边缘那一竖条正好沉到画面底边以下 sink 个物件高
			var x_in: float = minf(xw, right_edge / PPM)
			_depth[idx] = bottom_edge + float(it.get("sink", sink_min)) * hs + ground_y(x_in) * PPM
		var d: float = float(_depth[idx])
		seen[idx] = d
		var base_world: float = maxf(road + d, bottom_edge)
		# 顶最多高出路面 rise_max_m：按物件宽度上路面最低的那一点算（宽树冠往低处伸，不然会盖住人）；
		# 陡坡大件（柏树、石笋、枯树）顶上是尖的，只按中间一半宽算
		var steep_it: bool = bool(it.get("steep", false))
		var cap_half: float = half * (0.5 if steep_it else 1.0)
		var low: float = road
		for q: float in [-1.0, -0.5, 0.5, 1.0]:
			low = maxf(low, -ground_y(xw + q * cap_half) * PPM)
		base_world = maxf(base_world, low - rise_max_m * PPM + hs)
		var top_world: float = base_world - hs
		# 整件在画面底边以下、或整件在饰带下的黑釉里（暗叠暗只剩刻线，像悬在虚空里）：不画
		if top_world >= bottom_edge or top_world > road + band_v(xw) * PPM - 4.0:
			continue
		var base_layer: float = cam_center.y + (base_world - cam_center.y) / factor
		out.append({"key": it["key"], "rect": Rect2(-wd * PPM * 0.5, -h * PPM, wd * PPM, h * PPM), "pos": Vector2(x * PPM, base_layer),
			"flip": it["flip"], "a": 1.0, "z": int(it.get("z", 0)), "x": x, "steep": steep_it})
	_depth = seen
	out.sort_custom(func(p: Dictionary, q: Dictionary) -> bool:
		return int(p["z"]) < int(q["z"]) or (int(p["z"]) == int(q["z"]) and float(p["x"]) < float(q["x"])))
	return out


## 淡出焦点（画布坐标）：西西弗斯身体中心、石头中心；[Vector4(x, y, 内半径, 外半径)]
func focus_points(sim: SimGame) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var soft: float = fade_soft_m * PPM
	var sp: Dictionary = sim.sis if not sim.sis.is_empty() else sim.sit_pos
	if not sp.is_empty():
		var hm: float = float(sp.get("h", 2.0))
		var r: float = fade_sis_m * PPM
		out.append(Vector4(float(sp["x"]) * PPM, -(float(sp["y"]) + hm * 0.5) * PPM, r, r + soft))
	if sim.stone != null:
		var b: Boulder = sim.stone
		var r2: float = (b.r * fade_stone_k + 0.4) * PPM
		out.append(Vector4(b.x * PPM, -b.y * PPM, r2, r2 + soft))
	# 正在交互（离得近）的物件：最近的两个
	if not sp.is_empty() and sim.world != null:
		var sx: float = float(sp["x"])
		var near: Array[Vector2] = []
		for x: float in interact_xs(sim):
			if absf(x - sx) < fade_obj_near_m:
				near.append(Vector2(absf(x - sx), x))
		near.sort()
		var ro: float = fade_obj_m * PPM
		for i: int in mini(2, near.size()):
			var ox: float = near[i].y
			out.append(Vector4(ox * PPM, -(sim.world.y_at_x(ox) + fade_obj_m * 0.8) * PPM, ro, ro + soft))
	return out


## 能交互的物件的 x（米）：赐福祭坛、还没触发的剧情人物（只读）
static func interact_xs(sim: SimGame) -> PackedFloat32Array:
	var out: PackedFloat32Array = []
	var w: World = sim.world
	if sim.boons != null:
		for i: int in sim.boons.altar_count():
			var a: float = sim.boons.altar_alt(i)
			if a < World.SUMMIT - 2.0:
				out.append(_x_at_s(w, w.s_at_alt(a)))
	if sim.story != null:
		for n: Dictionary in sim.story.npcs:
			if not bool(n.get("done", false)) and n.has("s"):
				out.append(_x_at_s(w, float(n["s"])))
	return out


## 弧长 s → 地表 x（只读地形折线，不动 World 的 at() 游标）
static func _x_at_s(w: World, s: float) -> float:
	var sc: float = clampf(s, 0.0, w.length)
	var i: int = w.seg_index_by_s(sc)
	var j: int = mini(i + 1, w.ps.size() - 1)
	var l: float = w.ps[j] - w.ps[i]
	var t: float = (sc - w.ps[i]) / l if l > 0.0 else 0.0
	return w.px[i] + (w.px[j] - w.px[i]) * t


## HUD 区域（画面比例）→ 世界画布矩形 (x0, y0, x1, y1)
func zone_rects() -> Array[Vector4]:
	var out: Array[Vector4] = []
	var size: Vector2 = Vector2(view_h * view_aspect, view_h) * PPM
	var org: Vector2 = cam_center - size * 0.5
	for z: Rect2 in hud_zones:
		var a: Vector2 = org + z.position * size
		var b: Vector2 = org + z.end * size
		out.append(Vector4(a.x, a.y, b.x, b.y))
	return out


func _push_material(m: ShaderMaterial, wv: WorldView) -> void:
	var fp: Array[Vector4] = focus_points(wv.sim)
	var zr: Array[Vector4] = zone_rects()
	var f4: PackedVector4Array = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
	var z4: PackedVector4Array = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
	for i: int in mini(4, fp.size()):
		f4[i] = fp[i]
	for i: int in mini(4, zr.size()):
		z4[i] = zr[i]
	m.set_shader_parameter(&"focus", f4)
	m.set_shader_parameter(&"focus_n", mini(4, fp.size()))
	m.set_shader_parameter(&"zones", z4)
	m.set_shader_parameter(&"zone_n", mini(4, zr.size()))
	m.set_shader_parameter(&"zone_soft", zone_soft * view_h * PPM)
	m.set_shader_parameter(&"min_alpha", min_alpha)
	m.set_shader_parameter(&"defocus_px", defocus_px)
	m.set_shader_parameter(&"blur_px", blur_px)
	m.set_shader_parameter(&"mip_bias", mip_bias)
	m.set_shader_parameter(&"base_fade", base_fade)
	var sky: Array[Color] = DepthLayer.sky_pair(wv)
	m.set_shader_parameter(&"sky", sky[1])
	m.set_shader_parameter(&"tod_tint", BackgroundView.tint_at(wv.sim.tod(), wv.sim.night_k()))


func _draw() -> void:
	var _pt: int = Prof.t()
	_draw_impl()
	Prof.add(&"fg.draw", _pt)


func _draw_impl() -> void:
	if Engine.is_editor_hint():
		return
	for d: Dictionary in _draw_list:
		var tex: Texture2D = SpriteDB.tex_plain(d["key"])   # depth_sprite 着色器按单图 0–1 坐标淡出，不能用图集
		if tex == null:
			continue
		draw_set_transform(d["pos"], 0.0, Vector2(-1.0 if bool(d["flip"]) else 1.0, 1.0))
		draw_texture_rect(tex, d["rect"], false, Color(1, 1, 1, float(d["a"])))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 调试用：本帧要画的 [x, key, 不透明度]（tests/tools/depth_shots.gd）
func debug_candidates() -> Array:
	var out: Array = []
	for d: Dictionary in _draw_list:
		out.append([snappedf(float(d["pos"].x) / PPM, 0.1), d["key"], snappedf(float(d["a"]), 0.01)])
	return out


## 测试 / 调试用：本帧画了几个
func visible_count() -> int:
	return _draw_list.size()
