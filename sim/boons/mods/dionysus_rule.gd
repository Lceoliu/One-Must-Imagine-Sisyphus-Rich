class_name DionysusRule
extends RuleModule
## 狄俄尼索斯 · 酒神节（= gods/dionysus.js）：醉意槽（0–100）：每碾一件按档位涨（活物 ×1.5）；满了开 revel_dur 秒酒神节：
## 门槛 ×revel_req、不减速、价值 ×revel_value、长大 ×revel_grow；结束时宿醉余震（revel_quake）、醉意保留 revel_carry。白天醉步在 SimGame.do_push。
## 隐藏：酒神游行队（thiasos，节日次数 → 明天的醉汉帮手）、葡萄藤（vine，节日里一部分碾压物挂成葡萄串，节后 ×2 再结算）。
## 联动：德尔斐排班（delphi_fill，每拍 +醉意）、尼萨专递（feed）。

## 不是 const：文字要按当前语言取（Loc.t），所以每局新建时现算
var MISREADS: Array = [
	[Loc.t("dionysus_rule.sisyphus", "西西弗斯"), Loc.t("dionysus_rule.sisyphuses", "西西弗斯们")], [Loc.t("dionysus_rule.push_stone", "推石头"), Loc.t("dionysus_rule.push_barrel", "推酒桶")], [Loc.t("dionysus_rule.underworld_gate", "冥府之门"), Loc.t("dionysus_rule.underworld_wine", "冥府之酒")], [Loc.t("dionysus_rule.summit", "山顶"), Loc.t("dionysus_rule.summit_party", "山顶派对")], [Loc.t("dionysus_rule.gods", "众神"), Loc.t("dionysus_rule.wine_gods", "众酒神")],
]

var meter: float = 0.0
var revel_t: float = 0.0
var revels: int = 0
var vine_v: float = 0.0
var vine_n: int = 0
## 葡萄串挂在石头上的角度（给表现层）
var grapes: PackedFloat64Array = []
var last_beat: int = 0
var flip: float = 0.0
var quake_n: int = 0
## 旁白念错台词 {a, b, t}；空 = 没有
var misread: Dictionary = {}


func is_active(st: Stats) -> bool:
	return st.revel_fill > 0.0 or st.thiasos > 0.0 or st.vine > 0.0


func night_start() -> void:
	meter = 0.0
	revel_t = 0.0
	revels = 0
	vine_v = 0.0
	vine_n = 0
	grapes = PackedFloat64Array()
	last_beat = 0
	flip = 0.0
	quake_n = 0
	misread = {}


func feed(amt: float, extend: float = 0.0) -> void:
	var st: Stats = g.stats
	if not (st.revel_fill > 0.0):
		return
	if revel_t > 0.0:
		revel_t += extend
		return
	meter = minf(100.0, meter + amt)
	if meter >= 100.0:
		_start_revel()


func _start_revel() -> void:
	var st: Stats = g.stats
	revel_t = st.revel_dur
	revels += 1
	meter = 100.0
	g.fx.banner(Loc.t("dionysus_rule.dionysia", "酒神节！"), Loc.t("dionysus_rule.seconds_value_crushing_never", "%d 秒 · 价值 ×%s · 碾什么都不减速") % [roundi(st.revel_dur), Js.num_str(st.revel_value)], 1.8)
	g.fx.sfx(&"revel")
	if st.revel_fill >= 2.0:   # 信仰：旁白念错台词
		var m: Array = MISREADS[revels % MISREADS.size()]
		misread = {"a": str(m[0]), "b": str(m[1]), "t": 0.0}


func _end_revel(live: bool) -> float:
	var st: Stats = g.stats
	var b: Boulder = g.stone
	revel_t = 0.0
	meter = 100.0 * st.revel_carry
	if st.revel_quake > 0.0 and live:
		var n: int = 0
		for o: CrushObj in ModUtil.objs_ahead(g, st.revel_quake, 2):
			if ModUtil.remote(g, o, &"quake"):
				n += 1
		quake_n += n
		g.fx.ring(b.x, b.y - b.r, b.r, b.r + st.revel_quake, 0.6, SimFx.CREAM, 4.0)
		if n > 0:
			g.fx.text(b.x, b.y + b.r + 2.5, Loc.t("dionysus_rule.hangover_aftershock_objects", "宿醉余震 · %d 件") % n, 22.0, SimFx.CREAM, 1.1)
	var v: float = 0.0
	if vine_v > 0.0:
		v = vine_v * 2.0
		if live:
			g.add_night_bonus(v, Loc.t("dionysus_rule.grapevines", "葡萄藤"))
			g.fx.text(b.x, b.y + b.r + 4.0, Loc.t("dionysus_rule.grapes_burst", "葡萄串炸开 +") + NumFmt.fmt(v), 24.0, SimFx.GOLD_HI, 1.2)
		vine_v = 0.0
		vine_n = 0
		grapes = PackedFloat64Array()
	return v


func night_update(dt: float) -> void:
	var st: Stats = g.stats
	if not misread.is_empty():
		misread["t"] = float(misread["t"]) + dt
		if float(misread["t"]) > 2.4:
			misread = {}
	flip = clampf(flip + (dt * 5.0 if revel_t > 0.0 else -dt * 5.0), 0.0, 1.0)
	# 德尔斐排班：石头滚动时每拍 +delphi_fill
	if st.delphi_fill > 0.0:
		var A: ApolloRule = boons.inst(&"apollo") as ApolloRule
		if A != null and A.beats > last_beat:
			var d: int = A.beats - last_beat
			last_beat = A.beats
			if absf(g.stone.v) > 3.0 or g.stone.air:
				feed(st.delphi_fill * d)
	if revel_t > 0.0:
		revel_t -= dt
		if revel_t <= 0.0:
			_end_revel(true)


func on_crush(o: CrushObj, value: float, _opt: Dictionary) -> void:
	var st: Stats = g.stats
	if revel_t > 0.0:
		if st.vine > 0.0 and g.rand.next(SimRandom.Use.VINE) < st.vine:
			vine_v += value
			vine_n += 1
			if grapes.size() < 18:
				grapes.append(g.rand.next(SimRandom.Use.COSMETIC) * TAU)
		return
	if st.revel_fill > 0.0:   # 第二场起醉得慢一些
		feed((1.0 + maxi(1, o.tier)) * (1.5 if o.def != null and o.def.living else 1.0) * st.revel_fill * (0.5 if revels > 0 else 0.8))


func req_mul(_o: CrushObj) -> float:
	return g.stats.revel_req if revel_t > 0.0 else 1.0


func drag_mul(_o: CrushObj) -> float:
	return 0.0 if revel_t > 0.0 else 1.0


func value_mul(_o: CrushObj, _opt: Dictionary) -> float:
	return g.stats.revel_value if revel_t > 0.0 else 1.0


func grow_mul(_o: CrushObj) -> float:
	return g.stats.revel_grow if revel_t > 0.0 else 1.0


func on_night_end(data: Dictionary) -> void:
	var st: Stats = g.stats
	if revel_t > 0.0:
		var v: float = _end_revel(false)
		if v > 0.0:
			(data["extra"] as Array).append({"label": Loc.t("dionysus_rule.grapevines", "葡萄藤"), "v": v})
	if revels > 0:
		(data["school"] as Array).append({"god": "dionysus", "text": Loc.t("dionysus_rule.dionysia_2", "酒神节 %d 场%s") % [revels, (Loc.t("dionysus_rule.objects_aftershocks", " · 余震 %d 件") % quake_n) if quake_n > 0 else ""]})
	# 酒神游行队：每场节日明天多一名醉汉帮手（最多 thiasos 名，第二天清醒离队）
	boons.thiasos = mini(int(st.thiasos), revels) if st.thiasos > 0.0 else 0
	(data["log"] as Dictionary)["revels"] = revels


func view_state() -> Dictionary:
	var st: Stats = g.stats
	return {"meter": meter, "revel_t": revel_t, "revel_dur": st.revel_dur, "flip": flip, "grapes": grapes, "misread": misread, "show": st.revel_fill > 0.0}
