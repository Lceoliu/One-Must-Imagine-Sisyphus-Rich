class_name ShopScreen
extends Control
## 赫尔墨斯小摊（= ui.js showShop 的"天赋"页签；外框在 shop_screen.tscn，节点按钮是 shop_node.tscn）：各支天赋各一列，公开节点按深度排开。
## 两种钱：德拉克马；命运（三女神的三支只收命运，全场速览里不列它们，要去火堆旁找她们）。
## 点节点买一级（钱够、已解锁、未满级）；回车或"开工"进入下一天。
## 夜宴里（present/hub/）同一个界面拆给各位神：branches 只列这位神管的几支，mode 决定底部按钮。

signal start_pressed
## 夜宴里关掉这个摊（回到宴会）
signal closed

const SCENE: String = "res://present/ui/shop_screen.tscn"

var sim: SimGame = null
## 只显示这几支（空 = 全部八支）
var branches: PackedStringArray = []
var title: String = Loc.t("shop_screen.hermes_stall", "赫尔墨斯小摊")
var subtitle: String = Loc.t("shop_screen.earn_downhill_spend_feast", "钱从山下赚，货在夜宴买，概不赊账。")
## &"start"：开工（老流程）；&"station"：夜宴里某位神的摊（回到宴会）；&"overview"：夜宴全场速览（回到宴会 / 天亮开工）
var mode: StringName = &"start"
var _money: Label
var _grid: HBoxContainer
var _tip: Label
var _t: float = 0.0


static func create() -> ShopScreen:
	return SceneCache.make(SCENE) as ShopScreen


func _ready() -> void:
	(%Title as Label).text = title
	(%Sub as Label).text = subtitle
	_money = %Money
	_grid = %Grid
	_tip = %Tip
	_tip.text = ""
	if _narrow():
		_grid.alignment = BoxContainer.ALIGNMENT_CENTER
	var prog: Dictionary = Pricing.visible_progress(sim.content, sim.levels)
	(%Progress as Label).text = Loc.t("shop_screen.progress", "完成度 %d / %d") % [int(prog["done"]), int(prog["total"])]
	var back: Button = %Back
	back.visible = mode != &"start"
	back.pressed.connect(func() -> void: if _t > 0.3: closed.emit())
	var go: Button = %Go
	go.visible = mode != &"station"
	go.text = (Loc.t("shop_screen.sunrise_day", "天亮 · 第 %d 日") if mode == &"overview" else Loc.t("shop_screen.clock_day", "开工 · 第 %d 日")) % sim.day
	go.pressed.connect(func() -> void: if _t > 0.3: start_pressed.emit())
	if mode == &"overview":
		back.add_theme_stylebox_override("normal", UiKit.box(UiKit.GLAZE, UiKit.CLAY, 2, 6, 10))
		back.remove_theme_color_override("font_color")
	_rebuild()


## 摇到过命运（之后到处都显示命运）
static func moira_open(s: SimGame) -> bool:
	return s.moira > 0.0 or float(s.run_stats.get("moira_total", 0.0)) > 0.0


## 只有一到四支时不撑满整屏：每列固定宽度、居中
func _narrow() -> bool:
	return not branches.is_empty() and branches.size() <= 4


func _rebuild() -> void:
	for c: Node in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_money.text = NumFmt.fmt(sim.money)
	var mo: bool = moira_open(sim)
	(%Moira as Label).visible = mo
	(%MoiraUnit as Label).visible = mo
	(%Moira as Label).text = NumFmt.fmt(sim.moira)
	var st: Stats = sim.stats
	for br: Dictionary in sim.content.branches:
		if not branches.is_empty() and not branches.has(String(br.get("id", ""))):
			continue
		if branches.is_empty() and str(br.get("cur", "")) == "moira":
			continue
		var col: VBoxContainer = VBoxContainer.new()
		if _narrow():
			col.custom_minimum_size.x = 360
		else:
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 6)
		_grid.add_child(col)
		var bh: VBoxContainer = VBoxContainer.new()
		bh.add_child(UiKit.label(String(br.get("name", "")), 30, UiKit.GOLD_HI, 900, HORIZONTAL_ALIGNMENT_CENTER))
		bh.add_child(UiKit.label(String(br.get("sub", "")), 13, UiKit.MUTED, 500, HORIZONTAL_ALIGNMENT_CENTER))
		col.add_child(bh)
		var nodes: Array[NodeDef] = []
		for n: NodeDef in sim.content.nodes:
			# 隐藏质变节点原来靠神卡解封；神卡体系删掉后先不显示（v0.6 第 6.3、6.4 节：改成命运 / 两种货币）
			if n.hidden:
				continue
			if String(n.br) == String(br.get("id", "")):
				nodes.append(n)
		nodes.sort_custom(func(a: NodeDef, b: NodeDef) -> bool: return a.depth < b.depth)
		for n: NodeDef in nodes:
			col.add_child(_node_btn(n, Pricing.node_state(n, sim.levels, st)))


func _node_btn(n: NodeDef, state: StringName) -> Control:
	var b: ShopNodeButton = ShopNodeButton.create()
	b.setup(sim, n, state)
	if Loc.is_en() and not _narrow():
		# 英文节点名长：放不下的用省略号（悬停栏里有全名），全场速览里再小一档
		for key: String in ["%Name", "%Price"]:
			var lb: Label = b.get_node(key) as Label
			lb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			if mode == &"overview":
				lb.add_theme_font_size_override("font_size", 14 if key == "%Name" else 12)
	b.hovered.connect(func(text: String) -> void: _tip.text = text)
	b.bought.connect(_rebuild)
	return b


func _process(dt: float) -> void:
	_t += dt


func _unhandled_input(ev: InputEvent) -> void:
	var k: InputEventKey = ev as InputEventKey
	if k == null or not k.pressed or k.echo or _t <= 0.3:
		return
	if mode == &"start" and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		start_pressed.emit()
	elif mode != &"start" and (k.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER] or ev.is_action_pressed(&"interact") or ev.is_action_pressed(&"overview")):
		get_viewport().set_input_as_handled()
		closed.emit()
