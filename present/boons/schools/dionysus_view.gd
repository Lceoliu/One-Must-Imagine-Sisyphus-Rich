extends SchoolView
## 狄俄尼索斯 · 酒神节：连碾月桂左侧的小酒杯（kylix 剖面，醉意从下往上填金，满了翻转）、节日期间四周淡墨、
## 葡萄串挂在石头上、旁白念错台词（删除线 + 改正）。


func gold(c: CanvasItem, _wv: WorldView, sim: SimGame, st: Dictionary, _vr: Vector2) -> void:
	var grapes: PackedFloat64Array = st.get("grapes", PackedFloat64Array())
	if sim.phase != &"night" or grapes.is_empty():
		return
	var b: Boulder = sim.stone
	var ctr: Vector2 = WorldView.p(b.x, b.y)
	var R: float = b.r * PPM
	var gr: float = maxf(5.0, R * 0.05)
	for a0: float in grapes:
		var a: float = a0 - b.rot
		var p0: Vector2 = ctr + Vector2(cos(a), sin(a)) * R * 0.95
		for i: int in 4:
			var pc: Vector2 = p0 + Vector2((i % 2) * gr * 1.5 - gr * 0.75, float(i / 2) * gr * 1.5)
			c.draw_circle(pc, gr, INK)
			c.draw_arc(pc, gr, 0.0, TAU, 12, CREAM, 1.2, true)


func hud(h: HudView, sim: SimGame, st: Dictionary, vp: Vector2) -> void:
	if sim.phase != &"night" or not bool(st.get("show", false)):
		return
	var revel_t: float = float(st.get("revel_t", 0.0))
	if revel_t > 0.0:
		for i: int in 4:
			var inset: float = (i + 1) * 40.0
			h.draw_rect(Rect2(0, 0, vp.x, inset), Color(INK, 0.03))
			h.draw_rect(Rect2(0, vp.y - inset, vp.x, inset), Color(INK, 0.03))
			h.draw_rect(Rect2(0, 0, inset, vp.y), Color(INK, 0.03))
			h.draw_rect(Rect2(vp.x - inset, 0, inset, vp.y), Color(INK, 0.03))
	var x: float = vp.x / 2.0 - 112.0
	var y: float = HudView.FR + 8.0 + 62.0 + 70.0
	var flip: float = float(st.get("flip", 0.0))
	var dur: float = maxf(0.01, float(st.get("revel_dur", 1.0)))
	var fill: float = clampf(revel_t / dur, 0.0, 1.0) if revel_t > 0.0 else float(st.get("meter", 0.0)) / 100.0
	h.draw_set_transform(Vector2(x, y), flip * PI * 0.85, Vector2(1.4, 1.4))
	var bowl: PackedVector2Array = []
	for i: int in 17:
		var u: float = i / 16.0
		bowl.append(Vector2(-18.0 + 36.0 * u, -8.0 + (1.0 - pow(2.0 * u - 1.0, 2.0)) * 11.0))
	h.draw_colored_polygon(bowl, Color(INK, 0.75))
	if fill > 0.0:
		var top: float = 3.0 - 11.0 * fill
		var filled: PackedVector2Array = []
		for p: Vector2 in bowl:
			if p.y >= top:
				filled.append(p)
		if filled.size() >= 3:
			h.draw_colored_polygon(filled, GOLD_HI if revel_t > 0.0 else GOLD)
	var outline: PackedVector2Array = bowl.duplicate()
	outline.append(bowl[0])
	h.draw_polyline(outline, CREAM, 1.6, true)
	h.draw_line(Vector2(0, 3), Vector2(0, 14), CREAM, 1.6)
	h.draw_line(Vector2(-7, 15), Vector2(7, 15), CREAM, 1.6)
	h.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var wob: float = sin(h.t * 11.0) * 2.0 if revel_t > 0.0 else 0.0
	var lbl: String = (Loc.t("dionysus_view.revel_s", "酒神节 %ss") % Js.to_fixed(revel_t, 1)) if revel_t > 0.0 else (Loc.t("dionysus_view.tipsy", "醉意 %d") % int(float(st.get("meter", 0.0))))
	h.text_at(lbl, Vector2(x + wob, y + 44.0), 12, GOLD_HI if revel_t > 0.0 else CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	var mr: Dictionary = st.get("misread", {})
	if not mr.is_empty():
		var t: float = float(mr["t"])
		var a2: float = clampf(minf(t / 0.2, (2.4 - t) / 0.4), 0.0, 1.0)
		var yy: float = y + 110.0
		var wa: float = Fonts.serif(700).get_string_size(String(mr["a"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		h.text_at(String(mr["a"]), Vector2(vp.x / 2.0 - 8.0 - wa, yy), 16, Color(CREAM, a2), HORIZONTAL_ALIGNMENT_LEFT)
		h.draw_line(Vector2(vp.x / 2.0 - 10.0 - wa, yy - 5.0), Vector2(vp.x / 2.0 - 6.0, yy - 5.0), Color(CREAM, a2), 1.4)
		h.text_at(Loc.t("dionysus_view.sorry", "→ %s（旁白：抱歉）") % String(mr["b"]), Vector2(vp.x / 2.0 + 4.0, yy), 16, Color(GOLD_HI, a2), HORIZONTAL_ALIGNMENT_LEFT)
