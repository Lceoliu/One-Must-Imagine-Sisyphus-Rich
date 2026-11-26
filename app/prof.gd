class_name Prof
extends RefCounted
## 开发用分段计时（放 app/ 不放 core/：要读真实时间，core 按分层规则不许碰 Time）（默认关，性能测量脚本里 Prof.on = true 打开）：
##   var t0: int = Prof.t()   …   Prof.add(&"名字", t0)
## 累加每段的微秒数和次数；关着时 t() 返回 0、add() 直接返回，热路径上只多一次布尔判断。

static var on: bool = false
static var acc: Dictionary = {}
static var cnt: Dictionary = {}


static func t() -> int:
	return Time.get_ticks_usec() if on else 0


static func add(k: StringName, t0: int) -> void:
	if not on:
		return
	acc[k] = int(acc.get(k, 0)) + (Time.get_ticks_usec() - t0)
	cnt[k] = int(cnt.get(k, 0)) + 1


static func reset() -> void:
	acc.clear()
	cnt.clear()


## 每帧平均毫秒（按 frames 帧摊），从大到小
static func report(frames: int) -> String:
	var keys: Array = acc.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(acc[a]) > int(acc[b]))
	var out: PackedStringArray = []
	for k: Variant in keys:
		out.append("%s=%.2fms(%d次)" % [str(k), float(acc[k]) / 1000.0 / maxf(1.0, frames), int(cnt[k])])
	return "  ".join(out)


## 启动计时（命令行带 --boot-times 时打印，从进程启动算起的毫秒数）
static var _boot: int = -1


static func mark(label: String) -> void:
	if _boot < 0:
		_boot = 1 if OS.get_cmdline_user_args().has("--boot-times") else 0
	if _boot == 1:
		print("[boot] %6d ms  %s" % [Time.get_ticks_msec(), label])
