class_name BandDef
extends RefCounted
## 海拔带（content/world/bands.json，= world.js layout 里内联的 bands 表）。
## 权重 = w（数字或表达式，输入 potters pasture domino day alt）× new_w；min_day / min_alt 不满足时不参与抽取。
## 物件名以 @ 开头的是成群出现（@sheep @goat @horse @hoplite @column），数量与间距是 layout 的机制（F2 逐行移植）。
## fill（可选，2026-10-16）：两件主物件之间的空当里按概率 p 撒 n = [下限, 上限] 件小物件（items 里按 w 抽，只认数字权重），
##   让高处每夜不那么固定；用 World.layout 里单独的随机流，主物件的序列和网页一致。

const INPUTS: PackedStringArray = ["potters", "pasture", "domino", "day", "alt"]
const KEYS: PackedStringArray = ["top", "gap", "items", "fill"]
const FILL_KEYS: PackedStringArray = ["p", "n", "items", "margin"]
const ITEM_KEYS: PackedStringArray = ["type", "w", "new_w", "min_day", "min_alt"]

var top: float
var gap_lo: float
var gap_hi: float
var types: PackedStringArray = []
## 每项的权重：float 或 Expr
var weights: Array = []
var new_w: PackedFloat64Array = []
## 没有限制时为 -INF
var min_day: PackedFloat64Array = []
var min_alt: PackedFloat64Array = []
## 空当里撒的小物件（没有 fill 时 fill_p = 0）。fill_p：数字或表达式（输入同 INPUTS，如 "0.15 * pasture"）
var fill_p: Variant = 0.0
## 空当两头各留多少米（低坡的空当窄，留得少）
var fill_margin: float = 1.5
var fill_lo: int = 0
var fill_hi: int = 0
var fill_types: PackedStringArray = []
var fill_w: PackedFloat64Array = []


static func from_dict(d: Dictionary, idx: int, errors: PackedStringArray) -> BandDef:
	var b: BandDef = BandDef.new()
	var w: String = "world/bands.json[%d]" % idx
	DefUtil.known(d, KEYS, w, errors)
	b.top = DefUtil.n(d, "top", w, errors)
	var gap: PackedFloat64Array = DefUtil.nums(d, "gap", w, errors)
	if gap.size() != 2:
		errors.append("%s：gap 必须是 [下限, 上限]" % w)
	else:
		b.gap_lo = gap[0]
		b.gap_hi = gap[1]
	var items: Variant = d.get("items", [])
	if not (items is Array):
		errors.append("%s：items 应为数组" % w)
		return b
	var k: int = 0
	for it: Variant in items:
		var wi: String = "%s.items[%d]" % [w, k]
		k += 1
		if not (it is Dictionary):
			errors.append("%s：应为对象" % wi)
			continue
		var di: Dictionary = it
		DefUtil.known(di, ITEM_KEYS, wi, errors)
		b.types.append(DefUtil.s(di, "type", wi, errors))
		b.weights.append(Expr.value_or_expr(di.get("w", 0.0), INPUTS, wi + ".w", errors))
		b.new_w.append(DefUtil.n(di, "new_w", wi, errors, false, 1.0))
		b.min_day.append(DefUtil.n(di, "min_day", wi, errors, false, -INF))
		b.min_alt.append(DefUtil.n(di, "min_alt", wi, errors, false, -INF))
	var fv: Variant = d.get("fill", null)
	if fv is Dictionary:
		var fd: Dictionary = fv
		var wf: String = w + ".fill"
		DefUtil.known(fd, FILL_KEYS, wf, errors)
		b.fill_p = Expr.value_or_expr(fd.get("p", 0.0), INPUTS, wf + ".p", errors)
		b.fill_margin = DefUtil.n(fd, "margin", wf, errors, false, 1.5)
		var nn: PackedFloat64Array = DefUtil.nums(fd, "n", wf, errors)
		if nn.size() != 2:
			errors.append("%s：n 必须是 [下限, 上限]" % wf)
		else:
			b.fill_lo = int(nn[0])
			b.fill_hi = int(nn[1])
		var j: int = 0
		for it: Variant in fd.get("items", []):
			var wi2: String = "%s.items[%d]" % [wf, j]
			j += 1
			if not (it is Dictionary):
				errors.append("%s：应为对象" % wi2)
				continue
			DefUtil.known(it, PackedStringArray(["type", "w"]), wi2, errors)
			b.fill_types.append(DefUtil.s(it, "type", wi2, errors))
			b.fill_w.append(DefUtil.n(it, "w", wi2, errors))
	elif fv != null:
		errors.append("%s：fill 应为对象" % w)
	return b


## 这一段空当撒小物件的概率（inputs 同 weight）
func fill_prob(inputs: Dictionary) -> float:
	return Expr.to_num(Expr.resolve(fill_p, inputs))


## 空当里撒的小物件：按权重抽一种（r ∈ [0, 1)）
func fill_pick(r: float) -> String:
	var tot: float = 0.0
	for x: float in fill_w:
		tot += x
	var acc: float = r * tot
	for i: int in fill_types.size():
		acc -= fill_w[i]
		if acc <= 0.0:
			return fill_types[i]
	return fill_types[fill_types.size() - 1]


## 第 i 项的权重（= world.js：先算 it[1]，再 *= NEW_W）。inputs：potters pasture domino day alt。
func weight(i: int, inputs: Dictionary) -> float:
	return Expr.to_num(Expr.resolve(weights[i], inputs)) * new_w[i]


## 第 i 项在给定天数、海拔下是否可抽（world.js:199 的 minAlt / minDay 过滤，不含权重 > 0 与物件存在的判断）。
func allowed(i: int, day: float, alt: float) -> bool:
	return not (min_alt[i] > alt or min_day[i] > day)
