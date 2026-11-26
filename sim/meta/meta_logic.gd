class_name MetaLogic
extends RefCounted
## 元进度的纯函数（= 网页 meta.js）：meta 存档对象、祖传节点购买、冥府契约热度、余烬结算、一代结束、开新一代、先祖石碑、可选石头解锁。
## 只读写传入的字典，不碰磁盘（写盘由 app/save/save_service.gd 负责）。键名一律 snake_case；normalize 能读网页的 camelCase。

const HEAT_CAP: int = 16
const STELE_SHOW: int = 3
const DEADLINE_DAYS: Array[int] = [0, 22, 19, 16]
const DEADLINE_EMBERS: Array[int] = [0, 2, 4, 7]


static func default_meta() -> Dictionary:
	return {"v": 1, "gen": 1, "embers": 0.0, "ember_total": 0.0, "heir": {}, "endings": {}, "steles": [],
		"stones": {"moon": false, "urn": false}, "heat_max": 0, "heat_best": -1, "completions": 0,
		"best_day": 0, "seen_merchant": false, "last_run": {}, "ach": {}, "life": {}}


## camelCase → snake_case（网页存档导入）
static func snake(k: String) -> String:
	var out: String = ""
	for ch: String in k:
		out += ("_" + ch.to_lower()) if ch != ch.to_lower() else ch
	return out


static func snake_keys(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in d.keys():
		out[snake(str(k))] = d[k]
	return out


## 合并默认值并校验类型；坏数据退回默认（不会因为坏存档卡死菜单）
static func normalize(m: Variant) -> Dictionary:
	var d: Dictionary = default_meta()
	if not (m is Dictionary):
		return d
	var src: Dictionary = snake_keys(m)
	for k: Variant in src.keys():
		d[k] = src[k]
	d["gen"] = maxi(1, int(d["gen"]))
	d["embers"] = maxf(0.0, float(d["embers"]))
	d["ember_total"] = maxf(0.0, float(d["ember_total"]))
	d["heir"] = (d["heir"] as Dictionary).duplicate() if d["heir"] is Dictionary else {}
	d["endings"] = (d["endings"] as Dictionary).duplicate(true) if d["endings"] is Dictionary else {}
	var steles: Array = []
	if d["steles"] is Array:
		for s: Variant in d["steles"]:
			if s is Dictionary:
				steles.append(snake_keys(s))
	d["steles"] = steles
	var stones: Dictionary = {"moon": false, "urn": false}
	if d["stones"] is Dictionary:
		for k: Variant in (d["stones"] as Dictionary).keys():
			stones[str(k)] = bool(d["stones"][k])
	d["stones"] = stones
	d["heat_max"] = clampi(int(d["heat_max"]), 0, HEAT_CAP)
	d["heat_best"] = int(d["heat_best"])
	d["completions"] = maxi(0, int(d["completions"]))
	d["best_day"] = maxi(0, int(d["best_day"]))
	d["seen_merchant"] = bool(d["seen_merchant"])
	d["last_run"] = snake_keys(d["last_run"]) if d["last_run"] is Dictionary else {}
	d["ach"] = (d["ach"] as Dictionary).duplicate(true) if d["ach"] is Dictionary else {}
	d["life"] = (d["life"] as Dictionary).duplicate(true) if d["life"] is Dictionary else {}
	return d


## 所有代合计的统计（meta.life）：加总的、取最大的
const LIFE_SUM: PackedStringArray = ["crushed", "buildings", "chickens", "living", "pushes", "moira_total", "jars", "jackpots", "bets", "bets_won", "time_s", "crush_total", "faints"]
const LIFE_MAX: PackedStringArray = ["best_night", "max_r", "max_seals", "bet_best_odds"]


## 放弃进行中的一代（"重新开始本代"）：统计和已解锁的成就照样并进 meta，不丢
static func absorb_run(meta: Dictionary, rs: Dictionary, day: int, gen: int) -> void:
	if not (meta.get("life") is Dictionary):
		meta["life"] = {}
	if not (meta.get("ach") is Dictionary):
		meta["ach"] = {}
	merge_life(meta["life"], rs, day, int(rs.get("summit_day", 0)) > 0)
	for id: Variant in rs.get("ach", []):
		if not (meta["ach"] as Dictionary).has(str(id)):
			meta["ach"][str(id)] = {"gen": gen, "day": day}


## 一代的统计并进 meta.life（再加上代数、天数、登顶次数）
static func merge_life(life: Dictionary, rs: Dictionary, day: int, summit: bool) -> void:
	for k: String in LIFE_SUM:
		life[k] = float(life.get(k, 0.0)) + float(rs.get(k, 0.0))
	for k: String in LIFE_MAX:
		life[k] = maxf(float(life.get(k, 0.0)), float(rs.get(k, 0.0)))
	life["runs"] = int(life.get("runs", 0)) + 1
	life["days"] = int(life.get("days", 0)) + day
	if summit:
		life["summits"] = int(life.get("summits", 0)) + 1


static func default_run(meta: Dictionary) -> Dictionary:
	return {"gen": int(meta.get("gen", 1)), "stone": "basic", "pacts": {}, "heat": 0}


# ———————————————— 结局 ————————————————
static func ending_kind(c: ContentDB, id: StringName) -> StringName:
	var e: StoryDefs.Ending = c.ending_by_id.get(id)
	return e.kind if e != null else &"normal"


static func ending_name(c: ContentDB, id: StringName) -> String:
	var e: StoryDefs.Ending = c.ending_by_id.get(id)
	return e.text("name") if e != null else String(id)


## 完成一代（普通或真结局）才算"通关"：开放 / 提高热度上限、解锁月石
static func is_completion(c: ContentDB, id: StringName) -> bool:
	var k: StringName = ending_kind(c, id)
	return k == &"normal" or k == &"true"


# ———————————————— 祖传节点 ————————————————
static func heir_unlocked(c: ContentDB, meta: Dictionary, id: StringName) -> bool:
	var h: MetaDefs.Heirloom = c.heirloom_by_id.get(id)
	if h == null:
		return false
	for r: String in h.req:
		if not (meta["heir"] as Dictionary).has(r):
			return false
	return true


## &"owned" / &"locked" / &"can" / &"poor" / &"none"
static func heir_state(c: ContentDB, meta: Dictionary, id: StringName) -> StringName:
	var h: MetaDefs.Heirloom = c.heirloom_by_id.get(id)
	if h == null:
		return &"none"
	if (meta["heir"] as Dictionary).has(String(id)):
		return &"owned"
	if not heir_unlocked(c, meta, id):
		return &"locked"
	return &"can" if float(meta["embers"]) >= h.cost else &"poor"


## 购买：原地修改 meta，成功返回 true
static func buy_heirloom(c: ContentDB, meta: Dictionary, id: StringName) -> bool:
	if heir_state(c, meta, id) != &"can":
		return false
	var h: MetaDefs.Heirloom = c.heirloom_by_id[id]
	meta["embers"] = float(meta["embers"]) - h.cost
	meta["heir"][String(id)] = 1
	return true


# ———————————————— 冥府契约 ————————————————
static func heat_of(c: ContentDB, pacts: Dictionary) -> int:
	var h: int = 0
	for p: MetaDefs.Pact in c.pacts:
		if c.pact_on(p.id):
			h += clampi(int(pacts.get(String(p.id), 0)), 0, p.max_lv)
	return h


## 只保留合法条款；热度超过上限时从后往前削
static func sanitize_pacts(c: ContentDB, pacts: Dictionary, heat_max: int) -> Dictionary:
	var out: Dictionary = {}
	for p: MetaDefs.Pact in c.pacts:
		var lv: int = clampi(int(pacts.get(String(p.id), 0)), 0, p.max_lv)
		if lv > 0 and c.pact_on(p.id):
			out[String(p.id)] = lv
	var over: int = heat_of(c, out) - maxi(0, heat_max)
	for i: int in range(c.pacts.size() - 1, -1, -1):
		if over <= 0:
			break
		var id: String = String(c.pacts[i].id)
		while out.has(id) and over > 0:
			out[id] = int(out[id]) - 1
			over -= 1
			if int(out[id]) <= 0:
				out.erase(id)
	return out


static func has_reward(c: ContentDB, meta: Dictionary, id: String) -> bool:
	if not c.heat_reward_on(StringName(id)):
		return false
	for r: Variant in c.raw.get("meta/heat_rewards.json", []):
		if r is Dictionary and str((r as Dictionary).get("id", "")) == id:
			return int(meta.get("heat_best", -1)) >= int(r["heat"])
	return false


static func stone_unlocked(meta: Dictionary, id: String) -> bool:
	return id == "basic" or bool((meta.get("stones", {}) as Dictionary).get(id, false))


# ———————————————— 先祖石碑 ————————————————
static func last_stele(meta: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for s: Variant in meta.get("steles", []):
		if s is Dictionary and (best.is_empty() or int(s.get("gen", 0)) > int(best.get("gen", 0))):
			best = s
	return best


## 世界里显示的石碑（最近 STELE_SHOW 代；海拔相近的较早一代往下错开 5m）
static func stele_marks(c: ContentDB, meta: Dictionary) -> Array:
	var lst: Array = []
	for s: Variant in meta.get("steles", []):
		if s is Dictionary and float(s.get("alt", 0.0)) > 0.0:
			lst.append(s)
	lst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("gen", 0)) > int(b.get("gen", 0)))
	var used: Array[float] = []
	var out: Array = []
	for i: int in mini(STELE_SHOW, lst.size()):
		var s: Dictionary = lst[i]
		var a: float = minf(float(s["alt"]), World.SUMMIT - 6.0)
		var clash: bool = true
		while clash:
			clash = false
			for u: float in used:
				if absf(u - a) < 4.0:
					clash = true
					a -= 5.0
					break
		used.append(a)
		var nm: String = stele_name(c, s)
		out.append({"alt": a, "gen": int(s.get("gen", 0)), "day": int(s.get("day", 0)), "ending": str(s.get("ending", "")), "text": str(s.get("text", "")),
			"sprite": &"stele_ancestor", "label": Loc.t("meta_logic.generation", "第 %d 代") % int(s.get("gen", 0)), "gold": false, "npc": false,
			"line": Loc.t("meta_logic.generation_day", "第 %d 代 · 第 %d 日 · %s") % [int(s.get("gen", 0)), int(s.get("day", 0)), nm]})
	return out


## 石碑上刻的结局名：按结局 id 取当前语言的名字（存档里的 name 是当时语言写下的，只在 id 找不到时用）
static func stele_name(c: ContentDB, s: Dictionary) -> String:
	var id: String = str(s.get("ending", ""))
	if id != "" and c.ending_by_id.has(StringName(id)):
		return ending_name(c, StringName(id))
	return str(s.get("name", ""))


## 西西弗斯之名：给某一代的石碑刻字（输入框中文限 12 字、英文限 24 个字母，见 bloodline_screen.gd；这里按宽的那个截）
static func set_stele_text(meta: Dictionary, gen: int, text: String) -> void:
	var t: String = text.replace("\r", " ").replace("\n", " ").strip_edges().left(24)
	for s: Variant in meta.get("steles", []):
		if s is Dictionary and int(s.get("gen", 0)) == gen:
			s["text"] = t


# ———————————————— 余烬 ————————————————
## 一代结束时的余烬：{total, base, heat, heat_mult, fixed, debt, parts: [[标签, 数]]}
static func embers_for(c: ContentDB, meta: Dictionary, run: Dictionary, rs: Dictionary, ending_id: StringName, record: float, day: int) -> Dictionary:
	var kind: StringName = ending_kind(c, ending_id)
	var summit: bool = int(rs.get("summit_day", 0)) > 0 or record >= World.SUMMIT
	var summit_day: int = int(rs.get("summit_day", 0)) if int(rs.get("summit_day", 0)) > 0 else (day if summit else 0)
	var parts: Array = []
	var add: Callable = func(label: String, n: float) -> void:
		if n != 0.0:
			parts.append([label, n])
	add.call(Loc.t("meta_logic.bloodline_kindling", "血脉底火"), 1.0)
	add.call(Loc.t("meta_logic.generation_s_crushing", "本代碾压"), 2.0 * Js.log10(maxf(1e4, float(rs.get("crush_total", 0.0))) / 1e4))
	add.call(Loc.t("meta_logic.summit_reached", "登顶") if summit else Loc.t("meta_logic.highest_altitude_m", "最高海拔 %dm") % int(floorf(record)), 3.0 if summit else floorf(record / 250.0))
	add.call(Loc.t("meta_logic.ending", "结局 · ") + ending_name(c, ending_id), 5.0 if kind == &"true" else (1.0 if kind == &"normal" else 0.0))
	if not (meta.get("endings", {}) as Dictionary).has(String(ending_id)):
		add.call(Loc.t("meta_logic.first_time_seeing_ending", "初见此结局"), 2.0)
	if summit:
		add.call(Loc.t("meta_logic.reached_summit_day", "第 %d 天登顶") % summit_day, maxf(0.0, 17.0 - summit_day) * 0.5)
	add.call(Loc.t("meta_logic.most_seals_broken", "冥府之门最高 %d 重") % int(rs.get("max_seals", 0)), float(rs.get("max_seals", 0)) / 3.0)
	var base: float = 0.0
	for p: Array in parts:
		base += float(p[1])
	var heat: int = heat_of(c, run.get("pacts", {}))
	var total: float = floorf(base * (1.0 + 0.1 * heat))
	var dl: int = clampi(int((run.get("pacts", {}) as Dictionary).get("pk_deadline", 0)), 0, 3)
	var fixed: int = 0
	if dl > 0 and kind != &"normal-bad" and summit and summit_day <= DEADLINE_DAYS[dl]:
		fixed = DEADLINE_EMBERS[dl]
	total += fixed
	if kind == &"normal-bad":
		total = floorf(total * 0.8)
	return {"total": total, "base": base, "heat": heat, "heat_mult": 1.0 + 0.1 * heat, "fixed": fixed, "debt": kind == &"normal-bad", "parts": parts}


## 记录结局（假结局在本代中途发生时也调用）
static func record_ending(meta: Dictionary, id: StringName, gen: int) -> void:
	if id == &"":
		return
	var ends: Dictionary = meta["endings"]
	var prev: Dictionary = ends.get(String(id), {})
	ends[String(id)] = {"first": int(prev.get("first", gen)), "n": int(prev.get("n", 0)) + 1}
	if ends.size() >= 2:
		meta["stones"]["urn"] = true


## 一代结束：返回新的 meta（不写盘）
static func on_run_end(c: ContentDB, meta0: Dictionary, run: Dictionary, rs: Dictionary, ending_id: StringName, record: float, day: int, flags: Dictionary) -> Dictionary:
	var old: Dictionary = normalize(meta0)
	var e: Dictionary = embers_for(c, old, run, rs, ending_id, record, day)
	var m: Dictionary = normalize(old.duplicate(true))
	m["embers"] = float(m["embers"]) + float(e["total"])
	m["ember_total"] = float(m["ember_total"]) + float(e["total"])
	var gen: int = int(run.get("gen", m["gen"]))
	record_ending(m, ending_id, gen)
	var heat: int = heat_of(c, run.get("pacts", {}))
	if is_completion(c, ending_id):
		m["completions"] = int(m["completions"]) + 1
		m["heat_max"] = maxi(int(m["heat_max"]), 4) if int(m["completions"]) == 1 else mini(HEAT_CAP, int(m["heat_max"]) + 3)
		m["heat_best"] = maxi(int(m["heat_best"]), heat)
		m["stones"]["moon"] = true
		if heat >= 3:
			m["stones"]["urn"] = true
	var summit: bool = int(rs.get("summit_day", 0)) > 0 or record >= World.SUMMIT
	var sd: int = int(rs.get("summit_day", 0)) if int(rs.get("summit_day", 0)) > 0 else (day if summit else 0)
	if summit and sd > 0:
		m["best_day"] = mini(int(m["best_day"]), sd) if int(m["best_day"]) > 0 else sd
	if bool(flags.get("met_merchant", false)):
		m["seen_merchant"] = true
	var steles: Array = []
	for s: Variant in m["steles"]:
		if int(s.get("gen", 0)) != gen:
			steles.append(s)
	steles.append({"gen": gen, "alt": int(minf(World.SUMMIT, maxf(0.0, floorf(record)))), "day": sd if sd > 0 else day, "ending": String(ending_id),
		"name": ending_name(c, ending_id), "text": ""})
	steles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["gen"]) < int(b["gen"]))
	m["steles"] = steles.slice(maxi(0, steles.size() - 8))
	m["gen"] = maxi(int(m["gen"]), gen) + 1
	m["last_run"] = {"gen": gen, "ending_id": String(ending_id), "embers": e["total"], "parts": e["parts"], "heat": heat, "heat_mult": e["heat_mult"],
		"fixed": e["fixed"], "debt": e["debt"], "base": e["base"]}
	# 统计和成就（本局的并进来；看完日出算"应当想象"）
	merge_life(m["life"], rs, day, summit)
	var ach: Dictionary = m["ach"]
	for id: Variant in rs.get("ach", []):
		if not ach.has(str(id)):
			ach[str(id)] = {"gen": gen, "day": day}
	if String(ending_id) == "sunrise" and not ach.has("sunrise"):
		ach["sunrise"] = {"gen": gen, "day": day}
	return m


## 新一代开局时的存档（levels / money 由祖传节点决定）
static func new_run_persist(c: ContentDB, meta0: Dictionary, stone: String = "basic", pacts: Dictionary = {}, blood_branch: String = "") -> Dictionary:
	var meta: Dictionary = normalize(meta0)
	var h: Dictionary = meta["heir"]
	var levels: Dictionary = {}
	var add: Callable = func(key: String) -> void:
		var n: NodeDef = c.node_by_key.get(StringName(key))
		if n != null:
			levels[key] = mini(n.max_lv, int(levels.get(key, 0)) + 1)
	if h.has("hl_callus"):
		add.call("callus")
		add.call("arch")
	var blood: String = ""
	if h.has("hl_blood") and blood_branch != "":
		var k: int = 0
		for n: NodeDef in c.nodes:
			if String(n.br) == blood_branch and not n.hidden and k < 2:
				add.call(String(n.key))
				k += 1
		if k > 0:
			blood = blood_branch
	var st: String = stone if stone_unlocked(meta, stone) and c.stone_by_id.has(StringName(stone)) and c.stone_on(StringName(stone)) else "basic"
	var pk: Dictionary = sanitize_pacts(c, pacts, int(meta["heat_max"]))
	var run: Dictionary = {"gen": int(meta["gen"]), "stone": st, "pacts": pk, "heat": heat_of(c, pk)}
	if blood != "":
		run["blood"] = blood
	return {"v": 4, "day": 1, "money": 150 if h.has("hl_purse") else 0, "record": 0, "levels": levels, "city_level": 0,
		"run": run, "run_stats": SimGame.default_run_stats(), "ended": false}
