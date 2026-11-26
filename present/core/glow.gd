class_name Glow
extends RefCounted
## 径向光晕纹理（白心 → 透明边，平滑衰减；存成 glow.tres，场景里的灯光和光晕都引用它）：用 draw_texture_rect(tex, rect, false, 颜色) 画柔光，代替网页的 createRadialGradient。

static var _tex: GradientTexture2D = null


const RES: String = "res://present/core/glow.tres"


static func tex() -> GradientTexture2D:
	if _tex != null:
		return _tex
	if ResourceLoader.exists(RES):
		_tex = load(RES) as GradientTexture2D
		if _tex != null:
			return _tex
	var grad: Gradient = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.15), Color(1, 1, 1, 0)])
	var t: GradientTexture2D = GradientTexture2D.new()
	t.gradient = grad
	t.width = 128
	t.height = 128
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_tex = t
	return t


## 在 c 上以 center 为圆心、radius 为半径画一团柔光
static func draw(c: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	c.draw_texture_rect(tex(), Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)
