class_name NumFmt
## 网页的数字显示函数（逐行移植，静态）。
## 单位跟着界面语言：中文万 / 亿（网页原样），英文 K / M / B（见 fmt）。

## 希腊数字表（render.js:700 GN）：个位 / 十位 / 百位。
const GN: Array[PackedStringArray] = [
	["", "Α", "Β", "Γ", "Δ", "Ε", "ΣΤ", "Ζ", "Η", "Θ"],
	["", "Ι", "Κ", "Λ", "Μ", "Ν", "Ξ", "Ο", "Π", "Ϙ"],
	["", "Ρ", "Σ", "Τ", "Υ", "Φ", "Χ", "Ψ", "Ω", "Ϡ"],
]


## 移植自 render.js:692 fmt(n)（gods/util.js:11 同名函数多一个 `n || 0`：NaN 当 0，这里统一采用）。
## 中文：< 1 万：千分位整数；< 1 亿：x.xx万 / xx.x万；否则 x.xx亿。
## 英文（Loc.is_en()）：< 1 万：千分位整数；再往上 x.xxK / xxx.xK、x.xxM、x.xxB（四舍五入后满 1000 就进到下一档）。
static func fmt(n: float) -> String:
	if is_nan(n):
		n = 0.0
	n = floorf(n)
	if n < 1e4:
		return Js.group_int(n)
	if Loc.is_en():
		return _fmt_en(n)
	if n < 1e8:
		return Js.to_fixed(n / 1e4, 2 if n < 1e5 else 1) + "万"  # i18n: skip（中文单位；英文走 _fmt_en）
	return Js.to_fixed(n / 1e8, 2) + "亿"  # i18n: skip


static func _fmt_en(n: float) -> String:
	if n < 999950.0:
		return Js.to_fixed(n / 1e3, 2 if n < 1e5 else 1) + "K"
	if n < 999995000.0:
		return Js.to_fixed(n / 1e6, 2) + "M"
	return Js.to_fixed(n / 1e9, 2) + "B"


## 移植自 render.js:701 greekNum(n)：1–999 的希腊数字，第 17 日 → ΙΖʹ。
@warning_ignore("integer_division")
static func greek_num(n: float) -> String:
	var v: int = int(maxf(1.0, floorf(n))) % 1000
	return GN[2][v / 100] + GN[1][(v / 10) % 10] + GN[0][v % 10] + "ʹ"


## 移植自 render.js:1292 fmtTalent(r)：石头质量（塔兰同）。运算顺序照抄（浮点结果逐位一致）。
static func fmt_talent(r: float) -> String:
	var t: float = (4.0 / 3.0) * PI * r * r * r * 2600.0 / 26.0
	return Js.group_int(Js.round(t)) if t < 1e4 else fmt(t)
