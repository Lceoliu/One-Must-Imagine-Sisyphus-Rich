class_name SimRunner
extends Node
## 唯一推进模拟的地方：固定步长 1/60，速率由 FeelClock 决定（顿帧时为 0、慢放时 <1）。
## 每拍取走 sim 的事件：顿帧/慢放交给 FeelClock，其余经 events 信号发给表现层。

signal events(list: Array[SimEvent])

const DT: float = 1.0 / 60.0
const MAX_TICKS: int = 8

var sim: SimGame = null
var feel: FeelClock = FeelClock.new()
var app_paused: bool = false
var dev_speed: float = 1.0
## 渲染插值 0..1
var alpha: float = 0.0
## 本帧模拟速率（表现层：粒子在顿帧时按 real_dt×0.15 推进）
var rate: float = 1.0
var _acc: float = 0.0


func _process(real_dt: float) -> void:
	if sim == null:
		return
	real_dt = minf(real_dt, 0.1)
	rate = 0.0 if app_paused else feel.step(real_dt) * dev_speed
	_acc += real_dt * rate
	var n: int = 0
	while _acc >= DT and n < MAX_TICKS:
		var _pt: int = Prof.t()
		sim.tick(DT)
		Prof.add(&"sim.tick", _pt)
		_acc -= DT
		n += 1
		_pt = Prof.t()
		_flush()
		Prof.add(&"sim.flush", _pt)
	if n == MAX_TICKS:
		_acc = 0.0
	# 模态 / 结局 / 结算等待时 sim 不推进，但输入可能产生事件（比如回答模态后的效果）
	if n == 0:
		_flush()
	alpha = clampf(_acc / DT, 0.0, 1.0)


func _flush() -> void:
	var ev: Array[SimEvent] = sim.fx.drain()
	if ev.is_empty():
		return
	feel.feel_gain = Settings.feel_strength
	for e: SimEvent in ev:
		if e.kind == &"hit":
			feel.hit(e.a)
		elif e.kind == &"slowmo":
			feel.slowmo(e.a, e.b, e.c)
	events.emit(ev)


func reset_feel() -> void:
	feel.reset()
	_acc = 0.0
