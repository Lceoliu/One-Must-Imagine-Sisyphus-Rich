class_name PickPanel
extends Control
## 选择面板（= 网页 openPickPanel；布局在 pick_panel.tscn，卡面在 pick_card.tscn）：v0.6 删掉每日神龛、祭坛不再选卡之后，只剩登顶菜单、通知这类模态在用。
## 先按 min_show 展示，再出卡。
## 选择：鼠标点卡；数字键 1–5；←/→ 选中 + 回车/空格确认。防误触：卡面出现 0.4 秒内不响应，忽略按键连发。

signal chosen(i: int)
signal reroll_requested

const SCENE: String = "res://present/ui/pick_panel.tscn"

var m: ModalRequest
var _cards: Array[Control] = []
var _sel: int = -1
var _open_t: float = -1.0
var _t: float = 0.0
var _box: HBoxContainer
var _knock_lbl: Label
var _reroll_btn: Button
var _done: bool = false


static func create() -> PickPanel:
	return SceneCache.make(SCENE) as PickPanel


func setup(p_m: ModalRequest) -> void:
	m = p_m


func _ready() -> void:
	var mythic: bool = m.payload.get("variant", &"") == &"mythic"
	(%Dim as ColorRect).color.a = 0.82 if mythic else 0.5
	_knock_lbl = %Knock
	_build()
	_set_visible_cards(false)


func _build() -> void:
	(%Title as Label).text = String(m.payload.get("title", ""))
	(%Sub as Label).text = String(m.payload.get("sub", ""))
	_box = %Box
	for c: Node in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var cards: Array = m.payload.get("cards", [])
	for i: int in cards.size():
		var c: PickCard = PickCard.create()
		c.setup(cards[i], i)
		c.gui_input.connect(_on_card_input.bind(i))
		c.mouse_entered.connect(func() -> void: _select(i))
		_box.add_child(c)
		_cards.append(c)
	(%Hint as Label).text = String(m.payload.get("foot", Loc.t("pick_panel.click_card_or_press", "点击卡片或按 1–%d 选择") % cards.size()))
	_reroll_btn = %Reroll
	_reroll_btn.visible = m.reroll_left > 0
	_reroll_btn.text = Loc.t("pick_panel.reroll_before_gods_left", "神前再掷（剩 %d）") % m.reroll_left
	_reroll_btn.pressed.connect(func() -> void: if _ready_for_input(): reroll_requested.emit())
	var sk: Button = %Skip
	sk.visible = m.allow_skip
	sk.text = String(m.payload.get("skip_label", Loc.t("pick_panel.pay_respects_pass", "向神致意，不取")))
	sk.pressed.connect(func() -> void: _choose(-1))
	var note: String = String(m.payload.get("skip_note", ""))
	sk.tooltip_text = note
	var sn: Label = %SkipNote
	sn.text = (Loc.t("pick_panel.pass", "不取：") + note) if note != "" else ""
	sn.visible = note != ""
	var held: Label = %Held
	held.text = String(m.payload.get("held", ""))
	held.visible = held.text != ""


func _set_visible_cards(v: bool) -> void:
	(%Cards as Control).visible = v
	_knock_lbl.visible = not v


func _ready_for_input() -> bool:
	return _open_t >= 0.0 and _t - _open_t >= 0.4 and not _done


func _process(dt: float) -> void:
	_t += dt
	if _open_t < 0.0:
		var n: int = clampi(int(_t / 0.18) + 1, 1, 3)
		_knock_lbl.text = Loc.t("pick_panel.knock", "叩 · ").repeat(n).trim_suffix(" · ")
		if _t >= m.min_show:
			_open_t = _t
			_set_visible_cards(true)


func _select(i: int) -> void:
	_sel = i
	for k: int in _cards.size():
		_cards[k].scale = Vector2.ONE * (1.04 if k == i else 1.0)
		_cards[k].pivot_offset = _cards[k].size / 2.0


func _on_card_input(ev: InputEvent, i: int) -> void:
	var mb: InputEventMouseButton = ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_choose(i)


func _choose(i: int) -> void:
	if not _ready_for_input():
		# 叩击 / 神话演出中：点一下跳过（神话 1 秒后）
		if _open_t < 0.0 and _t > minf(1.0, m.min_show * 0.5):
			_t = m.min_show
		return
	_done = true
	chosen.emit(i)


func _unhandled_input(ev: InputEvent) -> void:
	var k: InputEventKey = ev as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	get_viewport().set_input_as_handled()
	var n: int = _cards.size()
	if k.keycode >= KEY_1 and k.keycode <= KEY_5:
		var i: int = k.keycode - KEY_1
		if i < n:
			_choose(i)
	elif k.keycode == KEY_LEFT or k.keycode == KEY_A:
		_select(clampi(_sel - 1, 0, n - 1) if _sel >= 0 else 0)
	elif k.keycode == KEY_RIGHT or k.keycode == KEY_D:
		_select(clampi(_sel + 1, 0, n - 1) if _sel >= 0 else 0)
	elif k.keycode == KEY_ENTER or k.keycode == KEY_SPACE or k.keycode == KEY_KP_ENTER:
		if _open_t < 0.0:
			_choose(0)
		elif _sel >= 0:
			_choose(_sel)
