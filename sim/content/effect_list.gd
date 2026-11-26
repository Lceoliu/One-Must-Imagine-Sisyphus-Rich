class_name EffectList
extends RefCounted
## 数值效果 DSL（architecture §5.2）：一条效果 = [op, stat, expr…]，一个列表按顺序执行。
## op 只有 12 种：add mul set max min min_nz clamp or map_add map_max if hook。
## 硬规则：op 集合要变，必须同时改本文件和 tools/content/dsl_ref.mjs，并在 architecture §5.2 登记。
##
## hook：["hook","<模块>.<函数>"] 调用 hook_host.call_fx(名字, st, inputs)（BoonSystem 实现，转给 RuleModule.fx_<函数>）。

const OPS: PackedStringArray = ["add", "mul", "set", "max", "min", "min_nz", "clamp", "or", "map_add", "map_max", "if", "hook"]
## 只能用于数值字段的 op
const NUMERIC_OPS: PackedStringArray = ["add", "mul", "max", "min", "min_nz", "clamp"]

enum Op { ADD, MUL, SET, MAX, MIN, MIN_NZ, CLAMP, OR, MAP_ADD, MAP_MAX, IF, HOOK }

var where: String = ""
## 预编译：每条 [Op, stat: StringName, a, b, c]；a/b/c 是 float / bool / Expr / EffectList / String
var _ops: Array = []
var _hooks: PackedStringArray = []


## 编译 JSON 数组。stat 名与类型按 Stats.TYPES 校验；表达式用 input_names 编译。错误追加进 errors（返回的列表跳过出错的条目）。
static func compile(raw: Variant, input_names: PackedStringArray, p_where: String, errors: PackedStringArray) -> EffectList:
	var fx: EffectList = EffectList.new()
	fx.where = p_where
	if raw == null:
		return fx
	if not (raw is Array):
		errors.append("%s：效果列表必须是数组" % p_where)
		return fx
	var i: int = 0
	for item: Variant in raw:
		var w: String = "%s[%d]" % [p_where, i]
		i += 1
		if not (item is Array) or (item as Array).is_empty():
			errors.append("%s：每条效果必须是非空数组 [op, …]" % w)
			continue
		var a: Array = item
		var op_name: String = str(a[0])
		var op: int = OPS.find(op_name)
		if op < 0:
			errors.append("%s：未知 op %s（只允许 %s）" % [w, op_name, ", ".join(OPS)])
			continue
		var c: Array = fx._compile_one(op, a, input_names, w, errors)
		if not c.is_empty():
			fx._ops.append(c)
	return fx


func _compile_one(op: int, a: Array, input_names: PackedStringArray, w: String, errors: PackedStringArray) -> Array:
	var need: int = {Op.OR: 2, Op.HOOK: 2, Op.CLAMP: 4, Op.MAP_ADD: 4, Op.MAP_MAX: 4}.get(op, 3)
	if a.size() != need:
		errors.append("%s：%s 需要 %d 个元素，实际 %d" % [w, OPS[op], need, a.size()])
		return []
	if op == Op.HOOK:
		var hn: String = str(a[1])
		if hn.count(".") != 1 or hn.begins_with(".") or hn.ends_with("."):
			errors.append("%s：hook 名必须是 \"<模块>.<函数>\"：%s" % [w, hn])
			return []
		_hooks.append(hn)
		return [op, StringName(hn)]
	if op == Op.IF:
		var cond: Variant = Expr.value_or_expr(a[1], input_names, w + ".if", errors)
		var body: EffectList = EffectList.compile(a[2], input_names, w + ".then", errors)
		for h: String in body._hooks:
			_hooks.append(h)
		return [op, &"", cond, body]
	var stat: StringName = StringName(str(a[1]))
	if not Stats.has_field(stat):
		errors.append("%s：未声明的 stat %s（content/stats/*.json）" % [w, stat])
		return []
	var ty: String = Stats.TYPES[stat]
	if OPS[op] in NUMERIC_OPS and ty != "float" and ty != "int":
		errors.append("%s：%s 只能用于数值字段，%s 是 %s" % [w, OPS[op], stat, ty])
		return []
	if op == Op.OR and ty != "bool":
		errors.append("%s：or 只能用于 bool 字段，%s 是 %s" % [w, stat, ty])
		return []
	if (op == Op.MAP_ADD or op == Op.MAP_MAX) and ty != "dict_float":
		errors.append("%s：%s 只能用于 dict_float 字段，%s 是 %s" % [w, OPS[op], stat, ty])
		return []
	if op == Op.SET and ty.begins_with("dict"):
		errors.append("%s：字典字段 %s 不能整体 set" % [w, stat])
		return []
	match op:
		Op.OR:
			return [op, stat]
		Op.CLAMP:
			return [op, stat, Expr.value_or_expr(a[2], input_names, w, errors), Expr.value_or_expr(a[3], input_names, w, errors)]
		Op.MAP_ADD, Op.MAP_MAX:
			return [op, stat, str(a[2]), Expr.value_or_expr(a[3], input_names, w, errors)]
	return [op, stat, Expr.value_or_expr(a[2], input_names, w, errors)]


func is_empty() -> bool:
	return _ops.is_empty()


## 用到的 hook 名（含 if 内部），ContentDB 用来列出需要模块实现的 fx_*。
func hook_names() -> PackedStringArray:
	return _hooks


## 执行。inputs：输入名 → 值（数字传 float）。hook_host：实现 call_fx(name: StringName, st: Stats, inputs: Dictionary) -> bool 的对象。
func apply(st: Stats, inputs: Dictionary, hook_host: Object = null) -> void:
	for c: Array in _ops:
		var op: int = c[0]
		match op:
			Op.ADD:
				st.set(c[1], Expr.to_num(st.get(c[1])) + _num(c[2], inputs))
			Op.MUL:
				st.set(c[1], Expr.to_num(st.get(c[1])) * _num(c[2], inputs))
			Op.SET:
				_set_value(st, c[1], Expr.resolve(c[2], inputs))
			Op.MAX:
				st.set(c[1], js_max(Expr.to_num(st.get(c[1])), _num(c[2], inputs)))
			Op.MIN:
				st.set(c[1], js_min(Expr.to_num(st.get(c[1])), _num(c[2], inputs)))
			Op.MIN_NZ:
				var cur: float = Expr.to_num(st.get(c[1]))
				var x: float = _num(c[2], inputs)
				st.set(c[1], js_min(cur, x) if cur != 0.0 else x)
			Op.CLAMP:
				var lo: float = _num(c[2], inputs)
				var hi: float = _num(c[3], inputs)
				st.set(c[1], js_max(lo, js_min(hi, Expr.to_num(st.get(c[1])))))
			Op.OR:
				st.set(c[1], true)
			Op.MAP_ADD:
				var m: Dictionary = st.get(c[1])
				m[c[2]] = float(m.get(c[2], 0.0)) + _num(c[3], inputs)
			Op.MAP_MAX:
				var m2: Dictionary = st.get(c[1])
				m2[c[2]] = js_max(float(m2.get(c[2], 0.0)), _num(c[3], inputs))
			Op.IF:
				if Expr.truthy(Expr.resolve(c[2], inputs)):
					(c[3] as EffectList).apply(st, inputs, hook_host)
			Op.HOOK:
				var ok: bool = false
				if hook_host != null and hook_host.has_method(&"call_fx"):
					ok = hook_host.call(&"call_fx", c[1], st, inputs)
				if not ok:
					push_error("[content] %s：hook %s 没有被处理（模块未实现 fx_ 函数或没传 hook_host）" % [where, c[1]])


func _num(v: Variant, inputs: Dictionary) -> float:
	return Expr.to_num(Expr.resolve(v, inputs))


## set 的值按字段类型落地：Object.set 会把 float 自动转 int（截断，与 dsl_ref 的 Math.trunc 一致）
func _set_value(st: Stats, stat: StringName, v: Variant) -> void:
	var ty: String = Stats.TYPES[stat]
	match ty:
		"float":
			st.set(stat, Expr.to_num(v))
		"int":
			st.set(stat, int(Expr.to_num(v)))
		"bool":
			st.set(stat, Expr.truthy(v))
		"name":
			st.set(stat, StringName("" if v == null else str(v)))


## JS Math.max(a, b)（两个参数、无 NaN）：相等时 +0 优先于 -0。maxf(0.0, -0.0) 会返回 -0.0，所以不用它。
## 注意：不写 -0.0 字面量——GDScript 的常量池把 0.0 和 -0.0 当成同一个常量（4.5.1 实测），只能返回参数本身。
static func js_max(a: float, b: float) -> float:
	if a > b:
		return a
	if b > a:
		return b
	if a == 0.0 and b == 0.0:
		return a if 1.0 / a > 0.0 else b
	return a


## JS Math.min(a, b)：相等时 -0 优先。
static func js_min(a: float, b: float) -> float:
	if a < b:
		return a
	if b < a:
		return b
	if a == 0.0 and b == 0.0:
		return a if 1.0 / a < 0.0 else b
	return a
