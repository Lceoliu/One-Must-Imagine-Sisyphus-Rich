extends HBoxContainer
## 冥府工资条的一行（布局在 payslip_row.tscn，PayslipScreen 按数据一行行实例化）：
## 左边一格小图标（物件精灵 / 三张叠放 / 命运线轴），文字，点线引到右边的金额（= ui.js rowEl）。
## 没有金额的说明行：文字占满整行、可以折行，不画点线。

## 行的种类（和 PayslipScreen 里 _rows 的第 4 项一致）
const NORMAL: int = 0
const INFO: int = 1      # 说明小字（石径、连碾、剧情）
const GOLD: int = 2      # 神性 / 门（金额用金色 + 黑釉描边；金色只给神和门）
const WARN: int = 3      # 扣钱、没撞到门：黑绘陶瓶的"加红"

const INK: Color = Color("120c0a")
const RED: Color = Color("7c2214")
const GOLD_C: Color = Color("d9a441")
const SERIF_500: FontVariation = preload("res://present/ui/fonts/serif_500.tres")
const SERIF_700: FontVariation = preload("res://present/ui/fonts/serif_700.tres")


func _ready() -> void:
	(%Leader as Control).draw.connect(_draw_leader)
	(%Spool as Control).draw.connect(_draw_spool)


## icon：精灵 key（StringName）/ 几个 key 的数组（叠放）/ &"moira"（代码画的线轴）/ null（空一格，保持对齐）
func setup(text: String, value: String, kind: int, icon: Variant = null, note: String = "") -> void:
	var t: Label = %Text
	var v: Label = %Value
	var nt: Label = %Note
	t.text = text
	v.text = value
	v.visible = value != ""
	nt.text = note
	nt.visible = note != ""
	(%Leader as Control).visible = value != ""
	# 没有金额：文字占满、能折行（长句不撑宽陶板）
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL if value == "" else Control.SIZE_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if value == "" else TextServer.AUTOWRAP_OFF
	var col: Color = RED if kind == WARN else INK
	if kind == INFO:
		t.add_theme_font_override("font", SERIF_500)
		t.add_theme_font_size_override("font_size", 17)
		col = Color(INK, 0.74)
	t.add_theme_color_override("font_color", col)
	if kind == GOLD:
		v.add_theme_color_override("font_color", GOLD_C)
		v.add_theme_color_override("font_outline_color", INK)
		v.add_theme_constant_override("outline_size", 4)
		v.add_theme_font_size_override("font_size", 23)
	else:
		v.add_theme_color_override("font_color", col)
	_set_icon(icon)


func _set_icon(icon: Variant) -> void:
	var ic: TextureRect = %Icon
	var st: Control = %Stack
	var sp: Control = %Spool
	ic.texture = null
	st.visible = false
	sp.visible = false
	ic.visible = true
	if icon is StringName and icon == &"moira":
		ic.visible = false
		sp.visible = true
	elif icon is Array:
		var ks: Array = icon
		if ks.size() > 1:
			ic.visible = false
			st.visible = true
			for i: int in 3:
				var tr: TextureRect = st.get_child(i) as TextureRect
				tr.texture = _tex(ks[i]) if i < ks.size() else null
				tr.visible = tr.texture != null
		elif ks.size() == 1:
			ic.texture = _tex(ks[0])
	elif icon != null:
		ic.texture = _tex(icon)


static func _tex(key: Variant) -> Texture2D:
	var k: StringName = StringName(str(key))
	return SpriteDB.tex(k) if k != &"" and SpriteDB.has(k) else null


## 点线引导（= 网页的 dotted border），落在文字基线附近
func _draw_leader() -> void:
	var l: Control = %Leader
	var y: float = l.size.y * 0.66
	var x: float = 4.0
	while x < l.size.x - 4.0:
		l.draw_circle(Vector2(x, y), 1.2, Color(INK, 0.5))
		x += 7.0


func _draw_spool() -> void:
	var s: Control = %Spool
	MoiraIcon.draw(s, s.size / 2.0, s.size.y * 0.47)
