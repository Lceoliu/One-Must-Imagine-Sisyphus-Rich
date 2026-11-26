class_name AutoPusher
extends RefCounted
## 设置里的"自动推石"：白天替玩家按头顶陶片交替按左右，和真人按键走同一条路（SimGame.key_down / key_up），
## 所以节奏层数、体力、累倒都照常。间隔按模拟时间算（开了加速也不会乱拍），且不短于节奏窗口下限 rhythm_lo（0.18 秒），
## 否则节奏层数会被打断。实测（tests/tools/autopush_rates.gd）窗口内按得越快推得越高：5 次/秒第一天约 42 米，和最好的手动节奏持平。
## 有"双掌"（hold_push）时改成一直按住右推。不在白天、有面板、放结局时松开。

## 次/秒
var rate: float = 5.0
var _acc: float = 0.0
var _last_t: float = -1.0
var _holding: bool = false


func step(g: SimGame, on: bool) -> void:
	var active: bool = on and g != null and g.phase == &"day" and g.modal == null and not g.ending_active
	if not active:
		release(g)
		_acc = 0.0
		_last_t = -1.0
		return
	if g.stats.hold_push:
		if not _holding:
			g.key_down(&"R")
			_holding = true
		return
	if _holding:
		release(g)
	if _last_t < 0.0 or g.t < _last_t:
		_last_t = g.t
	_acc += g.t - _last_t
	_last_t = g.t
	var iv: float = maxf(1.0 / clampf(rate, 1.0, 8.0), g.stats.rhythm_lo + 0.004)
	if _acc >= iv:
		_acc = 0.0   # 每次从零计，间隔永远 ≥ iv（累计余数会让间隔偶尔短一拍、跌出节奏窗口）；卡顿之后也不连发
		var k: StringName = g.expect_key if (g.expect_key == &"L" or g.expect_key == &"R") else &"L"
		g.key_down(k)
		g.key_up(k)


func release(g: SimGame) -> void:
	if _holding and g != null:
		g.key_up(&"R")
	_holding = false
