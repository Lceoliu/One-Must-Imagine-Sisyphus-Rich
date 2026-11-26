extends Node
## autoload `Content`（architecture §3.2）：持有当前的 ContentDB 实例并负责热重载。
## 热重载 = 重新 ContentDB.load_dir → 新实例有错误时保留旧实例并报错 → 发 reloaded（GameSession 据此重算 stats、刷新模块）。
## 调试构建里按 F5 触发（architecture §5.6 的"只改 JSON 演练"就靠它）。
## sim 不准引用本 autoload；测试和机器人自己 ContentDB.load_dir()。

signal reloaded

const ROOT: String = "res://content"
## 发行配置（content/profiles/<id>.json）：默认按 EA 版裁剪；命令行 --profile=<id> 换一个，--profile=full = 完整内容（开发用）
const DEFAULT_PROFILE: String = "ea"

## 当前内容库（启动时加载；加载有错误时仍然可用，但 errors 非空，并已 push_error）
var db: ContentDB = null
## 最近一次加载 / 重载的错误
var last_errors: PackedStringArray = []


func _ready() -> void:
	Prof.mark("Content 开始")
	db = _load()
	Prof.mark("Content 完成")


func _load() -> ContentDB:
	var t0: int = Time.get_ticks_usec()
	var d: ContentDB = ContentDB.load_dir(ROOT)
	var prof: String = profile_id()
	if prof != "full":
		d.apply_profile(prof)
	last_errors = d.errors
	for e: String in d.errors:
		push_error("[content] " + e)
	print_verbose("[content] 加载 %d 个文件，%d 处错误，用时 %.1f ms" % [d.raw.size(), d.errors.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	return d


## 这次运行用哪份发行配置
static func profile_id() -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			return a.substr(10)
	return DEFAULT_PROFILE


## 重新读取内容。新内容有错误时不替换（保留旧的继续玩），返回是否替换成功。
func reload() -> bool:
	var d: ContentDB = _load()
	if not d.errors.is_empty() and db != null:
		push_warning("[content] 热重载有 %d 处错误，保留旧内容" % d.errors.size())
		return false
	db = d
	reloaded.emit()
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var k: InputEventKey = event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F5:
		if reload():
			print("[content] 已热重载内容")
		get_viewport().set_input_as_handled()
