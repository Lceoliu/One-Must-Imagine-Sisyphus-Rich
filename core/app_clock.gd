class_name AppClock
## 真实时间（architecture §4.1）：镜头平滑、震屏、横幅、UI 动画、封印逐枚点亮等表现层计时都读这里。
## 只给表现层和 app 用；sim 不准读（lint 把 core/app_clock.gd 列为例外，但 sim/ 里引用 AppClock 仍按规则禁止 Time./OS.）。
## 截图和录像时设 fixed_dt = 1/60，让每帧推进固定量，画面可复现（§18.5）。

static var real_t: float = 0.0          ## 累计真实秒数
static var frame: int = 0               ## advance 调用次数
static var fixed_dt: float = -1.0       ## ≥ 0 时忽略传入的 real_dt，每帧固定推进这么多


## 由 SimRunner._process 每帧调用一次；返回实际推进量。
static func advance(real_dt: float) -> float:
	var dt: float = fixed_dt if fixed_dt >= 0.0 else real_dt
	real_t += dt
	frame += 1
	return dt


## 墙钟毫秒（UI 防误触等需要绝对时间的地方用）；fixed 模式下按 real_t 折算，保证截图可复现。
static func now_ms() -> int:
	if fixed_dt >= 0.0:
		return int(real_t * 1000.0)
	return Time.get_ticks_msec()


static func reset() -> void:
	real_t = 0.0
	frame = 0
	fixed_dt = -1.0
