class_name BetOdds
extends RefCounted
## 提喀的高度盘（docs/v05/feast-hub.md §4.3）：明天能推多高的对数正态模型 → 达成概率 → 赔率。纯函数。
## μ = 影子推演的机器人高度 H_bot × 玩家效率 e；e = 最近 5 天 A_d / H_bot_d 的第 75 百分位（不足 2 天 0.85）；
## s = ln e_d 的标准差和先验 0.15 加权混合，夹到 [0.08, 0.25]。
## 赔率 = (1 − 抽水 8%) / P(H) × (H 高于金线时 1.10) × 纪录附近的折扣；只开 1.05–25 的高度；截到两位小数。
## 纪录附近的折扣（用户 2026-10-15：赌本改成任意比例后，纪录附近押得最稳，略调低）：在纪录处 −10%，按高斯往两边消失（宽度 = 纪录的 6%）。

const VIG: float = 0.08
const GOLD_BONUS: float = 1.10
const ODDS_MIN: float = 1.05
const ODDS_MAX: float = 25.0
const NEAR_DIP: float = 0.10
const NEAR_W: float = 0.06
const E_DEFAULT: float = 0.85
const S_PRIOR: float = 0.15
const HIST_N: int = 5


## hist：[[H_bot, 实际], ...]（旧 → 新）；返回 {e, s, mu}
static func model(h_bot: float, hist: Array) -> Dictionary:
	var es: Array[float] = []
	for p: Variant in hist.slice(maxi(0, hist.size() - HIST_N)):
		var a: Array = p
		if a.size() >= 2 and float(a[0]) > 0.0 and float(a[1]) > 0.0:
			es.append(float(a[1]) / float(a[0]))
	var e: float = E_DEFAULT
	if es.size() >= 2:
		var sorted: Array[float] = es.duplicate()
		sorted.sort()
		e = _pct(sorted, 0.75)
	var n: int = es.size()
	var var_l: float = 0.0
	if n >= 2:
		var mean: float = 0.0
		for x: float in es:
			mean += log(x)
		mean /= n
		for x: float in es:
			var_l += pow(log(x) - mean, 2.0)
		var_l /= n - 1
	var s: float = clampf(sqrt((n * var_l + 3.0 * S_PRIOR * S_PRIOR) / (n + 3.0)), 0.08, 0.25)
	return {"e": e, "s": s, "mu": h_bot * e}


static func _pct(sorted: Array[float], q: float) -> float:
	if sorted.is_empty():
		return E_DEFAULT
	var i: float = q * (sorted.size() - 1)
	var lo: int = int(floorf(i))
	var hi: int = mini(lo + 1, sorted.size() - 1)
	return lerpf(sorted[lo], sorted[hi], i - lo)


## 明天最高海拔 ≥ h 的概率
static func p_reach(h: float, mu: float, s: float) -> float:
	if mu <= 0.0 or h <= 0.0:
		return 0.0
	return 1.0 - phi(log(h / mu) / s)


## 赔率（不开盘时返回 0）。floor：明天的起点海拔（纪录 × 新纺的线），不到它的高度必中，不开；山顶以上推不到，不开
static func odds(h: float, mu: float, s: float, gold_line: float, floor: float = 0.0) -> float:
	if h <= floor * 1.02 + 1.0 or h > World.SUMMIT - 0.5:
		return 0.0
	var p: float = p_reach(h, mu, s)
	if p <= 0.0:
		return 0.0
	var o: float = (1.0 - VIG) / p * (GOLD_BONUS if h > gold_line else 1.0) * near_dip(h, gold_line)
	o = floorf(o * 100.0) / 100.0
	return o if o >= ODDS_MIN and o <= ODDS_MAX else 0.0


## 纪录附近的赔率系数（纪录处 1 − NEAR_DIP，远处 1）
static func near_dip(h: float, gold_line: float) -> float:
	if gold_line <= 0.0:
		return 1.0
	return 1.0 - NEAR_DIP * exp(-pow((h - gold_line) / maxf(1.0, NEAR_W * gold_line), 2.0))


## 开盘的高度区间 [lo, hi]（整米）：赔率在 1.05–25 之间的那一段；不开盘时 [-1, -1]
static func open_range(mu: float, s: float, gold_line: float, floor: float = 0.0) -> Array[int]:
	var lo: int = -1
	var hi: int = -1
	var h0: int = maxi(1, int(mu * 0.4))
	var h1: int = mini(int(mu * 2.5) + 2, int(World.SUMMIT))
	for h: int in range(h0, h1):
		if odds(float(h), mu, s, gold_line, floor) > 0.0:
			if lo < 0:
				lo = h
			hi = h
	return [lo, hi]


## 达成概率为 p 的高度（众神的筹码钉在这里）
static func height_at(p: float, mu: float, s: float) -> float:
	return mu * exp(s * inv_phi(1.0 - clampf(p, 0.001, 0.999)))


## 标准正态分布函数（Abramowitz–Stegun 7.1.26，误差 < 1.5e-7）
static func phi(x: float) -> float:
	var t: float = 1.0 / (1.0 + 0.3275911 * absf(x) / sqrt(2.0))
	var y: float = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-x * x / 2.0)
	return 0.5 * (1.0 + (y if x >= 0.0 else -y))


## 反函数（二分，够用）
static func inv_phi(p: float) -> float:
	var lo: float = -8.0
	var hi: float = 8.0
	for i: int in 60:
		var m: float = (lo + hi) / 2.0
		if phi(m) < p:
			lo = m
		else:
			hi = m
	return (lo + hi) / 2.0
