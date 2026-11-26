class_name StorySystem
extends RefCounted
## 剧情（= 网页 story.js 的 Story）：NPC（奥托吕科斯 / 普罗米修斯 / 塔纳托斯）、冥府回响阶梯、墨洛珀的信、每日旁白、
## 睡着（假结局）、登顶菜单、信物效果。对话本身是数据（content/story/events/*.json，由 DialogRunner 推进），
## 这里只管"什么时候触发哪张事件图"和 flags。
## 约定（照网页）：只有奥托吕科斯扣钱；任何地方都不凭空给钱；save() 只返回数据。

var g: SimGame = null
var saved: Dictionary = {}
var flags: Dictionary = {}

## 今天的 NPC：{id, alt, s, done, retry}
var npcs: Array[Dictionary] = []
## 旁白 {text, at, life}（at 是 g.t 时刻）；空 = 没有
var narr: Dictionary = {}
var narr_day: int = 0
var idle_t: float = 0.0
var _last_in: float = -9.0
## 剧情触发的假结局 / 工资条后的事件链进行中
var busy: bool = false
var runner: DialogRunner = null


func bind(p_g: SimGame, p_saved: Dictionary) -> void:
	g = p_g
	saved = p_saved
	flags = (g.content.story.get("flags", {}) as Dictionary).duplicate(true)
	var src: Dictionary = p_saved.get("flags", p_saved) if p_saved.get("flags") is Dictionary else p_saved
	for k: Variant in src.keys():
		var key: String = _snake(str(k))
		if flags.has(key):
			flags[key] = _import_value(key, src[k])
	for k: String in ["gate_ladder", "queue"]:
		if not (flags[k] is Array):
			flags[k] = []
	for k: String in ["crush_types", "narr"]:
		if not (flags[k] is Dictionary):
			flags[k] = {}


## 网页存档（camelCase、chain 0/1、null）→ 本版 flags
static func _snake(k: String) -> String:
	var out: String = ""
	for ch: String in k:
		if ch != ch.to_lower():
			out += "_" + ch.to_lower()
		else:
			out += ch
	return out


static func _import_value(key: String, v: Variant) -> Variant:
	match key:
		"chain":
			if v is String:
				return v if v in ["none", "debt", "owned"] else "none"
			return "owned" if int(v) == 1 else "none"
		"prometheus", "pomegranate", "thanatos":
			return "none" if v == null else str(v)
		"queue":
			var q: Array = []
			if v is Array:
				for e: Variant in v:
					if e is Dictionary:
						q.append((e as Dictionary).duplicate())
			return q
	if v is Array or v is Dictionary:
		return v.duplicate(true)
	return v


func save() -> Dictionary:
	return flags.duplicate(true)


func consts() -> Dictionary:
	return g.content.story.get("consts", {})


func cst(name: String) -> float:
	return float(consts().get(name, 0.0))


## 剧情条件 / 文本的输入：day money cash record alt tod gen f + consts
func inputs() -> Dictionary:
	var d: Dictionary = ContentDB.story_inputs(flags, {"day": float(g.day), "money": g.money, "cash": floorf(maxf(0.0, g.money)),
		"record": g.record, "alt": g.altitude(), "tod": g.tod() if g.stats != null else 0.0, "gen": float(g.run.get("gen", 1))})
	var c: Dictionary = consts()
	for k: Variant in c.keys():
		d[k] = c[k]
	return d


func true_ready() -> bool:
	var e: Expr = g.content.story_true_ready
	return e != null and e.eval_bool(inputs())


func modal() -> bool:
	return runner != null or busy


## 给神龛：剧情 NPC 前后 range 米内不触发注视
func near_npc(range_m: float = 30.0) -> bool:
	var a: float = g.altitude()
	for n: Dictionary in npcs:
		if not bool(n["done"]) and absf(float(n["alt"]) - a) <= range_m:
			return true
	return false


# ———————————————— stats（信物：锁链、火种、雷霆印、石榴、渡河补偿）————————————————
func apply_stats(st: Stats) -> void:
	var inp: Dictionary = inputs()
	for p: StoryDefs.Passive in g.content.passives:
		p.apply(st, inp)


## 立刻把某个信物效果加到 st 上（拿到信物的当天就生效）
func apply_passive(id: StringName, st: Stats) -> void:
	if st == null:
		return
	for p: StoryDefs.Passive in g.content.passives:
		if p.id == id:
			p.apply(st, inputs())


# ———————————————— 新的一天：布置 NPC，选一条旁白 ————————————————
func new_day() -> void:
	npcs.clear()
	narr = {}
	idle_t = 0.0
	_last_in = g.last_input_t
	if runner != null:
		runner.abort()
		runner = null
	if g.demo or g.world == null:
		return
	var day: int = g.day
	var a0: float = g.altitude()
	var top: float = World.SUMMIT - 6.0
	var place: Callable = func(id: StringName, alt: float, retry: bool) -> void:
		alt = minf(alt, top)
		if alt <= a0 + 1.0:
			return
		npcs.append({"id": id, "alt": alt, "s": g.world.s_at_alt(alt), "done": false, "retry": retry})
	var m_alt: float = cst("MERCHANT_ALT")
	if flags["chain"] == "none" and not bool(flags["merchant_missed"]) and (day == 3 or (day == 4 and bool(flags["merchant_retry"]))):
		place.call(&"merchant", a0 + 20.0 if a0 >= m_alt - 2.0 else m_alt, day == 4)
	var p_alt: float = cst("PROMETHEUS_ALT")
	if flags["prometheus"] == "none" and a0 < p_alt - 3.0:
		place.call(&"prometheus", p_alt, false)
	var t_alt: float = cst("THANATOS_ALT")
	if day >= 8 and flags["chain"] == "owned" and flags["thanatos"] == "none":
		place.call(&"thanatos", a0 + 25.0 if a0 >= t_alt - 5.0 else t_alt, false)
	# 旁白：每天最多一条（日序台词优先；之后的海拔台词只在当天还没说过时出现）
	var nar: Dictionary = g.content.raw.get("story/narration.json", {})
	var line: String = str((nar.get("by_day", {}) as Dictionary).get(str(day), ""))
	var late: Dictionary = nar.get("late", {})
	if line == "" and day >= int(late.get("from_day", 17)) and g.record < World.SUMMIT - 1.0:
		line = str(late.get("text", ""))
	if line != "":
		say(line, 2.4)


func say(text: String, delay: float = 0.0) -> void:
	narr = {"text": text, "at": g.t + delay, "life": 5.5}
	narr_day = g.day


# ———————————————— 白天每拍 ————————————————
func update(dt: float) -> void:
	if g.phase != &"day" or g.demo or modal() or g.any_modal():
		return
	var b: Boulder = g.stone
	for n: Dictionary in npcs:
		if bool(n["done"]):
			continue
		if b.s + b.r * 0.9 >= float(n["s"]) - 0.4:
			n["done"] = true
			_meet(n)
			return
	# 海拔旁白（每天最多一条）
	var alt: float = g.altitude()
	if narr_day != g.day:
		var nar: Dictionary = g.content.raw.get("story/narration.json", {})
		for a: Dictionary in nar.get("by_alt", []):
			var aid: String = str(a["id"])
			if bool((flags["narr"] as Dictionary).get(aid, false)) or alt < float(a["alt"]):
				continue
			if bool(a.get("noon", false)) and (g.tod() >= 0.5 or flags["prometheus"] != "none"):
				continue
			flags["narr"][aid] = true
			say(str(a["text"]))
			break
	# 睡着了：白天连续 SLEEP_IDLE 秒没有任何输入（每天最多一次）
	if g.last_input_t != _last_in or g.since_input < 0.05:
		_last_in = g.last_input_t
		idle_t = 0.0
	else:
		idle_t += dt
	if idle_t >= cst("SLEEP_IDLE") and int(flags["sleep_day"]) != g.day:
		flags["sleep_day"] = g.day
		idle_t = 0.0
		play_fake(&"sleep", Callable())


func _meet(n: Dictionary) -> void:
	match n["id"]:
		&"merchant":
			run_event(&"merchant", {"day4": bool(n["retry"])})
		&"prometheus":
			run_event(&"prometheus")
		&"thanatos":
			run_event(&"thanatos")


# ———————————————— 对话 ————————————————
## 跑一张事件图；done 在整张图走完后调用（被中止则不调用）
func run_event(id: StringName, locals: Dictionary = {}, done: Callable = Callable()) -> void:
	var graph: DialogGraph = g.content.dialogs.get(id)
	if graph == null:
		push_error("[story] 缺少事件图 %s" % id)
		if done.is_valid():
			done.call()
		return
	# 同一时刻只有一张图在跑：走完先清掉 runner，再回调（回调里可能紧接着开下一张）
	var r: DialogRunner = DialogRunner.new(self, graph, locals, func() -> void:
		runner = null
		if done.is_valid():
			done.call()
		)
	runner = r
	r.start()


## 说话人资料（story.json speakers）；"" = 系统提示
func speaker(id: String) -> Dictionary:
	for s: Dictionary in g.content.story.get("speakers", []):
		if str(s.get("id", "")) == id:
			return s
	return {}


func page(who: String, text: String) -> Dictionary:
	var sp: Dictionary = speaker(who)
	return {"who": who, "name": str(sp.get("name", "")), "greek": str(sp.get("greek", "")), "portraits": sp.get("portraits", []),
		"initial": str(sp.get("initial", "")), "text": text}


## 发一个 DIALOG 模态：pages 依次翻页，最后一页显示 choices；没有选项时回答任意值都算"关闭"
func open_dialog(who: String, pages: Array, choices: Array, on_answer: Callable) -> void:
	var m: ModalRequest = ModalRequest.new()
	m.kind = ModalRequest.Kind.DIALOG
	var sp: Dictionary = speaker(who)
	m.payload = {"variant": &"dialog", "speaker": who, "name": str(sp.get("name", "")), "pages": pages, "choices": choices}
	m.n_choices = choices.size()
	m.min_show = 0.3
	m.on_answer = on_answer
	g.open_modal(m)


func request_save() -> void:
	if g.hooks.has("save"):
		(g.hooks["save"] as Callable).call()


# ———————————————— 假结局（白天 / 工资条后）：演出 → 结局卡"醒来" → 补偿 → 继续 ————————————————
func play_fake(id: StringName, then: Callable) -> void:
	busy = true
	g.fx.event(&"ending_seen", {"id": id})
	g.play_ending(id, func() -> void:
		apply_fake_comp(id)
		busy = false
		if then.is_valid():
			then.call()
		)


func _day_left() -> float:
	if g.stats == null:
		return 60.0
	return maxf(0.0, g.stats.day_length + g.mods.day_time_add - g.day_t) + 5.0


func apply_fake_comp(id: StringName) -> void:
	match id:
		&"ferry":
			if not bool(flags["ferry_seen"]):
				flags["ferry_seen"] = true
				apply_passive(&"ferry", g.stats)
		&"immortal":
			flags["thanatos"] = "locked"
			g.buff["no_back_t"] = maxf(float(g.buff.get("no_back_t", 0.0)), _day_left())
			g.fx.banner(Loc.t("story_system.wake_up", "醒来"), Loc.t("story_system.compensation_stone_won_t", "补偿：今天剩下的时间里石头不倒滑"), 2.4)
		&"throne":
			flags["throne_seen"] = true
		&"sleep":
			if g.stats != null:
				g.stamina = g.stats.stamina_max
			g.exhausted = 0
			g.buff["no_back_t"] = maxf(float(g.buff.get("no_back_t", 0.0)), 20.0)
			idle_t = 0.0
			g.fx.banner(Loc.t("story_system.achoo", "阿嚏！"), Loc.t("story_system.compensation_stamina_restored_no", "补偿：体力回满，20 秒不倒滑"), 2.2)
	if id != &"sleep" and id != &"immortal":
		request_save()


# ———————————————— 夜里 ————————————————
func on_crush(o: CrushObj) -> void:
	if g.demo or o == null:
		return
	var ct: Dictionary = flags["crush_types"]
	ct[String(o.type)] = int(ct.get(String(o.type), 0)) + 1
	if o.def == null or o.def.mat != &"ceramic":
		return
	flags["ceramics"] = int(flags["ceramics"]) + 1
	if not bool(flags["letter"]) and int(flags["ceramics"]) >= int(cst("LETTER_CERAMICS")) and g.day > int(cst("LETTER_AFTER_DAY")):
		flags["letter"] = true
		(flags["queue"] as Array).append({"type": "letter"})
		g.fx.text(o.x, o.y + o.h + 2.5, Loc.t("story_system.letter_flies_out_pot", "一封信从陶罐里飞了出来"), 20.0, SimFx.CREAM, 1.8)
		g.fx.sfx(&"pickup")


func on_gate(seals: int) -> void:
	if g.demo:
		return
	flags["max_seals"] = maxi(int(flags.get("max_seals", 0)), seals)
	var ladder: Array = consts().get("LADDER", [3, 6, 8, 9])
	var gl: Array = flags["gate_ladder"]
	var hit: Array[int] = []
	for v: Variant in ladder:
		var n: int = int(v)
		if seals >= n and not gl.has(n) and not gl.has(float(n)):
			hit.append(n)
	if hit.is_empty():
		return
	for n: int in hit:
		gl.append(n)
	var echo_seals: int = int(cst("ECHO_SEALS"))
	if hit.has(echo_seals):
		if g.day <= int(cst("ECHO_DAY")):
			flags["echo"] = true
		else:
			flags["echo_late"] = true
	# 一次撞到高重数时，3 重的卡戎张望（纯氛围）合并掉
	for n: int in hit:
		if hit.size() > 1 and n == 3:
			continue
		(flags["queue"] as Array).append({"type": "ladder", "n": n, "late": n == echo_seals and g.day > int(cst("ECHO_DAY"))})


## 结算：扣欠款（data.debt = 扣的金额，SimGame 从 net 里减）、工资条小字（data.story）
func on_night_end(data: Dictionary) -> void:
	data["debt"] = 0.0
	if not (data.get("story") is Array):
		data["story"] = []
	if g.demo:
		return
	var lines: Dictionary = g.content.raw.get("story/lines.json", {})
	var slip: Dictionary = lines.get("slip", {})
	var st: Array = data["story"]
	if float(flags["debt"]) > 0.0:
		var pay: float = minf(float(flags["debt"]), maxf(0.0, floorf(float(data.get("net", 0.0)))))
		flags["debt"] = float(flags["debt"]) - pay
		data["debt"] = pay
		if float(flags["debt"]) <= 0.0:
			flags["debt"] = 0.0
			flags["chain"] = "owned"
			st.append(str(slip.get("debt_paid", "")))
	# 错过商人
	if flags["chain"] == "none" and not bool(flags["merchant_missed"]):
		if g.day == 3 and not bool(flags["met_merchant"]):
			flags["merchant_missed"] = true
		elif g.day == 4 and bool(flags["merchant_retry"]):
			flags["merchant_missed"] = true
	if g.day == 2 and flags["chain"] == "none" and not bool(flags["merchant_missed"]):
		st.append(str(lines.get("hint_day2", "")))
	var q: Array = flags["queue"]
	var has_letter: bool = false
	var has_echo: bool = false
	for e: Dictionary in q:
		if str(e.get("type", "")) == "letter":
			has_letter = true
		if str(e.get("type", "")) == "ladder" and int(e.get("n", 0)) == int(cst("ECHO_SEALS")):
			has_echo = true
	if has_letter:
		st.append(str(slip.get("letter", "")))
	if bool(flags["echo"]) and has_echo:
		st.append(str(slip.get("echo", "")))


## 工资条"继续"之后：依次弹出排队的事件（回响阶梯、石榴、渡河、信），全部结束后调 done()
func after_payslip(done: Callable) -> void:
	busy = true
	var q: Array = flags["queue"]
	if q.is_empty():
		busy = false
		if done.is_valid():
			done.call()
		return
	var ev: Dictionary = q.pop_front()
	var id: StringName = _queued_event(ev)
	if id == &"":
		after_payslip(done)
		return
	run_event(id, {"late": bool(ev.get("late", false))}, func() -> void: after_payslip(done))


## 排队事件 → 事件图（按 trigger {kind: "queue", type, n?} 匹配）
func _queued_event(ev: Dictionary) -> StringName:
	for id: StringName in g.content.dialogs:
		var tr: Dictionary = (g.content.dialogs[id] as DialogGraph).trigger
		if str(tr.get("kind", "")) != "queue" or str(tr.get("type", "")) != str(ev.get("type", "")):
			continue
		if tr.has("n") and int(tr["n"]) != int(ev.get("n", -1)):
			continue
		return id
	return &""


# ———————————————— 登顶菜单（只列满足条件的项，顺序 = summit.json）————————————————
func summit_choices() -> Array:
	var out: Array = []
	var inp: Dictionary = inputs()
	for s: StoryDefs.Summit in g.content.summit:
		if s.available(inp):
			out.append({"id": String(s.id), "label": s.label, "kind": String(s.kind), "gold": s.gold})
	return out


# ———————————————— HUD 海拔柱标记 ————————————————
func marks() -> Array:
	var out: Array = []
	var gen: int = int(g.run.get("gen", 1))
	var knows: bool = gen >= 2 or bool(g.meta.get("seen_merchant", false))
	var m_alt: float = cst("MERCHANT_ALT")
	var m: Dictionary = _npc(&"merchant")
	if not m.is_empty() and not bool(m["done"]):
		out.append({"alt": m["alt"], "sprite": &"god_autolycus", "label": Loc.t("story_system.autolycus", "奥托吕科斯"), "gold": false, "npc": &"merchant"})
	elif m.is_empty() and knows and flags["chain"] == "none" and not bool(flags["merchant_missed"]) and g.day < 3:
		out.append({"alt": m_alt, "sprite": &"god_autolycus", "label": Loc.t("story_system.autolycus_day_3", "奥托吕科斯 · 第 3 日"), "gold": false})
	if flags["prometheus"] == "none":
		out.append({"alt": cst("PROMETHEUS_ALT"), "sprite": &"god_prometheus", "label": Loc.t("story_system.prometheus_before_noon", "普罗米修斯 · 正午前"), "gold": false, "npc": &"prometheus"})
	var t: Dictionary = _npc(&"thanatos")
	if not t.is_empty() and not bool(t["done"]):
		out.append({"alt": t["alt"], "sprite": &"god_thanatos", "label": Loc.t("story_system.thanatos", "塔纳托斯"), "gold": false, "npc": &"thanatos"})
	return out


func _npc(id: StringName) -> Dictionary:
	for n: Dictionary in npcs:
		if n["id"] == id:
			return n
	return {}


## 日晷正午刻度旁的普罗米修斯小像
func noon_mark() -> bool:
	return flags["prometheus"] == "none" and g.phase == &"day" and g.record >= 600.0 and g.tod() < 0.5
