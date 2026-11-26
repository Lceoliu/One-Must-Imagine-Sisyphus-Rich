class_name StoryDefs
## 剧情的小表（content/story/{story,summit,endings}.json）：StoryDefs.Passive / StoryDefs.Summit / StoryDefs.Ending。
## 条件表达式的输入（architecture §5.3）：day money cash record alt tod gen f（f = flags 字典，用 f.chain 读）。
## 事件图（story/events/*.json）见 sim/content/dialog_graph.gd，由 T 编写。

const INPUTS: PackedStringArray = ["day", "money", "cash", "record", "alt", "tod", "gen", "f"]


## 信物等被动效果：条件满足时执行 fx（story.json passives，= story.js applyStats / _fx）
class Passive:
	extends RefCounted
	var id: StringName
	var cond: Expr
	var fx: EffectList

	static func from_dict(d: Dictionary, idx: int, errors: PackedStringArray) -> Passive:
		var o: Passive = Passive.new()
		var w: String = "story/story.json:passives[%d]" % idx
		DefUtil.known(d, ["id", "if", "fx"], w, errors)
		o.id = StringName(DefUtil.s(d, "id", w, errors))
		o.cond = Expr.compile(DefUtil.s(d, "if", w, errors), INPUTS, w + ".if", errors)
		o.fx = EffectList.compile(d.get("fx", []), [], w + ".fx", errors)
		return o

	## 条件为真时执行；inputs 是剧情条件输入（至少要有 f）。
	func apply(st: Stats, inputs: Dictionary) -> bool:
		if cond != null and cond.eval_bool(inputs):
			fx.apply(st, {})
			return true
		return false


## 登顶菜单的一项（summit.json，顺序即显示顺序；if 为空 = 总是出现）
class Summit:
	extends RefCounted
	var id: StringName
	var kind: StringName
	var gold: bool
	var cond: Expr = null
	var _label: String
	var label: String:
		get:
			return Loc.t("summit.%s.label" % id, _label)

	static func from_dict(d: Dictionary, errors: PackedStringArray) -> Summit:
		var o: Summit = Summit.new()
		var w: String = "story/summit.json:%s" % d.get("id", "?")
		DefUtil.known(d, ["id", "label", "kind", "gold", "if"], w, errors)
		o.id = StringName(DefUtil.s(d, "id", w, errors))
		o._label = DefUtil.s(d, "label", w, errors)
		o.kind = StringName(DefUtil.s(d, "kind", w, errors))
		o.gold = DefUtil.b(d, "gold", w, errors)
		if d.has("if"):
			o.cond = Expr.compile(DefUtil.s(d, "if", w, errors), INPUTS, w + ".if", errors)
		return o

	func available(inputs: Dictionary) -> bool:
		return cond == null or cond.eval_bool(inputs)


## 结局元数据（endings.json，= endings.js ENDINGS + CREDITS + CUES）。画面在 present/endings（T）。
class Ending:
	extends RefCounted
	const KEYS: PackedStringArray = ["id", "name", "kind", "dur", "reveal", "text", "reveal_text", "comp", "aside", "spared", "credits", "cues"]
	const KINDS: PackedStringArray = ["normal", "true", "fake", "normal-bad"]
	var id: StringName
	var kind: StringName
	var dur: float
	## 假结局的揭示时长（0 = 没有揭示）
	var reveal: float
	var credits: PackedStringArray = []
	## [{t: float, sfx: StringName, args: Array}]，按 t 升序
	var cues: Array[Dictionary] = []
	var _src: Dictionary = {}

	## 文字：name text reveal_text comp aside spared
	func text(k: String) -> String:
		return Loc.t("ending.%s.%s" % [id, k], str(_src.get(k, ""))) if _src.has(k) else ""

	static func from_dict(d: Dictionary, errors: PackedStringArray) -> Ending:
		var o: Ending = Ending.new()
		var w: String = "story/endings.json:%s" % d.get("id", "?")
		DefUtil.known(d, KEYS, w, errors)
		o.id = StringName(DefUtil.s(d, "id", w, errors))
		o.kind = StringName(DefUtil.s(d, "kind", w, errors))
		if not KINDS.has(String(o.kind)):
			errors.append("%s：kind 只能是 %s" % [w, ", ".join(KINDS)])
		o.dur = DefUtil.n(d, "dur", w, errors)
		o.reveal = DefUtil.n(d, "reveal", w, errors, false)
		for k: String in ["name", "text", "reveal_text", "comp", "aside", "spared"]:
			if d.has(k):
				o._src[k] = DefUtil.s(d, k, w, errors)
		o.credits = DefUtil.strs(d, "credits", w, errors, false)
		var cues: Variant = d.get("cues", [])
		if cues is Array:
			for c: Variant in cues:
				if not (c is Dictionary):
					errors.append("%s：cues 的元素应为对象" % w)
					continue
				var cd: Dictionary = c
				DefUtil.known(cd, ["t", "sfx", "args"], w + ".cues", errors)
				o.cues.append({"t": DefUtil.n(cd, "t", w + ".cues", errors), "sfx": StringName(DefUtil.s(cd, "sfx", w + ".cues", errors)), "args": cd.get("args", [])})
		return o
