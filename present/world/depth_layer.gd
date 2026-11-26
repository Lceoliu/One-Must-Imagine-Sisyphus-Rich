@tool
class_name DepthLayer
extends Node2D
## "瓶画层叠"的视差层基类（docs/v05/art-bible.md §4）：后景山肩（BackRidge，factor < 1）、前景（Foreground，factor > 1）。
## 世界坐标里深度系数 f 的层：节点 transform = 以镜头中心为原点缩放 f（position = 镜头中心 ·(1 − f)、scale = f），
## 层里的东西按"层空间"坐标摆（单位同世界：画布像素 = 米 · PPM，y 朝下）。镜头中心在层空间和世界里是同一点：
## 镜头正对着的东西，层空间里在哪、画面上就在哪；离镜头中心越远，f < 1 的越往中心收（走得慢、显得小），f > 1 的越往外推。
## 每帧由 WorldView 调 depth_sync(wv)（只读模拟）；编辑器里（@tool）什么都不做，打开 main.tscn 不报错。
##
## 海拔段（前景、后景都按它挑素材）：foot 山脚城镇平地、low 0–120 米、mid 120–350、high 350–650、summit 650–1000。
## 段与段之间交错混合：边界 ± band_blend 米内，每个摆放点用自己的随机数决定落在哪一段（越过边界越可能是上一段）。

const PPM: float = 100.0
const BANDS: Array[StringName] = [&"foot", &"low", &"mid", &"high", &"summit"]
## 各段的上边界（米）；foot 的上边界是"离开平地"的地表高度
const BAND_TOP: PackedFloat32Array = [1.5, 120.0, 350.0, 650.0]

## 深度系数：< 1 在路面后面（走得慢、显得小），> 1 在路面前面
@export_range(0.3, 2.0, 0.01) var factor: float = 1.0
## 海拔段交界处交错混合的半宽（米）；foot / low 交界用它的 1/6（平地到坡只有几米高差）
@export_range(0.0, 120.0, 1.0) var band_blend: float = 30.0

## 当前镜头中心（世界画布像素）、视野高（米）、视野宽高比；depth_sync 每帧更新
var cam_center: Vector2 = Vector2.ZERO
var view_h: float = 14.0
var view_aspect: float = 16.0 / 9.0


## 以镜头中心为原点缩放 f 的变换
static func parallax_xf(center: Vector2, f: float) -> Transform2D:
	return Transform2D(0.0, Vector2(f, f), 0.0, center * (1.0 - f))


## 层空间点 → 世界画布点
static func layer_to_world(q: Vector2, center: Vector2, f: float) -> Vector2:
	return center + (q - center) * f


## 世界画布点 → 层空间点
static func world_to_layer(w: Vector2, center: Vector2, f: float) -> Vector2:
	return center + (w - center) / f


## 海拔 alt（米）、平地程度 foot_k（1 = 山脚城镇平地）、随机数 r ∈ [0, 1) → 段序号（0 foot … 4 summit）。
## 交界处按 smoothstep 概率交错：同一处的摆放点有的属于下一段、有的属于上一段。
static func band_index(alt: float, foot_k: float, r: float, blend: float) -> int:
	if foot_k > 0.0 and r < foot_k:
		return 0
	var idx: int = 1
	for i: int in range(1, BAND_TOP.size()):
		var b: float = BAND_TOP[i]
		var p: float = _smooth(b - blend, b + blend, alt) if blend > 0.0 else (1.0 if alt >= b else 0.0)
		if p > r:
			idx = i + 1
	return idx


static func band_name(alt: float, foot_k: float, r: float, blend: float) -> StringName:
	return BANDS[band_index(alt, foot_k, r, blend)]


## 地表平地程度：地表高 y（米）→ 1（城镇平地）… 0（上了坡）
static func foot_k_at(y: float) -> float:
	return 1.0 - _smooth(0.3, 8.0, y)


static func _smooth(e0: float, e1: float, x: float) -> float:
	var k: float = clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


## 读素材清单（assets/native/<表>/manifest.json：[{key, band, kind, height_m, weight, cluster}]）。
## 清单不存在、或里面的 key 还没登记进 SpriteDB 时，用 fallback（同样格式）顶替——美术到位后不改代码就能换上。
static func load_manifest(path: String, fallback: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Array:
			for e: Variant in data:
				if e is Dictionary and (e as Dictionary).has("key") and SpriteDB.has(StringName(str((e as Dictionary)["key"]))):
					out.append(_norm_entry(e as Dictionary))
	if out.is_empty():
		for e2: Variant in fallback:
			if SpriteDB.has(StringName(str((e2 as Dictionary)["key"]))):
				out.append(_norm_entry(e2 as Dictionary))
	return out


## 清单条目统一格式：cluster 可以是 bool（true = 2–3 个成组）或整数（最多几个成组）；floating = 飘在空中（云），kind = cloud 也算；
## role = anchor（一组的主件）/ side（挨着主件脚边的小件），没写当主件
static func _norm_entry(e: Dictionary) -> Dictionary:
	var cl: Variant = e.get("cluster", 1)
	var n: int = 1
	if cl is bool:
		n = 3 if cl else 1
	else:
		n = maxi(1, int(cl))
	return {"key": StringName(str(e["key"])), "band": StringName(str(e.get("band", "low"))), "kind": StringName(str(e.get("kind", ""))),
		"height_m": float(e.get("height_m", 3.0)), "weight": maxf(0.0, float(e.get("weight", 1.0))), "cluster": n,
		"floating": bool(e.get("floating", false)) or str(e.get("kind", "")) == "cloud", "role": StringName(str(e.get("role", "anchor")))}


## 按段把清单分组：段名 → 条目数组；某段没有条目时借相邻段（先往下、再往上）
static func by_band(entries: Array[Dictionary]) -> Dictionary:
	var raw: Dictionary = {}
	for b: StringName in BANDS:
		raw[b] = [] as Array[Dictionary]
	for e: Dictionary in entries:
		if raw.has(e["band"]):
			(raw[e["band"]] as Array[Dictionary]).append(e)
	var out: Dictionary = {}
	for i: int in BANDS.size():
		var pick: Array[Dictionary] = raw[BANDS[i]]
		var d: int = 1
		while pick.is_empty() and d < BANDS.size():
			if i - d >= 0 and not (raw[BANDS[i - d]] as Array[Dictionary]).is_empty():
				pick = raw[BANDS[i - d]]
			elif i + d < BANDS.size() and not (raw[BANDS[i + d]] as Array[Dictionary]).is_empty():
				pick = raw[BANDS[i + d]]
			d += 1
		out[BANDS[i]] = pick
	return out


## 按 weight 抽一条
static func pick_weighted(list: Array[Dictionary], r: float) -> Dictionary:
	if list.is_empty():
		return {}
	var tot: float = 0.0
	for e: Dictionary in list:
		tot += float(e["weight"])
	if tot <= 0.0:
		return list[mini(list.size() - 1, int(r * list.size()))]
	var acc: float = 0.0
	var target: float = r * tot
	for e: Dictionary in list:
		acc += float(e["weight"])
		if target < acc:
			return e
	return list[list.size() - 1]


## 地形高度（米）沿 x 等距采样 → 两遍方框平滑（≈ 三角核）。x0 起每 step 米一个点，共 n 个。radius ≤ 0 时不平滑
static func smooth_profile(w: World, x0: float, step: float, n: int, radius: float) -> PackedFloat32Array:
	var ys: PackedFloat32Array = []
	ys.resize(n)
	for i: int in n:
		ys[i] = w.y_at_x(x0 + i * step)
	var r: int = int(roundf(radius / step))
	if r <= 0:
		return ys
	return _box(_box(ys, r), r)


static func _box(a: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var n: int = a.size()
	var pre: PackedFloat64Array = []
	pre.resize(n + 1)
	pre[0] = 0.0
	for i: int in n:
		pre[i + 1] = pre[i] + a[i]
	var out: PackedFloat32Array = []
	out.resize(n)
	for i: int in n:
		var lo: int = maxi(0, i - r)
		var hi: int = mini(n - 1, i + r)
		out[i] = float((pre[hi + 1] - pre[lo]) / float(hi - lo + 1))
	return out


## 等距采样表在 x 处的线性插值（x0 起每 step 米一个点）
static func sample(tab: PackedFloat32Array, x0: float, step: float, x: float) -> float:
	var n: int = tab.size()
	if n == 0:
		return 0.0
	var f: float = clampf((x - x0) / step, 0.0, float(n - 1))
	var i: int = mini(n - 2, int(f)) if n > 1 else 0
	if n == 1:
		return tab[0]
	return lerpf(tab[i], tab[i + 1], f - i)


## 屏幕上一点离"焦点"（西西弗斯、石头……）的淡出系数：d ≤ r_in → min_a，d ≥ r_out → 1（smoothstep）。
## 和 depth_sprite.gdshader 的 focus 淡出同一公式（测试用它对拍）
static func focus_fade(d: float, r_in: float, r_out: float, min_a: float) -> float:
	return lerpf(min_a, 1.0, _smooth(r_in, maxf(r_in + 1e-3, r_out), d))


## 每帧：读镜头，套视差变换。子类 super 之后再更新自己的内容
func depth_sync(wv: WorldView) -> void:
	if wv.cam == null:
		return
	# 镜头没有拖拽边距 / 平滑 / 边界：画面中心 = 镜头位置（WorldView 本帧刚设好）
	cam_center = wv.cam.position + wv.cam.offset
	var vp: Vector2 = wv.get_viewport_rect().size
	view_aspect = vp.x / maxf(1.0, vp.y)
	view_h = vp.y / maxf(1e-4, wv.cam.zoom.y) / PPM
	transform = parallax_xf(cam_center, factor)


## 层空间里可见的 x 范围（米），两边多留 margin 米
func visible_x(margin: float) -> Vector2:
	var half_w: float = view_h * view_aspect * 0.5 / factor
	var cx: float = cam_center.x / PPM
	return Vector2(cx - half_w - margin, cx + half_w + margin)


## 远景天色（BackgroundView.sky_at：[天顶, 地平线]）；拿不到时给一档中性灰
static func sky_pair(wv: WorldView) -> Array[Color]:
	var bg: Node = wv.get_node_or_null("../BG/Background")
	if bg != null and bg.has_method(&"sky_at") and wv.sim != null:
		var r: Variant = bg.call(&"sky_at", clampf(wv.cam_y, 0.0, 1000.0), wv.sim.tod(), wv.sim.night_k())
		if r is Array and (r as Array).size() >= 2:
			return [(r as Array)[0] as Color, (r as Array)[1] as Color]
	return [Color("c6b6a0"), Color("e0d3bc")]
