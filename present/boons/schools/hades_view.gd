extends SchoolView
## 哈迪斯 · 冥府加班：冥河（门前一段地表两道波纹 + 卡戎撑船）、第二道门（小门 + 门楣三枚封印）。


func world(c: CanvasItem, wv: WorldView, sim: SimGame, st: Dictionary, vr: Vector2) -> void:
	var w: World = sim.world
	var band: float = float(st.get("styx_band", 0.0))
	if band > 0.0:
		var x0: float = float(st.get("styx_x0", 0.0))
		var xc: float = x0 + band * 0.6 + sin(wv.t * 0.6) * 2.0
		if xc > vr.x - 5.0 and xc < vr.y + 5.0:
			WorldView.spr_ground(c, w, first_key([&"charon_pusher", &"god_charon"]), xc, 2.1, 0.9 if sim.is_night() else 0.55, true, 0.2, true)
	var G2: Dictionary = st.get("gate2", {})
	if G2.is_empty():
		return
	w.at(float(G2["s"]))
	var x: float = w.ax
	if x < vr.x - 12.0 or x > vr.y + 12.0:
		return
	var small: bool = SpriteDB.has(&"gate_small")
	var hm: float = 6.0 if small else 24.0 * 0.45
	var sh: float = (randf() - 0.5) * float(G2["shake"]) * 0.4 if float(G2["shake"]) > 0.0 else 0.0
	WorldView.spr_ground(c, w, &"gate_small" if small else &"hades_gate", x + sh, hm, 0.45 if bool(G2["broken"]) else 1.0)


func gold(c: CanvasItem, wv: WorldView, sim: SimGame, st: Dictionary, vr: Vector2) -> void:
	var w: World = sim.world
	var band: float = float(st.get("styx_band", 0.0))
	if band > 0.0:
		var x0: float = float(st.get("styx_x0", 0.0))
		var x1: float = x0 + band
		if x1 > vr.x and x0 < vr.y:
			var tt: float = wv.t
			for k: int in 2:
				var kk: float = k
				ground_line(c, w, maxf(x0, vr.x), minf(x1, vr.y), 0.5,
					func(x: float) -> float: return 0.12 + kk * 0.22 + sin(x * 1.3 + tt * 2.0 + kk) * 0.06,
					Color(CREAM, 0.45) if k == 1 else Color(INK, 0.7), 1.2 if k == 1 else 3.0)
	var G2: Dictionary = st.get("gate2", {})
	if G2.is_empty():
		return
	w.at(float(G2["s"]))
	var x: float = w.ax
	if x < vr.x - 12.0 or x > vr.y + 12.0:
		return
	var hm: float = 6.0 if SpriteDB.has(&"gate_small") else 24.0 * 0.45
	var ctr: Vector2 = WorldView.p(x, w.y_at_x(x) + hm * 0.92)
	var r: float = maxf(4.0, hm * PPM * 0.04)
	for i: int in 3:
		var pc: Vector2 = ctr + Vector2((i - 1) * hm * PPM * 0.12, 0.0)
		c.draw_circle(pc, r, GOLD_HI if bool(G2["broken"]) else INK)
		c.draw_arc(pc, r, 0.0, TAU, 16, CREAM, 1.5, true)
