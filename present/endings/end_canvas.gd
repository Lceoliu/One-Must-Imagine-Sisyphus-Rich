class_name EndCanvas
extends RefCounted
## 结局演出用的"画布上下文"：把网页 canvas 2D 的 save / restore / translate / rotate / scale / globalAlpha
## 搬到 CanvasItem.draw_* 上（变换用 draw_set_transform_matrix，透明度乘进颜色）。
## 路径类绘制（arc / ellipse / quadraticCurveTo / bezierCurveTo）一律先采样成点，再 draw_colored_polygon / draw_polyline。
## 像素常量按网页 CSS 像素给，乘 u（= H / 900，网页以 1600×900 窗口调的）换成本视口单位。
## 不支持的：globalCompositeOperation（'lighter' 用普通 alpha 混合近似；'destination-out' 用 Geometry2D 做布尔）、
## 任意 clip（需要时调用方用 Geometry2D 求交）。

var ci: CanvasItem
var W: float
var H: float
## 网页 CSS 像素 → 本视口单位
var u: float
## 以 CSS 像素计的画布宽（网页公式 clamp(W / 46, 16, 24) 里的 W）
var wc: float
var xf: Transform2D = Transform2D.IDENTITY
## 等同 ctx.globalAlpha（绝对值；save/restore 一起保存）
var alpha: float = 1.0
var _stack: Array[Dictionary] = []

static var _wrap_cache: Dictionary = {}
static var _italic: Dictionary = {}
static var _spaced: Dictionary = {}


## 网页的 rnd(seed)：LCG，与 endings.js 同序列
class Rnd:
	extends RefCounted
	var s: int

	func _init(seed_v: int) -> void:
		s = seed_v & 0xFFFFFFFF
		if s == 0:
			s = 1

	func next() -> float:
		s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
		return float(s) / 4294967296.0


func _init(p_ci: CanvasItem, p_w: float, p_h: float) -> void:
	ci = p_ci
	W = p_w
	H = p_h
	u = p_h / 900.0
	wc = p_w / u
	ci.draw_set_transform_matrix(xf)


# —————————— 状态栈 ——————————

func save() -> void:
	_stack.append({"xf": xf, "a": alpha})


func restore() -> void:
	if _stack.is_empty():
		return
	var s: Dictionary = _stack.pop_back()
	xf = s["xf"]
	alpha = s["a"]
	ci.draw_set_transform_matrix(xf)


func reset() -> void:
	_stack.clear()
	xf = Transform2D.IDENTITY
	alpha = 1.0
	ci.draw_set_transform_matrix(xf)


func translate(x: float, y: float) -> void:
	xf = xf * Transform2D(0.0, Vector2(x, y))
	ci.draw_set_transform_matrix(xf)


func rotate(a: float) -> void:
	xf = xf * Transform2D(a, Vector2.ZERO)
	ci.draw_set_transform_matrix(xf)


func scale(sx: float, sy: float) -> void:
	xf = xf * Transform2D(Vector2(sx, 0.0), Vector2(0.0, sy), Vector2.ZERO)
	ci.draw_set_transform_matrix(xf)


## 颜色乘上当前 globalAlpha（再乘额外的 a）
func cc(c: Color, a: float = 1.0) -> Color:
	return Color(c.r, c.g, c.b, c.a * a * alpha)


## 网页字号公式 Math.round(clamp(v, lo, hi))（v、lo、hi 都是 CSS 像素）→ 本视口字号
func fsz(v: float, lo: float, hi: float) -> int:
	return maxi(1, roundi(clampf(v, lo, hi) * u))


# —————————— 基本图元 ——————————

func fill_rect(x: float, y: float, w: float, h: float, col: Color) -> void:
	ci.draw_rect(Rect2(x, y, w, h), cc(col))


func stroke_rect(x: float, y: float, w: float, h: float, col: Color, width: float) -> void:
	ci.draw_rect(Rect2(x, y, w, h), cc(col), false, width)


func fill_circle(x: float, y: float, r: float, col: Color) -> void:
	if r <= 0.0:
		return
	fill_poly(circle_pts(x, y, r), col)


func stroke_circle(x: float, y: float, r: float, col: Color, width: float) -> void:
	if r <= 0.0:
		return
	var pts: PackedVector2Array = circle_pts(x, y, r)
	pts.append(pts[0])
	stroke(pts, col, width)


## 填充多边形（三角化失败时静默跳过，不刷错误）
func fill_poly(pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3:
		return
	if Geometry2D.triangulate_polygon(pts).is_empty():
		return
	ci.draw_colored_polygon(pts, cc(col))


## 折线描边（closed = 首尾相连）
func stroke(pts: PackedVector2Array, col: Color, width: float, closed: bool = false) -> void:
	if pts.size() < 2:
		return
	var p: PackedVector2Array = pts
	if closed:
		p = pts.duplicate()
		p.append(pts[0])
	ci.draw_polyline(p, cc(col), maxf(width, 0.5), true)


func line(x0: float, y0: float, x1: float, y1: float, col: Color, width: float) -> void:
	ci.draw_line(Vector2(x0, y0), Vector2(x1, y1), cc(col), maxf(width, 0.5), true)


## 水平虚线（= setLineDash([dash, gap]) + lineDashOffset）
func dashed_h(x0: float, x1: float, y: float, dash: float, gap: float, offset: float, col: Color, width: float) -> void:
	var period: float = dash + gap
	if period <= 0.0:
		return
	var segs: PackedVector2Array = []
	var ph: float = fposmod(offset, period)
	var s: float = -ph
	while s < x1 - x0:
		var a: float = maxf(s, 0.0)
		var b: float = minf(s + dash, x1 - x0)
		if b > a:
			segs.append(Vector2(x0 + a, y))
			segs.append(Vector2(x0 + b, y))
		s += period
	if segs.size() >= 2:
		ci.draw_multiline(segs, cc(col), maxf(width, 0.5))


## 竖直线性渐变矩形（= createLinearGradient(0, y, 0, y + h)）
func vgrad(x: float, y: float, w: float, h: float, top: Color, bot: Color) -> void:
	var pts: PackedVector2Array = [Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]
	var cols: PackedColorArray = [cc(top), cc(top), cc(bot), cc(bot)]
	ci.draw_polygon(pts, cols)


## 柔光（代替 createRadialGradient(中心色 → 透明)）
func glow(x: float, y: float, r: float, col: Color) -> void:
	if r <= 0.0 or col.a * alpha <= 0.002:
		return
	Glow.draw(ci, Vector2(x, y), r, cc(col))


# —————————— 采样路径 ——————————

static func circle_pts(x: float, y: float, r: float) -> PackedVector2Array:
	return arc_pts(x, y, r, 0.0, TAU, _segs(r))


static func _segs(r: float) -> int:
	return clampi(int(r * 0.6) + 12, 12, 96)


## 圆弧采样（a0 → a1，含两端）
static func arc_pts(x: float, y: float, r: float, a0: float, a1: float, n: int = -1) -> PackedVector2Array:
	var m: int = n if n > 0 else maxi(4, int(_segs(r) * absf(a1 - a0) / TAU) + 2)
	var out: PackedVector2Array = []
	out.resize(m + 1)
	for i: int in m + 1:
		var a: float = lerpf(a0, a1, float(i) / float(m))
		out[i] = Vector2(x + cos(a) * r, y + sin(a) * r)
	return out


## 椭圆采样（= ctx.ellipse(x, y, rx, ry, rot, a0, a1)）
static func ellipse_pts(x: float, y: float, rx: float, ry: float, rot: float, a0: float = 0.0, a1: float = TAU, n: int = 28) -> PackedVector2Array:
	var out: PackedVector2Array = []
	out.resize(n + 1)
	var cr: float = cos(rot)
	var sr: float = sin(rot)
	for i: int in n + 1:
		var a: float = lerpf(a0, a1, float(i) / float(n))
		var px: float = cos(a) * rx
		var py: float = sin(a) * ry
		out[i] = Vector2(x + px * cr - py * sr, y + px * sr + py * cr)
	return out


## 二次贝塞尔（不含起点，便于接在已有点后面）
static func quad_to(out: PackedVector2Array, p0: Vector2, c: Vector2, p1: Vector2, n: int = 12) -> void:
	for i: int in range(1, n + 1):
		var k: float = float(i) / float(n)
		var a: Vector2 = p0.lerp(c, k)
		var b: Vector2 = c.lerp(p1, k)
		out.append(a.lerp(b, k))


## 三次贝塞尔（不含起点）
static func cubic_to(out: PackedVector2Array, p0: Vector2, c1: Vector2, c2: Vector2, p1: Vector2, n: int = 16) -> void:
	for i: int in range(1, n + 1):
		var k: float = float(i) / float(n)
		out.append(p0.bezier_interpolate(c1, c2, p1, k))


## 圆角矩形（= roundRectPath 的 arcTo 版本）
static func round_rect_pts(x: float, y: float, w: float, h: float, r: float) -> PackedVector2Array:
	var rr: float = minf(r, minf(w, h) / 2.0)
	var out: PackedVector2Array = []
	out.append_array(arc_pts(x + w - rr, y + rr, rr, -PI / 2.0, 0.0, 8))
	out.append_array(arc_pts(x + w - rr, y + h - rr, rr, 0.0, PI / 2.0, 8))
	out.append_array(arc_pts(x + rr, y + h - rr, rr, PI / 2.0, PI, 8))
	out.append_array(arc_pts(x + rr, y + rr, rr, PI, PI * 1.5, 8))
	return out


static func rect_pts(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])


# —————————— 精灵 ——————————

## 精灵存在且纹理已加载（= 网页 sp(name)）
static func has_spr(key: StringName) -> bool:
	return SpriteDB.has(key) and SpriteDB.tex(key) != null


## = 网页 spr(ctx, name, x, yb, h, o)：底边中点 (x, yb)、高 h；o = {rot, flip, alpha, ax, ay, night}
func spr(key: StringName, x: float, yb: float, h: float, o: Dictionary = {}) -> bool:
	if not SpriteDB.has(key):
		return false
	var tex: Texture2D = SpriteDB.tex(key)
	if tex == null:
		return false
	var w: float = h * SpriteDB.aspect(key)
	var rot: float = float(o.get("rot", 0.0))
	var flip: bool = bool(o.get("flip", false))
	var ax: float = float(o.get("ax", 0.5))
	var ay: float = float(o.get("ay", 1.0))
	var tint: Color = Palette.NIGHT_TINT if bool(o.get("night", false)) else Color.WHITE
	save()
	translate(x, yb)
	if rot != 0.0:
		rotate(rot)
	if flip:
		scale(-1.0, 1.0)
	alpha *= float(o.get("alpha", 1.0))
	ci.draw_texture_rect(tex, Rect2(-w * ax, -h * ay, w, h), false, cc(tint))
	restore()
	return true


# —————————— 文字 ——————————

## 斜体（FontVariation 斜切；网页用 italic）
static func italic(weight: int) -> Font:
	if _italic.has(weight):
		return _italic[weight]
	var fv: FontVariation = (Fonts.serif(weight) as FontVariation).duplicate() as FontVariation
	fv.variation_transform = Transform2D(Vector2(1.0, 0.2), Vector2(0.0, 1.0), Vector2.ZERO)
	_italic[weight] = fv
	return fv


## 加字距（= CSS letter-spacing）
static func spaced(base: Font, px: int) -> Font:
	var key: String = "%d|%d" % [base.get_instance_id(), px]
	if _spaced.has(key):
		return _spaced[key]
	# 直接复制带字重的 FontVariation 再加字距（套一层新的 FontVariation 会丢掉内层的字重）
	var fv: FontVariation
	if base is FontVariation:
		fv = (base as FontVariation).duplicate() as FontVariation
	else:
		fv = FontVariation.new()
		fv.base_font = base
	fv.spacing_glyph = px
	_spaced[key] = fv
	return fv


static func text_w(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## 画一行字：align -1 左 / 0 中 / 1 右；y 是 textBaseline = 'middle' 的中线
func text(s: String, x: float, y: float, font: Font, size: int, col: Color, align: int = 0) -> void:
	if s == "":
		return
	var w: float = text_w(font, s, size)
	var x0: float = x - (w / 2.0 if align == 0 else (w if align > 0 else 0.0))
	var by: float = y + (font.get_ascent(size) - font.get_descent(size)) / 2.0
	ci.draw_string(font, Vector2(x0, by), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, cc(col))


## 描边字（= strokeText，lineWidth = outline 像素）
func text_outline(s: String, x: float, y: float, font: Font, size: int, outline: int, col: Color) -> void:
	var w: float = text_w(font, s, size)
	var by: float = y + (font.get_ascent(size) - font.get_descent(size)) / 2.0
	ci.draw_string_outline(font, Vector2(x - w / 2.0, by), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, cc(col))


## 按宽度逐字折行（= endings.js wrap），结果缓存
static func wrap(font: Font, s: String, size: int, max_w: float) -> PackedStringArray:
	var key: String = "%d|%d|%d|%s" % [font.get_instance_id(), size, roundi(max_w), s]
	if _wrap_cache.has(key):
		return _wrap_cache[key]
	var out: PackedStringArray = []
	var cur: String = ""
	for ch: String in s:
		if cur != "" and text_w(font, cur + ch, size) > max_w:
			out.append(cur)
			cur = ""
		cur += ch
	if cur != "":
		out.append(cur)
	_wrap_cache[key] = out
	return out
