class_name SettingsScreen
extends Control
## 设置（主菜单和暂停菜单都能进；布局在 settings_screen.tscn，由 tools/assets/gen_settings_scene.py 生成，陶瓶风格 theme_vase.tres）。
## 分页：声音 / 画面（显示 + 画质）/ 辅助（界面大小、震屏、闪光、顿帧）/ 操作 / 游戏 / 开发。顶上的页签点一下切页，Q / E（或 PageUp / PageDown）也能翻页。
## 每个控件按属性名绑在 Settings 上（_slider / _check / _option），改动立刻生效并存盘（Settings.save_to_disk）。键位：点一个槽 → 按下新的键或鼠标键；Esc 取消，Delete / 退格清空这个槽。

signal back_pressed

const SCENE: String = "res://present/ui/settings_screen.tscn"
const PAGES: PackedStringArray = ["Sound", "Display", "Comfort", "Controls", "Game", "Dev"]
## 不是 const：文字要按当前语言取（Loc.t），所以每次建界面时现算
## 显示模式：[名字, DisplayServer 窗口模式]
var WINDOW_MODES: Array = [[Loc.t("settings_screen.windowed", "窗口"), DisplayServer.WINDOW_MODE_WINDOWED], [Loc.t("settings_screen.borderless_fullscreen", "无边框全屏"), DisplayServer.WINDOW_MODE_FULLSCREEN], [Loc.t("settings_screen.exclusive_fullscreen", "独占全屏"), DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]]
const WINDOW_SIZES: Array = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
var FPS: Array = [[30, "30"], [60, "60"], [120, "120"], [144, "144"], [0, Loc.t("settings_screen.unlimited", "不限")]]
var HINTS: PackedStringArray = [Loc.t("settings_screen.first_two_days", "只在前两天"), Loc.t("settings_screen.always", "一直显示"), Loc.t("settings_screen.off", "关闭")]
var LEVELS_FX: PackedStringArray = [Loc.t("settings_screen.low", "少"), Loc.t("settings_screen.medium", "中"), Loc.t("settings_screen.high", "多")]
var LEVELS_BG: PackedStringArray = [Loc.t("settings_screen.simple", "简"), Loc.t("settings_screen.medium", "中"), Loc.t("settings_screen.full", "全")]
var LEVELS_LIGHT: PackedStringArray = [Loc.t("settings_screen.simple", "简"), Loc.t("settings_screen.medium", "中"), Loc.t("settings_screen.full", "全")]

var world: WorldView = null
## 能不能切语言：只在主菜单里能（游戏中途切要重建 HUD、夜宴和已经生成的工资条文字）；暂停菜单里设成 false
var allow_locale: bool = true
## 打开时停在哪一页（PAGES 里的名字；空 = 第一页）。切完语言重建后回到"游戏"页
var start_page: String = ""
## 语言下拉框里的名字：每种语言用它自己的文字写
const LOCALE_NAMES: Dictionary = {"zh_CN": "简体中文", "en": "English"}  # i18n: skip
var _t: float = 0.0
## 正在等新按键的槽：{action, slot, button}；空 = 不在改键
var _capture: Dictionary = {}
var _bind_buttons: Dictionary = {}       # "action:slot" → Button
var _note: Label
var _page: int = 0
var _pages_on: PackedStringArray = []
## 每个控件"从 Settings 重新读一遍"的回调（恢复默认设置后统一刷新）
var _sync: Array[Callable] = []


static func create() -> SettingsScreen:
	return SceneCache.make(SCENE) as SettingsScreen


func _ready() -> void:
	_note = %Note
	_note.text = ""
	# 页签
	var group: ButtonGroup = ButtonGroup.new()
	for key: String in PAGES:
		var tab: Button = get_node("%Tab" + key) as Button
		tab.button_group = group
		_pages_on.append(key)
		var idx: int = _pages_on.size() - 1
		tab.pressed.connect(func() -> void: _show_page(idx))
	# 声音
	_slider(&"Master", "master_volume")
	_slider(&"Sfx", "sfx_volume")
	_slider(&"Music", "music_volume")
	_slider(&"Amb", "amb_volume")
	_check(&"MuteUnfocused", "mute_unfocused")
	# 画面
	var modes: PackedStringArray = []
	for m: Array in WINDOW_MODES:
		modes.append(String(m[0]))
	_option(&"WindowMode", modes, _mode_index, _set_mode)
	var sizes: PackedStringArray = []
	for v: Vector2i in WINDOW_SIZES:
		sizes.append("%d × %d" % [v.x, v.y])
	_option(&"WindowSize", sizes, func() -> int: return maxi(0, WINDOW_SIZES.find(Settings.window_size)),
		func(i: int) -> void: Settings.window_size = WINDOW_SIZES[i])
	var fps: PackedStringArray = []
	for f: Array in FPS:
		fps.append(String(f[1]))
	_option(&"MaxFps", fps, _fps_index, func(i: int) -> void: Settings.max_fps = int(FPS[i][0]))
	_check(&"Vsync", "vsync")
	# 画质：选预设 = 一次改齐四项；改任何一项细项，预设自动变成"自定义"（或者正好等于某档时显示那档）
	_option(&"GfxPreset", Settings.gfx_names(), func() -> int: return Settings.gfx_preset, func(i: int) -> void:
		if i < Settings.GFX_PRESETS.size():
			Settings.apply_gfx_preset(i)
		else:
			Settings.gfx_preset = i
		_sync_gfx()
		)
	var scales: PackedStringArray = []
	for v: float in Settings.RENDER_SCALES:
		scales.append("%d%%" % roundi(v * 100.0))
	_option(&"RenderScale", scales, _scale_index, func(i: int) -> void: _set_gfx("render_scale", float(Settings.RENDER_SCALES[i])))
	_option(&"FxLevel", LEVELS_FX, func() -> int: return Settings.fx_level, func(i: int) -> void: _set_gfx("fx_level", i))
	_option(&"BgLevel", LEVELS_BG, func() -> int: return Settings.bg_level, func(i: int) -> void: _set_gfx("bg_level", i))
	_option(&"LightLevel", LEVELS_LIGHT, func() -> int: return Settings.light_level, func(i: int) -> void: _set_gfx("light_level", i))
	_slider(&"UiScale", "ui_scale")
	_slider(&"Shake", "shake_strength")
	_slider(&"Flash", "flash_strength")
	_slider(&"Feel", "feel_strength")
	_refresh_size_enabled()
	# 操作
	_check(&"AutoPush", "auto_push")
	_slider(&"AutoRate", "auto_push_rate", Loc.t("settings_screen.presses_sec", "%.2f 次/秒"))
	var binds: Node = %Bindings
	for a: Array in Settings.actions():
		var row: Node = binds.get_node_or_null("Row_" + str(a[0]))
		if row == null:
			continue
		for slot: int in Settings.SLOTS:
			var b: Button = row.get_node_or_null("Slot%d" % slot) as Button
			if b == null:
				continue
			var action: String = str(a[0])
			b.pressed.connect(func() -> void: _start_capture(action, slot, b))
			_bind_buttons["%s:%d" % [action, slot]] = b
	_refresh_bindings()
	(%ResetBindings as Button).pressed.connect(func() -> void:
		Settings.reset_bindings()
		Settings.save_to_disk()
		_refresh_bindings()
		_note.text = Loc.t("settings_screen.keybinds_reset_default", "键位已恢复默认")
		)
	# 游戏
	_check(&"PauseOnBlur", "pause_on_blur")
	var lang: OptionButton = %Language
	for l: String in Loc.LOCALES:
		lang.add_item(String(LOCALE_NAMES.get(l, l)))
	lang.select(maxi(0, Loc.LOCALES.find(Loc.locale())))
	lang.disabled = not allow_locale
	(%LangNote as Control).visible = not allow_locale
	# 切换后 Settings 重载内容并发 locale_changed，主菜单整个重建（main._on_locale_changed），这一页跟着重开
	lang.item_selected.connect(func(i: int) -> void: Settings.set_locale(Loc.LOCALES[i]))
	_option(&"HintMode", HINTS, func() -> int: return clampi(Settings.hint_mode, 0, HINTS.size() - 1), func(i: int) -> void: Settings.hint_mode = i)
	(%OpenSaves as Button).pressed.connect(func() -> void:
		var dir: String = ProjectSettings.globalize_path("user://save")
		DirAccess.make_dir_recursive_absolute(dir)
		OS.shell_open(dir)
		)
	(%ResetAll as Button).pressed.connect(func() -> void:
		Settings.reset_defaults()
		for f: Callable in _sync:
			f.call()
		_refresh_size_enabled()
		_apply_and_save()
		_note.text = Loc.t("settings_screen.settings_reset_default_keybinds", "已恢复默认设置（键位没动）")
		)
	# 开发
	_check(&"DebugConsole", "debug_console")
	(%DebugConsole as CheckBox).text = Loc.t("settings_screen.enable_debug_console_press", "开启调试控制台（游戏里按 %s 打开）") % Settings.short_label("console")
	var back: Button = %Back
	back.pressed.connect(_back)
	_show_page(maxi(0, _pages_on.find(start_page)))


func _show_page(i: int) -> void:
	_page = clampi(i, 0, _pages_on.size() - 1)
	for key: String in PAGES:
		var on: bool = _pages_on.size() > _page and key == _pages_on[_page]
		(get_node("%Page" + key) as Control).visible = on
		(get_node("%Tab" + key) as Button).set_pressed_no_signal(on)
	(get_node("%Tab" + _pages_on[_page]) as Button).call_deferred("grab_focus")


func _mode_index() -> int:
	for i: int in WINDOW_MODES.size():
		if int(WINDOW_MODES[i][1]) == Settings.window_mode:
			return i
	return 0


func _set_mode(i: int) -> void:
	Settings.window_mode = int(WINDOW_MODES[i][1])
	_refresh_size_enabled()


func _fps_index() -> int:
	for i: int in FPS.size():
		if int(FPS[i][0]) == Settings.max_fps:
			return i
	return FPS.size() - 1


func _scale_index() -> int:
	var best: int = Settings.RENDER_SCALES.size() - 1
	for i: int in Settings.RENDER_SCALES.size():
		if absf(float(Settings.RENDER_SCALES[i]) - Settings.render_scale) < absf(float(Settings.RENDER_SCALES[best]) - Settings.render_scale):
			best = i
	return best


## 改一项画质细项：写进 Settings，重新判断预设档，刷新几个下拉框
func _set_gfx(prop: String, v: Variant) -> void:
	Settings.set(prop, v)
	Settings.refresh_gfx_preset()
	_sync_gfx()


func _sync_gfx() -> void:
	(%GfxPreset as OptionButton).select(Settings.gfx_preset)
	(%RenderScale as OptionButton).select(_scale_index())
	(%FxLevel as OptionButton).select(Settings.fx_level)
	(%BgLevel as OptionButton).select(Settings.bg_level)
	(%LightLevel as OptionButton).select(Settings.light_level)


func _refresh_size_enabled() -> void:
	(%WindowSize as OptionButton).disabled = Settings.window_mode != DisplayServer.WINDOW_MODE_WINDOWED


func _apply_and_save() -> void:
	PauseScreen.apply_settings(world)
	Settings.save_to_disk()


## 滑条 ↔ Settings 的一个属性；右边的数值默认显示百分比
func _slider(key: StringName, prop: String, fmt: String = "") -> void:
	var s: HSlider = get_node("%" + String(key)) as HSlider
	var val: Label = get_node("%" + String(key) + "Val") as Label
	var show: Callable = func(v: float) -> String: return (fmt % v) if fmt != "" else "%d%%" % roundi(v * 100.0)
	var sync: Callable = func() -> void:
		s.set_value_no_signal(float(Settings.get(prop)))
		val.text = show.call(s.value)
	sync.call()
	_sync.append(sync)
	s.value_changed.connect(func(v: float) -> void:
		Settings.set(prop, v)
		val.text = show.call(v)
		PauseScreen.apply_settings(world)
		)
	s.drag_ended.connect(func(_changed: bool) -> void: Settings.save_to_disk())


## 勾选框 ↔ Settings 的一个布尔属性
func _check(key: StringName, prop: String) -> void:
	var c: CheckBox = get_node("%" + String(key)) as CheckBox
	var sync: Callable = func() -> void: c.set_pressed_no_signal(bool(Settings.get(prop)))
	sync.call()
	_sync.append(sync)
	c.toggled.connect(func(v: bool) -> void:
		Settings.set(prop, v)
		_apply_and_save()
		)


## 下拉框：items 是显示的名字；get_i() 读出当前该选第几项，set_i(i) 写回 Settings
func _option(key: StringName, items: PackedStringArray, get_i: Callable, set_i: Callable) -> void:
	var o: OptionButton = get_node("%" + String(key)) as OptionButton
	for it: String in items:
		o.add_item(it)
	var sync: Callable = func() -> void: o.select(int(get_i.call()))
	sync.call()
	_sync.append(sync)
	o.item_selected.connect(func(i: int) -> void:
		set_i.call(i)
		_apply_and_save()
		)


func _refresh_bindings() -> void:
	for key: String in _bind_buttons:
		var parts: PackedStringArray = key.split(":")
		var lst: Array = Settings.bindings.get(parts[0], [])
		var slot: int = int(parts[1])
		var d: Dictionary = lst[slot] if slot < lst.size() else {}
		(_bind_buttons[key] as Button).text = Settings.label_of(d)


func _start_capture(action: String, slot: int, b: Button) -> void:
	if not _capture.is_empty():
		return
	_capture = {"action": action, "slot": slot, "button": b, "t": _t}
	b.text = Loc.t("settings_screen.press_new_key", "按下新按键…")
	_note.text = Loc.t("settings_screen.press_key_or_mouse", "按下新的键或鼠标键（Esc 取消，Delete / 退格清空）")


## 改键：在 GUI 之前截住下一次按键 / 鼠标键
func _input(ev: InputEvent) -> void:
	if _capture.is_empty() or not ev.is_pressed() or ev.is_echo():
		return
	var k: InputEventKey = ev as InputEventKey
	var m: InputEventMouseButton = ev as InputEventMouseButton
	if k == null and m == null:
		return
	get_viewport().set_input_as_handled()
	var action: String = str(_capture["action"])
	var slot: int = int(_capture["slot"])
	_capture = {}
	if k != null and k.keycode == KEY_ESCAPE:
		_note.text = Loc.t("settings_screen.rebinding_canceled_esc_reserved", "取消改键（Esc 固定是暂停，不能绑定）")
	elif k != null and (k.keycode == KEY_DELETE or k.keycode == KEY_BACKSPACE):
		Settings.clear_binding(action, slot)
		_note.text = Loc.t("settings_screen.cleared", "已清空")
	else:
		var d: Dictionary = Settings.from_event(ev)
		Settings.set_binding(action, slot, d)
		_note.text = Loc.t("settings_screen.removed_key_s_previous", "%s → %s（同一个键原来绑在别处的已摘掉）") % [action, Settings.label_of(d)]
	Settings.save_to_disk()
	_refresh_bindings()


func _back() -> void:
	if _t < 0.2 or not _capture.is_empty():
		return
	Settings.save_to_disk()
	back_pressed.emit()


func _process(dt: float) -> void:
	_t += dt


func _unhandled_input(ev: InputEvent) -> void:
	var k: InputEventKey = ev as InputEventKey
	if k == null or not k.pressed or k.echo or not _capture.is_empty():
		return
	if k.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_back()
	elif k.keycode == KEY_Q or k.keycode == KEY_PAGEUP:
		get_viewport().set_input_as_handled()
		_show_page((_page - 1 + _pages_on.size()) % _pages_on.size())
	elif k.keycode == KEY_E or k.keycode == KEY_PAGEDOWN:
		get_viewport().set_input_as_handled()
		_show_page((_page + 1) % _pages_on.size())
