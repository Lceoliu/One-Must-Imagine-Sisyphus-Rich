class_name Pricing
extends RefCounted
## 各摊的价格、解锁与完成度（= upgrades.js baseCost / priceMult / nodeCost / isUnlocked / maxLevel / nodeState /
## canLevel / visibleProgress）。st 可为 null（= 原价、不看解封）。golden：tests/golden/v04/price_cases.json。
## 两种钱（docs/v06/incremental.md 第 6 节）：德拉克马（node_cost）和命运（moira_cost）。三女神的节点（cur = moira）只收命运；
## 各摊最下面的质变节点（cost2 非空）两种一起付。命运价格不吃折扣 / 加价。


static func base_cost(content: ContentDB, n: NodeDef, lv: int) -> float:
	var t: Tuning = content.tuning
	if not n.costs.is_empty():
		return n.costs[mini(lv, n.costs.size() - 1)]
	return Js.round(n.cost * t.cost_mult * t.depth_mult[n.depth] * pow(n.grow + t.grow_add, float(lv)))


static func _cl(v: float, a: float, b: float) -> float:
	return maxf(a, minf(b, v))


## 价格系数：公开节点 Π(1 − 折扣) × Π(1 + 加价)；隐藏节点只吃 shop_disc / shop_tax；不低于 0.2
static func price_mult(content: ContentDB, n: NodeDef, st: Stats) -> float:
	if st == null:
		return 1.0
	var t: Tuning = content.tuning
	var m: float = (1.0 - _cl(st.shop_disc, 0.0, 0.5)) * (1.0 + _cl(st.shop_tax, 0.0, 3.0))
	if not n.hidden:
		var disc: float = _cl(float(st.branch_disc.get(String(n.br), 0.0)), 0.0, t.disc_cap)
		var tax: float = _cl(float(st.branch_tax.get(String(n.br), 0.0)), 0.0, t.tax_cap)
		m *= (1.0 - disc) * (1.0 + tax) * (1.0 - _cl(float(st.node_disc.get(String(n.key), 0.0)), 0.0, 0.6)) * (1.0 + _cl(float(st.node_tax.get(String(n.key), 0.0)), 0.0, 3.0))
	return maxf(0.2, m)


## 德拉克马价格（命运节点 = 0）
static func node_cost(content: ContentDB, n: NodeDef, lv: int, st: Stats) -> float:
	if n.cur == &"moira":
		return 0.0
	var base: float = base_cost(content, n, lv)
	if st == null:
		return base
	return maxf(1.0, Js.round(base * price_mult(content, n, st)))


## 命运价格（只要德拉克马的节点 = 0）
static func moira_cost(n: NodeDef, lv: int) -> float:
	if n.cur == &"moira":
		return n.costs[mini(lv, n.costs.size() - 1)] if not n.costs.is_empty() else 0.0
	if not n.cost2.is_empty():
		return n.cost2[mini(lv, n.cost2.size() - 1)]
	return 0.0


## 两种钱都够
static func affordable(content: ContentDB, n: NodeDef, lv: int, st: Stats, money: float, moira: float) -> bool:
	return node_cost(content, n, lv, st) <= money and moira_cost(n, lv) <= moira


static func is_seal_open(n: NodeDef, st: Stats) -> bool:
	return n.hidden and st != null and bool(st.unlocked_nodes.get(String(n.key), false))


## 公开节点：同支里前一个公开节点（按 depth）至少 1 级；隐藏节点：已解封
static func is_unlocked(content: ContentDB, n: NodeDef, levels: Dictionary, st: Stats) -> bool:
	if n.hidden:
		return is_seal_open(n, st)
	var prev: NodeDef = null
	for m: NodeDef in content.nodes:
		if m.br == n.br and not m.hidden and m.depth < n.depth and (prev == null or m.depth > prev.depth):
			prev = m
	return prev == null or int(levels.get(String(prev.key), 0)) > 0


static func max_level(n: NodeDef, st: Stats) -> int:
	if n.public_max >= 0:
		return n.max_lv if st != null and bool(st.unlocked_nodes.get(String(n.key) + "+", false)) else n.public_max
	return n.max_lv


## 'public' 公开 | 'sealed' 封印 | 'open' 已解封 | 'legacy' 旧约
static func node_state(n: NodeDef, levels: Dictionary, st: Stats) -> StringName:
	if not n.hidden:
		return &"public"
	if is_seal_open(n, st):
		return &"open"
	return &"legacy" if int(levels.get(String(n.key), 0)) > 0 else &"sealed"


static func can_level(content: ContentDB, n: NodeDef, levels: Dictionary, st: Stats) -> bool:
	return is_unlocked(content, n, levels, st) and int(levels.get(String(n.key), 0)) < max_level(n, st)


## 完成度：只算公开的德拉克马节点（三女神的不算），一指推按公开上限算
static func visible_progress(content: ContentDB, levels: Dictionary) -> Dictionary:
	var done: int = 0
	var total: int = 0
	for n: NodeDef in content.nodes:
		if n.hidden or n.cur == &"moira":
			continue
		var cap: int = n.public_max if n.public_max >= 0 else n.max_lv
		total += cap
		done += mini(cap, int(levels.get(String(n.key), 0)))
	return {"done": done, "total": total, "pct": float(done) / total if total > 0 else 0.0}


## 买一级（商店与机器人共用）：两种钱都够且能升级时扣钱、加等级，返回是否成功
static func buy(g: SimGame, n: NodeDef) -> bool:
	var lv: int = int(g.levels.get(String(n.key), 0))
	if not can_level(g.content, n, g.levels, g.stats):
		return false
	var c: float = node_cost(g.content, n, lv, g.stats)
	var c2: float = moira_cost(n, lv)
	if g.money < c or g.moira < c2:
		return false
	g.money -= c
	g.moira -= c2
	g.levels[String(n.key)] = lv + 1
	return true
