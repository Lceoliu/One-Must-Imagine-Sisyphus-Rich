class_name DebugConsole
extends CanvasLayer
## 调试控制台（布局在 debug_console.tscn）：设置里打开"调试控制台"后，按 console 键（默认 F1，可改键）开关。屏幕上半截一块半透明面板：输出 + 输入行。
## 打开时模拟暂停、松开所有按键；↑/↓ 翻历史，Tab 补全命令名，Esc 或再按一次 F1 关闭。命令见 debug_commands.gd。

const SCENE: String = "res://app/debug/debug_console.tscn"

var cmds: DebugCommands = DebugCommands.new()
## main 每帧写入（控制台不自己找）
var runner: SimRunner = null
var is_open: bool = false

var _panel: PanelContainer
var _log: RichTextLabel
var _line: LineEdit
var _fps: Label
var _history: PackedStringArray = []
var _hist_i: int = -1
var _was_paused: bool = false


static func create() -> DebugConsole:
	return SceneCache.make(SCENE) as DebugConsole


func _ready() -> void:
	_fps = %Fps
	_fps.visible = false
	_panel = %Panel
	_panel.visible = false
	_log = %Log
	_line = %Line
	_line.text_submitted.connect(_submit)
	_line.gui_input.connect(_on_input_gui)
	_print("调试控制台 · help 看命令")


func _print(s: String, color: Color = UiKit.CREAM) -> void:
	if s == "":
		return
	_log.push_color(color)
	_log.add_text(s + "\n")
	_log.pop()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if is_open:
		return
	is_open = true
	_panel.visible = true
	if runner != null:
		_was_paused = runner.app_paused
		runner.app_paused = true
		if runner.sim != null:
			runner.sim.release_all()
	cmds.runner = runner
	_line.clear()
	_line.call_deferred("grab_focus")


func close() -> void:
	if not is_open:
		return
	is_open = false
	_panel.visible = false
	_line.release_focus()
	if runner != null:
		runner.app_paused = _was_paused


func _submit(text: String) -> void:
	_line.clear()
	var line: String = text.strip_edges()
	if line == "":
		return
	_history.append(line)
	_hist_i = -1
	_print("> " + line, UiKit.GOLD)
	if line.split(" ", false)[0].to_lower() == "clear":
		_log.clear()
		return
	_print(cmds.run(line))


func _on_input_gui(ev: InputEvent) -> void:
	var k: InputEventKey = ev as InputEventKey
	if k == null or not k.pressed:
		return
	if k.keycode == KEY_UP or k.keycode == KEY_DOWN:
		if _history.is_empty():
			return
		if _hist_i < 0:
			_hist_i = _history.size()
		_hist_i = clampi(_hist_i + (-1 if k.keycode == KEY_UP else 1), 0, _history.size())
		_line.text = _history[_hist_i] if _hist_i < _history.size() else ""
		_line.caret_column = _line.text.length()
		_line.accept_event()
	elif k.keycode == KEY_TAB:
		var cur: String = _line.text.strip_edges()
		var hits: PackedStringArray = []
		for n: String in cmds.names():
			if n.begins_with(cur):
				hits.append(n)
		if hits.size() == 1:
			_line.text = hits[0] + " "
			_line.caret_column = _line.text.length()
		elif hits.size() > 1:
			_print("  ".join(hits), UiKit.MUTED)
		_line.accept_event()


func _input(ev: InputEvent) -> void:
	# 设置里打开"调试控制台"才能用（2026-10-16 用户定：正式版也保留，EA 期间方便测试）
	if not Settings.debug_console:
		if is_open:
			close()
		return
	var k: InputEventKey = ev as InputEventKey
	if ev.is_action_pressed(&"console") and (k == null or not k.echo):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open and k != null and k.pressed and k.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _process(_dt: float) -> void:
	_fps.visible = cmds.show_fps and Settings.debug_console
	_fps.position.y = (_panel.size.y + 8.0) if is_open else 8.0
	if _fps.visible:
		var g: SimGame = cmds.sim
		var extra: String = ""
		if g != null:
			extra = Loc.t("debug_console.day_money_speed", " · 第 %d 天 %s · 钱 %s · 速度 ×%s") % [g.day, String(g.phase), NumFmt.fmt(g.money), str(runner.dev_speed if runner != null else 1.0)]
		_fps.text = "FPS %d%s" % [Engine.get_frames_per_second(), extra]
