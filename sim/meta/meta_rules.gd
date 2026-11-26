class_name MetaRules
extends RefCounted
## 元进度规则（= 网页 meta.js applyMeta / updateSteles）：祖传节点（heirlooms.json 顺序）→ 石头 → 冥府契约（pacts.json 顺序）
## → day_length ≥ 20；先祖石碑（白天推过：几秒不耗体力；夜里滚过 + 先祖回响：本夜破封 +1）。
## meta 存档在 g.meta（字典，MetaLogic.normalize 过），本代设置在 g.run（stone / pacts / gen）。

var g: SimGame = null
var _stele_key: String = ""
var _stele_done: Dictionary = {}


func bind(p_g: SimGame) -> void:
	g = p_g


func _meta() -> Dictionary:
	return g.meta if not g.meta.is_empty() else MetaLogic.default_meta()


func apply_meta(st: Stats) -> void:
	var c: ContentDB = g.content
	var meta: Dictionary = _meta()
	var heir: Dictionary = meta.get("heir", {})
	var ls: Dictionary = MetaLogic.last_stele(meta)
	var env: Dictionary = {"day": float(g.day), "gen": float(g.run.get("gen", 1)), "last_stele_alt": float(ls.get("alt", 0.0))}
	for h: MetaDefs.Heirloom in c.heirlooms:
		if heir.has(String(h.id)):
			h.fx.apply(st, env)
	var sid: StringName = StringName(str(g.run.get("stone", "basic")))
	if not c.stone_by_id.has(sid) or not c.stone_on(sid):
		sid = &"basic"
	(c.stone_by_id[sid] as MetaDefs.Stone).fx.apply(st, {})
	st.stone = sid
	var pk: Dictionary = g.run.get("pacts", {})
	for p: MetaDefs.Pact in c.pacts:
		var lv: int = clampi(int(pk.get(String(p.id), 0)), 0, p.max_lv)
		if lv > 0 and c.pact_on(p.id):
			p.fx.apply(st, {"lv": float(lv)})
	st.day_length = maxf(20.0, st.day_length)


func stele_marks() -> Array:
	if g.demo:
		return []
	return MetaLogic.stele_marks(g.content, _meta())


## 白天推过石碑：5 秒（先祖回响 12 秒）不耗体力、节奏窗口放宽（g.buff.stele_t）；
## 夜里滚过石碑（先祖回响）：本夜破封 +1（g.buff.stele_seal）。计时器的递减在 SimGame.tick。
func update_steles(_dt: float) -> void:
	if g.demo or g.world == null:
		return
	var marks: Array = stele_marks()
	if marks.is_empty():
		return
	var h: Dictionary = _meta().get("heir", {})
	var b: Boulder = g.stone
	var day_phase: bool = g.phase == &"day"
	var key: String = "%d:%s" % [g.day, "d" if day_phase else "n"]
	if _stele_key != key:
		# 新的一天 / 一夜：开工时已经在石碑之上的不算
		_stele_key = key
		_stele_done = {}
		for m: Dictionary in marks:
			var s0: float = g.world.s_at_alt(float(m["alt"]))
			if (b.s + b.r * 0.8 >= s0) if day_phase else (b.s <= s0):
				_stele_done[int(m["gen"])] = true
		if not day_phase:
			g.buff["stele_seal"] = 0
	if day_phase:
		for m: Dictionary in marks:
			var gen: int = int(m["gen"])
			var s: float = g.world.s_at_alt(float(m["alt"]))
			if _stele_done.has(gen) or b.s + b.r * 0.8 < s:
				continue
			_stele_done[gen] = true
			var dur: float = 8.0 if h.has("hl_echo") else 5.0
			var cur: float = float(g.buff.get("stele_t", 0.0))
			g.buff["stele_t"] = minf(36.0, cur + dur) if h.has("hl_name") else maxf(cur, dur)
			g.world.at(s)
			g.fx.text(g.world.ax, g.world.ay + 4.4, Loc.t("meta_rules.ancestral_stele_seconds_without", "先祖的石碑 · %d 秒不耗体力") % roundi(float(g.buff["stele_t"])), 20.0, SimFx.GOLD_HI, 1.6)
			g.fx.sparks(g.world.ax, g.world.ay + 2.0, 14, 6.0)
			g.fx.sfx(&"sizeUp")
	elif g.phase == &"night" and h.has("hl_echo") and int(g.buff.get("stele_seal", 0)) == 0:
		for m: Dictionary in marks:
			var gen2: int = int(m["gen"])
			var s2: float = g.world.s_at_alt(float(m["alt"]))
			if _stele_done.has(gen2) or b.s > s2:
				continue
			_stele_done[gen2] = true
			g.buff["stele_seal"] = 1
			g.world.at(s2)
			g.fx.text(g.world.ax, g.world.ay + 5.0, Loc.t("meta_rules.ancestral_echo_1_seal", "先祖回响 · 今夜破封 +1"), 22.0, SimFx.GOLD_HI, 1.6)
			g.fx.sfx(&"sizeUp")
			break
