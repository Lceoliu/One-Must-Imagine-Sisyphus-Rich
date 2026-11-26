class_name BoonView
extends RefCounted
## 神的画面：山坡上的赐福祭坛、各位神的机制画面（按 rules/modules.json 的 view 加载 SchoolView）、
## 左下角已点亮祭坛的神像排、夜里的机制计数行。只读 sim（g.boons.view_states() 等）。

var _views: Dictionary = {}
var _t: float = 0.0


func setup(content: ContentDB) -> void:
	_views.clear()
	for m: Dictionary in content.modules:
		var path: String = str(m.get("view", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var scr: Script = load(path)
		var v: SchoolView = scr.new() as SchoolView
		if v != null:
			_views[StringName(str(m.get("id", "")))] = v


func tick(dt: float) -> void:
	_t += dt


# ———————————————— 世界：染色层 ————————————————
func draw_world(c: CanvasItem, wv: WorldView, sim: SimGame, vr: Vector2) -> void:
	if sim.demo or sim.world == null:
		return
	_draw_altars(c, sim, vr)
	var vs: Dictionary = sim.boons.view_states()
	for id: StringName in vs:
		var v: SchoolView = _views.get(id)
		if v != null:
			v.world(c, wv, sim, vs[id], vr)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_altars(c: CanvasItem, sim: SimGame, vr: Vector2) -> void:
	var w: World = sim.world
	for i: int in sim.boons.altar_count():
		var alt: float = sim.boons.altar_alt(i)
		if alt >= World.SUMMIT - 2.0:
			continue
		var s: float = w.s_at_alt(alt)
		w.at(s)
		var x: float = w.ax
		if x < vr.x - 6.0 or x > vr.y + 6.0:
			continue
		var done: bool = sim.boons.done.has(i)
		# 按坡度摆（WorldView.ground_fit：底边贴坡，不悬空）
		WorldView.spr_ground(c, w, &"altar_boon", x, 4.2, 0.55 if done else 1.0)


# ———————————————— 世界：金色层 ————————————————
func draw_gold(c: CanvasItem, wv: WorldView, sim: SimGame, vr: Vector2) -> void:
	if sim.demo or sim.world == null:
		return
	_draw_altar_glow(c, sim, vr)
	var vs: Dictionary = sim.boons.view_states()
	for id: StringName in vs:
		var v: SchoolView = _views.get(id)
		if v != null:
			v.gold(c, wv, sim, vs[id], vr)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 没点亮的祭坛：顶上一团呼吸的金光；点亮的：顶上一枚这座祭坛的神的圆章
func _draw_altar_glow(c: CanvasItem, sim: SimGame, vr: Vector2) -> void:
	var w: World = sim.world
	for i: int in sim.boons.altar_count():
		var alt: float = sim.boons.altar_alt(i)
		if alt >= World.SUMMIT - 2.0:
			continue
		var s: float = w.s_at_alt(alt)
		w.at(s)
		var x: float = w.ax
		if x < vr.x - 6.0 or x > vr.y + 6.0:
			continue
		var top: float = w.y_at_x(x) + 4.4
		var done: bool = sim.boons.done.has(i)
		if not done:
			var a: float = 0.22 + 0.12 * sin(_t * 2.4 + i)
			Glow.draw(c, WorldView.p(x, top), 2.2 * WorldView.PPM, Color(SchoolView.GOLD, a))
			continue
		var tex: Texture2D = SpriteDB.tex(StringName("god_" + String(sim.boons.altar(i)["god"])))
		if tex == null:
			continue
		var r: float = 0.7 * WorldView.PPM
		var ctr: Vector2 = WorldView.p(x, top + 0.9 + sin(_t * 1.6 + i) * 0.08)
		c.draw_circle(ctr, r * 1.08, SchoolView.INK)
		c.draw_texture_rect(tex, Rect2(ctr - Vector2(r, r), Vector2(r, r) * 2.0), false)
		c.draw_arc(ctr, r * 1.08, 0.0, TAU, 32, SchoolView.GOLD_HI, maxf(2.0, r * 0.08), true)


# ———————————————— HUD ————————————————
func draw_hud(h: HudView, sim: SimGame, vp: Vector2) -> void:
	if sim.demo or sim.world == null:
		return
	var vs: Dictionary = sim.boons.view_states()
	for id: StringName in vs:
		var v: SchoolView = _views.get(id)
		if v != null:
			v.hud(h, sim, vs[id], vp)
	# 流派计数行（连碾月桂下方；位置跟 hud.tscn 的 SchoolLines 槽位）
	if sim.phase == &"night" and h.begin_slot(&"SchoolLines"):
		var y: float = HudView.FR + 8.0 + 62.0 + 70.0 + 84.0
		for id: StringName in vs:
			var line: String = str((vs[id] as Dictionary).get("hud", ""))
			if line == "":
				continue
			var gold_line: bool = bool((vs[id] as Dictionary).get("gold", true))
			h.text_at(line, Vector2(vp.x / 2.0, y), 15, SchoolView.GOLD_HI if gold_line else SchoolView.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
			y += 22.0
	h.end_slot()
	if h.begin_slot(&"BoonRow"):
		_draw_row(h, sim, vp)
	h.end_slot()


## 左下角：已点亮的祭坛，按点亮顺序每座一枚神像圆章
func _draw_row(h: HudView, sim: SimGame, vp: Vector2) -> void:
	var bo: BoonSystem = sim.boons
	if bo.done.is_empty():
		return
	var x: float = HudView.FR + 30.0
	var y: float = vp.y - HudView.FR - 96.0
	for i: int in bo.done:
		_medal(h, StringName("god_" + String(bo.altar(i)["god"])), Vector2(x, y), 16.0, SchoolView.GOLD_HI, 2.0)
		x += 38.0


func _medal(h: HudView, key: StringName, ctr: Vector2, r: float, ring: Color, wd: float) -> void:
	h.draw_circle(ctr, r, SchoolView.INK)
	var tex: Texture2D = SpriteDB.tex(key)
	if tex != null:
		h.draw_texture_rect(tex, Rect2(ctr - Vector2(r, r) * 0.9, Vector2(r, r) * 1.8), false)
	h.draw_arc(ctr, r, 0.0, TAU, 28, ring, wd, true)
