class_name CardDef
extends RefCounted
## 赐福卡（content/boons/cards.json，= boon_data.js BOONS）：I/II/III 阶卡、双神联动（duo）、金苹果仲裁（arb）。
## fx 的输入是 k（仲裁后 I 阶 ×1.5，否则 1）。卡面 hi / lo 是文本节点；铜轨跳台这种随状态变化的卡面，
## 由 text_hook 指定的模块提供 text_inputs 里的输入（card_text 钩子，见 tools/port/out/manual.md）。

const INPUTS: PackedStringArray = ["k"]
const KEYS: PackedStringArray = ["id", "god", "god2", "gods", "rank", "name", "hi", "lo", "line", "fx", "text_hook", "text_inputs"]

var id: StringName
var god: StringName
var god2: StringName
## 联动 / 仲裁涉及的两位神
var gods: PackedStringArray = []
## &"rank"（阶卡）/ &"duo"（双神联动）/ &"arb"（金苹果仲裁）
var kind: StringName
## 阶卡的阶数 1–3；联动 / 仲裁为 0
var rank: int
var hi: TextTpl
var lo: TextTpl
var fx: EffectList
var text_hook: StringName
var text_inputs: PackedStringArray = []
var _name_src: String
var _line_src: String

var name: String:
	get:
		return Loc.t("card.%s.name" % id, _name_src)
var line: String:
	get:
		return Loc.t("card.%s.line" % id, _line_src)


static func from_dict(d: Dictionary, errors: PackedStringArray) -> CardDef:
	var o: CardDef = CardDef.new()
	var w: String = "boons/cards.json:%s" % d.get("id", "?")
	DefUtil.known(d, KEYS, w, errors)
	o.id = StringName(DefUtil.s(d, "id", w, errors))
	o.god = StringName(DefUtil.s(d, "god", w, errors))
	o.god2 = StringName(DefUtil.s(d, "god2", w, errors, false))
	o.gods = DefUtil.strs(d, "gods", w, errors, false)
	var r: Variant = d.get("rank")
	if typeof(r) == TYPE_FLOAT or typeof(r) == TYPE_INT:
		o.kind = &"rank"
		o.rank = int(r)
		if o.rank < 1 or o.rank > 3:
			errors.append("%s：rank 只能是 1 / 2 / 3 / \"duo\" / \"arb\"" % w)
	elif r == "duo" or r == "arb":
		o.kind = StringName(str(r))
		if o.gods.size() != 2:
			errors.append("%s：%s 卡必须有两位神（gods）" % [w, r])
	else:
		errors.append("%s：rank 只能是 1 / 2 / 3 / \"duo\" / \"arb\"" % w)
	o._name_src = DefUtil.s(d, "name", w, errors)
	o._line_src = DefUtil.s(d, "line", w, errors)
	o.text_hook = StringName(DefUtil.s(d, "text_hook", w, errors, false))
	o.text_inputs = DefUtil.strs(d, "text_inputs", w, errors, false)
	o.hi = TextTpl.compile(d.get("hi", ""), o.text_inputs, "card.%s.hi" % o.id, w + ".hi", errors)
	o.lo = TextTpl.compile(d.get("lo", ""), o.text_inputs, "card.%s.lo" % o.id, w + ".lo", errors)
	o.fx = EffectList.compile(d.get("fx", []), INPUTS, w + ".fx", errors)
	return o


func is_rank() -> bool:
	return kind == &"rank"
