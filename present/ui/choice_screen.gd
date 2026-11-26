class_name ChoiceScreen
extends Control
## 通用的选择界面（登顶选择、通知、滚落体验、反馈 / 制作人员）：布局在 choice_screen.tscn——陶瓶风格的陶土牌匾（theme_vase.tres），
## 标题 / 回纹线 / 副标题 / 正文 / 按钮列，居中；背后的画面压暗但看得见。
## 脚本按 title / subtitle / body / choices 填内容，空的藏起来。数字键 1–9 直接选；出现 0.4 秒内不响应。
## choices：[{label, gold?, disabled?}]。用 ChoiceScreen.create() 建（不要 .new()，那样没有场景里的节点）。

signal chosen(i: int)

const SCENE: String = "res://present/ui/choice_screen.tscn"

var title: String = ""
var subtitle: String = ""
var body: String = ""
var choices: Array = []
var dim: float = 0.7
var art: StringName = &""
var _t: float = 0.0


static func create() -> ChoiceScreen:
	return SceneCache.make(SCENE) as ChoiceScreen


func _ready() -> void:
	# 背后的画面只压暗、不涂黑（牌匾本身就够醒目）
	(%Dim as ColorRect).color.a = minf(dim, 0.6)
	var art_rect: TextureRect = %Art
	art_rect.visible = art != &"" and SpriteDB.has(art)
	if art_rect.visible:
		art_rect.texture = SpriteDB.tex(art)
	_set_text(%Title, title)
	_set_text(%Subtitle, subtitle)
	_set_text(%Body, body)
	var box: VBoxContainer = %Buttons
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for i: int in choices.size():
		var c: Dictionary = choices[i]
		var btn: Button = Button.new()
		btn.text = String(c.get("label", ""))
		btn.add_theme_font_size_override("font_size", 24)
		btn.add_theme_font_override("font", Fonts.serif(800 if bool(c.get("gold", false)) else 700))
		btn.custom_minimum_size = Vector2(360, 50)
		btn.disabled = bool(c.get("disabled", false))
		btn.pressed.connect(func() -> void: if _t > 0.4: chosen.emit(i))
		box.add_child(btn)
		if i == 0:
			btn.call_deferred("grab_focus")


static func _set_text(l: Label, s: String) -> void:
	l.text = s
	l.visible = s != ""


func _process(dt: float) -> void:
	_t += dt


func _unhandled_input(ev: InputEvent) -> void:
	var k: InputEventKey = ev as InputEventKey
	if k == null or not k.pressed or k.echo or _t < 0.4:
		return
	if k.keycode >= KEY_1 and k.keycode <= KEY_9:
		var i: int = k.keycode - KEY_1
		if i < choices.size() and not bool((choices[i] as Dictionary).get("disabled", false)):
			get_viewport().set_input_as_handled()
			chosen.emit(i)
