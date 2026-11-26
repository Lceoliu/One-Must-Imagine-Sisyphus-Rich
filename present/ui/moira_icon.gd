class_name MoiraIcon
extends RefCounted
## 第二货币「命运」的图标：一只线轴（黑釉的两片轴盘 + 中间缠着奶油色的线，斜着几道刻线表示一圈圈的线）。
## 用代码画（HUD 计数、宝瓶转轮、商店价格都用同一个），不依赖贴图；以后有画好的线轴贴图可以在这里换。

const INK: Color = Color("120c0a")
const THREAD: Color = Color("eadbb8")
const THREAD_DARK: Color = Color("b89c74")


## 在 ctr 画一只线轴；r = 半高（像素）；a = 整体透明度；glow = 线是否发金（大奖）
static func draw(c: CanvasItem, ctr: Vector2, r: float, a: float = 1.0, glow: bool = false) -> void:
	var w: float = r * 1.25            # 轴盘宽
	var core_w: float = r * 0.9        # 线团宽
	var fl: float = r * 0.32           # 轴盘厚
	var ink: Color = Color(INK, a)
	var th: Color = Color(Color("ffe08a") if glow else THREAD, a)
	var th_d: Color = Color(THREAD_DARK, a)
	# 线团（略鼓的腰）
	var top: float = ctr.y - r + fl * 0.8
	var bot: float = ctr.y + r - fl * 0.8
	var pts: PackedVector2Array = []
	var n: int = 10
	for i: int in n + 1:
		var k: float = float(i) / n
		var y: float = lerpf(top, bot, k)
		pts.append(Vector2(ctr.x - core_w / 2.0 - sin(k * PI) * r * 0.08, y))
	for i: int in range(n, -1, -1):
		var k: float = float(i) / n
		var y: float = lerpf(top, bot, k)
		pts.append(Vector2(ctr.x + core_w / 2.0 + sin(k * PI) * r * 0.08, y))
	c.draw_colored_polygon(pts, th)
	# 一圈圈的线：斜刻线
	var lw: float = maxf(1.0, r * 0.07)
	var m: int = 4
	for i: int in m:
		var y: float = lerpf(top, bot, (i + 0.5) / m)
		c.draw_line(Vector2(ctr.x - core_w / 2.0, y + r * 0.1), Vector2(ctr.x + core_w / 2.0, y - r * 0.1), th_d, lw, true)
	# 上下两片轴盘
	for sy: float in [-1.0, 1.0]:
		var cy: float = ctr.y + sy * (r - fl / 2.0)
		var rect: Rect2 = Rect2(ctr.x - w / 2.0, cy - fl / 2.0, w, fl)
		c.draw_rect(rect, ink)
		c.draw_line(Vector2(rect.position.x + fl * 0.3, cy), Vector2(rect.end.x - fl * 0.3, cy), Color(THREAD, a * 0.55), maxf(1.0, r * 0.05), true)
	# 线头：从线团右边垂下一小截
	c.draw_line(Vector2(ctr.x + core_w / 2.0, ctr.y + r * 0.15), Vector2(ctr.x + core_w / 2.0 + r * 0.35, ctr.y + r * 0.55), th, lw * 1.2, true)
