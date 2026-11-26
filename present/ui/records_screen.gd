class_name RecordsScreen
extends Control
## 记录（布局在 records_screen.tscn，陶瓶风格）：本代统计 / 所有代合计 / 成就三页。主菜单「记录」和暂停菜单「统计」都开它。
## 只读：本代 = run_stats（进行中的一代；没有就空着），所有代 = meta.life（一代结束时并进去，这里再加上进行中的一代），
## 成就 = meta.ach + 本代 run_stats.ach。Q / E 翻页，Esc 返回。

signal back_pressed

const SCENE: String = "res://present/ui/records_screen.tscn"
const PAGES: PackedStringArray = ["Run", "Life", "Ach"]
const INK: Color = Color(0.0705882, 0.0470588, 0.0392157, 1)
const MUTED: Color = Color(0.0705882, 0.0470588, 0.0392157, 0.55)

var content: ContentDB = null
var meta: Dictionary = {}
## 进行中的一代：{run, run_stats, day, record, gen}；空 = 没有
var cur: Dictionary = {}
var _page: int = 0
var _t: float = 0.0


static func create() -> RecordsScreen:
	return SceneCache.make(SCENE) as RecordsScreen


## 从一局模拟取进行中的一代
static func cur_of(g: SimGame) -> Dictionary:
	return {"run_stats": g.run_stats, "day": g.day, "record": g.record, "gen": int(g.run.get("gen", 1))}


func _ready() -> void:
	var group: ButtonGroup = ButtonGroup.new()
	for i: int in PAGES.size():
		var tab: Button = get_node("%Tab" + PAGES[i]) as Button
		tab.button_group = group
		var idx: int = i
		tab.pressed.connect(func() -> void: _show_page(idx))
	(%Back as Button).pressed.connect(func() -> void: if _t > 0.2: back_pressed.emit())
	_fill_run()
	_fill_life()
	_fill_ach()
	_show_page(0 if not cur.is_empty() else 1)


func _show_page(i: int) -> void:
	_page = clampi(i, 0, PAGES.size() - 1)
	for k: int in PAGES.size():
		(get_node("%Page" + PAGES[k]) as Control).visible = k == _page
		(get_node("%Tab" + PAGES[k]) as Button).set_pressed_no_signal(k == _page)
	(get_node("%Tab" + PAGES[_page]) as Button).call_deferred("grab_focus")


static func _time(sec: float) -> String:
	var m: int = int(sec / 60.0)
	return Loc.t("records_screen.hr_min", "%d 小时 %d 分") % [m / 60, m % 60] if m >= 60 else Loc.t("records_screen.min", "%d 分钟") % m


func _row(grid: GridContainer, name: String, value: String) -> void:
	var a: Label = Label.new()
	a.text = name
	a.add_theme_font_size_override("font_size", 20)
	a.add_theme_color_override("font_color", MUTED)
	a.custom_minimum_size.x = 280
	grid.add_child(a)
	var b: Label = Label.new()
	b.text = value
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_font_override("font", Fonts.serif(700))
	b.add_theme_color_override("font_color", INK)
	grid.add_child(b)


func _stat_rows(grid: GridContainer, rs: Dictionary) -> void:
	_row(grid, Loc.t("records_screen.time_played", "用时"), _time(float(rs.get("time_s", 0.0))))
	_row(grid, Loc.t("records_screen.best_night", "最好的一夜"), NumFmt.fmt(float(rs.get("best_night", 0.0))) + Loc.t("records_screen.drachmas", " 德拉克马"))
	_row(grid, Loc.t("records_screen.largest_stone", "最大的石头"), Loc.t("records_screen.m_diameter", "直径 %s m") % Js.to_fixed(float(rs.get("max_r", 0.0)) * 2.0, 1))
	_row(grid, Loc.t("records_screen.crushed", "碾碎"), Loc.t("records_screen.total_houses_creatures_chickens", "%s 件（房子 %s · 活物 %s · 鸡 %s）") % [NumFmt.fmt(float(rs.get("crushed", 0))), NumFmt.fmt(float(rs.get("buildings", 0))),
		NumFmt.fmt(float(rs.get("living", 0))), NumFmt.fmt(float(rs.get("chickens", 0)))])
	_row(grid, Loc.t("records_screen.total_crush_value", "碾压总价值"), NumFmt.fmt(float(rs.get("crush_total", 0.0))))
	_row(grid, Loc.t("records_screen.pushing", "推石"), Loc.t("records_screen.pushes_collapses", "%s 下 · 累倒 %d 次") % [NumFmt.fmt(float(rs.get("pushes", 0))), int(rs.get("faints", 0))])
	_row(grid, Loc.t("records_screen.underworld_gate", "冥府之门"), Loc.t("records_screen.most_seals_broken_one", "最多一夜破封 %d 重") % int(rs.get("max_seals", 0)))
	_row(grid, Loc.t("records_screen.fate_urn", "命运宝瓶"), Loc.t("records_screen.opened_fates_nod_fate", "开了 %d 只 · 三女神点头 %d 次 · 摇到命运 %s") % [int(rs.get("jars", 0)), int(rs.get("jackpots", 0)), NumFmt.fmt(float(rs.get("moira_total", 0.0)))])
	_row(grid, Loc.t("records_screen.tyche_s_bets", "提喀的盘口"), Loc.t("records_screen.bets_wins_best_odds", "押了 %d 注 · 中 %d 注 · 最高赔率 %s") % [int(rs.get("bets", 0)), int(rs.get("bets_won", 0)), Js.to_fixed(float(rs.get("bet_best_odds", 0.0)), 2)])


func _fill_run() -> void:
	var grid: GridContainer = %RunGrid
	if cur.is_empty():
		_row(grid, Loc.t("records_screen.no_generation_progress", "现在没有进行中的一代"), "")
		return
	var rs: Dictionary = cur.get("run_stats", {})
	_row(grid, Loc.t("records_screen.generation", "这一代"), Loc.t("records_screen.generation_day", "第 %d 代 · 第 %d 天") % [int(cur.get("gen", 1)), int(cur.get("day", 1))])
	var sd: int = int(rs.get("summit_day", 0))
	_row(grid, Loc.t("records_screen.highest_altitude", "最高海拔"), (Loc.t("records_screen.summit_day", "登顶（第 %d 天）") % sd) if sd > 0 else "%d m" % int(float(cur.get("record", 0.0))))
	_row(grid, Loc.t("records_screen.altars_lit", "点亮的祭坛"), "%d / %d" % [int(rs.get("altars", 0)), content.altars.size()])
	_stat_rows(grid, rs)


func _fill_life() -> void:
	var grid: GridContainer = %LifeGrid
	var life: Dictionary = (meta.get("life", {}) as Dictionary).duplicate()
	var runs: int = int(life.get("runs", 0))
	# 进行中的一代也算进来
	if not cur.is_empty():
		var rs: Dictionary = cur.get("run_stats", {})
		MetaLogic.merge_life(life, rs, int(cur.get("day", 1)), int(rs.get("summit_day", 0)) > 0)
	_row(grid, Loc.t("records_screen.generations", "代数"), Loc.t("records_screen.completed", "%d 代（结束了 %d 代）") % [maxi(int(meta.get("gen", 1)), runs + (1 if not cur.is_empty() else 0)), runs])
	_row(grid, Loc.t("records_screen.summits", "登顶"), Loc.t("records_screen.fastest_day", "%d 次 · 最快第 %d 天") % [int(life.get("summits", 0)), int(meta.get("best_day", 0))] if int(meta.get("best_day", 0)) > 0 else Loc.t("records_screen.summit_count", "%d 次") % int(life.get("summits", 0)))
	_row(grid, Loc.t("records_screen.days_pushed", "推了多少天"), Loc.t("records_screen.day_count", "%d 天") % int(life.get("days", 0)))
	_stat_rows(grid, life)


func _fill_ach() -> void:
	var grid: GridContainer = %AchGrid
	var have: Dictionary = (meta.get("ach", {}) as Dictionary).duplicate()
	if not cur.is_empty():
		for id: Variant in (cur.get("run_stats", {}) as Dictionary).get("ach", []):
			if not have.has(str(id)):
				have[str(id)] = {"gen": int(cur.get("gen", 1)), "day": 0}
	var n: int = 0
	for a: Dictionary in content.achievements:
		var id: String = str(a["id"])
		var on: bool = have.has(id)
		if on:
			n += 1
		var box: PanelContainer = PanelContainer.new()
		box.custom_minimum_size = Vector2(300, 92)
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(INK, 0.9) if on else Color(INK, 0.06)
		sb.set_border_width_all(2)
		sb.border_color = Color(INK, 0.9 if on else 0.3)
		sb.set_content_margin_all(10)
		sb.set_corner_radius_all(3)
		box.add_theme_stylebox_override("panel", sb)
		var v: VBoxContainer = VBoxContainer.new()
		var nm: Label = Label.new()
		nm.text = str(a["name"])
		nm.add_theme_font_override("font", Fonts.serif(800))
		nm.add_theme_font_size_override("font_size", 20)
		nm.add_theme_color_override("font_color", Color("e8c56a") if on else MUTED)
		v.add_child(nm)
		var ds: Label = Label.new()
		ds.text = str(a["desc"])
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds.custom_minimum_size.x = 270
		ds.add_theme_font_size_override("font_size", 15)
		ds.add_theme_color_override("font_color", Color("eadbb8", 0.85) if on else MUTED)
		v.add_child(ds)
		box.add_child(v)
		grid.add_child(box)
	(%Note as Label).text = Loc.t("records_screen.achievements", "成就 %d / %d") % [n, content.achievements.size()]


func _process(dt: float) -> void:
	_t += dt


func _unhandled_input(ev: InputEvent) -> void:
	var k: InputEventKey = ev as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _t > 0.2:
			back_pressed.emit()
	elif k.keycode == KEY_Q or k.keycode == KEY_PAGEUP:
		get_viewport().set_input_as_handled()
		_show_page((_page - 1 + PAGES.size()) % PAGES.size())
	elif k.keycode == KEY_E or k.keycode == KEY_PAGEDOWN:
		get_viewport().set_input_as_handled()
		_show_page((_page + 1) % PAGES.size())
