class_name NodeDef
extends RefCounted
## 天赋节点（content/shop/nodes.json，= upgrades.js NODES）。fx 的输入是 lv。
## 价格算法（baseCost / priceMult）在 sim/rules/pricing.gd（F2），常数在 tuning.json。

const INPUTS: PackedStringArray = ["lv"]
const KEYS: PackedStringArray = ["key", "br", "depth", "name", "max", "cost", "grow", "costs", "cost2", "cur", "public_max", "hidden", "q", "unlock_by", "unlock_n", "line", "desc", "fx"]

var key: StringName
var br: StringName
var depth: int
var max_lv: int
## 首级价格（costs 为空时用）
var cost: float
## 每级价格倍率（缺省 1；再加 tuning.grow_add）
var grow: float = 1.0
## 每级绝对价（隐藏的新节点、命运节点）；非空时忽略 cost / grow
var costs: PackedFloat64Array = []
## 用什么钱买：&"" = 德拉克马；&"moira" = 命运（三女神的店，价格是 costs）
var cur: StringName = &""
## 两种货币一起付的节点：每级另付的命运（不够级数时用最后一个）；空 = 只要德拉克马
var cost2: PackedFloat64Array = []
## 没有对应神的赐福时能买到的最高级（-1 = 无此限制）
var public_max: int = -1
var hidden: bool
var q: bool
var unlock_by: StringName
var unlock_n: int
var fx: EffectList
var _name_src: String
var _line_src: String
var _desc_src: String

var name: String:
	get:
		return Loc.t("node.%s.name" % key, _name_src)
var line: String:
	get:
		return Loc.t("node.%s.line" % key, _line_src) if _line_src != "" else ""
var desc: String:
	get:
		return Loc.t("node.%s.desc" % key, _desc_src)


static func from_dict(d: Dictionary, errors: PackedStringArray) -> NodeDef:
	var o: NodeDef = NodeDef.new()
	var w: String = "shop/nodes.json:%s" % d.get("key", "?")
	DefUtil.known(d, KEYS, w, errors)
	o.key = StringName(DefUtil.s(d, "key", w, errors))
	o.br = StringName(DefUtil.s(d, "br", w, errors))
	o.depth = DefUtil.i(d, "depth", w, errors)
	o._name_src = DefUtil.s(d, "name", w, errors)
	o.max_lv = DefUtil.i(d, "max", w, errors)
	if d.has("costs"):
		o.costs = DefUtil.nums(d, "costs", w, errors)
	else:
		o.cost = DefUtil.n(d, "cost", w, errors)
		o.grow = DefUtil.n(d, "grow", w, errors, false, 1.0)
	o.cur = StringName(DefUtil.s(d, "cur", w, errors, false))
	if o.cur != &"" and o.cur != &"moira":
		errors.append("%s：cur 只能是 moira（或不写 = 德拉克马）" % w)
	if o.cur == &"moira" and o.costs.is_empty():
		errors.append("%s：命运节点要写 costs" % w)
	if d.has("cost2"):
		o.cost2 = DefUtil.nums(d, "cost2", w, errors)
	o.public_max = DefUtil.i(d, "public_max", w, errors, false, -1)
	o.hidden = DefUtil.b(d, "hidden", w, errors)
	o.q = DefUtil.b(d, "q", w, errors)
	o.unlock_by = StringName(DefUtil.s(d, "unlock_by", w, errors, false))
	o.unlock_n = DefUtil.i(d, "unlock_n", w, errors, false)
	o._line_src = DefUtil.s(d, "line", w, errors, false)
	o._desc_src = DefUtil.s(d, "desc", w, errors)
	o.fx = EffectList.compile(d.get("fx", []), INPUTS, w + ".fx", errors)
	return o
