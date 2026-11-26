class_name DebugCommands
extends RefCounted
## 调试控制台的命令（app 层，可以直接改 sim 的状态）。run(行) → 输出文本；不认识的命令给提示。
## 控制台界面在 debug_console.gd；这里不碰节点，方便测试。

var sim: SimGame = null
var runner: SimRunner = null
## main（可选）：hub / save 之类要调 main 的流程
var main: Node = null

## 命令 → [用法, 说明]（按当前语言现取）
static func help_table() -> Dictionary:
	return {
	"help": [Loc.t("debug_commands.help_command", "help [命令]"), Loc.t("debug_commands.list_commands_or_show", "列出命令，或看某个命令的用法")],
	"clear": ["clear", Loc.t("debug_commands.clear_console", "清屏")],
	"info": ["info", Loc.t("debug_commands.show_day_phase_money", "当前状态：日期、阶段、钱、纪录、石头、赐福")],
	"money": ["money <n> | money +n | money -n", Loc.t("debug_commands.set_add_or_subtract", "设钱 / 加钱 / 扣钱")],
	"day": ["day <n>", Loc.t("debug_commands.set_day_number_next", "改天数（从下一次开工起生效）")],
	"record": [Loc.t("debug_commands.record_metres", "record <米>"), Loc.t("debug_commands.set_height_record", "改最高纪录")],
	"alt": [Loc.t("debug_commands.alt_metres", "alt <米>"), Loc.t("debug_commands.move_stone_height_during", "白天：把石头直接挪到这个海拔")],
	"speed": [Loc.t("debug_commands.speed_multiplier", "speed <倍数>"), Loc.t("debug_commands.set_simulation_speed_1", "模拟加速（1 = 正常，最高 20）")],
	"autopush": ["autopush [on|off]", Loc.t("debug_commands.toggle_auto_push", "自动推石开关（和设置里的是同一个）")],
	"stamina": ["stamina", Loc.t("debug_commands.refill_stamina_recover_from", "体力回满、解除累倒")],
	"night": ["night", Loc.t("debug_commands.clock_out_now_go", "白天立刻收工（进黄昏）")],
	"hub": ["hub", Loc.t("debug_commands.skip_rest_day_go", "直接进夜宴（跳过当天剩下的部分）")],
	"node": [Loc.t("debug_commands.node_key_all_list", "node <key|all|list> [级]"), Loc.t("debug_commands.set_upgrade_level_use", "设天赋等级；all = 全部点满；list = 列出所有 key")],
	"altar": [Loc.t("debug_commands.altar_index_list", "altar <下标|list>"), Loc.t("debug_commands.light_altar_or_use", "直接点亮一座赐福祭坛；list = 列出全部")],
	"flag": [Loc.t("debug_commands.flag_name_value", "flag [名字] [值]"), Loc.t("debug_commands.read_or_set_story", "看 / 改剧情 flag（值：true、false、数字或文字）")],
	"save": ["save", Loc.t("debug_commands.save_now", "立刻存档")],
	"fps": ["fps", Loc.t("debug_commands.toggle_frame_rate_status", "开关左上角的帧率 / 状态显示")],
}

## fps 叠加层开关（控制台读）
var show_fps: bool = false


func names() -> PackedStringArray:
	return PackedStringArray(help_table().keys())


func run(line: String) -> String:
	var parts: PackedStringArray = line.strip_edges().split(" ", false)
	if parts.is_empty():
		return ""
	var cmd: String = parts[0].to_lower()
	var args: PackedStringArray = parts.slice(1)
	if not help_table().has(cmd):
		return Loc.t("debug_commands.unknown_command_type_help", "没有这个命令：%s（help 看全部）") % cmd
	if sim == null and cmd not in ["help", "clear", "speed", "autopush", "fps"]:
		return Loc.t("debug_commands.no_run_progress", "现在没有进行中的一局")
	match cmd:
		"help":
			return _help(args)
		"clear":
			return ""
		"info":
			return _info()
		"money":
			return _money(args)
		"day":
			if args.is_empty() or not args[0].is_valid_int():
				return _usage(cmd)
			sim.day = maxi(1, int(args[0]))
			return Loc.t("debug_commands.day", "天数 = %d") % sim.day
		"record":
			if args.is_empty() or not args[0].is_valid_float():
				return _usage(cmd)
			sim.record = maxf(0.0, float(args[0]))
			return Loc.t("debug_commands.record_m", "纪录 = %d 米") % int(sim.record)
		"alt":
			return _alt(args)
		"speed":
			if args.is_empty() or not args[0].is_valid_float() or runner == null:
				return _usage(cmd)
			runner.dev_speed = clampf(float(args[0]), 0.1, 20.0)
			return Loc.t("debug_commands.simulation_speed", "模拟速度 ×%s") % str(runner.dev_speed)
		"autopush":
			if not args.is_empty():
				Settings.auto_push = args[0] in ["on", "1", "true", "开"]  # i18n: skip（玩家输入，中文的“开”也认）
			else:
				Settings.auto_push = not Settings.auto_push
			Settings.save_to_disk()
			return Loc.t("debug_commands.auto_push", "自动推石：%s") % (Loc.t("debug_commands.on", "开") if Settings.auto_push else Loc.t("debug_commands.off", "关"))
		"stamina":
			sim.stamina = sim.stats.stamina_max
			sim.exhausted = 0
			return Loc.t("debug_commands.stamina_full", "体力已回满")
		"night":
			if sim.phase != &"day":
				return Loc.t("debug_commands.can_only_clock_out", "只有白天能收工（现在是 %s）") % String(sim.phase)
			sim.start_dusk()
			return Loc.t("debug_commands.clocked_out_dusk_begins", "收工，进黄昏")
		"hub":
			if main == null or not main.has_method("_show_hub"):
				return Loc.t("debug_commands.can_t_enter_feast", "这里进不了夜宴")
			main.call("_show_hub")
			return Loc.t("debug_commands.feast_next_shift_starts", "进夜宴（天亮后从第 %d 天开工）") % sim.day
		"node":
			return _node(args)
		"altar":
			return _altar(args)
		"flag":
			return _flag(args)
		"save":
			if main != null and main.has_method("_save"):
				main.call("_save")
				return Loc.t("debug_commands.saved", "已存档")
			return Loc.t("debug_commands.save_service_unavailable", "没有存档服务")
		"fps":
			show_fps = not show_fps
			return Loc.t("debug_commands.status_display", "状态显示：%s") % (Loc.t("debug_commands.on", "开") if show_fps else Loc.t("debug_commands.off", "关"))
	return ""


func _usage(cmd: String) -> String:
	return Loc.t("debug_commands.usage", "用法：%s") % str((help_table()[cmd] as Array)[0])


func _help(args: PackedStringArray) -> String:
	if not args.is_empty() and help_table().has(args[0]):
		var h: Array = help_table()[args[0]]
		return "%s —— %s" % [str(h[0]), str(h[1])]
	var out: PackedStringArray = []
	var table: Dictionary = help_table()
	for k: Variant in table:
		var h: Array = table[k]
		out.append("%-34s %s" % [str(h[0]), str(h[1])])
	return "\n".join(out)


func _info() -> String:
	var b: Boulder = sim.stone
	var alt: float = sim.world.alt_at(b.ts) if sim.world != null else 0.0
	var lit: PackedStringArray = []
	for i: int in sim.boons.done:
		lit.append(String(sim.boons.altar(i)["name"]))
	return Loc.t("debug_commands.day_money_best_m", "第 %d 天 · 阶段 %s · 钱 %s · 纪录 %d 米 · 石头海拔 %d 米 半径 %.2f 米 · 体力 %d/%d\n祭坛：%s\n天赋：%d 级（%d 个节点）") % [
		sim.day, String(sim.phase), NumFmt.fmt(sim.money), int(sim.record), int(alt), b.r, int(sim.stamina), int(sim.stats.stamina_max),
		Loc.t("debug_commands.list_sep", "、").join(lit) if not lit.is_empty() else Loc.t("debug_commands.none", "（无）"),
		_levels_total(), sim.levels.size()]


func _levels_total() -> int:
	var n: int = 0
	for k: Variant in sim.levels:
		n += int(sim.levels[k])
	return n


func _money(args: PackedStringArray) -> String:
	if args.is_empty():
		return _usage("money")
	var s: String = args[0]
	var rel: bool = s.begins_with("+") or s.begins_with("-")
	var v: String = s.trim_prefix("+")
	if not v.is_valid_float():
		return _usage("money")
	sim.money = maxf(0.0, (sim.money if rel else 0.0) + float(v))
	return Loc.t("debug_commands.money", "钱 = %s") % NumFmt.fmt(sim.money)


func _alt(args: PackedStringArray) -> String:
	if args.is_empty() or not args[0].is_valid_float():
		return _usage("alt")
	if sim.phase != &"day":
		return Loc.t("debug_commands.can_only_move_stone", "只有白天能挪石头")
	var h: float = clampf(float(args[0]), 0.0, sim.content.tuning.summit - 1.0)
	sim.stone.ts = clampf(sim.world.s_at_alt(h), sim.world.s_foot + 1.0, sim.world.s_summit - 0.5)
	return Loc.t("debug_commands.stone_moved_m", "石头挪到 %d 米") % int(h)


func _node(args: PackedStringArray) -> String:
	if args.is_empty():
		return _usage("node")
	if args[0] == "list":
		var keys: PackedStringArray = []
		for n: NodeDef in sim.content.nodes:
			keys.append("%s(%s)" % [String(n.key), n.name])
		return " ".join(keys)
	if args[0] == "all":
		for n: NodeDef in sim.content.nodes:
			sim.levels[String(n.key)] = n.max_lv
		sim.recompute_stats()
		return Loc.t("debug_commands.maxed_all_upgrades", "全部天赋点满（%d 个）") % sim.content.nodes.size()
	var nd: NodeDef = null
	for n: NodeDef in sim.content.nodes:
		if String(n.key) == args[0]:
			nd = n
	if nd == null:
		return Loc.t("debug_commands.unknown_upgrade_type_node", "没有这个天赋：%s（node list 看全部）") % args[0]
	var lv: int = nd.max_lv if args.size() < 2 or not args[1].is_valid_int() else clampi(int(args[1]), 0, nd.max_lv)
	if lv == 0:
		sim.levels.erase(String(nd.key))
	else:
		sim.levels[String(nd.key)] = lv
	sim.recompute_stats()
	return Loc.t("debug_commands.level", "%s = %d 级") % [nd.name, lv]


func _altar(args: PackedStringArray) -> String:
	if args.is_empty():
		return _usage("altar")
	var bo: BoonSystem = sim.boons
	if args[0] == "list":
		var out: PackedStringArray = []
		for i: int in bo.altar_count():
			var a: Dictionary = bo.altar(i)
			out.append(Loc.t("debug_commands.altar_row", "%d：%d m %s「%s」%s") % [i, int(bo.altar_alt(i)), String(a["god"]), String(a["name"]), Loc.t("debug_commands.lit", "（已点亮）") if bo.done.has(i) else ""])
		return "
".join(out)
	if not args[0].is_valid_int() or int(args[0]) < 0 or int(args[0]) >= bo.altar_count():
		return Loc.t("debug_commands.unknown_altar_type_altar", "没有这座祭坛：%s（altar list 看全部）") % args[0]
	var i: int = int(args[0])
	if bo.done.has(i):
		return Loc.t("debug_commands.altar_already_lit", "第 %d 座祭坛已经点亮了") % i
	bo.pending.append(i)
	bo.try_open()
	return Loc.t("debug_commands.lit_altar_scene_plays", "点亮祭坛 %d「%s」（白天、没有别的弹窗时演出）") % [i, String(bo.altar(i)["name"])]


func _flag(args: PackedStringArray) -> String:
	var flags: Dictionary = sim.story.flags
	if args.is_empty():
		var out: PackedStringArray = []
		for k: Variant in flags:
			out.append("%s = %s" % [str(k), str(flags[k])])
		return "\n".join(out) if not out.is_empty() else Loc.t("debug_commands.no_flags", "（没有 flag）")
	var key: String = args[0]
	if args.size() < 2:
		return "%s = %s" % [key, str(flags.get(key, Loc.t("debug_commands.not_set", "（未设置）")))]
	var raw: String = " ".join(args.slice(1))
	var v: Variant = raw
	if raw == "true" or raw == "false":
		v = raw == "true"
	elif raw.is_valid_int():
		v = int(raw)
	elif raw.is_valid_float():
		v = float(raw)
	flags[key] = v
	return "%s = %s" % [key, str(v)]
