class_name DialogPanel
extends Control
## 底部陶板对话框（= 网页 story.js showDialog + css/story.css；陶板、立绘框的位置在 dialog_panel.tscn）：左侧立绘（por_* / por2_* 半身像；没有时圆章放进墨色拱框；再没有写希腊首字母），
## 右侧说话人名 + 希腊名 + 台词；点击 / 空格 / 回车翻页，最后一页出选项（数字键或点击；金色 = 推荐）。系统提示（who = ""）居中斜体。
## payload：{speaker, name, pages: [{who, name, greek, portraits, initial, text}], choices: [{label, gold}]}

signal answered(i: int)

const SCENE: String = "res://present/ui/dialog_panel.tscn"
## 有立绘时文字左边留出立绘的位置；旁白居中，左右都只留一点
const MARGIN_SPEAKER: int = 318
const MARGIN_NARRATOR: int = 71

var m: ModalRequest
var _page: int = 0
var _t: float = 0.0
var _page_t: float = 0.0
var _choices_t: float = -1.0
var _done: bool = false
var _panel: Control
var _margin: MarginContainer
var _por: Control
var _por_back: Panel
var _name: Label
var _greek: Label
var _text: Label
var _choices: HBoxContainer
var _next: Label


static func create() -> DialogPanel:
	return SceneCache.make(SCENE) as DialogPanel


func setup(p_m: ModalRequest) -> void:
	m = p_m


func _ready() -> void:
	_panel = %Panel
	_margin = %Margin
	_por = %Portrait
	# 立绘后面的陶土拱底：黑釉的男神立绘放在深色对话框上读不出剪影，垫一块陶瓶底色
	_por_back = %PorBack
	_name = %Name
	_greek = %Greek
	_text = %Text
	_choices = %Choices
	_next = %Next
	_show_page()


func _pages() -> Array:
	return m.payload.get("pages", [])


func _last() -> bool:
	return _page >= _pages().size() - 1


func _is_narrator() -> bool:
	var pg: Dictionary = _pages()[_page] if _page < _pages().size() else {}
	return String(pg.get("who", "")) == ""


func _show_page() -> void:
	var pages: Array = _pages()
	var pg: Dictionary = pages[_page] if _page < pages.size() else {"who": "", "text": ""}
	var narrator: bool = String(pg.get("who", "")) == ""
	_name.text = "" if narrator else String(pg.get("name", ""))
	_greek.text = "" if narrator else String(pg.get("greek", ""))
	_text.text = String(pg.get("text", ""))
	_text.add_theme_color_override("font_color", Color("e9d3a8") if narrator else UiKit.CREAM)
	for c: Node in _por.get_children():
		c.queue_free()
	_por_back.visible = not narrator and _has_bust(pg)
	if not narrator:
		var pc: Control = _portrait(pg)
		pc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_por.add_child(pc)
	_margin.add_theme_constant_override("margin_left", MARGIN_NARRATOR if narrator else MARGIN_SPEAKER)
	_margin.add_theme_constant_override("margin_right", MARGIN_NARRATOR if narrator else 36)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if narrator else HORIZONTAL_ALIGNMENT_LEFT
	for c: Node in _choices.get_children():
		_choices.remove_child(c)
		c.queue_free()
	_choices_t = -1.0
	var choices: Array = m.payload.get("choices", [])
	if _last() and not choices.is_empty():
		for i: int in choices.size():
			var ch: Dictionary = choices[i]
			var b: Button = UiKit.button("%d  %s" % [i + 1, String(ch.get("label", ""))], bool(ch.get("gold", false)), 18)
			b.pressed.connect(func() -> void: _choose(i))
			_choices.add_child(b)
		_choices_t = _t
		_next.text = ""
	else:
		_next.text = "%d / %d  ▼" % [_page + 1, pages.size()] if pages.size() > 1 else "▼"
	_page_t = _t


## 这一页有没有胸像立绘（por2_*，才垫陶土拱底；旧的 por_* 和墨色拱框不垫）
func _has_bust(pg: Dictionary) -> bool:
	for k: Variant in pg.get("portraits", []):
		if SpriteDB.has(StringName(str(k))):
			return str(k).begins_with("por2_")
	return false


## 立绘回退链：por_*（全身）→ 其余 key 画进墨色拱框 → 希腊首字母
func _portrait(pg: Dictionary) -> Control:
	var keys: Array = pg.get("portraits", [])
	for k: Variant in keys:
		var key: StringName = StringName(str(k))
		if not SpriteDB.has(key):
			continue
		if String(key).begins_with("por_") or String(key).begins_with("por2_"):
			var tr: TextureRect = UiKit.tex_rect(key, Vector2(10, 10))
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			return tr
		var arch: PanelContainer = PanelContainer.new()
		arch.add_theme_stylebox_override("panel", UiKit.box(UiKit.INK, Color("e9d3a8"), 2, 80, 10))
		arch.add_child(UiKit.tex_rect(key, Vector2(10, 10)))
		return arch
	var l: Label = UiKit.label(String(pg.get("initial", "?")), 72, UiKit.CREAM, 700, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", Fonts.greek())
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _process(dt: float) -> void:
	_t += dt
	var k: float = clampf((_t) / 0.2, 0.0, 1.0)
	_panel.modulate.a = k
	_por.modulate.a = k
	_por_back.modulate.a = k


func _advance() -> void:
	if _done or _t - _page_t < 0.18:
		return
	if not _last():
		_page += 1
		_show_page()
		return
	if (m.payload.get("choices", []) as Array).is_empty():
		_finish(0)


func _choose(i: int) -> void:
	if _done or _choices_t < 0.0 or _t - _choices_t < 0.25:
		return
	_finish(i)


func _finish(i: int) -> void:
	if _done:
		return
	_done = true
	answered.emit(i)


func _gui_input(ev: InputEvent) -> void:
	var mb: InputEventMouseButton = ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_advance()


func _unhandled_input(ev: InputEvent) -> void:
	var k: InputEventKey = ev as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	get_viewport().set_input_as_handled()
	if k.keycode >= KEY_1 and k.keycode <= KEY_9:
		_choose(k.keycode - KEY_1)
	elif k.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		if _choices_t >= 0.0:
			return   # 有选项时空格 / 回车不替玩家选（防误触）
		_advance()
