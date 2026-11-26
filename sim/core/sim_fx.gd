class_name SimFx
extends RefCounted
## 规则代码发出表现事件的唯一通道（= 网页 this.fx.* / S() / time.* / shake / cam.punch / showBanner / flash）。
## enabled = false 时全部是空操作（机器人、无头测试）。方法名照搬网页，移植时机械替换。

const GOLD: Color = Color("f0b93a")
const GOLD_HI: Color = Color("ffe08a")
const CREAM: Color = Color("f1e3c8")

var enabled: bool = true
var _buf: Array[SimEvent] = []


func _ev(kind: StringName) -> SimEvent:
	var e: SimEvent = SimEvent.new()
	e.kind = kind
	_buf.append(e)
	return e


func drain() -> Array[SimEvent]:
	var out: Array[SimEvent] = _buf
	_buf = []
	return out


# —— 粒子与飘字（世界坐标，米）——
func text(x: float, y: float, s: String, size: float, color: Color = GOLD_HI, life: float = 1.1) -> void:
	if not enabled: return
	var e: SimEvent = _ev(&"text"); e.x = x; e.y = y; e.text = s; e.a = size; e.b = life; e.color = color


func dust(x: float, y: float, n: int, size: float, speed: float) -> void:
	if not enabled: return
	var e: SimEvent = _ev(&"dust"); e.x = x; e.y = y; e.a = n; e.b = size; e.c = speed


func shards(x: float, y: float, n: float, speed: float, size: float) -> void:
	if not enabled: return
	var e: SimEvent = _ev(&"shards"); e.x = x; e.y = y; e.a = n; e.b = speed; e.c = size


func sparks(x: float, y: float, n: float, speed: float) -> void:
	if not enabled: return
	var e: SimEvent = _ev(&"sparks"); e.x = x; e.y = y; e.a = n; e.b = speed


## max_h_frac：屏幕空间半径上限（占屏高的比例，0 = 不限；网页 opt.maxPx = 比例 × 屏高）
func ring(x: float, y: float, r0: float, r1: float, life: float, color: Color, width: float = 3.0, max_h_frac: float = 0.0) -> void:
	if not enabled: return
	var e: SimEvent = _ev(&"ring"); e.x = x; e.y = y; e.a = r0; e.b = r1; e.c = life; e.color = color; e.d = width
	e.data = {"max_h_frac": max_h_frac}


## 看得见的金币（数值已经记账，表现层只负责飞和吸附）
func burst(x: float, y: float, value: float, tier: int, big: bool, type: StringName, gold: bool = false) -> void:
	if not enabled: return
	var e: SimEvent = _ev(&"burst"); e.x = x; e.y = y; e.a = value; e.b = tier; e.name = type
	e.data = {"big": big, "gold": gold}


## 纯装饰金币（网页 fx.coins）
func coins(x: float, y: float, n: int, value: float = 0.0) -> void:
	if not enabled: return
	var e: SimEvent = _ev(&"coins"); e.x = x; e.y = y; e.a = n; e.b = value


func flyer(type: StringName, x: float, y: float, w: float, h: float, vx: float, vy: float) -> void:
	if not enabled: return
	var e: SimEvent = _ev(&"flyer"); e.name = type; e.x = x; e.y = y; e.a = w; e.b = h; e.c = vx; e.d = vy


func smoke(x: float, y: float, n: int = 1) -> void:
	if not enabled: return
	var e: SimEvent = _ev(&"smoke"); e.x = x; e.y = y; e.a = n


# —— 声音 ——
func sfx(name: StringName, a: float = 0.0, b: float = 0.0) -> void:
	if not enabled: return
	var e: SimEvent = _ev(&"sfx"); e.name = name; e.a = a; e.b = b


# —— 手感 ——
## 顿帧（毫秒）：FeelClock 冻结模拟
func hit(ms: float) -> void:
	if not enabled: return
	var e: SimEvent = _ev(&"hit"); e.a = ms


## 慢动作：factor 速率、hold 保持秒数、recover 恢复秒数
func slowmo(factor: float, hold: float, recover: float = 0.3) -> void:
	if not enabled: return
	var e: SimEvent = _ev(&"slowmo"); e.a = factor; e.b = hold; e.c = recover


func shake(a: float) -> void:
	if not enabled: return
	var e: SimEvent = _ev(&"shake"); e.a = a


## 镜头冲击（正 = 推近，负 = 拉远；网页 cam.punch）。只保留更大的那一个。
func punch(v: float, keep_max: bool = false) -> void:
	if not enabled: return
	var e: SimEvent = _ev(&"punch"); e.a = v; e.b = 1.0 if keep_max else 0.0


## 闪光：a 透明度（封顶 0.4），at_x/at_y 给出世界坐标时画径向光
func flash(a: float, color: Color, at_x: float = NAN, at_y: float = NAN) -> void:
	if not enabled: return
	var e: SimEvent = _ev(&"flash"); e.a = minf(a, 0.4); e.color = color; e.x = at_x; e.y = at_y


## 横幅：y_frac 占屏高的位置（NAN = 默认），size 字号（0 = 默认）
func banner(text_s: String, sub_s: String = "", life: float = 2.0, y_frac: float = NAN, size: float = 0.0) -> void:
	if not enabled: return
	var e: SimEvent = _ev(&"banner"); e.text = text_s; e.sub = sub_s; e.a = life; e.b = y_frac; e.c = size


## 屏幕中间的一行提示（HudView 的 toasts，几秒后淡出）
func toast(text_s: String, life: float = 3.2, color: Color = CREAM) -> void:
	if not enabled: return
	var e: SimEvent = _ev(&"toast"); e.data = {"text": text_s, "life": life, "color": color}


## 通用事件（模块演出、阶段切换、碾压记录等）
func event(kind: StringName, data: Dictionary = {}, x: float = 0.0, y: float = 0.0) -> void:
	if not enabled: return
	var e: SimEvent = _ev(kind); e.data = data; e.x = x; e.y = y
