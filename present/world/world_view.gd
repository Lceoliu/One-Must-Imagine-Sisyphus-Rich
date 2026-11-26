class_name WorldView
extends Node2D
## 世界层（移植 render.js 的世界部分）。世界坐标米 → 画布像素：x·PPM、−y·PPM（y 向上 → 向下）。
## 子画布：Terrain（main.tscn 里，陶土山体着色器 terrain.gdshader，自己按 night_k 换夜色）、tinted（夜间染色 shader：物件、人物、石头）
## 与 gold（不染色：压痕、裂纹、火光、封印、按键提示）。
## 镜头只跟随 sim 给的目标（cam_tx / cam_ty / cam_view_h），平滑、震屏、冲击在这里做。

const PPM: float = 100.0
const GOLD: Color = Color("f0b93a")
const GOLD_HI: Color = Color("ffe08a")
const INK: Color = Color("120c0a")
const LINE: Color = Color("e9d3a8")
const CREAM: Color = Color("f1e3c8")
const RUBBLE_BIG: Dictionary = {&"stone": &"rubble_stone_big", &"wood": &"rubble_wood_big"}

var sim: SimGame = null
var runner: SimRunner = null
## 赐福画面（祭坛、各流派）；main 设置
var boons: BoonView = null
## 剧情画面（NPC）；main 设置
var story_view: StoryView = null
## 命运宝瓶（世界里的宝瓶）；main 设置
var chest_view: ChestView = null
var cam: Camera2D
## 视差层（有 depth_sync(wv) 的子节点：后景山肩、层间雾带、前景）
var _depth: Array[Node] = []
## 山体（陶土底 + 黑釉刻画，terrain.gdshader）：按地形折线生成一次的网格，换天（World 换了）时重建
var terrain: Node2D
var _tmesh: ArrayMesh = null
var _tmesh_for: World = null
var _px_scale: float = 0.0
var tinted: Node2D
## 山脚城镇近排、远排的画布（main.tscn；没有就画回 tinted 上）
var _town_rows: Array[Node2D] = []
## 山坡上的建筑画在山体后面（main.tscn 的 World/SlopeBack，在 Terrain 之前；材质同城镇近排，黑釉抬一档）：路面、岩体从它前面过，
## 陡坡上建筑上坡那头被山坡挡住、下坡那头坐台基，不会盖住西西弗斯走的路（没有这个节点就照旧画在 tinted 上）
var _slope_back: Node2D = null
var gold: Node2D
## 西西弗斯：分部位骨骼（present/actors/sisyphus.tscn），挂在 tinted 下跟世界一起染色；每帧按模拟摆位置、选动作
const SIS_SCENE: String = "res://present/actors/sisyphus.tscn"
var _sis: SisyphusRig = null
var _sis_group: CanvasGroup = null
## 西西弗斯 2.1 米对应的骨架像素（SisyphusRig.height_px，固定值）
var _sis_push_h: float = 250.0
## 推石时画面上的石头（纯表现，模拟里的距离、计分、输入都不变）：蓄力时顶住不动、发力时往前走，见 _update_push_stone
var _stone_vis_s: float = NAN
var _stone_vis_roll: float = 0.0
var _stone_step_start: float = 0.0
var _stone_step: int = -1
## 画面上的石头最多比模拟落后几个石头半径（连按很快时；慢慢推时本来就落后不到这么多）
const STONE_LAG_R: float = 1.2
## 坐着时坡度里让整个人顺坡转的比例（比推石时多：坐着往后靠着山坡）；最多交给腿部 IK 的坡度（弧度）
const SIT_TILT: float = 0.8
const SIS_KEEP: float = 0.3
## 运镜（present/world/dawn_shot.gd）接管镜头时的 (x, y, 视野高)，米；x 为 NAN = 不接管
var cine: Vector3 = Vector3(NAN, NAN, NAN)
## 调试（tests/tools/push_rec.gd 读）：手贴石面时整个人沿坡挪了多少米、石头半径、接触点离坡面的高度（石头半径的倍数）
var dbg_hand: Vector3 = Vector3.ZERO
## 石头贴图（多面体黑石 + 奶油色裂纹）：轮廓半径表（贴图像素，72 个方向）、不透明区域重心、参考半径
const ROCK_KEY: StringName = &"boulder_etched"
var _rock_r: PackedFloat32Array = []
var _rock_c: Vector2 = Vector2.ZERO
var _rock_ref: float = 1.0

# 镜头（世界米）
var cam_x: float = 0.0
var cam_y: float = 0.0
var view_h: float = 14.0
var punch: float = 0.0
var _snap_seen: int = -1
# 震屏（trauma 模型 + 地鸣；屏幕像素）
var trauma: float = 0.0
var shake_t: float = 0.0
var shake_px: Vector2 = Vector2.ZERO
var feel_gain: float = 1.0
var t: float = 0.0


func _ready() -> void:
	# 山体：main.tscn 里 World/Terrain（陶土着色器 terrain_mat.tres，颜色在编辑器里可调）；单独运行本脚本时补一个
	terrain = get_node_or_null("Terrain") as Node2D
	if terrain == null:
		terrain = Node2D.new()
		terrain.name = "Terrain"
		var tm: ShaderMaterial = ShaderMaterial.new()
		tm.shader = load("res://present/shaders/terrain.gdshader")
		terrain.material = tm
		add_child(terrain)
	# 山体贴图（岩块 / 路沿 / 饰带的明暗图，terrain2 素材或临时占位）拼成数组绑到材质上
	TerrainTex.bind(terrain.material as ShaderMaterial)
	terrain.draw.connect(_draw_terrain)
	# 山脚城镇的近排 / 远排建筑：main.tscn 里 World/TownNear、TownFar（town_row.gdshader 把后排黑釉抬一档，路面上的人才认得出）
	for row: int in [1, 2]:
		var tn: Node2D = get_node_or_null("TownNear" if row == 1 else "TownFar") as Node2D
		if tn != null:
			tn.draw.connect(_draw_town_row.bind(tn, row))
			_town_rows.append(tn)
	_slope_back = get_node_or_null("SlopeBack") as Node2D
	if _slope_back != null:
		_slope_back.draw.connect(_draw_slope_back)
	tinted = Node2D.new()
	tinted.name = "Tinted"
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://present/shaders/sprite_night.gdshader")
	tinted.material = mat
	# 石头贴图很大、画出来可能只有几十像素：用 mipmap，转起来裂纹才不闪
	tinted.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tinted.draw.connect(_draw_tinted)
	_rock_profile()
	if ResourceLoader.exists(SIS_SCENE):
		_sis = (load(SIS_SCENE) as PackedScene).instantiate() as SisyphusRig
		# 骨骼还没有推石动作（重做部位期间）时退回逐帧精灵
		var ap: AnimationPlayer = _sis.get_node_or_null("Anim") as AnimationPlayer
		if ap == null or not ap.has_animation(&"push"):
			_sis.free()
			_sis = null
	if _sis != null:
		_sis.visible = false
		# 西西弗斯放进一个 CanvasGroup：整体描一圈陶土色的"留白缝"（figure_gap.gdshader），叠在黑色建筑、石头上时也认得出人；
		# 世界的夜色染色也在这个着色器里做（组里的部位不再用 tinted 的材质）
		_sis_group = CanvasGroup.new()
		_sis_group.name = "SisGroup"
		_sis_group.fit_margin = 6.0
		var gm: ShaderMaterial = ShaderMaterial.new()
		gm.shader = load("res://present/shaders/figure_gap.gdshader")
		_sis_group.material = gm
		tinted.add_child(_sis_group)
		_sis.parent_tint = false
		_sis_group.add_child(_sis)
		_sis.set_phase(&"push", 0.0)
		_sis_push_h = maxf(50.0, _sis.height_px)
		# 推石落脚踩在真实地形上（画布坐标 x → y）
		_sis.ground_fn = func(px: float) -> float: return -sim.world.y_at_x(px / PPM) * PPM if sim != null and sim.world != null else 0.0
	add_child(tinted)
	gold = Node2D.new()
	gold.name = "Gold"
	gold.draw.connect(_draw_gold)
	add_child(gold)
	cam = Camera2D.new()
	cam.name = "Cam"
	add_child(cam)
	cam.make_current()
	# 视差层（main.tscn：BackRidge 后景山肩、NearMist 层间雾带、Foreground 前景）：每帧镜头定下来之后交给它们
	for ch: Node in get_children():
		if ch.has_method(&"depth_sync"):
			_depth.append(ch)


static func p(x: float, y: float) -> Vector2:
	return Vector2(x * PPM, -y * PPM)


## 世界米 → 屏幕像素（给屏幕空间的图层用）
func to_screen(x: float, y: float) -> Vector2:
	return get_viewport().get_canvas_transform() * p(x, y)


## 当前每米多少屏幕像素
func ppm_screen() -> float:
	return get_viewport().get_canvas_transform().get_scale().x * PPM


func on_events(list: Array[SimEvent]) -> void:
	for e: SimEvent in list:
		match e.kind:
			&"shake":
				# 越震越难再加（连续碾城时不会一直顶在最大）；单次大冲击照样能震满
				trauma = minf(1.0, trauma + e.a * feel_gain * (1.0 - 0.55 * trauma))
			&"punch":
				if e.b > 0.0:
					punch = maxf(punch, e.a)
				else:
					punch = e.a


func _process(dt: float) -> void:
	var _pt: int = Prof.t()
	_process_impl(dt)
	Prof.add(&"world.process", _pt)


func _process_impl(dt: float) -> void:
	if sim == null or sim.world == null:
		return
	t += dt
	var _pt: int = Prof.t()
	_update_sis(dt)
	Prof.add(&"wp.sis", _pt)
	_pt = Prof.t()
	if boons != null:
		boons.tick(dt)
	if story_view != null:
		story_view.tick(dt)
	Prof.add(&"wp.boons_story", _pt)
	_pt = Prof.t()
	var vps: Vector2 = get_viewport_rect().size
	var fo: Vector2 = frame_offset(sim.world, sim.cam_tx, sim.cam_ty, sim.cam_view_h, vps.x / maxf(1.0, vps.y))
	Prof.add(&"wp.frame", _pt)
	var tx: float = sim.cam_tx + fo.x
	var ty: float = sim.cam_ty + fo.y
	if not is_nan(cine.x):
		# 运镜（DawnShot）接管镜头：直接用它给的位置和视野
		_snap_seen = sim.cam_snap
		cam_x = cine.x
		cam_y = cine.y
		view_h = cine.z
	elif sim.cam_snap != _snap_seen:
		_snap_seen = sim.cam_snap
		cam_x = tx
		cam_y = ty
		view_h = sim.cam_view_h
	else:
		var a: float = 1.0 - exp(-sim.cam_k * dt)
		var b: float = 1.0 - exp(-sim.cam_kz * dt)
		cam_x += (tx - cam_x) * a
		cam_y += (ty - cam_y) * a
		view_h += (sim.cam_view_h - view_h) * b
	punch *= exp(-7.0 * dt)
	# 震屏
	shake_t += dt
	trauma = maxf(0.0, trauma - sim.shake_decay * dt)
	var tr: float = trauma * trauma * sim.shake_max_px
	var rb: float = sim.rumble
	shake_px = Vector2(_n(37.0, 1.3) * tr * 0.55 + _n(23.0, 4.1) * rb * 0.6, _n(41.0, 7.7) * tr + _n(29.0, 2.2) * rb)
	var vp: Vector2 = get_viewport_rect().size
	var zoom: float = vp.y / (view_h * PPM * (1.0 - punch))
	cam.zoom = Vector2(zoom, zoom)
	cam.position = p(cam_x, cam_y) - shake_px / zoom
	RenderingServer.global_shader_parameter_set(&"night_k", sim.night_k())
	if _tmesh_for != sim.world:
		terrain.queue_redraw()
	# 山体着色器的线宽按 1080p 逻辑像素给：告诉它现在 1 逻辑像素 = 几个实际像素。用所在视口的真实像素（游戏画面在
	# GameViewport 子视口里按渲染分辨率缩放；拿窗口像素算会把中 / 低档的刻线画粗 1 / render_scale 倍）
	var pxs: float = px_per_logical(self)
	if absf(pxs - _px_scale) > 0.001:
		_px_scale = pxs
		(terrain.material as ShaderMaterial).set_shader_parameter(&"px_scale", pxs)
	# 山体跟远景用同一套时刻染色（清晨冷紫、傍晚暖红）
	(terrain.material as ShaderMaterial).set_shader_parameter(&"tod_tint", BackgroundView.tint_at(sim.tod(), sim.night_k()))
	px_world = 1.0 / maxf(0.01, cam.zoom.x)
	tinted.queue_redraw()
	var gild: float = 1.0 if bool(World.town_level(sim.content, sim.city_level).get("gilded", false)) else 0.0
	for tn: Node2D in _town_rows:
		var sm: ShaderMaterial = tn.material as ShaderMaterial
		if sm != null:
			sm.set_shader_parameter(&"gild", gild)
		tn.queue_redraw()
	if _slope_back != null:
		_slope_back.queue_redraw()
	gold.queue_redraw()
	_pt = Prof.t()
	for d: Node in _depth:
		if (d as CanvasItem).visible:
			d.call(&"depth_sync", self)
	Prof.add(&"wp.depth", _pt)


## 1 逻辑像素 = 几个实际像素（着色器按 1080p 逻辑像素给线宽时用）。游戏画面在 GameViewport 子视口里按渲染分辨率缩放，
## 要用子视口自己的像素尺寸；不在子视口里（测试、工具直接挂）时用窗口像素
static func px_per_logical(n: CanvasItem) -> float:
	var vp: Viewport = n.get_viewport()
	var px_h: float = float((vp as SubViewport).size.y) if vp is SubViewport else float(n.get_window().size.y)
	return px_h / maxf(1.0, n.get_viewport_rect().size.y)


## 构图（docs/v05/art-bible.md §4）：画面里地表以下的山体最多占 FRAME_MAX；超了就把镜头往上、再往左挪
## （石头和人落到画面中间偏右下，天空、远景占大头，视觉重心在人和石头上，不被半屏岩体压住）。
## 只在山体超标时动，平地、城镇、冥府之门这些本来就不超的镜头不受影响。返回加在镜头目标上的偏移（米，y 朝上）。
static func frame_offset(w: World, cx: float, cy: float, vh: float, aspect: float) -> Vector2:
	if w == null or vh <= 0.0:
		return Vector2.ZERO
	# 挪镜头的"等效竖直米数"：先往上挪（人往下落，最多 FRAME_UP_MAX 个画面高），再往左挪（人往右，最多 FRAME_SIDE_MAX 个画面宽；
	# 坡角 m 越陡，横挪一米抵得上越多竖挪）；两头都封顶了就到此为止（人不能被挤到画面边上）
	var m: float = maxf(0.3, absf(w.y_at_x(cx + 4.0) - w.y_at_x(cx - 4.0)) / 8.0)
	var need: float = 0.0
	var off: Vector2 = Vector2.ZERO
	for i: int in 4:
		var f: float = mountain_frac(w, cx + off.x, cy + off.y, vh, aspect)
		if f <= FRAME_MAX + 0.002:
			break
		need += (f - FRAME_MAX) * vh
		var up: float = minf(need, FRAME_UP_MAX * vh)
		var left: float = minf((need - up) / m, FRAME_SIDE_MAX * vh * aspect)
		off = Vector2(-left, up)
		if need - up - left * m > 0.01:
			break
	return off


## 以 (cx, cy) 为中心、高 vh 米的画面里，地表以下占的比例（逐列采样地形）
static func mountain_frac(w: World, cx: float, cy: float, vh: float, aspect: float) -> float:
	const N: int = 24
	var vw: float = vh * aspect
	var top: float = cy + vh * 0.5
	var sum: float = 0.0
	for i: int in N:
		var x: float = cx - vw * 0.5 + vw * (i + 0.5) / N
		sum += clampf((w.y_at_x(x) - (top - vh)) / vh, 0.0, 1.0)
	return sum / N


func _n(f: float, o: float) -> float:
	return sin(shake_t * f + o) * 0.5 + sin(shake_t * f * 2.31 + o * 1.7) * 0.3 + sin(shake_t * f * 4.7 + o * 0.3) * 0.2


## 可见的世界 x 范围（米）
func _vis_x() -> Vector2:
	var vp: Vector2 = get_viewport_rect().size
	var half_w: float = view_h * (vp.x / vp.y) * 0.5 / maxf(0.2, 1.0 - punch)
	return Vector2(cam_x - half_w - 4.0, cam_x + half_w + 4.0)


static func _hash(s: float, k: int) -> float:
	var v: float = sin(s * 12.9898 + k * 78.233) * 43758.5453
	return v - floorf(v)


# ———————————————— 染色层 ————————————————
func _draw_tinted() -> void:
	var _pt: int = Prof.t()
	_draw_tinted_impl()
	Prof.add(&"world.tinted", _pt)


func _draw_tinted_impl() -> void:
	if sim == null or sim.world == null:
		return
	var c: CanvasItem = tinted
	var vr: Vector2 = _vis_x()
	var ph: StringName = sim.phase
	_vis_sync()
	if ph == &"day" and not sim.ruins.is_empty():
		var ra: float = 0.45 * clampf(1.0 - sim.day_t / 20.0, 0.0, 1.0)
		if ra > 0.003:
			for o: CrushObj in sim.ruins:
				if o.x + o.w < vr.x or o.x - o.w > vr.y:
					continue
				var rc: Array = _ruin_fit.get(o, [])
				if rc.is_empty():
					rc = [ground_fit(sim.world, o.x, o.w * 0.9, 0.02), _rubble_tex(o)]
					_ruin_fit[o] = rc
				_draw_rubble(c, o, ra, rc[0], rc[1])
	_draw_gate(c)
	_draw_objects(c, vr, ph == &"day" or ph == &"victory_wait")
	for v: ObjVis in _g_runup.near(vr):
		var o: CrushObj = v.o
		if o.x + o.w >= vr.x and o.x - o.w <= vr.y:
			_draw_vis(c, v, 1.0)
	if boons != null:
		boons.draw_world(c, self, sim, vr)
	if story_view != null:
		story_view.draw_world(c, self, sim, vr)
	_draw_bet_flag(c, vr)
	_draw_characters(c, ph)
	_draw_boulder(c)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 山体网格：每个地形顶点往下拉一条竖边到 TERRAIN_DEPTH 米深、往上拉 TERRAIN_GRASS 米（路沿上的草丛带），
## 相邻两条竖边之间两个平行四边形（地下 + 草丛带）。左右各延长 3000 米（镜头拉远时看不到边）。
## UV = (正上方地表点的弧长 s, 地表下竖直深度)：弧长在一段直线里随 x 线性变化，所以插值正好等于真实弧长。
## 顶点色 r = 1 − 山脚平地（城镇）程度；g = 平滑坡角（0.5 + 角度 / π），着色器用它把 (s, 深度) 换成沿地表 / 垂直地表的坐标
## （陡坡上路沿、分档、饰带不被剪切拉歪；角度在顶点间线性过渡，折角处也连续）。
const TERRAIN_DEPTH: float = 3000.0
const TERRAIN_GRASS: float = 1.3
## 平滑坡角取前后各多少米弧长的弦（太小：深处的饰带在折角处被挤压；太大：贴不住地表的走向）
const TERRAIN_ANGLE_SPAN: float = 10.0


func _build_terrain_mesh(w: World) -> ArrayMesh:
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, terrain_arrays(w))
	return m


## 山体网格的顶点数组（Mesh.ARRAY_*）；单独拿出来给测试检查（无头模式下 ArrayMesh 读不回数据）
static func terrain_arrays(w: World) -> Array:
	var xs: PackedFloat64Array = [w.px[0] - 3000.0]
	var ys: PackedFloat64Array = [w.py[0]]
	xs.append_array(w.px)
	ys.append_array(w.py)
	xs.append(w.px[w.px.size() - 1] + 3000.0)
	ys.append(w.py[w.py.size() - 1])
	# 弧长（延长段水平，所以真实顶点上的值和 World.ps 一致）
	var ss: PackedFloat64Array = [-3000.0]
	for i: int in range(1, xs.size()):
		ss.append(ss[i - 1] + Vector2(xs[i] - xs[i - 1], ys[i] - ys[i - 1]).length())
	var ss0: float = ss[1] - w.ps[0]
	for i: int in ss.size():
		ss[i] -= ss0
	var ang: PackedFloat32Array = []
	for i: int in xs.size():
		var a: Vector2 = _terrain_at_s(xs, ys, ss, ss[i] - TERRAIN_ANGLE_SPAN)
		var b: Vector2 = _terrain_at_s(xs, ys, ss, ss[i] + TERRAIN_ANGLE_SPAN)
		ang.append(atan2(b.y - a.y, b.x - a.x))
	var v: PackedVector2Array = []
	var uv: PackedVector2Array = []
	var cols: PackedColorArray = []
	for i: int in xs.size() - 1:
		var j: int = i + 1
		if xs[j] <= xs[i]:
			continue
		var q: Array[Vector2] = [p(xs[i], ys[i]), p(xs[j], ys[j]), p(xs[j], ys[j] - TERRAIN_DEPTH), p(xs[i], ys[i] - TERRAIN_DEPTH),
			p(xs[i], ys[i] + TERRAIN_GRASS), p(xs[j], ys[j] + TERRAIN_GRASS)]
		var u: Array[Vector2] = [Vector2(ss[i], 0.0), Vector2(ss[j], 0.0), Vector2(ss[j], TERRAIN_DEPTH), Vector2(ss[i], TERRAIN_DEPTH),
			Vector2(ss[i], -TERRAIN_GRASS), Vector2(ss[j], -TERRAIN_GRASS)]
		var ti: float = smoothstep(0.2, 0.8, ys[i])
		var tj: float = smoothstep(0.2, 0.8, ys[j])
		var gi: float = 0.5 + ang[i] / PI
		var gj: float = 0.5 + ang[j] / PI
		var cc: Array[Color] = [Color(ti, gi, 0), Color(tj, gj, 0), Color(tj, gj, 0), Color(ti, gi, 0), Color(ti, gi, 0), Color(tj, gj, 0)]
		for k: int in [0, 1, 2, 0, 2, 3, 4, 5, 1, 4, 1, 0]:
			v.append(q[k])
			uv.append(u[k])
			cols.append(cc[k])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = cols
	return arr


## 折线上弧长 s 处的点（超出两端时沿端段延长）
static func _terrain_at_s(xs: PackedFloat64Array, ys: PackedFloat64Array, ss: PackedFloat64Array, s: float) -> Vector2:
	var n: int = ss.size()
	var lo: int = 0
	var hi: int = n - 1
	while hi - lo > 1:
		var m: int = (lo + hi) >> 1
		if ss[m] <= s:
			lo = m
		else:
			hi = m
	var len: float = ss[hi] - ss[lo]
	var t: float = (s - ss[lo]) / len if len > 1e-9 else 0.0
	return Vector2(xs[lo] + (xs[hi] - xs[lo]) * t, ys[lo] + (ys[hi] - ys[lo]) * t)


func _draw_terrain() -> void:
	var _pt: int = Prof.t()
	_draw_terrain_impl()
	Prof.add(&"world.terrain", _pt)


func _draw_terrain_impl() -> void:
	if sim == null or sim.world == null:
		return
	if _tmesh_for != sim.world:
		_tmesh_for = sim.world
		_tmesh = _build_terrain_mesh(sim.world)
		# 饰带在山脚处从棕榈叶纹换成光芒纹、从浅变深
		(terrain.material as ShaderMaterial).set_shader_parameter(&"foot_s", sim.world.s_foot)
	terrain.draw_mesh(_tmesh, null)


## 只给对比截图用（tests/tools/world_shots.gd --scheme）：覆盖山体着色器参数 {"terrain": {参数名: "#rrggbb" 或数字}}
func apply_scheme(d: Dictionary) -> void:
	var m: ShaderMaterial = terrain.material as ShaderMaterial
	var tp: Dictionary = d.get("terrain", {})
	for k: String in tp:
		var val: Variant = tp[k]
		m.set_shader_parameter(StringName(k), Color(String(val)) if val is String else float(val))


## 站在坡上的东西怎么摆：底边两端落在地表上（按两端连线的角度转），再沉到底边中段也不悬空为止；
## 两端因此微陷的几厘米由素材底部的石基盖住。返回 Vector3(底边中点 x, 底边中点 y, 坡角)，画布旋转用 −坡角。
## cap：最大倾角。建筑类（ARCH_*）传 ARCH_TILT——坡比它陡时倾角不再跟着坡，反而慢慢回正；底边中点落在地表上，
## 下坡一侧悬空的部分由 terrace() 砌台基补上、上坡一侧嵌进山里（希腊山地神庙"半挖半填"的台地）。
## hold = true（一般物件）：坡比封顶陡时停在封顶角度不回正，按超出的角度把物件往坡里多埋一点（上坡一侧嵌进土里，下坡一侧不悬空）
static func ground_fit(w: World, x: float, wm: float, sink: float = 0.04, cap: float = PI, hold: bool = false) -> Vector3:
	var hw: float = maxf(0.05, wm * 0.5)
	var yl: float = w.y_at_x(x - hw)
	var yr: float = w.y_at_x(x + hw)
	var a: float = atan2(yr - yl, hw * 2.0)
	if absf(a) > cap and hold:
		return Vector3(x, w.y_at_x(x) - sink - hw * tan(absf(a) - cap), signf(a) * cap)
	if absf(a) > cap:
		# 超过封顶后倾角平滑回到 0（坡越陡越端正：缓坡顺坡、峭壁上端坐台基），在 2.5 倍封顶处完全竖直
		var k: float = clampf(1.0 - (absf(a) - cap) / (cap * 1.5), 0.0, 1.0)
		return Vector3(x, w.y_at_x(x) - sink, signf(a) * cap * k * k * (3.0 - 2.0 * k))
	var low: float = 0.0
	for i: int in range(1, 8):
		var f: float = i / 8.0
		low = maxf(low, yl + (yr - yl) * f - w.y_at_x(x - hw + hw * 2.0 * f))
	return Vector3(x, (yl + yr) * 0.5 - low - sink, a)


## 物件和西西弗斯、石头重叠时的不透明度；离开多少米后完全恢复
const NEAR_FADE: float = 0.5
const NEAR_FADE_SOFT: float = 1.0
## 一般物件（陶罐、草垛、牲畜、人）的最大倾角（≈ 21°）
const PROP_TILT: float = 0.37
## 建筑的最大倾角（≈ 8.6°）：缓坡照常整个顺坡转，再陡就慢慢回正、坐在台基上（斜 50° 的神庙看着像要滑下山）
const ARCH_TILT: float = 0.15
## 按建筑摆（倾角封顶 + 台基）的精灵：神龛、赐福祭坛、冥府之门、先祖石碑
const ARCH_KEYS: Dictionary = {&"shrine_bronze": true, &"shrine_silver": true, &"shrine_gold": true, &"shrine_mythic": true, &"herm": true,
	&"altar_boon": true, &"hades_gate": true, &"gate_small": true, &"stele_ancestor": true, &"stele": true}
## 山坡物件里按建筑摆的：石砌、高过 2.5 米的（民居、神庙、神像、塔……），外加几样木 / 陶的大建筑
const ARCH_TYPES: Dictionary = {&"siege_tower": true, &"olive_press": true, &"potter_kiln": true}
## 构图：山体最多占画面的比例；为此镜头先往上挪（最多几个画面高）、再往左挪（最多几个画面宽）
const FRAME_MAX: float = 0.36
const FRAME_UP_MAX: float = 0.07
const FRAME_SIDE_MAX: float = 0.12
## 1 屏幕像素 = 多少画布像素（每帧按镜头缩放更新；台基刻线按屏幕像素定宽）
static var px_world: float = 1.0
## 贴图底边的不透明范围（"脚"）：key → Vector3(左, 右, 底部透明边)，都是相对贴图宽 / 高的比例
static var _foot: Dictionary = {}


static func is_arch(o: CrushObj) -> bool:
	if ARCH_TYPES.has(o.type):
		return true
	return o.def != null and o.def.mat == &"stone" and o.h >= 2.5


## 贴图的"脚"：最下面一排不透明像素往上 4% 高度内的左右范围，和底下透明边的高度（读一次缓存；读不到像素时当整宽）。
## 图集里的物件用 pack_atlas.py 离线算好的同一结果（从图集读像素要把整页 4096 的图从显卡读回来，一次几十毫秒）
static func foot(key: StringName) -> Vector3:
	if _foot.has(key):
		return _foot[key]
	var pre: Variant = SpriteDB.foot_of(key)
	if pre != null:
		_foot[key] = pre
		return pre
	var tex: Texture2D = SpriteDB.tex_plain(key)
	var out: Vector3 = foot_from_image(tex.get_image() if tex != null else null)
	_foot[key] = out
	return out


## 从贴图像素算"脚"（img 为 null 时当整宽）；tools/assets/pack_atlas.py 的 foot_of() 是同一算法
static func foot_from_image(img: Image) -> Vector3:
	var out: Vector3 = Vector3(0.04, 0.96, 0.0)
	if img != null:
		if img.is_compressed():
			img.decompress()
		var iw: int = img.get_width()
		var ih: int = img.get_height()
		var step: int = maxi(1, iw / 400)
		var bottom: int = -1
		var y: int = ih - 1
		while y >= 0 and bottom < 0:
			for x: int in range(0, iw, step):
				if img.get_pixel(x, y).a > 0.5:
					bottom = y
					break
			y -= 1
		if bottom >= 0:
			var l: int = iw
			var r: int = -1
			for yy: int in range(maxi(0, bottom - int(ih * 0.04)), bottom + 1):
				for x: int in range(0, iw, step):
					if img.get_pixel(x, yy).a > 0.5:
						l = mini(l, x)
						r = maxi(r, x)
			if r > l:
				out = Vector3(float(l) / iw, float(r + 1) / iw, float(ih - 1 - bottom) / ih)
	return out


## 台基：建筑底边 [u0, u1]（局部米，沿底边）在地表上方悬空的部分，砌一座黑釉石台补到地里。
## 局部坐标：原点 = g 的底边中点，x 沿底边、y 朝下（垂直于底边）。奶油刻线：顶上一道压檐线、逐层砌缝、错缝竖缝，
## 线宽按屏幕像素（px_world）定；砌缝在屏幕上挤到一起时省掉。
static func terrace(c: CanvasItem, w: World, g: Vector3, u0: float, u1: float, alpha: float = 1.0) -> void:
	var tg: TerraceGeo = terrace_geo(w, g, u0, u1)
	if tg != null:
		terrace_draw(c, tg, g, alpha)


## 台基的几何（局部画布像素）：只看地形和底边，山坡物件的算一次存在 ObjVis 里；线宽、砌缝省不省每帧按缩放定（terrace_draw）
class TerraceGeo:
	var polys: Array[PackedVector2Array] = []
	var slabs: Array[Rect2] = []
	## 压檐线、逐层砌缝、错缝竖缝：成对的端点
	var cap: PackedVector2Array = []
	var courses: PackedVector2Array = []
	var joints: PackedVector2Array = []


const TERRACE_CH: float = 0.36       # 砌层高（米）


## 不用砌（悬空不到 0.16 米）时返回 null
static func terrace_geo(w: World, g: Vector3, u0: float, u1: float) -> TerraceGeo:
	const N: int = 18
	const CH: float = TERRACE_CH
	const BW: float = 0.95           # 石块长（米）
	var ca: float = cos(g.z)
	var sa: float = sin(g.z)
	var us: PackedFloat32Array = []
	var ds: PackedFloat32Array = []
	var dmax: float = 0.0
	for i: int in N + 1:
		var u: float = lerpf(u0, u1, float(i) / N)
		var gap: float = g.y + u * sa - w.y_at_x(g.x + u * ca)
		# 再往地里多埋 0.1 米：台基底边压过地表轮廓线，不露缝
		var d: float = maxf(0.0, gap * ca + 0.1) if gap > -0.1 else 0.0
		us.append(u)
		ds.append(d)
		dmax = maxf(dmax, d)
	if dmax < 0.16:
		return null
	var tg: TerraceGeo = TerraceGeo.new()
	# 实心台体：沿底边逐段的梯形（深度为 0 的那头退化成三角形）
	for i: int in N:
		if ds[i] <= 0.0 and ds[i + 1] <= 0.0:
			continue
		var q: PackedVector2Array = [Vector2(us[i], 0.0) * PPM, Vector2(us[i + 1], 0.0) * PPM]
		if ds[i + 1] > 0.0:
			q.append(Vector2(us[i + 1], ds[i + 1]) * PPM)
		if ds[i] > 0.0:
			q.append(Vector2(us[i], ds[i]) * PPM)
		tg.polys.append(q)
	# 压檐石：台基外露的那头（够高时）比底边多伸出一点
	var slab: float = 0.13
	for side: int in [0, N]:
		if ds[side] > 0.5:
			var ex: float = us[side] + (-0.07 if side == 0 else 0.07)
			tg.slabs.append(Rect2(minf(ex, us[side]) * PPM, 0.0, absf(ex - us[side]) * PPM, slab * PPM))
	_terrace_line(tg.cap, us, ds, slab)
	var k: int = 1
	while slab + k * CH < dmax - 0.06:
		_terrace_line(tg.courses, us, ds, slab + k * CH)
		k += 1
	# 错缝竖缝（奇数层错开半块）；每块长短略有不同
	for row: int in k:
		var y0: float = slab + row * CH
		var y1: float = y0 + CH
		var u: float = u0 + BW * (0.5 if row % 2 == 1 else 0.85)
		var j: int = 0
		while u < u1 - 0.2:
			var dj: float = _terrace_depth(us, ds, u)
			if dj > y0 + 0.08:
				tg.joints.append(Vector2(u, y0) * PPM)
				tg.joints.append(Vector2(u, minf(y1, dj - 0.04)) * PPM)
			u += BW * (0.8 + 0.4 * _hash(g.x + row * 3.7, j))
			j += 1
	return tg


static func terrace_draw(c: CanvasItem, tg: TerraceGeo, g: Vector3, alpha: float) -> void:
	c.draw_set_transform(p(g.x, g.y), -g.z, Vector2.ONE)
	var ink: Color = Color(INK, alpha)
	# 台体每段只有 3–4 个点（凸的）：画成图元（批量合并），不走 draw_colored_polygon（每次三角化、每帧新建顶点缓冲）
	var inks: PackedColorArray = [ink]
	for q: PackedVector2Array in tg.polys:
		c.draw_primitive(q, inks, PackedVector2Array())
	var lw: float = 1.5 * px_world
	var lc: Color = Color(LINE, 0.9 * alpha)
	for r: Rect2 in tg.slabs:
		c.draw_rect(r, ink)
	_draw_pairs(c, tg.cap, lc, lw)
	# 砌层：屏幕上层高不到 6 像素就只留压檐线
	if TERRACE_CH * PPM / px_world >= 6.0:
		_draw_pairs(c, tg.courses, lc, lw)
		_draw_pairs(c, tg.joints, lc, lw)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _draw_pairs(c: CanvasItem, pts: PackedVector2Array, col: Color, lw: float) -> void:
	for i: int in range(0, pts.size(), 2):
		c.draw_line(pts[i], pts[i + 1], col, lw)


## 台基深度在 u 处的插值
static func _terrace_depth(us: PackedFloat32Array, ds: PackedFloat32Array, u: float) -> float:
	var n: int = us.size()
	var f: float = clampf((u - us[0]) / maxf(1e-4, us[n - 1] - us[0]), 0.0, 1.0) * (n - 1)
	var i: int = mini(n - 2, int(f))
	return lerpf(ds[i], ds[i + 1], f - i)


## 台基里深度 y 的一道横砌缝：只画在台体深于 y 的那几段上（端点按相邻两点插值）
static func _terrace_line(out: PackedVector2Array, us: PackedFloat32Array, ds: PackedFloat32Array, y: float) -> void:
	var start: float = NAN
	var inset: float = 0.05
	for i: int in us.size():
		var inside: bool = ds[i] > y + inset
		if inside and is_nan(start):
			start = us[i] if i == 0 else lerpf(us[i - 1], us[i], (y + inset - ds[i - 1]) / maxf(1e-4, ds[i] - ds[i - 1]))
		elif not inside and not is_nan(start):
			var e: float = lerpf(us[i - 1], us[i], (y + inset - ds[i - 1]) / minf(-1e-4, ds[i] - ds[i - 1]))
			if e - start > 0.1:
				out.append(Vector2(start, y) * PPM)
				out.append(Vector2(e, y) * PPM)
			start = NAN
	if not is_nan(start) and us[us.size() - 1] - start > 0.1:
		out.append(Vector2(start, y) * PPM)
		out.append(Vector2(us[us.size() - 1], y) * PPM)


## spr_ground 用：精灵 key → [贴图, 宽高比, 脚]（取到贴图后才记）；台基几何缓存
static var _spr_info: Dictionary = {}
static var _ter_cache: Dictionary = {}


## 按 ground_fit 摆一张站在坡上的精灵（底边中点在 x，高 hm 米）；没有这张图返回 false。
## ARCH_KEYS 里的（神龛、祭坛、门、石碑）按建筑摆：倾角封顶 ARCH_TILT，下坡悬空处砌台基；
## 不论哪种，都按贴图真实的"脚"（底边不透明范围）贴地，贴图底下的透明边不会让它浮起来。
## upright = true：人、动物、陶罐这类"站着"的东西——倾角封顶 PROP_TILT（≈ 21°），陡坡上不跟着整个斜过去，上坡那只脚贴地
## skew：以脚为轴的斜切（正 = 上身往贴图朝向那边压，脚不动）；sxy：以脚为轴的缩放（帮手发力时压扁一点）
static func spr_ground(c: CanvasItem, w: World, key: StringName, x: float, hm: float, alpha: float = 1.0, flip: bool = false, lift: float = 0.0, upright: bool = false,
		skew: float = 0.0, sxy: Vector2 = Vector2.ONE) -> bool:
	var info: Array = _spr_info.get(key, [])
	if info.is_empty():
		var tx: Texture2D = SpriteDB.tex(key)
		if tx == null:
			return false
		info = [tx, SpriteDB.aspect(key), foot(key)]
		_spr_info[key] = info
	var tex: Texture2D = info[0]
	var h: float = hm * PPM
	var wd: float = h * float(info[1])
	var ft: Vector3 = info[2]
	var fu0: float = (ft.x - 0.5) * wd / PPM
	var fu1: float = (ft.y - 0.5) * wd / PPM
	if flip:
		var tmp: float = fu0
		fu0 = -fu1
		fu1 = -tmp
	var arch: bool = ARCH_KEYS.has(key)
	var g: Vector3 = ground_fit(w, x + (fu0 + fu1) * 0.5, fu1 - fu0, minf(0.08, hm * 0.02), PROP_TILT, true) if upright and not arch \
		else ground_fit(w, x + (fu0 + fu1) * 0.5, fu1 - fu0, minf(0.08, hm * 0.02), ARCH_TILT if arch else PI)
	# ground_fit 以脚的中点为准；换回贴图中轴（沿底边）
	var mid: float = (fu0 + fu1) * 0.5
	var gx: float = g.x - mid * cos(g.z)
	var gy: float = g.y - mid * sin(g.z)
	if arch:
		# 台基几何按 (地形, 落脚, 底边) 缓存：祭坛、冥府之门这些不动的建筑每帧都一样
		var tk: Array = [w, gx, gy, g.z, fu0, fu1]
		if not _ter_cache.has(tk):
			if _ter_cache.size() > 64:
				_ter_cache.clear()
			_ter_cache[tk] = terrace_geo(w, Vector3(gx, gy, g.z), fu0, fu1)
		var tg: TerraceGeo = _ter_cache[tk]
		if tg != null:
			terrace_draw(c, tg, Vector3(gx, gy, g.z), alpha)
	var up: Vector2 = Vector2(sin(g.z), cos(g.z)) * lift
	c.draw_set_transform_matrix(Transform2D(-g.z, Vector2((-1.0 if flip else 1.0) * sxy.x, sxy.y), -skew if flip else skew, p(gx - up.x, gy + up.y)))
	c.draw_texture_rect(tex, Rect2(-wd / 2.0, -h * (1.0 - ft.z), wd, h), false, Color(1, 1, 1, alpha))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## 山坡物件怎么摆：一般物件顺坡转但最多斜 PROP_TILT（陡坡上斜 45° 的陶罐、草垛像要倒），超出的部分埋进坡里；
## 建筑（is_arch）倾角封顶 ARCH_TILT，坐在台基上（台基在 _draw_vis 里画）
func _obj_fit(o: CrushObj) -> Vector3:
	if is_arch(o):
		return ground_fit(sim.world, o.x, o.w * _obj_foot_w(o), minf(0.06, o.h * 0.02), ARCH_TILT)
	return ground_fit(sim.world, o.x, o.w * _obj_foot_w(o), minf(0.06, o.h * 0.02), PROP_TILT, true)



## 物件贴图"脚"的宽度占整宽的比例（台基只砌在脚下面）
func _obj_foot_w(o: CrushObj) -> float:
	var key: StringName = o.type if SpriteDB.has(o.type) else StringName(o.ext.get("alias", o.type))
	if not SpriteDB.has(key):
		return 1.0
	var ft: Vector3 = foot(key)
	return clampf(ft.y - ft.x, 0.3, 1.0)


## 碎石贴图（没有时 null，走手画的碎块）
static func _rubble_tex(o: CrushObj) -> Texture2D:
	var mat: StringName = o.def.mat if o.def != null else &"stone"
	var key: StringName = RUBBLE_BIG.get(mat, &"") if o.tier >= 4 else &""
	if key == &"":
		key = StringName("rubble_" + String(mat))
	return SpriteDB.tex(key)


## fit、tex：调用方缓存的落脚和碎石贴图（不给就现算）
func _draw_rubble(c: CanvasItem, o: CrushObj, a: float, fit: Vector3 = Vector3(NAN, 0.0, 0.0), tex: Texture2D = null) -> void:
	if tex == null:
		tex = _rubble_tex(o)
	var hp: float = maxf(0.15, minf(1.2, o.h * 0.18)) * PPM
	var wp: float = o.w * 0.9 * PPM
	var g: Vector3 = fit if not is_nan(fit.x) else ground_fit(sim.world, o.x, o.w * 0.9, 0.02)
	c.draw_set_transform(p(g.x, g.y), -g.z, Vector2.ONE)
	if tex != null:
		c.draw_texture_rect(tex, Rect2(-wp / 2.0, -hp, wp, hp), false, Color(1, 1, 1, a))
		return
	var n: int = 3 + int(floorf(_hash(o.s, 1) * 3.0))
	for i: int in n:
		var cx: float = (float(i) / maxf(1.0, n - 1.0) - 0.5) * wp * 0.78 + (_hash(o.s, i + 2) - 0.5) * wp * 0.12
		var bw: float = wp * (0.22 + 0.16 * _hash(o.s, i + 9))
		var th: float = hp * (0.45 + 0.55 * _hash(o.s, i + 17))
		var lean: float = (_hash(o.s, i + 23) - 0.5) * bw * 0.8
		c.draw_colored_polygon(PackedVector2Array([Vector2(cx - bw / 2.0, 1.0), Vector2(cx + lean, -th), Vector2(cx + bw / 2.0, 1.0)]), Color(INK, a))
		if i % 2 == 0:
			c.draw_line(Vector2(cx - bw * 0.25, -th * 0.3), Vector2(cx + lean * 0.5, -th * 0.72), Color(LINE, a), maxf(1.0, hp * 0.08))


## 山坡物件：白天和夜里同一套画法（白天不再是虚影，黄昏也不再从地里长出来；只有赐福黄昏新放的会长出来）。
## 白天离西西弗斯和石头很近的物件淡到一半（near_fade），免得黑剪影叠在一起认不出人。
func _draw_objects(c: CanvasItem, vr: Vector2, day: bool) -> void:
	var nr: Vector2 = _near_range(day)
	var near_lo: float = nr.x
	var near_hi: float = nr.y
	# 山脚城镇分三排（o.ext.row：2 远排、1 近排、0 路面 / 山上物件）：先画后排，路面的人和车压在建筑前面。
	# 近排、远排有自己的画布（_draw_town_row，在 tinted 下面）时这里只画路面
	for pass_row: int in ([0] if _town_rows.size() == 2 else [2, 1, 0]):
		_draw_objects_row(c, vr, pass_row, near_lo, near_hi)


## 山坡上的建筑（World/SlopeBack 的 draw，画在山体后面）：在西西弗斯、石头经过时和别的物件一样淡到一半（连台基）
func _draw_slope_back() -> void:
	var _pt: int = Prof.t()
	_draw_slope_back_impl()
	Prof.add(&"world.slope_back", _pt)


func _draw_slope_back_impl() -> void:
	if sim == null or sim.world == null:
		return
	var vr: Vector2 = _vis_x()
	var nr: Vector2 = _near_range(sim.phase == &"day" or sim.phase == &"victory_wait")
	_vis_sync()
	for v: ObjVis in _g_back.near(vr):
		var o: CrushObj = v.o
		if o.x + o.w < vr.x or o.x - o.w > vr.y:
			continue
		_draw_vis(_slope_back, v, near_fade(o, nr.x, nr.y))
	_slope_back.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 白天"西西弗斯 → 石头前沿"这一段的 x 范围（米）；不是白天返回空范围（INF, −INF）
func _near_range(day: bool) -> Vector2:
	if not day or sim.sis.is_empty():
		return Vector2(INF, -INF)
	return Vector2(float(sim.sis["x"]) - 0.9, sim.stone.x + sim.stone.r * 0.75)


## 物件和"西西弗斯 → 石头"这一段重叠时淡到 NEAR_FADE，离开 NEAR_FADE_SOFT 米后恢复
static func near_fade(o: CrushObj, near_lo: float, near_hi: float) -> float:
	if near_hi <= near_lo:
		return 1.0
	var gap: float = maxf(near_lo - (o.x + o.w * 0.5), (o.x - o.w * 0.5) - near_hi)
	return lerpf(NEAR_FADE, 1.0, clampf(gap / NEAR_FADE_SOFT, 0.0, 1.0))


## 画在山体后面的物件：山坡上（不是城里）的建筑
static func behind_slope(o: CrushObj) -> bool:
	return not o.city and int(o.ext.get("row", 0)) == 0 and is_arch(o)


## 山脚城镇近排 / 远排（World/TownNear、TownFar 的 draw）：同一套画法，换了画布才吃到 town_row.gdshader 的后排抬色
func _draw_town_row(tn: Node2D, row: int) -> void:
	var _pt: int = Prof.t()
	_draw_town_row_impl(tn, row)
	Prof.add(&"world.town_row", _pt)


func _draw_town_row_impl(tn: Node2D, row: int) -> void:
	if sim == null or sim.world == null:
		return
	var nr: Vector2 = _near_range(sim.phase == &"day" or sim.phase == &"victory_wait")
	_vis_sync()
	_draw_objects_row(tn, _vis_x(), row, nr.x, nr.y)
	tn.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 某一排（o.ext.row）的物件，不含画在山体后面的建筑（有 SlopeBack 时）
func _draw_objects_row(c: CanvasItem, vr: Vector2, pass_row: int, near_lo: float, near_hi: float) -> void:
	for v: ObjVis in _g_row[pass_row].near(vr):
		var o: CrushObj = v.o
		if o.x + o.w < vr.x or o.x - o.w > vr.y:
			continue
		var a: float = near_fade(o, near_lo, near_hi)
		_draw_vis(c, v, a)
		if o.city and o.state == CrushObj.State.CRACKED:
			_draw_town_crack(c, v, a)


## 城中物件的裂痕（docs/v05/town.md：蹭裂跨夜保留，白天也一直看得见）：画在物件自己那排的画布上（不然远排房子的裂纹会压到路面的人身上），
## 像刻线一样的奶油色细裂缝，从石基往上爬、带一个分叉，裂得越深越长越多；不用山坡上那种金色闪裂（金色只给神性和火）。
## 只画在贴图实心的地方（_crack_mask：按贴图不透明度取的小遮罩），不会画到敞开的棚子、柱子之间的空当里；人和牲畜不画裂缝。
func _draw_town_crack(c: CanvasItem, v: ObjVis, a: float) -> void:
	var o: CrushObj = v.o
	if o.def.living:
		return
	var mask: Image = _crack_mask(o)
	if mask == null:
		return
	# 裂缝折线只随裂度变：按裂度缓存
	if v.crack_k != o.dmg:
		v.crack_k = o.dmg
		v.crack = []
		var w: float = o.w * PPM
		var h: float = o.h * PPM
		var n: int = 1 + int(floorf(o.dmg * 3.5))
		var steps: int = 4 + int(floorf(o.dmg * 7.0))
		for i: int in n:
			var pt: Vector2 = Vector2((_h2(o.s, 60 + i) - 0.5) * w * 0.8, -h * 0.06)
			var pts: PackedVector2Array = [pt]
			var side: float = 1.0 if _h2(o.s, 300 + i) > 0.5 else -1.0
			var branch: PackedVector2Array = []
			for k: int in steps:
				pt += Vector2((_h2(o.s, 100 + i * 17 + k) - 0.5) * w * 0.08, -h * (0.04 + 0.05 * _h2(o.s, 200 + i * 13 + k)))
				pts.append(pt)
				if k == int(steps / 2.0):
					branch = [pt, pt + Vector2(w * 0.04 * side, -h * 0.05), pt + Vector2(w * 0.07 * side, -h * 0.09), pt + Vector2(w * 0.08 * side, -h * 0.13)]
			_crack_runs(v.crack, mask, pts, w, h, 1.0)
			_crack_runs(v.crack, mask, branch, w, h, 0.7)
	var g: Vector3 = v.fit
	c.draw_set_transform(p(g.x, g.y), -g.z, Vector2(-1.0 if o.flip else 1.0, 1.0))
	var lw: float = 1.8 / maxf(0.05, cam.zoom.x)
	# 夜里不用自己换色：所在画布的着色器（sprite_night / town_row）会和刻线一起乘冷蓝
	var col: Color = Color(LINE, 0.9 * a)
	for r: Array in v.crack:
		c.draw_polyline(r[0], col, lw * float(r[1]), true)


## 折线里落在贴图实心处的段（一段段断开，像刻线时绕开了镂空），以 [折线, 线宽倍数] 追加到 out
func _crack_runs(out: Array, mask: Image, pts: PackedVector2Array, w: float, h: float, lw_k: float) -> void:
	var run: PackedVector2Array = []
	for k: int in range(1, pts.size()):
		var mid: Vector2 = (pts[k - 1] + pts[k]) * 0.5
		var u: float = clampf(mid.x / w + 0.5, 0.0, 0.999)
		var v: float = clampf(1.0 + mid.y / h, 0.0, 0.999)
		if mask.get_pixel(int(u * mask.get_width()), int(v * mask.get_height())).a > 0.5:
			if run.is_empty():
				run.append(pts[k - 1])
			run.append(pts[k])
		elif run.size() > 1:
			out.append([run, lw_k])
			run = []
		else:
			run = []
	if run.size() > 1:
		out.append([run, lw_k])


## 每种物件一张 48×48 的不透明度遮罩（图集里的物件用 pack_atlas.py 离线算好的；其余第一次用时从贴图读，之后缓存；读不到就不画裂缝）
var _crack_masks: Dictionary = {}


func _crack_mask(o: CrushObj) -> Image:
	if _crack_masks.has(o.type):
		return _crack_masks[o.type]
	var pre: Image = SpriteDB.mask_of(o.type)
	if pre == null and not SpriteDB.has(o.type) and o.ext.has("alias"):
		pre = SpriteDB.mask_of(o.ext["alias"])
	if pre != null:
		_crack_masks[o.type] = pre
		return pre
	var tex: Texture2D = SpriteDB.tex_plain(o.type)
	if tex == null and o.ext.has("alias"):
		tex = SpriteDB.tex_plain(o.ext["alias"])
	var img: Image = tex.get_image() if tex != null else null
	if img != null:
		img = img.duplicate() as Image
		if img.is_compressed():
			img.decompress()
		img.resize(48, 48, Image.INTERPOLATE_BILINEAR)
	_crack_masks[o.type] = img
	return img


## 被碾平又恢复完好的物件（赫尔墨斯补货）：表现层自己记下"上一帧还是平的"，恢复时从地里弹出来，而不是凭空一闪出现。
## sim.objs 换了一批（新的一天、黄昏分出助跑区）就清空记录。
const POP_DUR: float = 0.4
var _was_flat: Dictionary = {}
var _pop_t: Dictionary = {}
var _objs_ref: Array[CrushObj] = []


func _pop_k(o: CrushObj) -> float:
	if not is_same(sim.objs, _objs_ref):
		_objs_ref = sim.objs
		_was_flat.clear()
		_pop_t.clear()
	if o.state == CrushObj.State.FLAT:
		_was_flat[o.id] = true
		return 1.0
	if _was_flat.has(o.id):
		_was_flat.erase(o.id)
		_pop_t[o.id] = t
	if not _pop_t.has(o.id):
		return 1.0
	var k: float = (t - float(_pop_t[o.id])) / POP_DUR
	if k >= 1.0:
		_pop_t.erase(o.id)
		return 1.0
	# 先冲过头一点再落回（back-out）
	var u: float = k - 1.0
	return maxf(0.0, 1.0 + 2.7 * u * u * u + 1.7 * u * u)


## 成排出现的物件（橄榄树、羊群、山羊群）按物件的位置挑一张变体图，再随机镜像，避免"复制排列"。
## 变体和原图同宽高比（平衡不变）；没有变体图的 key 就跳过
const VARIANTS: Dictionary = {&"olive_tree": [&"olive_tree", &"w2_olive_tree_b", &"w2_olive_tree_c"],
	&"sheep": [&"sheep", &"w2_sheep_b"], &"goat": [&"goat", &"w2_goat_b"]}


func _obj_tex(o: CrushObj) -> Texture2D:
	var keys: Array = VARIANTS.get(o.type, [])
	if keys.size() > 1:
		var i: int = int(absf(o.s * 7.31 + float(o.id) * 3.17)) % keys.size()
		var t: Texture2D = SpriteDB.tex(StringName(keys[i]))
		if t != null:
			return t
	var tex: Texture2D = SpriteDB.tex(o.type)
	if tex == null and o.ext.has("alias"):
		tex = SpriteDB.tex(o.ext["alias"])
	return tex


# ———————————————— 物件绘制缓存 ————————————————
## 每件山坡 / 城中物件画法里不变的量（表现层自己存，不写回 sim）。落脚只看物件的 x、宽高、种类和地形，生成后都不变；
## 裂纹折线按裂度（dmg）缓存。第一次画到时才算（_vis_prep），换一批物件的那一帧不卡。
class ObjVis:
	var o: CrushObj
	var arch: bool = false
	## 画在山体后面的山坡建筑（behind_slope）
	var back: bool = false
	var ready: bool = false
	## 物件贴图；取不到（图集还在加载）时为 null，下次再取
	var tex: Texture2D = null
	var fit: Vector3 = Vector3.ZERO
	## 建筑的台基（不用砌时 null）
	var ter: TerraceGeo = null
	## 一般物件碾平后碎石的落脚（建筑的碎石落在台基上，用 fit）、碎石贴图
	var rub_fit: Vector3 = Vector3.ZERO
	var rub_tex: Texture2D = null
	## 裂纹折线按哪个裂度算的；城中裂痕 [折线, 线宽倍数]……、山坡金裂纹
	var crack_k: float = -1.0
	var crack: Array = []
	var gcrack: Array[PackedVector2Array] = []
	## 亮窗：_h2(o.s, 77)（和繁荣度比）、每盏开始亮的阈值、位置（贴图局部像素）
	var lamp_h: float = -1.0
	var lamp_on: PackedFloat64Array = []
	var lamp_at: PackedVector2Array = []


## 一块画布要画的一组物件，保持 sim.objs 里的先后（= 绘制先后）；每 BLOCK 件记一个 [min(x − w), max(x + w)]，整块在可见范围外就跳过
class ObjGroup:
	const BLOCK: int = 8
	var items: Array[ObjVis] = []
	var lo: PackedFloat64Array = []
	var hi: PackedFloat64Array = []

	func add(v: ObjVis) -> void:
		var a: float = v.o.x - v.o.w
		var z: float = v.o.x + v.o.w
		if items.size() % BLOCK == 0:
			lo.append(a)
			hi.append(z)
		else:
			var b: int = lo.size() - 1
			lo[b] = minf(lo[b], a)
			hi[b] = maxf(hi[b], z)
		items.append(v)

	## 和 [vr.x, vr.y] 沾边的块里的物件（逐件是否可见仍由调用方判断）
	func near(vr: Vector2) -> Array[ObjVis]:
		var out: Array[ObjVis] = []
		var n: int = items.size()
		for b: int in lo.size():
			if hi[b] < vr.x or lo[b] > vr.y:
				continue
			for i: int in range(b * BLOCK, mini(n, b * BLOCK + BLOCK)):
				out.append(items[i])
		return out


## 分组按 [sim.objs, 件数, 助跑区件数, 地形] 失效：新的一天、黄昏分出助跑区 / 赐福插入物件都会换数组或改件数
var _vis_key: Array = []
## 0 路面 / 山上、1 近排、2 远排（有 SlopeBack 时不含画在山体后面的建筑）
var _g_row: Array[ObjGroup] = [ObjGroup.new(), ObjGroup.new(), ObjGroup.new()]
var _g_back: ObjGroup = ObjGroup.new()
var _g_runup: ObjGroup = ObjGroup.new()
## 城里会亮窗的、山上的（金裂纹）
var _g_lamp: ObjGroup = ObjGroup.new()
var _g_hill: ObjGroup = ObjGroup.new()
## 白天残骸（sim.ruins）的 [落脚, 碎石贴图]，CrushObj → Array；分组重建时清空
var _ruin_fit: Dictionary = {}


func _vis_sync() -> void:
	if _vis_key.size() == 4 and is_same(_vis_key[0], sim.objs) and int(_vis_key[1]) == sim.objs.size() \
			and int(_vis_key[2]) == sim.runup_objs.size() and is_same(_vis_key[3], sim.world):
		return
	_vis_key = [sim.objs, sim.objs.size(), sim.runup_objs.size(), sim.world]
	_g_row = [ObjGroup.new(), ObjGroup.new(), ObjGroup.new()]
	_g_back = ObjGroup.new()
	_g_runup = ObjGroup.new()
	_g_lamp = ObjGroup.new()
	_g_hill = ObjGroup.new()
	_ruin_fit.clear()
	for o: CrushObj in sim.objs:
		var v: ObjVis = ObjVis.new()
		v.o = o
		v.arch = is_arch(o)
		var row: int = int(o.ext.get("row", 0))
		v.back = not o.city and row == 0 and v.arch
		if _slope_back != null and v.back:
			_g_back.add(v)
		elif row >= 0 and row <= 2:
			_g_row[row].add(v)
		if not o.city:
			_g_hill.add(v)
		elif LIT.has(o.type):
			_g_lamp.add(v)
	for o: CrushObj in sim.runup_objs:
		var v: ObjVis = ObjVis.new()
		v.o = o
		v.arch = is_arch(o)
		_g_runup.add(v)


func _vis_prep(v: ObjVis) -> void:
	if v.tex == null:
		v.tex = _obj_tex(v.o)
	if v.ready:
		return
	v.ready = true
	var o: CrushObj = v.o
	v.fit = _obj_fit(o)
	if v.arch:
		var fw: float = o.w * _obj_foot_w(o) * 0.5
		v.ter = terrace_geo(sim.world, v.fit, -fw, fw)
	else:
		v.rub_fit = ground_fit(sim.world, o.x, o.w * 0.9, 0.02)
	v.rub_tex = _rubble_tex(o)


func _draw_vis(c: CanvasItem, v: ObjVis, alpha: float) -> void:
	var o: CrushObj = v.o
	var pk: float = _pop_k(o)
	_vis_prep(v)
	var tex: Texture2D = v.tex
	var w: float = o.w * PPM
	var h: float = o.h * PPM
	var g: Vector3 = v.fit
	# 建筑在陡坡上坐台基；建筑被碾平后台基还在，碎石落在台基上
	if v.ter != null:
		terrace_draw(c, v.ter, g, alpha)
	if o.state == CrushObj.State.FLAT:
		var k: float = minf(1.0, o.t / o.flat_dur) if o.flat_dur > 0.0 else 1.0
		if k < 1.0:
			var sy: float = 1.0 - (1.0 - 0.07) * (1.0 - pow(1.0 - k, 3.0))
			var sx: float = 1.0 + (o.flat_x - 1.0) * k
			c.draw_set_transform(p(g.x, g.y), -g.z, Vector2(-1.0 if o.flip else 1.0, 1.0))
			if tex != null:
				c.draw_texture_rect(tex, Rect2(-w * sx / 2.0, -h * sy, w * sx, h * sy), false, Color(1, 1, 1, 0.95 * alpha))
			else:
				_draw_placeholder(c, o, w * sx, h * sy)
		else:
			_draw_rubble(c, o, 0.95 * alpha, g if v.arch else v.rub_fit, v.rub_tex)
		return
	var rise: float = o.rise * pk
	if rise <= 0.001:
		return
	var shx: float = (randf() - 0.5) * o.shake * 0.3 if o.shake > 0.0 else 0.0
	c.draw_set_transform(p(g.x + shx, g.y), -g.z, Vector2(-1.0 if o.flip else 1.0, 1.0))
	if tex != null:
		c.draw_texture_rect(tex, Rect2(-w / 2.0, -h * rise, w, h * rise), false, Color(1, 1, 1, alpha))
	else:
		_draw_placeholder(c, o, w, h * rise)


func _draw_placeholder(c: CanvasItem, o: CrushObj, w: float, h: float) -> void:
	var k: float = clampf((o.tier - 1) / 5.0, 0.0, 1.0)
	c.draw_rect(Rect2(-w / 2.0, -h, w, h), Color8(46 - int(28 * k), 32 - int(20 * k), 24 - int(14 * k)))
	c.draw_line(Vector2(-w * 0.32, -h * 0.62), Vector2(w * 0.32, -h * 0.62), LINE, maxf(1.0, minf(2.0, w * 0.03)))


func _draw_gate(c: CanvasItem) -> void:
	var gt: Dictionary = sim.gate
	if gt.is_empty():
		return
	var tex: Texture2D = SpriteDB.tex(&"hades_gate")
	var gs: float = float(gt["shake"])
	var gx: float = float(gt["x"]) + ((randf() - 0.5) * gs * 0.8 if gs > 0.0 else 0.0)
	var h: float = float(gt["h"])
	var wm: float = h * SpriteDB.aspect(&"hades_gate")
	# 火盆
	for side: float in [-1.0, 1.0]:
		var fr: int = int(floorf(t * 6.0 + (0.0 if side < 0.0 else 1.7))) % 2
		var bt: Texture2D = SpriteDB.tex(StringName("gate_brazier_%d" % fr))
		if bt != null:
			var bh: float = 3.2 * PPM
			var bw: float = bh * SpriteDB.aspect(StringName("gate_brazier_%d" % fr))
			c.draw_set_transform(p(gx + side * float(gt["w"]) * 0.56, 0.0), 0.0, Vector2.ONE)
			c.draw_texture_rect(bt, Rect2(-bw / 2.0, -bh, bw, bh), false)
	if tex != null:
		c.draw_set_transform(p(gx, h), 0.0, Vector2.ONE)
		c.draw_texture_rect(tex, Rect2(-wm * PPM / 2.0, 0.0, wm * PPM, h * PPM), false)


## 提喀的赌注：白天在押的高度插一面小金旗（还没兑现时；兑现、日落后就没了）
func _draw_bet_flag(c: CanvasItem, vr: Vector2) -> void:
	var b: Dictionary = sim.bet
	if sim.demo or b.is_empty() or int(b.get("day", -1)) != sim.day or bool(b.get("paid", false)) or sim.phase != &"day":
		return
	var w: World = sim.world
	w.at(w.s_at_alt(float(b["h"])))
	var x: float = w.ax
	if x < vr.x - 3.0 or x > vr.y + 3.0:
		return
	var y: float = w.ay
	var ink: Color = Color("120c0a")
	var gold: Color = Color("f0b93a")
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	c.draw_line(p(x, y - 0.1), p(x, y + 2.7), ink, 5.0, true)
	var wave: float = sin(t * 3.2) * 0.08
	var flag: PackedVector2Array = [p(x, y + 2.68), p(x + 1.15, y + 2.42 + wave), p(x + 1.05, y + 2.3 + wave * 0.6), p(x, y + 2.08)]
	c.draw_colored_polygon(flag, gold)
	flag.append(flag[0])
	c.draw_polyline(flag, ink, 2.5, true)
	c.draw_circle(p(x, y + 2.75), 7.0, gold)
	c.draw_arc(p(x, y + 2.75), 7.0, 0.0, TAU, 16, ink, 2.0, true)


func _draw_characters(c: CanvasItem, ph: StringName) -> void:
	var st: Stats = sim.stats
	if ph == &"day" or ph == &"victory_wait":
		var sis: Dictionary = sim.sis
		if sis.is_empty():
			return
		var x: float = float(sis["x"]) - 1.6
		var helpers: Array = []
		if st.cerberus:
			helpers.append([&"cerberus_pusher", 1.9])
		if st.charon:
			helpers.append([&"charon_pusher", 2.2])
		for i: int in int(st.spartans):
			helpers.append([&"spartan_pusher", 2.1])
		for i: int in int(st.ghosts):
			helpers.append([&"ghost_pusher", 2.0])
		for i: int in int(st.drunkards):
			helpers.append([&"satyr_pusher" if SpriteDB.has(&"satyr_pusher") else &"satyr", 1.9])
		var cap: int = int(st.helper_cap)
		var idle: bool = sim.exhausted > 0 or ph == &"victory_wait"
		for k: int in mini(helpers.size(), cap):
			var name: StringName = helpers[k][0]
			var hm: float = helpers[k][1]
			var ps: Dictionary = helper_pose(k, name, t, idle)
			# 帮手站在坡上：倾角封顶、脚贴地（spr_ground upright）；推石的小动作见 helper_pose
			spr_ground(c, sim.world, name, x + float(ps["dx"]), hm, float(ps["a"]), false, float(ps["lift"]), true, float(ps["skew"]), ps["sxy"])
			x -= hm * 0.75 * cos(sim.world.ang_at(sim.world.s_at_x(x)))
		if _sis == null:
			var name2: StringName = StringName("push_%d" % sim.push_frame)
			if sim.exhausted > 0:
				name2 = &"tired"
			if ph == &"victory_wait":
				name2 = &"cheer"
			_sprite(c, name2, float(sis["x"]), float(sis["y"]), float(sis["h"]), -sim.bob, -float(sis["ang"]), false, 1.0)
	elif _sis == null:
		var sp: Dictionary = sim.sit_pos if not sim.sit_pos.is_empty() else sim.sis
		if sp.is_empty():
			return
		_sprite(c, &"sit", float(sp["x"]), float(sp["y"]), 1.5, 0.0, -float(sp.get("ang", 0.0)), false, 1.0)


## 白天帮手推石的小动作（不是骨骼动画，只让贴图不再完全静止）：
## 推石的人一下一下往前压（以脚为轴斜切，发力时压扁一点、往石头顶一点、脚下轻轻起伏）；
## 亡魂不踩地，悬着上下飘、透明度轻轻闪；西西弗斯累倒或登顶时大家都停下来慢慢喘气。
## 每个帮手的节奏和相位都错开（k = 队伍里第几个）。返回 {dx（米，正 = 往石头那边）, lift（米）, skew（弧度）, sxy, a}
static func helper_pose(k: int, key: StringName, time: float, idle: bool) -> Dictionary:
	var ghost: bool = key == &"ghost_pusher"
	var ph: float = float(k) * 0.37
	if ghost:
		var hover: float = 0.12 + 0.07 * sin(time * 2.1 + ph * 3.0)
		var lean: float = 0.03 if idle else 0.05 + 0.025 * sin(time * 2.1 + ph * 3.0 + 0.6)
		return {"dx": 0.0, "lift": hover, "skew": lean, "sxy": Vector2.ONE, "a": 0.72 + 0.06 * sin(time * 3.3 + ph * 5.0)}
	if idle:
		var br: float = 0.5 + 0.5 * sin(time * 1.7 + ph * 2.0)
		return {"dx": 0.0, "lift": 0.0, "skew": 0.015 + 0.012 * br, "sxy": Vector2(1.0 + 0.008 * br, 1.0 - 0.012 * br), "a": 1.0}
	# 一次发力：e 从 0 升到 1 再落回（周期 1.05–1.35 秒）
	var period: float = 1.05 + 0.15 * float(k % 3)
	var u: float = fposmod((time + ph) / period, 1.0)
	var e: float = 0.5 - 0.5 * cos(TAU * u)
	var dog: bool = key == &"cerberus_pusher"
	var amp: float = 0.6 if dog else 1.0
	return {
		"dx": 0.07 * e * amp,
		"lift": 0.035 * absf(sin(TAU * u)) * amp,
		"skew": (0.035 + 0.055 * e) * amp,
		"sxy": Vector2(1.0 + 0.015 * e * amp, 1.0 - 0.03 * e * amp),
		"a": 1.0,
	}


## 西西弗斯骨骼：白天以固定 3 秒双步节奏推石；力竭、欢呼、夜坐保留原动作。
## 推石顺坡摆姿态，前掌接地/抬跟/摆腿分开，手掌承力时跟随石头的材质点。
func _update_sis(dt: float) -> void:
	if _sis == null:
		return
	var ph: StringName = sim.phase
	var sis: Dictionary = sim.sis
	if (ph == &"day" or ph == &"victory_wait") and not sis.is_empty():
		var st: Stats = sim.stats
		var sway: float = sin(t * 3.1) * 0.02 if st.stride_hi > st.stride_lo and ph == &"day" else 0.0
		var k: float = float(sis["h"]) * PPM / _sis_push_h
		var x: float = float(sis["x"])
		_sis.visible = true
		_sis.scale = Vector2(k, k)
		# 姿势按坡角摆（SisyphusRig.pose_on_slope / push_hands；参数在 sisyphus.tscn 根节点的"推石姿势""推石落脚"里，
		# 调试台 tests/tools/rig/push_lab.tscn 里能直接拖着调）。推石的腿完全按关键帧（sis_push.tres，动画面板里手调），
		# 跨步不追求和石头实际走的距离一致（纯表现）
		var ga: float = sim.world.ang_at(sim.world.s_at_x(x))
		var pushing: bool = ph == &"day" and sim.exhausted <= 0
		_sis.position = p(x, float(sis["y"]) - sim.bob)
		_sis.pose_on_slope(ga, pushing, dt, sway)
		if ph == &"victory_wait":
			_stone_vis_s = NAN
			_sis.play_state(&"cheer")
		elif sim.exhausted > 0:
			_update_push_stone(dt, false)
			_sis.play_state(&"tired")
		else:
			var motion_dt: float = 0.0 if runner.app_paused or sim.modal != null else dt
			_sis.advance_push(motion_dt, sim.since_push < 0.5)
			_update_push_stone(motion_dt, sim.since_push < 0.5)
			var surface: Callable = Callable()
			if st.stone != &"moon" and st.stone != &"urn" and not _rock_r.is_empty():
				surface = func(a: float) -> float: return _rock_radius(Vector2.from_angle(a)) * sim.stone.r * PPM / _rock_ref
			var hr: Vector2 = _sis.push_hands(_boulder_center(), sim.stone.r * PPM, ga, _boulder_roll(), surface)
			dbg_hand = Vector3(hr.x / PPM, sim.stone.r, hr.y)
		return
	_stone_vis_s = NAN
	_sis.head_lean = 0.0
	_sis.reach_n = Vector2(NAN, NAN)
	_sis.reach_f = Vector2(NAN, NAN)
	var sp: Dictionary = sim.sit_pos if not sim.sit_pos.is_empty() else sis
	if sp.is_empty() or ph == &"day":
		_sis.visible = false
		return
	_sis.visible = true
	var k2: float = 2.1 * PPM / _sis_push_h
	_sis.scale = Vector2(k2, k2)
	# 坐在坡上：大半坡度让整个人顺坡转（人往后靠着山坡坐），剩下的交给骨骼——臀压在坡面上、两只脚各自踩坡
	var ga2: float = sim.world.ang_at(sim.world.s_at_x(float(sp["x"])))
	var keep2: float = clampf(ga2 * (1.0 - SIT_TILT), -SIS_KEEP, SIS_KEEP)
	_sis.rotation = -(ga2 - keep2)
	_sis.slope = keep2
	_sis.lean = 0.0
	_sis.position = p(float(sp["x"]), float(sp["y"]))
	_sis.play_state(&"sit")


func _sprite(c: CanvasItem, name: StringName, x: float, y: float, hm: float, bobv: float, rot: float, flip: bool, alpha: float) -> void:
	var tex: Texture2D = SpriteDB.tex(name)
	if tex == null:
		return
	var h: float = hm * PPM
	var w: float = h * SpriteDB.aspect(name)
	c.draw_set_transform(p(x, y + bobv), rot, Vector2(-1.0 if flip else 1.0, 1.0))
	c.draw_texture_rect(tex, Rect2(-w / 2.0, -h, w, h), false, Color(1, 1, 1, alpha))


## 画面上的石头沿坡走到哪（纯表现，不改模拟）：每半个循环（一步）里，西西弗斯蓄力时石头顶住不动、发力时按定好的曲线追上模拟位置；
## 不推了就平滑回到模拟位置。连按很快时最多落后 STONE_LAG_R 个半径，不然人和石头会被甩到画面边上
func _update_push_stone(dt: float, driving: bool) -> void:
	if is_nan(_stone_vis_s):
		_stone_vis_s = sim.stone.s
		_stone_vis_roll = -sim.stone.rot
		_stone_step = -1
	if dt <= 0.0:
		return
	var before: float = _stone_vis_s
	var step: int = int(floor(_sis._phase_f * 2.0))
	if step != _stone_step:
		_stone_step = step
		_stone_step_start = before
	if driving and sim.stone.s >= before:
		var q: float = fposmod(_sis._phase_f * 2.0, 1.0)
		var keys: Array[Vector2] = [Vector2(0,0),Vector2(0.32,0),Vector2(0.42,0.08),Vector2(0.60,0.75),Vector2(0.70,0.90),Vector2(0.90,0.98),Vector2(1,1)]
		var progress: float = 0.0
		for i: int in keys.size()-1:
			if q <= keys[i+1].x:
				progress = lerpf(keys[i].y,keys[i+1].y,smoothstep(keys[i].x,keys[i+1].x,q))
				break
		_stone_vis_s = maxf(before, lerpf(_stone_step_start,sim.stone.s,progress))
	else:
		_stone_vis_s = lerpf(before,sim.stone.s,1.0-exp(-10.0*dt))
	_stone_vis_s = maxf(_stone_vis_s, sim.stone.s - STONE_LAG_R * sim.stone.r)
	# 往上坡（往右）滚是顺时针（屏幕上旋转为正），往回滚反过来
	_stone_vis_roll += (_stone_vis_s-before)/sim.stone.r


## 石头画出来转了多少（弧度）：推石时跟着画面上的位置滚，其他时候用模拟里的
func _boulder_roll() -> float:
	return -sim.stone.rot if is_nan(_stone_vis_s) else _stone_vis_roll


## 石头画在哪（圆心）：推石时用画面上的位置；默认石头轮廓不是正圆，把接地方向那一点挪到坡面上。画石头和手贴石面共用这一个
func _boulder_center() -> Vector2:
	var b: Boulder = sim.stone
	var R: float = b.r * PPM
	var center: Vector2 = p(b.x, b.y)
	var at_s: float = b.s
	if not is_nan(_stone_vis_s):
		at_s = _stone_vis_s
		var ga: float = sim.world.at(at_s)
		center = p(sim.world.ax, sim.world.ay) + Vector2(-sin(ga),-cos(ga))*R
	var k: float = R / _rock_ref
	if sim.stats.stone != &"moon" and sim.stats.stone != &"urn" and not b.air and not _rock_r.is_empty():
		var ga: float = sim.world.ang_at(at_s)
		var down: Vector2 = Vector2(sin(ga), cos(ga))
		center += down * (R - _rock_radius(down.rotated(-_boulder_roll())) * k)
	return center


## 石头上粘的东西：种类 → [贴图, 宽高比]
var _stuck_tex: Dictionary = {}


func _draw_boulder(c: CanvasItem) -> void:
	var b: Boulder = sim.stone
	var st: Stats = sim.stats
	var R: float = b.r * PPM
	var stone: StringName = st.stone
	var center: Vector2 = _boulder_center()
	var k: float = R / _rock_ref
	# 粘上的东西（贴在边缘，随石头转）
	var roll: float = _boulder_roll()
	for s: Dictionary in b.stuck:
		# 贴图和宽高比按种类缓存（大石头上能粘几百件）
		var ta: Array = _stuck_tex.get(s["type"], [])
		if ta.is_empty():
			var tx0: Texture2D = SpriteDB.tex(s["type"])
			if tx0 == null:
				continue
			ta = [tx0, SpriteDB.aspect(s["type"])]
			_stuck_tex[s["type"]] = ta
		var tex: Texture2D = ta[0]
		var hh: float = float(s["h"]) * PPM
		var ww: float = hh * float(ta[1])
		var a: float = roll + float(s["a"])
		var off: Vector2 = Vector2(0.0, -R * (0.93 + float(s["out"]))).rotated(a)
		c.draw_set_transform(center + off, a, Vector2.ONE)
		c.draw_texture_rect(tex, Rect2(-ww / 2.0, -hh * 0.55, ww, hh), false)
	c.draw_set_transform(center, _boulder_roll(), Vector2.ONE)
	var key: StringName = &"boulder_moon" if stone == &"moon" else (&"boulder_urn" if stone == &"urn" else &"")
	if key != &"" and SpriteDB.has(key):
		var tx: Texture2D = SpriteDB.tex(key)
		if tx != null:
			c.draw_texture_rect(tx, Rect2(-R, -R, R * 2.0, R * 2.0), false)
			return
	var rock: Texture2D = SpriteDB.tex(ROCK_KEY)
	if rock == null:
		c.draw_circle(Vector2.ZERO, R, INK)
		return
	# 节奏满 / 宙斯在场时裂纹发金：黑底乘什么都还是黑，只有奶油色的裂纹被乘成金色
	var charged: bool = (sim.zeus_t > 0.0 and sim.phase == &"night") or (sim.phase == &"day" and sim.rhythm >= 10.0)
	c.draw_texture_rect(rock, Rect2(-_rock_c * k, Vector2(rock.get_size()) * k), false, Color(1.0, 0.8, 0.34) if charged else Color.WHITE)


## 石头贴图在方向 d（贴图坐标，y 朝下）上的轮廓半径（贴图像素，相邻采样线性插值）
func _rock_radius(d: Vector2) -> float:
	var n: int = _rock_r.size()
	var f: float = fposmod(d.angle(), TAU) / TAU * n
	var i: int = int(f) % n
	return lerpf(_rock_r[i], _rock_r[(i + 1) % n], f - floorf(f))


## 读石头贴图的轮廓：不透明区域的重心、72 个方向的半径；参考半径取 70% 分位（= 物理半径 R 对应的贴图半径）
func _rock_profile() -> void:
	var tex: Texture2D = SpriteDB.tex(ROCK_KEY)
	if tex == null:
		return
	# 取不到像素（无头模式）时按正圆处理
	_rock_c = tex.get_size() / 2.0
	_rock_ref = minf(tex.get_width(), tex.get_height()) * 0.45
	var img: Image = tex.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	var sum: Vector2 = Vector2.ZERO
	var cnt: float = 0.0
	for y: int in range(0, img.get_height(), 4):
		for x: int in range(0, img.get_width(), 4):
			if img.get_pixel(x, y).a > 0.5:
				sum += Vector2(x, y)
				cnt += 1.0
	if cnt <= 0.0:
		return
	_rock_c = sum / cnt
	var rs: PackedFloat32Array = []
	for i: int in 72:
		var d: Vector2 = Vector2.from_angle(TAU * i / 72.0)
		var r: float = 1.0
		while r < 4000.0:
			var q: Vector2i = Vector2i(_rock_c + d * r)
			if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height() or img.get_pixelv(q).a <= 0.5:
				break
			r += 2.0
		rs.append(r)
	_rock_r = rs
	var sorted: PackedFloat32Array = rs.duplicate()
	sorted.sort()
	_rock_ref = sorted[int(sorted.size() * 0.7)]


# ———————————————— 不染色层（金色、火光、提示）————————————————
func _draw_gold(c2: CanvasItem = null) -> void:
	var _pt: int = Prof.t()
	_draw_gold_impl(c2)
	Prof.add(&"world.gold", _pt)


func _draw_gold_impl(c2: CanvasItem) -> void:
	if sim == null or sim.world == null:
		return
	var c: CanvasItem = gold
	_draw_trail(c)
	_draw_cracks(c)
	_draw_seals(c)
	_draw_city_lamps(c, _vis_x())
	if chest_view != null and (sim.phase == &"night" or sim.phase == &"night_end"):
		chest_view.draw_world(c, sim, _vis_x(), t)
	if boons != null:
		boons.draw_gold(c, self, sim, _vis_x())
	if sim.phase == &"night":
		_draw_crit_ring(c)
	if sim.phase == &"day" and not sim.sis.is_empty() and is_nan(cine.x):
		_draw_prompt(c)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 夜里城中亮窗（= render.js drawObjects 的 LIT）：民居 / 别墅 / 神庙……精灵包围盒 35%–65% 高度处 1–3 盏，按各自延迟逐盏亮起
const LIT: Dictionary = {&"house": 2, &"villa": 3, &"temple": 2, &"market_stall": 1, &"granary": 1, &"treasury": 2, &"theater": 2,
	&"townhouse": 3, &"courtyard_house": 2, &"stoa": 4, &"gymnasium": 2, &"bathhouse": 3, &"fountain_house": 1, &"smithy": 1, &"bakery": 1,
	&"wine_shop": 2, &"potter_workshop": 1, &"textile_shop": 1, &"agora_stalls": 2, &"city_gate": 2, &"watchtower": 1}


static func _h2(sv: float, k: int) -> float:
	var x: float = sin(sv * 127.1 + k * 311.7) * 43758.5453
	return x - floorf(x)


func _draw_city_lamps(c: CanvasItem, vr: Vector2) -> void:
	var lamp_k: float = sim.night_k() if sim.is_night() or sim.phase == &"dusk" else 0.0
	if lamp_k <= 0.25:
		return
	var zs: float = 1.0 / maxf(0.01, cam.zoom.x)
	# 城镇繁荣度（city_levels.json 的 lamps）：越繁华，亮灯的人家越多
	var share: float = float(World.town_level(sim.content, sim.city_level).get("lamps", 1.0))
	_vis_sync()
	for v: ObjVis in _g_lamp.near(vr):
		var o: CrushObj = v.o
		if o.is_flat() or o.rise < 0.9 or o.x < vr.x or o.x > vr.y:
			continue
		var w: float = o.w * PPM
		var h: float = o.h * PPM
		# 每家几盏、各在哪、什么时候亮：只看物件自己，算一次
		if v.lamp_h < 0.0:
			v.lamp_h = _h2(o.s, 77)
			var nl: int = int(LIT[o.type])
			for i: int in mini(nl, 1 + int(floorf(_h2(o.s, 5) * nl))):
				v.lamp_on.append(0.3 + 0.55 * _h2(o.s, 40 + i))
				v.lamp_at.append(Vector2((_h2(o.s, 30 + i) - 0.5) * w * 0.55, -h * (0.35 + 0.3 * _h2(o.s, 50 + i))))
		if v.lamp_h > share or w / zs <= 6.0:
			continue
		_vis_prep(v)
		var g: Vector3 = v.fit
		c.draw_set_transform(p(g.x, g.y), -g.z, Vector2(-1.0 if o.flip else 1.0, 1.0))
		for i: int in v.lamp_on.size():
			var on: float = clampf((lamp_k - v.lamp_on[i]) / 0.12, 0.0, 1.0)
			if on <= 0.0:
				continue
			var lp: Vector2 = v.lamp_at[i]
			var a: float = on * 0.7 * (0.85 + 0.15 * sin(t * 1.2566 + o.s))
			var sz: float = (2.5 if w / zs > 30.0 else 2.0) * zs
			Glow.draw(c, lp, 6.0 * zs, Color(GOLD, a * 0.25))
			c.draw_rect(Rect2(lp - Vector2(sz, sz) / 2.0, Vector2(sz, sz)), Color(GOLD, a))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_trail(c: CanvasItem) -> void:
	var a: float = 0.0
	if sim.phase == &"night" or sim.phase == &"night_end":
		a = 1.0
	elif sim.phase == &"day":
		a = maxf(0.0, 1.0 - sim.day_t / 15.0) * 0.4
	if a <= 0.003 or sim.trail.is_empty():
		return
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 首尾相接的线段连成一条（run）；整条的线宽取最宽那段。只把看得见的那一截（两头各多留两个点，折角和端头都在画面外）换成折线
	var tr: Array[PackedFloat64Array] = sim.trail
	var n: int = tr.size()
	var vr: Vector2 = _vis_x()
	var z: float = maxf(0.05, cam.zoom.x)
	var col: Color = Color(GOLD, 0.32 * a)
	var k0: int = 0
	var lw: float = 1.5
	var ex: float = INF
	var ey: float = INF
	var vis_lo: int = -1
	var vis_hi: int = -1
	for k: int in n + 1:
		var seg: PackedFloat64Array = tr[k] if k < n else PackedFloat64Array()
		if k == n or absf(ex - seg[0]) > 1e-3 or absf(ey - seg[1]) > 1e-3:
			if k > k0 and vis_lo >= 0:
				_trail_run(c, k0, k, lw, vis_lo, vis_hi, z, col)
			if k == n:
				break
			k0 = k
			lw = 1.5
			vis_lo = -1
		lw = maxf(lw, seg[4] * PPM)
		if maxf(seg[0], seg[2]) >= vr.x and minf(seg[0], seg[2]) <= vr.y:
			if vis_lo < 0:
				vis_lo = k
			vis_hi = k
		ex = seg[2]
		ey = seg[3]


## 拖尾 sim.trail[k0, k1) 这一条里，线段 [vis_lo, vis_hi] 附近的那一截：每个点沿法线往下坡那侧挪半个线宽（贴着地表）
func _trail_run(c: CanvasItem, k0: int, k1: int, lw: float, vis_lo: int, vis_hi: int, z: float, col: Color) -> void:
	var tr: Array[PackedFloat64Array] = sim.trail
	# 点 j：0 = 第 k0 段的起点，j ≥ 1 = 第 k0 + j − 1 段的终点
	var m: int = k1 - k0
	var j0: int = maxi(0, vis_lo - k0 - 2)
	var j1: int = mini(m, vis_hi - k0 + 3)
	var b0: int = maxi(0, j0 - 1)
	var pts: PackedVector2Array = []
	for j: int in range(b0, mini(m, j1 + 1) + 1):
		pts.append(p(tr[k0][0], tr[k0][1]) if j == 0 else p(tr[k0 + j - 1][2], tr[k0 + j - 1][3]))
	var w: float = clampf(lw * z, 1.5, 5.0) / z
	var off: float = w / 2.0 + 0.5 / z
	var q: PackedVector2Array = []
	for j: int in range(j0, j1 + 1):
		var aa: Vector2 = pts[maxi(0, j - 1) - b0]
		var bb: Vector2 = pts[mini(m, j + 1) - b0]
		var tg: Vector2 = (bb - aa).normalized()
		var nrm: Vector2 = Vector2(-tg.y, tg.x)
		if nrm.y < 0.0:
			nrm = -nrm
		q.append(pts[j - b0] + nrm * off)
	c.draw_polyline(q, col, w, true)


func _draw_cracks(c: CanvasItem) -> void:
	var vr: Vector2 = _vis_x()
	_vis_sync()
	for v: ObjVis in _g_hill.near(vr):
		var o: CrushObj = v.o
		if o.state != CrushObj.State.CRACKED or o.x < vr.x or o.x > vr.y:
			continue
		_vis_prep(v)
		var g: Vector3 = v.fit
		# 裂纹折线只随裂度变：按裂度缓存
		if v.crack_k != o.dmg:
			v.crack_k = o.dmg
			v.gcrack.clear()
			var w: float = o.w * PPM
			var h: float = o.h * PPM
			var n: int = 2 + int(floorf(o.dmg * 6.0))
			# 画在山体后面的建筑：被山坡挡住的那几道裂纹不画（不然金线会透过岩体亮出来）
			var back: bool = _slope_back != null and v.back
			for i: int in n:
				var cx: float = sin(i * 12.9 + o.s) * 0.35 * w
				var cy: float = -h * (0.25 + 0.5 * absf(sin(i * 7.1 + o.s)))
				if back:
					var q: Vector2 = Vector2(cx, cy + h * 0.28).rotated(-g.z) / PPM
					if g.y - q.y < sim.world.y_at_x(g.x + q.x):
						continue
				v.gcrack.append(PackedVector2Array([Vector2(cx, cy), Vector2(cx + sin(i * 3.3) * w * 0.15, cy + h * 0.15), Vector2(cx + sin(i * 5.1) * w * 0.1, cy + h * 0.28)]))
		c.draw_set_transform(p(g.x, g.y), -g.z, Vector2.ONE)
		for pl: PackedVector2Array in v.gcrack:
			c.draw_polyline(pl, Color(GOLD_HI, 0.9), 2.0 / maxf(0.05, cam.zoom.x))


## 冥府之门封印（9 枚，上限 >9 时 11 枚）：历史上破过的留米色裂纹，撞门时依次点亮
func _draw_seals(c: CanvasItem) -> void:
	var gt: Dictionary = sim.gate
	if gt.is_empty():
		return
	# 门不在画面里就只走一遍变换（后面画的东西接着用这里留下的变换），不画（封印、门缝光、径向金光都在门宽 + 门高以内）
	var vr: Vector2 = _vis_x()
	var reach: float = float(gt["w"]) + float(gt["h"])
	var vis: bool = float(gt["x"]) + reach >= vr.x and float(gt["x"]) - reach <= vr.y
	var n: int = 11 if int(gt["max"]) > 9 else 9
	var rs: float = maxf(0.25, float(gt["w"]) * 0.022) * PPM
	var hit_t: float = gt["hit_t"]
	var seals: int = gt["seals"]
	var best: int = gt["best"]
	var night: bool = sim.night_k() > 0.5
	var ink: Color = Color("05070f") if night else INK
	var cream: Color = Color("c4d6ee") if night else LINE
	for i: int in n:
		var th: float = PI * (0.9 - 0.8 * clampf(float(i) / (n - 1), 0.0, 1.0))
		var u: float = 0.5 + 0.19 * cos(th)
		var vt: float = 0.565 - 0.175 * sin(th)
		var sx: float = float(gt["x"]) + (u - 0.5) * float(gt["w"])
		var sy: float = float(gt["h"]) * (1.0 - vt)
		var age: float = hit_t - i * SimGame.SEAL_GAP
		var lit: bool = hit_t >= 0.0 and i < seals and age >= 0.0
		var sc: float = 1.0 + 0.35 * (1.0 - age / 0.15) if lit and age < 0.15 else 1.0
		c.draw_set_transform(p(sx, sy), 0.0, Vector2(sc, sc))
		if not vis:
			continue
		if lit and age < 0.6:
			Glow.draw(c, Vector2.ZERO, rs * 3.2, Color(GOLD_HI, maxf(0.0, 1.0 - age / 0.6) * 0.8))
		c.draw_circle(Vector2.ZERO, rs, ink)
		c.draw_arc(Vector2.ZERO, rs * 0.78, 0.0, TAU, 20, GOLD if lit else cream, maxf(1.0, rs * 0.14))
		if lit:
			c.draw_polyline(PackedVector2Array([Vector2(-rs * 0.15, -rs), Vector2(rs * 0.1, -rs * 0.2), Vector2(-rs * 0.2, rs * 0.3), Vector2(rs * 0.05, rs)]), GOLD_HI, maxf(1.0, rs * 0.13))
		elif i < best:
			c.draw_polyline(PackedVector2Array([Vector2(-rs * 0.1, -rs * 0.95), Vector2(rs * 0.12, -rs * 0.15), Vector2(-rs * 0.15, rs * 0.35), Vector2(rs * 0.05, rs * 0.9)]), Color(cream, 0.85), maxf(0.8, rs * 0.1))
	# 夜里门缝的预期光
	if sim.phase == &"night" and hit_t < 0.0:
		var a: float = minf(0.6, 0.08 + 0.05 * float(gt["predict"]))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if vis:
			var top: Vector2 = p(float(gt["x"]), float(gt["h"]) * 0.63)
			var bot: Vector2 = p(float(gt["x"]), float(gt["h"]) * 0.015)
			c.draw_line(top, bot, Color(GOLD, a * 0.35), maxf(3.0, float(gt["w"]) * 0.018 * PPM))
			c.draw_line(top, bot, Color(GOLD, a), maxf(1.0, float(gt["w"]) * 0.004 * PPM))
	# 门缝打开：径向金光
	var op: float = float(gt["open"])
	if op > 0.001:
		c.draw_set_transform(p(float(gt["x"]), float(gt["h"]) * 0.28), 0.0, Vector2.ONE)
		if not vis:
			return
		var R: float = float(gt["h"]) * PPM * 0.75
		Glow.draw(c, Vector2.ZERO, R, Color(1.0, 0.94, 0.75, op))
		Glow.draw(c, Vector2.ZERO, R * 1.3, Color(GOLD_HI, op * 0.5))


func _draw_crit_ring(c: CanvasItem) -> void:
	var rg: Dictionary = sim.ring
	if rg.is_empty():
		return
	var b: Boulder = sim.stone
	var k: float = clampf(float(rg["t"]) / maxf(0.01, float(rg["dur"])), 0.0, 1.2)
	var R: float = b.r * PPM
	var rad: float = R * (2.4 - 1.4 * minf(1.0, k))
	var res: StringName = rg["result"]
	var col: Color = GOLD_HI if res == &"" else (GOLD_HI if res == &"perfect" else (GOLD if res == &"good" else Color(0.7, 0.4, 0.3)))
	c.draw_set_transform(_boulder_center(), 0.0, Vector2.ONE)
	c.draw_arc(Vector2.ZERO, rad, 0.0, TAU, 48, Color(col, 0.85), maxf(2.0, R * 0.05))
	c.draw_arc(Vector2.ZERO, R * 1.02, 0.0, TAU, 48, Color(GOLD, 0.35), maxf(1.0, R * 0.02))


## 头顶按键陶片（显示当前绑定的左右推键，默认 A / D）与肩旁体力环
func _draw_prompt(c: CanvasItem) -> void:
	var sis: Dictionary = sim.sis
	var ang: float = float(sis["ang"])
	var ca: float = cos(ang)
	var sa: float = sin(ang)
	var hx: float = float(sis["x"]) - (float(sis["h"]) + 0.9) * sa
	var hy: float = float(sis["y"]) + (float(sis["h"]) + 0.9) * ca
	var z: float = maxf(0.05, cam.zoom.x)
	var size: float = 34.0 / z
	var center: Vector2 = p(hx, hy)
	c.draw_set_transform(center, 0.0, Vector2.ONE)
	var font: Font = Fonts.cinzel(800)
	var alpha: float = float(sim.prompt["alpha"])
	if sim.exhausted > 0:
		var txt: String = Loc.t("world_view.hold", "顶住！")
		var f2: Font = Fonts.serif(800)
		var fs: int = int(26.0)
		var tw: float = f2.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x / z
		c.draw_set_transform(center, 0.0, Vector2(1.0 / z, 1.0 / z))
		c.draw_string_outline(f2, Vector2(-tw * z / 2.0, 0.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.8))
		c.draw_string(f2, Vector2(-tw * z / 2.0, 0.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, GOLD_HI if sim.brace_t > 0.0 else CREAM)
	elif not sim.stats.hold_push:
		var expect: StringName = sim.expect_key
		for side: int in [0, 1]:
			var key: StringName = &"L" if side == 0 else &"R"
			var on: bool = expect == key
			var miss: float = float(sim.prompt["miss_t"])
			var jx: float = sin(t * 60.0) * 4.0 * miss / 0.15 if on and miss > 0.0 else 0.0
			var hit: bool = float(sim.prompt["hit_t"]) > 0.0 and sim.prompt["hit_side"] == key
			var cx: float = (-0.55 if side == 0 else 0.55) * size * 1.25 + jx / z
			var r: Rect2 = Rect2(cx - size / 2.0, -size / 2.0, size, size)
			c.draw_set_transform(center, 0.0, Vector2.ONE)
			c.draw_rect(r, Color(INK, (0.92 if on else 0.45) * alpha))
			c.draw_rect(r, Color(GOLD if (on or hit) else Color("c8642a"), alpha * (1.0 if on else 0.5)), false, 2.0 / z)
			c.draw_set_transform(center + Vector2(cx, 0.0), 0.0, Vector2(1.0 / z, 1.0 / z))
			var s: String = Settings.short_label("push_left" if side == 0 else "push_right")
			var fs2: int = 24 if s.length() <= 1 else 14
			var sw: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
			c.draw_string(font, Vector2(-sw / 2.0, 9.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(GOLD_HI if on else CREAM, alpha * (1.0 if on else 0.5)))
	# 体力环（左肩后上方）
	var st: Stats = sim.stats
	if st.no_stamina or sim.stamina_alpha <= 0.01:
		return
	var rx: float = float(sis["x"]) - 0.9 * ca - 1.9 * sa
	var ry: float = float(sis["y"]) - 0.9 * sa + 1.9 * ca
	var frac: float = clampf(sim.stamina / st.stamina_max, 0.0, 1.0)
	var rr: float = 15.0 / z
	c.draw_set_transform(p(rx, ry), 0.0, Vector2.ONE)
	var ex: bool = sim.exhausted > 0
	c.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 32, Color(INK, 0.75 * sim.stamina_alpha), 5.0 / z)
	var col: Color = Color(0.55, 0.52, 0.48) if ex else (Color("ff8a6a") if frac < 0.25 else GOLD)
	c.draw_arc(Vector2.ZERO, rr, -PI / 2.0, -PI / 2.0 + TAU * frac, 32, Color(col, sim.stamina_alpha), 3.6 / z, true)
