extends SchoolView
## 盖亚 · 母岩：子石（墨色小石 + 米色裂纹，跟着母石滚）、白天石头中心的地核年轮。


func world(c: CanvasItem, _wv: WorldView, sim: SimGame, st: Dictionary, _vr: Vector2) -> void:
	if sim.phase != &"night":
		return
	var w: World = sim.world
	for k: Dictionary in st.get("kids", []):
		if not bool(k["alive"]):
			continue
		var kr: float = float(k["r"])
		w.at(float(k["s"]))
		var ctr: Vector2 = WorldView.p(w.ax - sin(w.aang) * kr, w.ay + cos(w.aang) * kr)
		var R: float = kr * PPM
		c.draw_set_transform(ctr, -float(k["rot"]), Vector2.ONE)
		c.draw_circle(Vector2.ZERO, R, INK)
		c.draw_arc(Vector2.ZERO, R * 0.7, 0.3, 2.4, 16, Color("e9d3a8"), maxf(1.5, R * 0.04), true)
		c.draw_arc(Vector2.ZERO, R * 0.45, 3.4, 4.6, 10, Color("e9d3a8"), maxf(1.2, R * 0.03), true)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func gold(c: CanvasItem, _wv: WorldView, sim: SimGame, st: Dictionary, _vr: Vector2) -> void:
	var core: float = float(st.get("core_r", 0.0))
	if core <= 0.02 or sim.phase != &"day":
		return
	var b: Boulder = sim.stone
	var ctr: Vector2 = WorldView.p(b.x, b.y)
	var r: float = minf(core, b.r * 0.92) * PPM
	c.draw_circle(ctr, r, Color(INK, 0.35))
	for f: float in [1.0, 0.66, 0.36]:
		c.draw_arc(ctr, r * f, 0.0, TAU, 40, Color(CREAM, 0.7), 1.5, true)
