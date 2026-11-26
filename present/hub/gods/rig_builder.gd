class_name RigBuilder
extends RefCounted
## 给 HubGod 生成蒙皮网格与权重（编辑器里的「重建网格与权重」按钮和 tests/tools/rig/make_god.gd 都调这里）。
## 网格：立绘按 cell 像素切格，有不透明像素的格子（外扩一格留余量）各出一个四边形；UV = 贴图像素，坐标原点在脚底中点。
## 权重：每根骨头 = 从骨头原点到骨尖的线段；格子到线段的距离沿"身体内部"走（在不透明格子里反复做倒角距离传播），
##   所以举起的胳膊不会带动旁边的头。权重 = 1 / (1 + d / 衰减)^3，丢掉 < 5% 的影响再归一，最后在网格上抹平两遍。
## 骨头的静止姿态（rest）= 重建那一刻的姿态，所以重建前先让骨头回到 RESET（存场景时 AnimationPlayer 会自动回到 RESET）。

const LIT_MAT: String = "res://present/hub/mat_lit.tres"
const NORMALS: String = "res://assets/normals"
## 权重衰减（格子数）与幂次
const FALLOFF_CELLS: float = 2.0
const POWER: float = 3.0
const PRUNE: float = 0.05
## 灯光层：1 = 普通灯（火、吊灯），2 = 月光轮廓（只照人物和道具）
const LIGHT_MASK: int = 3


static func build(god: Node2D) -> bool:
	var skel: Skeleton2D = god.get_node_or_null("Skeleton") as Skeleton2D
	var body: Polygon2D = god.get_node_or_null("Body") as Polygon2D
	var tex: Texture2D = god.get("texture") as Texture2D
	var c: int = int(god.get("cell"))
	if skel == null or body == null or tex == null:
		push_warning("RigBuilder: %s 缺 Skeleton / Body / texture" % god.name)
		return false
	var img: Image = image_of(tex)
	if img == null:
		push_warning("RigBuilder: 读不到贴图 %s" % tex.resource_path)
		return false
	skel.position = Vector2.ZERO
	body.position = Vector2.ZERO
	var W: int = img.get_width()
	var H: int = img.get_height()
	var off: Vector2 = Vector2(-W * 0.5, -float(H))
	var nx: int = ceili(float(W) / c)
	var ny: int = ceili(float(H) / c)
	var occ: PackedByteArray = _occupancy(img, c, nx, ny)
	# —— 网格 ——
	var vid: PackedInt32Array = PackedInt32Array()
	vid.resize((nx + 1) * (ny + 1))
	vid.fill(-1)
	var pts: PackedVector2Array = []
	var uvs: PackedVector2Array = []
	var quads: Array = []
	for j: int in ny:
		for i: int in nx:
			if occ[j * nx + i] == 0:
				continue
			var q: PackedInt32Array = []
			for cr: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]:
				var k: int = cr.y * (nx + 1) + cr.x
				if vid[k] < 0:
					vid[k] = pts.size()
					var uv: Vector2 = Vector2(minf(cr.x * c, W), minf(cr.y * c, H))
					uvs.append(uv)
					pts.append(uv + off)
				q.append(vid[k])
			quads.append(q)
	# —— 骨头 ——
	var bones: Array[Bone2D] = bones_of(skel)
	fix_lengths(bones)
	for b: Bone2D in bones:
		b.rest = b.transform
	# —— 每根骨头的距离场（格子）→ 顶点距离 → 权重 ——
	var nv: int = pts.size()
	var dists: Array[PackedFloat32Array] = []
	for b: Bone2D in bones:
		var seg: PackedVector2Array = segment(b)
		var a: Vector2 = seg[0] - off
		var t: Vector2 = seg[1] - off
		var cd: PackedFloat32Array = _geodesic(occ, nx, ny, c, a, t)
		var vd: PackedFloat32Array = PackedFloat32Array()
		vd.resize(nv)
		for j: int in ny + 1:
			for i: int in nx + 1:
				var v: int = vid[j * (nx + 1) + i]
				if v < 0:
					continue
				var best: float = INF
				for cc: Vector2i in [Vector2i(i - 1, j - 1), Vector2i(i, j - 1), Vector2i(i - 1, j), Vector2i(i, j)]:
					if cc.x < 0 or cc.y < 0 or cc.x >= nx or cc.y >= ny or occ[cc.y * nx + cc.x] == 0:
						continue
					var ctr: Vector2 = Vector2((cc.x + 0.5) * c, (cc.y + 0.5) * c)
					best = minf(best, cd[cc.y * nx + cc.x] + ctr.distance_to(uvs[v]))
				if is_inf(best):
					best = _seg_dist(uvs[v], a, t) * 1.5
				vd[v] = best
		dists.append(vd)
	var weights: Array[PackedFloat32Array] = _weights(dists, nv, c)
	weights = _smooth(weights, quads, nv, 2)
	# —— 写进 Polygon2D ——
	body.texture = canvas_texture(tex)
	body.material = load(LIT_MAT) as Material
	body.light_mask = LIGHT_MASK
	body.polygon = pts
	body.uv = uvs
	body.polygons = quads
	body.internal_vertex_count = 0
	body.skeleton = NodePath("../Skeleton")
	body.clear_bones()
	for k: int in bones.size():
		body.add_bone(path_in(skel, bones[k]), weights[k])
	body.queue_redraw()
	return true


## 贴图 → Image（PNG 直接从文件读：无头模式下 GPU 贴图取不回像素）
static func image_of(tex: Texture2D) -> Image:
	var t: Texture2D = tex
	if t is CanvasTexture:
		t = (t as CanvasTexture).diffuse_texture
	if t == null:
		return null
	var p: String = t.resource_path
	var img: Image = null
	if p.ends_with(".png"):
		img = Image.load_from_file(ProjectSettings.globalize_path(p))
	if img == null:
		img = t.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	return img


## 立绘对应的法线图路径（不一定存在）
static func normal_path(p: String) -> String:
	return "%s/%s/%s_n.png" % [NORMALS, p.get_base_dir().get_file(), p.get_file().get_basename()]


## 立绘 + 自动法线（tools/assets/make_normals.py 生成的 assets/normals/<表>/<名>_n.png）
static func canvas_texture(tex: Texture2D) -> Texture2D:
	var np: String = normal_path(tex.resource_path)
	var ct: CanvasTexture = CanvasTexture.new()
	ct.diffuse_texture = tex
	if ResourceLoader.exists(np):
		ct.normal_texture = load(np) as Texture2D
	return ct


static func bones_of(n: Node) -> Array[Bone2D]:
	var out: Array[Bone2D] = []
	for ch: Node in n.get_children():
		if ch is Bone2D:
			out.append(ch as Bone2D)
			out.append_array(bones_of(ch))
	return out


## 只有一根子骨头的骨头：长度和角度对准子骨头（拖动子骨头后自动跟上）；叶子骨头保留自己的长度和角度
static func fix_lengths(bones: Array[Bone2D]) -> void:
	for b: Bone2D in bones:
		b.set_autocalculate_length_and_angle(false)
		var kids: Array[Bone2D] = []
		for ch: Node in b.get_children():
			if ch is Bone2D:
				kids.append(ch as Bone2D)
		if kids.size() == 1 and kids[0].position.length() > 1.0:
			var p: Vector2 = kids[0].position
			b.set_length(p.length())
			b.set_bone_angle(p.angle())


## 骨头在 Skeleton2D 坐标系里的线段 [原点, 骨尖]
static func segment(b: Bone2D) -> PackedVector2Array:
	var xf: Transform2D = b.transform
	var p: Node = b.get_parent()
	while p is Bone2D:
		xf = (p as Bone2D).transform * xf
		p = p.get_parent()
	var tip: Vector2 = xf * (Vector2.from_angle(b.get_bone_angle()) * maxf(b.get_length(), 1.0))
	return PackedVector2Array([xf.origin, tip])


static func path_in(skel: Node, b: Node) -> NodePath:
	var parts: PackedStringArray = []
	var n: Node = b
	while n != null and n != skel:
		parts.insert(0, String(n.name))
		n = n.get_parent()
	return NodePath("/".join(parts))


static func _occupancy(img: Image, c: int, nx: int, ny: int) -> PackedByteArray:
	var W: int = img.get_width()
	var H: int = img.get_height()
	var occ: PackedByteArray = PackedByteArray()
	occ.resize(nx * ny)
	for j: int in ny:
		for i: int in nx:
			var hit: bool = false
			var y: int = j * c
			while y < mini((j + 1) * c, H) and not hit:
				var x: int = i * c
				while x < mini((i + 1) * c, W):
					if img.get_pixel(x, y).a > 0.08:
						hit = true
						break
					x += 2
				y += 2
			occ[j * nx + i] = 1 if hit else 0
	# 外扩一格：骨头转动时边缘不会被裁掉
	var out: PackedByteArray = occ.duplicate()
	for j: int in ny:
		for i: int in nx:
			if occ[j * nx + i] == 0:
				continue
			for dj: int in range(-1, 2):
				for di: int in range(-1, 2):
					var x2: int = i + di
					var y2: int = j + dj
					if x2 >= 0 and y2 >= 0 and x2 < nx and y2 < ny:
						out[y2 * nx + x2] = 1
	return out


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var l2: float = ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## 格子到线段 (a, b) 的"体内距离"：线段附近的格子取直线距离作种子，再在不透明格子里来回传播（倒角距离，直到不再变）
static func _geodesic(occ: PackedByteArray, nx: int, ny: int, c: int, a: Vector2, b: Vector2) -> PackedFloat32Array:
	var d: PackedFloat32Array = PackedFloat32Array()
	d.resize(nx * ny)
	d.fill(INF)
	var seeded: bool = false
	var nearest: int = -1
	var nd: float = INF
	for j: int in ny:
		for i: int in nx:
			var k: int = j * nx + i
			if occ[k] == 0:
				continue
			var e: float = _seg_dist(Vector2((i + 0.5) * c, (j + 0.5) * c), a, b)
			if e < c * 0.9:
				d[k] = e
				seeded = true
			if e < nd:
				nd = e
				nearest = k
	if not seeded and nearest >= 0:
		d[nearest] = nd
	var s2: float = c * 1.41421
	var fwd: Array[Vector3i] = [Vector3i(-1, 0, 0), Vector3i(-1, -1, 1), Vector3i(0, -1, 0), Vector3i(1, -1, 1)]
	var bwd: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(1, 1, 1), Vector3i(0, 1, 0), Vector3i(-1, 1, 1)]
	for it: int in 40:
		var changed: bool = false
		for j: int in ny:
			for i: int in nx:
				changed = _relax(d, occ, nx, ny, i, j, fwd, c, s2) or changed
		for j: int in range(ny - 1, -1, -1):
			for i: int in range(nx - 1, -1, -1):
				changed = _relax(d, occ, nx, ny, i, j, bwd, c, s2) or changed
		if not changed:
			break
	return d


static func _relax(d: PackedFloat32Array, occ: PackedByteArray, nx: int, ny: int, i: int, j: int, nb: Array[Vector3i], c: int, s2: float) -> bool:
	var k: int = j * nx + i
	if occ[k] == 0:
		return false
	var cur: float = d[k]
	for o: Vector3i in nb:
		var x: int = i + o.x
		var y: int = j + o.y
		if x < 0 or y < 0 or x >= nx or y >= ny:
			continue
		var v: float = d[y * nx + x] + (s2 if o.z == 1 else float(c))
		if v < cur:
			cur = v
	if cur < d[k]:
		d[k] = cur
		return true
	return false


static func _weights(dists: Array[PackedFloat32Array], nv: int, c: int) -> Array[PackedFloat32Array]:
	var nb: int = dists.size()
	var out: Array[PackedFloat32Array] = []
	for k: int in nb:
		var w: PackedFloat32Array = PackedFloat32Array()
		w.resize(nv)
		out.append(w)
	var f: float = FALLOFF_CELLS * c
	for v: int in nv:
		var sum: float = 0.0
		var raw: PackedFloat32Array = PackedFloat32Array()
		raw.resize(nb)
		for k: int in nb:
			raw[k] = 1.0 / pow(1.0 + dists[k][v] / f, POWER)
			sum += raw[k]
		var sum2: float = 0.0
		for k: int in nb:
			raw[k] = raw[k] / sum if sum > 0.0 else 0.0
			if raw[k] < PRUNE:
				raw[k] = 0.0
			sum2 += raw[k]
		for k: int in nb:
			out[k][v] = raw[k] / sum2 if sum2 > 0.0 else (1.0 if k == 0 else 0.0)
	return out


## 在网格上抹平（每个顶点取自己和四边形邻居的平均），再归一
static func _smooth(weights: Array[PackedFloat32Array], quads: Array, nv: int, passes: int) -> Array[PackedFloat32Array]:
	var nbrs: Array[PackedInt32Array] = []
	for v: int in nv:
		nbrs.append(PackedInt32Array())
	for q: PackedInt32Array in quads:
		for a: int in 4:
			var u: int = q[a]
			var w: int = q[(a + 1) % 4]
			if not nbrs[u].has(w):
				nbrs[u].append(w)
			if not nbrs[w].has(u):
				nbrs[w].append(u)
	var cur: Array[PackedFloat32Array] = weights
	for p: int in passes:
		var nxt: Array[PackedFloat32Array] = []
		for k: int in cur.size():
			var w2: PackedFloat32Array = PackedFloat32Array()
			w2.resize(nv)
			for v: int in nv:
				var s: float = cur[k][v] * 2.0
				var n: float = 2.0
				for u: int in nbrs[v]:
					s += cur[k][u]
					n += 1.0
				w2[v] = s / n
			nxt.append(w2)
		cur = nxt
	for v: int in nv:
		var sum: float = 0.0
		for k: int in cur.size():
			sum += cur[k][v]
		if sum > 0.0:
			for k: int in cur.size():
				cur[k][v] = cur[k][v] / sum
	return cur
