extends SchoolView
## 赫菲斯托斯 · 锻造：青铜轨道（沿地表两条金色细线 + 每 3m 一根墨色枕木）、路边的塔罗斯（经过时一抖）、来回踱步的三足鼎。


func _pt(w: World, s: float, off: float) -> Vector2:
	w.at(s)
	return WorldView.p(w.ax - sin(w.aang) * off, w.ay + cos(w.aang) * off)


func world(c: CanvasItem, _wv: WorldView, sim: SimGame, st: Dictionary, vr: Vector2) -> void:
	var w: World = sim.world
	var tr: PackedFloat64Array = st.get("track", PackedFloat64Array())
	if tr.size() == 2:
		var lo: float = maxf(tr[0], w.s_at_x(vr.x))
		var hi: float = minf(tr[1], w.s_at_x(vr.y))
		var s: float = ceilf(lo / 3.0) * 3.0
		while s <= hi:
			c.draw_line(_pt(w, s, 0.02) + Vector2(-3, 0), _pt(w, s, 0.5) + Vector2(-3, 0), Color(INK, 0.6), 4.0, true)
			s += 3.0
	var key: StringName = first_key([&"talos", &"hoplite"])
	var big: float = 4.6 if key == &"talos" else 2.1 * 2.2
	for T: Dictionary in st.get("talos", []):
		w.at(float(T["s"]))
		var x: float = w.ax + 2.5
		if x < vr.x - 6.0 or x > vr.y + 6.0:
			continue
		var kick: float = 1.0 + 0.08 * sin(float(T["t"]) * 40.0) if float(T["t"]) > 0.0 else 1.0
		var g: Vector3 = WorldView.ground_fit(w, x, big * SpriteDB.aspect(key), 0.08)
		spr(c, key, g.x, g.y, big, 0.95, true, -g.z, Vector2(kick, kick))
	var pk: StringName = first_key([&"tripod_walker", &"tripod"])
	for P: Dictionary in st.get("pods", []):
		if not bool(P["alive"]):
			continue
		w.at(float(P["s"]))
		var x2: float = w.ax
		if x2 < vr.x - 3.0 or x2 > vr.y + 3.0:
			continue
		var bob: float = absf(sin(float(P["ph"]) * 4.0)) * 0.15
		WorldView.spr_ground(c, w, pk, x2, 1.6, 0.35 if sim.phase == &"day" else 1.0, false, bob)


func gold(c: CanvasItem, _wv: WorldView, sim: SimGame, st: Dictionary, vr: Vector2) -> void:
	var w: World = sim.world
	var tr: PackedFloat64Array = st.get("track", PackedFloat64Array())
	if tr.size() != 2:
		return
	var lo: float = maxf(tr[0], w.s_at_x(vr.x))
	var hi: float = minf(tr[1], w.s_at_x(vr.y))
	if hi <= lo:
		return
	var a: float = 0.35 if sim.is_night() else 0.2
	for off: float in [0.18, 0.42]:
		var pts: PackedVector2Array = []
		var s: float = lo
		while s <= hi + 0.01:
			pts.append(_pt(w, minf(s, hi), off))
			s += 1.0
		if pts.size() >= 2:
			c.draw_polyline(pts, Color(GOLD, a), 2.5, true)
