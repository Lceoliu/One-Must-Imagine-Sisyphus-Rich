class_name PauseScreen
extends Control
## 暂停菜单（Esc 或切出窗口，布局在 pause_screen.tscn）：继续 / 设置（present/ui/settings_screen.gd：音量、画面、键位、自动推石）/ 反馈（present/ui/feedback.gd）/ 回主菜单（会先存档）/ 退出游戏；右下角版本号。

signal resume_pressed
signal menu_pressed
signal quit_pressed

const SCENE: String = "res://present/ui/pause_screen.tscn"

var world: WorldView = null
## 记录页要读本局统计
var sim: SimGame = null
var _t: float = 0.0
var _settings: SettingsScreen = null
var _fb: ChoiceScreen = null
var _fb_rec: RecordsScreen = null
var _first: Button


static func create() -> PauseScreen:
	return SceneCache.make(SCENE) as PauseScreen


func _ready() -> void:
	_first = %Resume
	_first.pressed.connect(func() -> void: resume_pressed.emit())
	(%Settings as Button).pressed.connect(_open_settings)
	(%Records as Button).pressed.connect(_open_records)
	(%Feedback as Button).pressed.connect(_open_feedback)
	(%Version as Label).text = MenuScreen.version_text()
	(%Menu as Button).pressed.connect(func() -> void: menu_pressed.emit())
	(%Quit as Button).pressed.connect(func() -> void: quit_pressed.emit())
	_first.grab_focus()


## 反馈弹窗盖在暂停菜单上面，返回后回到暂停菜单
func _open_feedback() -> void:
	if _fb != null:
		return
	_fb = Feedback.feedback_screen(func(_i: int) -> void: _close_feedback())
	add_child(_fb)
	($Center as Control).visible = false     # 盖在上面的弹窗打开时，暂停牌匾先收起来，不叠两层


func _close_feedback() -> void:
	if _fb != null and is_instance_valid(_fb):
		_fb.queue_free()
	_fb = null
	_t = 0.0
	($Center as Control).visible = true
	(%Feedback as Button).grab_focus()


func _open_records() -> void:
	if _fb != null or _settings != null or sim == null:
		return
	var rec: RecordsScreen = RecordsScreen.create()
	rec.content = sim.content
	rec.meta = sim.meta
	rec.cur = RecordsScreen.cur_of(sim)
	_fb_rec = rec
	rec.back_pressed.connect(func() -> void:
		rec.queue_free()
		_fb_rec = null
		_t = 0.0
		($Center as Control).visible = true
		(%Records as Button).grab_focus()
		)
	add_child(rec)
	($Center as Control).visible = false


func _open_settings() -> void:
	if _settings != null:
		return
	_settings = SettingsScreen.create()
	_settings.world = world
	_settings.allow_locale = false
	_settings.back_pressed.connect(func() -> void:
		_settings.queue_free()
		_settings = null
		_t = 0.0
		($Center as Control).visible = true
		(%Settings as Button).grab_focus()
		)
	add_child(_settings)
	($Center as Control).visible = false


## 把 Settings 落到引擎：总线音量、震屏强度、窗口模式（main 启动时也调一次）
static func apply_settings(wv: WorldView) -> void:
	# 音量交给 Sfx（它在 Master 上还有一道 0.8 的主音量系数和限幅，不能直接改总线分贝）
	Sfx.set_master(Settings.master_volume)
	Sfx.set_bus_volume(&"SFX", Settings.sfx_volume)
	Sfx.set_bus_volume(&"UI", Settings.sfx_volume)
	Sfx.set_bus_volume(&"Music", Settings.music_volume)
	Sfx.set_bus_volume(&"Amb", Settings.amb_volume)
	if wv != null:
		wv.feel_gain = Settings.shake_strength
	Settings.apply_display()


func _process(dt: float) -> void:
	_t += dt


func _unhandled_input(ev: InputEvent) -> void:
	var k: InputEventKey = ev as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE and _t > 0.2 and _settings == null and _fb == null and _fb_rec == null:
		get_viewport().set_input_as_handled()
		resume_pressed.emit()
