class_name JsRng
extends RefCounted
## world.js:4 rng(seed)（mulberry32）的逐位移植。
## 所有中间量都保持在 [0, 2^32) 的 u32 表示，所以 `>>` 等价于 JS 的 `>>>`；与 JS 的 int32 表示只差符号解释，低 32 位完全相同。
## devbot.js:31 的 mulberry(a) 变体（首次调用时 a|=0）与本类同值：JsRng.new(seed * 2654435761 + 97)。

var _a: int


## seed 按 JS `seed >>> 0` 取 u32（可以传超过 2^32 的整数值浮点数）。
func _init(seed: float) -> void:
	_a = Js.to_u32(seed)


## 下一个 [0, 1) 的随机数，逐位等于网页 rng(seed)() 的返回值。
func next() -> float:
	_a = (_a + 0x6D2B79F5) & Js.M32
	var t: int = Js.imul(_a ^ (_a >> 15), 1 | _a)
	t = ((t + Js.imul(t ^ (t >> 7), 61 | t)) & Js.M32) ^ t
	return float((t ^ (t >> 14)) & Js.M32) / 4294967296.0


## 当前内部状态（u32），给对拍和测试快照用。
func state() -> int:
	return _a
