class_name BackgroundView
extends Node2D
## 远景（移植 background.js drawBack 的主要部分）：天空渐变（随时刻、海拔、夜色）、奥林匹斯、云带、远山、丘陵、海岸、
## 云海、太阳/月亮、白天整屏染色。双色背景图用 bg_recolor shader 上色（低饱和 + 大气透视），日夜颜色按 night_k 插值。

const SUMMIT: float = 1000.0
## 各层 [白天 [填色, 线色], 夜 [填色, 线色]]。白天按大气透视：越远越浅越冷，最近的海岸也比山体（陶土色，terrain_mat.tres）
## 浅一档、冷一档，黑色的人物、石头、物件压在陶土山体上最醒目；夜里各层不变（夜宴远景 hub.tscn 用同一组夜色）。
const PAL: Dictionary = {
	&"olympus": [["e2c1a2", "efdbc4"], ["27304a", "3a4664"]],
	&"veil": [["e7d0b8", "f2e3d2"], ["2c3652", "3c4866"]],
	&"range": [["d5ad8b", "e5c9ab"], ["1e273f", "33405c"]],
	&"hills": [["cba17f", "debe9d"], ["161d31", "2b3752"]],
	&"coast": [["c59b7a", "d9b798"], ["0f1526", "1f2b44"]],
	&"clouds": [["ebd8c1", "f5e9db"], ["2a3450", "3b4868"]],
}
const ATMOS: Dictionary = {&"olympus": 0.55, &"range": 0.35, &"hills": 0.20, &"coast": 0.10}
## 白天天色（2026-10-13 集成时定稿：候选"杏橙"七成 +"淡杏"三成）：往效果图的暖橙靠，但减淡、冷化（正午天顶饱和度约 0.39，
## 效果图约 0.7），久看不累；傍晚的时刻染色也压轻了（不发红）；
## 山体陶土色（terrain_mat.tres）比天空深、暖，远景各层比山体浅、冷。夜色（SKY_NIGHT、PAL 的夜色）不变。
const ATMOS_SKY: Array = ["e2c4a4", "283453"]
const SKY_TOD: Array = [[0.00, "77667a", "daab8e"], [0.12, "c19d87", "e1c1a2"], [0.50, "d6a582", "e9caa9"], [0.78, "d09c78", "e6c29e"], [0.94, "8a5e5c", "d49268"]]
const SKY_NIGHT: Array = ["161f36", "36456a"]
## 入夜途中（night_k ≈ 0.5）地平线余晖的颜色
const DUSK_GLOW: String = "c98a62"
const TINT_TOD: Array = [[0.00, Color(120 / 255.0, 96 / 255.0, 140 / 255.0), 0.16], [0.12, Color(120 / 255.0, 96 / 255.0, 140 / 255.0), 0.06], [0.28, Color(200 / 255.0, 190 / 255.0, 180 / 255.0), 0.0],
	[0.62, Color(200 / 255.0, 190 / 255.0, 180 / 255.0), 0.0], [0.78, Color(160 / 255.0, 110 / 255.0, 60 / 255.0), 0.05], [0.94, Color(160 / 255.0, 95 / 255.0, 80 / 255.0), 0.12], [1.10, Color(160 / 255.0, 95 / 255.0, 80 / 255.0), 0.16]]

var sim: SimGame = null
var wv: WorldView = null
var vx: float = 0.0
var _last_cam_x: float = NAN
var t: float = 0.0
var _black: ImageTexture
var _layers: Dictionary = {}       # 名字 → 子节点
var _sky: Node2D
var _sunmoon: Node2D
var _tint: Node2D
var _stars: Array[Vector4] = []
## 灯火点位缓存：贴图 key → {lamps: Array[Vector4(u, v, 亮起延迟 d, 相位)], boats: …}（u、v 是贴图内的归一化坐标）
var _lamp_pts: Dictionary = {}
var _lamp_warm: Dictionary = {}   # 已在白天预先算过撒点的图层
## 灯火层：紧跟在对应地面层后面画（不走重新上色的材质），被更近的层自然挡住
var _lamp_nodes: Dictionary = {}
const LAMP_OPT: Dictionary = {&"hills": {"lamps": 14, "fishing": 0, "seed": 53}, &"coast": {"lamps": 14, "fishing": 3, "seed": 71}}


func _ready() -> void:
	var img: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	_black = ImageTexture.create_from_image(img)
	_sky = _node("Sky", false, _draw_sky)
	for nm: StringName in [&"olympus", &"veil", &"range", &"hills", &"coast", &"clouds"]:
		_layers[nm] = _node(String(nm), true, _draw_layer.bind(nm))
	_sunmoon = _node("SunMoon", false, _draw_sunmoon)
	move_child(_sunmoon, 3)   # 天空、奥林匹斯、云带之后，远山之前：太阳落到山后自然被挡住
	for nm2: StringName in [&"hills", &"coast"]:
		var ln: Node2D = _node(String(nm2) + "Lamps", false, _draw_lamps.bind(nm2))
		move_child(ln, (_layers[nm2] as Node).get_index() + 1)
		_lamp_nodes[nm2] = ln
	_tint = _node("Tint", false, _draw_tint)
	var cm: CanvasItemMaterial = CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_tint.material = cm
	var R: JsRng = JsRng.new(91.0)
	for i: int in 90:
		_stars.append(Vector4(R.next(), R.next() * 0.6, 0.6 + R.next() * 1.6, R.next() * 6.28))


func _node(nm: String, recolor: bool, cb: Callable) -> Node2D:
	var n: Node2D = Node2D.new()
	n.name = nm
	if recolor:
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = load("res://present/shaders/bg_recolor.gdshader")
		n.material = m
	n.draw.connect(cb)
	add_child(n)
	return n


static func _smooth(e0: float, e1: float, x: float) -> float:
	var k: float = clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


static func _alt_adjust(c: Color, alt: float) -> Color:
	var k: float = clampf(alt / 1000.0, 0.0, 1.0)
	return Color.from_hsv(c.h, c.s * (1.0 - 0.2 * k), clampf(c.v + 0.08 * k, 0.0, 1.0))


func sky_at(alt: float, tod: float, nk: float) -> Array[Color]:
	var tt: float = clampf(tod, 0.0, 0.94)
	var i: int = 0
	while i + 2 < _sky_tod.size() and tt > float(_sky_tod[i + 1][0]):
		i += 1
	var a: Array = _sky_tod[i]
	var b: Array = _sky_tod[i + 1]
	var u: float = clampf((tt - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
	var top: Color = _alt_adjust(Color(a[1]).lerp(Color(b[1]), u), alt)
	var bot: Color = _alt_adjust(Color(a[2]).lerp(Color(b[2]), u), alt)
	if nk > 0.0:
		# 天顶先暗、地平线的余晖留得久一点（不然整片天一起混成灰紫）
		top = top.lerp(_alt_adjust(Color(SKY_NIGHT[0]), alt * 0.5), nk)
		bot = bot.lerp(_alt_adjust(Color(SKY_NIGHT[1]), alt * 0.5), pow(nk, 1.7))
		# 入夜途中地平线留一抹暖色余晖（不然天顶的冷蓝和白天的暖杏混成灰紫）；山肩、雾带取的天色也跟着暖一点
		var gl: float = 4.0 * nk * (1.0 - nk)
		bot = bot.lerp(Color(DUSK_GLOW), gl * 0.35)
		top = top.lerp(Color(DUSK_GLOW).darkened(0.45), gl * 0.18)
	return [top, bot]


## 只给对比截图用（tests/tools/world_shots.gd --scheme）：{"bg": {层名: [白天填色, 白天线色]}} 覆盖 PAL 的白天两色；
## "sky": [[tod, 天顶, 地平线], …] 覆盖 SKY_TOD；"atmos_sky": "rrggbb" 覆盖白天的大气色 ATMOS_SKY[0]
var _pal_day: Dictionary = {}
var _sky_tod: Array = SKY_TOD
var _atmos_day: String = ATMOS_SKY[0]


func apply_scheme(d: Dictionary) -> void:
	_pal_day = d.get("bg", {})
	_sky_tod = d.get("sky", SKY_TOD)
	_atmos_day = d.get("atmos_sky", ATMOS_SKY[0])


func _pal(nm: StringName, nk: float) -> Array[Color]:
	var p: Array = PAL[nm]
	if _pal_day.has(String(nm)):
		p = [_pal_day[String(nm)], p[1]]
	var at: float = ATMOS.get(nm, 0.0)
	var out: Array[Color] = []
	# 日夜之间（黄昏 / 黎明）带一点余晖的暖色，免得直接线性混成灰紫（山体着色器的 dusk_* 同理）
	var glow: float = 4.0 * nk * (1.0 - nk) * 0.3
	for j: int in 2:
		var dc: Color = Color(p[0][j]).lerp(Color(_atmos_day), at)
		var nc: Color = Color(p[1][j]).lerp(Color(ATMOS_SKY[1]), at)
		var c: Color = dc.lerp(nc, nk)
		out.append(c.lerp(Color(c.r * 1.12, c.g * 0.9, c.b * 0.84), glow))
	return out


func _process(dt: float) -> void:
	if sim == null or wv == null or sim.world == null:
		return
	t += dt
	var cx: float = wv.cam_x
	if is_nan(_last_cam_x) or absf(cx - _last_cam_x) > 300.0:
		vx = cx
	else:
		var boost: float = 1.0 + 0.8 * clampf((sim.stone.r - 2.0) / 12.0, 0.0, 1.0) if sim.phase == &"night" else 1.0
		vx += (cx - _last_cam_x) * boost
	_last_cam_x = cx
	for n: Node in get_children():
		(n as CanvasItem).queue_redraw()


func _alt() -> float:
	return clampf(wv.cam_y, 0.0, SUMMIT)


func _olympus(W: float, H: float) -> Rect2:
	var k: float = _alt() / SUMMIT
	var h: float = H * (1.05 + 0.8 * pow(k, 1.4))
	var w: float = h * SpriteDB.aspect(&"bg_olympus")
	var cx: float = W * 0.47 - (wv.cam_x - 600.0) * 0.06 * (H / 900.0)
	var y: float = H * (-0.01 - 0.02 * k)
	return Rect2(cx - w / 2.0, y, w, h)


func _draw_sky() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var nk: float = sim.night_k()
	var c: Array[Color] = sky_at(_alt(), sim.tod(), nk)
	var mid: Color = c[0].lerp(c[1], 0.62)
	_sky.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(vp.x, 0), Vector2(vp.x, vp.y * 0.55), Vector2(0, vp.y * 0.55)]), PackedColorArray([c[0], c[0], mid, mid]))
	_sky.draw_polygon(PackedVector2Array([Vector2(0, vp.y * 0.55), Vector2(vp.x, vp.y * 0.55), Vector2(vp.x, vp.y), Vector2(0, vp.y)]), PackedColorArray([mid, mid, c[1], c[1]]))
	if nk > 0.02:
		var sk: float = clampf((sim.tod() - 1.0) / 0.08, 0.25, 1.0) * nk
		# 星星攒成一批三角形（逐颗 draw_circle 是一颗一次绘制调用）
		var tri: PackedVector2Array = []
		var cols: PackedColorArray = []
		# 背景细节（设置 → 画面）：简 30 颗、中 60 颗、全 90 颗
		var ns: int = [30, 60, 90][clampi(Settings.bg_level, 0, 2)]
		for si: int in mini(ns, _stars.size()):
			var s: Vector4 = _stars[si]
			var x: float = fposmod(s.x * vp.x - vx * 0.03 * (vp.y / 900.0), vp.x)
			_disc(tri, cols, Vector2(x, s.y * vp.y), s.z, Color(0.86, 0.91, 1.0, sk * (0.3 + 0.35 * (0.5 + 0.5 * sin(t * 1.3 + s.w)))))
		RenderingServer.canvas_item_add_triangle_array(_sky.get_canvas_item(), PackedInt32Array(), tri, cols)


## 实心小圆（8 瓣扇形）攒进三角形批次
static func _disc(tri: PackedVector2Array, cols: PackedColorArray, c: Vector2, r: float, col: Color) -> void:
	var prev: Vector2 = c + Vector2(r, 0.0)
	for i: int in range(1, 9):
		var th: float = TAU * float(i) / 8.0
		var q: Vector2 = c + Vector2(cos(th), sin(th)) * r
		tri.append_array([c, prev, q])
		cols.append_array([col, col, col])
		prev = q


## 带 1 像素羽化边的折线（= draw_polyline 开 antialiased）攒进三角形批次：拐点用两侧段法线的平均（斜接），中间实色、两边淡到透明
static func _aa_strip(tri: PackedVector2Array, cols: PackedColorArray, pts: PackedVector2Array, w: float, col: Color) -> void:
	var n: int = pts.size()
	if n < 2:
		return
	var hw: float = w * 0.5
	var fe: float = 1.0
	var nor: PackedVector2Array = []
	for i: int in n:
		var d0: Vector2 = (pts[i] - pts[maxi(0, i - 1)]).normalized() if i > 0 else Vector2.ZERO
		var d1: Vector2 = (pts[mini(n - 1, i + 1)] - pts[i]).normalized() if i < n - 1 else Vector2.ZERO
		var d: Vector2 = (d0 + d1).normalized()
		var nn: Vector2 = Vector2(-d.y, d.x)
		# 斜接长度 1/cos(半角)，夹到 2 倍防尖刺
		var k: float = 1.0 / maxf(0.5, nn.dot(Vector2(-d1.y, d1.x) if i < n - 1 else Vector2(-d0.y, d0.x)))
		nor.append(nn * k)
	var c0: Color = Color(col, 0.0)
	for i: int in n - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var na: Vector2 = nor[i]
		var nb: Vector2 = nor[i + 1]
		# 实心芯
		tri.append_array([a + na * hw, b + nb * hw, b - nb * hw, a + na * hw, b - nb * hw, a - na * hw])
		cols.append_array([col, col, col, col, col, col])
		# 两侧羽化
		for sg: float in [1.0, -1.0]:
			var ai: Vector2 = a + na * hw * sg
			var bi: Vector2 = b + nb * hw * sg
			var ao: Vector2 = a + na * (hw + fe) * sg
			var bo: Vector2 = b + nb * (hw + fe) * sg
			tri.append_array([ai, bi, bo, ai, bo, ao])
			cols.append_array([col, col, c0, col, c0, c0])


## 平铺（奇数块水平镜像，任何横条都能无缝）
func _tiled(n: CanvasItem, key: StringName, off: float, y: float, h: float, W: float, alpha: float) -> void:
	var tex: Texture2D = SpriteDB.tex(key)
	if tex == null or h <= 1.0 or alpha <= 0.003:
		return
	var w: float = h * SpriteDB.aspect(key)
	var n0: int = int(floorf(off / w))
	var x: float = n0 * w - off
	var i: int = n0
	while x < W:
		var xa: float = floorf(x)
		var wi: float = floorf(x + w) - xa
		if wi > 0.0:
			if i & 1:
				n.draw_set_transform(Vector2(xa + wi, y), 0.0, Vector2(-1.0, 1.0))
				n.draw_texture_rect(tex, Rect2(0, 0, wi, h), false, Color(1, 1, 1, alpha))
			else:
				n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				n.draw_texture_rect(tex, Rect2(xa, y, wi, h), false, Color(1, 1, 1, alpha))
		x += w
		i += 1
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _set_mat(nm: StringName, lo: float, hi: float, edge: float) -> void:
	var n: Node2D = _layers[nm]
	var m: ShaderMaterial = n.material
	var pc: Array[Color] = _pal(&"veil" if nm == &"veil" else nm, sim.night_k())
	m.set_shader_parameter(&"fill_color", pc[0])
	m.set_shader_parameter(&"line_color", pc[1])
	m.set_shader_parameter(&"lo", lo)
	m.set_shader_parameter(&"hi", hi)
	m.set_shader_parameter(&"edge", edge)


func _draw_layer(nm: StringName) -> void:
	var n: Node2D = _layers[nm]
	var vp: Vector2 = get_viewport_rect().size
	var W: float = vp.x
	var H: float = vp.y
	var u: float = H / 900.0
	var alt: float = _alt()
	match nm:
		&"olympus":
			_set_mat(nm, 0.15, 0.75, 0.0)
			var tex: Texture2D = SpriteDB.tex(&"bg_olympus")
			if tex != null:
				n.draw_texture_rect(tex, _olympus(W, H), false)
		&"veil":
			var va: float = 1.0 - _smooth(420.0, 650.0, alt)
			if va <= 0.0:
				return
			_set_mat(nm, 0.35, 0.85, 0.15)
			var key: StringName = &"bg_clouds_v2" if SpriteDB.has(&"bg_clouds_v2") else &"bg_clouds"
			var O: Rect2 = _olympus(W, H)
			var vw: float = O.size.x * 1.35
			var vh: float = vw / SpriteDB.aspect(key)
			var x0: float = O.position.x + O.size.x / 2.0 - vw / 2.0 + sin(t * 0.07) * W * 0.015
			_tiled(n, key, -x0, O.position.y + O.size.y * 0.075 - vh * 0.47, vh, W, va * 0.9)
		&"range":
			_set_mat(nm, 0.15, 0.75, 0.0)
			_ground(n, &"bg_range", vx * 0.5 * u, H * (0.28 + 0.00035 * alt), H * 0.42, W, H)
		&"hills", &"coast":
			_set_mat(nm, 0.15, 0.75, 0.0)
			var gm: Array = _ground_geom(nm, W, H, u, alt)
			_ground(n, gm[0], gm[1], gm[2], gm[3], W, H)
			if nm == &"coast":
				_draw_waves(n, gm, W, H, u)
		&"clouds":
			_set_mat(nm, 0.35, 0.85, 0.15)
			var key3: StringName = &"bg_clouds_v2" if SpriteDB.has(&"bg_clouds_v2") else &"bg_clouds"
			var cy: float = minf(H * 0.74, H * (0.5 + (alt - 590.0) * 0.0035))
			var sea_k: float = _smooth(590.0, 650.0, alt)
			var h1: float = H * 0.22
			var cy1: float = cy - H * 0.07 * (0.3 + sea_k)
			if cy1 + h1 > 0.0:
				_tiled(n, key3, vx * 0.6 * u + t * 6.0, cy1 - h1 * 0.48, h1, W, 0.6)
			var h2: float = H * 0.36
			if sea_k > 0.0:
				n.draw_texture_rect(_black, Rect2(0, cy + h2 * 0.05, W, H - cy), false, Color(1, 1, 1, sea_k))
			if cy + h2 > 0.0:
				_tiled(n, key3, vx * u - t * 9.0, cy - h2 * 0.48, h2, W, 0.85)
			if sea_k > 0.0:
				var h3: float = H * 0.5
				var cy3: float = cy + H * 0.16
				_tiled(n, key3, vx * 1.7 * u + t * 14.0, cy3 - h3 * 0.48, h3, W, 0.45 * sea_k)


## 地面层的贴图与平铺参数：[key, 偏移, 顶边 y, 高]
func _ground_geom(nm: StringName, _W: float, H: float, u: float, alt: float) -> Array:
	if nm == &"hills":
		return [&"bg_hills", vx * 1.4 * u, H * (0.34 + 0.0013 * alt), H * 0.4]
	var key2: StringName = &"bg_coast_v2" if SpriteDB.has(&"bg_coast_v2") else &"bg_coast"
	return [key2, vx * 1.6 * u, H * (0.44 + 0.0022 * alt), H * 0.4]


## 灯火点位（= background.js placeLamps）：在每列不透明顶边下方 6–40px（按 0.6 倍缩小的贴图像素）撒点，必须落在剪影里；
## 海岸的点只放在地平线以上的陆地上，另在地平线上放几只渔船。
func _lamps_for(key: StringName, nm: StringName) -> Dictionary:
	if _lamp_pts.has(key):
		return _lamp_pts[key]
	var out: Dictionary = {"lamps": [], "boats": []}
	_lamp_pts[key] = out
	var tex: Texture2D = SpriteDB.tex(key)
	if tex == null:
		return out
	var img: Image = tex.get_image()
	if img == null:
		return out
	if img.is_compressed():
		img.decompress()
	var w: int = maxi(1, roundi(img.get_width() * 0.6))
	var h: int = maxi(1, roundi(img.get_height() * 0.6))
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var top: PackedInt32Array = []
	top.resize(w)
	for x: int in w:
		top[x] = -1
		for y: int in h:
			if img.get_pixel(x, y).a > 0.5:
				top[x] = y
				break
	var opt: Dictionary = LAMP_OPT[nm]
	var R: JsRng = JsRng.new(float(opt["seed"]))
	var fishing: int = int(opt["fishing"])
	var horizon: int = h
	if fishing > 0:
		var hist: Dictionary = {}
		for x: int in w:
			if top[x] >= 0:
				hist[top[x]] = int(hist.get(top[x], 0)) + 1
		var best: int = 0
		for y: Variant in hist.keys():
			if int(hist[y]) > best:
				best = int(hist[y])
				horizon = int(y)
	var lamps: Array = []
	var k: int = 0
	while k < 400 and lamps.size() < int(opt["lamps"]):
		k += 1
		var x: int = 6 + int(floorf(R.next() * (w - 12)))
		if top[x] < 0:
			continue
		if fishing > 0 and top[x] > horizon - 6:
			continue
		var y: int = top[x] + 6 + int(floorf(R.next() * 34))
		if fishing > 0 and y > horizon - 2:
			continue
		if y >= h or img.get_pixel(x, y).a <= 200.0 / 255.0:
			continue
		var clash: bool = false
		for q: Vector4 in lamps:
			if absf(q.x * w - x) < 14.0 and absf(q.y * h - y) < 10.0:
				clash = true
				break
		if clash:
			continue
		lamps.append(Vector4(float(x) / w, float(y) / h, 0.3 + R.next() * 0.55, R.next() * 6.28))
	out["lamps"] = lamps
	var boats: Array = []
	k = 0
	while fishing > 0 and k < 200 and boats.size() < fishing:
		k += 1
		var bx: int = 20 + int(floorf(R.next() * (w - 40)))
		if absi(top[bx] - horizon) > 1:
			continue
		var near: bool = false
		for b: Vector4 in boats:
			if absf(b.x * w - bx) < w / 6.0:
				near = true
		if near:
			continue
		boats.append(Vector4(float(bx) / w, (horizon + 3.0 + R.next() * 5.0) / h, 0.35 + R.next() * 0.4, R.next() * 6.28))
	out["boats"] = boats
	out["horizon"] = float(horizon) / h if fishing > 0 else 1.0
	return out


## 海面的浪纹（瓶画式的小波浪笔画）：海岸图层地平线以下那一大片平涂上，近处稀疏、长、亮一点，
## 越往地平线越密、越短、越淡（透视）；跟海岸层同一视差平移，再慢慢漂。画在海岸层节点上，用它的线色（白 = 线色）。
const WAVE_N: int = 64


func _draw_waves(n: CanvasItem, gm: Array, W: float, H: float, u: float) -> void:
	var pts: Dictionary = _lamps_for(gm[0], &"coast")
	var hz: float = float(gm[2]) + float(pts.get("horizon", 1.0)) * float(gm[3]) + 6.0 * u
	if hz >= H - 8.0:
		return
	var span: float = W * 1.4
	var R: JsRng = JsRng.new(37.0)
	# 几十道浪攒成一批三角形画（逐道 draw_polyline 是一道一次绘制调用）；背景细节简 / 中只画前 24 / 44 道（同一套随机数，少画后面的）
	var tri: PackedVector2Array = []
	var cols: PackedColorArray = []
	var nw: int = [24, 44, WAVE_N][clampi(Settings.bg_level, 0, 2)]
	for i: int in nw:
		var fx: float = R.next()
		var f: float = pow(R.next(), 0.7)              # 0 = 地平线，1 = 画面底
		var y: float = hz + (H - hz) * f * f
		if y > H - 4.0:
			continue
		var len: float = (8.0 + 30.0 * f) * u * (0.7 + 0.6 * R.next())
		var x: float = fposmod(fx * span - float(gm[1]) * (0.8 + 0.4 * f) - t * (2.0 + 4.0 * f) * u, span) - W * 0.2
		var amp: float = (0.8 + 1.8 * f) * u
		var a: float = 0.12 + 0.28 * f
		var q: PackedVector2Array = []
		for k: int in 7:
			var s2: float = float(k) / 6.0
			q.append(Vector2(x + s2 * len, y - sin(s2 * TAU) * amp * (1.0 - absf(s2 - 0.5)) ))
		_aa_strip(tri, cols, q, maxf(1.0, (0.8 + 0.6 * f) * u), Color(1, 1, 1, a))
	if not tri.is_empty():
		RenderingServer.canvas_item_add_triangle_array(n.get_canvas_item(), PackedInt32Array(), tri, cols)


## 一盏灯：2×2 金点 + 半径 6px 光晕（透明度 0.25）；黄昏 night_k 0.3–0.9 之间按自己的延迟亮起
func _draw_lamps(nm: StringName) -> void:
	var n: Node2D = _lamp_nodes[nm]
	var nk: float = sim.night_k()
	if nk <= 0.25:
		# 撒点要读背景贴图的像素（导出版从显卡读回来，一次几到几十毫秒）：白天第一帧（开局黑屏底下）就先算好，别等到黄昏亮灯时卡一下
		if not _lamp_warm.has(nm):
			_lamp_warm[nm] = true
			var v0: Vector2 = get_viewport_rect().size
			_lamps_for(_ground_geom(nm, v0.x, v0.y, v0.y / 900.0, _alt())[0], nm)
		return
	var vp: Vector2 = get_viewport_rect().size
	var W: float = vp.x
	var H: float = vp.y
	var gm: Array = _ground_geom(nm, W, H, H / 900.0, _alt())
	var key: StringName = gm[0]
	var pts: Dictionary = _lamps_for(key, nm)
	var off: float = gm[1]
	var top: float = gm[2]
	var h: float = gm[3]
	var w: float = h * SpriteDB.aspect(key)
	var n0: int = int(floorf(off / w))
	var x0: float = n0 * w - off
	var i: int = n0
	# 先收集，再先画全部光晕、后画全部金点和倒影：光晕（纹理）和金点（无纹理矩形）交替画会一盏灯拆成两次绘制调用
	var glows: Array[Vector4] = []      # 圆心 x、y、透明度、点大小
	var reflect: Array[Vector4] = []    # 倒影短线 x、y、宽、透明度
	while x0 < W:
		var xa: float = floorf(x0)
		var wi: float = floorf(x0 + w) - xa
		var mir: bool = (i & 1) == 1
		for p: Vector4 in pts["lamps"]:
			var on: float = clampf((nk - p.z) / 0.12, 0.0, 1.0)
			if on <= 0.0:
				continue
			var x: float = (xa + wi - p.x * wi) if mir else (xa + p.x * wi)
			var y: float = top + p.y * h
			if x < -8.0 or x > W + 8.0 or y > H:
				continue
			glows.append(Vector4(roundf(x), roundf(y), on * (0.65 + 0.15 * sin(t * 1.2566 + p.w)), 2.0))
		for b: Vector4 in pts["boats"]:
			var on2: float = clampf((nk - b.z) / 0.12, 0.0, 1.0)
			if on2 <= 0.0:
				continue
			var bx2: float = (xa + wi - b.x * wi) if mir else (xa + b.x * wi)
			var by2: float = top + b.y * h
			if bx2 < -8.0 or bx2 > W + 8.0 or by2 > H:
				continue
			# 渔火：1.5px 点 + 下方 3 道断续的倒影短线
			glows.append(Vector4(bx2, by2, on2 * 0.6, 1.5))
			for kk: int in range(1, 4):
				var ww: float = 5.0 - kk + sin(t * 2.0 + kk + b.w) * 1.2
				reflect.append(Vector4(bx2 - ww / 2.0, by2 + 2.0 + kk * 2.2, ww, on2 * 0.32))
		x0 += w
		i += 1
	# 背景细节"简"：只画金点，不画光晕
	if Settings.bg_level > 0:
		for g: Vector4 in glows:
			if g.z > 0.01:
				Glow.draw(n, Vector2(g.x, g.y), 6.0, Color(Palette.GOLD, g.z * 0.25))
	for g: Vector4 in glows:
		if g.z > 0.01:
			n.draw_rect(Rect2(Vector2(g.x, g.y) - Vector2(g.w, g.w) / 2.0, Vector2(g.w, g.w)), Color(Palette.GOLD, g.z))
	for r: Vector4 in reflect:
		n.draw_rect(Rect2(r.x, r.y, r.z, 0.9), Color(Palette.GOLD, r.w))


## 平铺一层"地面"背景，并把图层下方一直填到画面底（用黑色小纹理画，shader 会把它上成填充色）
func _ground(n: CanvasItem, key: StringName, off: float, top: float, h: float, W: float, H: float) -> void:
	if top >= H:
		return
	_tiled(n, key, off, top, h, W, 1.0)
	if top + h < H:
		n.draw_texture_rect(_black, Rect2(0, floorf(top + h - 1.0), W, H - (top + h) + 2.0), false)


func _draw_sunmoon() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var W: float = vp.x
	var H: float = vp.y
	var tod: float = sim.tod()
	var nk: float = sim.night_k()
	var sr: float = minf(W, H) * 0.045
	if nk < 0.999:
		var pp: float = clampf(tod, -0.05, 1.08)
		var sp: Vector2 = Vector2(W * (0.08 + 0.84 * pp), H * (0.58 - 0.42 * sin(PI * pp)))
		var a: float = (1.0 - 0.25 * _smooth(600.0, 1000.0, _alt())) * (1.0 - nk)
		_sunmoon.draw_circle(sp, sr, Color(0.07, 0.05, 0.04, a))
		for i: int in 24:
			var an: float = i / 24.0 * TAU + t * 0.05
			var l: float = 1.75 if i % 2 == 1 else 2.15
			var dv: Vector2 = Vector2(cos(an), sin(an))
			_sunmoon.draw_line(sp + dv * sr * 1.28, sp + dv * sr * l, Color(0.913, 0.827, 0.659, 0.75 * a), 2.0)
		_sunmoon.draw_arc(sp, sr * 0.72, 0.0, TAU, 32, Color(0.913, 0.827, 0.659, 0.55 * a), 1.2)
		var rim: float = maxf(1.0 - tod / 0.1, (tod - 0.88) / 0.06)
		if rim > 0.0:
			_sunmoon.draw_arc(sp, sr + 1.5, 0.0, TAU, 40, Color(Palette.GOLD, a * clampf(rim, 0.0, 1.0)), 2.2, true)
	if nk > 0.001:
		var pm: float = (0.9 + 0.5 * clampf(tod, 0.0, 0.1)) if tod < 1.0 else (0.04 + 0.5 * clampf((tod - 1.0) / 0.56, 0.0, 1.0))
		var mp: Vector2 = Vector2(W * (0.08 + 0.84 * pm), H * (0.58 - 0.42 * sin(PI * pm)))
		var mr: float = minf(W, H) * 0.05
		_sunmoon.draw_circle(mp, mr, Color(0.875, 0.91, 0.96, nk))
		var sky: Array[Color] = sky_at(_alt(), tod, nk)
		_sunmoon.draw_circle(mp + Vector2(mr * 0.45, -mr * 0.15), mr * 0.9, Color(sky[0], nk))


func _draw_tint() -> void:
	var col: Color = tint_at(sim.tod(), sim.night_k())
	if col.is_equal_approx(Color.WHITE):
		return
	var vp: Vector2 = get_viewport_rect().size
	_tint.draw_rect(Rect2(Vector2.ZERO, vp), col)


## 时刻染色（乘色）：清晨偏冷紫、傍晚偏暖橙红，正午 = 白；远景整屏乘它，山体着色器（tod_tint）也乘它，两边同一个时刻观感
static func tint_at(tod: float, nk: float) -> Color:
	if nk >= 0.999:
		return Color.WHITE
	var i: int = 0
	while i + 2 < TINT_TOD.size() and tod > float(TINT_TOD[i + 1][0]):
		i += 1
	var a: Array = TINT_TOD[i]
	var b: Array = TINT_TOD[i + 1]
	var u: float = clampf((tod - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
	var col: Color = (a[1] as Color).lerp(b[1] as Color, u)
	var ta: float = (float(a[2]) + (float(b[2]) - float(a[2])) * u) * (1.0 - nk)
	if ta <= 0.003:
		return Color.WHITE
	return Color.WHITE.lerp(col, ta)
