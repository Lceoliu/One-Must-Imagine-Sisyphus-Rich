class_name GaiaRule
extends RuleModule
## 盖亚 · 母岩（= gods/gaia.js）：地核——每夜把本夜长大量的 core_keep 存进 run_stats.core_r（SimGame.r_day 加上它）；
## 山崩（slide_on_big）：碾碎 tier≥3 大件时前方若干米中小件一起远程碾压；
## 子石（children）：半径到起滚时的若干倍时分出一块，在前面开路；地层（strata）：粘着物越多越值钱。

const SPLITS4: Array[float] = [1.5, 2.0, 3.0, 4.0]
const SPLITS2: Array[float] = [1.6, 2.4]

var r0: float = 0.0
## 子石 {s, r, rot, alive}
var kids: Array[Dictionary] = []
var born: int = 0
var slides: int = 0
var kid_crush: int = 0
var gain: float = 0.0


func is_active(st: Stats) -> bool:
	return st.core_keep > 0.0 or st.slide_on_big > 0.0 or st.children > 0.0 or st.strata > 0.0


func night_start() -> void:
	r0 = g.stone.r
	kids.clear()
	born = 0
	slides = 0
	kid_crush = 0
	gain = 0.0


func night_update(dt: float) -> void:
	var st: Stats = g.stats
	var b: Boulder = g.stone
	if not (st.children > 0.0):
		return
	var thr: Array[float] = SPLITS4 if st.children >= 4.0 else SPLITS2
	var mx: int = mini(int(st.children), thr.size())
	while born < mx and b.r >= r0 * thr[born]:
		born += 1
		kids.append({"s": b.s - b.r * 1.1, "r": b.r * st.child_frac, "rot": 0.0, "alive": true})
		g.fx.text(b.x, b.y + b.r + 2.0, Loc.t("gaia_rule.bedrock_birth", "母岩分娩"), 22.0, SimFx.GOLD, 1.0)
		g.fx.dust(b.x - b.r, b.y - b.r, 12, b.r * 0.5, 4.0)
	var s_gate: float = g.world.s_at_x(float(g.gate["x"]) + float(g.gate["w"]) * 0.4)
	for k: Dictionary in kids:
		if not bool(k["alive"]):
			continue
		var v: float = minf(-2.0, (-absf(b.vx) if b.air else b.v) * 1.25)
		var ds: float = v * dt
		var s0: float = float(k["s"])
		var kr: float = float(k["r"])
		k["s"] = s0 + ds
		k["rot"] = float(k["rot"]) + ds / kr
		if float(k["s"]) <= s_gate:
			k["alive"] = false
			continue
		# 经过的物件：够得着就远程碾压（也会触发山崩），够不着就帮母石砸裂一点然后消失
		for o: CrushObj in g.objs:
			if o.is_flat() or o.s > s0 + kr or o.s < float(k["s"]) - kr:
				continue
			if g.eff_req(o) <= kr:
				if ModUtil.remote(g, o, &"child"):
					kid_crush += 1
					slide(o)
			else:
				o.dmg += 0.5
				o.state = CrushObj.State.CRACKED
				o.shake = 1.0
				k["alive"] = false
				g.fx.dust(o.x, o.y, 8, kr, 3.0)
				break


func slide(o: CrushObj) -> void:
	var st: Stats = g.stats
	if not (st.slide_on_big > 0.0) or o.tier < 3:
		return
	var n: int = 0
	for x: CrushObj in ModUtil.objs_ahead(g, st.slide_on_big, 2, o.s):
		if ModUtil.remote(g, x, &"slide"):
			n += 1
	if n > 0:
		slides += 1
		g.fx.text(o.x, o.y + o.h + 2.0, Loc.t("gaia_rule.landslide_objects", "山崩 · %d 件") % n, 20.0, SimFx.CREAM, 1.0)
		g.fx.dust(o.x, o.y, 14, 2.0, 5.0)


func on_crush(o: CrushObj, _value: float, opt: Dictionary) -> void:
	var by: StringName = opt.get("by", &"")
	if by == &"slide" or by == &"child":
		return
	slide(o)


func value_mul(_o: CrushObj, _opt: Dictionary) -> float:
	var st: Stats = g.stats
	return 1.0 + st.strata * minf(70.0, g.stone.stuck.size()) if st.strata > 0.0 else 1.0


## 当天基础半径（用于信仰的地核上限）：r0 + growth·纪录
func core_cap_of() -> float:
	var st: Stats = g.stats
	var base: float = st.r0 + st.growth * g.record
	return (maxf(st.core_cap, st.core_cap_k * base) if st.core_cap_k > 0.0 else st.core_cap) + st.core_cap_add


func on_night_end(data: Dictionary) -> void:
	var st: Stats = g.stats
	var rs: Dictionary = g.run_stats
	if st.core_keep > 0.0:
		var before: float = float(rs.get("core_r", 0.0))
		var grow: float = maxf(0.0, float(data.get("end_r", g.stone.r)) - float(data.get("start_r", r0)))
		var after: float = minf(core_cap_of(), before + st.core_keep * grow)
		rs["core_r"] = maxf(before, after)
		gain = float(rs["core_r"]) - before
		(data["school"] as Array).append({"god": "gaia", "text": Loc.t("gaia_rule.earth_s_core_m", "地核 +%sm（累计 %sm）") % [Js.to_fixed(gain, 2), Js.to_fixed(float(rs["core_r"]), 2)]})
	if slides > 0 or kid_crush > 0:
		(data["school"] as Array).append({"god": "gaia", "text": Loc.t("gaia_rule.landslides", "山崩 %d 次%s") % [slides, (Loc.t("gaia_rule.child_stones_crushed_objects", " · 子石 %d 块碾碎 %d 件") % [born, kid_crush]) if born > 0 else ""]})
	(data["log"] as Dictionary)["core_r"] = snappedf(float(rs.get("core_r", 0.0)), 0.01)


func view_state() -> Dictionary:
	return {"kids": kids, "core_r": float(g.run_stats.get("core_r", 0.0))}
