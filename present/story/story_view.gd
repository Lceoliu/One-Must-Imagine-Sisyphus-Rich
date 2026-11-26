class_name StoryView
extends RefCounted
## 剧情的画面（= 网页 story.js drawWorld / drawHUD）：世界里的 NPC（奥托吕科斯的摊子、777m 崖上的普罗米修斯与秃鹫、塔纳托斯），
## 40 米内的名字标签、屏外 NPC 提示、底部旁白一行。只读 sim。

const PRO_K: float = 2.4
const THA_K: float = 1.5
const CREAM: Color = Color("f1e3c8")
const LINE: Color = Color("e9d3a8")
const INK: Color = Color("120c0a")
const GOLD: Color = Color("f0b93a")
const GOLD_HI: Color = Color("ffe08a")

## 本帧要画的名字标签（世界坐标）：[{x, y, name, sub}]，draw_world 写、draw_hud 读
var _tags: Array[Dictionary] = []
## 本帧可见的先祖石碑：[{x, y（碑顶）, line, text}]
var _steles: Array[Dictionary] = []
var _t: float = 0.0


func tick(dt: float) -> void:
	_t += dt


func _speaker(sim: SimGame, id: String) -> Dictionary:
	return sim.story.speaker(id)


# ———————————————— 世界（染色层）————————————————
func draw_world(c: CanvasItem, _wv: WorldView, sim: SimGame, vr: Vector2) -> void:
	_tags.clear()
	if sim.demo or sim.world == null:
		return
	var st: StorySystem = sim.story
	var w: World = sim.world
	var day: bool = sim.phase == &"day" or sim.phase == &"dusk" or sim.phase == &"victory_wait"
	var lst: Array[Dictionary] = st.npcs.duplicate()
	# 普罗米修斯的崖壁是地标：处理完之后（或夜里）也一直画着
	if st._npc(&"prometheus").is_empty():
		lst.append({"id": &"prometheus", "alt": st.cst("PROMETHEUS_ALT"), "s": w.s_at_alt(st.cst("PROMETHEUS_ALT")), "done": true})
	for n: Dictionary in lst:
		var id: StringName = n["id"]
		if id != &"prometheus" and (not day or bool(n["done"])):
			continue
		w.at(float(n["s"]))
		var x: float = w.ax
		if x < vr.x - 30.0 or x > vr.y + 30.0:
			continue
		var tag: Vector2 = Vector2.ZERO
		match id:
			&"merchant":
				tag = _merchant(c, w, x)
			&"prometheus":
				tag = _prometheus(c, w, x, String(st.flags["prometheus"]))
			&"thanatos":
				tag = _thanatos(c, w, x)
		if day and not bool(n["done"]) and absf(float(n["s"]) - sim.stone.s) < 40.0:
			var spk: Dictionary = _speaker(sim, "autolycus" if id == &"merchant" else String(id))
			var sub: String = ""
			match id:
				&"merchant":
					sub = Loc.t("story_view.chain_drachmas", "锁链 · %s 德拉克马") % NumFmt.fmt(st.cst("CHAIN_PRICE"))
				&"prometheus":
					sub = Loc.t("story_view.arrive_before_noon", "正午前到达") if sim.tod() < 0.5 else Loc.t("story_view.he_s_feeding_birds", "他在喂鸟……明天早点")
				_:
					sub = Loc.t("story_view.thanatos", "死神")
			_tags.append({"x": tag.x, "y": tag.y, "name": String(spk.get("name", "")), "sub": sub, "gy": w.y_at_x(tag.x)})
	_draw_steles(c, sim, vr)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 先祖石碑（meta.steles 最近 3 代）：碑身精灵；刻字在 HUD 层画（离镜头近时才显示）
func _draw_steles(c: CanvasItem, sim: SimGame, vr: Vector2) -> void:
	_steles.clear()
	var w: World = sim.world
	for m: Dictionary in sim.meta_rules.stele_marks():
		var s: float = w.s_at_alt(float(m["alt"]))
		w.at(s)
		var x: float = w.ax
		if x < vr.x - 6.0 or x > vr.y + 6.0:
			continue
		var key: StringName = &"stele_ancestor" if SpriteDB.has(&"stele_ancestor") else &"stele"
		WorldView.spr_ground(c, w, key, x, 3.4)
		_steles.append({"x": x, "y": w.ay - 0.15 + 3.4, "line": String(m["line"]), "text": String(m["text"])})


func _merchant(c: CanvasItem, w: World, x: float) -> Vector2:
	# 站在坡上的都按坡度摆（WorldView.spr_ground）
	if WorldView.spr_ground(c, w, &"npc_autolycus", x + 1.6, 3.4, 1.0, true):
		return Vector2(x + 1.6, w.y_at_x(x + 1.6) + 4.4)
	WorldView.spr_ground(c, w, &"olive_tree", x + 3.4, 4.4, 0.95)
	WorldView.spr_ground(c, w, &"market_stall", x + 1.8, 1.9, 1.0, true)
	WorldView.spr_ground(c, w, &"shepherd", x + 0.5, 1.85, 1.0, true)
	return Vector2(x + 0.8, w.y_at_x(x + 0.8) + 3.6)


func _prometheus(c: CanvasItem, w: World, x: float, state: String) -> Vector2:
	var K: float = PRO_K
	var fx: float = x + 1.0 * K
	if state != "freed":
		var ch: float = 3.0 * K
		# 站在坡上的都按坡度摆：倾角封顶、脚贴地（spr_ground upright）
		var cy0: float = w.y_at_x(fx)
		if WorldView.spr_ground(c, w, &"npc_prometheus_chained", fx, ch, 1.0, false, 0.0, true):
			var wd: float = ch * SpriteDB.aspect(&"npc_prometheus_chained")
			var vx: float = fx - wd * 0.2
			var vy: float = cy0 + ch * 0.93
			if not SchoolView.spr(c, &"npc_vulture_perch", vx, vy, 1.5 * K, 1.0, true):
				SchoolView.spr(c, &"eagle", vx, vy + sin(_t * 2.0) * 0.05 * K, 1.2 * K, 1.0, true)
			return Vector2(fx, cy0 + ch * 1.15)
		return Vector2(fx, w.y_at_x(fx) + 5.3 * K)
	var fh: float = 2.3 * K
	var wd2: float = fh * SpriteDB.aspect(&"npc_prometheus_free")
	var sy: float = w.y_at_x(fx)
	WorldView.spr_ground(c, w, &"npc_prometheus_free", fx, fh, 1.0, true, 0.0, true)
	return Vector2(fx, sy + fh * 1.12)


func _thanatos(c: CanvasItem, w: World, x: float) -> Vector2:
	var K: float = THA_K
	var bx: float = x + 0.9 * K
	var by: float = w.y_at_x(bx)
	var bob: float = (0.5 + 0.5 * sin(_t * 1.6)) * 0.08 * K
	if WorldView.spr_ground(c, w, &"npc_thanatos", bx, 3.0 * K, 1.0, true, bob, true):
		return Vector2(bx, by + 3.6 * K)
	WorldView.spr_ground(c, w, &"ghost_pusher", bx, 2.4 * K, 0.95, true, bob, true)
	return Vector2(bx, by + 3.4 * K)


# ———————————————— HUD ————————————————
func draw_hud(h: HudView, sim: SimGame, vp: Vector2, wv: WorldView) -> void:
	if sim.demo or sim.world == null:
		return
	var st: StorySystem = sim.story
	# 名字标签：头顶放不下（会压到顶部 HUD）时改放到脚下坡面。跟随世界的位置都要 screen_to_hud 换成 HUD 坐标（界面大小 ≠ 1 时 HUD 层是缩放过的）
	if wv != null:
		for tg: Dictionary in _tags:
			var top: Vector2 = h.screen_to_hud(wv.to_screen(float(tg["x"]), float(tg["y"])))
			var x: float = clampf(top.x, 140.0, vp.x - 200.0)
			var y: float = top.y
			if y < 170.0:
				var foot: Vector2 = h.screen_to_hud(wv.to_screen(float(tg["x"]), float(tg["gy"])))
				y = maxf(170.0, foot.y + 30.0)
			h.text_at(String(tg["name"]), Vector2(x, y), 18, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
			h.text_at(String(tg["sub"]), Vector2(x, y + 20.0), 13, Color(CREAM, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	# 石碑刻字：碑高 ≥ 22px 时才显示，字号随缩放
	if wv != null:
		var pps: float = wv.ppm_screen()
		for sl: Dictionary in _steles:
			var hpx: float = 3.4 * pps
			if hpx < 22.0:
				continue
			var fs: int = int(clampf(hpx * 0.13, 11.0, 16.0))
			var top2: Vector2 = h.screen_to_hud(wv.to_screen(float(sl["x"]), float(sl["y"])))
			var col: Color = Color("dfe8f5") if sim.is_night() else LINE
			h.text_at(String(sl["line"]), Vector2(top2.x, top2.y - 8.0), fs, col, HORIZONTAL_ALIGNMENT_CENTER)
			if String(sl["text"]) != "":
				h.text_at(Loc.t("story_view.quoted", "「%s」") % String(sl["text"]), Vector2(top2.x, top2.y - 8.0 - fs * 1.4), fs, col, HORIZONTAL_ALIGNMENT_CENTER)
	# 屏外提示（只在白天）：前方 160 米内还没见过的 NPC
	if sim.phase == &"day" and wv != null:
		for n: Dictionary in st.npcs:
			if bool(n["done"]) or float(n["s"]) <= sim.stone.s or float(n["s"]) - sim.stone.s >= 160.0:
				continue
			sim.world.at(float(n["s"]))
			var sx: float = h.screen_to_hud(wv.to_screen(sim.world.ax, sim.world.ay)).x
			if sx > vp.x - 40.0:
				var key: String = "autolycus" if n["id"] == &"merchant" else String(n["id"])
				var spk: Dictionary = _speaker(sim, key)
				var mx: float = vp.x - 130.0
				var my: float = vp.y * 0.6
				h.draw_circle(Vector2(mx, my), 20.0, INK)
				var pk: StringName = &""
				for k: Variant in spk.get("portraits", []):
					if not String(k).begins_with("por_") and SpriteDB.has(StringName(str(k))):
						pk = StringName(str(k))
						break
				var tex: Texture2D = SpriteDB.tex(pk) if pk != &"" else null
				if tex != null:
					h.draw_texture_rect(tex, Rect2(mx - 17.0, my - 17.0, 34.0, 34.0), false)
				h.draw_arc(Vector2(mx, my), 20.0, 0.0, TAU, 28, LINE, 1.5, true)
				h.text_at("%s %dm" % [String(spk.get("name", "")), maxi(0, roundi(float(n["alt"]) - sim.altitude()))], Vector2(mx - 28.0, my + 5.0), 14, CREAM, HORIZONTAL_ALIGNMENT_RIGHT)
				h.draw_colored_polygon(PackedVector2Array([Vector2(mx + 26.0, my - 7.0), Vector2(mx + 35.0, my), Vector2(mx + 26.0, my + 7.0)]), LINE)
			break
	# 旁白：底部一行（白天 / 登顶等待）
	var nr: Dictionary = st.narr
	if not nr.is_empty() and (sim.phase == &"day" or sim.phase == &"victory_wait"):
		var k: float = sim.t - float(nr["at"])
		var life: float = float(nr["life"])
		if k > 0.0 and k < life:
			var a: float = minf(1.0, minf(k / 0.6, (life - k) / 0.8))
			var y2: float = vp.y - 112.0
			var fnt: Font = Fonts.serif(500)
			var tw: float = minf(fnt.get_string_size(String(nr["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x, vp.x - 160.0)
			var band: Rect2 = Rect2(vp.x / 2.0 - tw / 2.0 - 70.0, y2 - 24.0, tw + 140.0, 38.0)
			h.draw_rect(Rect2(band.position + Vector2(band.size.x * 0.12, 0), Vector2(band.size.x * 0.76, band.size.y)), Color(INK, 0.55 * a))
			for i: int in 8:
				var f: float = (i + 0.5) / 8.0
				var aa: float = 0.55 * a * f
				h.draw_rect(Rect2(band.position.x + band.size.x * 0.12 * (i / 8.0), band.position.y, band.size.x * 0.12 / 8.0 + 1.0, band.size.y), Color(INK, aa))
				h.draw_rect(Rect2(band.end.x - band.size.x * 0.12 * ((i + 1) / 8.0), band.position.y, band.size.x * 0.12 / 8.0 + 1.0, band.size.y), Color(INK, aa))
			h.text_at(String(nr["text"]), Vector2(vp.x / 2.0, y2), 20, Color(CREAM, a), HORIZONTAL_ALIGNMENT_CENTER)
