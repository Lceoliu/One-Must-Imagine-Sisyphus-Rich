class_name Js
## JS 语义兼容层（无状态静态函数）。sim 与 present 共用；照 arch-sim §3.1，并补了几个移植时常用的 JS 行为。
## 规则代码里凡是 JS 与 GDScript 语义不同的地方（Math.round、ToUint32、Math.imul、log10、排序稳定性、toFixed、String(x)）一律走这里。

const M32: int = 0xFFFFFFFF


## JS ToUint32（有限数）：NaN/±Infinity → 0；其余向零截断后按 2^32 取模。种子都 < 2^53，int() 不会溢出。
static func to_u32(x: float) -> int:
	if is_nan(x) or is_inf(x):
		return 0
	return int(x) & M32


## JS ToInt32（`x | 0`）：先 ToUint32，再把 ≥ 2^31 的部分折回负数。
static func to_i32(x: float) -> int:
	var u: int = to_u32(x)
	return u - 0x100000000 if u >= 0x80000000 else u


## Math.imul，结果按 u32 表示（与 world.js 里 `>>>` 之后的取值一致）。16 位拆分，全部乘积 < 2^34，不会溢出 int64。
static func imul(a: int, b: int) -> int:
	var al: int = a & 0xFFFF
	var ah: int = (a >> 16) & 0xFFFF
	var bl: int = b & 0xFFFF
	var bh: int = (b >> 16) & 0xFFFF
	return (al * bl + (((ah * bl + al * bh) & 0xFFFF) << 16)) & M32


## Math.round：x.5 一律向 +∞（-2.5 → -2）；GDScript 的 round() 是远离零（-2.5 → -3），不能混用。
## 不用 arch-sim §3.1 的 floorf(x + 0.5)：它在 0.49999999999999994 → 1、2^52 附近的奇数 +0.5 处与 V8 不同（加法先舍入了）。
## x - floor(x) 对 double 是精确的，所以下面的写法与 V8 逐位一致（golden core_cases.round 覆盖）。
static func round(x: float) -> float:
	if is_nan(x) or is_inf(x):
		return x
	var f: float = floorf(x)
	var r: float = f + 1.0 if x - f >= 0.5 else f
	# V8：[-0.5, -0) 返回 -0
	return -0.0 if r == 0.0 and x < 0.0 else r


## Math.log10：GDScript 没有 log10；10 的整数次幂必须精确返回整数（封印数 floor 的边界依赖它）。
static func log10(x: float) -> float:
	var r: float = log(x) / log(10.0)
	var k: float = roundf(r)
	if absf(r - k) < 1e-9 and pow(10.0, k) == x:
		return k
	return r


## Math.hypot（两参数）。
static func hypot(a: float, b: float) -> float:
	return sqrt(a * a + b * b)


## Math.sign：0 和 -0 原样返回 0。
static func sign(x: float) -> float:
	if x > 0.0:
		return 1.0
	if x < 0.0:
		return -1.0
	return 0.0


## Math.max(...arr)：空数组返回 -INF（JS 语义），不是报错。
static func max_of(arr: Array) -> float:
	var m: float = -INF
	for v: Variant in arr:
		m = maxf(m, float(v))
	return m


## Math.min(...arr)：空数组返回 +INF。
static func min_of(arr: Array) -> float:
	var m: float = INF
	for v: Variant in arr:
		m = minf(m, float(v))
	return m


## JS 的 Array.prototype.sort 是稳定排序，GDScript sort_custom 不保证。按对象属性 key 升序稳定排序（原地）。
## 只读属性值，不关心元素的具体类型（core 不依赖 sim 的 CrushObj）。
static func stable_sort_by(a: Array, key: StringName) -> void:
	var keyed: Array = []
	for i: int in a.size():
		var o: Object = a[i]
		keyed.append([float(o.get(key)), i, o])
	keyed.sort_custom(_cmp_keyed)
	for i: int in a.size():
		var row: Array = keyed[i]
		a[i] = row[2]


## world.js:226、boons.js:417 的 `objs.sort((a,b)=>a.s-b.s)`。
static func stable_sort_by_s(a: Array) -> void:
	stable_sort_by(a, &"s")


static func _cmp_keyed(p: Array, q: Array) -> bool:
	var pk: float = p[0]
	var qk: float = q[0]
	if pk != qk:
		return pk < qk
	var pi: int = p[1]
	var qi: int = q[1]
	return pi < qi


## Number.prototype.toFixed(d)，d ∈ [0, 20]，与 V8 逐字一致。
## ECMA-262：取使 n/10^d − x 最接近 0 的整数 n（按 x 的二进制真值精确计算），平局取较大的 n。
## 4.5.1 实测 Godot 的 "%.*f" 不是按真值舍入的（1.45 → "1.5"，JS 是 "1.4"；1.7976931348623157e20 的整数位也不精确），
## 所以这里用小型大整数做精确运算：x = m·2^e，n = round_half_up(m·10^d·2^e)。
static func to_fixed(x: float, d: int) -> String:
	if is_nan(x):
		return "NaN"
	if is_inf(x):
		return "Infinity" if x > 0.0 else "-Infinity"
	if absf(x) >= 1e21:
		return num_str(x)
	var neg: bool = x < 0.0
	var b: PackedByteArray = PackedByteArray()
	b.resize(8)
	b.encode_double(0, absf(x))
	var bits: int = b.decode_s64(0)
	var ex: int = (bits >> 52) & 0x7FF
	var mant: int = bits & ((1 << 52) - 1)
	var e: int = -1074
	if ex != 0:
		mant |= 1 << 52
		e = ex - 1075
	var big: PackedInt64Array = _big_from(mant)
	for i: int in d:
		big = _big_mul_small(big, 10)
	if e >= 0:
		big = _big_shl(big, e)
	else:
		# 余数 ≥ 一半（含恰好一半的平局）→ 进一，正是"最接近、平局取大"
		var up: bool = _big_bit(big, -e - 1)
		big = _big_shr(big, -e)
		if up:
			big = _big_add_small(big, 1)
	var digits: String = _big_to_dec(big)
	if d > 0:
		if digits.length() <= d:
			digits = "0".repeat(d + 1 - digits.length()) + digits
		digits = digits.substr(0, digits.length() - d) + "." + digits.substr(digits.length() - d)
	# JS：负数先对绝对值取整再补负号，所以 (-0.001).toFixed(2) === "-0.00"；-0 不算负数
	return ("-" + digits) if neg else digits


## 十进制数字串 → double，正确舍入（与 JS Number(s)、V8 JSON.parse 逐位一致）。
## 4.5.1 实测 String.to_float / JSON.parse_string 只有 ≤ 12 位有效数字时才精确：13–17 位的串约 5%–40% 差 1–数 ulp
## （例：网页 JSON 里的 0.9500000000000001 读成 0.95）。golden 和内容里凡是需要逐位相等的数都必须走这里（JsonExact 自动处理）。
## 做法：先用 to_float 得到近似值，再用精确的大整数比较把它挪到离真值最近（平局取偶）的那个 double。
static func parse_num(s: String) -> float:
	var t: String = s.strip_edges()
	var neg: bool = t.begins_with("-")
	if neg or t.begins_with("+"):
		t = t.substr(1)
	var y: float = t.to_float()
	if is_inf(y) or is_nan(y):
		return -y if neg else y
	# 拆成 整数 D（全部有效数字）与十进制指数 E：值 = D·10^E
	var mant: String = t
	var exp10: int = 0
	var epos: int = t.findn("e")
	if epos >= 0:
		mant = t.substr(0, epos)
		exp10 = t.substr(epos + 1).to_int()
	var dot: int = mant.find(".")
	if dot >= 0:
		exp10 -= mant.length() - dot - 1
		mant = mant.substr(0, dot) + mant.substr(dot + 1)
	mant = mant.lstrip("0")
	if mant == "":
		return -0.0 if neg else 0.0
	if mant.length() <= 12 and absi(exp10) <= 22:
		# 实测：≤ 12 位有效数字时 to_float 已经正确舍入，省掉大整数运算
		return -y if neg else y
	var dbig: PackedInt64Array = _big_from_dec(mant)
	# 初值：to_float 对很小/很大的数可能差上千 ulp，改用 整数尾数 × 10 的幂（误差几个 ulp），再逐格修正
	var head: String = mant.substr(0, 18)
	var e_head: int = exp10 + (mant.length() - head.length())
	y = float(head.to_int())
	while e_head > 0:
		var k: int = mini(e_head, 22)
		y *= pow(10.0, float(k))
		e_head -= k
	while e_head < 0:
		var k: int = mini(-e_head, 22)
		y /= pow(10.0, float(k))
		e_head += k
	if is_inf(y) or y == 0.0:
		y = t.to_float()
	var b: PackedByteArray = PackedByteArray()
	b.resize(8)
	b.encode_double(0, y)
	var bits: int = b.decode_s64(0)
	for _i: int in 64:
		var me: Array[int] = _bits_me(bits)
		var m: int = me[0]
		var e: int = me[1]
		var odd: bool = (m & 1) == 1
		# 上中点：下一个 double 总是 (m+1)·2^e（跨阶时也成立），所以中点是 (2m+1)·2^(e-1)。
		# 真值超过它（或恰在中点且 m 为奇，按"平局取偶"）就往上挪一格
		var r_up: int = _cmp_dec_bin(dbig, exp10, m * 2 + 1, e - 1)
		if r_up > 0 or (r_up == 0 and odd):
			bits += 1
			continue
		if bits > 0:
			var lo_m: Array[int] = _bits_me(bits - 1)
			var r_lo: int
			if lo_m[1] == e:
				r_lo = _cmp_dec_bin(dbig, exp10, m * 2 - 1, e - 1)
			else:
				# 下一个更小的数阶更低（m 是 2^52）：中点 = (4m-1)·2^(e-2)
				r_lo = _cmp_dec_bin(dbig, exp10, m * 4 - 1, e - 2)
			if r_lo < 0 or (r_lo == 0 and odd):
				bits -= 1
				continue
		break
	b.encode_s64(0, bits)
	var out: float = b.decode_double(0)
	return -out if neg else out


## double 的位模式 → [整数尾数 m（含隐含位）, 二进制指数 e]，值 = m·2^e。
static func _bits_me(bits: int) -> Array[int]:
	var ex: int = (bits >> 52) & 0x7FF
	var m: int = bits & ((1 << 52) - 1)
	if ex == 0:
		return [m, -1074]
	return [m | (1 << 52), ex - 1075]


## 比较 D·10^E 与 N·2^f（N ≥ 0 小整数）：返回 -1 / 0 / 1。
static func _cmp_dec_bin(dbig: PackedInt64Array, e10: int, n: int, f: int) -> int:
	var left: PackedInt64Array = dbig
	var right: PackedInt64Array = _big_from(n)
	if e10 > 0:
		left = _big_mul_pow10(left, e10)
	elif e10 < 0:
		right = _big_mul_pow10(right, -e10)
	if f > 0:
		right = _big_shl(right, f)
	elif f < 0:
		left = _big_shl(left, -f)
	return _big_cmp(left, right)


# —— to_fixed / parse_num 用的小型无符号大整数：小端 2^24 进制分段（乘小整数、移位、转十进制都不会溢出 int64）——
const _LB: int = 24
const _LMASK: int = (1 << 24) - 1


static func _big_from(v: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	while v > 0:
		a.append(v & _LMASK)
		v >>= _LB
	return a


## 十进制数字串（只含 0-9）→ 大整数；每 6 位一组乘 10^6 再加。
static func _big_from_dec(digits: String) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	var i: int = 0
	var n: int = digits.length()
	var first: int = n % 6
	if first == 0:
		first = 6
	while i < n:
		var w: int = first if i == 0 else 6
		var chunk: int = digits.substr(i, w).to_int()
		a = _big_add_small(_big_mul_small(a, int(pow(10.0, float(w)))), chunk)
		i += w
	return a


static func _big_mul_pow10(a: PackedInt64Array, k: int) -> PackedInt64Array:
	var out: PackedInt64Array = a
	while k >= 6:
		out = _big_mul_small(out, 1000000)
		k -= 6
	if k > 0:
		out = _big_mul_small(out, int(pow(10.0, float(k))))
	return out


static func _big_cmp(a: PackedInt64Array, b: PackedInt64Array) -> int:
	var na: int = a.size()
	var nb: int = b.size()
	while na > 0 and a[na - 1] == 0:
		na -= 1
	while nb > 0 and b[nb - 1] == 0:
		nb -= 1
	if na != nb:
		return 1 if na > nb else -1
	for i: int in range(na - 1, -1, -1):
		if a[i] != b[i]:
			return 1 if a[i] > b[i] else -1
	return 0


static func _big_mul_small(a: PackedInt64Array, k: int) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	var carry: int = 0
	for limb: int in a:
		var t: int = limb * k + carry
		out.append(t & _LMASK)
		carry = t >> _LB
	while carry > 0:
		out.append(carry & _LMASK)
		carry >>= _LB
	return out


static func _big_add_small(a: PackedInt64Array, k: int) -> PackedInt64Array:
	var out: PackedInt64Array = a.duplicate()
	var carry: int = k
	var i: int = 0
	while carry > 0:
		if i == out.size():
			out.append(0)
		var t: int = out[i] + carry
		out[i] = t & _LMASK
		carry = t >> _LB
		i += 1
	return out


@warning_ignore("integer_division")
static func _big_shl(a: PackedInt64Array, s: int) -> PackedInt64Array:
	if a.is_empty():
		return a
	var q: int = s / _LB
	var r: int = s % _LB
	var out: PackedInt64Array = PackedInt64Array()
	for i: int in q:
		out.append(0)
	var carry: int = 0
	for limb: int in a:
		var t: int = (limb << r) | carry
		out.append(t & _LMASK)
		carry = t >> _LB
	if carry > 0:
		out.append(carry)
	return out


@warning_ignore("integer_division")
static func _big_shr(a: PackedInt64Array, s: int) -> PackedInt64Array:
	var q: int = s / _LB
	var r: int = s % _LB
	var out: PackedInt64Array = PackedInt64Array()
	for i: int in range(q, a.size()):
		var lo: int = a[i] >> r
		var hi: int = (a[i + 1] << (_LB - r)) & _LMASK if i + 1 < a.size() and r > 0 else 0
		out.append(lo | hi)
	while not out.is_empty() and out[out.size() - 1] == 0:
		out.remove_at(out.size() - 1)
	return out


@warning_ignore("integer_division")
static func _big_bit(a: PackedInt64Array, k: int) -> bool:
	if k < 0:
		return false
	var i: int = k / _LB
	if i >= a.size():
		return false
	return ((a[i] >> (k % _LB)) & 1) == 1


@warning_ignore("integer_division")
static func _big_to_dec(a: PackedInt64Array) -> String:
	if a.is_empty():
		return "0"
	var cur: PackedInt64Array = a.duplicate()
	var chunks: PackedStringArray = []
	while not cur.is_empty():
		# 除以 10^6，自高位向低位
		var rem: int = 0
		for i: int in range(cur.size() - 1, -1, -1):
			var t: int = (rem << _LB) | cur[i]
			cur[i] = t / 1000000
			rem = t % 1000000
		while not cur.is_empty() and cur[cur.size() - 1] == 0:
			cur.remove_at(cur.size() - 1)
		chunks.append(str(rem))
	var s: String = chunks[chunks.size() - 1]
	for i: int in range(chunks.size() - 2, -1, -1):
		s += chunks[i].pad_zeros(6)
	return s


## JS 的 String(x)（Number::toString）：最短往返数字串；1e-6 ≤ |x| < 1e21 用定点写法，否则指数写法（1e-7、1.5e+21）。
## 最短数字串取自 String.num_scientific（4.5.1 实测为最短往返），这里只把它改写成 JS 的排版。
static func num_str(x: float) -> String:
	if is_nan(x):
		return "NaN"
	if is_inf(x):
		return "Infinity" if x > 0.0 else "-Infinity"
	if x == 0.0:
		return "0"
	var neg: bool = x < 0.0
	var sci: String = String.num_scientific(absf(x))
	# 拆成 数字串 digits 和十进制指数 e（值 = 0.d1d2… × 10^e，与 ECMA-262 Number::toString 的 n 相同）
	var mant: String = sci
	var exp10: int = 0
	var epos: int = sci.find("e")
	if epos >= 0:
		mant = sci.substr(0, epos)
		exp10 = sci.substr(epos + 1).to_int()
	var dot: int = mant.find(".")
	var int_part: String = mant if dot < 0 else mant.substr(0, dot)
	var frac_part: String = "" if dot < 0 else mant.substr(dot + 1)
	var digits: String = (int_part + frac_part).lstrip("0")
	var n: int = int_part.lstrip("0").length() + exp10
	if int_part.lstrip("0") == "":
		# 0.00ddd 形式：前导零要从指数里扣掉
		var lead: int = frac_part.length() - frac_part.lstrip("0").length()
		n = exp10 - lead
	digits = digits.rstrip("0")
	if digits == "":
		return "0"
	var k: int = digits.length()
	var s: String
	if k <= n and n <= 21:
		s = digits + "0".repeat(n - k)
	elif 0 < n and n <= 21:
		s = digits.substr(0, n) + "." + digits.substr(n)
	elif -6 < n and n <= 0:
		s = "0." + "0".repeat(-n) + digits
	else:
		var e: int = n - 1
		var es: String = ("+" if e >= 0 else "-") + str(absi(e))
		s = digits.substr(0, 1) + ("." + digits.substr(1) if k > 1 else "") + "e" + es
	return ("-" + s) if neg else s


## Number.prototype.toLocaleString('en-US') 的整数部分：千分位逗号。只用于整数（调用方先 floor/round）。
static func group_int(n: float) -> String:
	var neg: bool = n < 0.0
	var digits: String = "%.0f" % absf(n)
	var out: String = ""
	var cnt: int = 0
	for i: int in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if neg and out != "0" else out
