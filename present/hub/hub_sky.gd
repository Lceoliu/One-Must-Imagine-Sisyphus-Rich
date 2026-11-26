@tool
class_name HubSky
extends Node2D
## 夜宴的天空（放在 hub.tscn 的 SkyLayer 这个 CanvasLayer 里，不受 CanvasModulate 和灯光影响）：竖向渐变 + 星星 + 月牙。
## 颜色、渐变分段、月亮样式都和白天入夜时一样（background_view.gd 的 SKY_NIGHT：顶 161f36 → 底 36456a，0.55 屏高处是 62% 的过渡色；
## 月亮 = 月面圆减去右上偏移 0.45r / 0.15r、半径 0.9r 的圆），让玩家认出这还是白天那座山脚下的夜。
## 越往右（镜头接近赫利俄斯）越接近黎明：渐变换成暖色，星星淡出。dawn 与 scroll 由 HubView 每帧写入。
## 编辑器里按 preview_width 横向铺开整条天空，从左（深夜）到右（黎明）过渡，方便对照场景调色。

@export var top: Color = Color("161f36"):
	set(v):
		top = v
		queue_redraw()
@export var horizon: Color = Color("36456a"):
	set(v):
		horizon = v
		queue_redraw()
@export var dawn_top: Color = Color("3c3256"):
	set(v):
		dawn_top = v
		queue_redraw()
@export var dawn_horizon: Color = Color("e0a05c"):
	set(v):
		dawn_horizon = v
		queue_redraw()
## 镜头中心走到场景宽度的这个比例处开始泛白
@export var dawn_from: float = 0.62
## 渐变中段的位置（占屏高的比例，= 白天 0.55）与中段颜色在顶→底之间的比例（= 白天 0.62）
@export var mid_at: float = 0.55
@export var mid_mix: float = 0.62
## 月亮：屏幕上的位置（占屏宽 / 屏高的比例）、半径（占屏高的比例，= 白天 min(W, H) × 0.05）
@export var moon_pos: Vector2 = Vector2(0.8, 0.15)
@export var moon_radius: float = 0.05
## 星星个数（白天夜里 90 颗，铺在上方 60%）
@export var star_count: int = 110
## 编辑器预览高度（参考 1080 高）
@export var ground: float = 1080.0
## 编辑器预览宽度（= 场景宽度）
@export var preview_width: float = 11800.0:
	set(v):
		preview_width = v
		queue_redraw()

## 0 = 深夜，1 = 黎明
var dawn: float = 0.0
## 镜头中心 x（星星有一点点视差）
var scroll: float = 0.0
var _stars: Array[Vector4] = []   # 归一化 x, y, 半径, 闪烁相位
var _t: float = 0.0


func _ready() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in star_count:
		var y: float = pow(rng.randf(), 1.2) * 0.6
		_stars.append(Vector4(rng.randf(), y, rng.randf_range(0.6, 1.7), rng.randf() * TAU))


func _process(dt: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += dt
	queue_redraw()


## 竖向位置 v（0 顶 → 1 地平线）、黎明程度 d 处的天色
func sky_at(v: float, d: float = -1.0) -> Color:
	var k: float = clampf(dawn if d < 0.0 else d, 0.0, 1.0)
	var t: Color = top.lerp(dawn_top, k)
	var h: Color = horizon.lerp(dawn_horizon, k * k)
	return t.lerp(h, clampf(v, 0.0, 1.0))


func _draw() -> void:
	if Engine.is_editor_hint():
		_draw_preview()
		return
	var vp: Vector2 = get_viewport_rect().size
	var c_top: Color = sky_at(0.0)
	var c_mid: Color = sky_at(mid_mix)
	var c_hor: Color = sky_at(1.0)
	var my: float = vp.y * mid_at
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(vp.x, 0), Vector2(vp.x, my), Vector2(0, my)]),
		PackedColorArray([c_top, c_top, c_mid, c_mid]))
	draw_polygon(PackedVector2Array([Vector2(0, my), Vector2(vp.x, my), Vector2(vp.x, vp.y), Vector2(0, vp.y)]),
		PackedColorArray([c_mid, c_mid, c_hor, c_hor]))
	# 星星：黎明时淡出；横向随镜头慢慢移一点（亮度 0.3–0.65 闪烁，= 白天）
	var sa: float = 1.0 - smoothstep(0.2, 0.9, dawn)
	if sa > 0.01:
		var span: float = vp.x * 1.4
		for s: Vector4 in _stars:
			var x: float = fposmod(s.x * span - scroll * 0.015, span) - vp.x * 0.2
			var tw: float = 0.3 + 0.35 * (0.5 + 0.5 * sin(_t * 1.3 + s.w))
			draw_circle(Vector2(x, s.y * vp.y), s.z, Color(0.86, 0.91, 1.0, tw * sa))
	_draw_moon(Vector2(vp.x * moon_pos.x, vp.y * moon_pos.y), vp.y * moon_radius, 1.0 - 0.7 * smoothstep(0.3, 1.0, dawn))


## 编辑器预览：整条场景宽的天空，左边深夜、从 dawn_from 起往右过渡到黎明
func _draw_preview() -> void:
	var n: int = 48
	for i: int in n:
		var x0: float = preview_width * float(i) / n - 2000.0
		var x1: float = preview_width * float(i + 1) / n - 2000.0
		var d0: float = clampf((float(i) / n - dawn_from) / maxf(0.01, 1.0 - dawn_from), 0.0, 1.0)
		var d1: float = clampf((float(i + 1) / n - dawn_from) / maxf(0.01, 1.0 - dawn_from), 0.0, 1.0)
		var my: float = ground * mid_at
		draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, my), Vector2(x0, my)]),
			PackedColorArray([sky_at(0.0, d0), sky_at(0.0, d1), sky_at(mid_mix, d1), sky_at(mid_mix, d0)]))
		draw_polygon(PackedVector2Array([Vector2(x0, my), Vector2(x1, my), Vector2(x1, ground), Vector2(x0, ground)]),
			PackedColorArray([sky_at(mid_mix, d0), sky_at(mid_mix, d1), sky_at(1.0, d1), sky_at(1.0, d0)]))
	_draw_moon(Vector2(1920.0 * moon_pos.x, ground * moon_pos.y), ground * moon_radius, 1.0)


func _draw_moon(mp: Vector2, mr: float, ma: float) -> void:
	# 月牙（= 白天：月面圆减去右上偏移的圆）；Geometry2D 裁剪，不用天色盖（盖的圆会在光晕上留下一块深色）。只留一圈很淡的光晕
	Glow.draw(self, mp, mr * 2.6, Color(0.7, 0.8, 1.0, 0.08 * ma))
	for poly: PackedVector2Array in crescent(mp, mr, mp + Vector2(mr * 0.45, -mr * 0.15), mr * 0.9):
		draw_colored_polygon(poly, Color(0.875, 0.91, 0.96, ma))


## 月牙轮廓：圆 (o, r) 减去圆 (i, r2)
static func crescent(o: Vector2, r: float, i: Vector2, r2: float, n: int = 48) -> Array[PackedVector2Array]:
	var a: PackedVector2Array = []
	var b: PackedVector2Array = []
	for k: int in n:
		var t: float = TAU * float(k) / float(n)
		a.append(o + Vector2.from_angle(t) * r)
		b.append(i + Vector2.from_angle(t) * r2)
	var out: Array[PackedVector2Array] = []
	for poly: PackedVector2Array in Geometry2D.clip_polygons(a, b):
		if not Geometry2D.is_polygon_clockwise(poly) or poly.size() >= 3:
			out.append(poly)
	return out
