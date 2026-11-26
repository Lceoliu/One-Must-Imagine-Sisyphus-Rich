class_name DialogRunner
extends RefCounted
## 推进一张剧情事件图（DialogGraph，content/story/events/*.json）：每个有台词 / 选项的节点发一个 DIALOG 模态，
## 玩家（或机器人）回答后按选项 / goto / branch 走到下一个节点。
## 节点的处理顺序：do（动作，按顺序；play_ending 会等演出结束再继续）→ branch（取第一个满足的）→ say + choices（发模态）→ goto / end。
## 动作词表（DialogGraph.ACTIONS）：
##   ["set", 目标, 值]       目标 = "f.<flag>" 或本图局部变量；值是表达式
##   ["add", 目标, 值]       同上，数值累加
##   ["money", 值]           g.money += 值（只有奥托吕科斯扣钱；众神不撒钱）
##   ["banner", 标题, 副标题, 秒?]  ["sfx", 名字, 参数?]  ["save"]  ["narr", 文字]
##   ["queue", 类型, n?]     往 flags.queue 追加一个工资条后的事件
##   ["play_ending", id]     播假结局（演出 + 结局卡 + 补偿），结束后继续本节点
##   ["refresh_stats", passive id]  立刻把这个信物效果加到今天的 stats 上（条件不满足就不加）
##   ["call", 名字, 参数…]   调 StorySystem.act_<名字>(参数…)（逃生口，尽量别用）

var story: StorySystem
var graph: DialogGraph
var locals: Dictionary = {}
var on_done: Callable = Callable()
var finished: bool = false


func _init(p_story: StorySystem, p_graph: DialogGraph, p_locals: Dictionary, p_done: Callable) -> void:
	story = p_story
	graph = p_graph
	on_done = p_done
	for k: String in graph.locals:
		locals[k] = 0.0
	for k: Variant in p_locals.keys():
		locals[str(k)] = p_locals[k]


func start() -> void:
	_enter(graph.start)


func _inputs() -> Dictionary:
	var d: Dictionary = story.inputs()
	for k: String in locals:
		d[k] = locals[k]
	return d


func _enter(name: StringName) -> void:
	if finished:
		return
	var nd: Dictionary = graph.nodes.get(name, {})
	if nd.is_empty():
		push_error("[story] %s：节点 %s 不存在" % [graph.id, name])
		_finish()
		return
	_run_do(nd, 0)


## 依次执行 do；遇到 play_ending 先停下，演完再从下一条继续
func _run_do(nd: Dictionary, i: int) -> void:
	var acts: Array = nd["do"]
	while i < acts.size():
		var a: Dictionary = acts[i]
		i += 1
		if a["action"] == &"play_ending":
			var next_i: int = i
			story.play_fake(StringName(str((a["args"] as Array)[0])), func() -> void: _run_do(nd, next_i))
			return
		_act(a["action"], a["args"])
	_after_do(nd)


func _after_do(nd: Dictionary) -> void:
	var inp: Dictionary = _inputs()
	for b: Dictionary in nd["branch"]:
		var c: Variant = b["cond"]
		if c == null or (c as Expr).eval_bool(inp):
			_enter(b["goto"])
			return
	var pages: Array = []
	for line: Dictionary in nd["say"]:
		var who: String = String(nd["who"]) if line["who"] == null else String(line["who"])
		pages.append(story.page(who, (line["text"] as TextTpl).render(inp)))
	# 只有台词、goto 到一个"只有选项"的节点：合成一个模态（台词 + 选项），和网页的一次对话一样
	var cnode: Dictionary = nd
	if (nd["choices"] as Array).is_empty() and nd["goto"] != &"" and not pages.is_empty():
		var t: Dictionary = graph.nodes.get(nd["goto"], {})
		if not t.is_empty() and (t["say"] as Array).is_empty() and (t["do"] as Array).is_empty() and (t["branch"] as Array).is_empty() and not (t["choices"] as Array).is_empty():
			cnode = t
	var shown: Array = []
	for c: Dictionary in cnode["choices"]:
		if c["cond"] == null or (c["cond"] as Expr).eval_bool(inp):
			shown.append(c)
	var all_hidden: bool = not (cnode["choices"] as Array).is_empty() and shown.is_empty()
	var who0: String = String(nd["who"])
	nd = cnode   # 之后的回答 / 离开都按选项所在的节点走（选项全隐藏时走它的 if_no_choice）
	if pages.is_empty() and shown.is_empty():
		_leave(nd, all_hidden)
		return
	var faces: Array = []
	for c: Dictionary in shown:
		faces.append({"label": (c["text"] as TextTpl).render(inp), "gold": bool(c["gold"])})
	story.open_dialog(who0, pages, faces, func(i: int) -> void:
		if shown.is_empty():
			_leave(nd, all_hidden)
			return
		var c: Dictionary = shown[clampi(i, 0, shown.size() - 1)]
		var inp2: Dictionary = _inputs()
		for k: String in c["set"]:
			locals[k] = (c["set"][k] as Expr).eval_dict(inp2)
		if bool(c["end"]):
			_finish()
		elif c["goto"] != &"":
			_enter(c["goto"])
		else:
			_leave(nd, false)
		)


func _leave(nd: Dictionary, all_hidden: bool) -> void:
	if all_hidden and nd["if_no_choice"] != &"":
		_enter(nd["if_no_choice"])
	elif nd["goto"] != &"":
		_enter(nd["goto"])
	else:
		_finish()


func _finish() -> void:
	if finished:
		return
	finished = true
	var cb: Callable = on_done
	on_done = Callable()
	if cb.is_valid():
		cb.call()


## 中止（换局、本代结束）：不再回调
func abort() -> void:
	finished = true
	on_done = Callable()


func _value(v: Variant) -> Variant:
	return Expr.resolve(v, _inputs())


func _act(action: StringName, args: Array) -> void:
	var g: SimGame = story.g
	match action:
		&"set", &"add":
			var target: String = str(args[0])
			var v: Variant = _value(args[1])
			if target.begins_with("f."):
				var k: String = target.substr(2)
				story.flags[k] = (Expr.to_num(story.flags.get(k, 0.0)) + Expr.to_num(v)) if action == &"add" else v
			else:
				locals[target] = (Expr.to_num(locals.get(target, 0.0)) + Expr.to_num(v)) if action == &"add" else v
		&"money":
			g.money += Expr.to_num(_value(args[0]))
		&"banner":
			g.fx.banner(str(args[0]), str(args[1]) if args.size() > 1 else "", float(args[2]) if args.size() > 2 else 2.2)
		&"sfx":
			g.fx.sfx(StringName(str(args[0])), float(args[1]) if args.size() > 1 else 0.0)
		&"save":
			story.request_save()
		&"narr":
			story.say(str(args[0]))
		&"queue":
			var q: Dictionary = {"type": str(args[0])}
			if args.size() > 1:
				q["n"] = int(args[1])
			(story.flags["queue"] as Array).append(q)
		&"refresh_stats":
			story.apply_passive(StringName(str(args[0])), g.stats)
		&"call":
			var fn: StringName = StringName("act_" + str(args[0]))
			if story.has_method(fn):
				story.callv(fn, args.slice(1))
			else:
				push_error("[story] %s：没有动作函数 %s" % [graph.id, fn])
