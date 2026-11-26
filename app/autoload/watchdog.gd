extends Node
## autoload `Watchdog`（开发用）：命令行带 --autoplay（自动驾驶 / 压力测试 / 录清单）时，真实时间超过 --max-seconds（默认 900 秒）
## 还没结束就强制退出（返回码 3）。2026-10-16：代码改到一半时启动的自动驾驶会卡在灰屏——main 或 HUD 脚本编译 / 初始化失败，
## 自动驾驶本身都没建出来，进程就一直挂着。这里不引用任何游戏脚本，别的脚本坏了它照样能工作。正常游戏（不带 --autoplay）什么都不做。

const DEFAULT_SECONDS: float = 900.0


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--autoplay"):
		set_process(false)
		return
	var sec: float = DEFAULT_SECONDS
	for a: String in args:
		if a.begins_with("--max-seconds="):
			sec = maxf(10.0, float(a.substr(14)))
	var t: SceneTreeTimer = get_tree().create_timer(sec, true, false, true)
	t.timeout.connect(func() -> void:
		push_error("[watchdog] 自动驾驶超过 %d 秒没结束（可能卡在灰屏），强制退出" % int(sec))
		get_tree().quit(3)
		)
