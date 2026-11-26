extends Node
## autoload `Settings`（architecture §3.2）：音量、画面（显示模式、窗口大小、垂直同步、帧率上限、画质、震屏、闪光）、键位、自动推石、
## 游戏（失焦暂停、操作提示）、调试控制台。apply_display() 把画面相关的设置交给引擎（启动时、设置界面改动时调用）。
## 读写 user://settings.cfg；设置界面在 present/ui/settings_screen.gd（主菜单和暂停菜单都能进）。
## 测试（命令行带 --test）或无头运行时只用内存，不读写磁盘。
## 键位：每个动作最多两个绑定，绑定是 {"k": keycode} 或 {"m": 鼠标键}；apply_bindings() 写进 Godot 的 InputMap，
## 游戏里一律用 is_action_pressed("push_left") 之类判断（Esc 固定为暂停，不可改）。

signal bindings_changed
## 画质细项变了（渲染分辨率、特效、背景、夜宴光影）：表现层各自重读
signal gfx_changed
## 界面语言切换完了（内容已按新语言重载）：主菜单等据此重建
signal locale_changed

const PATH: String = "user://settings.cfg"
const SLOTS: int = 2
## 动作（顺序 = 设置界面里的顺序）；显示名见 actions()
const ACTION_IDS: PackedStringArray = ["push_left", "push_right", "strike", "end_day", "interact", "overview", "console"]

var master_volume: float = 1.0
var sfx_volume: float = 1.0
var music_volume: float = 1.0
var amb_volume: float = 1.0
var shake_strength: float = 1.0      ## 震屏强度（网页调试面板的 shake）
var feel_strength: float = 1.0       ## 顿帧/慢放手感强度（0 = 关掉；app/feel_clock.gd 的 feel_gain）
var ui_scale: float = 1.0            ## 界面大小 0.8–1.3：缩放整个 HUD 层（present/hud/hud_view.gd）
## 界面语言（Loc.LOCALES 之一）。第一次启动按系统语言定（Loc.default_for）；命令行 --locale=en 临时指定（工具、截图用，不存盘）
var locale: String = Loc.SOURCE_LOCALE
var window_mode: int = DisplayServer.WINDOW_MODE_WINDOWED
## 窗口模式下的窗口大小
var window_size: Vector2i = Vector2i(1600, 900)
## 垂直同步；帧率上限（0 = 不限）
var vsync: bool = true
var max_fps: int = 0
## 画质（2026-10-16）：预设 0 低 / 1 中 / 2 高 / 3 自定义（改了任何一项细项就是自定义）。第一次启动按显卡挑默认档（集成显卡 → 中）
const GFX_COUNT: int = 4
const GFX_PRESETS: Array = [
	{"render_scale": 0.7, "fx_level": 0, "bg_level": 0, "light_level": 0},
	{"render_scale": 0.85, "fx_level": 1, "bg_level": 1, "light_level": 1},
	{"render_scale": 1.0, "fx_level": 2, "bg_level": 2, "light_level": 2},
]
const RENDER_SCALES: Array = [0.5, 0.6, 0.7, 0.85, 1.0]
var gfx_preset: int = 2
## 渲染分辨率：游戏画面（山、城、特效、夜宴）按这个比例渲染再放大到窗口；HUD 和界面文字始终是原生分辨率
var render_scale: float = 1.0
## 特效数量 0 少 / 1 中 / 2 多：碎屑、尘土、火星、烟的数量和同屏上限
var fx_level: int = 2
## 背景细节 0 简 / 1 中 / 2 全：远景雾带、星星、海浪、远山灯火、山后装饰
var bg_level: int = 2
## 夜宴光影 0 简 / 1 中 / 2 全：法线贴图（立体受光）、火光闪烁、光晕、火盆粒子
var light_level: int = 2
## 闪光强度（白闪、爆光的透明度倍率，0 = 关掉闪光）
var flash_strength: float = 1.0
## 切到别的窗口时：静音、暂停
var mute_unfocused: bool = false
var pause_on_blur: bool = true
## 底部操作提示：0 = 只在前两天，1 = 一直显示，2 = 关闭
var hint_mode: int = 0
## 自动推石：白天替玩家按节奏交替按左右（app/input/auto_pusher.gd）
var auto_push: bool = false
## 自动推石频率（次/秒）；落在节奏窗口 0.18–0.5 秒里才叠节奏层数
var auto_push_rate: float = 5.0
## 允许用 console 键打开调试控制台
var debug_console: bool = false
## 首次启动的抢先体验说明看过了
var ea_notice_seen: bool = false
## 动作 → [绑定, 绑定]（空字典 = 这个槽没绑）
var bindings: Dictionary = {}

## true = 只在内存里，不碰磁盘。创建时就判断（不等 _ready）：单元测试用 -s 脚本跑，测试执行时这个 autoload 的 _ready 还没跑，
## 2026-10-16 就因为这个，测试里的设置界面"存盘"把玩家的 settings.cfg 覆盖成了一份不完整的（已从 md5 还原）
var memory_only: bool = OS.get_cmdline_user_args().has("--test") or DisplayServer.get_name() == "headless"
## _ready 读完磁盘才算准备好；没准备好时绝不写盘（键位还是空的，会写出残缺文件）
var _loaded: bool = false


func _ready() -> void:
	memory_only = memory_only or OS.get_cmdline_user_args().has("--test") or DisplayServer.get_name() == "headless"
	bindings = default_bindings()
	if not memory_only:
		SaveService.import_legacy_en()
		var first: bool = not FileAccess.file_exists(PATH)
		load_from_disk()
		if first:
			apply_gfx_preset(auto_preset())
			locale = Loc.default_for(OS.get_locale_language())
	if memory_only:
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--locale="):
				locale = arg.substr(9)
	_loaded = true
	apply_bindings()
	# 自动加载顺序里 Settings 排在 Content 前面：内容按这里定的语言读
	locale = Loc.set_locale(locale)


## 切换界面语言：重载内容（JSON 里的文字按新语言替换）、存盘、发 locale_changed。返回是否真的换了
func set_locale(l: String) -> bool:
	if not Loc.LOCALES.has(l) or l == Loc.locale():
		return false
	locale = Loc.set_locale(l)
	var c: Node = get_node_or_null(^"/root/Content") if is_inside_tree() else null
	if c != null:
		c.call(&"reload")
	save_to_disk()
	locale_changed.emit()
	return true


## 画面设置交给引擎：显示模式、窗口大小（只在窗口模式下改，并居中）、垂直同步、帧率上限。无头运行时什么都不做
func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if DisplayServer.window_get_mode() != window_mode:
		DisplayServer.window_set_mode(window_mode)
	if window_mode == DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_size() != window_size:
		DisplayServer.window_set_size(window_size)
		var scr: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		DisplayServer.window_set_position(scr.position + (scr.size - window_size) / 2)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps


## 套一档画质预设（0 低 / 1 中 / 2 高）；3 = 自定义，不改细项
func apply_gfx_preset(i: int) -> void:
	gfx_preset = clampi(i, 0, GFX_COUNT - 1)
	if gfx_preset < GFX_PRESETS.size():
		var pr: Dictionary = GFX_PRESETS[gfx_preset]
		render_scale = float(pr["render_scale"])
		fx_level = int(pr["fx_level"])
		bg_level = int(pr["bg_level"])
		light_level = int(pr["light_level"])
	gfx_changed.emit()


## 改了某个细项：和哪档预设完全一样就显示那档，否则是"自定义"
func refresh_gfx_preset() -> void:
	gfx_preset = 3
	for i: int in GFX_PRESETS.size():
		var pr: Dictionary = GFX_PRESETS[i]
		if is_equal_approx(render_scale, float(pr["render_scale"])) and fx_level == int(pr["fx_level"]) and bg_level == int(pr["bg_level"]) 				and light_level == int(pr["light_level"]):
			gfx_preset = i
	gfx_changed.emit()


## 第一次启动的默认档：集成显卡（核显）→ 中，独立显卡 → 高。测试 / 无头 / 工具（内存模式）一律高，结果可复现
func auto_preset() -> int:
	if memory_only or DisplayServer.get_name() == "headless":
		return 2
	if RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		return 1
	var nm: String = RenderingServer.get_video_adapter_name().to_lower()
	for k: String in ["intel", "uhd", "iris", "radeon(tm) graphics", "radeon graphics", "vega 8", "vega 7", "vega 6", "mali", "adreno"]:
		if nm.contains(k) and not nm.contains("arc"):
			return 1
	return 2


## 特效数量的倍率（碎屑、尘土、火星、烟的生成数和同屏上限都乘它）
func fx_mult() -> float:
	return [0.4, 0.7, 1.0][clampi(fx_level, 0, 2)]


## "恢复默认设置"：除键位、调试控制台和"看过 EA 说明"以外的设置都回到默认值
func reset_defaults() -> void:
	master_volume = 1.0
	sfx_volume = 1.0
	music_volume = 1.0
	amb_volume = 1.0
	shake_strength = 1.0
	feel_strength = 1.0
	ui_scale = 1.0
	window_mode = DisplayServer.WINDOW_MODE_WINDOWED
	window_size = Vector2i(1600, 900)
	vsync = true
	max_fps = 0
	apply_gfx_preset(auto_preset())
	flash_strength = 1.0
	mute_unfocused = false
	pause_on_blur = true
	hint_mode = 0
	auto_push = false
	auto_push_rate = 5.0


static func default_bindings() -> Dictionary:
	return {
		"push_left": [{"k": KEY_A}, {"k": KEY_LEFT}],
		"push_right": [{"k": KEY_D}, {"k": KEY_RIGHT}],
		"strike": [{"k": KEY_SPACE}, {}],
		"end_day": [{"k": KEY_ENTER}, {"k": KEY_KP_ENTER}],
		"interact": [{"k": KEY_E}, {"k": KEY_W}],
		"overview": [{"k": KEY_TAB}, {}],
		"console": [{"k": KEY_F1}, {}],
	}


## 把 bindings 写进 InputMap（没有的动作先建出来）
func apply_bindings() -> void:
	for id: String in ACTION_IDS:
		var act: StringName = StringName(id)
		if not InputMap.has_action(act):
			InputMap.add_action(act, 0.2)
		InputMap.action_erase_events(act)
		for d: Variant in bindings.get(id, []):
			var ev: InputEvent = to_event(d as Dictionary)
			if ev != null:
				InputMap.action_add_event(act, ev)
	bindings_changed.emit()


static func to_event(d: Dictionary) -> InputEvent:
	if d.has("k"):
		var k: InputEventKey = InputEventKey.new()
		k.keycode = int(d["k"]) as Key
		return k
	if d.has("m"):
		var m: InputEventMouseButton = InputEventMouseButton.new()
		m.button_index = int(d["m"]) as MouseButton
		return m
	return null


## 按下的键 / 鼠标键 → 绑定字典（别的事件返回空字典）
static func from_event(ev: InputEvent) -> Dictionary:
	var k: InputEventKey = ev as InputEventKey
	if k != null:
		return {"k": int(k.keycode if k.keycode != KEY_NONE else k.physical_keycode)}
	var m: InputEventMouseButton = ev as InputEventMouseButton
	if m != null:
		return {"m": int(m.button_index)}
	return {}


## 键名 / 鼠标键名的显示（不在表里的键用引擎给的英文名）
static func key_names() -> Dictionary:
	return {
		"Left": "←", "Right": "→", "Up": "↑", "Down": "↓", "Space": Loc.t("settings_service.key_space", "空格"),
		"Enter": Loc.t("settings_service.key_enter", "回车"), "Kp Enter": Loc.t("settings_service.key_kp_enter", "小键盘回车"),
		"Escape": "Esc", "Backspace": Loc.t("settings_service.key_backspace", "退格"), "Ctrl": "Ctrl", "Shift": "Shift", "Alt": "Alt",
	}


static func mouse_names() -> Dictionary:
	return {1: Loc.t("settings_service.mouse_left", "鼠标左键"), 2: Loc.t("settings_service.mouse_right", "鼠标右键"),
		3: Loc.t("settings_service.mouse_middle", "鼠标中键"), 4: Loc.t("settings_service.wheel_up", "滚轮上"),
		5: Loc.t("settings_service.wheel_down", "滚轮下"), 8: Loc.t("settings_service.mouse_side_1", "鼠标侧键 1"),
		9: Loc.t("settings_service.mouse_side_2", "鼠标侧键 2")}


static func mouse_short() -> Dictionary:
	return {1: Loc.t("settings_service.mouse_left_short", "左键"), 2: Loc.t("settings_service.mouse_right_short", "右键"),
		3: Loc.t("settings_service.mouse_middle_short", "中键"), 4: Loc.t("settings_service.wheel_up_short", "滚上"),
		5: Loc.t("settings_service.wheel_down_short", "滚下"), 8: Loc.t("settings_service.mouse_side_1_short", "侧1"),
		9: Loc.t("settings_service.mouse_side_2_short", "侧2")}


## [动作, 显示名]（顺序 = 设置界面里的顺序）
static func actions() -> Array:
	return [
		["push_left", Loc.t("settings_service.act_push_left", "推石 · 左")], ["push_right", Loc.t("settings_service.act_push_right", "推石 · 右")],
		["strike", Loc.t("settings_service.act_strike", "重压 / 砸地 / 跳过")], ["end_day", Loc.t("settings_service.act_end_day", "提前收工")],
		["interact", Loc.t("settings_service.act_interact", "夜宴 · 交谈 / 交易")], ["overview", Loc.t("settings_service.act_overview", "夜宴 · 全场速览")],
		["console", Loc.t("settings_service.act_console", "调试控制台")],
	]


## 画质预设名（0 低 / 1 中 / 2 高 / 3 自定义）
static func gfx_names() -> PackedStringArray:
	return [Loc.t("settings_service.gfx_low", "低"), Loc.t("settings_service.gfx_mid", "中"), Loc.t("settings_service.gfx_high", "高"),
		Loc.t("settings_service.gfx_custom", "自定义")]


## 绑定的显示名（设置界面用）
static func label_of(d: Dictionary) -> String:
	if d.has("k"):
		var s: String = OS.get_keycode_string(int(d["k"]) as Key)
		return str(key_names().get(s, s))
	if d.has("m"):
		return str(mouse_names().get(int(d["m"]), Loc.t("settings_service.mouse_button", "鼠标键 %d") % int(d["m"])))
	return "—"


## 动作的第一个绑定的短名（画面提示用：头顶陶片、夜宴提示）
func short_label(action: String) -> String:
	for d: Variant in bindings.get(action, []):
		var dd: Dictionary = d
		if dd.has("m"):
			return str(mouse_short().get(int(dd["m"]), Loc.t("settings_service.mb", "鼠%d") % int(dd["m"])))
		if dd.has("k"):
			return label_of(dd)
	return "?"


## 绑定到某个动作的第 slot 个槽；同一个键原来绑在别的地方的会被摘掉（一个键只做一件事）
func set_binding(action: String, slot: int, d: Dictionary) -> void:
	for a: Variant in bindings:
		var lst: Array = bindings[a]
		for i: int in lst.size():
			if lst[i] == d:
				lst[i] = {}
	var cur: Array = bindings.get(action, [])
	while cur.size() < SLOTS:
		cur.append({})
	cur[clampi(slot, 0, SLOTS - 1)] = d
	bindings[action] = cur
	apply_bindings()


func clear_binding(action: String, slot: int) -> void:
	var cur: Array = bindings.get(action, [])
	if slot >= 0 and slot < cur.size():
		cur[slot] = {}
	apply_bindings()


func reset_bindings() -> void:
	bindings = default_bindings()
	apply_bindings()


func load_from_disk() -> void:
	if memory_only or not FileAccess.file_exists(PATH):
		return
	var cf: ConfigFile = ConfigFile.new()
	if cf.load(PATH) != OK:
		push_warning("[Settings] 读取 %s 失败，使用默认值" % PATH)
		return
	master_volume = float(cf.get_value("audio", "master", master_volume))
	sfx_volume = float(cf.get_value("audio", "sfx", sfx_volume))
	music_volume = float(cf.get_value("audio", "music", music_volume))
	amb_volume = float(cf.get_value("audio", "amb", amb_volume))
	shake_strength = float(cf.get_value("feel", "shake", shake_strength))
	feel_strength = float(cf.get_value("feel", "feel", feel_strength))
	ui_scale = float(cf.get_value("ui", "scale", ui_scale))
	locale = str(cf.get_value("ui", "locale", locale))
	window_mode = int(cf.get_value("display", "window_mode", window_mode))
	auto_push = bool(cf.get_value("play", "auto_push", auto_push))
	auto_push_rate = float(cf.get_value("play", "auto_push_rate", auto_push_rate))
	debug_console = bool(cf.get_value("debug", "console", debug_console))
	window_size = cf.get_value("display", "window_size", window_size) as Vector2i
	vsync = bool(cf.get_value("display", "vsync", vsync))
	max_fps = int(cf.get_value("display", "max_fps", max_fps))
	gfx_preset = clampi(int(cf.get_value("display", "gfx_preset", gfx_preset)), 0, GFX_COUNT - 1)
	render_scale = clampf(float(cf.get_value("display", "render_scale", render_scale)), 0.5, 1.0)
	fx_level = clampi(int(cf.get_value("display", "fx_level", fx_level)), 0, 2)
	bg_level = clampi(int(cf.get_value("display", "bg_level", bg_level)), 0, 2)
	light_level = clampi(int(cf.get_value("display", "light_level", light_level)), 0, 2)
	flash_strength = float(cf.get_value("feel", "flash", flash_strength))
	mute_unfocused = bool(cf.get_value("audio", "mute_unfocused", mute_unfocused))
	pause_on_blur = bool(cf.get_value("play", "pause_on_blur", pause_on_blur))
	hint_mode = int(cf.get_value("play", "hint_mode", hint_mode))
	ea_notice_seen = bool(cf.get_value("misc", "ea_notice_seen", ea_notice_seen))
	for id: String in ACTION_IDS:
		var v: Variant = cf.get_value("input", id, null)
		if v is Array:
			var lst: Array = []
			for d: Variant in v:
				lst.append(d if d is Dictionary else {})
			while lst.size() < SLOTS:
				lst.append({})
			bindings[id] = lst


func save_to_disk() -> void:
	if memory_only or not _loaded:
		return
	var cf: ConfigFile = ConfigFile.new()
	cf.set_value("audio", "master", master_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.set_value("audio", "music", music_volume)
	cf.set_value("audio", "amb", amb_volume)
	cf.set_value("feel", "shake", shake_strength)
	cf.set_value("feel", "feel", feel_strength)
	cf.set_value("ui", "scale", ui_scale)
	cf.set_value("ui", "locale", locale)
	cf.set_value("display", "window_mode", window_mode)
	cf.set_value("play", "auto_push", auto_push)
	cf.set_value("play", "auto_push_rate", auto_push_rate)
	cf.set_value("debug", "console", debug_console)
	cf.set_value("display", "window_size", window_size)
	cf.set_value("display", "vsync", vsync)
	cf.set_value("display", "max_fps", max_fps)
	cf.set_value("display", "gfx_preset", gfx_preset)
	cf.set_value("display", "render_scale", render_scale)
	cf.set_value("display", "fx_level", fx_level)
	cf.set_value("display", "bg_level", bg_level)
	cf.set_value("display", "light_level", light_level)
	cf.set_value("feel", "flash", flash_strength)
	cf.set_value("audio", "mute_unfocused", mute_unfocused)
	cf.set_value("play", "pause_on_blur", pause_on_blur)
	cf.set_value("play", "hint_mode", hint_mode)
	cf.set_value("misc", "ea_notice_seen", ea_notice_seen)
	for a: Variant in bindings:
		cf.set_value("input", str(a), bindings[a])
	if cf.save(PATH) != OK:
		push_warning("[Settings] 写入 %s 失败" % PATH)
