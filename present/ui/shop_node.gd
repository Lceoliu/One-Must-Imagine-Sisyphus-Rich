class_name ShopNodeButton
extends Button
## 商店里的一个天赋节点（布局在 shop_node.tscn：图标 + 名字 + 等级点 + 价格）。ShopScreen 用 setup() 填内容，边框颜色按状态换。

signal hovered(text: String)
signal bought

const SCENE: String = "res://present/ui/shop_node.tscn"


static func create() -> ShopNodeButton:
	return SceneCache.make(SCENE) as ShopNodeButton


func setup(sim: SimGame, n: NodeDef, state: StringName) -> void:
	var st: Stats = sim.stats
	var lv: int = int(sim.levels.get(String(n.key), 0))
	var mx: int = Pricing.max_level(n, st)
	var unlocked: bool = Pricing.is_unlocked(sim.content, n, sim.levels, st)
	var cost: float = Pricing.node_cost(sim.content, n, lv, st)
	var cost2: float = Pricing.moira_cost(n, lv)
	var can_pay: bool = Pricing.affordable(sim.content, n, lv, st, sim.money, sim.moira)
	var full: bool = lv >= mx
	var border: Color = UiKit.GOLD if n.q else UiKit.CLAY
	if state == &"sealed":
		border = Color(UiKit.MUTED, 0.5)
	add_theme_stylebox_override("normal", UiKit.box(UiKit.GLAZE, border, 2, 6, 6))
	var ic: TextureRect = %Icon
	ic.texture = SpriteDB.tex(StringName("ic_" + String(n.key)))
	if state == &"sealed":
		ic.modulate = Color(0.15, 0.12, 0.1, 0.7)
	var nm: Label = %Name
	nm.text = n.name if state != &"sealed" else Loc.t("shop_node.locked", "？？？")
	nm.add_theme_color_override("font_color", UiKit.CREAM if unlocked else UiKit.MUTED)
	var dots: String = ""
	for i: int in n.max_lv:
		dots += "●" if i < lv else ("○" if i < mx else "◌")
	(%Dots as Label).text = dots
	var price: String
	if state == &"sealed":
		price = Loc.t("shop_node.sealed", "封印中")
	elif full:
		price = Loc.t("shop_node.maxed", "已满")
	elif not unlocked:
		price = Loc.t("shop_node.buy_one_above_first", "先点前一个")
	elif n.cur == &"moira":
		price = Loc.t("shop_node.fate", "命运 ") + NumFmt.fmt(cost2)
	elif cost2 > 0.0:
		price = Loc.t("shop_node.fate_2", "%s ＋ 命运 %s") % [NumFmt.fmt(cost), NumFmt.fmt(cost2)]
	else:
		price = NumFmt.fmt(cost)
	var pl: Label = %Price
	pl.text = price
	var ok_col: Color = UiKit.CREAM if n.cur == &"moira" else UiKit.GOLD_HI
	pl.add_theme_color_override("font_color", ok_col if (unlocked and not full and can_pay) else UiKit.MUTED)
	if state == &"sealed" or full or not unlocked:
		pl.add_theme_font_override("font", Fonts.serif(700))
	var tip: String = "%s · %s%s" % [n.name, n.desc, (Loc.t("shop_node.tip_line", "  —— %s") % n.line) if n.line != "" else ""] if state != &"sealed" else Loc.t("shop_node.sealed", "封印中")
	mouse_entered.connect(func() -> void: hovered.emit(tip))
	pressed.connect(func() -> void:
		if Pricing.buy(sim, n):
			bought.emit()
		)
