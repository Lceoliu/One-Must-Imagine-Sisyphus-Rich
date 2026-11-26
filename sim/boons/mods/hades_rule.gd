class_name HadesRule
extends RuleModule
## 哈迪斯 · 冥府加班（= gods/hades.js）：撞门不收工——门把石头弹回（knock_bounce），冥府引力（knock_pull）再把它吸回来撞；
## 封印逐撞累加；第 2 撞起每撞记加班费。隐藏：冥河摆渡（styx_band，门前一段价值 ×styx_value、不减速）、第二道门（gate2_alt，小门 3 封）。

var knocks: int = 0
var total: int = 0
var crush_at_first: float = 0.0
var styx: bool = false
var bouncing: bool = false
var pull: float = 0.0
var pay: float = 0.0
var gate2_mult: float = 1.0
## 第二道门 {s, broken, passed, shake}；没有就是空字典
var gate2: Dictionary = {}


func is_active(st: Stats) -> bool:
	return st.knock_max > 1.0 or st.knock_pay > 0.0 or st.styx_band > 0.0 or st.gate2_alt > 0.0


func layout(_objs: Array[CrushObj]) -> void:
	var st: Stats = g.stats
	gate2 = {"s": g.world.s_at_alt(st.gate2_alt), "broken": false, "passed": false, "shake": 0.0} if st.gate2_alt > 0.0 else {}


func night_start() -> void:
	knocks = 0
	total = 0
	crush_at_first = 0.0
	styx = false
	bouncing = false
	pull = 0.0
	pay = 0.0
	gate2_mult = 1.0
	if not gate2.is_empty():
		gate2["broken"] = false
		gate2["passed"] = false


func gate_x() -> float:
	return float(g.gate["x"]) + float(g.gate["w"]) * 0.38


func night_update(dt: float) -> void:
	var st: Stats = g.stats
	var b: Boulder = g.stone
	# 冥府引力：撞过门、还在弹开的路上时往门的方向拉（引力按弹回速度放大：约 30m 处掉头）
	if bouncing and not g.gate_hit and not b.air and b.v > -0.5:
		b.v -= maxf(st.knock_pull, pull) * dt
	styx = st.styx_band > 0.0 and b.x - b.r < gate_x() + st.styx_band
	if not gate2.is_empty():
		if not bool(gate2["passed"]) and b.s <= float(gate2["s"]) and g.night_t > 0.2 and b.v < 0.0:
			gate2["passed"] = true
			gate2["shake"] = 1.0
			var vel: float = ModUtil.speed_of(g)
			var e: float = 0.5 * pow(b.r, 3.0) * st.mass_mult * vel * vel
			var seals: int = int(floorf((Js.log10(maxf(1.0, e)) - 1.0) * 1.5))
			if seals >= 3:
				gate2["broken"] = true
				gate2_mult = 1.2
				g.fx.ring(b.x, b.y, b.r, b.r * 4.0 + 6.0, 0.8, SimFx.GOLD_HI, 6.0)
				g.fx.sparks(b.x, b.y, 40, 18.0)
				g.fx.banner(Loc.t("hades_rule.second_gate_smashed_through", "第二道门 · 撞穿"), Loc.t("hades_rule.crush_value_1_2", "本夜之后的碾压 ×1.2 · 冥府之门 +1 重"), 2.0)
				g.fx.sfx(&"gateImpact", 0.4)
			else:
				g.fx.text(b.x, b.y + b.r + 2.0, Loc.t("hades_rule.second_gate_passed_through", "第二道门 · 穿门而过"), 18.0, SimFx.CREAM, 1.0)
		if float(gate2["shake"]) > 0.0:
			gate2["shake"] = maxf(0.0, float(gate2["shake"]) - dt * 1.5)


func extra_seals() -> int:
	return 1 if not gate2.is_empty() and bool(gate2["broken"]) else 0


## SimGame._hit_gate：info {E, vel, seals}（seals 已含本撞各种加成）→ {seals 累加后的总重数, stay 还没撞完, label, knocks}
func on_gate(info: Dictionary) -> Dictionary:
	var st: Stats = g.stats
	knocks += 1
	if knocks == 1:
		crush_at_first = g.night_total
	var seals: int = int(info["seals"])
	var tot: int
	if st.knock_accum and knocks > 1:
		tot = total + maxi(maxi(1, int(st.knock_min_seal)), seals / 2)
	else:
		tot = maxi(total, seals)
	tot = clampi(tot, 0, int(st.max_seals))
	total = tot
	var min_v: float = 4.0 if st.knock_max >= 99.0 else 3.0
	var vel: float = float(info["vel"])
	var stay: bool = st.knock_accum and knocks < int(st.knock_max) and vel * st.knock_bounce >= min_v and g.night_t < 100.0
	bouncing = stay
	if stay:
		var vb: float = vel * st.knock_bounce
		pull = (vb * vb) / (2.0 * 30.0)
	var label: String = (Loc.t("hades_rule.underworld_gate_hits_seals", "冥府之门 · %d 撞 · 破封 %d 重") % [knocks, tot]) if knocks > 1 else ""
	return {"seals": tot, "stay": stay, "label": label, "knocks": knocks}


func value_mul(_o: CrushObj, _opt: Dictionary) -> float:
	var m: float = gate2_mult
	if styx:
		m *= g.stats.styx_value
	return m


func drag_mul(_o: CrushObj) -> float:
	return 0.0 if styx else 1.0


func on_night_end(data: Dictionary) -> void:
	var st: Stats = g.stats
	if knocks > 1 and st.knock_pay > 0.0:
		var v: float = float(data.get("crush_sum", 0.0)) * st.knock_pay * (knocks - 1)
		if v > 0.0:
			(data["extra"] as Array).append({"label": Loc.t("hades_rule.underworld_overtime_pay", "冥府加班费"), "v": v})
			pay = v
	if knocks > 1:
		(data["school"] as Array).append({"god": "hades", "text": Loc.t("hades_rule.underworld_overtime_hits_seals", "冥府加班 %d 撞 · 破封 %d 重%s") % [knocks, total, (Loc.t("hades_rule.overtime_pay", " · 加班费 ") + NumFmt.fmt(pay)) if pay > 0.0 else ""]})
	if not gate2.is_empty() and bool(gate2["broken"]):
		(data["school"] as Array).append({"god": "hades", "text": Loc.t("hades_rule.second_gate_smashed_through", "第二道门 · 撞穿")})
	(data["log"] as Dictionary)["knocks"] = knocks


func view_state() -> Dictionary:
	var st: Stats = g.stats
	var out: Dictionary = {"styx_band": st.styx_band, "styx_x0": gate_x() if st.styx_band > 0.0 else 0.0, "gate2": gate2}
	if g.phase == &"night" and knocks >= 1 and st.knock_max > 1.0:
		out["hud"] = Loc.t("hades_rule.underworld_overtime_hit_seals", "冥府加班 第 %d/%s 撞 · 累计 %d 重") % [knocks, "∞" if st.knock_max >= 99.0 else str(int(st.knock_max)), total]
	return out
