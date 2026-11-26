class_name BetScreen
extends Control
## 提喀的高度盘（docs/v05/feast-hub.md §4；布局在 bet_screen.tscn，墓碑上的刻度和筹码由 BetBoard 画）。
## 打开时用影子推演（ShadowDay）算明天的机器人高度 H_bot（HubView 按天和天赋缓存），BetOdds 给出 μ、s、开盘区间和赔率。
## 玩家挪自己的筹码选高度，赌本用滑动条选手头的 1%–100%（← → 也能调）；押下去钱当场扣，天亮前可以撤回。只收德拉克马。
## 金线 = 最高纪录，碑上一直看得见（视野一定包含它）。

signal closed
## 押下了（HubView 记下这时的天赋签名，天亮封盘时对比）
signal placed

const SCENE: String = "res://present/ui/bet_screen.tscn"
## 赌本默认手头的一成
const STAKE_DEFAULT: int = 10

var sim: SimGame = null
## 影子推演的机器人高度（HubView 传进来）
var h_bot: float = 0.0
var _mu: float = 0.0
var _s: float = 0.15
var _gold: float = 0.0
## 明天的起点海拔（纪录 × 新纺的线）：不到它的高度不开盘
var _floor: float = 0.0
var _open: Array[int] = [-1, -1]
var _h: float = 0.0
## 赌本占手头的百分比（1–100）
var _pct: int = STAKE_DEFAULT
var _t: float = 0.0
var _board: BetBoard


static func create() -> BetScreen:
	return SceneCache.make(SCENE) as BetScreen


func _ready() -> void:
	_board = %Board
	_board.height_dragged.connect(func(v: float) -> void:
		if sim.bet.is_empty():
			_set_h(v)
		)
	var sl: HSlider = %StakeSlider
	sl.value = _pct
	sl.value_changed.connect(_on_stake_slider)
	(%Place as Button).pressed.connect(_place)
	(%Cancel as Button).pressed.connect(func() -> void:
		sim.cancel_bet()
		Sfx.play(&"click")
		_refresh()
		)
	(%Back as Button).pressed.connect(func() -> void: if _t > 0.2: closed.emit())
	var lines: Array = (sim.content.hub.get("talk", {}) as Dictionary).get("tyche", [])
	if not lines.is_empty():
		(%Quote as Label).text = Loc.t("bet_screen.tyche", "提喀：") + str(lines[sim.day % lines.size()])
	_setup_model()
	_refresh()


func _setup_model() -> void:
	var m: Dictionary = BetOdds.model(h_bot, sim.run_stats.get("bet_hist", []))
	_mu = float(m["mu"])
	_s = float(m["s"])
	_gold = sim.record
	_floor = sim.record * sim.stats.start_frac
	_open = BetOdds.open_range(_mu, _s, _gold, _floor)
	if not sim.bet.is_empty():
		_h = float(sim.bet["h"])
	elif _open[0] >= 0:
		_h = clampf(roundf(_mu), _open[0], _open[1])
	else:
		_h = roundf(_mu)
	# 碑上的视野：开盘区间、金线、昨天的实际高度都要看得见
	var y_alt: float = sim.max_alt
	var lo: float = minf(float(_open[0]) if _open[0] >= 0 else _mu * 0.8, minf(_gold, y_alt)) * 0.92
	var hi: float = maxf(maxf(float(_open[1]) if _open[1] >= 0 else _mu * 1.4, BetOdds.height_at(0.05, _mu, _s)), _gold) * 1.04
	_board.lo = maxf(0.0, floorf(lo))
	_board.hi = ceilf(hi)
	_board.open_lo = float(_open[0])
	_board.open_hi = float(_open[1])
	_board.gold_line = _gold
	# 众神的筹码（只是彩蛋，不影响数值；§4.4）
	var R: RandomNumberGenerator = RandomNumberGenerator.new()
	R.seed = sim.day * 7919 + 17
	_board.chips = [
		{"god": "thanatos", "h": maxf(_board.lo, float(_open[0]) if _open[0] >= 0 else _board.lo)},
		{"god": "ares", "h": BetOdds.height_at(0.8, _mu, _s)},
		{"god": "demeter", "h": y_alt},
		{"god": "persephone", "h": y_alt},
		{"god": "hera", "h": _gold},
		{"god": "aphrodite", "h": _gold * 1.02},
		{"god": "athena", "h": _mu},
		{"god": "hermes", "h": BetOdds.height_at(0.65, _mu, _s)},
		{"god": "hermes", "h": BetOdds.height_at(0.35, _mu, _s)},
		{"god": "dionysus", "h": R.randf_range(_board.lo, _board.hi)},
		{"god": "hades", "h": BetOdds.height_at(0.05, _mu, _s)},
	]


func _set_h(v: float) -> void:
	if _open[0] < 0:
		return
	_h = clampf(roundf(v), _board.lo, _board.hi)
	_refresh()


func _on_stake_slider(v: float) -> void:
	_set_pct(roundi(v))


func _set_pct(p: int) -> void:
	_pct = clampi(p, 1, 100)
	_refresh()


func _stake() -> float:
	return floorf(sim.money * float(_pct) / 100.0)


func _refresh() -> void:
	var placed: bool = not sim.bet.is_empty()
	var odds: float = float(sim.bet["odds"]) if placed else BetOdds.odds(_h, _mu, _s, _gold, _floor)
	_board.h = _h
	_board.queue_redraw()
	(%Height as Label).text = Loc.t("bet_screen.target_m", "押 %d m") % int(_h)
	(%Odds as Label).text = (Loc.t("bet_screen.odds", "赔率 %s") % Js.to_fixed(odds, 2)) if odds > 0.0 else Loc.t("bet_screen.no_bets", "不开盘")
	var note: String
	if placed:
		note = Loc.t("bet_screen.bet_placed_withdraw_before", "已经押下。天亮前还能撤回；白天推过 %d m，当场兑现。") % int(_h)
	elif _open[0] < 0:
		note = Loc.t("bet_screen.tyche_isn_t_taking", "提喀今晚不开盘：明天怎么推都差不多，没有可赌的。")
	elif odds <= 0.0:
		note = Loc.t("bet_screen.no_bets_sure_things", "太稳的高度不收，赔率超过 %d 的也不收。") % int(BetOdds.ODDS_MAX)
	elif _h > _gold:
		note = Loc.t("bet_screen.above_gold_line_best", "金线（最高纪录）以上，赔率高一成。")
	else:
		note = Loc.t("bet_screen.gold_line_personal_best", "金线（最高纪录）%d m。") % int(_gold)
	(%Note as Label).text = note
	var sl: HSlider = %StakeSlider
	sl.set_value_no_signal(_pct)
	var stake: float = float(sim.bet["stake"]) if placed else _stake()
	(%StakePct as Label).text = ("%d%%" % roundi(stake / maxf(1.0, sim.money + stake) * 100.0)) if placed else ("%d%%" % _pct)
	(%StakeVal as Label).text = NumFmt.fmt(stake)
	(%Payout as Label).text = (Loc.t("bet_screen.stake_payout", "押 %s → 赢回 %s") % [NumFmt.fmt(stake), NumFmt.fmt(floorf(stake * odds))]) if odds > 0.0 else ""
	sl.editable = not placed
	(%Place as Button).visible = not placed
	(%Place as Button).disabled = odds <= 0.0 or stake <= 0.0
	(%Cancel as Button).visible = placed


func _place() -> void:
	var odds: float = BetOdds.odds(_h, _mu, _s, _gold, _floor)
	if odds <= 0.0 or not sim.place_bet(_h, _stake(), odds):
		return
	sim.note_bet_pred(sim.day, h_bot)
	placed.emit()
	Sfx.play(&"critPerfect")
	_refresh()


func _process(dt: float) -> void:
	_t += dt


func _unhandled_input(ev: InputEvent) -> void:
	var k: InputEventKey = ev as InputEventKey
	if k == null or not k.pressed:
		return
	var step: float = 5.0 if k.shift_pressed else 1.0
	match k.keycode:
		KEY_UP, KEY_W:
			if sim.bet.is_empty():
				_set_h(_h + step)
		KEY_DOWN, KEY_S:
			if sim.bet.is_empty():
				_set_h(_h - step)
		KEY_LEFT, KEY_A:
			if sim.bet.is_empty():
				_set_pct(_pct - (10 if k.shift_pressed else 1))
		KEY_RIGHT, KEY_D:
			if sim.bet.is_empty():
				_set_pct(_pct + (10 if k.shift_pressed else 1))
		KEY_ENTER, KEY_KP_ENTER:
			if not k.echo and sim.bet.is_empty():
				_place()
		KEY_ESCAPE:
			if not k.echo and _t > 0.2:
				closed.emit()
		_:
			return
	get_viewport().set_input_as_handled()
