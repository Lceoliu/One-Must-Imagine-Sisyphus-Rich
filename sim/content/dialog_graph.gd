class_name DialogGraph
extends RefCounted
## 剧情事件图（content/story/events/*.json，格式照 arch-data §4.2；由 T 人工改写 story.js 的对话树）。
## 本文件只做数据结构、预编译和校验；推进逻辑（每个节点生成一个 DIALOG 模态、ANSWER 推进）在 sim/story/dialog_runner.gd（T）。
##
## 结构：{id, trigger:{kind, …}, start, locals?:[名], nodes:{名: 节点}}
## 节点字段：
##   say          [台词]：字符串 = 当前说话人；{"who": 说话人 id 或 ""（系统提示）, "text": …}
##   choices      [{text, if?, gold?, goto? | end?, set?:{局部变量: 表达式}}]；if 不满足的不显示
##   if_no_choice 所有选项都不满足时跳到的节点
##   branch       [{if?, goto}]：取第一个满足的
##   do           [[动作, 参数…]]：动作词表固定（ACTIONS）
##   goto / end   下一个节点 / 结束
##   who          本节点台词的默认说话人（story.json speakers 的 id；"" = 系统提示）
## 条件与文本可用的名字：剧情输入（day money cash record alt tod gen f）+ story.json 的 consts + 本图的局部变量。

const ACTIONS: PackedStringArray = ["set", "add", "money", "banner", "sfx", "save", "narr", "queue", "play_ending", "refresh_stats", "call"]
const NODE_KEYS: PackedStringArray = ["say", "choices", "if_no_choice", "branch", "do", "goto", "end", "who"]

var id: StringName
var file: String
var trigger: Dictionary = {}
var start: StringName
var locals: PackedStringArray = []
## 名字 → 编译后的节点 Dictionary：
##   say: Array[{who: String（null = 当前说话人）, text: TextTpl}]
##   choices: Array[{text: TextTpl, cond: Expr|null, gold: bool, goto: StringName, end: bool, set: {名: Expr}}]
##   if_no_choice / goto: StringName；end: bool；who: String
##   branch: Array[{cond: Expr|null, goto: StringName}]
##   do: Array[{action: StringName, args: Array（Expr / String / float）}]
var nodes: Dictionary = {}


static func from_dict(d: Dictionary, p_file: String, errors: PackedStringArray, consts: PackedStringArray = []) -> DialogGraph:
	var g: DialogGraph = DialogGraph.new()
	g.file = p_file
	var w: String = p_file
	DefUtil.known(d, ["id", "trigger", "start", "locals", "nodes"], w, errors)
	g.id = StringName(DefUtil.s(d, "id", w, errors))
	g.trigger = DefUtil.dict(d, "trigger", w, errors)
	if not g.trigger.is_empty() and not g.trigger.has("kind"):
		errors.append("%s：trigger 缺少 kind" % w)
	g.start = StringName(DefUtil.s(d, "start", w, errors))
	g.locals = DefUtil.strs(d, "locals", w, errors, false)
	var raw_nodes: Dictionary = DefUtil.dict(d, "nodes", w, errors, true)
	# 局部变量：locals 声明 + 选项 set 里出现的名字
	for nn: Variant in raw_nodes.keys():
		var nd: Variant = raw_nodes[nn]
		if nd is Dictionary and (nd as Dictionary).get("choices") is Array:
			for c: Variant in (nd as Dictionary)["choices"]:
				if c is Dictionary and (c as Dictionary).get("set") is Dictionary:
					for k: Variant in ((c as Dictionary)["set"] as Dictionary).keys():
						if not g.locals.has(str(k)):
							g.locals.append(str(k))
	var names: PackedStringArray = StoryDefs.INPUTS.duplicate()
	names.append_array(consts)
	names.append_array(g.locals)
	for nn: Variant in raw_nodes.keys():
		var nw: String = "%s:nodes.%s" % [w, nn]
		if not (raw_nodes[nn] is Dictionary):
			errors.append("%s：节点应为对象" % nw)
			continue
		g.nodes[StringName(str(nn))] = g._compile_node(raw_nodes[nn], names, "story.%s.%s" % [g.id, nn], nw, errors)
	g._check_links(errors)
	return g


func _compile_node(nd: Dictionary, names: PackedStringArray, key: String, w: String, errors: PackedStringArray) -> Dictionary:
	DefUtil.known(nd, NODE_KEYS, w, errors)
	var out: Dictionary = {"say": [], "choices": [], "branch": [], "do": [], "goto": &"", "end": false, "if_no_choice": &"", "who": str(nd.get("who", ""))}
	var i: int = 0
	for line: Variant in nd.get("say", []):
		var who: Variant = null
		var text: Variant = line
		if line is Dictionary:
			who = str((line as Dictionary).get("who", ""))
			text = (line as Dictionary).get("text", "")
		(out["say"] as Array).append({"who": who, "text": TextTpl.compile(text, names, "%s.l%d" % [key, i], "%s.say[%d]" % [w, i], errors)})
		i += 1
	i = 0
	for c: Variant in nd.get("choices", []):
		var cw: String = "%s.choices[%d]" % [w, i]
		if not (c is Dictionary):
			errors.append("%s：应为对象" % cw)
			continue
		var cd: Dictionary = c
		DefUtil.known(cd, ["text", "if", "gold", "goto", "end", "set"], cw, errors)
		var sets: Dictionary = {}
		for k: Variant in DefUtil.dict(cd, "set", cw, errors).keys():
			sets[str(k)] = Expr.compile(str(cd["set"][k]), names, "%s.set.%s" % [cw, k], errors)
		(out["choices"] as Array).append({
			"text": TextTpl.compile(cd.get("text", ""), names, "%s.c%d" % [key, i], cw + ".text", errors),
			"cond": Expr.compile(str(cd["if"]), names, cw + ".if", errors) if cd.has("if") else null,
			"gold": DefUtil.b(cd, "gold", cw, errors),
			"goto": StringName(DefUtil.s(cd, "goto", cw, errors, false)),
			"end": DefUtil.b(cd, "end", cw, errors),
			"set": sets,
		})
		i += 1
	i = 0
	for b: Variant in nd.get("branch", []):
		var bw: String = "%s.branch[%d]" % [w, i]
		i += 1
		if not (b is Dictionary):
			errors.append("%s：应为对象" % bw)
			continue
		var bd: Dictionary = b
		DefUtil.known(bd, ["if", "goto"], bw, errors)
		(out["branch"] as Array).append({"cond": Expr.compile(str(bd["if"]), names, bw + ".if", errors) if bd.has("if") else null, "goto": StringName(DefUtil.s(bd, "goto", bw, errors))})
	i = 0
	for a: Variant in nd.get("do", []):
		var aw: String = "%s.do[%d]" % [w, i]
		i += 1
		if not (a is Array) or (a as Array).is_empty():
			errors.append("%s：动作应为 [名字, 参数…]" % aw)
			continue
		var act: String = str((a as Array)[0])
		if not ACTIONS.has(act):
			errors.append("%s：未知动作 %s（词表：%s）" % [aw, act, ", ".join(ACTIONS)])
			continue
		var args: Array = []
		var arr: Array = a
		for j: int in range(1, arr.size()):
			var v: Variant = arr[j]
			# set / add 的第 2 个参数和 money 的第 1 个参数是表达式；其余原样（字符串 / 数字）
			if (act == "set" or act == "add") and j == 2 or act == "money" and j == 1:
				args.append(Expr.value_or_expr(v, names, "%s[%d]" % [aw, j], errors))
			else:
				args.append(v)
		(out["do"] as Array).append({"action": StringName(act), "args": args})
	out["goto"] = StringName(DefUtil.s(nd, "goto", w, errors, false))
	out["end"] = DefUtil.b(nd, "end", w, errors)
	out["if_no_choice"] = StringName(DefUtil.s(nd, "if_no_choice", w, errors, false))
	return out


## 所有 goto / if_no_choice / branch 目标都必须存在；start 必须存在。
func _check_links(errors: PackedStringArray) -> void:
	if not nodes.has(start):
		errors.append("%s：start 节点 %s 不存在" % [file, start])
	for nn: StringName in nodes.keys():
		var nd: Dictionary = nodes[nn]
		var targets: Array[StringName] = [nd["goto"], nd["if_no_choice"]]
		for c: Dictionary in nd["choices"]:
			targets.append(c["goto"])
		for b: Dictionary in nd["branch"]:
			targets.append(b["goto"])
		for t: StringName in targets:
			if t != &"" and not nodes.has(t):
				errors.append("%s：节点 %s 跳向不存在的节点 %s" % [file, nn, t])
