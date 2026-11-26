extends SchoolView
## 阿波罗 · 七弦律：连碾月桂右侧一把小七弦琴——每拍琴弦一亮，和声层数的弦常亮金色。


func hud(h: HudView, sim: SimGame, st: Dictionary, vp: Vector2) -> void:
	if sim.phase != &"night":
		return
	var cx: float = vp.x / 2.0 + 112.0
	var cy: float = HudView.FR + 8.0 + 62.0 + 70.0
	var n: int = int(st.get("strings", 7))
	var harm: int = int(st.get("harm", 0))
	var flash: float = float(st.get("flash", 0.0))
	# 琴身：一道弧（墨底米边）+ 横梁
	var arm: PackedVector2Array = []
	for i: int in 13:
		var a: float = PI * 0.15 + PI * 0.7 * i / 12.0
		arm.append(Vector2(cx + cos(a) * 26.0, cy + 6.0 + sin(a) * 22.0))
	h.draw_polyline(arm, INK, 6.0, true)
	h.draw_polyline(arm, CREAM, 2.0, true)
	h.draw_line(Vector2(cx - 22.0, cy - 16.0), Vector2(cx + 22.0, cy - 16.0), CREAM, 2.0, true)
	var shown: int = mini(n, 10)
	for i: int in shown:
		var x: float = cx - 16.0 + 32.0 * i / maxf(1.0, shown - 1)
		var lit: bool = i < harm
		var col: Color = GOLD_HI if lit else Color(CREAM, 0.55 + 0.45 * flash)
		h.draw_line(Vector2(x, cy - 16.0), Vector2(x, cy + 20.0 - absf(x - cx) * 0.25), col, 2.0 if lit else 1.2, true)
	if harm > 0:
		h.text_at(Loc.t("apollo_view.harmony", "和声 %d") % harm, Vector2(cx, cy + 46.0), 12, GOLD_HI, HORIZONTAL_ALIGNMENT_CENTER)
