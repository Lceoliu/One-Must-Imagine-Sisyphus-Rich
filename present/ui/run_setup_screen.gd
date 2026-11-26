class_name RunSetupScreen
extends Control
## 开局设置（= 网页 ui.js showRunSetup；布局在 run_setup_screen.tscn）：选石头（未解锁的写解锁条件）、签冥府契约（热度 ≤ 上限，余烬 ×(1+0.1·热度)）、
## 有「血之传承」时选一支天赋（前 2 个公开节点各送 1 级）。记住上一代的选择（仍合法时）。

signal start_pressed(stone: String, pacts: Dictionary, blood: String)
signal back_pressed

static var last_setup: Dictionary = {}

const SCENE: String = "res://present/ui/run_setup_screen.tscn"

var content: ContentDB
var meta: Dictionary = {}
var allow_back: bool = true
var _stone: String = "basic"
var _pacts: Dictionary = {}
var _blood: String = ""
var _stones_box: VBoxContainer
var _pacts_box: VBoxContainer
var _blood_box: HFlowContainer = null
var _heat: Label
var _sum: Label
var _t: float = 0.0


static func create() -> RunSetupScreen:
	return SceneCache.make(SCENE) as RunSetupScreen


func _ready() -> void:
	if not last_setup.is_empty():
		var ls: String = str(last_setup.get("stone", "basic"))
		if MetaLogic.stone_unlocked(meta, ls) and content.stone_on(StringName(ls)):
			_stone = ls
		_pacts = MetaLogic.sanitize_pacts(content, last_setup.get("pacts", {}), int(meta["heat_max"]))
		_blood = str(last_setup.get("blood", ""))
	(%Title as Label).text = Loc.t("run_setup_screen.generation_setup", "第 %d 代 · 开局") % int(meta["gen"])
	_stones_box = %Stones
	_pacts_box = %Pacts
	var has_blood: bool = (meta["heir"] as Dictionary).has("hl_blood")
	(%BloodHead as Control).visible = has_blood
	(%Blood as Control).visible = has_blood
	_blood_box = %Blood if has_blood else null
	_heat = %Heat
	(%PactsLocked as Control).visible = not content.heat_on() or int(meta["heat_max"]) <= 0
	if not content.heat_on():
		# EA：热度机制先不开放——契约一栏只留标题和「暂未开放」，开头那句也不提契约
		(%PactsLocked as Label).text = Loc.t("run_setup_screen.not_available_yet", "暂未开放")
		(%Intro as Control).visible = false
		_heat.visible = false
	_sum = %Sum
	var bb: Button = %Back
	bb.visible = allow_back
	bb.pressed.connect(func() -> void: back_pressed.emit())
	var go: Button = %Go
	go.text = Loc.t("run_setup_screen.begin_generation", "开始第 %d 代") % int(meta["gen"])
	go.pressed.connect(_go)
	_render()


func _render() -> void:
	for c: Node in _stones_box.get_children():
		_stones_box.remove_child(c)
		c.queue_free()
	for s: MetaDefs.Stone in content.stones:
		_stones_box.add_child(_stone_card(s))
	var heat: int = MetaLogic.heat_of(content, _pacts)
	_heat.text = Loc.t("run_setup_screen.not_available_yet", "暂未开放") if not content.heat_on() else Loc.t("run_setup_screen.unavailable", "未开放") if int(meta["heat_max"]) <= 0 else Loc.t("run_setup_screen.heat_embers", "热度 %d / %d · 余烬 ×%s") % [heat, int(meta["heat_max"]), Js.to_fixed(1.0 + 0.1 * heat, 1)]
	for c: Node in _pacts_box.get_children():
		_pacts_box.remove_child(c)
		c.queue_free()
	for p: MetaDefs.Pact in content.pacts:
		if content.pact_on(p.id):
			_pacts_box.add_child(_pact_row(p))
	if _blood_box != null:
		for c: Node in _blood_box.get_children():
			_blood_box.remove_child(c)
			c.queue_free()
		for br: Dictionary in content.branches:
			var bid: String = str(br.get("id", ""))
			var first: PackedStringArray = []
			for n: NodeDef in content.nodes:
				if String(n.br) == bid and not n.hidden and first.size() < 2:
					first.append(n.name)
			var b: Button = UiKit.button("%s · %s" % [str(br.get("name", "")), Loc.t("run_setup_screen.list_sep", "、").join(first)], _blood == bid, 15)
			b.pressed.connect(func() -> void:
				_blood = "" if _blood == bid else bid
				Sfx.play(&"click")
				_render()
				)
			_blood_box.add_child(b)
	var st: MetaDefs.Stone = content.stone_by_id[StringName(_stone)]
	var dl: int = int(_pacts.get("pk_deadline", 0))
	var parts: PackedStringArray = [st.text("name")]
	if content.heat_on():
		parts.append(Loc.t("run_setup_screen.heat", "热度 %d") % heat)
	if dl > 0:
		parts.append(Loc.t("run_setup_screen.deadline_reach_summit_before", "期限：第 %d 天前登顶") % MetaLogic.DEADLINE_DAYS[dl])
	if _blood_box != null:
		parts.append(Loc.t("run_setup_screen.blood_inheritance", "血之传承：") + (_branch_name(_blood) if _blood != "" else Loc.t("run_setup_screen.none_selected", "未选")))
	_sum.text = " · ".join(parts)


func _branch_name(id: String) -> String:
	for br: Dictionary in content.branches:
		if str(br.get("id", "")) == id:
			return str(br.get("name", id))
	return id


func _stone_card(s: MetaDefs.Stone) -> Control:
	var open: bool = content.stone_on(s.id)
	var ok: bool = open and MetaLogic.stone_unlocked(meta, String(s.id))
	var on: bool = _stone == String(s.id)
	var b: Button = Button.new()
	b.custom_minimum_size = Vector2(540, 92)
	b.add_theme_stylebox_override("normal", UiKit.box(UiKit.INK, UiKit.GOLD if on else Color(UiKit.MUTED, 0.5 if ok else 0.25), 3 if on else 1, 8, 8))
	b.add_theme_stylebox_override("hover", UiKit.box(Color("2a1b13"), UiKit.CREAM, 2, 8, 8))
	var h: HBoxContainer = HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 12)
	b.add_child(h)
	var disc: Control = UiKit.tex_rect(s.sprite, Vector2(64, 64)) if s.sprite != &"" and SpriteDB.has(s.sprite) else _disc()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not open:
		# 没开放的石头：整张卡灰掉、点不动
		b.disabled = true
		b.add_theme_stylebox_override("disabled", UiKit.box(UiKit.INK, Color(UiKit.MUTED, 0.2), 1, 8, 8))
		b.modulate = Color(0.55, 0.55, 0.55, 0.8)
		disc.modulate = Color(0.35, 0.35, 0.35)
	h.add_child(disc)
	var v: VBoxContainer = VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	v.add_child(UiKit.label(s.text("name"), 18, UiKit.GOLD_HI if on else (UiKit.CREAM if open else UiKit.MUTED), 800))
	var desc: String = Loc.t("run_setup_screen.not_available_yet", "暂未开放") if not open else s.text("mech") if ok else Loc.t("run_setup_screen.locked", "未解锁 · ") + s.text("unlock")
	if ok and s.text("day") != "—":
		desc += Loc.t("run_setup_screen.daytime", "\n白天：") + s.text("day")
	var dl: Label = UiKit.label(desc, 13, UiKit.CREAM if ok else UiKit.MUTED, 500)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size.x = 440
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(dl)
	for c: Node in v.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(func() -> void:
		if not ok:
			Sfx.play(&"denied")
			return
		Sfx.play(&"click")
		_stone = String(s.id)
		_render()
		)
	return b


func _disc() -> Control:
	var p: Panel = Panel.new()
	p.custom_minimum_size = Vector2(64, 64)
	p.add_theme_stylebox_override("panel", UiKit.box(UiKit.INK, Color("e9d3a8"), 2, 32, 0))
	return p


func _pact_row(p: MetaDefs.Pact) -> Control:
	var lv: int = int(_pacts.get(String(p.id), 0))
	var locked: bool = int(meta["heat_max"]) <= 0
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var nm: Label = UiKit.label(p.name, 16, UiKit.GOLD_HI if lv > 0 else UiKit.CREAM, 700)
	nm.custom_minimum_size.x = 130
	h.add_child(nm)
	for k: int in p.max_lv:
		var want: int = k + 1
		var pip: Button = UiKit.button(["Ⅰ", "Ⅱ", "Ⅲ"][k], k < lv, 14)
		pip.custom_minimum_size = Vector2(38, 32)
		pip.disabled = locked
		pip.pressed.connect(func() -> void:
			var nxt: int = want - 1 if lv == want else want
			var trial: Dictionary = _pacts.duplicate()
			trial[String(p.id)] = nxt
			if MetaLogic.heat_of(content, trial) > int(meta["heat_max"]):
				Sfx.play(&"denied")
				return
			if nxt > 0:
				_pacts[String(p.id)] = nxt
			else:
				_pacts.erase(String(p.id))
			Sfx.play(&"click")
			_render()
			)
		h.add_child(pip)
	var txt: Label = UiKit.label((Loc.t("run_setup_screen.compensation", "%s · 补偿：%s") % [p.txt(lv), p.comp(lv)]) if lv > 0 else (Loc.t("run_setup_screen.pair_sep", "%s　·　%s") % [p.txt(1), p.comp(1)]), 13, UiKit.TERRA if lv > 0 else UiKit.MUTED, 600)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size.x = 380
	h.add_child(txt)
	return h


func _process(dt: float) -> void:
	_t += dt


func _go() -> void:
	if _t < 0.4:
		return
	Sfx.play(&"click")
	last_setup = {"stone": _stone, "pacts": _pacts.duplicate(), "blood": _blood}
	start_pressed.emit(_stone, _pacts.duplicate(), _blood if _blood_box != null else "")


func _unhandled_input(ev: InputEvent) -> void:
	var k: InputEventKey = ev as InputEventKey
	if k != null and k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		_go()
