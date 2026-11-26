class_name HermesRule
extends RuleModule
## 赫尔墨斯 · 加急快递（= gods/hermes.js）：石头停下（或撞完门）不收工，送回本夜起滚海拔的 trip_height 处再滚一程，
## 送之前山坡按 restock 折价补货；快递业务（极速 80% 以上远程碾）；塔拉里亚（每程落地冲击波）；联动读写 dionysus / athena。

var trip: int = 0
var trip_value: float = 1.0
var restocked: int = 0
var sums: Array[float] = []
var gated: Dictionary = {}
var express_acc: float = 0.0
var express: int = 0
## 送件动画（给表现层）：{from_x, from_y, t}；空 = 没有
var drop: Dictionary = {}
## 新补的货上方的"二手"价签：[{o: CrushObj, t}]
var tags: Array[Dictionary] = []


func is_active(st: Stats) -> bool:
	return st.trips_max > 0.0 or st.faith_trips or st.express_rate > 0.0 or st.trip_ring > 0.0


func max_trips() -> int:
	return int(tune.get("max_trips", 4))


func night_start() -> void:
	trip = 1
	trip_value = 1.0
	restocked = 0
	sums = [0.0]
	gated = {}
	express_acc = 0.0
	express = 0
	drop = {}
	tags.clear()


func value_mul(_o: CrushObj, _opt: Dictionary) -> float:
	return trip_value


## 门倍率只乘撞到门的那几程
func mark_gate() -> void:
	if trip > 0:
		gated[trip - 1] = true


func ungated() -> float:
	var u: float = 0.0
	for i: int in sums.size():
		if not gated.has(i):
			u += sums[i]
	return u


func on_crush(_o: CrushObj, value: float, _opt: Dictionary) -> void:
	if trip > 0 and trip - 1 < sums.size():
		sums[trip - 1] += value


func night_update(dt: float) -> void:
	var st: Stats = g.stats
	var b: Boulder = g.stone
	if not drop.is_empty():
		drop["t"] = float(drop["t"]) + dt
		if float(drop["t"]) > 0.9:
			drop = {}
	for tg: Dictionary in tags:
		tg["t"] = float(tg["t"]) + dt
	if not tags.is_empty() and float(tags[0]["t"]) > 0.8:
		tags.clear()
	if st.express_rate > 0.0 and not b.air and ModUtil.speed_of(g) >= 0.8 * ModUtil.v_term(g):
		express_acc += st.express_rate * dt
		while express_acc >= 1.0:
			express_acc -= 1.0
			var ahead: Array[CrushObj] = ModUtil.objs_ahead(g, st.express_range)
			if not ahead.is_empty():
				var o: CrushObj = ahead[0]
				if ModUtil.remote(g, o, &"express"):
					express += 1
					g.fx.text(o.x, o.y + o.h + 1.2, Loc.t("hermes_rule.delivered", "已送达"), 14.0, SimFx.CREAM, 0.6)
	else:
		express_acc = minf(express_acc, 0.99)


func before_night_end(reason: StringName) -> bool:
	var st: Stats = g.stats
	if not (st.trips_max > 0.0 or st.faith_trips) or trip == 0:
		return false
	if trip >= max_trips() or g.night_t > (55.0 if st.knock_max > 1.0 else 60.0):
		return false
	if st.faith_trips:
		var first: float = sums[0]
		var last: float = sums[trip - 1]
		if trip > 1 + int(st.trips_max) and last < 0.2 * first:
			return false
	elif trip >= 1 + int(st.trips_max):
		return false
	_deliver(reason)
	return true


func _deliver(_reason: StringName) -> void:
	var st: Stats = g.stats
	var b: Boulder = g.stone
	trip += 1
	sums.append(0.0)
	trip_value = 1.0 + st.trip_step * (trip - 1)
	# 镜头附近会被补货的物件（补完弹"二手"价签）
	var near: Array[CrushObj] = []
	for o: CrushObj in g.objs:
		if o.is_flat() and not o.city and o.roadblock == &"" and absf(o.x - b.x) < 140.0:
			near.append(o)
	var n: int = g.restock_flat(st.restock)
	restocked += n
	tags.clear()
	for o2: CrushObj in near.slice(maxi(0, near.size() - 24)):
		if not o2.is_flat():
			tags.append({"o": o2, "t": 0.0})
	var alt: float = maxf(2.0, g.start_alt * st.trip_height)
	var v: float = -(1.5 + st.start_speed) * g.mods.night_speed_mult * st.night_speed * st.trip_speed
	var from_x: float = b.x
	var from_y: float = b.y
	g.place_stone_at(g.world.s_at_alt(alt), minf(v, -6.0))
	drop = {"from_x": from_x, "from_y": from_y, "t": 0.0}
	if not st.combo_carry:
		g.combo = 0
		g.combo_t = 0.0
	g.fx.sfx(&"whoosh")
	g.fx.event(&"hermes_drop", {"from_x": from_x, "from_y": from_y})
	var nm: String = Loc.t("hermes_rule.free_mountainwide_shipping", "全山包邮") if trip >= 4 else (Loc.t("hermes_rule.next_day_delivery", "次日达") if trip == 3 else Loc.t("hermes_rule.express_parcel", "加急件"))
	g.fx.banner(Loc.t("hermes_rule.trip", "第 %d 程 · %s") % [trip, nm], (Loc.t("hermes_rule.slope_objects_restocked_secondhand", "山坡补货 %d 件（二手）· 本程价值 ×%s") % [n, Js.to_fixed(trip_value, 2)]) if n > 0 else (Loc.t("hermes_rule.trip_value", "本程价值 ×%s") % Js.to_fixed(trip_value, 2)), 1.8)
	if st.trip_ring > 0.0:
		var k: int = ModUtil.shock(g, b.s, st.trip_ring, 3, 1.0, &"sandals")
		g.fx.ring(b.x, b.y - b.r + 0.2, b.r * 0.5, st.trip_ring, 0.6, SimFx.GOLD_HI, 4.0)
		if k > 0:
			g.fx.text(b.x, b.y + b.r + 2.0, Loc.t("hermes_rule.winged_landing_objects", "翼鞋落地 · %d 件") % k, 18.0, SimFx.GOLD_HI, 1.0)
	if st.nysa_fill > 0.0:
		var dn: DionysusRule = boons.module(&"dionysus") as DionysusRule
		if dn != null:
			dn.feed(st.nysa_fill, 2.0)
	if st.perseus:
		var at: AthenaRule = boons.module(&"athena") as AthenaRule
		if at != null:
			at.charge(12.0, 2, true)


func on_night_end(data: Dictionary) -> void:
	if trip == 0:
		return
	if trip > 1 or express > 0:
		(data["school"] as Array).append({"god": "hermes", "text": Loc.t("hermes_rule.delivery_trips_objects_restocked", "快递 %d 程 · 补货 %d 件%s") % [trip, restocked, (Loc.t("hermes_rule.express_deliveries", " · 快递业务 %d 件") % express) if express > 0 else ""]})
	(data["log"] as Dictionary)["trips"] = trip


func view_state() -> Dictionary:
	var st: Stats = g.stats
	if not (st.trips_max > 0.0 or st.faith_trips):
		return {}
	return {"hud": Loc.t("hermes_rule.delivery_trip", "快递 第 %d/%d 程 · ×%s") % [trip, max_trips() if st.faith_trips else mini(max_trips(), 1 + int(st.trips_max)), Js.to_fixed(trip_value, 2)], "gold": trip > 1,
		"drop": drop, "tags": tags}
