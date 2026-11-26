class_name EndingScenes
extends RefCounted
## 9 段结局演出的绘制（= proto/js/endings.js 的 SCENES / REVEALS / drawReveal / drawChrome 及全部绘制函数）。
## 全是静态函数：c 是 EndCanvas（画布上下文），p 是 EndingPlayer（读 t / flags / types / stuck / day / 结局定义）。
## 黑绘：墨色剪影 + 米色刻线；金色只出现在太阳和火焰里。素材 end_* / npc_* 存在时用素材，否则用程序剪影（同网页）。
## 与网页的差异：
##   · 'lighter' 叠加混合用普通 alpha 混合 + Glow 柔光近似；
##   · 陶瓶拉远 / 揭示碎片的离屏画布由 EndingPlayer 的 SubViewport 提供（EndingScenes.offscreen 决定画什么）；
##   · 揭示前 0.4 秒的裂纹阶段直接重画冻结帧（场景对固定时刻是确定的），碎片阶段用离屏纹理贴多边形。

const INK: Color = Color("#120c0a")
const INK2: Color = Color("#1d0f08")
const CREAM: Color = Color("#e9d3a8")
const CREAM_HI: Color = Color("#f1e3c8")
const MUTED: Color = Color("#b9a58c")
const MUSEUM: Color = Color("#0b0807")
const GOLD: Color = Color("#f0b93a")
const GOLD_HI: Color = Color("#ffe08a")
const NIGHT: Array[Color] = [Color("#161f36"), Color("#36456a")]
const PREDAWN: Array[Color] = [Color("#5d5a72"), Color("#d2a589")]
## = mix(PREDAWN, ['#a89a8e', '#d8c4aa'], 0.42)，按网页 Math.round 取整
const DAWN: Array[Color] = [Color("#7d757e"), Color("#d5b297")]
const DAY: Array[Color] = [Color("#c6b6a0"), Color("#e0d3bc")]
const GOLD_GLOW: Color = Color(240.0 / 255.0, 185.0 / 255.0, 58.0 / 255.0, 1.0)
const CREAM_GLOW: Color = Color(241.0 / 255.0, 227.0 / 255.0, 200.0 / 255.0, 1.0)
const PLAT: float = 0.70
const BX: float = 0.55
const DEF_TYPES: PackedStringArray = ["amphora", "sheep", "house", "column", "temple", "olive_tree", "hoplite", "chariot"]
const GODS: PackedStringArray = ["god_hera", "god_athena", "god_apollo", "god_hermes", "god_ares", "god_artemis", "god_dionysus", "god_poseidon"]

static var _tree: Array[Dictionary] = []


# —————————— 小工具 ——————————

static func seg(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


static func ez(k: float) -> float:
	var x: float = clampf(k, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func sky_mix(a: Array[Color], b: Array[Color], k: float) -> Array[Color]:
	var out: Array[Color] = [a[0].lerp(b[0], k), a[1].lerp(b[1], k)]
	return out


static func r_b(W: float, H: float) -> float:
	return minf(H * 0.085, W * 0.07)


static func ltext(p: EndingPlayer, key: String, src: String) -> String:
	return Loc.t("ending.%s.%s" % [p.id, key], src)


# —————————— 入口 ——————————

static func draw_scene(id: StringName, c: EndCanvas, W: float, H: float, t: float, p: EndingPlayer) -> void:
	match id:
		&"sunrise":
			scene_sunrise(c, W, H, t, p)
		&"home":
			scene_home(c, W, H, t, p)
		&"spring":
			scene_spring(c, W, H, t, p)
		&"true":
			scene_true(c, W, H, t, p)
		&"debt":
			scene_debt(c, W, H, t, p)
		&"ferry":
			scene_ferry(c, W, H, t, p)
		&"immortal":
			scene_immortal(c, W, H, t, p)
		&"throne":
			scene_throne(c, W, H, t, p)
		&"sleep":
			scene_sleep(c, W, H, t, p)
		_:
			c.fill_rect(0, 0, W, H, INK)


static func draw_reveal_scene(id: StringName, c: EndCanvas, W: float, H: float, rt: float, p: EndingPlayer) -> void:
	match id:
		&"ferry":
			reveal_ferry(c, W, H, rt, p)
		&"immortal":
			reveal_immortal(c, W, H, rt, p)
		&"throne":
			reveal_throne(c, W, H, rt, p)
		&"sleep":
			reveal_sleep(c, W, H, rt, p)
		_:
			c.fill_rect(0, 0, W, H, INK)


## 这一刻离屏画布要画什么：{mode: &"vase" | &"freeze" | &""，t: 内层时间}。提前 0.5 秒开始画，避免切换那一帧空白。
static func offscreen(p: EndingPlayer, t: float) -> Dictionary:
	if p.def.reveal > 0.0 and t >= p.def.dur - 0.05:
		return {"mode": &"freeze", "t": p.def.dur - 0.001}
	if p.id == &"sunrise" and t >= 9.0:
		return {"mode": &"vase", "t": minf(t, 9.5) + maxf(0.0, t - 9.5) * 0.3}
	if p.id == &"true" and t >= 15.5:
		return {"mode": &"vase", "t": 16.0}
	return {"mode": &"", "t": 0.0}


## 离屏画布的内容（vase：陶瓶画板里的场景；freeze：假结局演出的最后一帧）
static func draw_offscreen(c: EndCanvas, W: float, H: float, p: EndingPlayer, mode: StringName, ti: float) -> void:
	if mode == &"freeze":
		draw_scene(p.id, c, W, H, ti, p)
	elif mode == &"vase":
		if p.id == &"sunrise":
			sunrise_frame(c, W, H, ti, p)
		elif p.id == &"true":
			true_inner(c, W, H, ti, p)


# —————————— 通用绘制 ——————————

## 天空：0 → y1 线性渐变，y1 以下用底色
static func sky(c: EndCanvas, W: float, H: float, top: Color, bot: Color, y1: float = -1.0) -> void:
	var yy: float = H if y1 < 0.0 else y1
	c.vgrad(0, 0, W, yy, top, bot)
	if yy < H:
		c.fill_rect(0, yy, W, H - yy, bot)


static func stars(c: EndCanvas, W: float, H: float, a: float, seed_v: int = 7) -> void:
	if a <= 0.01:
		return
	var r: EndCanvas.Rnd = EndCanvas.Rnd.new(seed_v)
	for i: int in 70:
		var x: float = r.next() * W
		var y: float = r.next() * H * 0.55
		var s: float = (1.6 if r.next() < 0.15 else 1.0) * c.u
		var aa: float = a * (0.25 + 0.5 * r.next())
		c.fill_rect(x, y, s, s, Color(CREAM_HI, aa))


## 月牙（= 圆减去偏移圆；网页用 destination-out）
static func moon(c: EndCanvas, x: float, y: float, r: float, a: float = 1.0) -> void:
	if a <= 0.0:
		return
	var parts: Array[PackedVector2Array] = Geometry2D.clip_polygons(EndCanvas.circle_pts(x, y, r), EndCanvas.circle_pts(x + r * 0.45, y - r * 0.15, r * 0.9))
	for poly: PackedVector2Array in parts:
		if not Geometry2D.is_polygon_clockwise(poly) or parts.size() == 1:
			c.fill_poly(poly, Color(Color("#dfe8f5"), a))


static func sea(c: EndCanvas, W: float, H: float, hz: float, dk: float) -> void:
	c.fill_rect(0, hz, W, H - hz, Color("#0f1526").lerp(Color("#4a4650"), dk))
	var rows: Array[Vector2] = [Vector2(6, 0.24), Vector2(15, 0.17), Vector2(28, 0.11)]
	for i: int in rows.size():
		var a: float = rows[i].y * (0.6 + 0.4 * dk)
		c.dashed_h(0, W, hz + rows[i].x * c.u, (22 + i * 14) * c.u, (16 + i * 10) * c.u, i * 13 * c.u, Color(CREAM, a), 1.0 * c.u)


static func far_range(c: EndCanvas, W: float, H: float, hz: float, col: Color) -> void:
	var pts: PackedVector2Array = [Vector2(0, hz)]
	for q: Vector2 in [Vector2(0, -0.02), Vector2(0.08, -0.05), Vector2(0.16, -0.03), Vector2(0.22, -0.07), Vector2(0.3, -0.035), Vector2(0.36, -0.01), Vector2(0.42, 0)]:
		pts.append(Vector2(q.x * W, hz + q.y * H))
	pts.append(Vector2(0.42 * W, hz + 2))
	pts.append(Vector2(0, hz + 2))
	c.fill_poly(pts, col)


## 山顶剪影：平台 x 0.36–0.64W，y = H·0.70
static func summit_mass(c: EndCanvas, W: float, H: float, line_a: float = 0.55) -> void:
	var src: Array[Vector2] = [Vector2(-0.05, 1.05), Vector2(-0.05, 0.93), Vector2(0.1, 0.86), Vector2(0.22, 0.79), Vector2(0.31, 0.73), Vector2(0.36, PLAT), Vector2(0.64, PLAT), Vector2(0.69, 0.725), Vector2(0.8, 0.8), Vector2(0.93, 0.89), Vector2(1.05, 0.95), Vector2(1.05, 1.05)]
	var pts: PackedVector2Array = []
	for q: Vector2 in src:
		pts.append(Vector2(q.x * W, q.y * H))
	c.fill_poly(pts, INK)
	# 刻线：山脊下沿一道米色细线 + 两道地层
	var ridge: PackedVector2Array = []
	for i: int in range(1, src.size() - 1):
		ridge.append(Vector2(src[i].x * W, src[i].y * H + 5 * c.u))
	c.stroke(ridge, Color(CREAM, line_a), 1.4 * c.u)
	var a2: Color = Color(CREAM, line_a * 0.45)
	c.stroke(PackedVector2Array([Vector2(0.05 * W, 0.95 * H), Vector2(0.3 * W, 0.84 * H), Vector2(0.62 * W, 0.83 * H), Vector2(0.9 * W, 0.97 * H)]), a2, 1.0 * c.u)
	c.stroke(PackedVector2Array([Vector2(0.4 * W, 0.76 * H), Vector2(0.55 * W, 0.775 * H), Vector2(0.7 * W, 0.8 * H)]), a2, 1.0 * c.u)
	if EndCanvas.has_spr(&"end_summit_rock"):
		c.spr(&"end_summit_rock", 0.5 * W, PLAT * H + H * 0.05, H * 0.14)


static func boulder(c: EndCanvas, x: float, y: float, r: float, rot: float = 0.0, line_a: float = 0.7) -> void:
	c.save()
	c.translate(x, y)
	c.rotate(rot)
	c.fill_circle(0, 0, r, INK)
	var lc: Color = Color(CREAM, line_a)
	var lw: float = maxf(1.0 * c.u, r * 0.03)
	c.stroke_circle(0, 0, r * 0.88, lc, lw)
	var a: PackedVector2Array = [Vector2(-r * 0.55, -r * 0.18)]
	EndCanvas.quad_to(a, a[0], Vector2(-r * 0.1, -r * 0.48), Vector2(r * 0.38, -r * 0.3))
	c.stroke(a, lc, lw)
	var b: PackedVector2Array = [Vector2(-r * 0.35, r * 0.38)]
	EndCanvas.quad_to(b, b[0], Vector2(r * 0.1, r * 0.16), Vector2(r * 0.48, r * 0.38))
	c.stroke(b, lc, lw)
	c.line(-r * 0.15, -r * 0.02, r * 0.12, r * 0.04, lc, lw)
	c.restore()


## 火焰：金色只给火
static func flame(c: EndCanvas, x: float, y: float, h: float, t: float, seed_v: float = 0.0, a: float = 1.0) -> void:
	if h <= 0.5 or a <= 0.0:
		return
	c.save()
	c.alpha = a
	c.glow(x, y - h * 0.4, h * 1.5, Color(GOLD_GLOW, 0.32))
	for i: int in 3:
		var ph: float = t * (7.0 + i * 2.3) + seed_v * 3.1 + i * 2.0
		var hh: float = h * (1.0 - i * 0.22) * (1.0 + sin(ph) * 0.1)
		var ww: float = h * (0.42 - i * 0.1)
		var sw: float = sin(ph * 0.7) * ww * 0.35
		c.alpha = a * (0.85 if i == 0 else 1.0)
		var pts: PackedVector2Array = [Vector2(x - ww, y)]
		EndCanvas.quad_to(pts, pts[0], Vector2(x - ww * 0.9, y - hh * 0.55), Vector2(x + sw, y - hh), 10)
		EndCanvas.quad_to(pts, Vector2(x + sw, y - hh), Vector2(x + ww * 0.9, y - hh * 0.5), Vector2(x + ww, y), 10)
		c.fill_poly(pts, GOLD_HI if i == 2 else GOLD)
	c.restore()


## 黑绘太阳：空心圆 + 放射刻纹，内部按 fill_k 从下往上填金（地平线以下由随后画的海盖住，不再裁剪）
static func sun_disc(c: EndCanvas, cx: float, cy: float, R: float, ring_k: float, ray_k: float, fill_k: float) -> void:
	c.save()
	if fill_k > 0.0:
		c.glow(cx, cy, R * 2.6, Color(GOLD_GLOW, 0.22 * fill_k))
		var top: float = cy + R - 2.0 * R * fill_k
		var inner: PackedVector2Array = EndCanvas.circle_pts(cx, cy, R * 0.92)
		for poly: PackedVector2Array in Geometry2D.intersect_polygons(inner, EndCanvas.rect_pts(cx - R, top, 2.0 * R, cy + R - top)):
			c.fill_poly(poly, GOLD)
		c.fill_circle(cx - R * 0.25, cy - R * 0.25, R * 0.35, Color(GOLD_HI, 0.5))
	if EndCanvas.has_spr(&"end_sun_disc"):
		c.alpha *= maxf(ring_k, ray_k)
		c.spr(&"end_sun_disc", cx, cy + R * 1.45, R * 2.9)
	else:
		var lw: float = maxf(1.2 * c.u, R * 0.04)
		if ring_k > 0.0:
			c.stroke(EndCanvas.arc_pts(cx, cy, R, PI, PI + TAU * ring_k), CREAM, lw)
		if ray_k > 0.0:
			var lw2: float = maxf(1.0 * c.u, R * 0.03)
			for i: int in 18:
				var a: float = float(i) / 18.0 * TAU
				var k: float = clampf(ray_k * 1.4 - i / 30.0, 0.0, 1.0)
				if k <= 0.0:
					continue
				var r2: float = R * (1.12 + 0.38 * k * (0.7 if i % 2 == 1 else 1.0))
				c.line(cx + cos(a) * R * 1.12, cy + sin(a) * R * 1.12, cx + cos(a) * r2, cy + sin(a) * r2, CREAM, lw2)
	c.restore()


## 刻字：逐字出现（米色），按宽度折行；返回占用高度
static func carve(c: EndCanvas, s: String, x: float, y: float, k: float, size: int, max_w: float, weight: int = 600, col: Color = CREAM_HI) -> float:
	if k <= 0.0 or s == "":
		return 0.0
	var font: Font = Fonts.serif(weight)
	var lines: PackedStringArray = EndCanvas.wrap(font, s, size, max_w)
	var total: int = 0
	for l: String in lines:
		total += l.length()
	var left: int = floori(total * clampf(k, 0.0, 1.0) + 0.999)
	var lh: float = size * 1.5
	for i: int in lines.size():
		var l: String = lines[i]
		var vis: String = l.substr(0, maxi(0, left))
		left -= l.length()
		if vis == "":
			continue
		var yy: float = y + i * lh
		# 逐字出现时位置不跳：按整行宽度定左端
		var x0: float = x - EndCanvas.text_w(font, l, size) / 2.0
		c.text(vis, x0 + 1.0 * c.u, yy + 1.5 * c.u, font, size, Color(0, 0, 0, 0.6), -1)
		c.text(vis, x0, yy, font, size, col, -1)
	return lines.size() * lh


static func carve_size(c: EndCanvas, div: float, lo: float, hi: float) -> int:
	return c.fsz(c.wc / div, lo, hi)


## 陶瓶：把离屏场景收进"瓶身画板"，镜头拉远（k 0→1）；返回 {bottom, top}
static func vase_pull(c: EndCanvas, W: float, H: float, k: float, p: EndingPlayer, cy_o: float, sc: float) -> Dictionary:
	var pw: float = W * sc
	var ph: float = H * sc
	var cx: float = W / 2.0
	var cy: float = cy_o
	var z: float = lerpf(W / pw, 1.0, ez(k))
	c.save()
	c.fill_rect(0, 0, W, H, MUSEUM)
	c.glow(W / 2.0, H * 0.45, maxf(W, H) * 0.7, Color(60.0 / 255.0, 44.0 / 255.0, 32.0 / 255.0, 0.55))
	c.translate(W / 2.0, H / 2.0)
	c.scale(z, z)
	c.translate(-cx, -cy)
	vase_body(c, cx, cy, pw, ph, z)
	var tex: Texture2D = p.off_texture()
	if tex != null:
		c.ci.draw_texture_rect(tex, Rect2(cx - pw / 2.0, cy - ph / 2.0, pw, ph), false, c.cc(Color.WHITE))
	# 画板边：米色细线 + 回纹带
	c.alpha = 0.8
	c.stroke_rect(cx - pw / 2.0, cy - ph / 2.0, pw, ph, CREAM, 1.5 * c.u / z)
	meander_band(c, cx - pw / 2.0, cy - ph / 2.0 - ph * 0.09, pw, ph * 0.07, z)
	meander_band(c, cx - pw / 2.0, cy + ph / 2.0 + ph * 0.02, pw, ph * 0.07, z)
	c.restore()
	var art: bool = EndCanvas.has_spr(&"end_vase_frame")
	return {"bottom": H / 2.0 + ph * (1.25 if art else 1.18) * z, "top": H / 2.0 - ph * (1.35 if art else 1.32) * z}


static func vase_body(c: EndCanvas, cx: float, cy: float, pw: float, ph: float, z: float) -> void:
	if EndCanvas.has_spr(&"end_vase_frame"):
		c.fill_poly(EndCanvas.round_rect_pts(cx - pw * 0.72, cy - ph * 0.82, pw * 1.44, ph * 1.86, pw * 0.3), INK)
		c.spr(&"end_vase_frame", cx, cy + ph * 1.25, ph * 2.6)
		return
	var bw: float = pw * 0.78
	var top: float = cy - ph * 0.78
	var bot: float = cy + ph * 1.02
	var neck_w: float = pw * 0.26
	var mouth_y: float = cy - ph * 1.28
	var pts: PackedVector2Array = [Vector2(cx - neck_w * 1.25, mouth_y), Vector2(cx + neck_w * 1.25, mouth_y), Vector2(cx + neck_w * 1.25, mouth_y + ph * 0.07), Vector2(cx + neck_w, mouth_y + ph * 0.1), Vector2(cx + neck_w, top - ph * 0.04)]
	EndCanvas.cubic_to(pts, pts[pts.size() - 1], Vector2(cx + bw * 1.05, top), Vector2(cx + bw * 1.1, cy + ph * 0.2), Vector2(cx + bw * 0.86, cy + ph * 0.62))
	EndCanvas.cubic_to(pts, pts[pts.size() - 1], Vector2(cx + bw * 0.62, bot - ph * 0.1), Vector2(cx + pw * 0.2, bot), Vector2(cx + pw * 0.16, bot))
	pts.append(Vector2(cx + pw * 0.26, bot + ph * 0.14))
	pts.append(Vector2(cx - pw * 0.26, bot + ph * 0.14))
	pts.append(Vector2(cx - pw * 0.16, bot))
	EndCanvas.cubic_to(pts, pts[pts.size() - 1], Vector2(cx - pw * 0.2, bot), Vector2(cx - bw * 0.62, bot - ph * 0.1), Vector2(cx - bw * 0.86, cy + ph * 0.62))
	EndCanvas.cubic_to(pts, pts[pts.size() - 1], Vector2(cx - bw * 1.1, cy + ph * 0.2), Vector2(cx - bw * 1.05, top), Vector2(cx - neck_w, top - ph * 0.04))
	pts.append(Vector2(cx - neck_w, mouth_y + ph * 0.1))
	pts.append(Vector2(cx - neck_w * 1.25, mouth_y + ph * 0.07))
	c.fill_poly(pts, INK)
	c.stroke(pts, Color(CREAM, 0.55), 1.2 * c.u / z, true)
	# 把手
	for d: float in [-1.0, 1.0]:
		var hp: PackedVector2Array = [Vector2(cx + d * neck_w, mouth_y + ph * 0.3)]
		EndCanvas.cubic_to(hp, hp[0], Vector2(cx + d * pw * 0.72, mouth_y + ph * 0.2), Vector2(cx + d * pw * 0.78, top + ph * 0.05), Vector2(cx + d * bw * 0.86, top + ph * 0.16))
		c.stroke(hp, INK, pw * 0.05)
	# 底部放射纹
	var ry: float = cy + ph * 0.66
	for i: int in range(-6, 7):
		var x0: float = cx + i * pw * 0.07
		var w: float = pw * 0.035
		c.stroke(PackedVector2Array([Vector2(x0 - w, bot - ph * 0.02), Vector2(x0, ry + absi(i) * ph * 0.012), Vector2(x0 + w, bot - ph * 0.02)]), Color(CREAM, 0.45), 1.0 * c.u / z)
	# 瓶颈棕榈纹
	for i: int in range(-1, 2):
		palmette(c, cx + i * neck_w * 0.6, mouth_y + ph * 0.36, ph * 0.12, Color(CREAM, 0.5), 1.0 * c.u / z)


static func palmette(c: EndCanvas, x: float, y: float, s: float, col: Color, lw: float) -> void:
	for i: int in range(-3, 4):
		var a: float = -PI / 2.0 + i * 0.32
		var pts: PackedVector2Array = [Vector2(x, y)]
		EndCanvas.quad_to(pts, pts[0], Vector2(x + cos(a) * s * 0.5, y + sin(a) * s * 0.6), Vector2(x + cos(a) * s, y + sin(a) * s), 8)
		c.stroke(pts, col, lw)


static func meander_band(c: EndCanvas, x: float, y: float, w: float, h: float, z: float) -> void:
	var n: int = maxi(6, floori(w / h))
	var uu: float = w / n
	var col: Color = Color(CREAM, 0.55 / maxf(c.alpha, 0.001))
	var lw: float = 1.0 * c.u / z
	for i: int in n:
		var x0: float = x + i * uu
		c.stroke(PackedVector2Array([Vector2(x0, y + h), Vector2(x0, y), Vector2(x0 + uu * 0.8, y), Vector2(x0 + uu * 0.8, y + h * 0.7), Vector2(x0 + uu * 0.35, y + h * 0.7), Vector2(x0 + uu * 0.35, y + h * 0.35)]), col, lw)
	c.line(x, y + h, x + w, y + h, col, lw)


## 链节：沿折线画 n 个米色椭圆
static func chain_along(c: EndCanvas, pts: PackedVector2Array, k: float, size: float, col: Color = CREAM) -> void:
	var L: PackedFloat32Array = []
	var tot: float = 0.0
	for i: int in range(1, pts.size()):
		var d: float = pts[i].distance_to(pts[i - 1])
		L.append(d)
		tot += d
	var n: int = floori(tot / (size * 1.5))
	var m: int = floori(n * clampf(k, 0.0, 1.0))
	var lw: float = maxf(1.2 * c.u, size * 0.28)
	for j: int in m:
		var d: float = j * size * 1.5
		var i: int = 0
		while i < L.size() - 1 and d > L[i]:
			d -= L[i]
			i += 1
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var f: float = clampf(d / (L[i] if L[i] != 0.0 else 1.0), 0.0, 1.0)
		var q: Vector2 = a.lerp(b, f)
		var ang: float = atan2(b.y - a.y, b.x - a.x)
		c.stroke(EndCanvas.ellipse_pts(q.x, q.y, size, size * (0.25 if j % 2 == 1 else 0.5), ang, 0.0, TAU, 16), col, lw)


## 演职员表（k 推进，到 stall 卡住轻抖）
static func credits(c: EndCanvas, W: float, H: float, k: float, lines: PackedStringArray, stall: float = 1.0) -> void:
	c.fill_rect(0, 0, W, H, Color("#060404"))
	var lh: float = maxf(26.0 * c.u, H * 0.05)
	var tot: float = lines.size() * lh + H
	var off: float = H - minf(k, stall) * tot
	if k > stall:
		off += sin(k * 90.0) * 1.2 * c.u
	for i: int in lines.size():
		var y: float = off + i * lh
		if y < -lh or y > H + lh:
			continue
		var font: Font = Fonts.serif(700 if i == 0 else 500)
		var size: int = roundi(lh * (0.9 if i == 0 else 0.6))
		c.text(lines[i], W / 2.0, y, font, size, Color(CREAM_HI, 0.9))


# —————————— 揭示（假结局） ——————————

## 裂开：8 道裂纹 + 8 块碎片（随机种子同网页）
static func shards(p: EndingPlayer, W: float, H: float) -> Dictionary:
	if not p.cracks.is_empty() and float(p.cracks["W"]) == W and float(p.cracks["H"]) == H:
		return p.cracks
	var r: EndCanvas.Rnd = EndCanvas.Rnd.new(1337 + String(p.id).length() * 17)
	var cx: float = W * (0.46 + r.next() * 0.08)
	var cy: float = H * (0.42 + r.next() * 0.08)
	var n: int = 8
	var rays: Array[Dictionary] = []
	var lmax: float = Vector2(W, H).length()
	for i: int in n:
		var a: float = (i + r.next() * 0.6) / n * TAU
		var pts: PackedVector2Array = [Vector2(cx, cy)]
		var d: float = 0.0
		while d < lmax:
			d += lmax * (0.08 + r.next() * 0.08)
			var j: float = (r.next() - 0.5) * 0.22
			pts.append(Vector2(cx + cos(a + j) * d, cy + sin(a + j) * d))
		rays.append({"a": a, "pts": pts})
	var screen: PackedVector2Array = EndCanvas.rect_pts(0, 0, W, H)
	var pieces: Array[Dictionary] = []
	for i: int in n:
		var ray: Dictionary = rays[i]
		var nx: Dictionary = rays[(i + 1) % n]
		var poly: PackedVector2Array = (ray["pts"] as PackedVector2Array).duplicate()
		var rev: PackedVector2Array = (nx["pts"] as PackedVector2Array).duplicate()
		rev.reverse()
		poly.append_array(rev)
		var ra: float = ray["a"]
		var na: float = nx["a"]
		var mid: float = (ra + (na + TAU if na < ra else na)) / 2.0
		# 离屏纹理只覆盖屏幕范围（网页 drawImage 也只画在 0..W × 0..H），预先求交
		var clipped: Array[PackedVector2Array] = Geometry2D.intersect_polygons(poly, screen)
		pieces.append({"poly": poly, "clip": clipped, "dir": mid, "delay": r.next() * 0.12, "rot": (r.next() - 0.5) * 0.6})
	p.cracks = {"W": W, "H": H, "c": Vector2(cx, cy), "rays": rays, "pieces": pieces}
	return p.cracks


static func draw_reveal(c: EndCanvas, W: float, H: float, rt: float, p: EndingPlayer) -> void:
	var cr: Dictionary = shards(p, W, H)
	if rt < 0.4:
		# 冻结演出最后一帧（对固定时刻重画）+ 裂纹生长
		draw_scene(p.id, c, W, H, p.def.dur - 0.001, p)
		c.reset()
		var k: float = rt / 0.4
		for ray: Dictionary in cr["rays"]:
			var pts: PackedVector2Array = ray["pts"]
			var m: int = maxi(2, ceili(pts.size() * k))
			var part: PackedVector2Array = pts.slice(0, m)
			c.stroke(part, Color(0, 0, 0, 0.7), 4.0 * c.u)
			c.stroke(part, CREAM_HI, 1.6 * c.u)
		return
	# 真相在下面
	draw_reveal_scene(p.id, c, W, H, rt, p)
	c.reset()
	var fk: float = (rt - 0.4) / 0.9
	if fk >= 1.0:
		return
	var tex: Texture2D = p.off_texture()
	var center: Vector2 = cr["c"]
	for pc: Dictionary in cr["pieces"]:
		var delay: float = pc["delay"]
		var kk: float = clampf((fk - delay) / (1.0 - delay), 0.0, 1.0)
		var dir: float = pc["dir"]
		var dx: float = cos(dir) * kk * W * 0.15
		var dy: float = sin(dir) * kk * H * 0.1 + kk * kk * H * 1.1
		c.save()
		c.alpha = 1.0 - kk * 0.3
		c.translate(center.x + dx, center.y + dy)
		c.rotate(float(pc["rot"]) * kk)
		c.translate(-center.x, -center.y)
		if tex != null:
			for poly: PackedVector2Array in pc["clip"]:
				if Geometry2D.triangulate_polygon(poly).is_empty():
					continue
				var uvs: PackedVector2Array = []
				uvs.resize(poly.size())
				for i: int in poly.size():
					uvs[i] = Vector2(poly[i].x / W, poly[i].y / H)
				c.ci.draw_polygon(poly, PackedColorArray([c.cc(Color.WHITE)]), uvs, tex)
		c.stroke(pc["poly"], CREAM_HI, 1.4 * c.u, true)
		c.restore()


## 角标：结局名（左上）、跳过提示（右下）
static func draw_chrome(c: EndCanvas, W: float, H: float, p: EndingPlayer) -> void:
	c.reset()
	var a: float = minf(1.0, p.t / 0.8) * (0.5 if p.t > p.total - 0.2 else 1.0)
	c.alpha = 0.75 * a
	c.text("%s · %s" % [p.kind_label(), p.def.text("name")], 24.0 * c.u, 26.0 * c.u, Fonts.serif(600), roundi(13.0 * c.u), CREAM_HI, -1)
	if p.t >= EndingPlayer.SKIP_AT and not p.done:
		c.alpha = 0.45
		c.text(Loc.t("ending.ui.skip", "空格 / 点击 跳过"), W - 24.0 * c.u, H - 22.0 * c.u, Fonts.serif(500), roundi(12.0 * c.u), CREAM_HI, 1)
	c.alpha = 1.0


# —————————— 山顶通用场景 ——————————

## o：{sky: Array[Color], stars, moon, dk, sun: Callable(hz), behind: Callable()}
static func summit_scene(c: EndCanvas, W: float, H: float, o: Dictionary) -> void:
	var sk: Array[Color] = o["sky"]
	sky(c, W, H, sk[0], sk[1], H * 0.62)
	stars(c, W, H, float(o.get("stars", 0.0)))
	var mo: float = float(o.get("moon", 0.0))
	if mo > 0.0:
		moon(c, W * 0.16, H * 0.14, minf(W, H) * 0.035, mo)
	var hz: float = H * 0.6
	if o.has("sun"):
		(o["sun"] as Callable).call(hz)
	sea(c, W, H, hz, float(o.get("dk", 0.0)))
	far_range(c, W, H, hz, sk[1].lerp(INK, 0.5))
	if o.has("behind"):
		(o["behind"] as Callable).call()
	summit_mass(c, W, H)


# —————————— E1 日出（13s） ——————————

static func sunrise_frame(c: EndCanvas, W: float, H: float, t: float, p: EndingPlayer) -> void:
	var dk: float = ez(seg(t, 5.0, 7.5))
	var sky_c: Array[Color] = NIGHT if t < 5.0 else sky_mix(NIGHT, DAWN, dk)
	var r: float = r_b(W, H)
	var by: float = H * PLAT - r
	var bx: float = W * BX
	var sx: float = W * 0.8
	var R: float = H * 0.1
	var sun: Callable = func(hz: float) -> void:
		# 1.5–3：地平线上一道极细刻线；3–5：长成半圆，内部填金
		var lk: float = ez(seg(t, 1.5, 3.0))
		if lk > 0.0:
			c.line(sx - W * 0.6 * lk, hz, sx + W * 0.6 * lk, hz, Color(CREAM_HI, 0.9 * (1.0 - seg(t, 5.0, 6.5) * 0.6)), 1.2 * c.u)
		var rk: float = ez(seg(t, 3.0, 4.4))
		var fk: float = ez(seg(t, 3.8, 5.5))
		var rise: float = ez(seg(t, 5.0, 10.0)) * R * 0.55
		if rk > 0.0:
			sun_disc(c, sx, hz - rise, R * (0.6 + 0.4 * rk), rk, seg(t, 4.0, 5.2), fk)
	summit_scene(c, W, H, {"sky": sky_c, "stars": 1.0 - dk, "dk": dk, "moon": 1.0 - dk, "sun": sun})
	# 西西弗斯与石头
	if EndCanvas.has_spr(&"end_sisyphus_watch") and t > 0.8:
		c.spr(&"end_sisyphus_watch", bx - r * 0.4, H * PLAT + 2.0 * c.u, r * 2.3)
	else:
		boulder(c, bx, by, r)
		if t < 0.8:
			c.spr(&"push_0", bx - r - r * 0.55, H * PLAT + 1.0 * c.u, r * 1.9)
		else:
			c.spr(&"sit", bx - r - r * 0.62, H * PLAT + 2.0 * c.u + (1.0 - ez(seg(t, 0.8, 1.3))) * -r * 0.3, r * 1.45)
	# 7.5–9.5：阳光沿坡扫下，照亮本代碾得最多的 6 种物件
	var sw: float = seg(t, 7.5, 9.5)
	if t > 7.5:
		var gx: float = lerpf(W * 0.62, W * 0.05, ez(sw))
		var gy: float = lerpf(H * 0.7, H * 0.95, ez(sw))
		c.glow(gx, gy, H * 0.25, Color(CREAM, 0.16 * (1.0 - seg(t, 9.2, 10.0))))
	frieze(c, W, H, p.types, -1.0 if t < 7.5 else sw)


static func frieze(c: EndCanvas, W: float, H: float, types: PackedStringArray, k: float) -> void:
	if k < 0.0:
		return
	var y0: float = H * 0.865
	var h: float = H * 0.1
	c.fill_rect(0, y0, W, h, Color(INK, 0.92))
	c.line(0, y0 + 3.0 * c.u, W, y0 + 3.0 * c.u, Color(CREAM, 0.5), 1.0 * c.u)
	c.line(0, y0 + h - 3.0 * c.u, W, y0 + h - 3.0 * c.u, Color(CREAM, 0.5), 1.0 * c.u)
	var n: int = maxi(1, types.size())
	for i: int in types.size():
		var lit: float = clampf((k * (n + 1) - i) / 1.2, 0.0, 1.0)
		var x: float = W * (0.5 + (i - (n - 1) / 2.0) * minf(0.15, 0.9 / n))
		c.spr(StringName(types[i]), x, y0 + h - 7.0 * c.u, h * 0.72, {"alpha": 0.12 + 0.88 * lit})


static func scene_sunrise(c: EndCanvas, W: float, H: float, t: float, p: EndingPlayer) -> void:
	var pk: float = seg(t, 9.5, 11.5)
	if pk <= 0.0:
		sunrise_frame(c, W, H, minf(t, 9.5), p)
		return
	var box: Dictionary = vase_pull(c, W, H, pk, p, H * 0.43, 0.34)
	carve(c, p.def.text("text"), W / 2.0, minf(H - 40.0 * c.u, float(box["bottom"]) + 26.0 * c.u), seg(t, 11.5, 12.7), carve_size(c, 46, 16, 24), W * 0.86)


# —————————— E2 回家（9s） ——————————

static func along_path(pts: Array[Vector2], k: float, W: float, H: float) -> Vector3:
	var L: PackedFloat32Array = []
	var tot: float = 0.0
	for i: int in range(1, pts.size()):
		var d: float = Vector2((pts[i].x - pts[i - 1].x) * W, (pts[i].y - pts[i - 1].y) * H).length()
		L.append(d)
		tot += d
	var d2: float = tot * clampf(k, 0.0, 1.0)
	var i2: int = 0
	while i2 < L.size() - 1 and d2 > L[i2]:
		d2 -= L[i2]
		i2 += 1
	var a: Vector2 = pts[i2]
	var b: Vector2 = pts[i2 + 1]
	var f: float = clampf(d2 / (L[i2] if L[i2] != 0.0 else 1.0), 0.0, 1.0)
	return Vector3(lerpf(a.x, b.x, f) * W, lerpf(a.y, b.y, f) * H, atan2((b.y - a.y) * H, (b.x - a.x) * W))


static func scene_home(c: EndCanvas, W: float, H: float, t: float, p: EndingPlayer) -> void:
	var oy: float = ez(seg(t, 3.0, 6.2)) * H * 1.0
	sky(c, W, H, NIGHT[0], NIGHT[1])
	stars(c, W, H, 1.0)
	moon(c, W * 0.82, H * 0.13, minf(W, H) * 0.035)
	c.save()
	c.translate(0, -oy)
	# 远海与山体（世界坐标：山顶平台在 y=0.42H，山脚在 y=1.55H）
	var hz: float = H * 0.9
	c.fill_rect(0, hz, W, H * 2.0, Color("#0f1526"))
	var slope: Array[Vector2] = [Vector2(1.1, 0.42), Vector2(0.52, 0.42), Vector2(0.44, 0.6), Vector2(0.36, 0.8), Vector2(0.28, 1.05), Vector2(0.22, 1.3), Vector2(0.17, 1.55)]
	var body: PackedVector2Array = [Vector2(1.1 * W, 2.2 * H)]
	for q: Vector2 in slope:
		body.append(Vector2(q.x * W, q.y * H))
	body.append(Vector2(-0.1 * W, 1.55 * H))
	body.append(Vector2(-0.1 * W, 2.2 * H))
	c.fill_poly(body, INK)
	var ridge: PackedVector2Array = []
	for i: int in slope.size():
		ridge.append(Vector2(slope[i].x * W + (4.0 * c.u if i > 0 else 0.0), slope[i].y * H + 5.0 * c.u))
	ridge.append(Vector2(-0.1 * W, 1.55 * H + 5.0 * c.u))
	c.stroke(ridge, Color(CREAM, 0.5), 1.3 * c.u)
	# 石头留在山顶
	var r: float = r_b(W, H) * 0.9
	boulder(c, W * 0.64, H * 0.42 - r, r)
	# 山脚村舍
	for hs: Vector3 in [Vector3(0.62, 0.12, 0), Vector3(0.78, 0.1, 1), Vector3(0.9, 0.13, 0)]:
		c.spr(&"house", hs.x * W, 1.55 * H + 2.0 * c.u, hs.y * H, {"flip": hs.z > 0.5, "alpha": 0.95})
	# 墨洛珀举灯
	var mx: float = W * 0.4
	var my: float = 1.55 * H
	if not c.spr(&"end_merope_lamp", mx, my + 2.0 * c.u, H * 0.17):
		c.spr(&"villager_woman", mx, my + 2.0 * c.u, H * 0.16, {"flip": true})
	var lamp_a: float = 0.4 + 0.6 * seg(t, 3.5, 5.0)
	flame(c, mx - H * 0.035, my - H * 0.165, H * 0.018, t, 2.0, lamp_a)
	# 西西弗斯：转身，空手下山
	var pth: Array[Vector2] = [Vector2(0.6, 0.42), Vector2(0.52, 0.42), Vector2(0.44, 0.6), Vector2(0.36, 0.8), Vector2(0.28, 1.05), Vector2(0.22, 1.3), Vector2(0.2, 1.55), Vector2(0.34, 1.55)]
	var pk: float = ez(seg(t, 0.8, 6.3))
	var pos: Vector3 = along_path(pth, pk, W, H)
	var walking: bool = t > 0.8 and pk < 1.0
	var frame: StringName = StringName("push_%d" % (floori(t * 6.0) % 6)) if walking else &"cheer"
	var nm: StringName
	if EndCanvas.has_spr(&"end_sisyphus_walk") and walking:
		nm = &"end_sisyphus_walk"
	elif t < 0.8:
		nm = &"push_0"
	else:
		nm = frame if walking else &"push_0"
	var back: bool = pk >= 1.0
	c.spr(nm, pos.x, pos.y + 2.0 * c.u, H * 0.11 * (0.95 if walking else 1.0), {"flip": not back, "rot": pos.z * 0.35 if walking else 0.0})
	c.restore()
	carve(c, p.def.text("text"), W / 2.0, H * 0.82, seg(t, 6.6, 8.4), carve_size(c, 46, 16, 24), W * 0.86)


# —————————— E3 冥府的春天（10s） ——————————

static func tree_def() -> Array[Dictionary]:
	if not _tree.is_empty():
		return _tree
	var r: EndCanvas.Rnd = EndCanvas.Rnd.new(424242)
	var out: Array[Dictionary] = []
	_grow(out, r, 0.0, 0.0, -PI / 2.0, 1.0, 0, 0.0)
	_tree = out
	return out


static func _grow(out: Array[Dictionary], r: EndCanvas.Rnd, x: float, y: float, a: float, len_v: float, depth: int, t0: float) -> void:
	var t1: float = t0 + 0.28 + depth * 0.02
	var x2: float = x + cos(a) * len_v
	var y2: float = y + sin(a) * len_v
	out.append({"x": x, "y": y, "x2": x2, "y2": y2, "w": maxf(0.6, (5 - depth) * 0.9), "t0": t0, "t1": t1, "depth": depth, "leaf": false})
	if depth >= 4:
		out.append({"fruit": r.next() < 0.45, "leaf": true, "x": x2, "y": y2, "a": a, "t0": t1, "t1": t1 + 0.12})
		return
	var n: int = 3 if depth == 0 else 2
	for i: int in n:
		var na: float = a + (i - (n - 1) / 2.0) * (0.55 + r.next() * 0.25)
		na += (r.next() - 0.5) * 0.2
		var nl: float = len_v * (0.68 + r.next() * 0.1)
		_grow(out, r, x2, y2, na, nl, depth + 1, t1)


static func draw_tree(c: EndCanvas, x: float, y: float, s: float, k: float) -> void:
	if EndCanvas.has_spr(&"end_pomegranate_tree"):
		c.save()
		c.alpha = ez(k)
		c.spr(&"end_pomegranate_tree", x, y, s * 2.6 * (0.3 + 0.7 * ez(k)))
		c.restore()
		return
	var kk: float = k * 1.9
	for b: Dictionary in tree_def():
		var f: float = clampf((kk - float(b["t0"])) / (float(b["t1"]) - float(b["t0"])), 0.0, 1.0)
		if f <= 0.0:
			continue
		if bool(b["leaf"]):
			var px: float = x + float(b["x"]) * s
			var py: float = y + float(b["y"]) * s
			if bool(b["fruit"]):
				var fr: float = s * 0.06 * f
				c.fill_circle(px, py + 3.0, fr, INK)
				c.stroke_circle(px, py + 3.0, fr, CREAM, 1.0 * c.u)
				c.stroke(PackedVector2Array([Vector2(px - 2, py + 3 - fr), Vector2(px, py - s * 0.08 * f), Vector2(px + 2, py + 3 - fr)]), CREAM, 1.0 * c.u)
			else:
				var lp: PackedVector2Array = EndCanvas.ellipse_pts(px, py, s * 0.07 * f, s * 0.03 * f, float(b["a"]), 0.0, TAU, 16)
				c.fill_poly(lp, INK)
				c.stroke(lp, CREAM, 0.8 * c.u)
			continue
		var bx: float = float(b["x"])
		var by: float = float(b["y"])
		var p0: Vector2 = Vector2(x + bx * s, y + by * s)
		var p1: Vector2 = Vector2(x + lerpf(bx, float(b["x2"]), f) * s, y + lerpf(by, float(b["y2"]), f) * s)
		var w: float = float(b["w"]) * s * 0.025 + 1.2
		c.line(p0.x, p0.y, p1.x, p1.y, INK, w)
		c.fill_circle(p1.x, p1.y, w / 2.0, INK)
		if int(b["depth"]) < 2:
			c.line(p0.x, p0.y, p1.x, p1.y, Color(CREAM, 0.35), 1.0 * c.u)


static func scene_spring(c: EndCanvas, W: float, H: float, t: float, p: EndingPlayer) -> void:
	var dk: float = ez(seg(t, 0.0, 10.0)) * 0.75
	var r: float = r_b(W, H)
	var bx: float = W * BX
	var by: float = H * PLAT - r
	summit_scene(c, W, H, {"sky": sky_mix(NIGHT, PREDAWN, dk), "stars": 1.0 - dk, "dk": dk * 0.5, "moon": 1.0 - dk})
	boulder(c, bx, by, r)
	# 7–8.6：石头一半开出花纹（米色刻线，裁剪在右半圆里）
	var fk: float = ez(seg(t, 7.0, 8.6))
	if fk > 0.0:
		var half: PackedVector2Array = EndCanvas.arc_pts(bx, by, r * 0.86, -PI / 2.0, PI / 2.0, 24)
		var rr: EndCanvas.Rnd = EndCanvas.Rnd.new(99)
		var col: Color = Color(CREAM_HI, 0.9)
		for i: int in 7:
			var px: float = bx + r * (0.12 + rr.next() * 0.65)
			var py: float = by + r * (rr.next() * 1.4 - 0.7)
			var s: float = r * (0.12 + rr.next() * 0.1) * clampf(fk * 7.0 - i, 0.0, 1.0)
			if s <= 0.0:
				continue
			for j: int in 6:
				var a: float = j / 6.0 * TAU
				var petal: PackedVector2Array = EndCanvas.ellipse_pts(px + cos(a) * s * 0.6, py + sin(a) * s * 0.6, s * 0.45, s * 0.2, a, 0.0, TAU, 16)
				for part: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(petal, half):
					c.stroke(part, col, 1.2 * c.u)
			for part: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(EndCanvas.arc_pts(px, py, s * 0.18, 0.0, TAU, 12), half):
				c.stroke(part, col, 1.2 * c.u)
	# 石榴树（3–6.2s 生长）
	var tx: float = W * 0.41
	var ty: float = H * PLAT + 1.0 * c.u
	var mound: float = ez(seg(t, 0.4, 2.4))
	if mound > 0.0:
		c.fill_poly(EndCanvas.ellipse_pts(tx, ty, W * 0.03 * mound, H * 0.012 * mound, 0.0, PI, TAU, 16), INK)
	# 0.8–2.6：埋下石榴
	if t > 0.8 and t < 2.6:
		var k: float = seg(t, 0.8, 2.4)
		var fx: float = lerpf(tx + W * 0.03, tx, k)
		var fy: float = lerpf(H * PLAT - H * 0.07, ty - 2.0, k)
		c.fill_circle(fx, fy, H * 0.011, INK)
		c.stroke_circle(fx, fy, H * 0.011, CREAM, 1.0 * c.u)
	draw_tree(c, tx, ty, H * 0.2, seg(t, 3.0, 6.2))
	# 西西弗斯：先跪着埋，之后坐下看
	if t < 3.0:
		c.spr(&"tired", tx + W * 0.06, H * PLAT + 2.0 * c.u, r * 1.8, {"flip": true})
	else:
		c.spr(&"sit", bx - r - r * 0.62, H * PLAT + 2.0 * c.u, r * 1.45)
	# 6–8：珀耳塞福涅出现在树下，把一颗石榴放在石头上
	var pa: float = ez(seg(t, 6.0, 6.8))
	if pa > 0.0:
		c.save()
		c.alpha = pa
		if not c.spr(&"npc_persephone", tx - W * 0.05, H * PLAT + 2.0 * c.u, H * 0.16):
			c.spr(&"villager_woman", tx - W * 0.05, H * PLAT + 2.0 * c.u, H * 0.155)
		c.restore()
		var k2: float = ez(seg(t, 6.6, 7.6))
		if k2 > 0.0:
			var fx2: float = lerpf(tx - W * 0.03, bx, k2)
			var fy2: float = lerpf(H * PLAT - H * 0.1, by - r - 4.0, k2) - sin(k2 * PI) * H * 0.08
			c.fill_circle(fx2, fy2, H * 0.012, INK)
			c.stroke_circle(fx2, fy2, H * 0.012, CREAM, 1.0 * c.u)
	carve(c, p.def.text("text"), W / 2.0, H * 0.9, seg(t, 8.1, 9.6), carve_size(c, 46, 16, 24), W * 0.86)


# —————————— T 幸福的西西弗斯（20s） ——————————

## o：{sky, stars, dk, moon, sun?, chain_k, fire_k, use_beacon}；返回 {r, bx, by}
static func beacon_summit(c: EndCanvas, W: float, H: float, t: float, p: EndingPlayer, o: Dictionary) -> Dictionary:
	var r: float = r_b(W, H)
	var bx: float = W * BX
	var by: float = H * PLAT - r
	var px: float = W * 0.665
	var so: Dictionary = {"sky": o["sky"], "stars": o["stars"], "dk": o["dk"], "moon": o["moon"]}
	if o.has("sun"):
		so["sun"] = o["sun"]
	summit_scene(c, W, H, so)
	# 岩柱
	if not c.spr(&"column", px, H * PLAT + 4.0 * c.u, H * 0.2):
		c.fill_rect(px - W * 0.015, H * (PLAT - 0.2), W * 0.03, H * 0.2, INK)
	if EndCanvas.has_spr(&"end_beacon") and bool(o.get("use_beacon", false)):
		c.spr(&"end_beacon", bx + r * 0.6, H * PLAT + 3.0 * c.u, r * 3.4)
	else:
		boulder(c, bx, by, r)
		# 粘在石头上的碎物（本代碾碎的一切）
		var n: int = p.stuck.size()
		for i: int in n:
			var a: float = -PI * (0.08 + 0.84 * (i + 0.5) / maxf(1.0, n))
			var sx: float = bx + cos(a) * r * 0.92
			var sy: float = by + sin(a) * r * 0.92
			c.spr(StringName(p.stuck[i]), sx, sy + r * 0.08, r * 0.34, {"rot": a + PI / 2.0, "alpha": 0.95})
	# 锁链：岩柱 → 石头，绕一圈
	var ck: float = float(o.get("chain_k", 1.0))
	var pts: PackedVector2Array = [Vector2(px - W * 0.008, H * (PLAT - 0.11)), Vector2(bx + r * 0.9, by - r * 0.3)]
	for i: int in 15:
		var a2: float = -0.3 - i / 14.0 * PI * 1.25
		pts.append(Vector2(bx + cos(a2) * r * 1.02, by + sin(a2) * r * 1.02))
	chain_along(c, pts, ck, maxf(3.0 * c.u, r * 0.07))
	# 火：金色只在火焰里
	var fk: float = float(o.get("fire_k", 0.0))
	if fk > 0.0:
		flame(c, bx, by - r * 0.82, r * 1.7 * fk, t, 1.0)
		var n2: int = mini(9, p.stuck.size() if p.stuck.size() > 0 else 6)
		for i: int in n2:
			var a3: float = -PI * (0.12 + 0.76 * (i + 0.5) / n2)
			var kk: float = clampf(fk * 1.6 - i * 0.08, 0.0, 1.0)
			flame(c, bx + cos(a3) * r * 1.0, by + sin(a3) * r * 1.0 + 2.0 * c.u, r * 0.5 * kk, t, i + 3.0, kk)
	return {"r": r, "bx": bx, "by": by}


## 真结局的山顶部分（tt < 8：拴锁链、点火；tt ≥ 12：普罗米修斯坐下一起看日出）
static func true_inner(c: EndCanvas, W: float, H: float, tt: float, p: EndingPlayer) -> void:
	if tt < 8.0:
		var bs: Dictionary = beacon_summit(c, W, H, tt, p, {"sky": sky_mix(NIGHT, PREDAWN, ez(seg(tt, 4.0, 8.0)) * 0.25), "stars": 1.0, "dk": 0.0, "moon": 1.0, "chain_k": ez(seg(tt, 0.6, 3.4)), "fire_k": ez(seg(tt, 5.0, 7.6))})
		var r: float = bs["r"]
		var bx: float = bs["bx"]
		var by: float = bs["by"]
		# 西西弗斯：拴好锁链 → 掏出火种
		var sx: float = bx - r - r * 0.55
		var nm: StringName = StringName("push_%d" % (floori(tt * 5.0) % 6)) if tt < 3.6 else &"push_0"
		c.spr(nm, sx, H * PLAT + 1.0 * c.u, r * 1.9)
		if tt > 4.0 and tt < 5.2:
			var k: float = ez(seg(tt, 4.0, 5.1))
			flame(c, lerpf(sx + r * 0.6, bx, k), lerpf(H * PLAT - r * 1.4, by - r * 0.8, k), r * 0.25, tt, 9.0)
		return
	# 12–16：普罗米修斯坐到他身边，一起看日出（火和太阳同时在画面里）
	var dk: float = ez(seg(tt, 12.5, 15.5))
	var sxx: float = W * 0.8
	var R: float = H * 0.1
	var sun: Callable = func(hz: float) -> void:
		var k: float = ez(seg(tt, 12.0, 13.8))
		sun_disc(c, sxx, hz - ez(seg(tt, 13.0, 16.0)) * R * 0.5, R * (0.6 + 0.4 * k), k, seg(tt, 12.6, 14.0), ez(seg(tt, 13.0, 15.0)))
	var bs2: Dictionary = beacon_summit(c, W, H, tt, p, {"sky": sky_mix(NIGHT, DAWN, dk), "stars": 1.0 - dk, "dk": dk, "moon": 1.0 - dk, "chain_k": 1.0, "fire_k": 1.0, "use_beacon": true, "sun": sun})
	var r2: float = bs2["r"]
	var bx2: float = bs2["bx"]
	c.spr(&"sit", bx2 - r2 - r2 * 0.62, H * PLAT + 2.0 * c.u, r2 * 1.45)
	var pa: float = ez(seg(tt, 12.2, 13.2))
	c.save()
	c.alpha = pa
	var ppx: float = bx2 - r2 - r2 * 2.0
	if not c.spr(&"npc_prometheus_free", ppx, H * PLAT + 2.0 * c.u, r2 * 2.2):
		c.spr(&"sit", ppx, H * PLAT + 2.0 * c.u, r2 * 1.6)
	c.restore()


static func scene_true(c: EndCanvas, W: float, H: float, t: float, p: EndingPlayer) -> void:
	if t >= 8.0 and t < 12.0:
		true_gate(c, W, H, t, p)
		return
	if t < 16.0:
		true_inner(c, W, H, t, p)
		return
	var k: float = seg(t, 16.0, 17.8)
	if k <= 0.0:
		true_inner(c, W, H, 16.0, p)
		return
	var box: Dictionary = vase_pull(c, W, H, k, p, H * 0.52, 0.27)
	var fs: int = carve_size(c, 50, 15, 22)
	var top: float = maxf(60.0 * c.u, float(box["top"]) - fs * 3.4)
	var h: float = carve(c, p.def.text("text"), W / 2.0, top, seg(t, 17.6, 19.2), fs, W * 0.86)
	if str(p.flags.get("thanatos", "none")) == "spared":
		carve(c, p.def.text("spared"), W / 2.0, top + h + 4.0 * c.u, seg(t, 19.2, 19.8), roundi(fs * 0.8), W * 0.8, 500, MUTED)


## 山脚：冥府之门六重全开，哈迪斯 / 珀耳塞福涅 / 卡戎抬头看火；奥林匹斯的金光熄灭
static func true_gate(c: EndCanvas, W: float, H: float, t: float, p: EndingPlayer) -> void:
	sky(c, W, H, NIGHT[0], NIGHT[1])
	stars(c, W, H, 1.0, 11)
	# 奥林匹斯（左上远山）+ 金光：10–11.5s 熄灭
	c.fill_poly(PackedVector2Array([Vector2(0, H * 0.42), Vector2(W * 0.1, H * 0.2), Vector2(W * 0.18, H * 0.12), Vector2(W * 0.26, H * 0.22), Vector2(W * 0.36, H * 0.42)]), NIGHT[1].lerp(INK, 0.35))
	var og: float = 1.0 - ez(seg(t, 10.0, 11.5))
	if og > 0.0:
		c.glow(W * 0.18, H * 0.12, H * 0.16, Color(GOLD_GLOW, 0.3 * og))
	c.spr(&"temple", W * 0.18, H * 0.125, H * 0.05, {"alpha": 0.9, "night": true})
	# 大山：右上是山顶，山顶上一点火
	c.fill_poly(PackedVector2Array([Vector2(W * 0.3, H), Vector2(W * 0.55, H * 0.55), Vector2(W * 0.75, H * 0.22), Vector2(W * 0.82, H * 0.15), Vector2(W * 0.9, H * 0.2), Vector2(W * 1.05, H * 0.35), Vector2(W * 1.05, H)]), INK)
	c.stroke(PackedVector2Array([Vector2(W * 0.32, H * 0.98), Vector2(W * 0.56, H * 0.57), Vector2(W * 0.76, H * 0.24), Vector2(W * 0.82, H * 0.17)]), Color(CREAM, 0.4), 1.2 * c.u)
	flame(c, W * 0.82, H * 0.15, H * 0.035, t, 1.0)
	# 地面
	c.fill_rect(0, H * 0.84, W, H * 0.16, INK)
	# 冥府之门
	var gx: float = W * 0.2
	var gy: float = H * 0.84
	var gh: float = H * 0.36
	var open: float = ez(seg(t, 8.4, 10.0))
	c.glow(gx, gy - gh * 0.45, gh * 0.9, Color(CREAM_GLOW, 0.35 * open))
	if not c.spr(&"hades_gate", gx, gy + 2.0 * c.u, gh):
		c.fill_rect(gx - gh * 0.45, gy - gh, gh * 0.9, gh, INK)
	# 门缝里的光
	if open > 0.0:
		c.fill_rect(gx - gh * 0.03 * open, gy - gh * 0.62, gh * 0.06 * open, gh * 0.6, Color(CREAM_GLOW, 0.8 * open))
	# 门楣九枚封印，六枚亮起
	for i: int in 9:
		var x: float = gx + (i - 4) * gh * 0.075
		var y: float = gy - gh * 0.86
		var lit: float = ez(seg(t, 8.2 + i * 0.12, 8.5 + i * 0.12)) if i < 6 else 0.0
		c.fill_circle(x, y, gh * 0.026, INK)
		c.stroke_circle(x, y, gh * 0.026, CREAM, 1.0 * c.u)
		if lit > 0.0:
			c.fill_circle(x, y, gh * 0.016, Color(CREAM_GLOW, lit))
	# 三位冥府之人，面朝山顶
	var fig: Array[Array] = [[&"hades_scribe", gx + gh * 0.55, 0.2], [&"npc_persephone", gx + gh * 0.82, 0.17], [&"charon_pusher", gx - gh * 0.55, 0.18]]
	for f: Array in fig:
		var nm: StringName = f[0]
		var fx: float = f[1]
		var fh: float = f[2]
		if not c.spr(nm, fx, gy + 2.0 * c.u, H * fh):
			c.spr(&"villager_woman" if nm == &"npc_persephone" else &"shepherd", fx, gy + 2.0 * c.u, H * fh * 0.95)
	var ta: float = 0.5 * seg(t, 9.6, 10.6) * (1.0 - seg(t, 11.4, 12.0))
	if ta > 0.0:
		c.alpha = ta
		c.text(ltext(p, "zeus_silent", Loc.t("ending_scenes.olympus_zeus_said_nothing", "奥林匹斯上，宙斯没有说话。")), W * 0.5, H * 0.08, EndCanvas.italic(500), c.fsz(c.wc / 60.0, 13, 17), CREAM_HI)
		c.alpha = 1.0


# —————————— 冥府收债（8s，期限契约逾期） ——————————

static func scene_debt(c: EndCanvas, W: float, H: float, t: float, p: EndingPlayer) -> void:
	sky(c, W, H, Color("#0b0f1c"), Color("#1d2640"))
	stars(c, W, H, 0.8, 21)
	c.fill_rect(0, H * 0.8, W, H * 0.2, INK)
	var gx: float = W * 0.34
	var gy: float = H * 0.8
	var gh: float = H * 0.5
	var open: float = ez(seg(t, 3.4, 5.0))
	c.glow(gx, gy - gh * 0.4, gh * 0.8, Color(CREAM_GLOW, 0.18 * open))
	if not c.spr(&"hades_gate", gx, gy + 2.0 * c.u, gh):
		c.fill_rect(gx - gh * 0.45, gy - gh, gh * 0.9, gh, INK)
	c.spr(&"hades_scribe", W * 0.72, gy + 2.0 * c.u, H * 0.32, {"flip": true})
	# 账簿上的字
	var la: float = seg(t, 0.6, 1.4) * (1.0 - seg(t, 5.6, 6.2))
	if la > 0.0:
		c.alpha = la
		var s: String = Loc.t("ending.debt.ledger", "账目 · 西西弗斯 · 第 {d} 日 —— 逾期").replace("{d}", str(p.day))
		c.text(s, W * 0.5, H * 0.12, Fonts.serif(600), c.fsz(c.wc / 48.0, 14, 22), CREAM_HI)
		c.alpha = 1.0
	# 石头慢慢滚进门里
	var k: float = ez(seg(t, 3.0, 6.0))
	var r: float = H * 0.07
	if k < 1.0:
		var x: float = lerpf(W * 1.1, gx + gh * 0.05, k)
		c.save()
		c.alpha = 1.0 - seg(t, 5.4, 6.0)
		boulder(c, x, gy - r, r, -k * 9.0)
		c.restore()
	carve(c, p.def.text("text"), W / 2.0, H * 0.9, seg(t, 6.2, 7.6), carve_size(c, 46, 15, 22), W * 0.86)


# —————————— 假结局 ——————————

static func scene_ferry(c: EndCanvas, W: float, H: float, t: float, p: EndingPlayer) -> void:
	if t >= 6.0:
		credits(c, W, H, (t - 6.0) / 4.0 * 0.9, p.def.credits, 0.5)
		return
	sky(c, W, H, Color("#0b0f1c"), Color("#232c46"), H * 0.6)
	stars(c, W, H, 0.6, 31)
	var hz: float = H * 0.6
	c.fill_rect(0, hz, W, H - hz, Color("#0a0d18"))
	# 冥河：缓慢流动的米色波纹
	for i: int in 7:
		var y: float = hz + (10.0 + i * i * 4.5) * c.u
		c.dashed_h(0, W, y, (30 + i * 9) * c.u, (22 + i * 6) * c.u, -t * (12 + i * 6) * c.u, Color(CREAM, 0.08 + i * 0.03), 1.0 * c.u)
	# 对岸
	var shore: PackedVector2Array = [Vector2(W * 0.7, hz)]
	EndCanvas.quad_to(shore, shore[0], Vector2(W * 0.85, hz - H * 0.06), Vector2(W, hz - H * 0.08), 16)
	shore.append(Vector2(W, hz))
	c.fill_poly(shore, Color("#05070f"))
	# 船
	var bx: float = lerpf(W * 0.12, W * 0.62, ez(seg(t, 0.0, 6.0)))
	var by: float = hz + H * 0.07 + sin(t * 2.0) * 2.0 * c.u
	if not c.spr(&"npc_charon_boat", bx, by + 6.0 * c.u, H * 0.24):
		var hull: PackedVector2Array = [Vector2(bx - W * 0.13, by - H * 0.02)]
		EndCanvas.quad_to(hull, hull[0], Vector2(bx, by + H * 0.05), Vector2(bx + W * 0.13, by - H * 0.03), 16)
		hull.append(Vector2(bx + W * 0.11, by))
		hull.append(Vector2(bx - W * 0.11, by))
		c.fill_poly(hull, INK)
		c.stroke(hull, Color(CREAM, 0.5), 1.0 * c.u, true)
		c.spr(&"charon_pusher", bx + W * 0.06, by - H * 0.01, H * 0.2)
		c.spr(&"sit", bx - W * 0.05, by - H * 0.008, H * 0.1)
	carve(c, p.def.text("text"), W / 2.0, H * 0.88, seg(t, 2.2, 3.8), carve_size(c, 46, 15, 22), W * 0.86)


static func reveal_ferry(c: EndCanvas, W: float, H: float, rt: float, p: EndingPlayer) -> void:
	credits(c, W, H, 0.45, p.def.credits, 0.45)
	c.fill_rect(0, 0, W, H, Color(6.0 / 255.0, 4.0 / 255.0, 4.0 / 255.0, 0.9))
	# 卡戎回头
	if not c.spr(&"npc_charon_boat", W * 0.5, H * 0.72, H * 0.42, {"flip": true}):
		c.spr(&"charon_pusher", W * 0.5, H * 0.72, H * 0.4, {"flip": true})
	carve(c, p.def.text("reveal_text"), W / 2.0, H * 0.84, seg(rt, 1.2, 2.4), carve_size(c, 40, 18, 28), W * 0.86)


## "完"字黑屏（immortal / sleep 共用）
static func _the_end(c: EndCanvas, W: float, H: float, a: float, big: float) -> void:
	c.fill_rect(0, 0, W, H, Color.BLACK)
	c.alpha = a
	c.text(Loc.t("ending.ui.fin", "完"), W / 2.0, H * 0.46, Fonts.serif(700), roundi(H * big), Color("#f5efe4"))
	c.alpha = 1.0


static func scene_immortal(c: EndCanvas, W: float, H: float, t: float, p: EndingPlayer) -> void:
	if t >= 5.5:
		var a: float = seg(t, 5.7, 6.6)
		_the_end(c, W, H, a, 0.16)
		c.alpha = a * 0.6
		c.text("ΤΕΛΟΣ · THE END", W / 2.0, H * 0.6, Fonts.cinzel(600), c.fsz(c.wc / 70.0, 11, 15), Color("#f5efe4"))
		c.alpha = seg(t, 6.6, 7.2) * 0.55
		c.text(p.def.text("aside"), W / 2.0, H * 0.68, EndCanvas.italic(500), c.fsz(c.wc / 80.0, 11, 14), Color("#f5efe4"))
		c.alpha = 1.0
		return
	sky(c, W, H, DAY[0], DAY[1])
	c.fill_rect(0, H * 0.78, W, H * 0.22, INK)
	# 西西弗斯用锁链锁住死神
	var tx: float = W * 0.58
	var gy: float = H * 0.78
	if not c.spr(&"npc_thanatos", tx, gy + 2.0 * c.u, H * 0.36, {"flip": true}):
		# 占位：黑翼 + 亡魂
		for d: float in [-1.0, 1.0]:
			var wing: PackedVector2Array = [Vector2(tx, gy - H * 0.22)]
			EndCanvas.quad_to(wing, wing[0], Vector2(tx + d * H * 0.2, gy - H * 0.38), Vector2(tx + d * H * 0.24, gy - H * 0.2))
			EndCanvas.quad_to(wing, Vector2(tx + d * H * 0.24, gy - H * 0.2), Vector2(tx + d * H * 0.12, gy - H * 0.18), Vector2(tx, gy - H * 0.12))
			c.fill_poly(wing, INK)
			c.stroke(wing, CREAM, 1.0 * c.u, true)
		c.spr(&"ghost_pusher", tx, gy + 2.0 * c.u, H * 0.3, {"flip": true})
	c.spr(StringName("push_%d" % (floori(t * 5.0) % 6)), W * 0.38, gy + 2.0 * c.u, H * 0.24)
	var ck: float = ez(seg(t, 0.6, 2.6))
	var pts: PackedVector2Array = []
	for i: int in 31:
		var a2: float = i / 30.0 * TAU * 2.2
		pts.append(Vector2(tx + cos(a2) * H * 0.09, gy - H * 0.06 - i * H * 0.006 + sin(a2) * H * 0.02))
	chain_along(c, pts, ck, maxf(3.0 * c.u, H * 0.008))
	carve(c, ltext(p, "scene_title", Loc.t("ending_scenes.he_had_tricked_death", "他第三次骗过了死神。")), W / 2.0, H * 0.12, seg(t, 1.0, 2.4), carve_size(c, 44, 16, 24), W * 0.86, 600, INK)
	carve(c, p.def.text("text"), W / 2.0, H * 0.9, seg(t, 3.0, 4.4), carve_size(c, 46, 15, 22), W * 0.86)


static func reveal_immortal(c: EndCanvas, W: float, H: float, rt: float, p: EndingPlayer) -> void:
	c.fill_rect(0, 0, W, H, Color.BLACK)
	carve(c, p.def.text("reveal_text"), W / 2.0, H * 0.48, seg(rt, 0.9, 2.2), carve_size(c, 40, 18, 28), W * 0.86)


static func scene_throne(c: EndCanvas, W: float, H: float, t: float, p: EndingPlayer) -> void:
	if t >= 5.0:
		credits(c, W, H, (t - 5.0) / 3.0 * 0.75, p.def.credits, 1.0)
		return
	# 奥林匹斯大殿：柱廊、宝座、众神圆章鼓掌
	sky(c, W, H, Color("#cbbaa6"), Color("#e0d3bc"))
	for i: int in 6:
		c.spr(&"column", W * (0.1 + i * 0.16), H * 0.84, H * 0.62, {"alpha": 0.85})
	c.fill_rect(0, H * 0.84, W, H * 0.16, INK)
	c.fill_rect(0, 0, W, H * 0.12, INK)
	meander_band(c, 0, H * 0.085, W, H * 0.03, 1.0)
	# 宝座（墨色，米色刻线）
	var tx: float = W * 0.5
	var ty: float = H * 0.84
	var th: PackedVector2Array = [Vector2(tx - H * 0.12, ty), Vector2(tx - H * 0.12, ty - H * 0.42)]
	EndCanvas.quad_to(th, th[1], Vector2(tx, ty - H * 0.5), Vector2(tx + H * 0.12, ty - H * 0.42), 16)
	th.append(Vector2(tx + H * 0.12, ty))
	c.fill_poly(th, INK)
	c.stroke(th, CREAM, 1.2 * c.u, true)
	c.stroke_rect(tx - H * 0.09, ty - H * 0.38, H * 0.18, H * 0.2, CREAM, 1.2 * c.u)
	palmette(c, tx, ty - H * 0.3, H * 0.06, CREAM, 1.2 * c.u)
	c.spr(&"sit", tx, ty - H * 0.08, H * 0.2)
	# 宙斯递来一块小石头当权杖
	c.spr(&"zeus_statue", W * 0.82, ty + 2.0 * c.u, H * 0.42, {"flip": true})
	var k: float = ez(seg(t, 1.6, 3.0))
	boulder(c, lerpf(W * 0.74, tx + H * 0.04, k), lerpf(ty - H * 0.3, ty - H * 0.2, k) - sin(k * PI) * H * 0.08, H * 0.022)
	# 众神鼓掌：一排圆章上下跳
	var gi: int = 0
	for nm: String in GODS:
		if not EndCanvas.has_spr(StringName(nm)):
			continue
		var x: float = W * (0.12 + gi * 0.1)
		var y: float = H * 0.22 + absf(sin(t * 9.0 + gi)) * -H * 0.02
		c.spr(StringName(nm), x, y + H * 0.06, H * 0.08)
		gi += 1
	carve(c, p.def.text("text"), W / 2.0, H * 0.93, seg(t, 2.6, 4.0), carve_size(c, 46, 15, 22), W * 0.86)


static func reveal_throne(c: EndCanvas, W: float, H: float, rt: float, p: EndingPlayer) -> void:
	# 镜头拉远：宝座在另一座更高的山脚下
	sky(c, W, H, Color("#c6b6a0"), Color("#e0d3bc"))
	var z: float = 1.0 - ez(seg(rt, 0.4, 1.6)) * 0.85
	c.fill_poly(PackedVector2Array([Vector2(-W * 0.1, H), Vector2(W * 0.3, H * 0.6), Vector2(W * 0.55, -H * 0.2), Vector2(W * 0.62, -H * 0.3), Vector2(W * 0.75, H * 0.1), Vector2(W * 1.1, H * 0.8), Vector2(W * 1.1, H)]), INK)
	c.stroke(PackedVector2Array([Vector2(W * 0.02, H * 0.92), Vector2(W * 0.31, H * 0.62), Vector2(W * 0.56, -H * 0.18)]), Color(CREAM, 0.45), 1.2 * c.u)
	# 山脚的小宝座
	var tx: float = W * 0.2
	var ty: float = H * 0.9
	var s: float = H * 0.5 * z + H * 0.04
	var th: PackedVector2Array = EndCanvas.rect_pts(tx - s * 0.24, ty - s * 0.84, s * 0.48, s * 0.84)
	c.fill_poly(th, INK)
	c.stroke(th, CREAM, 1.0 * c.u, true)
	c.spr(&"sit", tx, ty - s * 0.16, s * 0.4)
	var za: float = seg(rt, 1.2, 1.8)
	if not c.spr(&"por_zeus", W * 0.8, H * 0.95, H * 0.5, {"alpha": za}):
		c.spr(&"god_zeus", W * 0.78, H * 0.62, H * 0.22, {"alpha": za})
	c.fill_rect(0, H * 0.8, W, H * 0.12, Color(INK, 0.6))
	carve(c, p.def.text("reveal_text"), W / 2.0, H * 0.86, seg(rt, 1.5, 2.6), carve_size(c, 38, 18, 30), W * 0.86)


static func scene_sleep(c: EndCanvas, W: float, H: float, t: float, p: EndingPlayer) -> void:
	if t >= 2.5:
		var a: float = seg(t, 2.7, 3.4)
		_the_end(c, W, H, a, 0.14)
		c.alpha = a * 0.75
		c.text(p.def.text("text"), W / 2.0, H * 0.62, Fonts.serif(500), c.fsz(c.wc / 50.0, 13, 19), Color("#f5efe4"))
		c.alpha = seg(t, 3.6, 4.2) * 0.5
		c.text(p.def.text("aside"), W / 2.0, H * 0.7, EndCanvas.italic(500), c.fsz(c.wc / 80.0, 11, 14), Color("#f5efe4"))
		c.alpha = 1.0
		return
	sleep_scene(c, W, H, t, 0.0)
	c.fill_rect(0, 0, W, H, Color(0, 0, 0, 0.7 * seg(t, 0.6, 2.5)))
	carve(c, p.def.text("text"), W / 2.0, H * 0.86, seg(t, 0.4, 1.6), carve_size(c, 44, 16, 24), W * 0.86)


static func sleep_scene(c: EndCanvas, W: float, H: float, t: float, wake: float) -> void:
	sky(c, W, H, DAY[0], DAY[1])
	c.fill_poly(PackedVector2Array([Vector2(0, H), Vector2(0, H * 0.86), Vector2(W, H * 0.6), Vector2(W, H)]), INK)
	var r: float = H * 0.12
	var bx: float = W * 0.58
	var by: float = lerpf(H * 0.86, H * 0.6, 0.58) - r * 0.9
	boulder(c, bx, by, r, wake * sin(t * 40.0) * 0.03)
	var sx: float = bx - r * 1.1
	var sy: float = lerpf(H * 0.86, H * 0.6, (bx - r * 1.1) / W)
	c.spr(&"push_0" if wake > 0.5 else &"tired", sx, sy + 3.0 * c.u, H * 0.22, {"rot": -0.25 if wake > 0.5 else -0.12})


static func reveal_sleep(c: EndCanvas, W: float, H: float, rt: float, p: EndingPlayer) -> void:
	var sneeze: bool = rt > 1.1
	sleep_scene(c, W, H, rt, 1.0 if sneeze else 0.0)
	# 苍蝇：绕两圈，落在鼻子上
	var r: float = H * 0.12
	var bx: float = W * 0.58
	var nose: Vector2 = Vector2(bx - r * 1.1 + H * 0.05, lerpf(H * 0.86, H * 0.6, 0.48) - H * 0.17)
	var k: float = seg(rt, 0.4, 1.05)
	var fx: float = nose.x + cos(k * 14.0) * (1.0 - k) * H * 0.12
	var fy: float = nose.y + sin(k * 11.0) * (1.0 - k) * H * 0.08
	if not sneeze:
		var uu: float = c.u
		c.fill_circle(fx, fy, 2.5 * uu, INK)
		var wf: float = sin(rt * 90.0) * 3.0
		c.stroke(EndCanvas.ellipse_pts(fx - 2.0 * uu, fy - 2.0 * uu, 3.0 * uu, (1.5 + wf * 0.2) * uu, -0.6, 0.0, TAU, 12), INK, 1.0 * uu)
		c.stroke(EndCanvas.ellipse_pts(fx + 2.0 * uu, fy - 2.0 * uu, 3.0 * uu, (1.5 - wf * 0.2) * uu, 0.6, 0.0, TAU, 12), INK, 1.0 * uu)
	else:
		var s: float = 1.0 + maxf(0.0, 0.3 - (rt - 1.1)) * 2.0
		var fs: int = roundi(H * 0.09 * s)
		var achoo: String = ltext(p, "achoo", Loc.t("ending_scenes.achoo", "阿嚏！"))
		var font: Font = Fonts.serif(900)
		c.text_outline(achoo, nose.x + W * 0.06, nose.y - H * 0.12, font, fs, roundi(6.0 * c.u), INK)
		c.text(achoo, nose.x + W * 0.06, nose.y - H * 0.12, font, fs, CREAM_HI)
	c.fill_rect(0, H * 0.06, W, H * 0.1, Color(INK, 0.55))
	carve(c, ltext(p, "fly", Loc.t("ending_scenes.fly_landed_his_nose", "……一只苍蝇落在他鼻子上。")), W / 2.0, H * 0.11, seg(rt, 0.5, 1.0), carve_size(c, 46, 15, 22), W * 0.86)
