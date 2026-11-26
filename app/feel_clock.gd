class_name FeelClock
extends RefCounted
## 手感时钟（= 网页 fx.js 的 time）：顿帧冻结模拟、慢动作降低模拟速率。只决定"每秒真实时间跑多少模拟时间"，
## 不改模拟步长，所以开关手感不影响任何结果。

var feel_gain: float = 1.0
var hitstop: float = 0.0
var slow: float = 1.0
var slow_hold: float = 0.0
var slow_from: float = 1.0
var slow_recover: float = 0.3
var recover_t: float = 0.0


func hit(ms: float) -> void:
	hitstop = maxf(hitstop, (ms / 1000.0) * feel_gain)


func slowmo(factor: float, hold: float, recover: float = 0.3) -> void:
	if feel_gain <= 0.0:
		return
	if slow_hold > 0.0 and factor >= slow:
		slow_hold = maxf(slow_hold, hold)
		return
	slow = factor
	slow_from = factor
	slow_hold = hold
	slow_recover = recover
	recover_t = 0.0


func reset() -> void:
	hitstop = 0.0
	slow = 1.0
	slow_hold = 0.0


## 返回本帧的模拟速率（0 = 顿帧，0.2–1 = 慢放）
func step(dt: float) -> float:
	if hitstop > 0.0:
		hitstop -= dt
		return 0.0
	if slow_hold > 0.0:
		slow_hold -= dt
	elif slow < 1.0:
		recover_t += dt
		var k: float = minf(1.0, recover_t / slow_recover)
		slow = slow_from + (1.0 - slow_from) * (1.0 - pow(1.0 - k, 3.0))
	return slow
