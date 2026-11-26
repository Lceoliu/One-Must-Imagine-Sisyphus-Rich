class_name Achievements
extends RefCounted
## 成就（content/meta/achievements.json；docs/v06/incremental.md 第 11 节）。纯规则：
## context() 把本局统计 run_stats 和几项派生的数拼成一张表，check() 每夜结算、登顶时调用，新解锁的记进 run_stats.ach 并弹提示；
## 一代结束时 MetaLogic.on_run_end 把本局的并进 meta.ach。已经在 meta.ach 里的不再弹。以后接 Steam 时在这里多发一次。


## 判定用的数（缺的给 0）
static func context(g: SimGame) -> Dictionary:
	var rs: Dictionary = g.run_stats
	var d: Dictionary = {}
	for k: String in ["crushed", "buildings", "chickens", "living", "pushes", "best_night", "max_r", "max_seals", "moira_total", "jars",
			"jackpots", "bets", "bets_won", "bet_best_odds", "altars"]:
		d[k] = float(rs.get(k, 0))
	var sd: int = int(rs.get("summit_day", 0))
	var summit: bool = sd > 0 or g.record >= World.SUMMIT
	d["summit"] = 1.0 if summit else 0.0
	d["fast_summit"] = 1.0 if sd > 0 and sd <= 15 else 0.0
	d["city"] = float(g.city_level)
	d["gen"] = float(g.run.get("gen", 1))
	d["day"] = float(g.day)
	var heat: int = MetaLogic.heat_of(g.content, g.run.get("pacts", {}))
	d["heat_summit"] = float(heat) if summit else 0.0
	d["ending_sunrise"] = 0.0
	var fates: bool = true
	var dual: bool = false
	var wines: int = 0
	for n: NodeDef in g.content.nodes:
		var lv: int = int(g.levels.get(String(n.key), 0))
		if n.cur == &"moira" and lv < n.max_lv:
			fates = false
		if not n.cost2.is_empty() and lv > 0:
			dual = true
		if n.br == &"wine" and lv > 0:
			wines += 1
	d["fates_done"] = 1.0 if fates else 0.0
	d["dual_any"] = 1.0 if dual else 0.0
	d["wine_all"] = 1.0 if wines >= 3 else 0.0
	return d


## 已经解锁过的（以前各代 + 本局）
static func unlocked(g: SimGame) -> Dictionary:
	var out: Dictionary = (g.meta.get("ach", {}) as Dictionary).duplicate()
	for id: Variant in g.run_stats.get("ach", []):
		out[str(id)] = true
	return out


## 检查一遍；返回新解锁的 id
static func check(g: SimGame, extra: Dictionary = {}) -> PackedStringArray:
	var out: PackedStringArray = []
	if g.demo:
		return out
	var ctx: Dictionary = context(g)
	ctx.merge(extra, true)
	var have: Dictionary = unlocked(g)
	var lst: Array = g.run_stats.get("ach", [])
	for a: Dictionary in g.content.achievements:
		var id: String = str(a["id"])
		if have.has(id):
			continue
		if float(ctx.get(str(a["k"]), 0.0)) >= float(a["ge"]):
			lst.append(id)
			out.append(id)
			g.fx.toast(Loc.t("achievements.achievement", "成就 ·「%s」：%s") % [str(a["name"]), str(a["desc"])], 3.6, SimFx.GOLD_HI)
			g.fx.event(&"achievement", {"id": id})
	g.run_stats["ach"] = lst
	return out
