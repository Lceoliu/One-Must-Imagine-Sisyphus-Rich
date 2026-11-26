class_name SaveService
extends RefCounted
## 存档：user://save/run.json（本代）与 user://save/meta.json（跨代）。写入先写 .tmp 再改名，并保留上一份 .bak。
## memory = true 时只存在内存里（测试、机器人用），绝不碰磁盘。

const DIR: String = "user://save"
const RUN: String = "user://save/run.json"
const META: String = "user://save/meta.json"

## 写盘成功（内存存档不发）：main 据此闪一下"已自动保存"
signal saved

var memory: bool = false
var _mem: Dictionary = {}
## 读档时出的问题（主菜单读到后提示玩家一次，然后清空）；空 = 没问题
var problem: String = ""


func _init(p_memory: bool = false) -> void:
	memory = p_memory


## 2026-11-24 itch 上的英文单独包把存档放在 %APPDATA%\Sisyphus-en。现在中英文合成一个包、只用 Sisyphus：
## 这边还没有存档、那边有的话，复制过来（连同 settings.cfg，保住玩家选的英文）。只复制不删，那边原样留着。
## Settings 启动时（读设置之前）调一次；内存模式（测试、工具）不调。返回复制了几个文件。
static func import_legacy_en() -> int:
	var here: String = ProjectSettings.globalize_path("user://").trim_suffix("/").trim_suffix("\\")
	var old: String = here.get_base_dir().path_join("Sisyphus-en")
	if not DirAccess.dir_exists_absolute(old.path_join("save")):
		return 0
	if FileAccess.file_exists(META) or FileAccess.file_exists(RUN):
		return 0
	var n: int = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	for f: String in ["meta.json", "meta.json.bak", "run.json", "run.json.bak"]:
		var src: String = old.path_join("save").path_join(f)
		if FileAccess.file_exists(src) and DirAccess.copy_absolute(src, ProjectSettings.globalize_path(DIR).path_join(f)) == OK:
			n += 1
	var cfg: String = old.path_join("settings.cfg")
	if n > 0 and FileAccess.file_exists(cfg) and not FileAccess.file_exists("user://settings.cfg"):
		if DirAccess.copy_absolute(cfg, ProjectSettings.globalize_path("user://settings.cfg")) == OK:
			n += 1
	if n > 0:
		print("[save] 从 %s 复制了 %d 个文件（英文单独包的旧存档）" % [old, n])
	return n


func has_run() -> bool:
	if memory:
		return _mem.has(RUN)
	return FileAccess.file_exists(RUN)


func load_run() -> Dictionary:
	return _read(RUN)


func load_meta() -> Dictionary:
	return _read(META)


func save_run(d: Dictionary) -> void:
	_write(RUN, d)


func save_meta(d: Dictionary) -> void:
	_write(META, d)


## "重新开始"：只清本代存档，保留元进度
func clear_run() -> void:
	if memory:
		_mem.erase(RUN)
		return
	if FileAccess.file_exists(RUN):
		DirAccess.rename_absolute(RUN, RUN + ".bak")


func _read(path: String) -> Dictionary:
	if memory:
		return (_mem.get(path, {}) as Dictionary).duplicate(true)
	if not FileAccess.file_exists(path):
		return {}
	var v: Variant = JsonExact.load_file(path)
	if v is Dictionary:
		return _migrate(path, v)
	# 读坏了：试一下备份
	if FileAccess.file_exists(path + ".bak"):
		var b: Variant = JsonExact.load_file(path + ".bak")
		if b is Dictionary:
			problem = Loc.t("save_service.couldn_t_read_save", "存档读取失败，已换用上一份备份，可能少了最近一点进度。")
			return _migrate(path, b)
	# 正式档和备份都坏了：改名留着（别被下一次存档覆盖），告诉玩家文件在哪，这次从新档开始
	var keep: String = "%s.corrupt-%d.json" % [path.get_basename(), int(Time.get_unix_time_from_system())]
	DirAccess.rename_absolute(path, keep)
	problem = Loc.t("save_service.save_corrupt", "存档损坏，读不出来。原文件已另存为：\n%s\n这次从新档开始；反馈问题时请附上这个文件。") % ProjectSettings.globalize_path(keep)
	push_error("存档损坏：%s → %s" % [path, keep])
	return {}


## 存档版本迁移的入口：EA 期间存档格式改了，就在这里把旧档升级成新格式（本代存档 v4、元进度 v1 时原样返回）
func _migrate(_path: String, d: Dictionary) -> Dictionary:
	return d


func _write(path: String, d: Dictionary) -> void:
	if memory:
		_mem[path] = d.duplicate(true)
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("存档写入失败：%s" % tmp)
		return
	f.store_string(JSON.stringify(d, "\t", true, true))
	f.close()
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(path + ".bak")
		DirAccess.rename_absolute(path, path + ".bak")
	if DirAccess.rename_absolute(tmp, path) == OK:
		saved.emit()
