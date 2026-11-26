class_name BoonSystem
extends RefCounted
## 神的机制与赐福祭坛（docs/v06/incremental.md 第 4 节）。
## - 机制：八位主神各一个规则模块（sim/boons/mods/*_rule.gd，清单 = rules/modules.json）。模块看 Stats 自己决定是否生效，
##   效果来源是商店节点、祭坛、契约、祖传……本文件只负责分发钩子。
## - 祭坛：固定海拔（boons/altars.json）。推过去就神降演出（ModalRequest.Kind.ALTAR，表现层 AltarShow），效果立刻生效、整局有效；
##   不选、没有代价。存档只记已经点亮的祭坛下标。
## 钩子合成规则（照抄 boons.js）：*_mul 连乘；on_space 任一为真；before_night_end 第一个真；dusk_start 的新物件并入 objs 后按 s 稳定排序。

const SAVE_V: int = 3

var g: SimGame = null
var saved: Dictionary = {}

# —— 整局状态（存档）——
## 已经点亮的祭坛（altars.json 的下标，按点亮顺序）
var done: Array[int] = []
## 酒神游行队（隐藏节点 dn_thiasos）：昨夜酒神节攒下、今天来帮推的醉汉数
var thiasos: int = 0

# —— 运行时 ——
## 推过了、还没演出的祭坛（有别的模态开着时先排队）
var pending: Array[int] = []
var night_knocks: int = 0
var last_log: Dictionary = {}
var _mods: Array[RuleModule] = []
var _mod_by_id: Dictionary = {}


func bind(p_g: SimGame, p_saved: Dictionary) -> void:
	g = p_g
	saved = p_saved
	_load(p_saved)
	_make_modules()


## SimGame.dispose 调用：打断 模块 ↔ BoonSystem ↔ SimGame 的环
func dispose() -> void:
	for m: RuleModule in _mods:
		m.g = null
		m.boons = null
	_mods.clear()
	_mod_by_id.clear()
	g = null


# ———————————————— 存档 ————————————————
## v3：{v, done}。旧存档（v2 及以前，选卡制）不迁移：已经推过的祭坛在下一个白天开始时补一次演出、补上效果
func _load(s: Dictionary) -> void:
	done.clear()
	pending.clear()
	if int(s.get("v", 0)) != SAVE_V:
		return
	var n: int = g.content.altars.size()
	for v: Variant in s.get("done", []):
		var i: int = int(v)
		if i >= 0 and i < n and not done.has(i):
			done.append(i)
	thiasos = maxi(0, int(s.get("thiasos", 0)))


func save() -> Dictionary:
	return {"v": SAVE_V, "done": done.duplicate(), "thiasos": thiasos}


# ———————————————— 模块 ————————————————
## 每天 layout 时重建（= 网页 layout 清空 this.st）
func _make_modules() -> void:
	for m: RuleModule in _mods:
		m.g = null
		m.boons = null
	_mods.clear()
	_mod_by_id.clear()
	for m: Dictionary in g.content.modules:
		var scr: Script = load(String(m.get("script", "")))
		if scr == null:
			push_error("[boons] 模块脚本缺失：%s" % m.get("script", ""))
			continue
		var inst: RuleModule = scr.new()
		inst.id = StringName(str(m.get("id", "")))
		var gd: GodDef = g.content.god_by_id.get(inst.id)
		inst.bind(g, self, gd.tuning if gd != null else {})
		_mods.append(inst)
		_mod_by_id[inst.id] = inst


## 当前有效的模块（stats 满足 is_active）
func active_mods() -> Array[RuleModule]:
	var out: Array[RuleModule] = []
	var st: Stats = g.stats
	if st == null:
		return out
	for m: RuleModule in _mods:
		if m.is_active(st):
			out.append(m)
	return out


## 有效的模块实例（= 网页 boons.mod(id)）；没生效返回 null
func module(id: StringName) -> RuleModule:
	var m: RuleModule = _mod_by_id.get(id)
	return m if m != null and g.stats != null and m.is_active(g.stats) else null


## 模块实例（不管是否生效；= 网页 boons.state(id)，跨模块读状态用）
func inst(id: StringName) -> RuleModule:
	return _mod_by_id.get(id)


## EffectList 的 hook 宿主："<模块>.<函数>" → 模块的 fx_<函数>(st, inputs)
func call_fx(name: StringName, st: Stats, inputs: Dictionary) -> bool:
	var parts: PackedStringArray = String(name).split(".")
	if parts.size() != 2:
		return false
	var m: RuleModule = inst(StringName(parts[0]))
	var fn: StringName = StringName("fx_" + parts[1])
	if m == null or not m.has_method(fn):
		return false
	m.call(fn, st, inputs)
	return true


# ———————————————— 祭坛 ————————————————
func altar_count() -> int:
	return g.content.altars.size()


func altar(i: int) -> Dictionary:
	return g.content.altars[i]


func altar_alt(i: int) -> float:
	return float(g.content.altars[i]["alt"])


## startDay（meta 之后、story 之前）：已点亮的祭坛按点亮顺序叠加
func apply_stats(st: Stats) -> void:
	for k: StringName in Stats.CARD_NEUTRAL.keys():
		st.set(k, Stats.CARD_NEUTRAL[k])
	for i: int in done:
		(altar(i)["fx"] as EffectList).apply(st, {}, self)
	st.patron = &""
	if thiasos > 0:
		st.helper_push += 0.5 * thiasos
		st.drunkards = thiasos


## 白天推出新纪录时：越过的祭坛排队演出
func on_record(prev: float, cur_alt: float) -> void:
	if g.demo:
		return
	for i: int in altar_count():
		if prev < altar_alt(i) and cur_alt >= altar_alt(i) and not done.has(i) and not pending.has(i):
			pending.append(i)
	pending.sort()
	try_open()


## 新的一天：纪录已经越过、却还没点亮的祭坛（旧存档、开局设置改过纪录）排队，白天第一拍补演
func on_day_start() -> void:
	if g.demo:
		return
	for i: int in altar_count():
		if altar_alt(i) <= g.record and not done.has(i) and not pending.has(i):
			pending.append(i)
	pending.sort()
	# 不在这里开：天亮运镜（模拟暂停）放完、第一拍 day_update 再演


## 有别的模态开着时先等（day_update 每拍再试）
func try_open() -> void:
	if g.demo or g.phase != &"day" or g.any_modal() or pending.is_empty():
		return
	_light(pending.pop_front())


## 点亮：效果立刻写进今天的 stats（明天起由 apply_stats 叠加），再请表现层演一段神降
func _light(i: int) -> void:
	if done.has(i):
		return
	done.append(i)
	var a: Dictionary = altar(i)
	if g.stats != null:
		(a["fx"] as EffectList).apply(g.stats, {}, self)
	var gd: GodDef = g.content.god_by_id.get(a["god"])
	g.fx.sfx(&"faith")
	if not g.sis.is_empty():
		g.fx.sparks(float(g.sis["x"]), float(g.sis["y"]) + 3.0, 30, 9.0)
	g.fx.event(&"altar_lit", {"idx": i, "god": a["god"]})
	g.run_stats["altars"] = done.size()
	var m: ModalRequest = ModalRequest.new()
	m.kind = ModalRequest.Kind.ALTAR
	m.id = i
	m.payload = {"variant": &"altar", "idx": i, "god": a["god"], "card": a["card"], "alt": altar_alt(i),
		"kicker": Loc.t("boon_system.altar_m", "赐福祭坛 · %d m") % int(altar_alt(i)), "name": a["name"], "hi": a["hi"], "lo": a["lo"], "line": a["line"],
		"title": gd.title if gd != null else "", "greek": gd.greek if gd != null else "", "cn": gd.cn if gd != null else ""}
	m.n_choices = 1
	m.min_show = 0.6
	m.on_answer = func(_i: int) -> void:
		g.fx.event(&"altar_done", {"idx": i})
		try_open()
	g.open_modal(m)


# ———————————————— 玩法钩子分发 ————————————————
func layout(objs: Array[CrushObj]) -> void:
	_make_modules()
	g.v_t_boost = 1.0
	g.beat_hold = false
	g.free_slam = false
	for m: RuleModule in active_mods():
		m.layout(objs)


## 黄昏：模块插入的新物件（圣牛、路障……）并入 objs（同一个数组），按 s 稳定排序
func dusk_start(objs: Array[CrushObj]) -> void:
	var add: Array[CrushObj] = []
	for m: RuleModule in active_mods():
		add.append_array(m.dusk_start(objs))
	if not add.is_empty():
		objs.append_array(add)
		Js.stable_sort_by_s(objs)


func day_update(dt: float) -> void:
	try_open()
	for m: RuleModule in active_mods():
		m.day_update(dt)


func night_start() -> void:
	night_knocks = 0
	for m: RuleModule in active_mods():
		m.night_start()


func night_update(dt: float) -> void:
	g.v_t_boost = 1.0
	g.beat_hold = false
	g.free_slam = false
	for m: RuleModule in active_mods():
		m.night_update(dt)


func on_space() -> bool:
	var hit: bool = false
	for m: RuleModule in active_mods():
		if m.on_space():
			hit = true
	return hit


func value_mul(o: CrushObj, opt: Dictionary) -> float:
	var k: float = 1.0
	for m: RuleModule in active_mods():
		k *= m.value_mul(o, opt)
	return k


func req_mul(o: CrushObj) -> float:
	var k: float = 1.0
	for m: RuleModule in active_mods():
		k *= m.req_mul(o)
	return k


func drag_mul(o: CrushObj) -> float:
	var k: float = 1.0
	for m: RuleModule in active_mods():
		k *= m.drag_mul(o)
	return k


func grow_mul(o: CrushObj) -> float:
	var k: float = 1.0
	for m: RuleModule in active_mods():
		k *= m.grow_mul(o)
	return k


func on_crush(o: CrushObj, value: float, opt: Dictionary) -> void:
	for m: RuleModule in active_mods():
		m.on_crush(o, value, opt)


func on_land(info: Dictionary) -> void:
	for m: RuleModule in active_mods():
		m.on_land(info)


## 撞门：info {E, vel, seals}（seals 是 SimGame 算好的本撞重数）→ {seals, stay, knocks?, label?, extra}
func on_gate(info: Dictionary) -> Dictionary:
	var st: Stats = g.stats
	var extra: int = 0
	var hm: HermesRule = module(&"hermes") as HermesRule
	if night_knocks == 0:
		var h0: HermesRule = inst(&"hermes") as HermesRule
		if st.psycho_seal > 0.0 and h0 != null and h0.trip > 1:
			extra += mini(int(st.psycho_seal), h0.trip - 1)
		for id: StringName in [&"hades", &"athena"]:
			var m: RuleModule = module(id)
			if m != null:
				extra += m.extra_seals()
	night_knocks += 1
	if hm != null:
		hm.mark_gate()
	var seals: int = int(info["seals"]) + extra
	var hd: HadesRule = module(&"hades") as HadesRule
	if hd != null:
		var inf2: Dictionary = info.duplicate()
		inf2["seals"] = seals
		var r: Dictionary = hd.on_gate(inf2)
		r["extra"] = extra
		return r
	return {"seals": seals, "stay": false, "extra": extra}


## 门倍率作用的那部分碾压额（赫尔墨斯：没撞到门的那几程不吃门倍率）
func gated_part(crush_sum: float) -> float:
	var hm: HermesRule = module(&"hermes") as HermesRule
	return maxf(0.0, crush_sum - hm.ungated()) if hm != null else crush_sum


func before_night_end(reason: StringName) -> bool:
	for m: RuleModule in active_mods():
		if m.before_night_end(reason):
			return true
	return false


func on_night_end(data: Dictionary) -> void:
	if not data.has("extra"):
		data["extra"] = []
	data["school"] = []
	data["log"] = {}
	var act: Array[RuleModule] = active_mods()
	for m: RuleModule in act:
		m.on_night_end(data)
	var dn: RuleModule = inst(&"dionysus")
	if dn == null or not act.has(dn):
		thiasos = 0
	last_log = (data["log"] as Dictionary).duplicate()


## 机器人每日日志
func log_day() -> Dictionary:
	var out: Dictionary = {"altars": done.size()}
	out.merge(last_log)
	return out


# ———————————————— 给 HUD / 工资条 ————————————————
func marks() -> Array:
	var out: Array = []
	for i: int in altar_count():
		var a: Dictionary = altar(i)
		out.append({"alt": altar_alt(i), "sprite": &"altar_boon", "label": Loc.t("boon_system.altar", "%s的祭坛") % _cn(a["god"]), "gold": false, "done": done.has(i), "god": a["god"]})
	return out


## 已点亮的祭坛（按点亮顺序）：工资条、HUD 用
func summary() -> Array:
	var out: Array = []
	for i: int in done:
		var a: Dictionary = altar(i)
		out.append({"id": "altar_%d" % i, "name": a["name"], "god": "god_" + String(a["god"]), "desc": Loc.t("boon_system.join_semicolon", "%s；%s") % [a["hi"], a["lo"]],
			"line": a["line"], "alt": altar_alt(i)})
	return out


func _cn(god: StringName) -> String:
	var gd: GodDef = g.content.god_by_id.get(god)
	return gd.cn if gd != null else String(god)


## 每个生效模块给表现层的只读状态 {模块 id: Dictionary}
func view_states() -> Dictionary:
	var out: Dictionary = {}
	for m: RuleModule in active_mods():
		out[m.id] = m.view_state()
	return out
