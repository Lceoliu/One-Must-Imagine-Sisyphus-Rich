class_name SimRandom
extends RefCounted
## 影响经济的随机（网页 Math.random 的 4 处：打滑、城市连升、葡萄藤、宝瓶）按"局种子 × 天 × 用途"分流，可复现。
## 只影响外观的随机（粘附角度等）用 COSMETIC 流。const_k ≥ 0 时所有用途都返回常数（对拍模式）。

enum Use { SLIP, CITY, VINE, CHEST, COSMETIC, MISC }

var run_seed: int = 1
var const_k: float = -1.0
var _day: int = 0
var _streams: Dictionary = {}


func begin_day(day: int) -> void:
	_day = day
	_streams.clear()


func next(use: Use) -> float:
	if const_k >= 0.0:
		return const_k
	var r: JsRng = _streams.get(use)
	if r == null:
		var seed: int = Js.imul(run_seed, 0x9E3779B1) ^ Js.to_u32(float(_day * 104729 + int(use) * 7919 + 97))
		r = JsRng.new(float(Js.to_u32(float(seed))))
		_streams[use] = r
	return r.next()
