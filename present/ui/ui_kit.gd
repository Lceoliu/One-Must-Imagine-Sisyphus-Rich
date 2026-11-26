class_name UiKit
extends RefCounted
## 界面工具：统一的 Theme（黑釉陶片 + 陶红描边 + 米色字，金色只做点缀）和常用控件的构造函数。
## Theme 存在 res://present/ui/theme.tres（编辑器里改它，场景和代码搭的控件都跟着变）；没有这个文件时现建。

const THEME_PATH: String = "res://present/ui/theme.tres"

const GOLD: Color = Color("f0b93a")
const GOLD_HI: Color = Color("ffe08a")
const CREAM: Color = Color("f1e3c8")
const MUTED: Color = Color("b9a58c")
const CLAY: Color = Color("c8642a")
const INK: Color = Color("120c0a")
const GLAZE: Color = Color("1e140f")
const TERRA: Color = Color("b0705a")

static var _theme: Theme = null


static func box(bg: Color, border: Color, bw: int = 2, radius: int = 6, pad: int = 12) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 6
	s.shadow_offset = Vector2(2, 4)
	return s


static func theme() -> Theme:
	if _theme != null:
		return _theme
	if ResourceLoader.exists(THEME_PATH):
		_theme = load(THEME_PATH) as Theme
		if _theme != null:
			return _theme
	return build_theme()


## 按代码里的配色现建 Theme（theme.tres 丢了时的后备；改配色请直接在编辑器里改 theme.tres）
static func build_theme() -> Theme:
	var th: Theme = Theme.new()
	th.default_font = Fonts.serif(600)
	th.default_font_size = 20
	th.set_color("font_color", "Label", CREAM)
	th.set_color("font_color", "Button", CREAM)
	th.set_color("font_hover_color", "Button", GOLD_HI)
	th.set_color("font_pressed_color", "Button", GOLD)
	th.set_color("font_disabled_color", "Button", Color(MUTED, 0.5))
	th.set_stylebox("normal", "Button", box(GLAZE, CLAY, 2, 6, 10))
	th.set_stylebox("hover", "Button", box(Color("2c1d14"), GOLD, 2, 6, 10))
	th.set_stylebox("pressed", "Button", box(Color("120a06"), GOLD_HI, 2, 6, 10))
	th.set_stylebox("disabled", "Button", box(Color(GLAZE, 0.6), Color(CLAY, 0.35), 2, 6, 10))
	th.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), GOLD_HI, 2, 6, 10))
	th.set_stylebox("panel", "PanelContainer", box(Color(GLAZE, 0.96), CLAY, 2, 8, 16))
	th.set_stylebox("panel", "Panel", box(Color(GLAZE, 0.96), CLAY, 2, 8, 0))
	th.set_stylebox("normal", "LineEdit", box(INK, CLAY, 1, 4, 6))
	th.set_color("font_color", "RichTextLabel", CREAM)
	th.set_font("normal_font", "RichTextLabel", Fonts.serif(500))
	th.set_font("bold_font", "RichTextLabel", Fonts.serif(800))
	_theme = th
	return th


static func label(text: String, size: int = 20, color: Color = CREAM, weight: int = 600, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_override("font", Fonts.serif(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


static func num_label(text: String, size: int = 24, color: Color = GOLD_HI, align: int = HORIZONTAL_ALIGNMENT_RIGHT) -> Label:
	var l: Label = label(text, size, color, 700, align)
	l.add_theme_font_override("font", Fonts.cinzel(700))
	return l


static func button(text: String, gold: bool = false, size: int = 22) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_font_override("font", Fonts.serif(800 if gold else 700))
	if gold:
		b.add_theme_stylebox_override("normal", box(Color("3a2410"), GOLD, 2, 6, 12))
		b.add_theme_stylebox_override("hover", box(Color("4a2e14"), GOLD_HI, 3, 6, 12))
		b.add_theme_color_override("font_color", GOLD_HI)
	b.focus_mode = Control.FOCUS_ALL
	return b


static func tex_rect(key: StringName, size: Vector2) -> TextureRect:
	var r: TextureRect = TextureRect.new()
	r.texture = SpriteDB.tex(key)
	r.custom_minimum_size = size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return r


## 神像圆章：god_<name> → ic_<name> → 墨色圆加希腊首字母
static func god_icon(god: StringName, size: float) -> Control:
	var key: StringName = god if String(god).begins_with("god_") else StringName("god_" + String(god))
	if SpriteDB.has(key):
		return tex_rect(key, Vector2(size, size))
	var alt: StringName = StringName("ic_" + String(god).trim_prefix("god_"))
	if SpriteDB.has(alt):
		return tex_rect(alt, Vector2(size, size))
	var p: Panel = Panel.new()
	p.custom_minimum_size = Vector2(size, size)
	p.add_theme_stylebox_override("panel", box(INK, CLAY, 2, int(size / 2.0), 0))
	return p


## 全屏遮罩 + 居中容器
static func overlay(dim: float = 0.55) -> Control:
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.02, dim)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	return root
