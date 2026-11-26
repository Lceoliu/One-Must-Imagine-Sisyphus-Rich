class_name MetaDefs
## 元进度的三张表（content/meta/{heirlooms,pacts,stones}.json，= meta.js HEIRLOOMS / PACTS / STONES）。
## 三个定义类都很小，放在一个文件里作内部类：MetaDefs.Heirloom / MetaDefs.Pact / MetaDefs.Stone。
## 套用顺序（MetaRules.apply_meta，S）：祖传按 heirlooms.json 顺序 → 石头 → 契约按 pacts.json 顺序 → day_length = max(20, …)。

## 祖传 fx 的输入（last_stele_alt：上一代石碑海拔，没有时 0）
const HEIR_INPUTS: PackedStringArray = ["day", "gen", "last_stele_alt"]
const PACT_INPUTS: PackedStringArray = ["lv"]


class Heirloom:
	extends RefCounted
	const KEYS: PackedStringArray = ["id", "name", "cost", "req", "row", "col", "icon", "desc", "fx"]
	var id: StringName
	var cost: float
	var req: PackedStringArray = []
	## 血脉界面的排布：第 row 层第 col 个
	var row: int
	var col: int
	var icon: StringName
	var fx: EffectList
	var _name_src: String
	var _desc_src: String
	var name: String:
		get:
			return Loc.t("heirloom.%s.name" % id, _name_src)
	var desc: String:
		get:
			return Loc.t("heirloom.%s.desc" % id, _desc_src)

	static func from_dict(d: Dictionary, errors: PackedStringArray) -> Heirloom:
		var o: Heirloom = Heirloom.new()
		var w: String = "meta/heirlooms.json:%s" % d.get("id", "?")
		DefUtil.known(d, KEYS, w, errors)
		o.id = StringName(DefUtil.s(d, "id", w, errors))
		o._name_src = DefUtil.s(d, "name", w, errors)
		o.cost = DefUtil.n(d, "cost", w, errors)
		o.req = DefUtil.strs(d, "req", w, errors)
		o.row = DefUtil.i(d, "row", w, errors)
		o.col = DefUtil.i(d, "col", w, errors)
		o.icon = StringName(DefUtil.s(d, "icon", w, errors))
		o._desc_src = DefUtil.s(d, "desc", w, errors)
		o.fx = EffectList.compile(d.get("fx", []), HEIR_INPUTS, w + ".fx", errors)
		return o


class Pact:
	extends RefCounted
	const KEYS: PackedStringArray = ["id", "name", "max", "txt", "comp", "fx"]
	var id: StringName
	var max_lv: int
	var fx: EffectList
	var _name_src: String
	var _txt: PackedStringArray = []
	var _comp: PackedStringArray = []
	var name: String:
		get:
			return Loc.t("pact.%s.name" % id, _name_src)

	## 第 lv 级（从 1 开始）的条款 / 补偿文字
	func txt(lv: int) -> String:
		return Loc.t("pact.%s.txt#%d" % [id, lv - 1], _txt[lv - 1]) if lv >= 1 and lv <= _txt.size() else ""

	func comp(lv: int) -> String:
		return Loc.t("pact.%s.comp#%d" % [id, lv - 1], _comp[lv - 1]) if lv >= 1 and lv <= _comp.size() else ""

	static func from_dict(d: Dictionary, errors: PackedStringArray) -> Pact:
		var o: Pact = Pact.new()
		var w: String = "meta/pacts.json:%s" % d.get("id", "?")
		DefUtil.known(d, KEYS, w, errors)
		o.id = StringName(DefUtil.s(d, "id", w, errors))
		o._name_src = DefUtil.s(d, "name", w, errors)
		o.max_lv = DefUtil.i(d, "max", w, errors)
		o._txt = DefUtil.strs(d, "txt", w, errors)
		o._comp = DefUtil.strs(d, "comp", w, errors)
		if o._txt.size() != o.max_lv or o._comp.size() != o.max_lv:
			errors.append("%s：txt / comp 的条数必须等于 max" % w)
		o.fx = EffectList.compile(d.get("fx", []), PACT_INPUTS, w + ".fx", errors)
		return o


class Stone:
	extends RefCounted
	const KEYS: PackedStringArray = ["id", "name", "sprite", "mech", "day", "unlock", "fx"]
	var id: StringName
	## 空 = 用默认石头精灵
	var sprite: StringName
	var fx: EffectList
	var _src: Dictionary = {}

	## 文字：name mech day unlock
	func text(k: String) -> String:
		return Loc.t("stone.%s.%s" % [id, k], str(_src.get(k, "")))

	static func from_dict(d: Dictionary, errors: PackedStringArray) -> Stone:
		var o: Stone = Stone.new()
		var w: String = "meta/stones.json:%s" % d.get("id", "?")
		DefUtil.known(d, KEYS, w, errors)
		o.id = StringName(DefUtil.s(d, "id", w, errors))
		o.sprite = StringName(DefUtil.s(d, "sprite", w, errors, false))
		for k: String in ["name", "mech", "day", "unlock"]:
			o._src[k] = DefUtil.s(d, k, w, errors)
		o.fx = EffectList.compile(d.get("fx", []), [], w + ".fx", errors)
		return o
