class_name HeliosRule
extends RuleModule
## 赫利俄斯 · 日车（= gods/helios.js）：日落点火（sunset_t 秒内价值 ×(1+sunset_value)）；
## 信仰"日车坠落"：开夜火浪 40 m/s 冲下整面山坡（tier ≤1 碾碎，其余点燃 ×1.15）。
## 隐藏：太阳神的牛（sacred_cattle，dusk_start 插入若干群圣牛）。黄昏补签（overtime）在 SimGame._update_day 里。

const COW_VALUE: float = 60.0

var sun_t: float = 0.0
var sun_max: float = 0.0
var wave_x: float = NAN
var wave_n: int = 0
var lit: int = 0
var fall_t: float = 0.0


func is_active(st: Stats) -> bool:
	return st.sunset_t > 0.0 or st.phaethon or st.sacred_cattle > 0.0


func dusk_start(_objs: Array[CrushObj]) -> Array[CrushObj]:
	var st: Stats = g.stats
	var out: Array[CrushObj] = []
	if not (st.sacred_cattle > 0.0):
		return out
	var w: World = g.world
	var b: Boulder = g.stone
	var s_lo: float = w.s_at_x(float(g.gate["x"]) + 24.0)
	var s_hi: float = b.s - (10.0 + 2.5 * b.r) - 4.0
	if s_hi - s_lo < 20.0:
		return out
	var R: JsRng = JsRng.new(g.day * 613 + 17)
	var d: ObjDef = g.content.object_by_id.get(&"sacred_cow")
	var herds: int = roundi(st.sacred_cattle)
	for i: int in herds:
		var s: float = s_lo + (s_hi - s_lo) * ((i + 0.5) / herds) + (R.next() - 0.5) * 6.0
		for k: int in 3:
			w.at(s)
			var flip: bool = R.next() < 0.5
			var o: CrushObj = ModUtil.make_obj(g, &"sacred_cow", s, d.h, d.req, COW_VALUE * 3.0 * (1.0 + 0.004 * w.ay), d.tier, flip, &"bull")
			o.ext["sacred"] = true
			out.append(o)
			s += o.w + 0.5
	return out


func night_start() -> void:
	var st: Stats = g.stats
	var b: Boulder = g.stone
	sun_t = st.sunset_t
	sun_max = st.sunset_t
	wave_x = NAN
	wave_n = 0
	lit = 0
	fall_t = 0.0
	if st.phaethon:
		wave_x = b.x - b.r
		fall_t = 0.0001
		g.fx.flash(0.25, Color("fff1c0"))
		g.fx.banner(Loc.t("helios_rule.sun_chariot_crash", "日车坠落"), Loc.t("helios_rule.wave_fire_sweeps_down", "火浪冲下整面山坡"), 1.8)
		g.fx.event(&"phaethon_fall", {})


func night_update(dt: float) -> void:
	if sun_t > 0.0:
		sun_t = maxf(0.0, sun_t - dt)
	if fall_t > 0.0:
		fall_t += dt
	if not is_nan(wave_x):
		var prev: float = wave_x
		wave_x -= 40.0 * dt
		var lo: float = wave_x
		var gx: float = float(g.gate["x"])
		for o: CrushObj in g.objs:
			if o.is_flat() or o.x > prev or o.x < lo:
				continue
			if o.tier <= 1 and g.eff_req(o) <= g.stone.r:
				if ModUtil.remote(g, o, &"phaethon"):
					wave_n += 1
			elif not bool(o.ext.get("lit", false)):
				o.ext["lit"] = true
				lit += 1
		if wave_x < gx:
			wave_x = NAN


func value_mul(o: CrushObj, _opt: Dictionary) -> float:
	var m: float = 1.0
	if sun_t > 0.0:
		m *= 1.0 + g.stats.sunset_value
	if o != null and bool(o.ext.get("lit", false)):
		m *= 1.15
	return m


func on_night_end(data: Dictionary) -> void:
	var parts: PackedStringArray = []
	if g.stats.sunset_t > 0.0:
		parts.append(Loc.t("helios_rule.sunset_ignition_seconds", "日落点火 %d 秒") % roundi(sun_max))
	if wave_n > 0 or lit > 0:
		parts.append(Loc.t("helios_rule.fire_wave_objects_crushed", "火浪碾碎 %d 件 · 点燃 %d 件") % [wave_n, lit])
	if not parts.is_empty():
		(data["school"] as Array).append({"god": "helios", "text": " · ".join(parts)})
	for o: CrushObj in g.objs:
		o.ext.erase("lit")


func view_state() -> Dictionary:
	return {"sun_t": sun_t, "sun_max": sun_max, "wave_x": wave_x, "fall_t": fall_t}
