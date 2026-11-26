class_name ApolloRule
extends RuleModule
## 阿波罗 · 七弦律（= gods/apollo.js）：夜里有节拍器，滚动中连碾不断；踩拍按空格叠和声（每层价值 +harmony_val）；
## 每 wave_every 拍一道声波清场；安可（连碾 ≥40 断开时返场）；月桂冠（完美重压放声波）；德尔斐排班联动酒神节。

var beat_t: float = 0.0
var beats: int = 0
var harm: int = 0
var miss: int = 0
var flash: float = 0.0
var waves: int = 0
var harm_max: int = 0
var hist_t: PackedFloat64Array = []   # 最近 3 秒碾压的时刻
var hist_v: PackedFloat64Array = []   # 与 hist_t 对应的价值
var encores: int = 0
var encore_v: float = 0.0
var last_combo: int = 0


func is_active(st: Stats) -> bool:
	return st.beat_keep > 0 or st.harmony_max > 0.0 or st.wave_every > 0.0 or st.encore > 0.0 or st.laurel > 0.0


func night_start() -> void:
	var st: Stats = g.stats
	beat_t = 0.0
	beats = 0
	harm = int(st.harmony_floor) if st.harmony_max > 0.0 else 0
	miss = 0
	flash = 0.0
	waves = 0
	harm_max = 0
	hist_t.clear()
	hist_v.clear()
	encores = 0
	encore_v = 0.0
	last_combo = 0


func _revel() -> bool:
	var dn: DionysusRule = boons.module(&"dionysus") as DionysusRule
	return dn != null and dn.revel_t > 0.0


func night_update(dt: float) -> void:
	var st: Stats = g.stats
	var moving: bool = ModUtil.speed_of(g) > 3.0
	g.beat_hold = g.beat_hold or (st.beat_keep > 0 and (st.beat_keep == 2 or moving))
	flash = maxf(0.0, flash - dt * 4.0)
	beat_t += dt
	var P: float = st.beat_period if st.beat_period > 0.0 else 0.5
	while beat_t >= P:
		beat_t -= P
		beats += 1
		flash = 1.0
		if st.harmony_max > 0.0:
			var keep: bool = st.delphi_fill > 0.0 and _revel()
			if not keep:
				miss += 1
				if miss >= 8:
					miss = 0
					harm = maxi(int(st.harmony_floor), harm - 1)
			if st.auto_crit > 0.0 and beats % 2 == 0:
				harm = mini(int(st.harmony_max), harm + 1)
		var every: int = 2 if (st.delphi_fill > 0.0 and _revel() and st.wave_every > 0.0) else int(st.wave_every)
		if every > 0 and beats % every == 0 and moving:
			wave(st.wave_range, int(st.wave_tier), &"wave")
	harm_max = maxi(harm_max, harm)
	if st.encore > 0.0:
		var t: float = g.night_t
		var cut: int = 0
		while cut < hist_t.size() and hist_t[cut] < t - 3.0:
			cut += 1
		if cut > 0:
			hist_t = hist_t.slice(cut)
			hist_v = hist_v.slice(cut)
		if last_combo >= 40 and g.combo < last_combo and g.combo <= 1:
			_encore(true)
		last_combo = g.combo


func wave(rng_m: float, tier: int, by: StringName) -> int:
	var b: Boulder = g.stone
	var n: int = 0
	for o: CrushObj in ModUtil.objs_ahead(g, rng_m, tier):
		if ModUtil.remote(g, o, by):
			n += 1
	waves += 1
	g.fx.ring(b.x, b.y, b.r, b.r + rng_m, 0.45, SimFx.GOLD, 3.0)
	if n > 0:
		g.fx.sfx(&"ringTick")
	return n


func _encore(live: bool) -> float:
	var st: Stats = g.stats
	var v: float = 0.0
	for h: float in hist_v:
		v += h
	v *= st.encore
	hist_t.clear()
	hist_v.clear()
	if v <= 0.0:
		return 0.0
	encores += 1
	encore_v += v
	if live:
		g.add_night_bonus(v, Loc.t("apollo_rule.encore", "安可"))
		g.fx.text(g.stone.x, g.stone.y + g.stone.r + 3.0, Loc.t("apollo_rule.encore_2", "安可！+") + NumFmt.fmt(v), 26.0, SimFx.GOLD_HI, 1.3)
		g.fx.sfx(&"critGood")
	return v


func on_space() -> bool:
	var st: Stats = g.stats
	if not (st.harmony_max > 0.0):
		return false
	var P: float = st.beat_period if st.beat_period > 0.0 else 0.5
	var off: float = minf(beat_t, P - beat_t)
	if off <= 0.1:
		harm = mini(int(st.harmony_max), harm + 1)
		miss = 0
		g.fx.text(g.stone.x, g.stone.y + g.stone.r + 1.5, Loc.t("apollo_rule.harmony", "和声 %d") % harm, 16.0, SimFx.GOLD_HI, 0.6)
		return true
	return false


func value_mul(_o: CrushObj, _opt: Dictionary) -> float:
	var st: Stats = g.stats
	return 1.0 + st.harmony_val * harm if st.harmony_max > 0.0 else 1.0


func on_crush(_o: CrushObj, value: float, opt: Dictionary) -> void:
	var st: Stats = g.stats
	if st.encore > 0.0:
		hist_t.append(g.night_t)
		hist_v.append(value)
	if st.laurel > 0.0 and opt.get("crit", &"") == &"perfect" and not bool(opt.get("remote", false)):
		wave(st.laurel, 3, &"laurel")


func on_night_end(data: Dictionary) -> void:
	var st: Stats = g.stats
	if st.encore > 0.0 and g.combo >= 40:
		var v: float = _encore(false)
		if v > 0.0:
			(data["extra"] as Array).append({"label": Loc.t("apollo_rule.encore", "安可"), "v": v})
	var parts: PackedStringArray = []
	if st.harmony_max > 0.0:
		parts.append(Loc.t("apollo_rule.harmony_peak_stacks", "和声最高 %d 层") % harm_max)
	if waves > 0:
		parts.append(Loc.t("apollo_rule.sound_waves", "声波 %d 次") % waves)
	if encores > 0:
		parts.append(Loc.t("apollo_rule.encores", "安可 %d 次") % encores)
	if not parts.is_empty():
		(data["school"] as Array).append({"god": "apollo", "text": " · ".join(parts)})
	(data["log"] as Dictionary)["harmony_max"] = harm_max
	(data["log"] as Dictionary)["waves"] = waves


func view_state() -> Dictionary:
	return {"beats": beats, "flash": flash, "harm": harm, "strings": int(g.stats.harmony_max) if g.stats.harmony_max > 0.0 else 7}
