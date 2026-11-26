class_name SimGame
extends RefCounted
## 模拟核心：白天推石 → 黄昏 → 夜晚滚落碾压 → 撞冥府之门 → 结算。逐行移植 proto/js/game.js 的模拟部分；
## 画面、声音、手感一律通过 fx 发事件（表现层消费），镜头只写目标（cam_tx / cam_ty / cam_view_h），平滑在表现层。
## 推进：tick(dt) 由 SimRunner（或机器人）以固定步长调用；输入：key_down / key_up；选择：answer。

const CHAR_TILT: float = 0.45
const SEAL_GAP: float = 0.07
## 不是 const：文字要按当前语言取（Loc.t），所以每局新建时现算
var VOICE_TXT: Dictionary = {&"bleat": Loc.t("sim_game.baa", "咩！"), &"cry": Loc.t("sim_game.hey", "哎！"), &"honk": Loc.t("sim_game.honk", "嘎！"), &"squeal": Loc.t("sim_game.squeeeal", "吱——！"), &"low": Loc.t("sim_game.moo", "哞！"), &"neigh": Loc.t("sim_game.neigh", "咴！")}

# —— 依赖 ——
var content: ContentDB
var tune: Tuning
var fx: SimFx = SimFx.new()
var rand: SimRandom = SimRandom.new()
## 回调：on_night_end(data) / on_victory(data) / save() / on_run_end(id) / play_ending(id, done: Callable)
var hooks: Dictionary = {}
var boons: BoonSystem
var story: StorySystem
var meta_rules: MetaRules
var chests: ChestSystem
var modal: ModalRequest = null
var view_aspect: float = 16.0 / 9.0

# —— 存档内容（= game.persist()）——
var meta: Dictionary = {}
var run: Dictionary = {}
var run_stats: Dictionary = {}
var day: int = 1
var money: float = 0.0
## 第二货币「命运」：命运宝瓶的转轮摇出来，三女神的店和各摊最下面的质变节点用（docs/v06/incremental.md 第 6 节）
var moira: float = 0.0
## 今夜摇到的命运（工资条用）
var night_moira: float = 0.0
## 提喀的高度盘（docs/v05/feast-hub.md §4）：夜宴里押明天推到的高度。{h, stake, odds, day, paid}；空 = 没押
var bet: Dictionary = {}
var record: float = 0.0
var levels: Dictionary = {}
var city_level: int = 0
## 山脚城镇没倒的建筑留下的裂痕：slot → dmg（跨夜保留，存档）
var city_cracks: Dictionary = {}
var ended: bool = false

# —— 一天的状态 ——
var stats: Stats
var world: World
var objs: Array[CrushObj] = []
var ruins: Array[CrushObj] = []
## 黄昏时石头身后助跑区里的物件：移出 objs（不挡石头、不计钱、不计连碾），只留给表现层画，石头挣脱滚过时顺带压平
var runup_objs: Array[CrushObj] = []
var stone: Boulder = Boulder.new()
var gate: Dictionary = {}
var phase: StringName = &"idle"
var t: float = 0.0
var last_input_t: float = -9.0
var keys: Dictionary = {}
var demo: bool = false
var buff: Dictionary = {"stele_t": 0.0, "no_back_t": 0.0, "stele_seal": 0}
var ending_active: bool = false
var _ending_done: Callable = Callable()

# 白天
var day_t: float = 0.0
var max_alt: float = 0.0
var stamina: float = 0.0
var exhausted: int = 0
var since_input: float = 9.0
var since_push: float = 9.0
var expect_key: StringName = &"L"
var rhythm: float = 0.0
var last_press_t: float = -9.0
var good_presses: int = 0
var brace_t: float = 0.0
var second_wind_t: float = 0.0
var second_wind_n: int = 0
var faint_t: float = 0.0
var slid_this_faint: float = 0.0
var slid_day: float = 0.0
var faint_log: Array[float] = []
var slide_dust_t: float = 0.0
var auto_acc: float = 0.0
var hold_acc: float = 0.0
var push_frame: int = 0
var push_n: int = 0
var bob: float = 0.0
var overtime_t: float = 0.0
var overtime_done: bool = false
var last_tier: int = 0
var sis: Dictionary = {}
var sit_pos: Dictionary = {}
var prompt: Dictionary = {"hit_t": 0.0, "miss_t": 0.0, "hit_side": &"", "alpha": 1.0}
var stamina_alpha: float = 0.0
var stamina_full_t: float = 0.0

# 黄昏
var dusk_t: float = 0.0
var dusk_dur: float = 2.8

# 夜晚
var night_t: float = 0.0
var night_total: float = 0.0
var night_total_valid: bool = false
var combo: int = 0
var combo_t: float = 0.0
var max_combo: int = 0
var tally: Dictionary = {}
var crits: Dictionary = {"perfect": 0, "good": 0}
var slam_left: int = 0
var slamming: bool = false
## 今夜第几次砸地（砸地收益按次翻倍，tune.slam_pay / slam_pay_cap）
var slam_n: int = 0
## 进城那一刻镜头往后拉（1 → 0，约 2 秒）
var cam_pull: float = 0.0
var ring: Dictionary = {}
var rest_t: float = 0.0
var last_hit: float = 0.0
var last_slow: float = -9.0
var last_knee: float = -INF
var last_land: float = -9.0
var air_t: float = 0.0
var pre_air_speed: float = 30.0
var prev_s: float = 0.0
var zeus_t: float = 0.0
var speed_stack_now: float = 0.0
var urn_n: int = 0
var urn_v: float = 0.0
var urn_burst_gate: int = 0
var urn_bursts: int = 0
var start_r: float = 0.0
var start_alt: float = 0.0
var domino_q: Array[Dictionary] = []
var blocked_by: CrushObj = null
var trail: Array[PackedFloat64Array] = []    # 每段 [x0, y0, x1, y1, w, glow]
var _last_trail: PackedFloat64Array = []
var gate_hit: bool = false
var gate_hit_night: bool = false
var gate_end_t: float = 0.0
var gate_cool: float = 0.0
var gate_e: float = 0.0
var gate_mult: float = 1.0
var night_seal_max: int = 0
var trip_t0: float = 0.0
var city_r: float = -1.0
var best_seals: int = 0
## 碾压密度（最近一秒左右碾了多少件，指数衰减）：越密，单次的顿帧 / 震屏越轻，慢放越少（碾城时手感不抽、不晕）
var crush_heat: float = 0.0
var crush_heat_t: float = 0.0
## 夜宴反应用（FeastReact）：今天开工时的纪录、今天那一注的结果、入夜前的封印纪录和三女神点头次数
var record0: float = 0.0
var bet_today: Dictionary = {}
var seals_best0: int = 0
var jackpots0: int = 0
var v_t_boost: float = 1.0
var free_slam: bool = false
var beat_hold: bool = false
var helper_value_now: float = 0.0
var chorus_lv: int = -1
var last_night: Dictionary = {}
var _wait_t: float = 0.0
var _wait_hook: StringName = &""
var _wait_data: Dictionary = {}

# 表现读取的状态
var tier_flash: float = 0.0
var combo_pulse: float = 0.0
var rumble: float = 0.0
var shake_max_px: float = 30.0
var shake_decay: float = 1.6
var cam_tx: float = 0.0
var cam_ty: float = 0.0
var cam_view_h: float = 14.0
var cam_k: float = 5.0
var cam_kz: float = 2.0
var cam_snap: int = 0      # 每次需要镜头直接对齐时 +1


func _init(p_content: ContentDB, persist: Dictionary = {}, p_meta: Dictionary = {}) -> void:
	content = p_content
	tune = content.tuning
	meta = MetaLogic.normalize(p_meta)
	run = {"gen": int(meta["gen"]), "stone": "basic", "pacts": {}, "heat": 0}
	run.merge(persist.get("run", {}), true)
	run_stats = default_run_stats()
	run_stats.merge(persist.get("run_stats", persist.get("runStats", {})), true)
	day = int(persist.get("day", 1))
	money = float(persist.get("money", 0))
	moira = float(persist.get("moira", 0))
	bet = (persist.get("bet", {}) as Dictionary).duplicate()
	record = float(persist.get("record", 0))
	levels = (persist.get("levels", {}) as Dictionary).duplicate()
	city_level = int(persist.get("city_level", persist.get("cityLevel", 0)))
	city_cracks = (persist.get("city_cracks", {}) as Dictionary).duplicate()
	ended = bool(persist.get("ended", false))
	best_seals = int(run_stats.get("max_seals", 0))
	rand.run_seed = int(run.get("seed", 1 + int(run["gen"]) * 7919))
	boons = BoonSystem.new()
	boons.bind(self, persist.get("boons", {}))
	story = StorySystem.new()
	story.bind(self, persist.get("story", {}))
	meta_rules = MetaRules.new()
	meta_rules.bind(self)
	chests = ChestSystem.new()
	chests.bind(self)


## 打断 SimGame ↔ 各系统 ↔ 规则模块之间的循环引用（RefCounted 不会自己回收环）。一局不用了就调用（换局、机器人、测试）。
func dispose() -> void:
	modal = null
	hooks = {}
	if boons != null:
		boons.dispose()
	if story.runner != null:
		story.runner.abort()
		story.runner = null
	story.g = null
	meta_rules.g = null
	chests.g = null


static func default_run_stats() -> Dictionary:
	return {"crush_total": 0.0, "max_seals": 0, "seals_by_day": {}, "ceramics": 0, "living": 0, "summit_day": 0,
		"faints": 0, "core_r": 0.0, "altars": 0, "moira_total": 0.0, "jars": 0, "jackpots": 0,
		"bets": 0, "bets_won": 0, "bet_best_odds": 0.0, "bet_hist": [], "bet_pred": {},
		"crushed": 0, "buildings": 0, "chickens": 0, "pushes": 0, "best_night": 0.0, "max_r": 0.0, "time_s": 0.0, "ach": []}


## 替换系统实现（神与祭坛 / 剧情 / 元进度由各自模块提供）
func set_systems(p_boons: BoonSystem, p_story: StorySystem, p_meta: MetaRules) -> void:
	if p_boons != null:
		p_boons.bind(self, boons.saved)
		boons = p_boons
	if p_story != null:
		p_story.bind(self, story.saved)
		story = p_story
	if p_meta != null:
		meta_rules = p_meta
		meta_rules.bind(self)


## 今日修正（DayMods）：每日神龛删掉以后没有来源，保持中性；字段留给以后的一日效果。每天开始时归零
var mods: DayMods = DayMods.new()


func persist() -> Dictionary:
	return {"v": 4, "day": day, "money": floorf(money), "moira": floorf(moira), "bet": bet.duplicate(), "record": record, "levels": levels.duplicate(), "city_level": city_level, "city_cracks": city_cracks.duplicate(),
		"run": run.duplicate(true), "run_stats": run_stats.duplicate(true), "boons": boons.save(), "story": story.save(), "ended": ended}


# —— 小接口 ——
func altitude() -> float:
	if world == null:
		return 0.0
	return world.alt_at(stone.s)


func aspect_of(type: StringName) -> float:
	return content.aspect(type)


## 盘口：押 h 米、赌本 stake、赔率 odds（夜宴里押，第二天 = day 这一天生效）；钱当场扣
func place_bet(h: float, stake: float, p_odds: float) -> bool:
	if stake <= 0.0 or stake > money or not bet.is_empty():
		return false
	money -= stake
	# lv：押注时的天赋签名（天亮封盘比对）；sealed：夜宴天亮时提喀重算过；started：这一天已经开工过
	bet = {"h": h, "stake": stake, "odds": p_odds, "day": day, "paid": false, "lv": levels_sig(), "sealed": false, "started": false}
	run_stats["bets"] = int(run_stats.get("bets", 0)) + 1
	return true


## 天赋和点亮的祭坛的签名（押注后又买了东西 = 签名变了）
func levels_sig() -> String:
	return "%s|%d" % [str(levels.hash()), boons.done.size()]


## 开工时核对押注（docs/v05/feast-hub.md §4.3 ⑤ 封盘）：
## - 这一天已经开工过（白天中途存档再继续）：没兑现的赌本归庄，不能重推一遍再赌；
## - 没经过天亮封盘（夜宴里直接回主菜单 / 退出）又在押注后买了东西：退回赌本，赔率作废。
func _open_bet_day() -> void:
	if bet.is_empty() or int(bet.get("day", -1)) != day or bool(bet.get("paid", false)):
		return
	if bool(bet.get("started", false)):
		fx.toast(Loc.t("sim_game.tyche_remembers_already_worked", "提喀记得你昨天就开过工：押在 %d m 的赌本归庄。") % int(float(bet["h"])), 3.6)
		bet = {}
		return
	if not bool(bet.get("sealed", false)) and str(bet.get("lv", "")) != levels_sig():
		money += float(bet["stake"])
		run_stats["bets"] = maxi(0, int(run_stats.get("bets", 0)) - 1)
		fx.toast(Loc.t("sim_game.left_before_tyche_closed", "没等提喀封盘就走了：赌本退回，这一注作废。"), 3.6)
		bet = {}
		return
	bet["started"] = true


## 天亮之前撤回（退钱）
func cancel_bet() -> void:
	if bet.is_empty() or bool(bet.get("paid", false)):
		return
	money += float(bet["stake"])
	bet = {}
	run_stats["bets"] = maxi(0, int(run_stats.get("bets", 0)) - 1)


## 影子推演的预测记下来（第 d 天），日落时和实际最高海拔配成一对，算玩家效率
func note_bet_pred(d: int, h_bot: float) -> void:
	run_stats["bet_pred"] = {"day": d, "h_bot": h_bot}


## 白天推过押注高度：当场兑现
func _check_bet(alt: float) -> void:
	if bet.is_empty() or bool(bet.get("paid", false)) or int(bet.get("day", -1)) != day or alt < float(bet["h"]):
		return
	var win: float = floorf(float(bet["stake"]) * float(bet["odds"]))
	money += win
	bet["paid"] = true
	bet["win"] = win
	run_stats["bets_won"] = int(run_stats.get("bets_won", 0)) + 1
	run_stats["bet_best_odds"] = maxf(float(run_stats.get("bet_best_odds", 0.0)), float(bet["odds"]))
	fx.flash(0.35, Color("ffe08a"))
	fx.sfx(&"critPerfect")
	fx.banner(Loc.t("sim_game.tyche_pays_out", "提喀兑现！"), Loc.t("sim_game.bet_m", "押 %d m × %s → +%s") % [int(float(bet["h"])), Js.to_fixed(float(bet["odds"]), 2), NumFmt.fmt(win)], 2.2)
	fx.event(&"bet_won", {"win": win, "h": bet["h"]})


## 日落：没推到的赌本归庄；今天的预测和实际配对存进历史
func _settle_bet_day() -> void:
	var pred: Dictionary = run_stats.get("bet_pred", {})
	if int(pred.get("day", -1)) == day and float(pred.get("h_bot", 0.0)) > 0.0:
		var hist: Array = run_stats.get("bet_hist", [])
		hist.append([float(pred["h_bot"]), max_alt])
		while hist.size() > 8:
			hist.pop_front()
		run_stats["bet_hist"] = hist
		run_stats["bet_pred"] = {}
	if bet.is_empty() or int(bet.get("day", -1)) != day:
		return
	if not bool(bet.get("paid", false)):
		fx.toast(Loc.t("sim_game.tyche_keeps_stake_m", "提喀收下了你押在 %d m 的赌本。") % int(float(bet["h"])), 3.2)
	bet_today = {"h": float(bet["h"]), "won": bool(bet.get("paid", false)), "odds": float(bet.get("odds", 0.0)),
		"stake": float(bet.get("stake", 0.0)), "win": float(bet.get("win", 0.0))}
	bet = {}


## 命运入账（命运宝瓶）：表现层在 (x, y) 放出线团飞向 HUD 的命运计数
func add_moira(v: float, x: float = NAN, y: float = NAN) -> void:
	if not (v > 0.0):
		return
	moira += v
	night_moira += v
	run_stats["moira_total"] = float(run_stats.get("moira_total", 0.0)) + v
	fx.event(&"moira", {"v": v}, stone.x if is_nan(x) else x, (stone.y + stone.r) if is_nan(y) else y)


## 碾压派生的额外结算（安可、葡萄藤、陶瓮、宝瓶……）：计入今夜碾得；coins = true 时在 (x, y)（缺省 = 石头）炸出等值金币给 HUD 追
func add_night_bonus(v: float, label: String = Loc.t("sim_game.treasure", "宝藏"), x: float = NAN, y: float = NAN, coins: bool = true) -> void:
	if not night_total_valid:
		return
	night_total += v
	if coins and v > 0.0:
		fx.event(&"bonus", {"v": v, "label": label}, stone.x if is_nan(x) else x, (stone.y + stone.r) if is_nan(y) else y)
	var key: String = label
	var tl: Dictionary = tally.get(key, {})
	if tl.is_empty():
		tl = {"n": 0, "v": 0.0, "label": true}
		tally[key] = tl
	tl["n"] = int(tl["n"]) + 1
	tl["v"] = float(tl["v"]) + v


## 下一次砸地的收益（HUD 提示、腾空提示用）
func next_slam_pay() -> float:
	return minf(tune.slam_pay_cap, tune.slam_pay * pow(2.0, slam_n))


func mass_norm(r: float) -> float:
	var r0: float = stats.r0 if stats != null and stats.r0 > 0.0 else tune.r0
	return clampf(log(r / r0) / log(15.0 / r0), 0.0, 1.0)


func helper_count() -> int:
	var st: Stats = stats
	return int(minf(st.helper_cap, st.ghosts + st.spartans + (1.0 if st.charon else 0.0) + (1.0 if st.cerberus else 0.0) + st.drunkards))


func size_tier(r: float) -> int:
	var tiers: Array[Dictionary] = content.size_tiers
	var ti: int = 0
	for i: int in tiers.size():
		if r >= float(tiers[i]["min"]):
			ti = i
	return ti


func make_gate() -> Dictionary:
	var h: float = 24.0
	return {"x": world.gate_x, "y": 0.0, "h": h, "w": h * aspect_of(&"hades_gate"), "shake": 0.0, "seals": 0, "hit_t": -1.0,
		"predict": 0.0, "best": best_seals, "open": 0.0, "max": int(stats.max_seals) if stats != null else 9, "seal_q": 0}


## 一天里的时刻：白天 0→1 = 06:00→18:00；黄昏 1→1.06；夜 1.06→1.56
func tod() -> float:
	match phase:
		&"day":
			return clampf(day_t / (stats.day_length + mods.day_time_add), 0.0, 1.0)
		&"dusk":
			return 1.0 + 0.06 * clampf(dusk_t / dusk_dur, 0.0, 1.0)
		&"night", &"night_end":
			return 1.06 + 0.5 * minf(1.0, night_t / 45.0)
		&"victory_wait":
			return 0.98
	return 0.5


## 夜色混合度：开工 2.5 秒的黎明淡出；黄昏 2.2 秒交叉淡入；夜 1
func night_k() -> float:
	match phase:
		&"day":
			return maxf(0.0, 0.6 * (1.0 - day_t / 2.5))
		&"dusk":
			var k: float = clampf(dusk_t / 2.2, 0.0, 1.0)
			return k * k * (3.0 - 2.0 * k)
		&"night", &"night_end":
			return 1.0
	return 0.0


func is_night() -> bool:
	return phase == &"night" or phase == &"night_end"


## 有模态 / 结局演出 / 剧情事件链进行中（祭坛、神龛等先等它结束）
func any_modal() -> bool:
	return modal != null or ending_active or (story != null and story.modal())


func open_modal(m: ModalRequest) -> void:
	modal = m
	keys.clear()
	hold_acc = 0.0
	fx.event(&"modal", {"kind": m.kind})


## 回答当前模态（i = -1 表示跳过）
func answer(i: int) -> void:
	var m: ModalRequest = modal
	if m == null:
		return
	modal = null
	if m.on_answer.is_valid():
		m.on_answer.call(i)


func reroll() -> void:
	if modal != null and modal.on_reroll.is_valid():
		modal.on_reroll.call()


# ———————————————— 白天 ————————————————
func recompute_stats() -> void:
	var st: Stats = StatsBuilder.build_nodes(content, levels)
	meta_rules.apply_meta(st)
	boons.apply_stats(st)
	story.apply_stats(st)
	stats = st


func start_day() -> void:
	recompute_stats()
	var st: Stats = stats
	rand.begin_day(day)
	buff["stele_t"] = 0.0
	buff["no_back_t"] = 0.0
	world = World.new(st.ramps, content.terrain)
	objs = world.layout(content, st, city_level, aspect_of, day, int(run["gen"]))
	_town_apply_cracks()
	runup_objs.clear()
	gate = make_gate()
	boons.layout(objs)
	record0 = record
	bet_today = {}
	var s_alt: float = record * st.start_frac
	var s0: float = world.s_at_alt(s_alt) if s_alt > 2.0 else world.s_foot + 3.0
	if st.start_back > 0.0:
		s0 = maxf(world.s_foot + 1.0, s0 - st.start_back)
	stone = Boulder.new()
	stone.s = s0
	stone.ts = s0
	max_alt = world.alt_at(s0)
	stone.r = r_day()
	place_boulder()
	stone.save_prev()
	stamina = st.stamina_max
	exhausted = 0
	since_input = 9.0
	since_push = 9.0
	brace_t = 0.0
	second_wind_t = 0.0
	second_wind_n = 0
	faint_t = 0.0
	slid_this_faint = 0.0
	slid_day = 0.0
	faint_log.clear()
	slide_dust_t = 0.0
	keys.clear()
	expect_key = &"H" if st.hold_push else &"L"
	rhythm = 0.0
	last_press_t = -9.0
	good_presses = 0
	prompt = {"hit_t": 0.0, "miss_t": 0.0, "hit_side": &"", "alpha": 1.0}
	stamina_alpha = 0.0
	stamina_full_t = 0.0
	auto_acc = 0.0
	hold_acc = 0.0
	push_frame = 0
	bob = 0.0
	day_t = 0.0
	overtime_t = 0.0
	overtime_done = false
	push_n = 0
	urn_n = 0
	urn_v = 0.0
	speed_stack_now = 0.0
	last_tier = size_tier(stone.r)
	sis = {}
	phase = &"day"
	night_total = 0.0
	night_total_valid = false
	chests.clear()
	mods.reset()
	if not demo:
		_open_bet_day()
	boons.on_day_start()
	story.new_day()
	cam_tx = stone.x + 3.0
	cam_ty = stone.y + 1.0
	cam_view_h = maxf(13.0, stone.r * 5.5)
	cam_snap += 1
	fx.event(&"phase", {"phase": &"day", "day": day})
	# 操作提示只在前两天（同屏文字预算）
	fx.banner(Loc.t("sim_game.day", "第 %d 日") % day, (Loc.t("sim_game.hold_right_push_key", "按住右推键推石上山") if st.hold_push else Loc.t("sim_game.follow_potsherd_overhead_alternate", "跟着头顶的陶片，左右交替按")) if day <= 2 else "", 2.2)
	fx.sfx(&"ambience", 0.0)
	fx.sfx(&"chorus", 0.0)
	# 契约「期限」：逾期还没登顶 → 冥府收债（本代结束）
	if st.deadline > 0.0 and day > int(st.deadline) and int(run_stats.get("summit_day", 0)) == 0 and not demo:
		play_ending(&"debt", func() -> void:
			phase = &"idle"
			if hooks.has("on_run_end"):
				(hooks["on_run_end"] as Callable).call(&"debt"))


## 盖亚地核 run_stats.core_r 直接加在当天半径上
func r_day() -> float:
	return stats.r0 + float(run_stats.get("core_r", 0.0)) + stats.growth * max_alt


func place_boulder() -> void:
	var b: Boulder = stone
	var sx: float = 0.0
	var sy: float = 0.0
	for k: int in range(-2, 3):
		var a: float = world.ang_at(b.s + k * b.r * 0.35)
		sx += cos(a)
		sy += sin(a)
	var ang: float = atan2(sy, sx)
	world.at(b.s)
	b.ang = ang
	b.x = world.ax - sin(ang) * b.r
	b.y = world.ay + cos(ang) * b.r


## 输入：key = &"L" &"R" &"strike"（空格）&"end_day"（回车）
func key_down(key: StringName, repeat: bool = false) -> void:
	if ending_active:
		return
	keys[key] = true
	last_input_t = t
	if modal != null:
		return
	if phase == &"day" and not repeat:
		if key == &"L" or key == &"R":
			if exhausted > 0:
				brace_t = tune.brace_t
				fx.sfx(&"brace")
			elif stats.hold_push:
				do_push(&"player")
			elif expect_key == key:
				expect_key = &"R" if key == &"L" else &"L"
				press_good(key)
				do_push(&"player")
			else:
				prompt["miss_t"] = 0.15
		if key == &"end_day":
			start_dusk()
	if phase == &"night" and key == &"strike" and not repeat:
		night_action()
	if phase == &"dusk" and (key == &"strike" or key == &"end_day") and dusk_t > 0.6:
		dusk_t = maxf(dusk_t, dusk_dur - 0.3)


func key_up(key: StringName) -> void:
	keys[key] = false


func release_all() -> void:
	keys.clear()
	hold_acc = 0.0


func press_good(side: StringName) -> void:
	var gap: float = t - last_press_t
	var st: Stats = stats
	var wide: float = 0.2 if float(buff["stele_t"]) > 0.0 else 0.0
	if gap >= st.rhythm_lo * (1.0 - wide) and gap <= st.rhythm_hi * (1.0 + wide):
		rhythm = minf(10.0, rhythm + 1.0)
	else:
		rhythm = floorf(rhythm / 2.0)
	last_press_t = t
	good_presses += 1
	prompt["hit_t"] = 0.16
	prompt["hit_side"] = side
	if not sis.is_empty():
		fx.sparks(float(sis["x"]) + (-0.6 if side == &"L" else 0.6), float(sis["y"]) + float(sis["h"]) + 1.2, 4, 3)


func do_push(src: StringName) -> void:
	if phase != &"day":
		return
	var st: Stats = stats
	var b: Boulder = stone
	var md: DayMods = mods
	if src == &"player":
		if exhausted > 0:
			return
		since_input = 0.0
		run_stats["pushes"] = int(run_stats.get("pushes", 0)) + 1
	var ang: float = world.ang_at(b.ts)
	var slope: float = maxf(0.0, sin(ang))
	var r_eff: float = maxf(st.r0, b.r - float(run_stats.get("core_r", 0.0)))
	var load: float = pow(r_eff / st.r0, st.load_exp + tune.load_k) * (0.45 + slope * st.slope_resist)
	# 大石头额外负重（平台期）：半径过了拐点越推越吃力，封顶；「承重」按比例抵消
	if r_eff > tune.heavy_r and tune.heavy_k > 0.0:
		load *= 1.0 + minf(tune.heavy_cap, tune.heavy_k * (r_eff - tune.heavy_r)) * (1.0 - clampf(st.heavy_relief, 0.0, 1.0))
	var steep: float = 1.0 + st.steep_bonus if ang > 35.0 * PI / 180.0 else 1.0
	var stride: float = st.stride * st.push_power * steep / load * md.push_mult
	if src == &"player" or (src == &"auto" and st.auto_rhythm):
		stride *= 1.0 + st.rhythm_step * rhythm
	var td: float = tod()
	var tod_k: float = (st.am_push + md.am_push + (st.dawn_push if td < 0.25 else 0.0)) if td < 0.5 else st.pm_push
	if tod_k != 0.0:
		stride *= 1.0 + tod_k
	if st.path_push > 0.0 and world.alt_at(b.ts) < st.path_alt:
		stride *= 1.0 + st.path_push
	if src == &"player" and second_wind_n > 0:
		stride *= 1.0 + st.second_wind
		second_wind_n -= 1
	if st.civic_push > 0.0:
		stride *= 1.0 + minf(st.civic_cap, st.civic_push * helper_count())
	if st.stride_hi > st.stride_lo:
		stride *= st.stride_lo + JsRng.new(float(day * 131 + push_n)).next() * (st.stride_hi - st.stride_lo)
		push_n += 1
	if overtime_t > 0.0:
		stride *= st.overtime_push
	if src == &"player" and not st.no_stamina and not (float(buff["stele_t"]) > 0.0):
		var cost: float = st.push_cost * pow(load, 0.35) * md.stamina_cost_mult
		stamina -= cost
		if stamina <= 0.0:
			stamina = 0.0
			exhausted = 1
			rhythm = floorf(rhythm / 2.0)
			faint_t = 0.0
			slid_this_faint = 0.0
			brace_t = 0.0
			second_wind_n = 0
			run_stats["faints"] = int(run_stats.get("faints", 0)) + 1
			fx.sfx(&"pushGrunt", 1.0)
			fx.event(&"faint")
	# 打滑：第 tune.slip_from_day 天起才会出现（默认第 3 天），退 tune.slip_back 米（默认 0.3），不打断节奏
	if src == &"player" and day >= int(tune.slip_from_day) and rand.next(SimRandom.Use.SLIP) < st.slip_chance * tune.slip_scale * (0.5 + slope):
		if md.slip_immune > 0.0:
			md.slip_immune -= 1.0
		else:
			b.ts = maxf(world.s_foot + 1.0, b.ts - tune.slip_back)
			fx.sfx(&"slip")
			fx.dust(b.x - b.r, world.y_at_x(b.x - b.r), 5, 0.4, 2.0)
			# 看得出这一下没推上去：脚下飘「打滑」，该按的陶片晃一下
			prompt["miss_t"] = 0.15
			if not sis.is_empty():
				fx.text(float(sis["x"]), float(sis["y"]) + 0.4, Loc.t("sim_game.slip", "打滑"), 18.0, SimFx.CREAM, 0.7)
			run_stats["slips"] = int(run_stats.get("slips", 0)) + 1
			run_stats["slip_m"] = float(run_stats.get("slip_m", 0.0)) + tune.slip_back
			return
	b.ts = minf(world.s_summit, b.ts + stride)
	if src == &"player":
		run_stats["push_m"] = float(run_stats.get("push_m", 0.0)) + stride
	since_push = 0.0
	push_frame = (push_frame + 1) % 6
	bob = 0.06
	if src == &"player":
		fx.sfx(&"step", clampf(load / 6.0, 0.0, 1.0))
		if not sis.is_empty():
			fx.dust(float(sis["x"]) + 0.3, sis["y"], 2, 0.25, 1.5)
		fx.punch(0.006, true)


## 累倒防护等级：0 正常；1 每次累倒最多退 1m；2 累倒不滑
func faint_guard_lv() -> int:
	var st: Stats = stats
	var helpers: int = 2 if st.helper_guard > 0.0 and helper_count() >= int(st.helper_guard) else 0
	return int(maxf(maxf(st.faint_guard, mods.faint_guard), float(helpers)))


func _update_day(dt: float) -> void:
	var st: Stats = stats
	var b: Boulder = stone
	var md: DayMods = mods
	if not (overtime_t > 0.0):
		day_t += dt * md.day_time_mult * st.day_clock
	since_input += dt
	since_push += dt
	if exhausted > 0 and stamina >= st.stamina_max * st.faint_exit:
		exhausted = 0
		faint_log.append(snappedf(slid_this_faint, 0.01))
		second_wind_n = 3
		second_wind_t = 1.2
		fx.sfx(&"secondWind")
		fx.event(&"second_wind")
	brace_t = maxf(0.0, brace_t - dt)
	second_wind_t = maxf(0.0, second_wind_t - dt)
	prompt["hit_t"] = maxf(0.0, float(prompt["hit_t"]) - dt)
	prompt["miss_t"] = maxf(0.0, float(prompt["miss_t"]) - dt)
	var want_alpha: float = 0.5 if good_presses > 30 and not st.hold_push else 1.0
	prompt["alpha"] = float(prompt["alpha"]) + (want_alpha - float(prompt["alpha"])) * minf(1.0, dt * 3.0)
	if t - last_press_t > 1.2:
		rhythm = maxf(0.0, rhythm - dt * 4.0)
	var full: bool = st.no_stamina or stamina >= st.stamina_max - 0.01
	stamina_full_t = stamina_full_t + dt if full else 0.0
	var target_a: float = 0.0 if full and stamina_full_t > 0.8 else 1.0
	stamina_alpha += (target_a - stamina_alpha) * minf(1.0, dt * (2.5 if full else 8.0))
	story.update(dt)
	meta_rules.update_steles(dt)
	boons.day_update(dt)
	if phase != &"day" or modal != null or ending_active:
		return
	# 按住推（累倒时按住 = 一直顶住）
	var holding: bool = bool(keys.get(&"R", false))
	if st.hold_push and holding:
		if exhausted > 0:
			brace_t = maxf(brace_t, tune.brace_t)
		else:
			since_input = 0.0
			hold_acc += st.hold_rate * dt
			while hold_acc >= 1.0:
				hold_acc -= 1.0
				# 按住也算节奏（2026-10-16 用户定）：原来按住推不经过 press_good，节奏加成掉光，节奏稳的玩家买了「双手」反而少三成推力
				rhythm = minf(10.0, rhythm + 1.0)
				last_press_t = t
				do_push(&"player")
	# 自动推（一指推 + 帮手；帮手推力上午 ×(1+am_helper)）
	var am_h: float = 1.0 + st.am_helper if tod() < 0.5 else 1.0
	auto_acc += (st.auto_push + st.helper_push * st.helper_mult * md.helper_mult * am_h) * dt
	while auto_acc >= 1.0:
		auto_acc -= 1.0
		do_push(&"auto")
	if st.auto_rhythm and st.auto_push > 0.0:
		rhythm = minf(10.0, rhythm + dt * 2.0)
		last_press_t = t
	# 体力恢复：累倒时强制喘气（恢复更快）；平时停手 0.35 秒后恢复
	if not st.no_stamina and (exhausted > 0 or since_input > 0.35):
		var k: float = md.regen_mult * ((1.4 * md.faint_regen) if exhausted > 0 else st.rest_regen)
		stamina = minf(st.stamina_max, stamina + st.stamina_regen * k * dt)
	# 倒滑（§1）
	var no_back: bool = md.no_backslide or float(buff["no_back_t"]) > 0.0
	var slope: float = maxf(0.0, sin(world.ang_at(b.ts)))
	var base_slide: float = st.backslide * 0.6 * (slope / 0.5)
	if exhausted > 0:
		faint_t += dt
		var guard: int = faint_guard_lv()
		if not no_back and guard < 2 and faint_t > st.faint_delay:
			var cap: float = minf(1.5, st.faint_slide_cap) if day <= 2 else st.faint_slide_cap
			if guard == 1:
				cap = minf(cap, 1.0)
			var v: float = base_slide * st.faint_slide_mult * (tune.brace_k if brace_t > 0.0 else 1.0)
			var d: float = minf(minf(v * dt, maxf(0.0, cap - slid_this_faint)), maxf(0.0, b.ts - (world.s_foot + 1.0)))
			if d > 0.0:
				b.ts -= d
				slid_this_faint += d
				slid_day += d
				slide_dust_t -= dt
				if slide_dust_t <= 0.0:
					slide_dust_t = 0.18
					world.at(b.s)
					fx.dust(world.ax, world.ay, 2, maxf(0.3, b.r * 0.3), 1.2)
	elif since_push > st.idle_grace and not no_back:
		b.ts = maxf(world.s_foot + 1.0, b.ts - base_slide * dt)
	# 平滑移动
	var ps0: float = b.s
	b.s += (b.ts - b.s) * (1.0 - exp(-14.0 * dt))
	b.rot -= (b.s - ps0) / b.r
	bob = maxf(0.0, bob - dt * 0.4)
	var alt: float = world.alt_at(b.s)
	if alt > max_alt:
		var gain: float = alt - max_alt
		max_alt = alt
		if st.sweat_pay > 0.0:
			money += gain * st.sweat_pay
		b.r = r_day()
		var ti: int = size_tier(b.r)
		if ti > last_tier:
			last_tier = ti
			_tier_up(ti)
	_check_bet(alt)
	if alt > record:
		boons.on_record(record, alt)
		_check_milestone(record, alt)
		record = alt
	place_boulder()
	place_sisyphus()
	if alt >= World.SUMMIT - 0.5:
		_victory()
		return
	# 黄昏补签（太阳落山后再推 overtime 秒，推力 ×overtime_push）
	if overtime_t > 0.0:
		overtime_t -= dt
		if overtime_t <= 0.0:
			overtime_t = 0.0
			start_dusk()
			return
	elif day_t >= st.day_length + md.day_time_add:
		if st.overtime > 0.0 and not overtime_done:
			overtime_done = true
			overtime_t = st.overtime
			fx.banner(Loc.t("sim_game.late_shift", "黄昏补签"), Loc.t("sim_game.push_more_seconds_push", "再推 %d 秒 · 推力 ×%s") % [roundi(st.overtime), Js.num_str(st.overtime_push)], 1.8)
		else:
			start_dusk()
			return
	day_camera()


## 白天镜头：框住"帮手队尾 → 石头前沿"这一整段（每帧调；截图工具摆完石头也调它）
func day_camera() -> void:
	var b: Boulder = stone
	var n_help: int = helper_count()
	var back: float = (float(sis["x"]) if not sis.is_empty() else b.x - b.r - 1.0) - 1.2 - n_help * 1.55
	var front: float = b.x + b.r + 3.0
	cam_ty = b.y + 1.0 + b.r * 0.2
	cam_view_h = clampf(maxf(maxf(13.0, b.r * 5.5), (front - back) * 1.15 / view_aspect), 13.0, maxf(13.0, b.r * 10.0))
	cam_tx = maxf((back + front) / 2.0, front - cam_view_h * view_aspect * 0.25)
	cam_k = 5.0
	cam_kz = 2.0
	rumble = 0.0


func place_sisyphus() -> void:
	var b: Boulder = stone
	var w: World = world
	var hm: float = 2.1
	var wm: float = hm * aspect_of(&"push_0")
	var hh: float = minf(1.45, b.r * 1.2)
	var slope_at: Callable = func(x: float) -> float:
		var s: float = w.s_at_x(x)
		var cx: float = 0.0
		var cy: float = 0.0
		for k: float in [-0.6, 0.0, 0.6]:
			var a: float = w.ang_at(s + k)
			cx += cos(a)
			cy += sin(a)
		return atan2(cy, cx) * CHAR_TILT
	var x_max: float = b.x - b.r * 0.3 - wm * 0.42
	var x: float = minf(x_max, b.x - b.r - wm * 0.4)
	var ang: float = 0.0
	var last_d: float = INF
	for k: int in 10:
		ang = slope_at.call(x)
		var ca: float = cos(ang)
		var sa: float = sin(ang)
		var hx: float = x + wm * 0.42 * ca - hh * sa
		var hy: float = w.y_at_x(x) + wm * 0.42 * sa + hh * ca
		var d: float = Js.hypot(hx - b.x, hy - b.y) - b.r
		if absf(d) < 0.01 or absf(d) >= absf(last_d):
			break
		last_d = d
		x = minf(x_max, x + d * 0.8)
	if not sis.is_empty() and int(sis["day"]) == day and phase == &"day":
		x = float(sis["x"]) + (x - float(sis["x"])) * 0.35
	ang = slope_at.call(x)
	sis = {"x": x, "y": w.y_at_x(x), "h": hm, "ang": ang, "day": day}


func _check_milestone(prev: float, now: float) -> void:
	for m: Array in [[10.0, Loc.t("sim_game.ten_meters", "十米 · ΔΕΚΑ")], [25.0, Loc.t("sim_game.twenty_five_meters", "二十五米")], [50.0, Loc.t("sim_game.fifty_meters", "五十米 · Ν")]]:
		if prev < float(m[0]) and now >= float(m[0]):
			fx.slowmo(0.3, 0.45, 0.4)
			fx.banner(m[1], Loc.t("sim_game.first_milestone", "这是你的第一块里程石") if float(m[0]) == 10.0 else "", 1.8, 0.3, 40.0)
			fx.sfx(&"sizeUp")
			if not sis.is_empty():
				fx.sparks(sis["x"], float(sis["y"]) + 2.0, 20, 8)


func _tier_up(ti: int) -> void:
	tier_flash = 1.0
	fx.sfx(&"sizeUp")
	fx.punch(0.06)
	fx.banner(Loc.t("sim_game.stone_has_reached_class", "石头长成了「%s级」") % String(content.size_tiers[ti]["name"]), "", 1.6, 0.22, 30.0)
	fx.event(&"tier_up", {"tier": ti})


# ———————————————— 黄昏 ————————————————
func start_dusk() -> void:
	if phase != &"day" and phase != &"victory_wait":
		return
	if exhausted > 0:
		faint_log.append(snappedf(slid_this_faint, 0.01))
	exhausted = 0
	if not demo:
		_settle_bet_day()
	seals_best0 = int(run_stats.get("max_seals", 0))
	jackpots0 = int(run_stats.get("jackpots", 0))
	phase = &"dusk"
	dusk_t = 0.0
	dusk_dur = 2.8
	ruins.clear()
	var runup: float = 10.0 + 2.5 * stone.r
	var bs: float = stone.s
	var kept: Array[CrushObj] = []
	runup_objs.clear()
	for o: CrushObj in objs:
		if o.city or not (o.s < bs and o.s > bs - runup):
			kept.append(o)
		else:
			runup_objs.append(o)
	objs = kept
	if sis.is_empty():
		place_sisyphus()
	# 白天就在的物件原样留着（rise_delay < 0 = 不重新长出）；只有赐福在黄昏新放的物件（圣牛、路障……）从地里长出来
	for o: CrushObj in objs:
		o.rise = 1.0
		o.rise_delay = -1.0
	if not demo:
		boons.dusk_start(objs)
	for o: CrushObj in objs:
		if o.rise_delay >= 0.0:
			o.rise = 0.0
			o.rise_delay = clampf((stone.s - o.s) / 260.0, 0.0, 1.4) + 0.5
	fx.sfx(&"duskGong")
	fx.sfx(&"ambience", 1.0)
	overtime_t = 0.0
	sit_pos = {"x": sis["x"], "y": sis["y"], "ang": world.ang_at(world.s_at_x(sis["x"])) * 0.6}
	fx.event(&"phase", {"phase": &"dusk"})
	fx.banner(Loc.t("sim_game.dusk_stone_breaks_free", "黄昏 · 石头挣脱了"), Loc.t("sim_game.space_skip", "空格跳过"), 2.2)


func _update_dusk(dt: float) -> void:
	dusk_t += dt
	for o: CrushObj in objs:
		if o.rise_delay < 0.0:
			continue
		var k: float = clampf((dusk_t - o.rise_delay) / 0.35, 0.0, 1.0)
		o.rise = 1.0 - pow(1.0 - k, 3.0)
	var b: Boulder = stone
	cam_tx = b.x - 8.0 - b.r * 1.5
	cam_ty = b.y + 1.0
	cam_view_h = maxf(24.0, b.r * 6.0)
	if dusk_t >= dusk_dur:
		for o: CrushObj in objs:
			o.rise = 1.0
		_start_night()


# ———————————————— 夜晚 ————————————————
func _start_night() -> void:
	var st: Stats = stats
	var b: Boulder = stone
	phase = &"night"
	var md: DayMods = mods
	b.r *= md.start_size_mult * st.start_size
	b.v = -(1.5 + st.start_speed) * md.night_speed_mult * st.night_speed
	b.air = false
	chests.clear()
	night_t = 0.0
	combo = 0
	combo_t = 0.0
	max_combo = 0
	night_total = 0.0
	night_total_valid = true
	night_moira = 0.0
	tally = {}
	crits = {"perfect": 0, "good": 0}
	slam_left = int(st.slam_charges)
	slam_n = 0
	slamming = false
	ring = {}
	rest_t = 0.0
	last_hit = 0.0
	crush_heat = 0.0
	crush_heat_t = 0.0
	_last_trail = PackedFloat64Array()
	zeus_t = st.zeus_dur if st.zeus else 0.0
	speed_stack_now = 0.0
	urn_n = 0
	urn_v = 0.0
	urn_burst_gate = 0
	urn_bursts = 0
	buff["stele_seal"] = 0
	start_r = b.r
	start_alt = world.alt_at(b.s)
	domino_q.clear()
	blocked_by = null
	trail.clear()
	last_tier = size_tier(b.r)
	gate_hit = false
	city_r = -1.0
	trip_t0 = 0.0
	gate_cool = 0.0
	night_seal_max = 0
	gate_end_t = 0.0
	gate_hit_night = false
	v_t_boost = 1.0
	beat_hold = false
	free_slam = false
	var cap: float = st.helper_value_cap if st.helper_value_cap > 0.0 else 0.6
	helper_value_now = minf(cap, st.helper_value * helper_count()) if st.helper_value > 0.0 else 0.0
	last_knee = -INF
	last_land = -9.0
	last_slow = -9.0
	chorus_lv = -1
	_set_chorus(0)
	fx.event(&"phase", {"phase": &"night"})
	if zeus_t > 0.0:
		fx.flash(0.4, Color("fff6d0"))
		fx.shake(0.5)
		fx.sfx(&"critPerfect")
		fx.banner(Loc.t("sim_game.zeus_wrath", "宙斯之怒！"), Loc.t("sim_game.crush_value_2_first", "前 %d 秒碾压价值 ×2") % roundi(zeus_t), 1.8)
	if st.start_speed > 0.0:
		fx.sfx(&"whoosh")
	if not demo:
		boons.night_start()


func _set_chorus(lv: int) -> void:
	if lv != chorus_lv:
		chorus_lv = lv
		fx.sfx(&"chorus", lv)


func night_action() -> void:
	var b: Boulder = stone
	var st: Stats = stats
	boons.on_space()
	if not ring.is_empty() and ring["result"] == &"":
		var rem: float = float(ring["dur"]) - float(ring["t"])
		var wk: float = st.crit_window * mods.crit_window_mult
		if absf(rem) <= 0.09 * wk:
			ring["result"] = &"perfect"
			fx.sfx(&"ringTick")
		elif absf(rem) <= 0.22 * wk:
			ring["result"] = &"good"
			fx.sfx(&"ringTick")
		else:
			ring["result"] = &"miss"
		return
	if b.air and slam_left > 0 and not slamming:
		slam_left -= 1
		slamming = true
		b.vy = minf(b.vy, -26.0 - b.r)
		fx.sfx(&"whoosh")
		fx.slowmo(0.5, 0.08, 0.2)
		fx.text(b.x, b.y + b.r + 1.0, Loc.t("sim_game.slam", "砸地！"), 26.0, SimFx.GOLD_HI, 0.8)


func _update_night(dt: float) -> void:
	var st: Stats = stats
	var b: Boulder = stone
	night_t += dt
	if zeus_t > 0.0:
		zeus_t -= dt
	if combo > 0 and not mods.combo_no_break and not beat_hold:
		combo_t -= dt
		if combo_t <= 0.0:
			combo = 0
			if not gate_hit:
				_set_chorus(0)
	for i: int in range(domino_q.size() - 1, -1, -1):
		var q: Dictionary = domino_q[i]
		q["t"] = float(q["t"]) - dt
		if float(q["t"]) <= 0.0:
			domino_q.remove_at(i)
			var qo: CrushObj = q["o"]
			if not qo.is_flat():
				crush(qo, {"domino": q["chain"]})
	var sub: int = 4
	var h: float = dt / sub
	for k: int in sub:
		if phase != &"night":
			break
		_step_physics(h)
	if phase != &"night":
		return
	_flatten_runup(dt)
	if not demo:
		boons.night_update(dt)
	if phase != &"night":
		return
	_update_ring(dt)
	# 停住判定
	if not gate_hit and not b.air and absf(b.v) < 0.35:
		rest_t += dt
		if rest_t > 1.1:
			var bb: CrushObj = blocked_by
			var blocked: bool = bb != null and not bb.is_flat() and b.x > bb.x - bb.w * 0.5
			try_end_night(&"blocked" if blocked else &"stopped")
			return
	else:
		rest_t = 0.0
	if not gate_hit and night_t - trip_t0 > 150.0:
		try_end_night(&"blocked" if blocked_by != null else &"stopped")
		return
	# 镜头：随体积拉远 + 速度前瞻
	var m: float = mass_norm(b.r)
	var vx: float = b.vx if b.air else b.v * cos(b.ang)
	var vy: float = b.vy if b.air else b.v * sin(b.ang)
	var sp: float = Js.hypot(vx, vy)
	cam_tx = b.x + vx * 0.42
	cam_ty = b.y + vy * 0.3 + b.r * 0.5
	cam_view_h = maxf(14.0, b.r * 4.6) * (1.0 + minf(0.3, sp / 90.0)) * (1.25 if st.devour else 1.0) * (1.0 + 0.45 * cam_pull)
	cam_pull = maxf(0.0, cam_pull - dt * 0.5)
	cam_k = 9.0
	cam_kz = 3.0
	rumble = 0.0 if b.air else (1.0 + 9.0 * m) * minf(1.0, sp / 25.0)
	shake_max_px = 12.0 + 34.0 * m
	shake_decay = 1.8 - 0.9 * m


## 助跑区的物件（runup_objs）：石头滚过时顺带压平——只有压扁动画、尘土和碎屑，不计钱、不计连碾、不减速、不长个
func _flatten_runup(dt: float) -> void:
	var b: Boulder = stone
	for o: CrushObj in runup_objs:
		if o.state == CrushObj.State.FLAT:
			o.t += dt
			continue
		if b.air or b.s - b.r * 0.4 > o.s + o.w * 0.5:
			continue
		var m: float = mass_norm(b.r)
		o.state = CrushObj.State.FLAT
		o.t = 0.0
		o.flat_dur = 0.085 - 0.05 * m
		o.flat_x = 1.3 + 0.9 * m
		fx.dust(o.x, o.y, 2 + o.tier, maxf(0.5, o.h * 0.45), 1.5 + o.tier)
		fx.shards(o.x, o.y + o.h * 0.35, 3.0 + o.tier * 2.0, 4.0 + o.tier, maxf(0.1, o.h * 0.1))
		fx.sfx(&"crunch", o.tier, m * 0.5)


func _step_physics(h: float) -> void:
	var st: Stats = stats
	var b: Boulder = stone
	var w: World = world
	if h <= 0.0:
		return
	prev_s = b.s
	if not b.air:
		var ang: float = w.ang_at(b.s)
		var v_t: float = (22.0 + 3.0 * b.r) * mods.night_speed_mult * st.night_speed * (1.0 + speed_stack_now) * v_t_boost
		var drag_k: float = clampf(absf(sin(ang)) / 0.5, 0.12, 1.4)
		var a: float = -tune.g_roll * sin(ang)
		var flat: bool = absf(sin(ang)) < 0.06
		var resist: float = 0.25 + (0.3 if flat else 0.0) + (1.2 if absf(b.v) < 2.5 else 0.0)
		a -= Js.sign(b.v) * (resist + tune.g_roll * 0.5 * (b.v / v_t) * (b.v / v_t) * drag_k)
		b.v += a * h
		if ang < -0.02 and b.v > -3.0 and b.v < 0.5:
			b.v = -3.0
		var dir: float = Js.sign(b.v)
		if dir == 0.0:
			dir = -1.0
		var ahead: float = w.ang_at(b.s + dir * maxf(0.6, b.r * 0.3))
		var drop: float = (ahead - ang) if dir < 0.0 else (ang - ahead)
		if dir < 0.0 and ang < -0.04 and absf(b.v) > 8.0 and drop > 0.25 and night_t - last_land > 0.3:
			var tang: float = ang + PI
			var spd: float = minf(absf(b.v), 20.0 + 1.2 * b.r)
			pre_air_speed = absf(b.v)
			b.air = true
			b.vx = cos(tang) * spd
			b.vy = sin(tang) * spd + 2.0
			b.y = maxf(b.y, w.y_at_x(b.x) + b.r + 0.05)
			air_t = 0.0
			fx.slowmo(0.4, 0.3, 0.5)
			fx.sfx(&"whoosh")
			fx.punch(-0.06)
			fx.event(&"jump", {}, b.x, b.y)
			if slam_left > 0:
				fx.text(b.x, b.y + b.r * 1.6, Loc.t("sim_game.airborne_space_slam", "腾空！空格砸地 +%s") % NumFmt.fmt(next_slam_pay()), 22.0, SimFx.GOLD_HI, 1.0)
		else:
			if drop > 0.3 and absf(b.v) > 10.0 and night_t - last_knee > 0.4:
				last_knee = night_t
				fx.shake(0.12 + 0.2 * mass_norm(b.r))
				fx.dust(b.x, b.y - b.r, 4, b.r * 0.4, 3.0)
				fx.sfx(&"land", mass_norm(b.r) * 0.5)
			b.s += b.v * h
			b.s = clampf(b.s, 0.0, w.s_summit)
			b.rot -= (b.v * h) / b.r
			place_boulder()
	if b.air:
		air_t += h
		b.vy -= 9.8 * (5.0 if air_t > 0.45 else 2.4) * h
		b.x += b.vx * h
		b.y += b.vy * h
		b.rot -= (b.vx * h) / b.r
		var a0: float = w.at(w.s_at_x(b.x))
		var dist: float = -(b.x - w.ax) * sin(a0) + (b.y - w.ay) * cos(a0)
		if (air_t > 0.05 and b.vy <= 0.0 and dist <= b.r) or dist < b.r * 0.2:
			_land()
	# 金色压痕（限宽 0.5m）
	if not b.air:
		var gx: float = b.x + sin(b.ang) * b.r
		var gy: float = b.y - cos(b.ang) * b.r
		if _last_trail.is_empty() or Js.hypot(gx - _last_trail[0], gy - _last_trail[1]) > 0.8:
			if not _last_trail.is_empty():
				trail.append(PackedFloat64Array([_last_trail[0], _last_trail[1], gx, gy, minf(b.r * 0.22, 0.5), 0.0]))
			if trail.size() > 900:
				trail.pop_front()
			_last_trail = PackedFloat64Array([gx, gy])
	else:
		_last_trail = PackedFloat64Array()
	_collide()
	if not gate_hit and night_t >= gate_cool and b.x - b.r <= float(gate["x"]) + float(gate["w"]) * 0.38:
		_hit_gate()


func _land() -> void:
	var b: Boulder = stone
	var w: World = world
	var s: float = w.s_at_x(b.x)
	for k: int in 2:
		var qa: float = w.at(s)
		s = clampf(s + (b.x - w.ax) * cos(qa) + (b.y - w.ay) * sin(qa), 0.0, w.s_summit)
	var ang: float = w.ang_at(s)
	var v_along: float = b.vx * cos(ang) + b.vy * sin(ang)
	var v_n: float = -b.vx * sin(ang) + b.vy * cos(ang)
	b.air = false
	b.s = s
	var brief: bool = air_t < 0.12 and not slamming
	b.v = Js.sign(v_along) * minf(absf(v_along) * (1.0 if brief else 0.9), pre_air_speed * 1.05)
	last_land = night_t
	place_boulder()
	if brief:
		return
	w.at(b.s)
	var px: float = w.ax
	var py: float = w.ay
	var m: float = mass_norm(b.r)
	var impact: float = absf(v_n)
	var free: bool = not slamming and (free_slam or stats.auto_slam_on_land)
	var slam: bool = slamming or free
	fx.shake(clampf(impact * 0.025 * (0.6 + m) * (2.0 if slam else 1.0), 0.1, 1.0))
	fx.hit((25.0 + 70.0 * m) * (1.8 if slam else 1.0))
	fx.punch(0.12 if slam else 0.05)
	fx.sfx(&"land", clampf(m + (0.3 if slam else 0.0), 0.0, 1.0))
	fx.dust(px, py, 10 + int(20.0 * m), b.r * 0.8, 5.0 + impact * 0.3)
	fx.shards(px, py, 8 + floorf(20.0 * m), 6.0 + impact * 0.4, maxf(0.2, b.r * 0.12))
	fx.ring(px, py + 0.2, b.r * 0.6, b.r * (stats.slam_radius if slam else 1.8), 0.6, SimFx.GOLD_HI, 6.0 if slam else 3.0, 0.3)
	fx.event(&"land", {"slam": slam, "impact": impact}, px, py)
	if urn_full():
		urn_burst(px, py)
	var radius: float = b.r * (stats.slam_radius if slam else 1.3)
	for o: CrushObj in _objs_near(b.x, radius + 30.0):
		if o.is_flat() or absf(o.x - b.x) > radius + o.w / 2.0:
			continue
		if b.r >= eff_req(o):
			crush(o, {"slam": slam})
	boons.on_land({"slam": slam, "impact": impact, "free": free})
	if slamming:
		# 砸地本身就有收益（跳台位置固定，常常砸在空地上）：每夜第 n 次 +slam_pay × 2^(n−1)，单次封顶 slam_pay_cap；
		# 走 add_night_bonus，和碾压一样吃冥府之门倍率
		var pay: float = next_slam_pay()
		slam_n += 1
		if pay > 0.0:
			add_night_bonus(pay, Loc.t("sim_game.slam_2", "砸地"), px, py + b.r)
		fx.banner(Loc.t("sim_game.slam", "砸地！"), "+%s" % NumFmt.fmt(pay) if pay > 0.0 else "", 1.0, 0.3, 44.0)
		fx.flash(0.35, Color("fff1c0"))
	elif free:
		fx.text(px, py + b.r * 1.4 + 1.0, Loc.t("sim_game.slam_2", "砸地"), 22.0, SimFx.GOLD_HI, 0.7)
	slamming = false


## 物件按 s 排序、x 随 s 单调：二分出 x 在 [x0 - span, x0 + span] 内的物件（与网页全表扫描结果相同）
func _objs_near(x0: float, span: float) -> Array[CrushObj]:
	var lo: int = 0
	var hi: int = objs.size()
	var xl: float = x0 - span
	while lo < hi:
		var mid: int = (lo + hi) >> 1
		if objs[mid].x < xl:
			lo = mid + 1
		else:
			hi = mid
	var out: Array[CrushObj] = []
	var xr: float = x0 + span
	var i: int = lo
	while i < objs.size() and objs[i].x <= xr:
		out.append(objs[i])
		i += 1
	return out


func _collide() -> void:
	var b: Boulder = stone
	var st: Stats = stats
	for o: CrushObj in _objs_near(b.x, b.r + 40.0):
		if o.is_flat():
			continue
		if absf(o.x - b.x) > b.r + o.w:
			continue
		var qx: float = clampf(b.x, o.x - o.w * 0.4, o.x + o.w * 0.4)
		var qy: float = clampf(b.y, o.y, o.y + o.h * 0.9)
		if (qx - b.x) * (qx - b.x) + (qy - b.y) * (qy - b.y) > b.r * b.r:
			continue
		var er: float = eff_req(o)
		if o.city and city_r < 0.0:
			city_r = b.r
		if o.tier >= 3 and urn_full():
			urn_burst(o.x, o.y + o.h * 0.4)
		var crit: StringName = (ring["result"] as StringName) if not ring.is_empty() and ring["o"] == o else &""
		if b.r >= er:
			crush(o, {"crit": crit})
			continue
		if town_roadside(o):
			_town_graze(o, er, qx, qy)
			continue
		var vel: float = b.speed()
		var toward: float = Js.sign(o.x - b.x)
		if toward == 0.0:
			toward = -1.0
		if not b.air:
			b.s = prev_s
			place_boulder()
			if Js.sign(b.v) == toward:
				b.v = 0.0
		elif Js.sign(b.vx) == toward:
			b.vx = 0.0
		blocked_by = o
		if o.hit_cool > night_t:
			continue
		var e: float = 0.5 * pow(b.r, 3.0) * st.mass_mult * vel * vel
		var hp: float = pow(er, 3.0) * 90.0
		var add: float = (e / hp) * (3.0 if crit == &"perfect" else (1.6 if crit == &"good" else 1.0))
		# 裂痕保底：城里挡路的东西每晚第一次被撞至少裂 crack_pity（跨夜保留，几晚之内一定撞开）
		if o.city and int(o.ext.get("pity_day", -1)) != day:
			o.ext["pity_day"] = day
			add = maxf(add, tune.crack_pity)
		o.dmg += add
		if not ring.is_empty() and ring["o"] == o:
			ring = {}
		if o.dmg >= 1.0:
			crush(o, {"crit": crit, "breakthrough": true})
			continue
		o.state = CrushObj.State.CRACKED
		o.shake = 1.0
		o.hit_cool = night_t + 0.25
		if vel < 1.5:
			continue
		var back: float = -toward
		if b.air:
			b.vx = back * maxf(absf(b.vx), vel * 0.5) * 0.3
			b.vy = maxf(2.0, b.vy * 0.2)
		else:
			b.v = back * vel * 0.32
		var m: float = mass_norm(b.r)
		# 不飘数字（2026-10-16 用户定）：裂得越深，撞击声越重、碎屑越多、东西晃得越厉害（裂纹本身也越画越长）
		var dk: float = clampf(o.dmg, 0.0, 1.0)
		o.shake = 1.0 + dk
		fx.shake(0.25 + 0.3 * m + 0.25 * dk)
		fx.hit(45.0 + 30.0 * dk)
		fx.sfx(&"bounce", m)
		fx.sfx(&"wood" if d_mat(o) == &"wood" else &"stone", clampf(0.25 + 0.75 * dk, 0.0, 1.0))
		fx.shards(qx, qy, 6 + floorf(14.0 * dk), 4.0 + 4.0 * dk, 0.15 + 0.12 * dk)


static func d_mat(o: CrushObj) -> StringName:
	return o.def.mat if o.def != null else &"stone"


## 本局第一次碾动城里路面上的东西（石头够大或者撞塌了挡路的）：进城的那一刻要够爽，让人记住「石头大 = 爽」
func _town_in_moment() -> void:
	run_stats["town_in"] = true
	fx.slowmo(0.2, 0.7, 0.6)
	fx.shake(1.0)
	fx.flash(0.35, Color("fff1c0"))
	fx.sfx(&"coinsCascade", 30.0, 0.9)
	cam_pull = 1.0


## 碾压（game.js:793）。opt：crit domino slam remote k grow breakthrough by
func crush(o: CrushObj, opt: Dictionary = {}) -> void:
	if o.is_flat():
		return
	if blocked_by == o:
		blocked_by = null
	var st: Stats = stats
	var b: Boulder = stone
	var d: ObjDef = o.def
	var m: float = mass_norm(b.r)
	o.state = CrushObj.State.FLAT
	o.t = 0.0
	o.flat_dur = 0.085 - 0.05 * m
	o.flat_x = 1.3 + 0.9 * m
	o.ang = world.ang_at(o.s)
	if not ring.is_empty() and ring["o"] == o:
		ring = {}
	combo += 1
	max_combo = maxi(max_combo, combo)
	combo_t = st.combo_window + mods.combo_window_add
	combo_pulse = 1.0
	var remote: bool = bool(opt.get("remote", false))
	var crit: StringName = opt.get("crit", &"")
	var ace: int = int(mods.auto_crit_every)
	if ace > 0 and combo % ace == 0 and crit == &"" and not remote:
		crit = &"perfect"
		opt = opt.duplicate()
		opt["crit"] = crit
	var mult: float = main_mult(o, opt)
	if bool(opt.get("slam", false)):
		mult *= st.slam_value
	if opt.has("k"):
		mult *= float(opt["k"])
	var crit_txt: String = ""
	if crit == &"perfect":
		mult *= st.crit_perfect
		crits["perfect"] = int(crits["perfect"]) + 1
		crit_txt = Loc.t("sim_game.perfect_heavy_crush", "完美重压 ×%s") % Js.num_str(st.crit_perfect)
	elif crit == &"good":
		mult *= st.crit_good
		crits["good"] = int(crits["good"]) + 1
		crit_txt = Loc.t("sim_game.heavy_crush", "重压 ×%s") % Js.num_str(st.crit_good)
	var value: float = o.value * mult
	night_total += value
	var key: String = String(o.type)
	var tl: Dictionary = tally.get(key, {})
	if tl.is_empty():
		tl = {"n": 0, "v": 0.0}
		tally[key] = tl
	tl["n"] = int(tl["n"]) + 1
	tl["v"] = float(tl["v"]) + value
	run_stats["crush_total"] = float(run_stats.get("crush_total", 0.0)) + value
	if d.mat == &"ceramic":
		run_stats["ceramics"] = int(run_stats.get("ceramics", 0)) + 1
	if d.living:
		run_stats["living"] = int(run_stats.get("living", 0)) + 1
	run_stats["crushed"] = int(run_stats.get("crushed", 0)) + 1
	if d.tier >= 3 and not d.living:
		run_stats["buildings"] = int(run_stats.get("buildings", 0)) + 1
	if o.type == &"chicken":
		run_stats["chickens"] = int(run_stats.get("chickens", 0)) + 1
	story.on_crush(o)
	if st.urn_cap > 0.0:
		urn_n += 1
		urn_v += value
	if st.speed_stack > 0.0:
		speed_stack_now = minf(st.speed_stack_cap, speed_stack_now + st.speed_stack)
	# 雪球长大（月石 no_stick：不长也不粘）
	var gain: float = 0.0
	if not st.no_stick:
		gain = content.absorb_gain[o.tier] * st.absorb / (1.0 + b.r / st.absorb_falloff) * mods.growth_mult * float(opt.get("grow", 1.0)) * boons.grow_mul(o) * (TOWN_GROW if o.city else 1.0)
	var old_r: float = b.r
	b.r += gain
	if not b.air:
		place_boulder()
	if not st.no_stick and not remote and o.h < b.r * 1.5:
		b.stuck.append({"type": o.type, "a": rand.next(SimRandom.Use.COSMETIC) * TAU,
			"h": minf(o.h, b.r * 0.55) * (0.9 if d.living and st.living_mult > 1.0 else 0.75), "out": rand.next(SimRandom.Use.COSMETIC) * 0.08})
		if b.stuck.size() > int(st.max_stuck):
			b.stuck.remove_at(0)
	var ti: int = size_tier(b.r)
	if ti > last_tier:
		last_tier = ti
		_tier_up(ti)
	# 速度
	var er: float = o.req * st.req_mult
	if remote:
		pass
	elif st.unstoppable:
		b.v *= 1.03
	else:
		var loss: float = clampf(0.12 * pow(er / old_r, 1.5), 0.004, 0.35) * boons.drag_mul(o) * ((TOWN_SIDE_DRAG if town_roadside(o) else TOWN_DRAG) if o.city else 1.0)
		if b.air:
			b.vx *= 1.0 - loss * 0.5
		else:
			b.v *= 1.0 - loss
	# 手感：全按质量缩放，再按碾压密度压低（2026-10-15：碾进城一件接一件时顿帧、慢放、震屏叠在一起，抽、晕）
	var rel: float = er / old_r
	var big: bool = o.tier >= 3 and rel > 0.5
	crush_heat = crush_heat * exp(-2.0 * maxf(0.0, night_t - crush_heat_t)) + 1.0
	crush_heat_t = night_t
	var dense: float = 1.0 / (1.0 + 0.22 * maxf(0.0, crush_heat - 1.0))
	var huge: bool = o.tier >= 5 or crit_txt != "" or bool(opt.get("breakthrough", false))
	fx.shake(clampf(0.06 + 0.07 * o.tier * (0.4 + m), 0.0, 0.85) * (1.6 if crit_txt != "" else 1.0) * clampf(rel * 1.6, 0.35, 1.0) * (0.4 if remote else 1.0) * (1.0 if huge else dense))
	if night_t - last_hit > (0.35 if big else 0.18) and (crush_heat < 5.0 or huge):
		fx.hit(minf(70.0, (14.0 + 12.0 * o.tier * (0.5 + m)) * clampf(rel * 1.5, 0.3, 1.0) * (1.7 if crit_txt != "" else 1.0) * (1.0 if huge else dense)))
		last_hit = night_t
	if not opt.has("domino") and not remote and (big or crit == &"perfect" or bool(opt.get("breakthrough", false))) and night_t - last_slow > 1.2 			and (crush_heat < 4.0 or huge):
		last_slow = night_t
		fx.slowmo(0.35 if rel > 0.75 or crit_txt != "" else 0.55, 0.2, 0.4)
		fx.punch(0.08 + 0.04 * m)
	var cx: float = o.x
	var cy: float = o.y + o.h * 0.4
	# 碾得密时碎屑、灰尘按密度减量（最少留 35%），大件 / 暴击照旧
	var bits: float = 1.0 if huge else maxf(0.35, dense)
	fx.shards(cx, cy, minf(70.0, 4.0 + o.tier * 5.0 * (1.0 + m * 2.0)) * bits, 5.0 + o.tier * 1.6 + m * 6.0, maxf(0.12, o.h * 0.12))
	fx.dust(cx, o.y, maxi(1, roundi((3 + o.tier * 2) * bits)), maxf(0.6, o.h * 0.5), 2.0 + o.tier)
	chests.on_burst(cx, cy, value, o.tier, big, o.type, o.def.jar + int(o.ext.get("jar_add", 0)) if o.def.jar > 0 else 0)
	if o.tier >= 3:
		fx.sparks(cx, cy, 8 + o.tier * 3, 10 + o.tier * 2)
	fx.text(cx, o.y + o.h + 0.5 + b.r * 0.2, "+" + NumFmt.fmt(value), 15.0 + o.tier * 4.0 + m * 10.0)
	if crit_txt != "":
		fx.text(cx, o.y + o.h + 2.0 + b.r * 0.4, crit_txt, 30.0, SimFx.GOLD_HI, 1.2)
		fx.flash(0.25, Color("fff1c0"))
		fx.sfx(&"critPerfect" if crit == &"perfect" else &"critGood")
	if bool(opt.get("breakthrough", false)):
		fx.text(cx, o.y + o.h + 3.0, Loc.t("sim_game.smashed_through", "撞穿！"), 34.0, SimFx.GOLD_HI, 1.2)
	if o.city and not town_roadside(o) and not bool(run_stats.get("town_in", false)) and not demo:
		_town_in_moment()
	var vx: float = b.vx if b.air else b.v * cos(b.ang)
	fx.event(&"crush", {"id": o.id, "type": o.type, "tier": o.tier, "mat": d.mat, "voice": d.voice, "voice_txt": VOICE_TXT.get(d.voice, Loc.t("sim_game.hey", "哎！")),
		"w": o.w, "h": o.h, "fly": o.h < b.r * 2.0, "vx": vx, "m": m, "value": value}, cx, cy)
	match d.mat:
		&"ceramic": fx.sfx(&"shatter", m)
		&"wood": fx.sfx(&"wood", m)
		&"stone": fx.sfx(&"stone", m)
	fx.sfx(&"crunch", o.tier, m)
	if not gate_hit:
		_set_chorus(5 if combo >= 100 else (4 if combo >= 50 else (3 if combo >= 25 else (2 if combo >= 12 else (1 if combo >= 5 else 0)))))
	# 多米诺：同一排柱子向两边依次倒下
	if o.domino > 0:
		for k: int in [o.domino - 1, o.domino + 1]:
			for nx: CrushObj in objs:
				if nx.dgroup == o.dgroup and nx.domino == k and not nx.is_flat():
					var queued: bool = false
					for q: Dictionary in domino_q:
						if q["o"] == nx:
							queued = true
							break
					if not queued:
						domino_q.append({"o": nx, "t": 0.12, "chain": int(opt.get("domino", 0)) + 1})
					break
	if not trail.is_empty() and not remote:
		var last: PackedFloat64Array = trail[trail.size() - 1]
		last[5] = minf(1.0, last[5] + 0.3 * o.tier)
		trail[trail.size() - 1] = last
	boons.on_crush(o, value, opt)


## 碾压门槛：天赋 req_mult × 神龛 mods.req_mult × 赐福 req_mul（酒神节）
func eff_req(o: CrushObj) -> float:
	return o.req * stats.req_mult * mods.req_mult * boons.req_mul(o)


## 碾压价值的主倍率（不含重压、砸地、远程系数）
func main_mult(o: CrushObj, opt: Dictionary = {}) -> float:
	var st: Stats = stats
	var b: Boulder = stone
	var md: DayMods = mods
	var combo_mult: float = minf(st.combo_cap, 1.0 + st.combo_step * maxf(0.0, combo - 1))
	var mult: float = pow(b.r / st.r0, st.size_exp) * combo_mult * st.value_mult
	if st.speed_stack > 0.0:
		mult *= 1.0 + speed_stack_now
	if o.def.living:
		mult *= st.living_mult * md.living_mult
	if zeus_t > 0.0:
		mult *= 2.0
	mult *= md.night_value_mult
	mult *= boons.value_mul(o, opt)
	if helper_value_now != 0.0:
		mult *= 1.0 + helper_value_now
	if b.air and not bool(opt.get("remote", false)):
		mult *= st.air_value
	if opt.has("domino"):
		mult *= 1.0 + 0.1 * float(opt["domino"])
	return mult


## 远程碾压：价值 ×k、长大 ×grow，不减速、不粘附
func crush_remote(o: CrushObj, k: float = 1.0, grow: float = 1.0, by: StringName = &"remote") -> bool:
	if o == null or o.is_flat() or phase != &"night":
		return false
	crush(o, {"remote": true, "k": k, "grow": grow, "by": by})
	return true


## 石头下坡方向 dist 米以内、门槛够、tier ≤ max_tier 的物件（最近的在前）
func objs_ahead(dist: float, max_tier: int = 9, from: float = NAN) -> Array[CrushObj]:
	var f: float = stone.s if is_nan(from) else from
	var out: Array[CrushObj] = []
	for o: CrushObj in objs:
		if o.is_flat() or o.tier > max_tier or o.s > f or o.s < f - dist:
			continue
		if eff_req(o) > stone.r:
			continue
		out.append(o)
	out.sort_custom(func(a: CrushObj, c: CrushObj) -> bool: return a.s > c.s)
	return out


## 赫尔墨斯补货：被碾平的非城市物件恢复完好，价值 ×k；返回件数
func restock_flat(k: float = 0.5) -> int:
	var n: int = 0
	for o: CrushObj in objs:
		if not o.is_flat() or o.city or o.roadblock != &"":
			continue
		o.state = CrushObj.State.STAND
		o.dmg = 0.0
		o.t = 0.0
		o.rise = 1.0
		o.shake = 0.0
		o.hit_cool = 0.0
		o.ang = world.ang_at(o.s)
		o.value *= k
		o.resold += 1
		n += 1
	return n


## 把石头放到 s 处、速度 v（沿坡，负 = 下坡）
func place_stone_at(s: float, v: float) -> void:
	var b: Boulder = stone
	b.s = s
	b.ts = s
	b.v = v
	b.air = false
	b.vx = 0.0
	b.vy = 0.0
	place_boulder()
	rest_t = 0.0
	trip_t0 = night_t
	blocked_by = null
	ring = {}
	_last_trail = PackedFloat64Array()
	gate_hit = false
	gate_end_t = 0.0
	gate_cool = 0.0
	slamming = false
	gate["hit_t"] = -1.0
	gate["open"] = 0.0
	gate["seal_q"] = gate["seals"]
	cam_tx = b.x
	cam_ty = b.y
	cam_snap += 1


func try_end_night(reason: StringName) -> bool:
	if not demo and boons.before_night_end(reason):
		return false
	_end_night(reason)
	return true


func _update_ring(dt: float) -> void:
	var b: Boulder = stone
	var st: Stats = stats
	if not ring.is_empty():
		ring["t"] = float(ring["t"]) + dt
		var ac: int = 2 if mods.auto_crit_all else int(st.auto_crit)
		if ac > 0 and ring["result"] == &"" and float(ring["dur"]) - float(ring["t"]) < 0.05:
			ring["result"] = &"perfect" if ac == 2 else &"good"
		var ro: CrushObj = ring["o"]
		if float(ring["t"]) > float(ring["dur"]) + 0.3 or ro.is_flat():
			ring = {}
		return
	var vx: float = b.vx if b.air else b.v * cos(b.ang)
	if vx > -2.0:
		return
	var near: Array[CrushObj] = _objs_near(b.x - absf(vx) * 0.8 - b.r - 20.0, absf(vx) * 0.8 + b.r + 20.0)
	for i: int in range(near.size() - 1, -1, -1):
		var o: CrushObj = near[i]
		if o.is_flat() or o.x > b.x:
			continue
		var gap: float = (b.x - o.x) - (b.r + o.w * 0.4)
		if gap > absf(vx) * 0.8:
			break
		var er: float = eff_req(o)
		if er < b.r * 0.45 or er > b.r * 2.0 or (er > b.r and town_roadside(o)):
			continue
		var ttc: float = gap / absf(vx)
		if ttc <= 0.12:
			continue
		if ttc < 0.75:
			ring = {"o": o, "t": 0.0, "dur": ttc, "result": &""}
			fx.sfx(&"ringTick")
		break


## 撞门能量 → 破封重数（hitGate 与门上"预估重数"共用）。urn：门前陶瓮迸裂 +1
func seals_for(e: float, urn: int = 0) -> int:
	var st: Stats = stats
	var b: Boulder = stone
	var base: float = floorf((Js.log10(maxf(1.0, e)) - 1.0) * 1.5)
	var size: float = minf(3.0, floorf(b.r / st.size_seals)) if st.size_seals > 0.0 else 0.0
	var cmb: float = minf(3.0, floorf(max_combo / st.combo_seals)) if st.combo_seals > 0.0 else 0.0
	return int(clampf(base + mods.gate_seal_bonus + st.gate_seal_add + float(buff["stele_seal"]) + size + cmb + urn, 0.0, st.max_seals))


func _hit_gate() -> void:
	var b: Boulder = stone
	var st: Stats = stats
	gate_hit = true
	gate_hit_night = true
	if urn_full():
		urn_burst(float(gate["x"]) + float(gate["w"]) * 0.3, float(gate["h"]) * 0.3)
		urn_burst_gate = 1
	var vel: float = b.speed()
	var e: float = 0.5 * pow(b.r, 3.0) * st.mass_mult * vel * vel
	var seals0: int = seals_for(e, urn_burst_gate)
	var r: Dictionary = {"seals": seals0, "stay": false}
	if not demo:
		r = boons.on_gate({"E": e, "vel": vel, "seals": seals0})
	var seals: int = maxi(int(clampf(float(r["seals"]), 0.0, st.max_seals)), night_seal_max)
	night_seal_max = seals
	gate["seals"] = seals
	gate["shake"] = 1.2
	gate_e = e
	var per: float = st.seal_mult_per * mods.seal_mult_per_mult
	gate_mult = (minf(st.seal_exp_cap, pow(1.0 + per, seals)) * st.gate_mult) if st.seal_exp else (1.0 + per * seals * st.gate_mult)
	run_stats["max_seals"] = maxi(int(run_stats.get("max_seals", 0)), seals)
	var by_day: Dictionary = run_stats.get("seals_by_day", {})
	by_day[str(day)] = maxi(int(by_day.get(str(day), 0)), seals)
	run_stats["seals_by_day"] = by_day
	best_seals = maxi(best_seals, seals)
	var gx: float = float(gate["x"]) + float(gate["w"]) * 0.3
	var gy: float = float(gate["h"]) * 0.4
	if bool(r.get("stay", false)):
		fx.hit(120.0)
		fx.shake(0.5)
		fx.punch(0.08)
		fx.ring(gx, gy, 1.0, b.r * 3.0 + 6.0, 0.7, SimFx.GOLD_HI, 5.0, 0.35)
		fx.sparks(gx, gy, 30, 18)
		fx.text(gx + 4.0, gy + 4.0, Loc.t("sim_game.hit_seals_total", "第 %d 撞 · 累计 %d 重") % [int(r.get("knocks", 1)), seals], 22.0, SimFx.CREAM, 1.0)
		fx.sfx(&"gateKnock", clampf(seals / 12.0, 0.0, 1.0))
		fx.sfx(&"gateImpact", clampf(seals / 12.0, 0.0, 1.0) * 0.6)
		if b.air:
			b.air = false
			b.s = world.s_at_x(b.x)
			place_boulder()
		b.v = absf(vel) * st.knock_bounce
		gate_hit = false
		gate_cool = night_t + 0.4
		return
	story.on_gate(seals)
	gate["hit_t"] = 0.0
	gate["seal_q"] = 0
	gate["open"] = 0.0
	var m: float = mass_norm(b.r)
	fx.hit(260.0 + 120.0 * m)
	fx.slowmo(0.2, 0.7, 1.1)
	fx.shake(1.0)
	shake_max_px = 40.0
	fx.punch(0.15)
	fx.flash(0.4, Color("ffe08a"), float(gate["x"]), float(gate["h"]) * 0.45)
	for i: int in 2:
		fx.ring(gx, gy, 1.0, b.r * (3.0 + i * 2.5) + 10.0, 0.8, SimFx.GOLD if i % 2 == 1 else SimFx.GOLD_HI, 7.0 - 2.0 * i, 0.45)
	fx.sparks(gx, gy, 80, 30)
	fx.shards(gx, gy, 60, 18.0, 0.6)
	fx.coins(gx, gy + 4.0, 14, 0.0)
	fx.sfx(&"gateImpact", clampf(seals / 9.0, 0.0, 1.0))
	fx.event(&"gate_hit", {"seals": seals, "E": e, "mult": gate_mult})
	_set_chorus(5)
	var label: String = String(r.get("label", ""))
	if label == "":
		label = (Loc.t("sim_game.underworld_gate_seal_echoes", "冥府之门 · 第 %d 重回响") % seals) if seals > 0 else Loc.t("sim_game.underworld_gate_unmoved", "冥府之门 · 纹丝不动")
	fx.banner(label, Loc.t("sim_game.impact_energy_tonight_s", "撞击能量 %s · 全夜收益 ×%s") % [NumFmt.fmt(e), Js.to_fixed(gate_mult, 2)], 3.0, 0.18, 46.0)
	if b.air:
		b.air = false
		b.s = world.s_at_x(b.x)
	b.v = absf(vel) * 0.06
	gate_end_t = 2.6


func _end_night(reason: StringName) -> void:
	if phase != &"night":
		return
	var st: Stats = stats
	phase = &"night_end"
	rumble = 0.0
	_set_chorus(0)
	fx.sfx(&"rumble", 0.0, 0.0)
	chests.collect_all()
	var bd: Dictionary = {"extra": [], "crush_sum": night_total, "start_r": start_r, "end_r": stone.r, "reason": reason}
	if not demo:
		boons.on_night_end(bd)
	var extra_sum: float = 0.0
	for x: Dictionary in bd["extra"]:
		extra_sum += float(x.get("v", 0.0))
	var crush_sum: float = night_total + extra_sum
	var hit_any: bool = gate_hit or gate_hit_night
	var gm: float = gate_mult if hit_any else 1.0
	var gated: float = clampf(boons.gated_part(crush_sum), 0.0, crush_sum) if hit_any else 0.0
	var gross: float = (crush_sum - gated) + gated * gm
	if not hit_any and st.no_gate_penalty > 0.0:
		gross *= 1.0 - st.no_gate_penalty
	var after: float = gross * st.aftershock
	var fire: float = gross * st.fire
	var cut: float = gross * st.last_cut
	gross += after + fire + cut
	var tax: float = gross * st.tax
	var net: float = floorf(gross - tax)
	# 山脚城镇：碾平得够多，连夜重建得更繁华；没倒的留着裂痕
	var prev_city: int = city_level
	_town_after_night()
	ruins.clear()
	for o: CrushObj in objs:
		if o.is_flat():
			ruins.append(o.copy())
	var tl: Array = []
	for k: String in tally:
		var v: Dictionary = tally[k]
		var nm: String = k
		if not bool(v.get("label", false)) and content.object_by_id.has(StringName(k)):
			nm = (content.object_by_id[StringName(k)] as ObjDef).name
		tl.append({"type": k, "name": nm, "n": v["n"], "v": v["v"], "label": bool(v.get("label", false))})
	tl.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return float(a["v"]) > float(c["v"]))
	var data: Dictionary = {
		"day": day, "reason": reason, "blocked_by": blocked_by.def.name if blocked_by != null else "",
		"tally": tl,
		"crush_sum": crush_sum, "start_r": start_r, "end_r": stone.r, "start_alt": start_alt, "max_combo": max_combo, "crits": crits.duplicate(),
		"gate": {"seals": gate["seals"], "mult": gm, "E": gate_e} if hit_any else {},
		"after": after, "fire": fire, "cut": cut, "tax_rate": st.tax, "tax": tax, "net": net, "moira": night_moira,
		"city_up": String(content.city_levels[city_level]["name"]) if city_level > prev_city else "",
		"demo": demo, "boons": boons.summary(), "story": [], "debt": 0.0,
		"extra": bd["extra"], "school": bd.get("school", []), "boon_log": bd.get("log", {}),
	}
	if not demo:
		story.on_night_end(data)
	var debt: float = clampf(floorf(float(data.get("debt", 0.0))), 0.0, net)
	data["debt"] = debt
	net -= debt
	data["net"] = net
	money += net
	if not demo:
		run_stats["best_night"] = maxf(float(run_stats.get("best_night", 0.0)), net)
		run_stats["max_r"] = maxf(float(run_stats.get("max_r", 0.0)), stone.r)
		# 夜宴里神的反应要用的（FeastReact.context）
		data["ach_new"] = Achievements.check(self)
		data["record0"] = record0
		data["record"] = record
		data["seals_best0"] = seals_best0
		data["max_seals"] = int(st.max_seals)
		data["jackpots"] = int(run_stats.get("jackpots", 0)) - jackpots0
		data["bet"] = bet_today.duplicate()
	last_night = data
	fx.event(&"night_settled", {"net": net})
	_wait(0.7, &"on_night_end", data)


# —— 山脚城镇（docs/v05/town.md）——
# 整座城第一天就在（World._layout_town）。路边的近排 / 远排建筑不挡路：石头够大就碾平，不够大只蹭裂；
# 裂痕按 slot 跨夜保留（city_cracks），攒满就倒——早期被挡也在给后面铺路。city_level = 繁荣度。

## 城里碾碎东西的减速系数：路面的人和货（城里一百多件，按山上的算法石头走不到冥府之门）；路边建筑（石头是擦着它过去的，不是正面撞穿）
const TOWN_DRAG: float = 0.25
const TOWN_SIDE_DRAG: float = 0.16
## 城里的东西碾碎了只粘上一点（整座城一百多件，按山上的长法石头会在城里暴涨）
const TOWN_GROW: float = 0.2
## 蹭一下的伤害系数（正面撞是 1）与同一栋的冷却（秒）
const TOWN_GRAZE_K: float = 0.5
const TOWN_GRAZE_COOL: float = 1.5


## 城里路边（近排 / 远排）的建筑
static func town_roadside(o: CrushObj) -> bool:
	return o.city and int(o.ext.get("row", 0)) > 0


## 石头不够大，擦着路边建筑过去：不挡、不减速，只留裂痕（攒满 = 撞穿）
func _town_graze(o: CrushObj, er: float, qx: float, qy: float) -> void:
	if o.hit_cool > night_t:
		return
	o.hit_cool = night_t + TOWN_GRAZE_COOL
	var b: Boulder = stone
	var vel: float = b.speed()
	if vel < 2.0:
		return
	var e: float = 0.5 * pow(b.r, 3.0) * stats.mass_mult * vel * vel
	o.dmg += TOWN_GRAZE_K * e / (pow(er, 3.0) * 90.0)
	if o.dmg >= 1.0:
		crush(o, {"breakthrough": true})
		return
	o.state = CrushObj.State.CRACKED
	var dk: float = clampf(o.dmg, 0.0, 1.0)
	o.shake = 0.6 + 0.6 * dk
	fx.shards(qx, qy, 4 + floorf(8.0 * dk), 3.0 + 2.0 * dk, 0.12 + 0.08 * dk)
	fx.sfx(&"wood" if d_mat(o) == &"wood" else &"stone", clampf(0.15 + 0.6 * dk, 0.0, 1.0))


## 夜里收尾：记下没倒的城中物件的裂痕；碾平的价值占全城（按基础价值）够高就升一档繁荣度（重建契约有概率再升一档）
func _town_after_night() -> void:
	var all_v: float = 0.0
	var flat_v: float = 0.0
	var keep: Dictionary = {}
	for o: CrushObj in objs:
		if not o.city:
			continue
		all_v += o.def.value
		if o.is_flat():
			flat_v += o.def.value
		elif o.dmg > 0.0 and o.ext.has("slot"):
			keep[String(o.ext["slot"])] = snappedf(minf(o.dmg, 0.95), 0.001)
	city_cracks = keep
	var top: int = content.city_levels.size() - 1
	if all_v <= 0.0 or city_level >= top:
		return
	var frac: float = flat_v / all_v
	if _town_can_grow(city_level + 1, frac):
		city_level += 1
		if city_level < top and rand.next(SimRandom.Use.CITY) < stats.rebuild * 0.25 and _town_can_grow(city_level + 1, 1.0):
			city_level += 1


## 升到 lvl 档：碾平的价值占比够（need），并且今夜出发时的石头够大（min_r × 门槛倍率；用出发半径，免得赫尔墨斯多程把收尾半径滚得太大、城一夜之间富起来）
func _town_can_grow(lvl: int, frac: float) -> bool:
	if lvl >= content.city_levels.size():
		return false
	var c: Dictionary = content.city_levels[lvl]
	return frac >= float(c.get("need", 1.0)) and start_r >= float(c.get("min_r", 0.0)) * stats.req_mult


## 白天布局之后：把昨夜留下的裂痕放回去
func _town_apply_cracks() -> void:
	if city_cracks.is_empty():
		return
	for o: CrushObj in objs:
		if o.city and o.ext.has("slot"):
			var d: float = float(city_cracks.get(String(o.ext["slot"]), 0.0))
			if d > 0.0:
				o.dmg = d
				o.state = CrushObj.State.CRACKED


func _victory() -> void:
	phase = &"victory_wait"
	record = World.SUMMIT
	if int(run_stats.get("summit_day", 0)) == 0:
		run_stats["summit_day"] = day
	fx.sfx(&"critPerfect")
	fx.sfx(&"chorus", 5.0)
	fx.flash(0.4, Color("fff3cf"))
	fx.shake(0.6)
	fx.banner(Loc.t("sim_game.summit_reached", "登顶！"), Loc.t("sim_game.stone_has_stopped_summit", "石头第一次停在了山顶"), 3.0)
	Achievements.check(self)
	fx.event(&"phase", {"phase": &"victory_wait"})
	_wait(2.6, &"on_victory", {"day": day, "r": stone.r, "choices": story.summit_choices()})


# —— 陶瓮石：满了就迸裂（瓮中物价值再结算 urn_mult 倍，走 add_night_bonus = 碾压派生；半径 ×0.75）——
func urn_full() -> bool:
	return phase == &"night" and stats.urn_cap > 0.0 and urn_n >= int(stats.urn_cap)


func urn_burst(x: float, y: float) -> void:
	var v: float = urn_v * stats.urn_mult
	urn_n = 0
	urn_v = 0.0
	urn_bursts += 1
	add_night_bonus(v, Loc.t("sim_game.jar_burst", "陶瓮迸裂"))
	stone.r = maxf(stats.r0, stone.r * 0.75)
	if not stone.air:
		place_boulder()
	fx.shards(x, y, 40, 14.0, 0.4)
	fx.coins(x, y + 2.0, 16, 0.0)
	fx.text(x, y + stone.r + 2.0, Loc.t("sim_game.jar_bursts", "陶瓮迸裂！+") + NumFmt.fmt(v), 30.0, SimFx.GOLD_HI, 1.4)
	fx.shake(0.5)
	fx.sfx(&"urnBurst")
	fx.sfx(&"shatter", 1.0)


# —— 结局（演出由表现层播放；sim 只暂停并等 finish_ending）——
func play_ending(id: StringName, on_done: Callable) -> void:
	ending_active = true
	keys.clear()
	hold_acc = 0.0
	_ending_done = on_done
	fx.event(&"ending", {"id": id})
	if hooks.has("play_ending"):
		(hooks["play_ending"] as Callable).call(id)
	else:
		finish_ending()


func finish_ending() -> void:
	var cb: Callable = _ending_done
	ending_active = false
	_ending_done = Callable()
	if cb.is_valid():
		cb.call()


# —— 演示：直接看夜晚 ——
func setup_demo(r: float) -> void:
	demo = true
	levels = {}
	stats = StatsBuilder.build_nodes(content, levels)
	meta_rules.apply_meta(stats)
	var alt: float = clampf((r - stats.r0) / stats.growth, 20.0, 760.0)
	city_level = 0 if r < 1.6 else (1 if r < 3.0 else (2 if r < 5.0 else (3 if r < 8.0 else 5)))
	record = alt
	day = 1
	stats.start_frac = 1.0
	world = World.new(r >= 4.0, content.terrain)
	objs = world.layout(content, stats, city_level, aspect_of, 3)
	gate = make_gate()
	var s0: float = world.s_at_alt(alt)
	stone = Boulder.new()
	stone.s = s0
	stone.ts = s0
	stone.r = r
	max_alt = alt
	place_boulder()
	place_sisyphus()
	stone.save_prev()
	cam_tx = stone.x
	cam_ty = stone.y
	cam_view_h = maxf(16.0, r * 7.0)
	cam_snap += 1
	chests.clear()
	mods.reset()
	phase = &"day"
	day_t = 99.0
	start_dusk()


# ———————————————— 主循环 ————————————————
func _wait(sec: float, hook: StringName, data: Dictionary) -> void:
	_wait_t = sec
	_wait_hook = hook
	_wait_data = data


## 推进一拍（dt = 模拟时间；顿帧/慢放由 FeelClock 决定每秒跑几拍，不改 dt）
func tick(dt: float) -> void:
	if ending_active or modal != null or phase == &"idle":
		return
	stone.save_prev()
	t += dt
	if float(buff["stele_t"]) > 0.0:
		buff["stele_t"] = maxf(0.0, float(buff["stele_t"]) - dt)
	if float(buff["no_back_t"]) > 0.0:
		buff["no_back_t"] = maxf(0.0, float(buff["no_back_t"]) - dt)
	tier_flash = maxf(0.0, tier_flash - dt * 1.5)
	combo_pulse = maxf(0.0, combo_pulse - dt * 5.0)
	if not gate.is_empty():
		gate["shake"] = maxf(0.0, float(gate["shake"]) - dt * 1.2)
		_update_gate(dt)
	for o: CrushObj in objs:
		if o.state == CrushObj.State.FLAT:
			o.t += dt
		if o.shake > 0.0:
			o.shake = maxf(0.0, o.shake - dt * 3.0)
	match phase:
		&"day":
			_update_day(dt)
		&"dusk":
			_update_dusk(dt)
		&"night":
			_update_night(dt)
			if phase == &"night":
				meta_rules.update_steles(dt)
			if gate_hit:
				gate_end_t -= dt
				if gate_end_t <= 0.0:
					try_end_night(&"gate")
	if phase == &"night" or phase == &"night_end":
		chests.update(dt)
	if phase == &"night" and gate_hit:
		cam_tx = float(gate["x"]) + float(gate["w"]) * 0.25
		cam_ty = float(gate["h"]) * 0.5
		cam_view_h = maxf(maxf(float(gate["h"]) * 2.2, 30.0), stone.r * 2.4)
	if _wait_hook != &"":
		_wait_t -= dt
		if _wait_t <= 0.0:
			var hk: StringName = _wait_hook
			_wait_hook = &""
			if hooks.has(String(hk)):
				(hooks[String(hk)] as Callable).call(_wait_data)


## 冥府之门：夜里预估重数；撞门后逐枚点亮封印（每枚 70ms），亮完开门 1.0s 再合上
func _update_gate(dt: float) -> void:
	var gt: Dictionary = gate
	var b: Boulder = stone
	if phase == &"night" and not gate_hit:
		var vel: float = b.speed()
		var e: float = 0.5 * pow(b.r, 3.0) * stats.mass_mult * vel * vel
		var p: int = seals_for(e, 1 if urn_full() else 0)
		gt["predict"] = float(gt["predict"]) + (p - float(gt["predict"])) * minf(1.0, dt * 3.0)
	if float(gt["hit_t"]) >= 0.0:
		gt["hit_t"] = float(gt["hit_t"]) + dt
		while int(gt["seal_q"]) < int(gt["seals"]) and float(gt["hit_t"]) >= int(gt["seal_q"]) * SEAL_GAP:
			var i: int = int(gt["seal_q"])
			gt["seal_q"] = i + 1
			fx.sfx(&"gateKnock", i / 9.0)
			fx.event(&"gate_knock", {"i": i})
		var t0: float = int(gt["seals"]) * SEAL_GAP + 0.08
		var tt: float = float(gt["hit_t"]) - t0
		if int(gt["seals"]) <= 0 or tt < 0.0:
			gt["open"] = 0.0
		elif tt < 0.25:
			gt["open"] = tt / 0.25
		elif tt < 1.25:
			gt["open"] = 1.0
		else:
			gt["open"] = maxf(0.0, 1.0 - (tt - 1.25) / 0.4)
