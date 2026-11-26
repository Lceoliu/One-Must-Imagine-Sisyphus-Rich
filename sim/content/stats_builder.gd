class_name StatsBuilder
extends RefCounted
## 一天的 stats 构建（architecture §5.1）。顺序写死在代码里，与网页 game.js:154 startDay 一致：
##   Stats.new()（默认值）
##   → nodes：按 shop/nodes.json 的顺序，对 lv > 0 的节点执行 fx（输入 lv）                         [F1，本文件]
##   → g.meta_rules.apply_meta(st)：祖传 → 石头 → 契约 → day_length = max(20, …)                 [S]
##   → g.boons.apply_stats(st)：CARD_NEUTRAL 归位 → 按 taken 执行卡 fx(k) → 信仰 → 怨气/折扣/解封 → 醉汉 [B]
##   → g.story.apply_stats(st)：story.json 的 passives（条件 = flags 表达式）                      [T]
## 后三步是"调用点"：build(g) 按名字调用 g 上的系统对象（F2 先放中性桩，S / B / T 填实现）。
## 本文件不引用 SimGame 类型（sim/content 在 sim/core 之前建成），所以用 Object 动态调用。


## 只做 nodes 这一步：默认值 + 各节点 fx。levels：节点 key（String 或 StringName）→ 等级。
static func build_nodes(content: ContentDB, levels: Dictionary) -> Stats:
	var st: Stats = Stats.new()
	apply_nodes(st, content, levels)
	return st


static func apply_nodes(st: Stats, content: ContentDB, levels: Dictionary) -> void:
	for n: NodeDef in content.nodes:
		var lv: int = int(levels.get(String(n.key), levels.get(n.key, 0)))
		if lv > 0:
			n.fx.apply(st, {"lv": float(lv)})


## 完整构建（= game.js startDay 的 4 步）。g 需要有 content: ContentDB、run.levels: Dictionary，
## 以及 meta_rules / boons / story 三个系统对象（各有 apply_meta(st) / apply_stats(st) / apply_stats(st)；缺了就跳过那一步）。
static func build(g: Object) -> Stats:
	var content: ContentDB = g.get(&"content")
	var run: Object = g.get(&"run")
	var levels: Dictionary = run.get(&"levels") if run != null else {}
	var st: Stats = build_nodes(content, levels)
	_step(g, &"meta_rules", &"apply_meta", st)
	_step(g, &"boons", &"apply_stats", st)
	_step(g, &"story", &"apply_stats", st)
	return st


static func _step(g: Object, system: StringName, method: StringName, st: Stats) -> void:
	var sys: Variant = g.get(system)
	if sys is Object and (sys as Object).has_method(method):
		(sys as Object).call(method, st)
