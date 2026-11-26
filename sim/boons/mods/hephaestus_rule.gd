class_name HephaestusRule
extends RuleModule
## 赫菲斯托斯 · 锻造（= gods/hephaestus.js）：青铜轨道（track_from–track_to 海拔）：轨道上极速 ×(1+track_boost)、碾碎不减速。
## 塔罗斯（auto_slam_on_land，SimGame._land 读）。信仰"锻造流水线"：起滚海拔 25/50/75% 处各站一尊塔罗斯，路过时踢一脚（速度 +20%）并砸地。
## 隐藏：自走三足鼎（tripods，碰到炸出砸地冲击）。联动：铜网（net_window 秒内落地免费砸地、腾空 ×net_air）。

## 轨道 [s0, s1]；空 = 没有
var track: PackedFloat64Array = []
## 塔罗斯 {s, kicked, t}
var talos: Array[Dictionary] = []
## 三足鼎 {s, s0, ph, alive, boom}
var pods: Array[Dictionary] = []
var on_track: bool = false
var kicks: int = 0
var booms: int = 0
var nets: int = 0


## 卡 hephaestus_1「铜轨跳台」的效果（cards.json ["hook", "hephaestus.ramps_card"]）：没有跳台就送跳台 + 砸地 1；已经有了改成砸地 +2
func fx_ramps_card(st: Stats, _inputs: Dictionary) -> void:
	var had: bool = st.ramps and not st.hp_ramps_free
	st.ramps = true
	st.hp_ramps_free = not had
	st.slam_charges += 2.0 if had else 1.0


## 同一张卡的卡面输入（text_hook）
func text_ramps_card(st: Stats) -> Dictionary:
	return {"had_ramps": st.ramps and not st.hp_ramps_free}


func is_active(st: Stats) -> bool:
	return st.track_to > 0.0 or st.talos > 0.0 or st.tripods > 0.0 or st.net_window > 0.0


func layout(_objs: Array[CrushObj]) -> void:
	var st: Stats = g.stats
	var w: World = g.world
	track = PackedFloat64Array([w.s_at_alt(st.track_from if st.track_from > 0.0 else 15.0), w.s_at_alt(st.track_to)]) if st.track_to > 0.0 else PackedFloat64Array()
	talos.clear()
	pods.clear()


func dusk_start(_objs: Array[CrushObj]) -> Array[CrushObj]:
	var st: Stats = g.stats
	var w: World = g.world
	var b: Boulder = g.stone
	w.at(b.s)
	var alt0: float = w.ay
	talos.clear()
	for i: int in range(1, mini(3, int(st.talos)) + 1):
		var s: float = w.s_at_alt(alt0 * (i / 4.0))
		if s < b.s - 8.0:
			talos.append({"s": s, "kicked": false, "t": 0.0})
	pods.clear()
	if st.tripods > 0.0:
		var R: JsRng = JsRng.new(g.day * 977 + 5)
		var s_lo: float = w.s_at_x(float(g.gate["x"]) + 30.0)
		var s_hi: float = b.s - (10.0 + 2.5 * b.r) - 6.0
		var i: int = 0
		while i < int(st.tripods) and s_hi - s_lo > 20.0:
			var s: float = s_lo + (s_hi - s_lo) * (0.25 + 0.5 * R.next())
			pods.append({"s": s, "s0": s, "ph": R.next() * 6.0, "alive": true, "boom": 0.0})
			i += 1
	return []


func night_start() -> void:
	on_track = false
	kicks = 0
	booms = 0
	nets = 0


func night_update(dt: float) -> void:
	var st: Stats = g.stats
	var b: Boulder = g.stone
	on_track = track.size() == 2 and not b.air and b.s >= track[0] and b.s <= track[1]
	if on_track:
		g.v_t_boost *= 1.0 + st.track_boost
	# 铜网：开夜 net_window 秒内落地免费砸地
	g.free_slam = g.free_slam or (st.net_window > 0.0 and g.night_t < st.net_window)
	var slam_k: float = st.slam_value if st.slam_value > 0.0 else 1.5
	# 塔罗斯：石头下行经过时踢一脚
	for T: Dictionary in talos:
		if float(T["t"]) > 0.0:
			T["t"] = maxf(0.0, float(T["t"]) - dt)
		if bool(T["kicked"]) or b.s > float(T["s"]):
			continue
		T["kicked"] = true
		T["t"] = 0.3
		kicks += 1
		if not b.air:
			b.v *= 1.2
		else:
			b.vx *= 1.2
		var k: int = ModUtil.shock(g, b.s, b.r * 2.5, 9, slam_k, &"talos")
		g.fx.ring(b.x, b.y - b.r + 0.2, b.r * 0.6, b.r * 2.5, 0.6, SimFx.GOLD_HI, 5.0)
		g.fx.text(b.x, b.y + b.r + 2.0, Loc.t("hephaestus_rule.talos_stomp", "塔罗斯一脚%s") % ((Loc.t("hephaestus_rule.objects", " · %d 件") % k) if k > 0 else ""), 22.0, SimFx.GOLD_HI, 1.0)
		g.fx.sfx(&"land", 0.8)
	# 自走三足鼎：来回踱步；石头碰到就炸
	for P: Dictionary in pods:
		if not bool(P["alive"]):
			P["boom"] = float(P["boom"]) + dt
			continue
		P["ph"] = float(P["ph"]) + dt
		P["s"] = float(P["s0"]) + sin(float(P["ph"]) * 0.6) * 3.0
		if absf(b.s - float(P["s"])) < b.r + 0.8:
			P["alive"] = false
			booms += 1
			var k: int = ModUtil.shock(g, float(P["s"]), b.r * 2.5, 3, slam_k, &"tripod")
			var w: World = g.world
			w.at(float(P["s"]))
			var px: float = w.ax
			var py: float = w.ay
			g.fx.ring(px, py + 0.3, 0.5, b.r * 2.5, 0.7, SimFx.GOLD, 6.0)
			g.fx.sparks(px, py + 1.0, 30, 14.0)
			g.fx.text(px, py + 3.0, Loc.t("hephaestus_rule.tripods_objects", "三足鼎 · %d 件") % k, 22.0, SimFx.GOLD, 1.1)
			g.fx.flash(0.2, Color("fff1c0"))
			g.fx.sfx(&"gateImpact", 0.3)


func drag_mul(_o: CrushObj) -> float:
	return 0.0 if on_track else 1.0


func value_mul(_o: CrushObj, _opt: Dictionary) -> float:
	var st: Stats = g.stats
	return st.net_air if st.net_air > 1.0 and st.net_window > 0.0 and g.stone.air and g.night_t < st.net_window else 1.0


func on_land(info: Dictionary) -> void:
	if bool(info.get("free", false)):
		nets += 1


func on_night_end(data: Dictionary) -> void:
	var parts: PackedStringArray = []
	if kicks > 0:
		parts.append(Loc.t("hephaestus_rule.talos_stomps", "塔罗斯 %d 脚") % kicks)
	if booms > 0:
		parts.append(Loc.t("hephaestus_rule.tripods", "三足鼎 %d 座") % booms)
	if nets > 0:
		parts.append(Loc.t("hephaestus_rule.bronze_net_drops", "铜网落地 %d 次") % nets)
	if not parts.is_empty():
		(data["school"] as Array).append({"god": "hephaestus", "text": " · ".join(parts)})


func view_state() -> Dictionary:
	return {"track": track, "talos": talos, "pods": pods}
