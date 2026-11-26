extends Node
## 游戏入口与流程（= 网页 main.js）：主菜单 → 新开 / 继续 → 白天 → 夜晚 → 工资条 → 夜宴（present/hub/）→ 下一天；登顶 → 选择。
## 场景树在 main.tscn：BG(CanvasLayer -10) → World(Node2D + Camera2D) → FX(CanvasLayer 5) → HUD(20，hud.tscn) → UI(50) → 调试控制台(90)；
## 夜宴期间另挂 HubView（自带镜头和层）。

var content: ContentDB
var save: SaveService
var runner: SimRunner
var sim: SimGame = null
var bg: BackgroundView
var world: WorldView
var fxv: FxView
var hud: HudView
var ui: Control
## 游戏画面（背景、山、城、特效、夜宴）画在这个子视口里，按设置的渲染分辨率缩放后由 GameView 铺满窗口；HUD 和界面在主视口，始终原生分辨率
var game_vp: SubViewport
var game_view: TextureRect
var _modal_ui: Control = null
var _modal_id: int = -1
var _screen: Control = null
## 夜宴大厅（工资条之后到天亮之前）；不在夜宴时为 null
var _hub: HubView = null
## 后台预热资源（AssetWarmer：开局、夜里第一次用到的贴图和音效，夜宴的依赖；无头模式下的测试 / 机器人不需要）
var _hub_warm: bool = DisplayServer.get_name() != "headless"
## 开局盖黑那一帧里（防止连点两次开两局）
var _starting: bool = false
## 天亮运镜（播放时模拟暂停、HUD 藏起来）
var _dawn: DawnShot = null
## 调试控制台（设置里打开后按 console 键，默认 F1）
var _console: DebugConsole
## 设置里的自动推石
var _autopush: AutoPusher = AutoPusher.new()
## 可改绑的动作 → 模拟的按键名（Esc 固定为暂停）
const SIM_KEYS: Array = [[&"push_left", &"L"], [&"push_right", &"R"], [&"strike", &"strike"], [&"end_day", &"end_day"]]


func _ready() -> void:
	Prof.mark("main._ready 开始")
	content = Content.db
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var auto: bool = args.has("--autoplay")
	# 内存存档：--nosave、自动驾驶，以及设置服务处于内存模式时（测试、无头运行、录像 / 截图工具都会设它）——工具绝不能写玩家的存档
	save = SaveService.new(args.has("--nosave") or auto or Settings.memory_only)
	save.saved.connect(_on_saved)
	# 节点都在 main.tscn 里（分层：BG -10 / World / FX 5 / HUD 20 / UI 50 / 调试控制台 90）
	runner = $Runner as SimRunner
	game_vp = $GameViewport as SubViewport
	game_view = $GameView as TextureRect
	game_view.texture = game_vp.get_texture()
	bg = $GameViewport/BG/Background as BackgroundView
	world = $GameViewport/World as WorldView
	fxv = $GameViewport/FX/Fx as FxView
	hud = $HUD/Hud as HudView
	ui = $UI/Screens as Control
	_console = $DebugConsole as DebugConsole
	fxv.hud_view = hud
	if auto:
		var ap: AutoPilot = AutoPilot.new()
		ap.main = self
		add_child(ap)
		move_child(ap, 0)
	runner.events.connect(_on_events)
	_console.runner = runner
	_console.cmds.main = self
	PauseScreen.apply_settings(world)
	get_viewport().size_changed.connect(_fit_game_view)
	Settings.gfx_changed.connect(_fit_game_view)
	Settings.locale_changed.connect(_on_locale_changed)
	Settings.gfx_changed.connect(func() -> void:
		if _hub != null:
			_hub.apply_gfx()
		)
	_fit_game_view()
	# 后台预热（一次读一个）：先排开局、白天、夜里第一次用到的（warm.json 录的），夜宴的依赖白天再排（HubView.warm_step）。
	# --no-warm：关掉（tools/assets/record_warm.py 录清单时要看"不预热时哪些是用到才读的"）
	if args.has("--no-warm"):
		_hub_warm = false
	AssetWarmer.enabled = _hub_warm
	AssetWarmer.enqueue_manifest(["run"])
	_set_views_visible(false)
	Prof.mark("main 设置完")
	_show_menu()
	Prof.mark("main._ready 完成（菜单已建）")
	RenderingServer.frame_post_draw.connect(func() -> void: Prof.mark("第一帧画完"), CONNECT_ONE_SHOT)


## 编辑器 / 调试构建，或命令行带 --dev（调试控制台 2026-10-16 起正式版也能用，只看设置开关）
static func dev_mode() -> bool:
	return OS.is_debug_build() or OS.get_cmdline_user_args().has("--dev")


## 子视口跟着窗口和渲染分辨率走：像素尺寸 = 窗口实际像素 × render_scale；2D 坐标系固定成主视口的逻辑尺寸
## （size_2d_override + stretch），所以所有按视口大小排版、按逻辑坐标换算的代码（HUD 跟随世界坐标等）都不用改
func _fit_game_view() -> void:
	var root: Viewport = get_viewport()
	var logical: Vector2 = root.get_visible_rect().size
	var phys: Vector2 = Vector2(get_window().size) if get_window() != null else logical
	if logical.x < 2.0 or logical.y < 2.0 or phys.x < 2.0 or phys.y < 2.0:
		return
	var px: Vector2i = Vector2i(maxi(2, roundi(phys.x * Settings.render_scale)), maxi(2, roundi(phys.y * Settings.render_scale)))
	game_vp.size_2d_override = Vector2i(roundi(logical.x), roundi(logical.y))
	if game_vp.size != px:
		game_vp.size = px


## 菜单、结局这些时候世界和夜宴都不画：子视口停止渲染，省下一整屏的填充
func _sync_game_view() -> void:
	var on: bool = world.visible or _hub != null
	var mode: SubViewport.UpdateMode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if game_vp.render_target_update_mode != mode:
		game_vp.render_target_update_mode = mode
		game_view.visible = on


func _set_views_visible(v: bool) -> void:
	world.visible = v
	(bg.get_parent() as CanvasLayer).visible = v
	(fxv.get_parent() as CanvasLayer).visible = v
	(hud.get_parent() as CanvasLayer).visible = v


func _on_events(list: Array[SimEvent]) -> void:
	world.on_events(list)
	fxv.on_events(list)
	hud.on_events(list)
	Sfx.on_events(list)
	for e: SimEvent in list:
		if e.kind == &"ending_seen":
			_record_seen(StringName(str(e.data.get("id", ""))))


# ———————————————— 菜单 ————————————————
func _show_menu() -> void:
	_close_hub()
	runner.sim = null
	Sfx.stop_all()
	Sfx.bgm(&"menu")
	_set_views_visible(false)
	var meta: Dictionary = MetaLogic.normalize(save.load_meta())
	var has: bool = save.has_run()
	var run: Dictionary = save.load_run() if has else {}
	# 第一次启动的抢先体验说明、存档读坏了的提示：开始页面出来后盖在上面（各一次）
	var first_run: bool = not Settings.ea_notice_seen and not Settings.memory_only
	if first_run:
		Settings.ea_notice_seen = true
		Settings.save_to_disk()
	var problem: String = save.problem
	save.problem = ""
	var live: bool = has and not bool(run.get("ended", false))
	var gen: int = int(meta["gen"])
	var seen: int = 0
	for e: StoryDefs.Ending in content.endings_on():
		if (meta["endings"] as Dictionary).has(String(e.id)):
			seen += 1
	var buttons: Array = []
	if live:
		buttons.append({"id": "continue", "label": Loc.t("main.continue_day", "继续 · 第 %d 日") % int(run.get("day", 1)), "gold": true})
		buttons.append({"id": "new", "label": Loc.t("main.restart_generation", "重新开始本代")})
	else:
		buttons.append({"id": "new", "label": (Loc.t("main.begin_generation", "开始第 %d 代") % gen) if gen > 1 else Loc.t("main.start_pushing", "开始推石"), "gold": true})
	if seen > 0:
		buttons.append({"id": "gallery", "label": Loc.t("main.ending_gallery", "结局画廊")})
	buttons.append({"id": "settings", "label": Loc.t("main.settings", "设置")})
	buttons.append({"id": "feedback", "label": Loc.t("main.feedback", "反馈")})
	buttons.append({"id": "records", "label": Loc.t("main.records", "记录")})
	buttons.append({"id": "credits", "label": Loc.t("main.credits", "制作人员")})
	buttons.append({"id": "quit", "label": Loc.t("main.quit", "退出")})
	var ms: MenuScreen = MenuScreen.create()
	ms.buttons = buttons
	ms.redfig = MetaLogic.has_reward(content, meta, "redfig")
	if live:
		ms.instant = ["new"]     # 先弹确认框，不播放大
	if gen > 1 or float(meta["embers"]) > 0.0 or seen > 0:
		ms.gen_line = Loc.t("main.generation_embers_endings", "第 %d 代 · 血脉余烬 %d · 已见结局 %d / %d") % [gen, int(meta["embers"]), seen, content.endings_on().size()]
	ms.chosen.connect(func(id: String, arg: float) -> void:
		match id:
			"continue":
				_start(run)
			"new":
				# 有进行中的一代：先确认（只清本代存档；血脉、祖传、结局记录都保留）
				if live:
					var cs: ChoiceScreen = ChoiceScreen.create()
					cs.title = Loc.t("main.restart_generation_2", "重新开始本代？")
					cs.subtitle = Loc.t("main.progress_day_will_lost", "第 %d 日的进度会清空。血脉、祖传和结局记录保留。") % int(run.get("day", 1))
					cs.choices = [{"label": Loc.t("main.restart", "重新开始")}, {"label": Loc.t("main.cancel", "取消"), "gold": true}]
					cs.chosen.connect(func(i: int) -> void:
						if i == 0:
							MetaLogic.absorb_run(meta, run.get("run_stats", {}), int(run.get("day", 1)), int((run.get("run", {}) as Dictionary).get("gen", gen)))
							save.save_meta(meta)
							save.clear_run()
							_new_run(meta, true)
						else:
							ms.close_overlay()
						)
					ms.overlay(cs)
					return
				if has:
					save.clear_run()
				_new_run(meta, true)
			"gallery":
				_show_gallery(meta)
			"settings":
				_open_settings(ms, "")
			"demo":
				_start({}, arg)
			"feedback":
				ms.overlay(Feedback.feedback_screen(func(_i: int) -> void: ms.close_overlay()))
			"records":
				var rec: RecordsScreen = RecordsScreen.create()
				rec.content = content
				rec.meta = meta
				if live:
					rec.cur = {"run_stats": run.get("run_stats", {}), "day": int(run.get("day", 1)), "record": float(run.get("record", 0.0)),
						"gen": int((run.get("run", {}) as Dictionary).get("gen", gen))}
				rec.back_pressed.connect(ms.close_overlay)
				ms.overlay(rec)
			"credits":
				ms.overlay(Feedback.credits_screen(func(_i: int) -> void: ms.close_overlay()))
			_:
				get_tree().quit()
		)
	_show_screen(ms)
	_menu_notices(ms, problem, first_run)


## 主菜单上盖一层设置界面；page = 打开时停在哪一页
func _open_settings(ms: MenuScreen, page: String) -> void:
	var ss: SettingsScreen = SettingsScreen.create()
	ss.world = world
	ss.start_page = page
	ss.back_pressed.connect(ms.close_overlay)
	ms.overlay(ss)


## 设置里切了语言（只有主菜单的设置能切）：内容已按新语言重载（Settings.set_locale），
## 这里换成新的内容库，整个主菜单重建（菜单、按钮、提示都是代码按当前语言拼的），再把设置开回"游戏"那一页
func _on_locale_changed() -> void:
	content = Content.db
	if not (_screen is MenuScreen):
		return
	_show_menu()
	var ms: MenuScreen = _screen as MenuScreen
	if ms != null:
		_open_settings(ms, "Game")


## 开始页面上依次盖：存档读坏了的说明 → 第一次启动的抢先体验说明（都只出现一次）
func _menu_notices(ms: MenuScreen, problem: String, first_run: bool) -> void:
	if problem != "":
		var cs: ChoiceScreen = ChoiceScreen.create()
		cs.title = Loc.t("main.save_file", "存档")
		cs.subtitle = problem
		cs.choices = [{"label": Loc.t("main.ok", "好"), "gold": true}]
		cs.chosen.connect(func(_i: int) -> void:
			ms.close_overlay()
			_menu_notices(ms, "", first_run)
			)
		ms.overlay(cs)
	elif first_run:
		ms.overlay(Feedback.ea_notice_screen(func(_i: int) -> void: ms.close_overlay()))


## 开新一代：第 1 代直接开；之后先过开局设置（石头 / 契约 / 血之传承）
func _new_run(meta: Dictionary, from_menu: bool) -> void:
	if int(meta["gen"]) <= 1 and (meta["heir"] as Dictionary).is_empty() and int(meta["heat_max"]) <= 0:
		_start(MetaLogic.new_run_persist(content, meta))
		return
	var rs: RunSetupScreen = RunSetupScreen.create()
	rs.content = content
	rs.meta = meta
	rs.allow_back = from_menu
	rs.start_pressed.connect(func(stone: String, pacts: Dictionary, blood: String) -> void:
		_start(MetaLogic.new_run_persist(content, meta, stone, pacts, blood))
		)
	rs.back_pressed.connect(_show_menu)
	_show_screen(rs)


## 滚落体验（= 网页主菜单的 demo 按钮）：选一块石头，直接看它滚下山
static func _demo_stones() -> Array:
	return [[0.9, Loc.t("main.pebble_1_8_m", "卵石 1.8m")], [2.6, Loc.t("main.ox_cart_5_m", "牛车级 5m")], [5.0, Loc.t("main.sanctuary_10_m", "神殿级 10m")], [9.0, Loc.t("main.titan_18_m", "泰坦级 18m")]]


func _demo_menu() -> void:
	runner.sim = null
	_set_views_visible(false)
	var choices: Array = []
	var stones: Array = _demo_stones()
	for d: Array in stones:
		choices.append({"label": String(d[1]), "gold": float(d[0]) >= 9.0})
	choices.append({"label": Loc.t("main.back", "返回")})
	var cs: ChoiceScreen = ChoiceScreen.create()
	cs.title = Loc.t("main.try_downhill_run", "直接体验「滚下山」")
	cs.subtitle = Loc.t("main.same_hill_bigger_stone", "同一座山，石头越大，能碾的东西越大、震得越狠")
	cs.dim = 0.95
	cs.choices = choices
	cs.chosen.connect(func(i: int) -> void:
		if i < stones.size():
			_start({}, float(stones[i][0]))
		else:
			_show_menu()
		)
	_show_screen(cs)


func _show_gallery(meta: Dictionary) -> void:
	var gs: GalleryScreen = GalleryScreen.create()
	gs.content = content
	gs.meta = meta
	gs.back_pressed.connect(_show_menu)
	gs.replay.connect(func(id: StringName) -> void:
		_show_screen(null)
		var tmp: SimGame = SimGame.new(content, {}, meta)
		_play_ending_ui(id, tmp, func() -> void:
			tmp.dispose()
			_show_gallery(meta)
			)
		)
	_show_screen(gs)


func _show_screen(c: Control) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = c
	if c != null:
		ui.add_child(c)


# ———————————————— 一局 ————————————————
func _start(persist: Dictionary, demo_r: float = 0.0) -> void:
	if demo_r <= 0.0 and Engine.get_process_frames() > 0:
		# 开局要建世界、第一次画满屏物件（0.2–0.3 秒）：先盖一帧全黑再建，卡在黑屏底下看不出来；天亮运镜本来就从全黑淡入
		if _starting:
			return
		_starting = true
		var cover: ColorRect = _black_cover()
		await _wait_drawn()
		_starting = false
		_start_now(persist, demo_r)
		cover.queue_free()
		return
	_start_now(persist, demo_r)


## 等画面真的画出一帧（盖上的黑幕已经显示）。无头模式、窗口最小化时引擎不画帧、frame_post_draw 不发，只等一帧处理，免得卡住
func _wait_drawn() -> void:
	if DisplayServer.get_name() == "headless" or not DisplayServer.window_can_draw():
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw


## 盖住整个画面的黑幕（UI 层最上面）：先画出一帧全黑，再做会卡的事
func _black_cover() -> ColorRect:
	var cover: ColorRect = ColorRect.new()
	cover.color = Color.BLACK
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(cover)
	return cover


func _start_now(persist: Dictionary, demo_r: float = 0.0) -> void:
	_close_hub()
	_show_screen(null)
	var meta: Dictionary = save.load_meta()
	_autopush = AutoPusher.new()
	if sim != null:
		sim.dispose()
	var _pt: int = Prof.t()
	sim = SimGame.new(content, persist, meta)
	Prof.add(&"start.sim_new", _pt)
	sim.hooks = {
		"on_night_end": _on_night_end,
		"on_victory": _on_victory,
		"save": _save,
		"play_ending": _on_play_ending,
		"on_run_end": func(id: StringName) -> void: _end_run(id),
	}
	world.sim = sim
	world.runner = runner
	bg.sim = sim
	bg.wv = world
	fxv.sim = sim
	fxv.wv = world
	fxv.runner = runner
	hud.sim = sim
	hud.fxv = fxv
	hud.wv = world
	var bv: BoonView = BoonView.new()
	bv.setup(content)
	world.boons = bv
	hud.boons = bv
	var sv: StoryView = StoryView.new()
	world.story_view = sv
	hud.story_view = sv
	var cv: ChestView = ChestView.new()
	world.chest_view = cv
	hud.chest_view = cv
	runner.sim = sim
	runner.reset_feel()
	if demo_r > 0.0:
		sim.setup_demo(demo_r)
		Sfx.bgm(&"off")
	else:
		_pt = Prof.t()
		sim.start_day()
		Prof.add(&"start.start_day", _pt)
		Sfx.bgm(&"day")   # 天亮运镜期间模拟暂停、phase 事件要等第一拍才到，先切过去
	_set_views_visible(true)
	# 上一局可能在天亮运镜中途退出（HUD 还是全透明）：先复原，非滚落体验的局再由运镜接管
	hud.modulate.a = 1.0
	hud.visible = true
	if demo_r <= 0.0:
		_play_dawn()


## 存档写盘后右下角闪一下"已自动保存"（游戏没有手动存档：每天结束、回主菜单、退出时自动存）
func _on_saved() -> void:
	var mark: CanvasItem = get_node_or_null("UI/SaveMark") as CanvasItem
	if mark == null:
		return
	var tw: Tween = create_tween()
	tw.tween_property(mark, "modulate:a", 1.0, 0.2)
	tw.tween_interval(1.2)
	tw.tween_property(mark, "modulate:a", 0.0, 0.6)


func _save() -> void:
	if sim != null and not sim.demo:
		save.save_run(sim.persist())


func _on_night_end(data: Dictionary) -> void:
	if sim.demo:
		var r: float = sim.stone.r
		var ps0: PayslipScreen = PayslipScreen.create()
		ps0.data = data
		ps0.button_label = Loc.t("main.continue", "继续")
		ps0.next_pressed.connect(func() -> void:
			var cs: ChoiceScreen = ChoiceScreen.create()
			cs.title = Loc.t("main.downhill_run", "滚落体验")
			cs.subtitle = Loc.t("main.crushed_drachmas_worth_tonight", "这一夜碾得 %s 德拉克马") % NumFmt.fmt(float(data.get("net", 0.0)))
			cs.dim = 0.8
			cs.choices = [{"label": Loc.t("main.roll_again", "再滚一次"), "gold": true}, {"label": Loc.t("main.pick_another_stone", "换一块石头")}, {"label": Loc.t("main.main_menu", "回主菜单")}]
			cs.chosen.connect(func(i: int) -> void:
				match i:
					0:
						_start({}, float(data.get("start_r", r)))
					1:
						_demo_menu()
					_:
						_show_menu()
				)
			_show_screen(cs)
			)
		_show_screen(ps0)
		return
	sim.day += 1
	var _pt: int = Prof.t()
	_save()
	Prof.add(&"night_end.save", _pt)
	_pt = Prof.t()
	var ps: PayslipScreen = PayslipScreen.create()
	ps.data = data
	ps.next_pressed.connect(_after_payslip)
	_show_screen(ps)
	Prof.add(&"night_end.payslip", _pt)


## 工资条 → 剧情事件链（回响阶梯、石榴、渡河、信；对话模态由 _process 打开）→ 夜宴
func _after_payslip() -> void:
	_show_screen(null)
	var g: SimGame = sim
	sim.story.after_payslip(func() -> void:
		if sim == g:
			_save()
			_show_hub()
		)


## 夜宴：众神在今晚的废墟上开席。走到赫利俄斯那里确认天亮 → 下一天
func _show_hub() -> void:
	# 先盖一帧全黑再建夜宴（第一晚要建众神、灯、幽魂队列，0.1–0.2 秒），建好后从黑里淡出：卡顿藏在黑幕底下
	var cover: ColorRect = _black_cover()
	var g: SimGame = sim
	await _wait_drawn()
	if sim != g or sim == null or _hub != null:
		cover.queue_free()
		return
	_close_hub()
	_set_views_visible(false)
	var _pt: int = Prof.t()
	var h: HubView = HubView.create()
	Prof.add(&"hub.create", _pt)
	_pt = Prof.t()
	h.name = "Hub"
	h.sim = sim
	h.content = content
	h.blocked = func() -> bool: return _screen != null or _console.is_open
	h.left.connect(_leave_hub)
	_hub = h
	game_vp.add_child(h)
	# 夜宴自己的界面层（提示、对话、商店）挪到主视口：不随渲染分辨率变糊、按钮收得到鼠标
	h.detach_ui(self)
	Prof.add(&"hub.ready", _pt)
	# 夜宴：撞门后的合唱团收掉，换夜宴曲
	Sfx.chorus(0.0)
	Sfx.bgm(&"feast")
	# 黑幕底下先把整个大厅缩小画一帧（新机器第一次进夜宴要现编着色器），镜头回位后再淡出
	h.prewarm_view()
	for i: int in 3:
		await get_tree().process_frame
	if not is_instance_valid(cover):
		return
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw: Tween = cover.create_tween()
	tw.tween_property(cover, "color:a", 0.0, 0.35)
	tw.tween_callback(cover.queue_free)


func _leave_hub() -> void:
	var _pt: int = Prof.t()
	_close_hub()
	_set_views_visible(true)
	world.cam.make_current()
	Prof.add(&"leave.close_hub", _pt)
	_pt = Prof.t()
	_save()
	Prof.add(&"leave.save", _pt)
	_pt = Prof.t()
	sim.start_day()
	Prof.add(&"leave.start_day", _pt)
	_pt = Prof.t()
	Sfx.bgm(&"day")
	fxv.clear()
	_play_dawn()
	Prof.add(&"leave.dawn", _pt)


## 天亮运镜：冥府大门 → 城镇全景 → 西西弗斯（present/world/dawn_shot.gd）；纯表现，播放时模拟暂停，空格跳过
func _play_dawn() -> void:
	if sim == null or sim.demo:
		return
	if _dawn != null:
		_dawn.queue_free()
	_dawn = DawnShot.create()
	add_child(_dawn)
	runner.app_paused = true
	# HUD 不隐藏、只调成全透明：照常画，第一次画要排一堆字形（~30 毫秒），在运镜里先画掉，运镜结束 HUD 出现那一帧就不卡了
	hud.modulate.a = 0.0
	# 模拟暂停着、还没走第一拍：先把西西弗斯摆到石头后面（白天每拍都会重摆，确定性的，不影响模拟）
	if sim.sis.is_empty():
		sim.place_sisyphus()
	_dawn.finished.connect(_end_dawn)
	_dawn.play(world, sim)


func _end_dawn() -> void:
	if _dawn != null:
		_dawn.stop()
		_dawn.queue_free()
		_dawn = null
	world.cine = Vector3(NAN, NAN, NAN)
	hud.modulate.a = 1.0
	hud.visible = true
	if _screen == null:
		runner.app_paused = false


func _close_hub() -> void:
	if _hub == null:
		return
	_hub.teardown()
	_hub.queue_free()
	_hub = null
	world.cam.make_current()



## 登顶菜单：继续 / 假结局（演完回到菜单）/ 普通或真结局（结束本代）
func _on_victory(data: Dictionary) -> void:
	var choices: Array = sim.story.summit_choices()
	var cs: ChoiceScreen = ChoiceScreen.create()
	cs.title = Loc.t("main.summit", "山 顶")
	cs.subtitle = Loc.t("main.day_once_stone_stays", "第 %d 日 · 石头第一次停在了山顶") % int(data.get("day", sim.day))
	cs.dim = 0.55
	cs.choices = choices
	cs.chosen.connect(func(i: int) -> void:
		var c: Dictionary = choices[i]
		var id: StringName = StringName(str(c.get("id", "")))
		_show_screen(null)
		match String(c.get("kind", "")):
			"continue":
				sim.start_dusk()
			"fake":
				sim.play_ending(id, func() -> void:
					sim.story.apply_fake_comp(id)
					_record_seen(id)
					_save()
					_on_victory(data)
					)
			_:
				sim.play_ending(id, func() -> void: _end_run(id))
		)
	_show_screen(cs)


## SimGame.play_ending 的表现：放结局演出（含结局卡），演完 sim.finish_ending()
func _on_play_ending(id: StringName) -> void:
	var g: SimGame = sim
	_play_ending_ui(id, sim, func() -> void:
		if sim == g:
			sim.finish_ending()
		)


## 结局演出 + 结局卡（present/endings/ending_player.gd）；完成后调 done
func _play_ending_ui(id: StringName, g: SimGame, done: Callable) -> void:
	var ep: EndingPlayer = EndingPlayer.new()
	ep.setup(id, g)
	ep.finished.connect(func() -> void:
		ep.queue_free()
		done.call()
		)
	ui.add_child(ep)


## 假结局第一次出现时写进 meta.endings（画廊用）；本代结束的结局在 _end_run 里统一记
func _record_seen(id: StringName) -> void:
	if MetaLogic.ending_kind(content, id) != &"fake" or sim == null or sim.demo:
		return
	var meta: Dictionary = MetaLogic.normalize(save.load_meta())
	MetaLogic.record_ending(meta, id, int(sim.run.get("gen", 1)))
	save.save_meta(meta)


## 本代结束：余烬结算、立碑、写 meta → 血脉界面 → 开局设置 → 下一代第 1 天
func _end_run(id: StringName) -> void:
	if sim == null:
		return
	_close_hub()
	if sim.story.runner != null:
		sim.story.runner.abort()
		sim.story.runner = null
	var meta: Dictionary = MetaLogic.on_run_end(content, save.load_meta(), sim.run, sim.run_stats, id, sim.record, sim.day, sim.story.flags)
	sim.meta = meta
	sim.ended = true
	_save()
	save.save_meta(meta)
	runner.sim = null
	var bl: BloodlineScreen = BloodlineScreen.create()
	bl.content = content
	bl.meta = meta
	bl.meta_changed.connect(func() -> void: save.save_meta(meta))
	bl.next_pressed.connect(func(text: String, gen: int) -> void:
		if text != "":
			MetaLogic.set_stele_text(meta, gen, text)
		save.save_meta(meta)
		_set_views_visible(false)
		_new_run(meta, false)
		)
	_show_screen(bl)


# ———————————————— 每帧：模态与输入 ————————————————
func _process(dt: float) -> void:
	_sync_game_view()
	if _hub_warm:
		AssetWarmer.step()
	_console.cmds.sim = sim
	if sim == null:
		return
	# 游戏时长（记录页用）：暂停、主菜单时不算；白天、夜里、夜宴都算
	if not runner.app_paused and not sim.demo and runner.sim == sim:
		sim.run_stats["time_s"] = float(sim.run_stats.get("time_s", 0.0)) + dt
	# 设置里的自动推石：白天、没开面板 / 夜宴 / 控制台 / 暂停时替玩家交替按左右
	_autopush.rate = Settings.auto_push_rate
	_autopush.step(sim, Settings.auto_push and _screen == null and _hub == null and not runner.app_paused and not _console.is_open and runner.sim == sim)
	# 滚石隆隆声：模拟不发逐帧 rumble 事件，音频层只读石头速度 / 体积自己算
	if runner.sim == sim and not runner.app_paused:
		Sfx.follow_stone(sim)
	# 夜宴场景在后台提前加载，翻完工资条直接进（第一次同步加载整屏卡 0.9 秒）。不在入夜时加载：贴图传显卡仍在主线程、
	# 要卡 50–100 毫秒；挪到撞冥府之门那一刻（本来就慢放 + 大震屏，看不出来），没撞门的夜晚在收夜时（HubView.preload_scene）
	if _hub == null and not sim.demo and ((sim.phase == &"night" and sim.gate_hit) or sim.phase == &"night_end"):
		HubView.preload_scene()
	# 更早：白天就开始一张一张预热夜宴的贴图（每帧最多传一张进显卡），第一晚收夜时基本都已就绪
	elif _hub == null and not sim.demo and _hub_warm:
		HubView.warm_step()
	if sim.modal != null and _modal_id != sim.modal.id + sim.modal.get_instance_id():
		_open_modal_ui(sim.modal)
	elif sim.modal == null and _modal_ui != null:
		_modal_ui.queue_free()
		_modal_ui = null
		_modal_id = -1


func _open_modal_ui(m: ModalRequest) -> void:
	if _modal_ui != null:
		_modal_ui.queue_free()
	_modal_id = m.id + m.get_instance_id()
	if m.kind == ModalRequest.Kind.DIALOG:
		var dp: DialogPanel = DialogPanel.create()
		dp.setup(m)
		dp.answered.connect(func(i: int) -> void: sim.answer(i))
		_modal_ui = dp
		ui.add_child(dp)
		return
	if m.kind == ModalRequest.Kind.ALTAR:
		var fs: AltarShow = AltarShow.create()
		fs.setup(m)
		fs.finished.connect(func() -> void: sim.answer(0))
		_modal_ui = fs
		ui.add_child(fs)
		return
	var pp: PickPanel = PickPanel.create()
	pp.setup(m)
	pp.chosen.connect(func(i: int) -> void: sim.answer(i))
	pp.reroll_requested.connect(func() -> void:
		sim.reroll()
		_modal_id = -1
		)
	_modal_ui = pp
	ui.add_child(pp)


## 键盘和鼠标键都走 InputMap 动作（Settings 里改绑）；Esc 固定为暂停
func _unhandled_input(ev: InputEvent) -> void:
	if sim == null or _screen != null or sim.modal != null or _console.is_open:
		return
	# 天亮运镜：任何键 / 鼠标键按下 = 跳过（快进到结尾），按键都不漏给模拟
	if _dawn != null and _dawn.playing():
		if (ev is InputEventKey or ev is InputEventMouseButton) and ev.is_pressed() and not ev.is_echo():
			_dawn.skip()
		if ev is InputEventKey or ev is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	var k: InputEventKey = ev as InputEventKey
	if k != null and k.keycode == KEY_ESCAPE:
		if k.pressed and not k.echo:
			_pause()
		get_viewport().set_input_as_handled()
		return
	# 夜宴里走路、交互由 HubView 自己处理，不能漏给模拟（夜宴在 GameViewport 子视口里收不到输入事件，由这里转给它）
	if _hub != null:
		_hub.handle_input(ev)
		return
	if not (ev is InputEventKey or ev is InputEventMouseButton):
		return
	for pair: Array in SIM_KEYS:
		if ev.is_action(pair[0]):
			if ev.is_pressed():
				sim.key_down(pair[1], ev.is_echo())
			else:
				sim.key_up(pair[1])
			get_viewport().set_input_as_handled()
			return


## Esc：暂停菜单（模拟停住；继续 / 设置 / 回主菜单 / 退出）
func _pause() -> void:
	if sim == null or _screen != null:
		return
	runner.app_paused = true
	sim.release_all()
	var ps: PauseScreen = PauseScreen.create()
	ps.world = world
	ps.sim = sim
	ps.resume_pressed.connect(func() -> void:
		runner.app_paused = false
		_show_screen(null)
		)
	ps.menu_pressed.connect(func() -> void:
		runner.app_paused = false
		_save()
		_show_menu()
		)
	ps.quit_pressed.connect(func() -> void:
		_save()
		get_tree().quit()
		)
	_show_screen(ps)


## 退出时打断模拟的循环引用（否则退出时报资源泄漏）
func _exit_tree() -> void:
	if sim != null:
		sim.dispose()
		sim = null
	# 静态缓存（预热留着的引用、界面场景、夜宴场景）在退出前放掉，不然引擎退出时报 ObjectDB 泄漏
	AssetWarmer.clear()
	SceneCache.clear()
	HubView.release_cache()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		var real: bool = is_inside_tree() and get_tree().current_scene == self    # 录像、测试工具用脚本挂 main 时不算
		if sim != null:
			sim.release_all()
			# 切出窗口就暂停（设置里可关）：不然石头在玩家看不见的时候继续滚
			if real and Settings.pause_on_blur:
				_pause()
		if real and Settings.mute_unfocused:
			AudioServer.set_bus_mute(0, true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		AudioServer.set_bus_mute(0, false)
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		# 点窗口的关闭按钮：先存档（白天中途也存，和"回主菜单"一样）
		_save()
