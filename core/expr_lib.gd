class_name ExprLib
extends RefCounted
## 内容表达式（DSL 的 expr 字段）可调用的函数白名单，以及 Expression 的 base_instance（architecture §5.3）。
##
## 白名单：min max pow floor ceil abs clamp sqrt jsround pct lvl3 lvl4 lvl5。
## 其中 min max pow floor ceil abs clamp sqrt 由 Godot Expression 直接解析为内建工具函数（语义与 JS Math.* 一致：输入全是 float）；
## jsround、pct、lvl3/4/5 是本类的方法，经 base_instance 调用。
## 注意（4.5.1 实测）：const_calls_only=true 拦不住内建工具函数（如 print），所以白名单必须在加载期用 check() 静态检查，
## 由 sim/content/expr.gd 在 parse 之前调用；tools/content/dsl_ref.mjs 必须保持同一套规则。

const ALLOWED_FUNCS: PackedStringArray = ["min", "max", "pow", "floor", "ceil", "abs", "clamp", "sqrt", "jsround", "pct", "lvl3", "lvl4", "lvl5"]
## 没有 if / else：Godot 4.5.1 的 Expression 三元 `a if c else b` 实测永远返回 a（套括号还解析失败），所以表达式子集不含三元，
## 写了就按"未知标识符"拒绝。条件放在 DSL 的 if op、文本节点的 if 或神龛参数的 evo 里（F1 handoff §4）。
const KEYWORDS: PackedStringArray = ["and", "or", "not", "true", "false", "null"]

## Expression.execute 的 base_instance（无状态，可全局共用）。
static var INSTANCE: ExprLib = ExprLib.new()


## Math.round 语义（-2.5 → -2）。表达式里取整一律用它，不用 round。
func jsround(x: float) -> float:
	return Js.round(x)


## 逐级表（2026-10-16，升级的逐级效果不再是「每级一样」）：lvlN(lv, 第1级, …, 第N级) = 第 lv 级的累计值；
## lv ≤ 0 → 0，超过 N 取第 N 级。例：跨度 "1.0 + lvl5(lv, 0.04, 0.09, 0.15, 0.22, 0.45)"。= tools/content/dsl_ref.mjs 的同名函数
func lvl3(lv: float, a1: float, a2: float, a3: float) -> float:
	return _lvl(lv, [a1, a2, a3])


func lvl4(lv: float, a1: float, a2: float, a3: float, a4: float) -> float:
	return _lvl(lv, [a1, a2, a3, a4])


func lvl5(lv: float, a1: float, a2: float, a3: float, a4: float, a5: float) -> float:
	return _lvl(lv, [a1, a2, a3, a4, a5])


static func _lvl(lv: float, t: Array) -> float:
	var i: int = int(floor(lv))
	return 0.0 if i <= 0 else float(t[mini(i, t.size()) - 1])


## 百分数取整：events.js:259 的 P(x) = Math.round(x*100)。返回数值，不带 % 号（文本里的 % 由 TextFmt 的 pct 格式符负责）。
func pct(x: float) -> float:
	return Js.round(x * 100.0)


## 静态检查表达式源码：只允许 输入名 / 白名单函数调用 / 关键字 / 成员访问（a.b 的 b） / 数字和字符串字面量。
## 返回错误列表（空 = 合法）。input_names 是该场合允许的输入（architecture §5.3 的表）。
static func check(src: String, input_names: PackedStringArray) -> PackedStringArray:
	var errs: PackedStringArray = []
	var i: int = 0
	var n: int = src.length()
	var prev_dot: bool = false
	while i < n:
		var ch: String = src[i]
		if ch == "\"" or ch == "'":
			# 字符串字面量：跳到配对的引号（不支持转义里的同种引号，内容里也用不到）
			var j: int = src.find(ch, i + 1)
			if j < 0:
				errs.append("未闭合的字符串字面量：%s" % src)
				return errs
			i = j + 1
			prev_dot = false
			continue
		if _is_ident_start(ch):
			var j: int = i + 1
			while j < n and _is_ident_char(src[j]):
				j += 1
			var word: String = src.substr(i, j - i)
			var k: int = j
			while k < n and src[k] == " ":
				k += 1
			var is_call: bool = k < n and src[k] == "("
			if prev_dot:
				if is_call:
					errs.append("不允许调用成员方法 .%s()：%s" % [word, src])
			elif is_call and not KEYWORDS.has(word):
				# and / or / not 后面跟括号是分组，不是调用
				if not ALLOWED_FUNCS.has(word):
					errs.append("函数 %s 不在白名单 %s 里：%s" % [word, str(ALLOWED_FUNCS), src])
			elif not KEYWORDS.has(word) and not input_names.has(word):
				errs.append("未知标识符 %s（可用输入 %s）：%s" % [word, str(input_names), src])
			i = j
			prev_dot = false
			continue
		if ch >= "0" and ch <= "9":
			# 数字字面量（含小数点和指数），跳过，避免把 1e5 的 e 当成标识符
			var j: int = i + 1
			while j < n and (_is_ident_char(src[j]) or src[j] == "."):
				if (src[j] == "e" or src[j] == "E") and j + 1 < n and (src[j + 1] == "-" or src[j + 1] == "+"):
					j += 1
				j += 1
			i = j
			prev_dot = false
			continue
		if ch == "=" and not (i + 1 < n and src[i + 1] == "=") and not (i > 0 and "<>!=".contains(src[i - 1])):
			errs.append("表达式里不允许赋值：%s" % src)
		if ch == "*" and i + 1 < n and src[i + 1] == "*":
			errs.append("表达式里不允许 **（用 pow）：%s" % src)
		prev_dot = ch == "."
		i += 1
	return errs


static func _is_ident_start(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "_"


static func _is_ident_char(ch: String) -> bool:
	return _is_ident_start(ch) or (ch >= "0" and ch <= "9")
