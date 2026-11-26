class_name MenuScreen
extends Control
## 主菜单（2026-10-15 重做，布局在 menu_screen.tscn）：整屏就是一只陶瓶的瓶腹——浅陶土底、上面回纹饰带、下面舌形纹瓶足；
## 瓶腹上画着一道山坡，西西弗斯在坡上永远推着石头（present/ui/menu_stage.gd，游戏里同一套骨骼动画）。
## 标题和菜单项都是写在陶土上的黑字（PaintedButton：选中时一道黑釉色带刷到字后面，字变象牙色）；
## "直接体验滚下山"是坡脚地平线上大小不同的四块石头（PaintedStone）。
## 设计画布 1920×1080（Canvas），按窗口等比缩放居中；陶土底、上下饰带铺满整个窗口。
## 发出 chosen(id, arg)：id = continue / new / gallery / settings / feedback / credits / quit / demo（arg = 石头半径）。

signal chosen(id: String, arg: float)

## [半径（米）, 名字, 画面上的半径（像素）]
## 不是 const：文字要按当前语言取（Loc.t），所以每次建界面时现算
var DEMO_STONES: Array = [[0.9, Loc.t("menu_screen.pebble_1_8_m", "卵石 1.8m"), 20.0], [2.6, Loc.t("menu_screen.ox_cart_5_m", "牛车级 5m"), 30.0], [5.0, Loc.t("menu_screen.sanctuary_10_m", "神殿级 10m"), 42.0], [9.0, Loc.t("menu_screen.titan_18_m", "泰坦级 18m"), 55.0]]
const DESIGN: Vector2 = Vector2(1920, 1080)
const TOP_H: float = 64.0
const BOTTOM_H: float = 100.0
const INK: Color = Color("120c0a")

const SCENE: String = "res://present/ui/menu_screen.tscn"

## [{id, label, gold}]
var buttons: Array = []
var gen_line: String = ""
var redfig: bool = false
## 不播放大淡出、直接回调的项（比如要先弹确认框的「重新开始本代」）
var instant: PackedStringArray = []
var _canvas: Control
var _stage: MenuStage
var _content: VBoxContainer
var _zoom_t: float = -1.0
var _pick: Array = []
var _t: float = 0.0
var _scale: float = 1.0
## 盖在开始页面上的弹层（设置、反馈、制作人员、首次说明……）；空 = 没有
var _overlay: Control = null
var _focus_back: Control = null


static func create() -> MenuScreen:
	return SceneCache.make(SCENE) as MenuScreen


## 角落的版本号（主菜单、暂停菜单都显示；玩家反馈时能报出版本）
static func version_text() -> String:
	return Loc.t("menu_screen.early_access_v", "抢先体验 v%s") % str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


func _ready() -> void:
	_canvas = %Canvas
	_stage = %Stage
	_content = %Content
	if redfig:
		(%Clay as TextureRect).modulate = Color(1.0, 0.86, 0.76)
	(%Version as Label).text = version_text()
	# 英文版大标题已经是 One Must Imagine Sisyphus Rich，下面这行同样的英文副标题就不重复了
	(get_node(^"Canvas/Content/Sub") as Label).visible = not Loc.is_en()
	var rule: Control = %Rule
	rule.draw.connect(func() -> void:
		# 回纹细线（黑）
		var x: float = 0.0
		while x < rule.size.x:
			var pts: PackedVector2Array = [Vector2(x + 1, 11), Vector2(x + 1, 1.5), Vector2(x + 9, 1.5), Vector2(x + 9, 8), Vector2(x + 4.5, 8), Vector2(x + 4.5, 5), Vector2(x + 6.5, 5)]
			rule.draw_polyline(pts, Color(INK, 0.85), 1.5)
			rule.draw_line(Vector2(x, 11), Vector2(x + 12, 11), Color(INK, 0.85), 1.5)
			x += 12.0
		)
	var gl: Label = %GenLine
	gl.text = gen_line
	gl.visible = gen_line != ""
	var font_btn: Font = load("res://present/ui/fonts/serif_700.tres") as Font
	var col: VBoxContainer = %Buttons
	_clear(col)
	var first: Control = null
	for b: Dictionary in buttons:
		var pb: PaintedButton = PaintedButton.new()
		pb.font = font_btn
		pb.primary = bool(b.get("gold", false))
		pb.font_size = 34 if pb.primary else 27
		pb.text = String(b["label"])
		var id: String = String(b["id"])
		pb.pressed.connect(func() -> void: _go(id, 0.0))
		col.add_child(pb)
		if first == null:
			first = pb
	var srow: HBoxContainer = %Stones
	_clear(srow)
	var font_s: Font = load("res://present/ui/fonts/serif_600.tres") as Font
	for d: Array in DEMO_STONES:
		var ps: PaintedStone = PaintedStone.new()
		ps.stone_r = float(d[0])
		ps.label = String(d[1])
		ps.radius_px = float(d[2])
		ps.font = font_s
		ps.size_flags_vertical = Control.SIZE_SHRINK_END
		var r: float = ps.stone_r
		ps.pressed.connect(func() -> void: _go("demo", r))
		srow.add_child(ps)
	resized.connect(_layout)
	_layout()
	if first != null:
		first.call_deferred("grab_focus")


## 在开始页面上盖一层（开始页面留在后面、压暗）。弹层打开期间菜单按钮、石头拿不到焦点
func overlay(c: Control) -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	else:
		_focus_back = get_viewport().gui_get_focus_owner()
	_overlay = c
	# 放大淡出（开始 / 继续）播完才弹的弹层（"重新开始本代？"）：先把画面复位，不然弹层跟着整页一起透明
	if _zoom_t != -1.0:
		_zoom_t = -1.0
		modulate.a = 1.0
		_content.modulate.a = 1.0
		(%StoneBox as Control).modulate.a = 1.0
		_layout()
	c.z_index = 100     # 西西弗斯的骨骼部件带 z_index（最高 13），弹层要压在它们上面
	add_child(c)
	_menu_focus(false)


func close_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_menu_focus(true)


func has_overlay() -> bool:
	return _overlay != null and is_instance_valid(_overlay)


## 关弹层后把焦点还给菜单项；这一帧里又开了新弹层（连着的提示）就不抢
func _refocus(c: Control) -> void:
	if not has_overlay() and is_instance_valid(c) and c.is_inside_tree():
		c.grab_focus()


func current_overlay() -> Control:
	return _overlay if has_overlay() else null


func _menu_focus(on: bool) -> void:
	var first: Control = null
	for n: Node in (%Buttons as Node).get_children() + (%Stones as Node).get_children():
		var c: Control = n as Control
		if c == null:
			continue
		c.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
		if first == null:
			first = c
	if on:
		var back: Control = _focus_back if _focus_back != null and is_instance_valid(_focus_back) and _focus_back.is_inside_tree() else first
		_focus_back = null
		if back != null:
			_refocus.call_deferred(back)


static func _clear(n: Node) -> void:
	for c: Node in n.get_children():
		n.remove_child(c)
		c.queue_free()


## 设计画布按窗口等比缩放（整张画都看得见），居中；上下饰带按同一比例定高
func _layout() -> void:
	_scale = minf(size.x / DESIGN.x, size.y / DESIGN.y)
	_canvas.scale = Vector2.ONE * _scale
	_canvas.position = (size - DESIGN * _scale) * 0.5
	(%TopBand as TextureRect).offset_bottom = TOP_H * _scale
	(%BottomBand as TextureRect).offset_top = -BOTTOM_H * _scale
	_canvas.pivot_offset = _stage.stone_center()


func _go(id: String, arg: float) -> void:
	if _zoom_t >= 0.0 or _t < 0.3 or has_overlay():
		return
	Sfx.play(&"click")
	if id in ["quit", "gallery", "settings", "feedback", "credits", "records"] or instant.has(id):
		chosen.emit(id, arg)
		return
	_pick = [id, arg]
	_zoom_t = 0.0


func _process(dt: float) -> void:
	_t += dt
	if _zoom_t < 0.0:
		return
	# 选中开始 / 继续 / 体验：镜头推向坡上的石头，整幅画淡出（0.9 秒）再回调
	_zoom_t += dt
	var k: float = clampf(_zoom_t / 0.9, 0.0, 1.0)
	var e: float = k * k * k
	_canvas.scale = Vector2.ONE * _scale * (1.0 + 1.6 * e)
	_content.modulate.a = maxf(0.0, 1.0 - _zoom_t / 0.3)
	(%StoneBox as Control).modulate.a = _content.modulate.a
	modulate.a = 1.0 - k * k
	if _zoom_t >= 0.9:
		_zoom_t = -2.0
		chosen.emit(String(_pick[0]), float(_pick[1]))
