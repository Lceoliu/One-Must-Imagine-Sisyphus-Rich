class_name TextTpl
extends RefCounted
## 内容里的文本节点：字符串（TextFmt 模板）| {"if": 条件, "then": 节点, "else": 节点} | 数组（依次拼接）。
## 条件是表达式（Expr），按 JS 真值判断；模板占位符见 core/text_fmt.gd。
## 本地化：每个字符串叶子有稳定键（key；非纯字符串时叶子按深度优先编号 key#0、key#1…），渲染时先过 Loc.t(键, 源文)。
## tools/content/i18n.mjs 用同一套编号生成 i18n/content.csv。JS 版渲染是 dsl_ref.mjs 的 renderText。

var key: String = ""
## 编译后的节点：String（叶子）| [Expr 条件, 节点, 节点] 的三元组用 Dictionary 表示 | Array（拼接）
var _root: Variant = ""


static func compile(node: Variant, input_names: PackedStringArray, p_key: String, where: String, errors: PackedStringArray) -> TextTpl:
	var t: TextTpl = TextTpl.new()
	t.key = p_key
	var counter: Array[int] = [0]
	var plain: bool = typeof(node) == TYPE_STRING
	t._root = t._compile(node, input_names, where, errors, counter, plain)
	return t


func _compile(node: Variant, input_names: PackedStringArray, where: String, errors: PackedStringArray, counter: Array[int], plain: bool) -> Variant:
	match typeof(node):
		TYPE_NIL:
			return ""
		TYPE_STRING:
			var s: String = node
			for e: String in TextFmt.check(s):
				errors.append("%s：%s" % [where, e])
			var k: String = key if plain else "%s#%d" % [key, counter[0]]
			counter[0] += 1
			return [k, s]
		TYPE_ARRAY:
			var out: Array = []
			for x: Variant in node:
				out.append(_compile(x, input_names, where, errors, counter, false))
			return out
		TYPE_DICTIONARY:
			var d: Dictionary = node
			if not d.has("if"):
				errors.append("%s：文本对象必须有 if / then / else" % where)
				return ""
			var cond: Variant = Expr.value_or_expr(d["if"], input_names, where + ".if", errors)
			var a: Variant = _compile(d.get("then", ""), input_names, where, errors, counter, false)
			var b: Variant = _compile(d.get("else", ""), input_names, where, errors, counter, false)
			return {"c": cond, "a": a, "b": b}
	errors.append("%s：无法识别的文本节点 %s" % [where, var_to_str(node)])
	return ""


## 渲染。args：输入名 → 值（条件和占位符都从这里取）。
func render(args: Dictionary) -> String:
	return _render(_root, args)


func _render(n: Variant, args: Dictionary) -> String:
	if n is Dictionary:
		var d: Dictionary = n
		return _render(d["a"] if Expr.truthy(Expr.resolve(d["c"], args)) else d["b"], args)
	if n is Array:
		var a: Array = n
		if a.size() == 2 and typeof(a[0]) == TYPE_STRING and typeof(a[1]) == TYPE_STRING:
			return TextFmt.fmt(Loc.t(a[0], a[1]), args)
		var s: String = ""
		for x: Variant in a:
			s += _render(x, args)
		return s
	return str(n)


## 是不是一个不带条件的纯字符串（渲染结果与参数无关时可缓存）。
func is_plain() -> bool:
	return _root is Array and (_root as Array).size() == 2 and typeof((_root as Array)[0]) == TYPE_STRING and typeof((_root as Array)[1]) == TYPE_STRING
