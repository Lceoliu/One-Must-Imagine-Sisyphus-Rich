class_name GodDef
extends RefCounted
## 八位主神（content/boons/gods.json 的 gods，= boon_data.js PATRONS）。数组顺序 = HUD 与同级取舍的顺序。
## faith_fx：集齐三阶后的主神信仰效果（无输入）；tuning：该神 RuleModule 用的可调常数（只读）。

const KEYS: PackedStringArray = ["id", "cn", "school", "br", "greek", "nemesis", "allies", "mech", "title", "roadblock", "mark", "grudge_line", "faith", "tuning"]

var id: StringName
var br: StringName
var greek: String
var nemesis: StringName
var allies: PackedStringArray = []
## 有机制模块（RuleModule）
var mech: bool
## 宿敌路障的物件 id
var roadblock: StringName
var faith_fx: EffectList
var tuning: Dictionary = {}
var _cn: String
var _school: String
var _title: String
var _mark: String
var _grudge: String
var _faith: Dictionary = {}

var cn: String:
	get:
		return Loc.t("god.%s.cn" % id, _cn)
var school: String:
	get:
		return Loc.t("god.%s.school" % id, _school)
var title: String:
	get:
		return Loc.t("god.%s.title" % id, _title)
var mark: String:
	get:
		return Loc.t("god.%s.mark" % id, _mark)
var grudge_line: String:
	get:
		return Loc.t("god.%s.grudge_line" % id, _grudge)


## 信仰文字：name hi lo line
func faith_text(k: String) -> String:
	return Loc.t("god.%s.faith.%s" % [id, k], str(_faith.get(k, "")))


static func from_dict(d: Dictionary, errors: PackedStringArray) -> GodDef:
	var o: GodDef = GodDef.new()
	var w: String = "boons/gods.json:%s" % d.get("id", "?")
	DefUtil.known(d, KEYS, w, errors)
	o.id = StringName(DefUtil.s(d, "id", w, errors))
	o._cn = DefUtil.s(d, "cn", w, errors)
	o._school = DefUtil.s(d, "school", w, errors)
	o.br = StringName(DefUtil.s(d, "br", w, errors))
	o.greek = DefUtil.s(d, "greek", w, errors)
	o.nemesis = StringName(DefUtil.s(d, "nemesis", w, errors))
	o.allies = DefUtil.strs(d, "allies", w, errors)
	o.mech = DefUtil.b(d, "mech", w, errors)
	o._title = DefUtil.s(d, "title", w, errors)
	o.roadblock = StringName(DefUtil.s(d, "roadblock", w, errors))
	o._mark = DefUtil.s(d, "mark", w, errors)
	o._grudge = DefUtil.s(d, "grudge_line", w, errors)
	var f: Dictionary = DefUtil.dict(d, "faith", w, errors, true)
	DefUtil.known(f, ["name", "hi", "lo", "line", "fx"], w + ".faith", errors)
	for k: String in ["name", "hi", "lo", "line"]:
		o._faith[k] = DefUtil.s(f, k, w + ".faith", errors)
	o.faith_fx = EffectList.compile(f.get("fx", []), [], w + ".faith.fx", errors)
	o.tuning = DefUtil.dict(d, "tuning", w, errors)
	return o
