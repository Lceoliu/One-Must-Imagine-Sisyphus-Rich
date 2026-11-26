class_name TextFmt
## 带数字的文本模板（architecture §16、arch-data §5）。不用 String.format（它没有格式符）。
##
## 语法：`{名字}` 或 `{名字|格式符|格式符…}`；`{{` `}}` 输出字面量 `{` `}`。
## 格式符：
##   pct    四舍五入百分数并带 %：0.4 → "40%"（= events.js:68 pct）
##   f1 f2  JS toFixed(1/2)
##   int    Math.round 后的整数
##   money  网页 fmt：千分位 / 万 / 亿（NumFmt.fmt）
##   cn_num 中文数字：3 → 三，12 → 十二
##   sign   修饰符：值 ≥ 0 时在结果前加 "+"（可与其他格式符连用，如 {v|sign|pct} → "+40%"）
## 没有格式符的数字按 JS String(x) 输出（整数不带 .0）；字符串原样插入。缺少的名字原样保留 `{名字}` 并在结果里可见，便于发现漏传。

const SPECS: PackedStringArray = ["pct", "f1", "f2", "int", "money", "cn_num", "sign"]
const _CN_DIGITS: PackedStringArray = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
const _CN_UNITS: PackedStringArray = ["", "十", "百", "千"]


static func fmt(tpl: String, args: Dictionary) -> String:
	var out: String = ""
	var i: int = 0
	var n: int = tpl.length()
	while i < n:
		var ch: String = tpl[i]
		if ch == "{":
			if i + 1 < n and tpl[i + 1] == "{":
				out += "{"
				i += 2
				continue
			var j: int = tpl.find("}", i + 1)
			if j < 0:
				out += tpl.substr(i)
				break
			out += _field(tpl.substr(i + 1, j - i - 1), args)
			i = j + 1
			continue
		if ch == "}" and i + 1 < n and tpl[i + 1] == "}":
			out += "}"
			i += 2
			continue
		out += ch
		i += 1
	return out


## 模板里出现的格式符是否都合法（validate 用；返回错误列表）。
static func check(tpl: String) -> PackedStringArray:
	var errs: PackedStringArray = []
	var i: int = tpl.find("{")
	while i >= 0:
		if i + 1 < tpl.length() and tpl[i + 1] == "{":
			i = tpl.find("{", i + 2)
			continue
		var j: int = tpl.find("}", i + 1)
		if j < 0:
			errs.append("未闭合的 {：%s" % tpl)
			break
		var parts: PackedStringArray = tpl.substr(i + 1, j - i - 1).split("|")
		for k: int in range(1, parts.size()):
			if not SPECS.has(parts[k].strip_edges()):
				errs.append("未知格式符 %s：%s" % [parts[k], tpl])
		i = tpl.find("{", j + 1)
	return errs


static func _field(body: String, args: Dictionary) -> String:
	var parts: PackedStringArray = body.split("|")
	var key: String = parts[0].strip_edges()
	if not args.has(key):
		return "{" + body + "}"
	var v: Variant = args[key]
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return str(v)
	var x: float = float(v)
	var signed: bool = false
	var s: String = ""
	var has_fmt: bool = false
	for k: int in range(1, parts.size()):
		var spec: String = parts[k].strip_edges()
		if spec == "sign":
			signed = true
			continue
		has_fmt = true
		s = num(x, spec)
	if not has_fmt:
		s = Js.num_str(x)
	if signed and x >= 0.0:
		s = "+" + s
	return s


## 按单个格式符格式化一个数（未知格式符退回 JS String(x)）。
static func num(x: float, spec: String) -> String:
	match spec:
		"pct":
			# 用 Js.num_str 而不是 "%.0f"：-0 要输出 "0"（JS 模板 `${Math.round(-0.004*100)}%` 是 "0%"），大数也按 JS String 排版
			return Js.num_str(Js.round(x * 100.0)) + "%"
		"f1":
			return Js.to_fixed(x, 1)
		"f2":
			return Js.to_fixed(x, 2)
		"int":
			return Js.num_str(Js.round(x))
		"money":
			return NumFmt.fmt(x)
		"cn_num":
			return cn_num(int(Js.round(x)))
	return Js.num_str(x)


## 中文数字（0 – 99999999）：10 → 十，12 → 十二，105 → 一百零五，2000 → 二千（不做"两"的口语变换）。英文界面直接写阿拉伯数字。
static func cn_num(n: int) -> String:
	if Loc.is_en():
		return str(n)
	if n < 0:
		return "负" + cn_num(-n)
	if n < 10:
		return _CN_DIGITS[n]
	if n >= 10000:
		var hi: int = floori(n / 10000.0)
		var lo: int = n % 10000
		var head: String = _cn_under_10k(hi, false) + "万"
		if lo == 0:
			return head
		return head + ("零" if lo < 1000 else "") + _cn_under_10k(lo, true)
	return _cn_under_10k(n, false)


## 1–9999 的中文读法；inner=true 表示它跟在"万"后面（此时 10–19 要读"一十"）。
static func _cn_under_10k(n: int, inner: bool) -> String:
	var s: String = ""
	var zero: bool = false
	var started: bool = false
	for p: int in [3, 2, 1, 0]:
		var unit: int = int(pow(10.0, float(p)))
		var d: int = floori(float(n) / float(unit)) % 10
		if d == 0:
			if started:
				zero = true
			continue
		if zero:
			s += "零"
			zero = false
		if not (p == 1 and d == 1 and not started and not inner):
			s += _CN_DIGITS[d]
		s += _CN_UNITS[p]
		started = true
	return s
