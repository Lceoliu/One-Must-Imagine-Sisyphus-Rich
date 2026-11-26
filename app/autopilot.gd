class_name AutoPilot
extends Node
## 开发用自动驾驶（只在命令行带 --autoplay 时启用）：自动开一局、按 A/D、遇到面板选第一项，
## 按计划截图到 --shots=<目录>（默认 user://frames），截完退出。--days=N 跑几天，--fast=K 模拟加速。
## 绝不写存档：main.gd 在 --autoplay 时强制 --nosave；设置也只在内存里改（Settings.memory_only）。
## 设置相关：--settings 先截一张设置界面；--autopush 白天交给设置里的自动推石；--mouse 把推石改绑到鼠标左右键并真的发鼠标点击；
## --console="cmd1;cmd2" 第一天白天打开调试控制台依次执行命令并截图。

var main: Node = null
var shots_dir: String = "user://frames"
var prefix: String = "gd"
var days: int = 1
var fast: float = 1.0
var _f: int = 0
var _taken: Dictionary = {}
var _t: float = 0.0
var _phase_t: float = 0.0
var _last_phase: StringName = &""
var _day0: int = 1
## --demo=R：直接开滚落体验（半径 R 米），看夜里和撞门
var demo_r: float = 0.0
var _end_t: float = 0.0
var opt_settings: bool = false
var opt_autopush: bool = false
var opt_mouse: bool = false
var console_cmds: PackedStringArray = []
var _settings_t: float = -1.0
var _console_done: bool = false
## 夜宴：依次走到这些位置截图（act = 到了就按 E，截对话 / 摊位），最后买最便宜的东西、天亮
const HUB_STEPS: Array = [
	{"x": 900.0, "shot": "hub_gate"}, {"x": 2250.0, "shot": "hub_queue"}, {"x": 3330.0, "shot": "hub_couch"},
	{"x": 4780.0, "shot": "hub_throne"}, {"x": 6250.0, "shot": "hub_stele"}, {"x": 7200.0, "shot": "hub_fire"},
	{"x": 8880.0, "shot": "hub_forge"}, {"x": 9720.0, "shot": "hub_hermes"}, {"x": 10470.0, "shot": "hub_helios"},
	{"x": 4980.0, "act": true, "shot": "hub_talk"}, {"x": 9720.0, "act": true, "shot": "hub_shop"},
]
var _hub_id: int = 0
var _hub_t: float = 0.0


## --noshots：不存截图（量卡顿时用，存 PNG 本身就卡一下）；--spikes：每帧真实耗时超过 50 毫秒就打印一行（阶段、第几天、耗时）；
## --prof：同 --spikes，并打开 Prof 分段计时，卡顿那一帧各段花了多少一起打出来
## --perf：每 2 秒打印一行：阶段、平均 / 最慢帧时、GPU 时间（引擎计时查询）、绘制调用、显存；进主菜单时打印启动耗时和内存
var opt_noshots: bool = false
var opt_spikes: bool = false
var opt_perf: bool = false
var opt_summit_continue: bool = false
## --perf-layers：白天 / 夜宴里依次隐藏各图层 1.5 秒，打印每层的 GPU 时间（看谁最吃填充率）
var opt_layers: bool = false
var _lay: Dictionary = {}
var _perf: Dictionary = {}
var _us: int = 0
var _shot_f: int = -10


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
		elif a.begins_with("--prefix="):
			prefix = a.substr(9)
		elif a.begins_with("--days="):
			days = int(a.substr(7))
		elif a.begins_with("--fast="):
			fast = float(a.substr(7))
		elif a == "--noshots":
			opt_noshots = true
		elif a == "--spikes":
			opt_spikes = true
		elif a == "--perf":
			opt_perf = true
			Prof.on = true
		elif a.begins_with("--gfx="):
			# 画质预设 0 低 / 1 中 / 2 高（只改内存里的设置）
			Settings.apply_gfx_preset(int(a.substr(6)))
		elif a.begins_with("--render-scale="):
			Settings.render_scale = clampf(float(a.substr(15)), 0.5, 1.0)
			Settings.refresh_gfx_preset()
		elif a == "--perf-layers":
			opt_layers = true
		elif a == "--summit=continue":
			opt_summit_continue = true
		elif a == "--novsync":
			Settings.vsync = false
			Settings.max_fps = 0
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
		elif a == "--prof":
			opt_spikes = true
			Prof.on = true
		elif a.begins_with("--demo="):
			demo_r = float(a.substr(7))
		elif a == "--settings":
			opt_settings = true
		elif a == "--autopush":
			opt_autopush = true
		elif a == "--mouse":
			opt_mouse = true
		elif a.begins_with("--console="):
			console_cmds = a.substr(10).split(";", false)
	DirAccess.make_dir_recursive_absolute(shots_dir)
	Settings.memory_only = true
	# 并行跑好几局时窗口焦点会被别的窗口抢走：切出窗口自动暂停会把这一局卡在暂停菜单上（只改内存里的设置）
	Settings.pause_on_blur = false
	if opt_autopush:
		Settings.auto_push = true
	if opt_mouse:
		Settings.set_binding("push_left", 0, {"m": MOUSE_BUTTON_LEFT})
		Settings.set_binding("push_right", 0, {"m": MOUSE_BUTTON_RIGHT})
	if not console_cmds.is_empty():
		Settings.debug_console = true


func _shot(name: String) -> void:
	if _taken.has(name):
		return
	_taken[name] = true
	if opt_noshots:
		return
	_shot_f = Engine.get_process_frames()
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [shots_dir, prefix, name])
	print("[autopilot] shot ", name)


func _process(dt: float) -> void:
	_t += dt
	if opt_perf:
		_perf_step()
	if opt_layers:
		_layers_step()
	if opt_spikes:
		var now: int = Time.get_ticks_usec()
		var ms: float = (now - _us) / 1000.0
		if _us > 0 and ms > 50.0 and Engine.get_process_frames() - _shot_f > 3:
			var s0: SimGame = main.get("sim")
			print("[autopilot] SPIKE %.0fms day=%s phase=%s t=%.1fs screen=%s" % [ms, str(s0.day) if s0 != null else "-", String(s0.phase) if s0 != null else "-", _t,
				str((main.get("_screen") as Node).name) if main.get("_screen") != null else "-"])
			if Prof.on:
				print("    process=%.0fms  " % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0), Prof.report(1))
		_us = now
		Prof.reset()
	var sim: SimGame = main.get("sim")
	var screen: Control = main.get("_screen")
	if sim == null:
		var ms: MenuScreen = screen as MenuScreen
		var ss: SettingsScreen = screen as SettingsScreen
		if ss == null and ms != null:
			ss = ms.current_overlay() as SettingsScreen
		if ss != null:
			_settings_t += dt
			if _settings_t > 1.0:
				_shot("settings")
			if _settings_t > 1.6:
				ss.back_pressed.emit()
			return
		if ms != null and opt_settings and _settings_t < 0.0 and _t > 0.8:
			_settings_t = 0.0
			ms.chosen.emit("settings", 0.0)
			return
		if ms != null and _t > 0.8:
			_shot("menu")
			if demo_r > 0.0:
				main.call("_start", {}, demo_r)
			elif _t > 1.2:
				ms.chosen.emit("new", 0.0)
		return
	(main.get("runner") as SimRunner).dev_speed = fast
	# 结局演出：截两张，然后直接结束
	for ch: Node in (main.get("ui") as Control).get_children():
		var ep: EndingPlayer = ch as EndingPlayer
		if ep == null:
			continue
		_end_t += dt
		if _end_t > 2.0:
			_shot("end_%s_a" % String(ep.get("id")))
		if _end_t > 5.0:
			_shot("end_%s_b" % String(ep.get("id")))
			_end_t = 0.0
			ep.skip_all()
		return
	if sim.phase != _last_phase:
		_last_phase = sim.phase
		_phase_t = 0.0
	_phase_t += dt
	var tag: String = "d%d_" % sim.day
	var hub: HubView = main.get("_hub") as HubView
	if hub != null and screen == null:
		_drive_hub(hub, sim, dt, "d%d_" % (sim.day - 1))
		return
	if screen is PayslipScreen and sim.demo:
		if _phase_t > 2.5:
			_shot(tag + "payslip")
			get_tree().quit()
		return
	if screen is PayslipScreen:
		if _phase_t > 2.5:
			_shot(tag + "payslip")
			if _phase_t > 3.2:
				(screen as PayslipScreen).next_pressed.emit()
		return
	if screen is ShopScreen:
		_shot(tag + "shop")
		_buy_cheapest(sim)
		if sim.day > _day0 + days - 1:
			get_tree().quit()
			return
		(screen as ShopScreen).start_pressed.emit()
		return
	if screen is ChoiceScreen:
		_shot(tag + "choice")
		var pick: int = 0
		# --summit=continue：登顶菜单选"推下去"（压力测试：最大的石头从山顶滚下来）
		if opt_summit_continue:
			var cs: Array = (screen as ChoiceScreen).choices
			for i: int in cs.size():
				if str((cs[i] as Dictionary).get("kind", "")) == "continue":
					pick = i
		(screen as ChoiceScreen).chosen.emit(pick)
		return
	if screen is BloodlineScreen:
		if _phase_t > 1.0:
			_shot(tag + "bloodline")
			get_tree().quit()
		return
	if screen is RunSetupScreen:
		_shot(tag + "setup")
		(screen as RunSetupScreen).start_pressed.emit("basic", {}, "")
		return
	if sim.modal != null:
		var dlg: DialogPanel = main.get("_modal_ui") as DialogPanel
		if dlg != null:
			if dlg._t > 0.8:
				_shot(tag + "dialog")
				dlg._finish(0)
			return
		var fsw: AltarShow = main.get("_modal_ui") as AltarShow
		if fsw != null:
			# 祭坛演出要按确认才结束（AltarShow.READY 之后才收）
			if fsw._t > AltarShow.READY + 0.3:
				_shot(tag + "altar")
				fsw.confirm()
			return
		var pp: PickPanel = main.get("_modal_ui") as PickPanel
		if pp != null and pp._open_t >= 0.0:
			_shot(tag + "pick")
			if pp._t - pp._open_t > 0.6:
				pp.chosen.emit(0)
		return
	# 命令里有 night 之类会切阶段的：控制台开着时模拟是暂停的，别的阶段也要把它关掉
	if sim.phase != &"day" and not console_cmds.is_empty() and not _console_done and (main.get("_console") as DebugConsole).is_open:
		_drive_console()
		return
	match sim.phase:
		&"day":
			_f += 1
			if not console_cmds.is_empty() and not _console_done and sim.day_t > 2.0:
				_drive_console()
				return
			if opt_autopush:
				pass
			elif opt_mouse:
				# 真的发鼠标点击（走完整的输入管线：GUI → _unhandled_input → 动作），检验 HUD 不吞点击
				if _f % 6 == 0:
					var btn: MouseButton = MOUSE_BUTTON_LEFT if sim.expect_key == &"L" else MOUSE_BUTTON_RIGHT
					for down: bool in [true, false]:
						var mb: InputEventMouseButton = InputEventMouseButton.new()
						mb.button_index = btn
						mb.pressed = down
						mb.position = get_viewport().get_visible_rect().size / 2.0
						Input.parse_input_event(mb)
			elif _f % 6 == 0 and not sim.stats.hold_push:
				var k: StringName = &"R" if sim.expect_key == &"R" else &"L"
				sim.key_down(k)
				sim.key_up(k)
			if sim.stats.hold_push:
				sim.keys[&"R"] = true
			if sim.day_t > 1.5:
				_shot(tag + "day_early")
			if sim.day_t > sim.stats.day_length * 0.5:
				_shot(tag + "day_noon")
			if sim.day_t > sim.stats.day_length * 0.92:
				_shot(tag + "day_late")
		&"dusk":
			if sim.dusk_t > 1.2:
				if not _taken.has(tag + "dusk"):
					print("[autopilot] 第 %d 天收工：纪录 %d 米，准确按键 %d 次，节奏 %s · 节点 %d 对象 %d 资源 %d 内存 %.0fMB 显存 %.0fMB" % [sim.day, int(sim.record), sim.good_presses, str(sim.rhythm),
						int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT)),
						int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
						Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
				_shot(tag + "dusk")
		&"night":
			if sim.night_t > 2.0:
				_shot(tag + "night_a")
			if sim.night_t > 8.0:
				_shot(tag + "night_b")
			if sim.gate_hit and sim.gate_end_t < 2.0:
				_shot(tag + "gate")


## 机器人策略：买最便宜的，买到买不起为止
func _buy_cheapest(sim: SimGame) -> void:
	while true:
		var best: NodeDef = null
		var bc: float = INF
		for nd: NodeDef in sim.content.nodes:
			var lv: int = int(sim.levels.get(String(nd.key), 0))
			if not Pricing.can_level(sim.content, nd, sim.levels, sim.stats):
				continue
			# 要连命运丝线一起算：用丝线标价的节点德拉克马价是 0，只比德拉克马会一直挑中它、买不成、死循环（2026-10-15 卡死在夜宴商店）
			if not Pricing.affordable(sim.content, nd, lv, sim.stats, sim.money, sim.moira):
				continue
			var c: float = Pricing.node_cost(sim.content, nd, lv, sim.stats)
			if c < bc:
				bc = c
				best = nd
		if best == null or not Pricing.buy(sim, best):
			break


## 夜宴：按 HUB_STEPS 走一遍截图（第一夜才截），再买东西、天亮
func _drive_hub(hub: HubView, sim: SimGame, dt: float, tag: String) -> void:
	if hub.get_instance_id() != _hub_id:
		_hub_id = hub.get_instance_id()
		_hub_t = 0.0
	_hub_t += dt
	var shoot: bool = sim.day - 1 == _day0
	var steps: int = HUB_STEPS.size() if shoot else 0
	var i: int = int(_hub_t / 1.1) - 1
	if i < 0:
		return
	if i < steps:
		var st: Dictionary = HUB_STEPS[i]
		var lt: float = _hub_t - float(i + 1) * 1.1
		if lt < dt * 1.5:
			if hub._panel != null:
				hub._close_panel()
			hub.teleport(float(st["x"]))
			if bool(st.get("act", false)):
				hub.interact()
		elif lt > 0.75:
			_shot(tag + String(st["shot"]))
		return
	if hub._panel != null:
		hub._close_panel()
	_buy_cheapest(sim)
	if sim.day > _day0 + days - 1:
		get_tree().quit()
		return
	hub.leave_now()


## --console：打开控制台，依次执行命令，截图后关掉
func _drive_console() -> void:
	var con: DebugConsole = main.get("_console") as DebugConsole
	if con == null:
		_console_done = true
		return
	if not con.is_open:
		con.open()
		for c: String in console_cmds:
			con.call("_submit", c)
		return
	_end_t += get_process_delta_time()
	if _end_t > 0.8:
		_shot("console")
	if _end_t > 1.4:
		_end_t = 0.0
		con.close()
		_console_done = true


## --perf：帧时用真实时钟（不受 fast 影响），GPU 时间用 RenderingServer 的计时查询（兼容渲染器也支持）
func _perf_step() -> void:
	var vp: RID = get_viewport().get_viewport_rid()
	var now: int = Time.get_ticks_usec()
	var gvp: SubViewport = main.get("game_vp") as SubViewport
	if _perf.is_empty():
		RenderingServer.viewport_set_measure_render_time(vp, true)
		if gvp != null:
			RenderingServer.viewport_set_measure_render_time(gvp.get_viewport_rid(), true)
		_perf = {"t0": now, "last": now, "n": 0, "sum": 0.0, "max": 0.0, "gpu": 0.0, "dc": 0.0, "boot": false}
		return
	var ms: float = (now - int(_perf["last"])) / 1000.0
	_perf["last"] = now
	_perf["n"] = int(_perf["n"]) + 1
	_perf["sum"] = float(_perf["sum"]) + ms
	_perf["max"] = maxf(float(_perf["max"]), ms)
	# 游戏画面在 GameViewport 子视口里单独渲染，两块加起来才是整帧的 GPU 时间（root = 主视口：HUD、界面、把子视口铺满窗口的那一下）
	var g_root: float = RenderingServer.viewport_get_measured_render_time_gpu(vp)
	_perf["gpu"] = float(_perf["gpu"]) + g_root + (RenderingServer.viewport_get_measured_render_time_gpu(gvp.get_viewport_rid()) if gvp != null else 0.0)
	_perf["gpu_root"] = float(_perf.get("gpu_root", 0.0)) + g_root
	_perf["dc"] = float(_perf["dc"]) + Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var sim: SimGame = main.get("sim")
	if not bool(_perf["boot"]) and main.get("_screen") is MenuScreen:
		_perf["boot"] = true
		print("[perf] 进主菜单：启动 %d 毫秒 · 内存 %.0fMB · 显存 %.0fMB（贴图 %.0fMB）" % [Time.get_ticks_msec(), OS.get_static_memory_usage() / 1048576.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0])
	if now - int(_perf["t0"]) < 2000000:
		return
	var n: int = maxi(1, int(_perf["n"]))
	var where: String = "%s d%d %s r=%.1f alt=%d" % [String(sim.phase), sim.day, "hub" if main.get("_hub") != null else "", sim.stone.r, int(sim.altitude())] if sim != null else "menu"
	print("[perf] %s · 帧 %.1f ms（最慢 %.0f）· GPU %.2f ms（主视口 %.2f）· 绘制 %d · 物件 %d · 显存 %.0fMB · 窗口 %s" % [where, float(_perf["sum"]) / n, float(_perf["max"]),
		float(_perf["gpu"]) / n, float(_perf.get("gpu_root", 0.0)) / n, int(float(_perf["dc"]) / n), sim.objs.size() if sim != null else 0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, str(get_window().size)])
	print("    ", Prof.report(n))
	Prof.reset()
	_perf["t0"] = now
	_perf["n"] = 0
	_perf["sum"] = 0.0
	_perf["max"] = 0.0
	_perf["gpu"] = 0.0
	_perf["gpu_root"] = 0.0
	_perf["dc"] = 0.0


## --perf-layers：每段 1.5 秒（前 0.3 秒不计），第一段什么都不藏当基准，之后每段藏一层；夜宴里另跑一轮夜宴的层
func _layers_step() -> void:
	var vp: RID = get_viewport().get_viewport_rid()
	var gvp2: SubViewport = main.get("game_vp") as SubViewport
	if _lay.is_empty():
		RenderingServer.viewport_set_measure_render_time(vp, true)
		if gvp2 != null:
			RenderingServer.viewport_set_measure_render_time(gvp2.get_viewport_rid(), true)
		_lay = {"set": "", "i": -1, "t": 0.0, "gpu": 0.0, "n": 0, "hidden": null, "base": 0.0, "done": {}}
	var sim: SimGame = main.get("sim")
	var hub: Node = main.get("_hub")
	var want: String = ""
	if hub != null and main.get("_screen") == null:
		want = "hub"
	elif sim != null and sim.phase == &"day" and sim.day_t > 6.0 and main.get("_screen") == null and main.get("_dawn") == null:
		want = "day"
	elif sim != null and sim.phase == &"night" and sim.night_t > 1.0:
		want = "night"
	if want == "" or (_lay["done"] as Dictionary).has(want):
		return
	var paths: Array = []
	if want == "hub":
		for c: Node in hub.get_children():
			paths.append(hub.get_path_to(c))
		paths.append("Main/*lights")
	else:
		paths = ["GameViewport/BG", "GameViewport/World/BackRidge", "GameViewport/World/NearMist", "GameViewport/World/SlopeBack", "GameViewport/World/Terrain",
			"GameViewport/World/TownFar", "GameViewport/World/TownNear", "GameViewport/World/Foreground", "GameViewport/FX", "HUD", "GameViewport/World/*self"]
	if _lay["set"] != want:
		_lay["set"] = want
		_lay["i"] = -1
		_lay["t"] = 0.0
		_lay["gpu"] = 0.0
		_lay["n"] = 0
	var root: Node = hub if want == "hub" else main
	_lay["t"] = float(_lay["t"]) + get_process_delta_time() / maxf(0.01, fast)
	if float(_lay["t"]) > 0.3:
		_lay["gpu"] = float(_lay["gpu"]) + RenderingServer.viewport_get_measured_render_time_gpu(vp) 			+ (RenderingServer.viewport_get_measured_render_time_gpu(gvp2.get_viewport_rid()) if gvp2 != null else 0.0)
		_lay["n"] = int(_lay["n"]) + 1
	if float(_lay["t"]) < 1.5:
		return
	var avg: float = float(_lay["gpu"]) / maxi(1, int(_lay["n"]))
	var i: int = int(_lay["i"])
	if i < 0:
		_lay["base"] = avg
		print("[layers] %s 基准 GPU %.2f ms（%s）" % [want, avg, str(get_window().size)])
	else:
		print("[layers] %s 藏掉 %-22s GPU %.2f ms（省 %.2f）" % [want, str(paths[i]), avg, float(_lay["base"]) - avg])
	# 复原上一层
	_layer_vis(root, paths, i, true)
	i += 1
	_lay["i"] = i
	_lay["t"] = 0.0
	_lay["gpu"] = 0.0
	_lay["n"] = 0
	if i >= paths.size():
		(_lay["done"] as Dictionary)[want] = true
		return
	_layer_vis(root, paths, i, false)


func _layer_vis(root: Node, paths: Array, i: int, on: bool) -> void:
	if i < 0 or i >= paths.size():
		return
	var p: String = str(paths[i])
	if p.ends_with("*lights"):
		for n: Node in root.find_children("*", "PointLight2D", true, false):
			(n as PointLight2D).enabled = on
		return
	if p.ends_with("*self"):
		var w: CanvasItem = root.get_node(p.get_base_dir()) as CanvasItem
		w.self_modulate.a = 1.0 if on else 0.0
		return
	var n2: Node = root.get_node_or_null(p)
	if n2 is CanvasItem:
		(n2 as CanvasItem).visible = on
	elif n2 is CanvasLayer:
		(n2 as CanvasLayer).visible = on
