extends SchoolView
## 赫利俄斯 · 日车：日落点火（石头前方 30m 一道跳动的金色火线，随剩余秒数淡出）、火浪前沿、被点燃物件顶上的火苗、
## 开夜 0.9 秒内日车从右上坠落（HUD）。


func gold(c: CanvasItem, wv: WorldView, sim: SimGame, st: Dictionary, vr: Vector2) -> void:
	if sim.phase != &"night":
		return
	var w: World = sim.world
	var b: Boulder = sim.stone
	var sun_t: float = float(st.get("sun_t", 0.0))
	var sun_max: float = float(st.get("sun_max", 0.0))
	var tt: float = wv.t
	if sun_t > 0.0 and sun_max > 0.0:
		var a: float = 0.5 * clampf(sun_t / minf(3.0, sun_max), 0.0, 1.0)
		ground_line(c, w, b.x - 30.0, b.x - b.r * 0.5, 0.6,
			func(x: float) -> float: return 0.15 + absf(sin(x * 2.1 + tt * 9.0)) * 0.25, Color(GOLD, a), 3.0)
	var wx: float = float(st.get("wave_x", NAN))
	if not is_nan(wx):
		var p0: Vector2 = WorldView.p(wx, w.y_at_x(wx))
		c.draw_line(p0, p0 + Vector2(0.6 * PPM, -3.0 * PPM), Color(GOLD_HI, 0.75), 6.0, true)
		Glow.draw(c, p0 + Vector2(0.0, -1.5 * PPM), 2.5 * PPM, Color(GOLD, 0.3))
	for o: CrushObj in sim.objs:
		if not bool(o.ext.get("lit", false)) or o.is_flat() or o.x < vr.x or o.x > vr.y:
			continue
		var top: Vector2 = WorldView.p(o.x, o.y + o.h * o.rise)
		var f: float = maxf(6.0, o.w * PPM * 0.12) * (0.8 + 0.2 * sin(tt * 11.0 + o.s))
		var flame: PackedVector2Array = [top + Vector2(-f * 0.6, 0.0), top + Vector2(-f * 0.3, -f * 1.2), top + Vector2(0.0, -f * 2.4),
			top + Vector2(f * 0.3, -f * 1.2), top + Vector2(f * 0.6, 0.0)]
		c.draw_colored_polygon(flame, Color(GOLD, 0.75))


func hud(h: HudView, sim: SimGame, st: Dictionary, vp: Vector2) -> void:
	var ft: float = float(st.get("fall_t", 0.0))
	if sim.phase != &"night" or ft <= 0.0 or ft > 0.9:
		return
	var key: StringName = first_key([&"sun_chariot_fall", &"helios_chariot"])
	var k: float = clampf(ft / 0.6, 0.0, 1.0)
	var pos: Vector2 = Vector2(vp.x * 0.82 - k * vp.x * 0.12, -40.0 + k * vp.y * 0.35)
	var a: float = clampf((0.9 - ft) / 0.3, 0.0, 1.0)
	var tex: Texture2D = SpriteDB.tex(key)
	if tex == null:
		h.draw_circle(pos, 26.0, Color(GOLD, a))
		return
	var hh: float = 140.0
	var ww: float = hh * SpriteDB.aspect(key)
	h.draw_set_transform(pos, 0.6 + k * 0.5, Vector2.ONE)
	h.draw_texture_rect(tex, Rect2(-ww / 2.0, -hh / 2.0, ww, hh), false, Color(1, 1, 1, a))
	h.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
