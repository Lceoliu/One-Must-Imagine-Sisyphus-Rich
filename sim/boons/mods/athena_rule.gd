class_name AthenaRule
extends RuleModule
## 雅典娜 · 城邦（= gods/athena.js）：公民大会（civic_push，SimGame.do_push 读）；方阵冲锋（phalanx_rate：夜里每名帮手每秒在前方碾若干件）。
## 隐藏：重装步兵（hoplite，方阵碾压也长大；没有方阵时每 2 秒自发冲一次）、埃癸斯（aegis，每夜头几次被挡住直接撞穿 +1 重）。
## 联动：珀耳修斯套装（perseus：每程落地冲锋一次、每名帮手滚速 +1%）、工坊之城（workshop_slam：每 4 名帮手 +1 次砸地）。

var n: int = 0
var acc: float = 0.0
var idle: float = 0.0
## 冲锋剪影 {x, y, t}（给表现层）
var charges: Array[Dictionary] = []
var hits: int = 0
var aegis_left: int = 0
var aegis_seal: int = 0


func is_active(st: Stats) -> bool:
	return st.civic_push > 0.0 or st.phalanx_rate > 0.0 or st.hoplite or st.aegis > 0.0 or st.perseus or st.workshop_slam > 0.0


func night_start() -> void:
	var st: Stats = g.stats
	n = g.helper_count()
	acc = 0.0
	idle = 0.0
	charges.clear()
	hits = 0
	aegis_left = int(st.aegis)
	aegis_seal = 0
	if st.workshop_slam > 0.0:
		var add: int = mini(int(st.workshop_slam), n / 4)
		if add > 0:
			g.slam_left += add


## 冲锋一次：前方 rng_m 米内最近的够格物件（all = true 时全部）
func charge(rng_m: float, max_tier: int, all: bool = true) -> int:
	var st: Stats = g.stats
	var lst: Array[CrushObj] = ModUtil.objs_ahead(g, rng_m, max_tier)
	if not all and lst.size() > 1:
		lst = lst.slice(0, 1)
	var k: int = 0
	for o: CrushObj in lst:
		if ModUtil.remote(g, o, &"phalanx", 1.0, 1.0 if st.hoplite else 0.0):
			k += 1
			hits += 1
			if charges.size() < 10:
				charges.append({"x": o.x + 2.0, "y": o.y, "t": 0.0})
	return k


func night_update(dt: float) -> void:
	var st: Stats = g.stats
	for c: Dictionary in charges:
		c["t"] = float(c["t"]) + dt
	if not charges.is_empty() and float(charges[0]["t"]) > 0.4:
		var keep: Array[Dictionary] = []
		for c: Dictionary in charges:
			if float(c["t"]) <= 0.4:
				keep.append(c)
		charges = keep
	if st.perseus:
		g.v_t_boost *= 1.0 + minf(0.2, 0.01 * n)
	if st.phalanx_rate > 0.0 and n > 0:
		acc += n * st.phalanx_rate * dt
		while acc >= 1.0:
			acc -= 1.0
			charge(st.phalanx_range, int(st.phalanx_tier), false)
	elif st.hoplite and n > 0:
		idle += dt
		if idle >= 2.0:
			idle = 0.0
			charge(10.0, 2, false)
	# 埃癸斯：被挡住（碾不动又撞不穿）时直接撞穿
	var o: CrushObj = g.blocked_by
	if aegis_left > 0 and o != null and not o.is_flat() and not g.gate_hit:
		aegis_left -= 1
		aegis_seal += 1
		g.crush(o, {"breakthrough": true})
		g.fx.text(o.x, o.y + o.h + 3.0, Loc.t("athena_rule.aegis_make_way", "埃癸斯 · 让路"), 26.0, SimFx.GOLD, 1.2)
		if g.stone.v > -6.0:
			g.stone.v = -6.0


func extra_seals() -> int:
	return aegis_seal


func on_night_end(data: Dictionary) -> void:
	if hits > 0:
		(data["school"] as Array).append({"god": "athena", "text": Loc.t("athena_rule.phalanx_charge_objects_helpers", "方阵冲锋 %d 件 · %d 名帮手") % [hits, n]})
	(data["log"] as Dictionary)["phalanx_n"] = hits


func view_state() -> Dictionary:
	return {"charges": charges}
