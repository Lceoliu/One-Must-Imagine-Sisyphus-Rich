class_name Expr
extends RefCounted
## 内容表达式（architecture §5.3）：加载期静态检查 + 预编译，执行期只算数。
##
## 子集：数字 / 字符串字面量、输入名、+ - * /、括号、比较、and or not、数组字面量加下标、成员读取（f.chain）、
## ExprLib 白名单函数（min max pow floor ceil abs clamp sqrt jsround pct）。
## 没有三元（Godot 4.5.1 的 `a if c else b` 实测永远返回 a）、没有 %（float % float 运行时报错）、没有 **。
## 输入一律以 float 传入；JS 版参考解释器是 tools/content/dsl_ref.mjs，语义逐条一致。

var src: String = ""
var names: PackedStringArray = []
var where: String = ""
var _e: Expression = null
## 表达式本身就是一个数字字面量时直接返回它（省一次 execute）
var _const: Variant = null
var _is_const: bool = false
var _warned: bool = false


## 编译：先 ExprLib.check（白名单），再 Expression.parse。失败返回 null 并把错误追加进 errors。
static func compile(p_src: String, p_names: PackedStringArray, p_where: String, errors: PackedStringArray) -> Expr:
	var x: Expr = Expr.new()
	x.src = p_src
	x.names = p_names
	x.where = p_where
	var errs: PackedStringArray = ExprLib.check(p_src, p_names)
	if not errs.is_empty():
		for e: String in errs:
			errors.append("%s：%s" % [p_where, e])
		return null
	if p_src.strip_edges().is_valid_float() and not p_src.contains("e") and not p_src.contains("E"):
		x._is_const = true
		x._const = p_src.strip_edges().to_float()
		return x
	var e: Expression = Expression.new()
	if e.parse(p_src, p_names) != OK:
		errors.append("%s：表达式解析失败 %s（%s）" % [p_where, p_src, e.get_error_text()])
		return null
	x._e = e
	return x


## 按 names 的顺序传入输入值（数字请传 float）。执行失败时报一次错并返回 null。
func eval(inputs: Array) -> Variant:
	if _is_const:
		return _const
	var v: Variant = _e.execute(inputs, ExprLib.INSTANCE, false, true)
	if _e.has_execute_failed():
		if not _warned:
			_warned = true
			push_error("[content] %s：表达式求值失败 %s（%s）" % [where, src, _e.get_error_text()])
		return null
	return v


## 按名字传入输入（缺的名字当 0.0）。int 一律转 float，避免 Godot 整除。
func eval_dict(d: Dictionary) -> Variant:
	if _is_const:
		return _const
	var arr: Array = []
	arr.resize(names.size())
	for i: int in names.size():
		var v: Variant = d.get(names[i], 0.0)
		arr[i] = float(v) if typeof(v) == TYPE_INT else v
	return eval(arr)


## 求值并转成 float（bool → 0/1；null → 0）。
func eval_float(d: Dictionary) -> float:
	return Expr.to_num(eval_dict(d))


## 求值并按 JS 真值转成 bool。
func eval_bool(d: Dictionary) -> bool:
	return Expr.truthy(eval_dict(d))


static func to_num(v: Variant) -> float:
	match typeof(v):
		TYPE_FLOAT, TYPE_INT, TYPE_BOOL:
			return float(v)
	return 0.0


## JS 式真值：0 / "" / null / false / 空容器为假。
static func truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return float(v) != 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			return not String(v).is_empty()
		TYPE_ARRAY:
			return not (v as Array).is_empty()
		TYPE_DICTIONARY:
			return not (v as Dictionary).is_empty()
	return true


## 内容 JSON 里的"值"：数字 / 布尔直接用；字符串是表达式，编译成 Expr。
static func value_or_expr(v: Variant, p_names: PackedStringArray, p_where: String, errors: PackedStringArray) -> Variant:
	if typeof(v) == TYPE_STRING:
		return compile(v, p_names, p_where, errors)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	if typeof(v) == TYPE_BOOL:
		return v
	errors.append("%s：期望数字、布尔或表达式字符串，得到 %s" % [p_where, var_to_str(v)])
	return null


## 对 value_or_expr 的结果求值。
static func resolve(v: Variant, d: Dictionary) -> Variant:
	if v is Expr:
		return (v as Expr).eval_dict(d)
	return v
