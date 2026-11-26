class_name BloodlineScreen
extends Control
## 血脉结算（= 网页 ui.js showBloodline；布局在 bloodline_screen.tscn）：左边余烬明细（冥府人事部离职证明），右边祖传节点树（用余烬买给下一代），
## 有「西西弗斯之名」时可以给自己的石碑刻一句话。按钮「传给第 N 代」。
## 买节点会原地改 meta；每次买完发 meta_changed（main 负责写盘）。

signal meta_changed
signal next_pressed(stele_text: String, gen: int)

const SCENE: String = "res://present/ui/bloodline_screen.tscn"

var content: ContentDB
var meta: Dictionary = {}
var _bal: Label
var _tree: GridContainer
var _tip_name: Label
var _tip_desc: Label
var _input: LineEdit = null
var _t: float = 0.0
var _gen: int = 1


static func create() -> BloodlineScreen:
	return SceneCache.make(SCENE) as BloodlineScreen


func _ready() -> void:
	var lr: Dictionary = meta.get("last_run", {})
	_gen = int(lr.get("gen", maxi(1, int(meta["gen"]) - 1)))
	var eid: StringName = StringName(str(lr.get("ending_id", "")))
	(%Title as Label).text = Loc.t("bloodline_screen.bloodline_generation_ends", "血脉 · 第 %d 代落幕") % _gen
	(%Sub as Label).text = Loc.t("bloodline_screen.underworld_hr_exit_certificate", "冥府人事部 · 离职证明 No.%04d · 离职原因「%s」%s") % [_gen, MetaLogic.ending_name(content, eid), Loc.t("bloodline_screen.underworld_debt_collection_embers", " · 冥府收债，余烬 ×0.8") if bool(lr.get("debt", false)) else ""]
	_ledger(lr)
	_tree = %Tree
	_tip_name = %TipName
	_tip_desc = %TipDesc
	(%Unlocks as Label).text = _unlock_line()
	var go: Button = %Go
	go.text = Loc.t("bloodline_screen.pass_generation", "传给第 %d 代") % int(meta["gen"])
	go.pressed.connect(_go)
	_render_tree()
	Sfx.play(&"stamp")


func _ledger(lr: Dictionary) -> void:
	var v: VBoxContainer = %Rows
	for c: Node in v.get_children():
		v.remove_child(c)
		c.queue_free()
	for p: Variant in lr.get("parts", []):
		v.add_child(_row(str((p as Array)[0]), "+" + Js.to_fixed(float((p as Array)[1]), 1), UiKit.CREAM))
	v.add_child(_row(Loc.t("bloodline_screen.total", "合计"), Js.to_fixed(float(lr.get("base", 0.0)), 1), UiKit.GOLD_HI))
	if int(lr.get("heat", 0)) > 0:
		v.add_child(_row(Loc.t("bloodline_screen.pacts_heat", "冥府契约 · 热度 %d") % int(lr["heat"]), "×" + Js.to_fixed(float(lr.get("heat_mult", 1.0)), 1), UiKit.CREAM))
	if int(lr.get("fixed", 0)) > 0:
		v.add_child(_row(Loc.t("bloodline_screen.deadline_met", "期限达成"), "+%d" % int(lr["fixed"]), UiKit.CREAM))
	if bool(lr.get("debt", false)):
		v.add_child(_row(Loc.t("bloodline_screen.underworld_collects", "冥府收债"), "×0.8", UiKit.TERRA))
	(%Embers as Label).text = "+%d" % int(float(lr.get("embers", 0.0)))
	_bal = %Balance
	var my: Dictionary = {}
	for s: Variant in meta.get("steles", []):
		if int((s as Dictionary).get("gen", 0)) == _gen:
			my = s
	var has_stele: bool = not my.is_empty() and float(my.get("alt", 0.0)) > 0.0
	var sl: Label = %Stele
	sl.visible = has_stele
	var can_carve: bool = has_stele and (meta["heir"] as Dictionary).has("hl_name")
	(%EpitaphHead as Control).visible = can_carve
	var le: LineEdit = %Epitaph
	le.visible = can_carve
	# 场景里的 12 是按汉字定的；英文字母窄，放宽到 24
	le.max_length = 24 if Loc.is_en() else 12
	if has_stele:
		var where: String = Loc.t("bloodline_screen.summit", "山顶") if float(my["alt"]) >= 1000.0 else Loc.t("bloodline_screen.at_altitude", " %d 米处") % int(my["alt"])
		sl.text = Loc.t("bloodline_screen.stele_stands_generation_day", "你的石碑立在%s：「第 %d 代 · 第 %d 日 · %s」") % [where, _gen, int(my.get("day", 0)), MetaLogic.stele_name(content, my)]
	if can_carve:
		_input = le
		_input.text = str(my.get("text", ""))


func _row(a: String, b: String, col: Color) -> Control:
	var h: HBoxContainer = HBoxContainer.new()
	var l: Label = UiKit.label(a, 17, col, 600)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(UiKit.num_label(b, 18, col))
	return h


func _render_tree() -> void:
	_bal.text = Loc.t("bloodline_screen.embers_lifetime", "现有余烬 %d · 累计 %d") % [int(meta["embers"]), int(meta.get("ember_total", 0.0))]
	for c: Node in _tree.get_children():
		_tree.remove_child(c)
		c.queue_free()
	# 按 row / col 排：4 层，每层最多 5 个
	var cells: Dictionary = {}
	for h: MetaDefs.Heirloom in content.heirlooms:
		cells[Vector2i(h.col, h.row)] = h
	for row: int in 4:
		for col: int in 5:
			var h2: MetaDefs.Heirloom = cells.get(Vector2i(col, row))
			if h2 == null:
				var sp: Control = Control.new()
				sp.custom_minimum_size = Vector2(118, 96)
				_tree.add_child(sp)
				continue
			_tree.add_child(_heir_cell(h2))


func _heir_cell(h: MetaDefs.Heirloom) -> Control:
	var state: StringName = MetaLogic.heir_state(content, meta, h.id)
	var col: Color = {&"owned": UiKit.GOLD_HI, &"can": UiKit.GOLD, &"poor": UiKit.MUTED, &"locked": Color(UiKit.MUTED, 0.4)}.get(state, UiKit.MUTED)
	var b: Button = Button.new()
	b.custom_minimum_size = Vector2(118, 96)
	b.add_theme_stylebox_override("normal", UiKit.box(UiKit.INK if state != &"owned" else Color("2a1b10"), col, 2 if state != &"locked" else 1, 8, 6))
	b.add_theme_stylebox_override("hover", UiKit.box(Color("2a1b13"), UiKit.CREAM, 2, 8, 6))
	b.add_theme_stylebox_override("pressed", UiKit.box(Color("2a1b13"), UiKit.CREAM, 2, 8, 6))
	var v: VBoxContainer = VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(v)
	# 英文祖传名长：图标缩小、名字换行两行、字号小一档（中文照旧）
	var en: bool = Loc.is_en()
	if en:
		v.add_theme_constant_override("separation", 0)
	var ic: TextureRect = UiKit.tex_rect(h.icon, Vector2(32, 32) if en else Vector2(40, 40))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.modulate = Color(1, 1, 1, 0.4 if state == &"locked" else 1.0)
	v.add_child(ic)
	var nl: Label = UiKit.label(h.name, 12 if en else 13, col, 700, HORIZONTAL_ALIGNMENT_CENTER)
	if en:
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size.x = 108.0
		nl.max_lines_visible = 2
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nl)
	var cl: Label = UiKit.label(Loc.t("bloodline_screen.owned", "已拥有") if state == &"owned" else Loc.t("bloodline_screen.embers", "%d 余烬") % int(h.cost), 12, col, 600, HORIZONTAL_ALIGNMENT_CENTER)
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cl)
	b.mouse_entered.connect(func() -> void:
		_tip_name.text = Loc.t("bloodline_screen.embers_2", "%s · %d 余烬") % [h.name, int(h.cost)]
		var req: PackedStringArray = []
		for r: String in h.req:
			var rh: MetaDefs.Heirloom = content.heirloom_by_id.get(StringName(r))
			if rh != null:
				req.append(rh.name)
		_tip_desc.text = h.desc + (Loc.t("bloodline_screen.requires", "（需要：%s）") % Loc.t("bloodline_screen.list_sep", "、").join(req) if not req.is_empty() and state == &"locked" else "")
		)
	b.pressed.connect(func() -> void:
		if MetaLogic.buy_heirloom(content, meta, h.id):
			Sfx.play(&"buy")
			meta_changed.emit()
			_render_tree()
		else:
			Sfx.play(&"denied")
		)
	return b


func _unlock_line() -> String:
	var parts: PackedStringArray = []
	if content.heat_on():
		parts.append(Loc.t("bloodline_screen.heat_cap", "热度上限 %d%s") % [int(meta["heat_max"]), "" if int(meta["heat_max"]) > 0 else Loc.t("bloodline_screen.unlocks_after_first_clear", "（通关一次后开放）")])
	var st: PackedStringArray = []
	for s: MetaDefs.Stone in content.stones:
		if s.id != &"basic" and content.stone_on(s.id) and MetaLogic.stone_unlocked(meta, String(s.id)):
			st.append(s.text("name"))
	if not st.is_empty():
		parts.append(Loc.t("bloodline_screen.stones_unlocked", "已解锁石头：") + Loc.t("bloodline_screen.list_sep", "、").join(st))
	var rw: PackedStringArray = []
	for r: Variant in content.raw.get("meta/heat_rewards.json", []):
		if content.heat_reward_on(StringName(str((r as Dictionary).get("id", "")))) and int(meta.get("heat_best", -1)) >= int((r as Dictionary)["heat"]):
			rw.append(str(r["name"]))
	if not rw.is_empty():
		parts.append(Loc.t("bloodline_screen.heat_rewards", "热度奖励：") + Loc.t("bloodline_screen.list_sep", "、").join(rw))
	return " · ".join(parts)


func _process(dt: float) -> void:
	_t += dt


func _go() -> void:
	if _t < 0.5:
		return
	Sfx.play(&"click")
	# 输入框已经按语言限了长度（中文 12、英文 24）；这里按宽的那个截
	next_pressed.emit(_input.text.strip_edges().left(24) if _input != null else "", _gen)


func _unhandled_input(ev: InputEvent) -> void:
	var k: InputEventKey = ev as InputEventKey
	if k != null and k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and (_input == null or not _input.has_focus()):
		get_viewport().set_input_as_handled()
		_go()
