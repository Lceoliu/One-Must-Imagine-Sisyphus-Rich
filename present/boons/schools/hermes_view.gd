extends SchoolView
## 赫尔墨斯 · 加急快递：送件——包裹剪影从旧位置被拎走（0.3 秒），再从上方落回石头新位置；新补的货上方弹出"二手"价签。
## 计数行由 view_state.hud 提供（BoonView 统一画）。


func gold(c: CanvasItem, _wv: WorldView, sim: SimGame, st: Dictionary, _vr: Vector2) -> void:
	if sim.phase != &"night":
		return
	var b: Boulder = sim.stone
	var dr: Dictionary = st.get("drop", {})
	if not dr.is_empty():
		var t: float = float(dr["t"])
		var hm: float = maxf(1.4, b.r * 1.2)
		if t < 0.3:
			spr(c, &"parcel", float(dr["from_x"]), float(dr["from_y"]) + t * 60.0, hm, 1.0 - t / 0.3)
		else:
			spr(c, &"parcel", b.x, b.y + b.r + maxf(0.0, 0.6 - t) * 40.0, hm, clampf((0.9 - t) / 0.3, 0.0, 1.0))


func hud(h: HudView, sim: SimGame, st: Dictionary, _vp: Vector2) -> void:
	if sim.phase != &"night" or h.wv == null:
		return
	for tg: Dictionary in st.get("tags", []):
		var t: float = float(tg["t"])
		if t > 0.6:
			continue
		var o: CrushObj = tg["o"]
		var sc: Vector2 = h.screen_to_hud(h.wv.to_screen(o.x, o.y + o.h + 0.5))
		var a: float = 1.0 - t / 0.6
		var r: Rect2 = Rect2(sc.x - 15.0, sc.y - 8.0 - t * 14.0, 30.0, 16.0)
		h.draw_rect(r, Color(INK, 0.8 * a))
		h.draw_rect(r, Color(CREAM, a), false, 1.0)
		h.text_at(Loc.t("hermes_view.secondhand", "二手"), Vector2(sc.x, sc.y + 4.0 - t * 14.0), 11, Color(CREAM, a), HORIZONTAL_ALIGNMENT_CENTER)
