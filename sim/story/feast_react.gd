class_name FeastReact
extends RefCounted
## 夜宴里神对今晚的反应（docs/v06/incremental.md 第 14 节）。台词在 content/hub/hub.json 的 react 列表里：
## {who: 站点 id 或说话人, when: 条件名, ge: 阈值（默认 1）, text: 台词（{名字} 换成 context 里的值）}，按顺序取第一条满足的。
## 条件只看今晚结算的数据（SimGame.last_night）和本局统计；静态台词不假装知道玩家做了什么，依赖状态的都放这里。
## 每个站点每夜最多反应一次（hub_view 记着），说完照常交谈 / 开店。


## 今晚的情况 → {条件名: 数}（没有今晚的数据就返回空：读档进来的夜宴、演示局）
static func context(g: SimGame) -> Dictionary:
	var L: Dictionary = g.last_night
	if L.is_empty() or bool(L.get("demo", false)) or not L.has("record0"):
		return {}
	var c: Dictionary = {}
	var new_ach: Array = Array(L.get("ach_new", PackedStringArray()))
	var gate: Dictionary = L.get("gate", {})
	var seals: int = int(gate.get("seals", 0))
	var best0: int = int(L.get("seals_best0", 0))
	c["seals"] = seals
	c["gate_hit"] = 1 if not gate.is_empty() else 0
	c["gate_first"] = 1 if new_ach.has("gate_first") else 0
	c["gate_record"] = 1 if best0 > 0 and seals > best0 else 0
	c["gate_all"] = 1 if seals > 0 and seals >= int(L.get("max_seals", 9)) else 0
	var blocked: String = str(L.get("blocked_by", ""))
	c["blocked"] = 1 if String(L.get("reason", "")) == "blocked" and blocked != "" else 0
	c["blocked_by"] = blocked
	var by: Dictionary = {}
	for t: Dictionary in L.get("tally", []):
		by[str(t.get("type", ""))] = int(by.get(str(t.get("type", "")), 0)) + int(t.get("n", 0))
	c["acropolis"] = int(by.get("acropolis", 0))
	c["temples"] = int(by.get("temple", 0)) + int(by.get("doric_temple", 0)) + int(by.get("olympian_temple", 0))
	c["chickens"] = int(by.get("chicken", 0))
	c["city_up"] = 1 if str(L.get("city_up", "")) != "" else 0
	c["city"] = str(L.get("city_up", ""))
	c["combo"] = int(L.get("max_combo", 0))
	var net: float = float(L.get("net", 0.0))
	c["net"] = net
	# 第 3 夜起才算"最好的一夜"（头两夜每晚都是新纪录）
	c["best_night"] = 1 if int(L.get("day", 0)) >= 3 and net > 0.0 and net >= float(g.run_stats.get("best_night", 0.0)) else 0
	c["jackpots"] = int(L.get("jackpots", 0))
	c["moira_first"] = 1 if new_ach.has("moira_first") else 0
	var bet: Dictionary = L.get("bet", {})
	c["bet_won"] = 1 if not bet.is_empty() and bool(bet.get("won", false)) else 0
	c["bet_lost"] = 1 if not bet.is_empty() and not bool(bet.get("won", false)) else 0
	c["gain"] = maxi(0, roundi(float(L.get("record", 0.0)) - float(L.get("record0", 0.0))))
	var t0: int = g.size_tier(float(L.get("start_r", 0.0)))
	var t1: int = g.size_tier(float(L.get("end_r", 0.0)))
	c["tier_up"] = 1 if t1 > t0 else 0
	c["tier"] = String(g.content.size_tiers[t1]["name"]) if t1 < g.content.size_tiers.size() else ""
	# 泰坦级（半径 ≥ 9 m，size_tiers.json 的「泰坦」「奥林匹斯」两档）；按门槛判断，不比名字（名字随语言变）
	c["titan"] = 1 if t1 > t0 and float(g.content.size_tiers[t1].get("min", 0.0)) >= 9.0 else 0
	c["summit"] = 1 if int(g.run_stats.get("summit_day", 0)) > 0 else 0
	return c


## 站点 id / 说话人 who 今晚第一条满足的反应：{i, text}；没有就返回空
static func pick(list: Array, id: String, who: String, ctx: Dictionary) -> Dictionary:
	if ctx.is_empty():
		return {}
	for i: int in list.size():
		var r: Dictionary = list[i]
		var w: String = str(r.get("who", ""))
		if w != id and w != who:
			continue
		if float(ctx.get(str(r.get("when", "")), 0)) >= float(r.get("ge", 1)):
			return {"i": i, "text": fill(str(r.get("text", "")), ctx)}
	return {}


## 台词里的 {名字} 换成今晚的数（钱按 NumFmt 写）
static func fill(text: String, ctx: Dictionary) -> String:
	var out: String = text
	for k: Variant in ctx:
		var v: Variant = ctx[k]
		var s: String = NumFmt.fmt(float(v)) if k == "net" else (str(int(v)) if v is int or v is float else str(v))
		out = out.replace("{%s}" % str(k), s)
	return out
