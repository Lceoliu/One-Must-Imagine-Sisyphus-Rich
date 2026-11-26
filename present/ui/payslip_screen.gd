class_name PayslipScreen
extends Control
## 冥府工资条（= ui.js showPayslip；陶板布局在 payslip_screen.tscn，每一行是 payslip_row.tscn）：
## 冥府书记员坐在陶板左边记账；明细逐行刻出来（0.26 秒一行），结算行在虚线下面，
## 最后整局赐福、总额（德拉克马金币）浮现，冥府印盖下去，出现按钮。
## 所有行一开始就排好（透明），逐行显形——陶板不会边刻边长高、跳来跳去。
## 防误触：出现 0.4 秒内不响应；按键连发忽略；刻完后再等 0.4 秒才能按按钮。

signal next_pressed

const SCENE: String = "res://present/ui/payslip_screen.tscn"
const ROW_SCENE: PackedScene = preload("res://present/ui/payslip_row.tscn")
const STEP: float = 0.26

## 行种类（= payslip_row.gd）
const K_NORMAL: int = 0
const K_INFO: int = 1
const K_GOLD: int = 2
const K_WARN: int = 3

## 结算区的额外收入（赐福 v2 的 data.extra）没带图标时，按名字配一个。
## 名字和产生它的 sim 代码用同一个翻译 key，所以中英文都对得上
static func _extra_icon() -> Dictionary:
	return {Loc.t("hades_rule.underworld_overtime_pay", "冥府加班费"): &"god_hades", Loc.t("apollo_rule.encore", "安可"): &"god_apollo",
		Loc.t("dionysus_rule.grapevines", "葡萄藤"): &"grape_cluster"}


## 明细里不是"碾平某物"的几类（SimGame.add_night_bonus 的 label）：图标
static func _label_icon() -> Dictionary:
	return {Loc.t("sim_game.slam_2", "砸地"): &"ic_slam", Loc.t("sim_game.jar_burst", "陶瓮迸裂"): &"ic_potters"}

var data: Dictionary = {}
var button_label: String = Loc.t("payslip_screen.feast", "去夜宴")
var _rows: Array[Control] = []
var _i: int = 0
var _t: float = 0.0
var _acc: float = 0.0
var _done_t: float = -1.0
var _late: Array[CanvasItem] = []
var _btn: Button
var _fitted: bool = false


static func create() -> PayslipScreen:
	return SceneCache.make(SCENE) as PayslipScreen


func _ready() -> void:
	(%Head as Label).text = (Loc.t("payslip_screen.underworld_payslip_night", "冥府工资条 · 第 %d 夜") % int(data.get("day", 1))) if not bool(data.get("demo", false)) else Loc.t("payslip_screen.downhill_run_underworld_payslip", "滚落体验 · 冥府工资条")
	var box: VBoxContainer = %Box
	var settle: VBoxContainer = %Settle
	# 场景里的示例行只给编辑器预览
	for host: Node in [box, settle]:
		for c: Node in host.get_children():
			host.remove_child(c)
			c.queue_free()
	_boons()
	(%Net as Label).text = NumFmt.fmt(float(data.get("net", 0.0)))
	(%Stamp as Label).text = Loc.t("payslip_screen.sisyphus_rich", "应当想象\n西西弗斯\n很有钱") if String(data.get("stamp", "")) == "" else String(data["stamp"])
	_btn = %Next
	_btn.text = button_label
	_btn.pressed.connect(func() -> void: if _done_t >= 0.0 and _t - _done_t >= 0.4: next_pressed.emit())
	var specs: Array = _make_rows()
	for r: Array in specs:
		var row: Control = ROW_SCENE.instantiate()
		row.call("setup", r[1], r[2], r[3], r[4], r[5])
		row.modulate.a = 0.0
		(box if r[0] == 0 else settle).add_child(row)
		_rows.append(row)
	(%SettleRule as CanvasItem).visible = settle.get_child_count() > 0
	# 最后才浮现的：赐福、总额、印、按钮（按钮占着位置但透明、不接鼠标，陶板不会跳）
	_late = [%BoonRow, %Total, %Seal, _btn]
	for c: CanvasItem in _late:
		c.modulate.a = 0.0
	_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_btn.focus_mode = Control.FOCUS_NONE


## 整局赐福：每个点亮的祭坛一枚小胶囊（神像 + 名字）；场景里的第一枚是模板
func _boons() -> void:
	var chips: Container = %Chips
	var tpl: Control = chips.get_child(0) as Control
	chips.remove_child(tpl)
	var bo: Array = data.get("boons", [])
	for b: Dictionary in bo:
		var ch: Control = tpl.duplicate() as Control
		(ch.get_node("H/Name") as Label).text = String(b.get("name", ""))
		var god: StringName = StringName(String(b.get("god", "")))
		(ch.get_node("H/God") as TextureRect).texture = SpriteDB.tex(god) if SpriteDB.has(god) else null
		chips.add_child(ch)
	tpl.free()
	(%BoonRow as Control).visible = not bo.is_empty()


## 一行 = [区（0 明细 / 1 结算）, 文字, 金额, 种类, 图标, 小注]
func _make_rows() -> Array:
	var settle: Array = []
	for x: Dictionary in data.get("extra", []):
		var v: float = float(x.get("v", 0.0))
		var lab: String = String(x.get("label", ""))
		var ic: Variant = StringName(String(x["icon"])) if x.has("icon") else _extra_icon().get(lab, null)
		settle.append([1, lab, ("−" if v < 0.0 else "+") + NumFmt.fmt(absf(v)), K_NORMAL, ic, ""])
	var gate: Dictionary = data.get("gate", {})
	if not gate.is_empty():
		settle.append([1, Loc.t("payslip_screen.underworld_gate_struck_seals", "撞冥府之门 · 破封 %d 重") % int(gate["seals"]), "×" + Js.to_fixed(float(gate["mult"]), 2), K_GOLD, &"hades_gate", ""])
	elif String(data.get("reason", "")) == "blocked":
		settle.append([1, Loc.t("payslip_screen.stopped_stone_isn_t", "被「%s」挡下 —— 石头还不够大") % String(data.get("blocked_by", "")), "", K_WARN, &"city_wall", ""])
	else:
		settle.append([1, Loc.t("payslip_screen.stone_stopped_halfway_underworld", "石头停在了半路，没撞到冥府之门"), "", K_WARN, &"gate_small", ""])
	if float(data.get("after", 0.0)) > 0.0:
		settle.append([1, Loc.t("payslip_screen.aftershock_debris_paid_out", "余震 · 残骸再结算"), "+" + NumFmt.fmt(float(data["after"])), K_NORMAL, &"ic_aftershock", ""])
	if float(data.get("fire", 0.0)) > 0.0:
		settle.append([1, Loc.t("payslip_screen.prometheus_fire_burnt_debris", "普罗米修斯余烬"), "+" + NumFmt.fmt(float(data["fire"])), K_NORMAL, &"item_fire", ""])
	if float(data.get("cut", 0.0)) > 0.0:
		settle.append([1, Loc.t("payslip_screen.atropos_final_cut_whole", "阿特洛波斯的最后一剪 · 整条山坡再结算"), "+" + NumFmt.fmt(float(data["cut"])), K_GOLD, &"ic_fate", ""])
	if float(data.get("tax_rate", 0.0)) > 0.0:
		settle.append([1, Loc.t("payslip_screen.hades_underworld_tax", "哈迪斯冥界税 −%s%%") % Js.num_str(roundf(float(data["tax_rate"]) * 1000.0) / 10.0), "−" + NumFmt.fmt(float(data.get("tax", 0.0))), K_WARN, &"ic_hadesbook", ""])
	if float(data.get("debt", 0.0)) > 0.0:
		settle.append([1, Loc.t("payslip_screen.repaid_autolycus_remaining_chain", "还奥托吕科斯（锁链余款）"), "−" + NumFmt.fmt(float(data["debt"])), K_WARN, &"item_chain", ""])
	# 提喀的盘口：白天推过押注高度就当场兑现了 / 日落时赌本归庄——这里只列出来，不进今夜到手
	var bet: Dictionary = data.get("bet", {})
	if not bet.is_empty():
		var h: int = int(float(bet.get("h", 0.0)))
		if bool(bet.get("won", false)):
			settle.append([1, Loc.t("payslip_screen.tyche_s_bets_m", "提喀的盘口 · 押 %d m 中了 ×%s") % [h, Js.to_fixed(float(bet.get("odds", 0.0)), 2)], "+" + NumFmt.fmt(float(bet.get("win", 0.0))), K_GOLD, &"chip_tyche", Loc.t("payslip_screen.paid_during_day", "白天已入账")])
		else:
			settle.append([1, Loc.t("payslip_screen.tyche_s_bets_m_2", "提喀的盘口 · 押 %d m 没推到") % h, "−" + NumFmt.fmt(float(bet.get("stake", 0.0))), K_WARN, &"chip_tyche", Loc.t("payslip_screen.house_kept_stake", "赌本已归庄")])
	# 神的机制小结（价值已算在碾压明细里）
	for x: Dictionary in data.get("school", []):
		if String(x.get("text", "")) != "":
			var g: String = String(x.get("god", ""))
			settle.append([1, String(x["text"]), "", K_GOLD if g != "" else K_INFO, StringName("god_" + g) if g != "" else null, ""])
	if float(data.get("moira", 0.0)) > 0.0:
		settle.append([1, Loc.t("payslip_screen.fate_urns_yielded_fate", "命运宝瓶摇到命运 %s（拿去火堆旁找三女神）") % NumFmt.fmt(float(data["moira"])), "", K_GOLD, &"moira", ""])
	if String(data.get("city_up", "")) != "":
		if _is_gilded(String(data["city_up"])):
			settle.append([1, Loc.t("payslip_screen.gods_couldn_t_watch", "众神看不下去了：连夜用大理石和金子把城重建 →「神造之城」（更难碾，陶罐更值钱）"), "", K_GOLD, &"acropolis", ""])
		else:
			settle.append([1, Loc.t("payslip_screen.city_foot_mountain_was", "山脚的城被连夜重建得更繁华了 →「%s」") % data["city_up"], "", K_INFO, &"acropolis", ""])
	for s: Variant in data.get("story", []):
		settle.append([1, String(s), "", K_INFO, null, ""])
	# 明细：结算行多的夜里少列几类，陶板不出屏
	var tally: Array = data.get("tally", [])
	var tight: bool = settle.size() > 8
	var top: int = 3 if tight else 5
	var rows: Array = []
	for k: int in mini(top, tally.size()):
		var tl: Dictionary = tally[k]
		if bool(tl.get("label", false)):
			rows.append([0, "%s ×%d" % [tl["name"], int(tl["n"])], "+" + NumFmt.fmt(float(tl["v"])), K_NORMAL, _label_icon().get(String(tl["name"]), null), ""])
		else:
			rows.append([0, Loc.t("payslip_screen.crushed", "碾平 %s ×%d") % [tl["name"], int(tl["n"])], "+" + NumFmt.fmt(float(tl["v"])), K_NORMAL, StringName(String(tl.get("type", ""))), ""])
	if tally.size() > top:
		var nn: int = 0
		var vv: float = 0.0
		var ics: Array = []
		for k: int in range(top, tally.size()):
			nn += int(tally[k]["n"])
			vv += float(tally[k]["v"])
			if ics.size() < 3:
				ics.append(StringName(String(tally[k].get("type", ""))))
		rows.append([0, Loc.t("payslip_screen.other_types", "其余 %d 类 ×%d") % [tally.size() - top, nn], "+" + NumFmt.fmt(vv), K_NORMAL, ics, ""])
	if tally.is_empty():
		rows.append([0, Loc.t("payslip_screen.nothing_crushed", "什么也没碾到"), "0", K_INFO, null, ""])
	if tight:
		return rows + settle   # 结算行很多的夜里，石径 / 连碾这两行小字让位
	var grow: float = float(data.get("end_r", 1.0)) / maxf(0.01, float(data.get("start_r", 1.0))) - 1.0
	rows.append([0, Loc.t("payslip_screen.stone_diameter_m_m", "石径 %sm → %sm（一路粘大 %d%%）") % [Js.to_fixed(float(data.get("start_r", 0.0)) * 2.0, 1), Js.to_fixed(float(data.get("end_r", 0.0)) * 2.0, 1), roundi(grow * 100.0)], "", K_INFO, &"boulder_etched", ""])
	var crits: Dictionary = data.get("crits", {})
	var cs: String = (Loc.t("payslip_screen.heavy_crush_perfect_good", " · 重压 %d 完美 / %d 良好") % [int(crits.get("perfect", 0)), int(crits.get("good", 0))]) if int(crits.get("perfect", 0)) + int(crits.get("good", 0)) > 0 else ""
	rows.append([0, Loc.t("payslip_screen.longest_crush_combo", "最长连碾 %d%s") % [int(data.get("max_combo", 0)), cs], "", K_INFO, null, ""])
	return rows + settle


## 刻出一行：淡入 + 从左边滑进来一点
func _show_row(row: Control, instant: bool) -> void:
	if instant:
		row.modulate.a = 1.0
		return
	var tw: Tween = row.create_tween()
	tw.tween_property(row, "modulate:a", 1.0, 0.22).from(0.0)


func _finish() -> void:
	if _done_t >= 0.0:
		return
	while _i < _rows.size():
		_show_row(_rows[_i], true)
		_i += 1
	for c: CanvasItem in [%BoonRow, %Total, _btn]:
		c.create_tween().tween_property(c, "modulate:a", 1.0, 0.25)
	# 总额：放大落下
	var net: Label = %Net
	net.pivot_offset = net.size / 2.0
	var tn: Tween = net.create_tween()
	tn.tween_property(net, "scale", Vector2.ONE, 0.35).from(Vector2(1.25, 1.25)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 冥府印：从大处砸下来
	var seal: Control = %Seal
	var ts: Tween = seal.create_tween().set_parallel()
	ts.tween_property(seal, "modulate:a", 1.0, 0.12)
	ts.tween_property(seal, "scale", Vector2.ONE, 0.32).from(Vector2(2.2, 2.2)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play(&"stamp")
	_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_btn.focus_mode = Control.FOCUS_ALL
	_btn.grab_focus()
	_done_t = _t


## 极端的夜（结算行特别多、长句折行）：排好版后整张陶板仍高出屏幕，就整体缩到放得下
func _fit() -> void:
	_fitted = true
	var st: Control = %Stack
	var avail: float = size.y - 24.0
	if st.size.y > avail and st.size.y > 0.0:
		st.pivot_offset = st.size / 2.0
		st.scale = Vector2.ONE * (avail / st.size.y)


func _process(dt: float) -> void:
	if not _fitted and _t > 0.0:
		_fit()
	_t += dt
	if _done_t >= 0.0:
		return
	_acc += dt
	while _acc >= STEP and _i < _rows.size():
		_acc -= STEP
		_show_row(_rows[_i], false)
		_i += 1
	if _i >= _rows.size() and _acc >= STEP:
		_finish()


func _gui_input(ev: InputEvent) -> void:
	var mb: InputEventMouseButton = ev as InputEventMouseButton
	if mb != null and mb.pressed and _t > 0.4:
		_finish()


func _unhandled_input(ev: InputEvent) -> void:
	var k: InputEventKey = ev as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode != KEY_ENTER and k.keycode != KEY_SPACE and k.keycode != KEY_KP_ENTER:
		return
	get_viewport().set_input_as_handled()
	if _t < 0.4:
		return
	if _done_t < 0.0:
		_finish()
	elif _t - _done_t >= 0.4:
		next_pressed.emit()


## 升到的是不是「神造之城」（city_levels.json 里 gilded 的那一档）。按名字找档，名字随语言变，不能写死中文
static func _is_gilded(city: String) -> bool:
	for lv: Dictionary in Content.db.city_levels:
		if bool(lv.get("gilded", false)):
			return String(lv.get("name", "")) == city
	return false
