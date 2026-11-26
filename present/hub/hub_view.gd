class_name HubView
extends Node2D
## 夜宴大厅（docs/v05/feast-hub.md）。布局全部在 hub.tscn 里（在编辑器里摆）：
##   SkyLayer/Sky（天空，HubSky）· Ambient（CanvasModulate = 冷月光）· Far / Strip* / Mid / Fg（HubParallax 视差层）·
##   Main（冥府之门、众神、道具、火盆 Fire*、吊灯 Lamp*、各种 PointLight2D、Queue 幽魂队列、Servant* 侍者、Helpers 帮手站位、Player）·
##   Stations（HubStation 站点：交谈 / 买卖 / 天亮）· Camera · UILayer/UI（提示、钱、标题）。
## 台词、说话人、天亮对话、操作提示在 content/hub/hub.json（文本，方便重写剧情）。
## 光照：黑绘的黑乘什么光都还是黑，只有米色刻线被照成暖金或冷蓝；幽魂、火焰、光晕用 unshaded 材质自发光。
## 加在 hub_flicker 组里的灯会闪烁（灯下名为 Halo 的光晕跟着一起闪）。
## 按键都走 Settings 里的动作（push_left / push_right / interact / overview；空格、回车也能交互）。
## 只读 sim；买东西走 ShopScreen → Pricing.buy。离开时发 left，由 main 开始下一天。用 HubView.create() 建。

signal left

const SCENE: String = "res://present/hub/hub.tscn"
const REF_H: float = 1080.0
const GHOST_COLOR: Color = Color(0.72, 0.86, 1.15, 0.95)

## 场景宽度（镜头右边界）
@export var width: float = 11800.0
## 地面高度（参考 1080 高）
@export var ground: float = 850.0
@export var walk_speed: float = 300.0
@export var run_speed: float = 600.0
## 三条道（docs/v05/art-bible.md 第 5 条）：后道（Main/Back：躺椅、矮桌、侍者）在场景里整体抬高、压暗；
## 中道（站着的神、摊位、排队的幽魂）脚踩 ground；西西弗斯走前道，比 ground 低这么多
@export var lane_front: float = 22.0
@export_group("前景淡出")
## 前景大物件（hub_fade 组，比如前景碎石丘）和西西弗斯重叠时淡到这个不透明度
@export_range(0.0, 1.0) var fade_alpha: float = 0.45
## 淡出 / 淡回的速度（每秒变化的不透明度）
@export var fade_speed: float = 3.0
## 西西弗斯的身体框：左右各这么宽、脚下再往下算这么多（脚边一圈也算挡）
@export var fade_half_width: float = 80.0
@export var fade_below_feet: float = 30.0
@export var fade_body_height: float = 400.0
@export_group("")

var sim: SimGame = null
var content: ContentDB = null
## 返回 true 时不响应移动和交互（main 的暂停菜单等界面开着）
var blocked: Callable = Callable()

## hub.json（台词、说话人、提示文字）
var cfg: Dictionary = {}
var player_x: float = 0.0
var facing: int = 1
## 当前靠近的站点 id（"" = 没有）
var near_id: String = ""
## 站点（从 Stations 下的 HubStation 收集）：{id, x, who, action, branches, title, sub, verb, range, name, py}
## 提喀的盘口从第几天开（之前只交谈）
const BET_DAY: int = 3
## 影子推演缓存 {sig, h}
var _bet_cache: Dictionary = {}
var stations: Array[Dictionary] = []
## 这一夜赫尔墨斯已经喊过你一次了
var warned: bool = false
var built: bool = false

var _cam: Camera2D
var _sky: HubSky
var _ui_layer: CanvasLayer
var _ui: Control
var _panel: Control = null
var _layers: Array[HubParallax] = []
var _main: Node2D
var _player: Node2D
## 西西弗斯的分部位骨骼（present/actors/sisyphus.tscn 的实例，名字 Player）；旧的逐帧精灵时为 null
var _rig: SisyphusRig = null
## 走过的总路程（骨骼走路按路程推进动画，脚不打滑）
var _walk_dist: float = 0.0
## 站着不动多久了（在火盆边站久了会坐下烤火）
var _idle_t: float = 0.0
## 火盆的 x（Main 下名字以 Fire 开头的节点）
var _fire_xs: PackedFloat32Array = []
## 站在火盆这么近、又站了这么久，就坐下烤火
const FIRE_NEAR: float = 260.0
const SIT_AFTER: float = 5.0
## 离任何一位神这么近就不坐（站着说话）
const SIT_CLEAR: float = 130.0
var _walk_min: float = 700.0
var _walk_max: float = 11000.0
var _flicker: Array[Dictionary] = []     # {light, base, ph, halo}
var _flicker_on: bool = true             # 夜宴光影"简"时火光不闪（apply_gfx）
var _queue: HubQueue = null
var _ghosts: Array[Dictionary] = []      # {node, halo, x, tx, a, ta, enter, ph, h}
var _queue_left: int = 0
var _queue_t: float = 0.0
var _queue_seq: int = 0
var _servants: Array[HubPatrol] = []
var _helpers: HubHelpers = null
var _helper_nodes: Array[Node] = []
## 西西弗斯身后那团压暗（Main/PlayerAura）：跟着他走，和他的相对高度按场景里摆的
var _aura: Node2D = null
var _aura_dy: float = 0.0
## 会淡出的前景物件：{node, rect（本地坐标里不透明像素的包围盒）}
var _faders: Array[Dictionary] = []
var _sparks: CPUParticles2D = null
var _forge_light: PointLight2D = null
var _forge_base: float = 0.0
var _spark_t: float = 0.0
## 会动的神（HubGod 实例）：每帧告诉他们西西弗斯在哪；说话 / 买东西时让对应的神做动作
var _gods: Array[HubGod] = []
## 锻造的光闪由赫菲斯托斯的锤子驱动（他的打铁循环发 struck）；没有这样的神时退回自己计时
var _forge_by_god: bool = false
var _modulate: CanvasModulate
var _prompt: PanelContainer
var _prompt_label: Label
var _marks: Dictionary = {}              # 站点 id → 金币标记（有买得起的东西）
var _money: Label
var _title: Control
var _talked: Dictionary = {}             # 站点 id → 本夜第几次交谈
## 神对今晚的反应（FeastReact）：今晚的情况、已经说过的站点、头顶的对话气泡
var react_ctx: Dictionary = {}
var _reacted: Dictionary = {}
var _talk_marks: Dictionary = {}
## 没有对话功能的人偶尔冒的气泡（排队的亡魂、门口等明天的帮手；台词在 hub.json 的 chatter）
var _chat: Array[Dictionary] = []        # {bubble, src}：src = 亡魂的字典，或帮手的 Sprite2D
var _chat_next: Array[Dictionary] = []   # 等着接话的 {src, text, t}
var _chat_t: float = 3.0
var _chat_used: Dictionary = {}
var _mark_t: float = 0.0
var _t: float = 0.0
## 进场预热的倒计时（prewarm_view）：2 = 下一帧缩小画全景，1 = 再下一帧回到正常镜头
var _overview_frames: int = 0
var _unshaded: Material = null
var _add_mat: Material = null


## 夜宴场景第一次加载后一直留着：每晚都要进，不留的话每晚收夜都要重新读盘、把近百张贴图再传一遍显卡（2026-10-16 实测收夜连卡十几帧）
static var _scene: PackedScene = null
## 白天的预热排过队了（warm_step）；快进夜宴时提到队首过了（preload_scene）
static var _warm_queued: bool = false
static var _scene_queued_front: bool = false


## 退出时放掉缓存的场景（main._exit_tree）
static func release_cache() -> void:
	_scene = null
	_warm_queued = false
	_scene_queued_front = false


static func create() -> HubView:
	if _scene == null:
		# 预热（AssetWarmer）已经把场景和依赖读进缓存时这里立刻拿到；还在读就等它读完；没排过队就同步读
		_scene = load(SCENE) as PackedScene
	return _scene.instantiate() as HubView


## 快要进夜宴了（撞冥府之门、收夜）而白天的预热还没轮到：把夜宴的依赖和场景本身提到 AssetWarmer 队首。
## 不自己另发后台请求：兼容渲染器下多个线程同时建贴图会崩（2026-10-16，开子线程加载夜宴场景时导出版约三分之一的局崩溃），
## 所有后台读取都走 AssetWarmer 这一条队列，同一时刻只有一个。重复调用无害
static func preload_scene() -> void:
	if _scene != null or _scene_queued_front:
		return
	_scene_queued_front = true
	var lst: PackedStringArray = warm_list()
	lst.append(SCENE)
	AssetWarmer.enqueue_front(lst)


## 白天每帧调一次（main._process）：夜宴的全部依赖（贴图、众神子场景……依赖在前）和西西弗斯的法线图排进 AssetWarmer，
## 一次只在后台读一个；队列读空后再请求场景本身（依赖都在缓存里，很快）。第一晚收夜时已全部就绪。
static func warm_step() -> void:
	if _scene != null or _warm_queued:
		return
	_warm_queued = true
	var lst: PackedStringArray = warm_list()
	lst.append(SCENE)
	AssetWarmer.enqueue(lst)


## 夜宴要预热的资源：场景依赖 + 西西弗斯的全部部件和法线图（骨骼人物在夜宴里才换上受光的 CanvasTexture，
## 法线图是 RigBuilder.canvas_texture 运行时按路径读的，不在场景依赖里；睡着的头、换手形这些部件也是运行时换）
const RIG_DIRS: PackedStringArray = ["res://assets/native/sis_parts", "res://assets/normals/sis_parts"]


static func warm_list() -> PackedStringArray:
	var out: PackedStringArray = AssetWarmer.collect_deps(SCENE)
	for dir: String in RIG_DIRS:
		for f: String in ResourceLoader.list_directory(dir):
			if f.ends_with(".png"):
				out.append(dir + "/" + f)
	return out


# ———————————————— 接上场景里的节点 ————————————————
func _ready() -> void:
	if not built:
		build()
	_cam.make_current()
	_snap()


## 找到场景里的各个节点、生成运行时才有的东西（排队的幽魂、帮手、提示标记）。不需要进场景树，测试里可以直接调。
func build() -> void:
	built = true
	cfg = content.hub
	_unshaded = load("res://present/hub/mat_unshaded.tres") as Material
	_add_mat = load("res://present/hub/mat_add.tres") as Material
	_sky = get_node("SkyLayer/Sky") as HubSky
	_modulate = get_node("Ambient") as CanvasModulate
	_main = get_node("Main") as Node2D
	_cam = get_node("Camera") as Camera2D
	_cam.limit_right = int(width)
	for c: Node in get_children():
		if c is HubParallax:
			_layers.append(c as HubParallax)
	_player = _main.get_node("Player") as Node2D
	_rig = _player as SisyphusRig
	if _rig != null:
		_rig.lit = true
	_fire_xs.clear()
	for c2: Node in _main.get_children():
		if String(c2.name).begins_with("Fire") and c2 is Node2D:
			_fire_xs.append((c2 as Node2D).position.x)
	player_x = _player.position.x
	_aura = _main.get_node_or_null("PlayerAura") as Node2D
	if _aura != null:
		_aura_dy = _aura.position.y - _player.position.y
	_faders.clear()
	for n3: Node in _all(self):
		var fs: Sprite2D = n3 as Sprite2D
		if fs != null and fs.is_in_group(&"hub_fade"):
			_faders.append({"node": fs, "rect": _opaque_rect(fs)})
	_walk_min = (_main.get_node("WalkMin") as Node2D).position.x
	_walk_max = (_main.get_node("WalkMax") as Node2D).position.x
	for n: Node in _all(self):
		var l: PointLight2D = n as PointLight2D
		if l != null and l.is_in_group(&"hub_flicker"):
			var halo: Sprite2D = l.get_node_or_null("Halo") as Sprite2D
			_flicker.append({"light": l, "base": l.energy, "ph": l.global_position.x * 0.013 + l.global_position.y * 0.007, "halo": halo})
		elif n is HubPatrol:
			_servants.append(n as HubPatrol)
	_forge_light = _main.get_node_or_null("ForgeLight") as PointLight2D
	if _forge_light != null:
		_forge_base = _forge_light.energy
	_sparks = _main.get_node_or_null("ForgeSparks") as CPUParticles2D
	_gods.clear()
	_forge_by_god = false
	for n2: Node in _all(_main):
		var god: HubGod = n2 as HubGod
		if god == null:
			continue
		_gods.append(god)
		if god.strike_at >= 0.0 and not _forge_by_god:
			_forge_by_god = true
			god.struck.connect(_forge_strike)
	_queue = _main.get_node_or_null("Queue") as HubQueue
	apply_gfx()
	_helpers = _main.get_node_or_null("Helpers") as HubHelpers
	_build_stations()
	_build_chips()
	_build_queue()
	rebuild_helpers()
	_build_ui()


## 精灵本地坐标里不透明像素的包围盒（读不到图像时退回整张贴图）
static func _opaque_rect(sp: Sprite2D) -> Rect2:
	var r: Rect2 = sp.get_rect()
	var ct: CanvasTexture = sp.texture as CanvasTexture
	var tex: Texture2D = ct.diffuse_texture if ct != null else sp.texture
	var u: Rect2i = SpriteDB.used_px(tex)   # 按贴图缓存（导出版读像素要从显卡读回来）
	if u.size == Vector2i.ZERO:
		return r
	var k: Vector2 = r.size / tex.get_size()
	return Rect2(r.position + Vector2(u.position) * k, Vector2(u.size) * k)


static func _all(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c: Node in n.get_children():
		out.append(c)
		out.append_array(_all(c))
	return out


## 关掉夜宴前调：立刻拿掉 CanvasModulate（不然 queue_free 之前那一帧山上的世界会被染成夜色）
func teardown() -> void:
	if _modulate != null and is_instance_valid(_modulate):
		remove_child(_modulate)
		_modulate.free()
		_modulate = null
	if _ui_layer != null and is_instance_valid(_ui_layer) and _ui_layer.get_parent() != self:
		_ui_layer.visible = false
		_ui_layer.queue_free()


## 运行时才建的精灵（幽魂、帮手、筹码）：原点在底边中点
func _sprite(key: StringName, h: float) -> Sprite2D:
	var s: Sprite2D = Sprite2D.new()
	s.texture = SpriteDB.tex(key)
	var sz: Vector2i = SpriteDB.size(key)
	if sz.y <= 0:
		sz = Vector2i(100, 100)
	var k: float = h / float(sz.y)
	s.scale = Vector2(k, k)
	s.offset = Vector2(0, -float(sz.y) / 2.0)
	return s


func _halo(parent: Node2D, pos: Vector2, rx: float, ry: float, c: Color, z: int) -> Sprite2D:
	var h: Sprite2D = Sprite2D.new()
	h.texture = Glow.tex()
	h.material = _add_mat
	h.position = pos
	h.scale = Vector2(rx / 64.0, ry / 64.0)
	h.z_index = z
	h.modulate = c
	parent.add_child(h)
	return h


## 提喀的盘口：碑上一根金线 = 昨天的纪录（占登顶高度的比例），众神的羊拐骨钉在 金线 × 倍数 的位置
func _build_chips() -> void:
	var st: HubStele = _main.get_node_or_null("Stele") as HubStele
	if st == null:
		return
	var line_f: float = 0.46
	if sim != null and content.tuning.summit > 0.0:
		line_f = clampf(sim.record / content.tuning.summit, 0.03, 0.95)
	var tw: float = float(SpriteDB.size(&"bet_stele").x)
	var k: float = st.scale.x
	var ln: Line2D = Line2D.new()
	var y: float = st.groove_y(line_f)
	ln.points = PackedVector2Array([Vector2(-tw * 0.32, y), Vector2(tw * 0.32, y)])
	ln.width = 3.0 / k
	ln.default_color = Palette.GOLD
	ln.z_index = 1
	ln.material = _unshaded
	st.add_child(ln)
	for i: int in st.chip_keys.size():
		var m: float = st.chip_mults[i] if i < st.chip_mults.size() else 1.0
		var ch: Sprite2D = _sprite(StringName(st.chip_keys[i]), st.chip_height / k)
		ch.position = Vector2(-tw * 0.12 if i % 2 == 0 else tw * 0.12, st.groove_y(line_f * m) + st.chip_height / k / 2.0)
		ch.z_index = 2
		st.add_child(ch)


# ———————————————— 幽魂 ————————————————
func _ghost(key: StringName, h: float, z: int) -> Dictionary:
	var sp: Sprite2D = _sprite(key, h)
	sp.z_index = z
	# 幽魂的图（gh_*）本来就朝左画：队伍往左走进冥府之门、面朝塔纳托斯的名册，不用翻
	sp.flip_h = false
	sp.material = _unshaded
	sp.modulate = GHOST_COLOR
	_main.add_child(sp)
	var halo: Sprite2D = _halo(_main, Vector2.ZERO, h * 0.42, h * 0.62, Color(0.55, 0.72, 1.0, 0.22), z - 1)
	return {"node": sp, "halo": halo, "ph": randf() * TAU, "h": h, "key": String(key)}


func _place_ghost(g: Dictionary, x: float, a: float) -> void:
	var sp: Sprite2D = g["node"]
	var bob: float = sin(_t * 1.6 + float(g["ph"])) * 3.0
	var y: float = _queue.position.y
	sp.position = Vector2(x, y + bob)
	sp.self_modulate.a = a
	var halo: Sprite2D = g["halo"]
	halo.position = Vector2(x, y - float(g["h"]) * 0.5 + bob)
	halo.self_modulate.a = a


## 今晚被碾死的人：工资条明细里所有活物的件数（演示 / 测试没有数据时给 6 个）
func souls_tonight() -> int:
	if sim == null or sim.last_night.is_empty():
		return 6
	var n: int = 0
	for e: Variant in sim.last_night.get("tally", []):
		var d: Dictionary = e
		var od: ObjDef = content.object_by_id.get(StringName(str(d.get("type", ""))))
		if od != null and od.living:
			n += int(d.get("n", 0))
	return n


func _slot_x(i: int) -> float:
	return _queue.position.x + float(i) * _queue.spacing


func _build_queue() -> void:
	if _queue == null:
		return
	var total: int = mini(souls_tonight(), _queue.max_souls)
	var first: int = mini(total, _queue.slots)
	_queue_left = total - first
	for i: int in first:
		var g: Dictionary = _ghost(_queue_key(), _queue.ghost_height, _queue.z_index)
		var x: float = _slot_x(i)
		g.merge({"x": x, "tx": x, "a": 1.0, "ta": 1.0, "enter": false})
		_ghosts.append(g)
		_place_ghost(g, x, 1.0)


func _queue_key() -> StringName:
	var keys: PackedStringArray = _queue.keys if not _queue.keys.is_empty() else PackedStringArray(["gh_shepherd"])
	var day: int = sim.day if sim != null else 1
	_queue_seq += 1
	return StringName(keys[(day * 7 + _queue_seq * 5) % keys.size()])


func _update_queue(dt: float) -> void:
	if _queue == null:
		return
	var into: float = _queue.position.x + _queue.into_x
	_queue_t += dt
	if _queue_t >= _queue.interval and not _ghosts.is_empty():
		_queue_t = 0.0
		var front: Dictionary = {}
		for g: Dictionary in _ghosts:
			if not bool(g["enter"]):
				front = g
				break
		if not front.is_empty():
			front["enter"] = true
			front["tx"] = into
			var i: int = 0
			for g: Dictionary in _ghosts:
				if not bool(g["enter"]):
					g["tx"] = _slot_x(i)
					i += 1
			if _queue_left > 0:
				_queue_left -= 1
				var ng: Dictionary = _ghost(_queue_key(), _queue.ghost_height, _queue.z_index)
				ng.merge({"x": _slot_x(i) + 60.0, "tx": _slot_x(i), "a": 0.0, "ta": 1.0, "enter": false})
				_ghosts.append(ng)
	var gone: Array[Dictionary] = []
	for g: Dictionary in _ghosts:
		var x: float = move_toward(float(g["x"]), float(g["tx"]), (80.0 if bool(g["enter"]) else 45.0) * dt)
		g["x"] = x
		var a: float = float(g["a"])
		if bool(g["enter"]):
			# 走进门洞时淡出
			a = clampf((x - into) / 260.0, 0.0, 1.0)
			if a <= 0.01:
				gone.append(g)
		else:
			a = move_toward(a, float(g["ta"]), dt * 0.8)
		g["a"] = a
		_place_ghost(g, x, a)
	for g: Dictionary in gone:
		(g["node"] as Node).queue_free()
		(g["halo"] as Node).queue_free()
		_ghosts.erase(g)


## 门口等明天的帮手（= 已经买下的众）：斯巴达推石，幽魂辅助；买了三头犬，门边睡着的那只就醒过来站到队里
func rebuild_helpers() -> void:
	for c: Node in _helper_nodes:
		c.queue_free()
	_helper_nodes.clear()
	if _helpers == null:
		return
	var st: Stats = sim.stats if sim != null else null
	var n_sp: int = mini(int(st.spartans) if st != null else 0, _helpers.max_each)
	var n_gh: int = mini(int(st.ghosts) if st != null else 0, _helpers.max_each)
	var dog_awake: bool = st != null and st.cerberus
	var x: float = _helpers.position.x
	var y: float = _helpers.position.y
	for i: int in n_sp:
		var sp: Sprite2D = _sprite(StringName(_helpers.spartans[i % _helpers.spartans.size()]), _helpers.helper_height)
		sp.position = Vector2(x, y)
		sp.set_meta("chat", "spartan")
		sp.set_meta("h", _helpers.helper_height)
		_main.add_child(sp)
		_helper_nodes.append(sp)
		x += _helpers.spacing
	for i: int in n_gh:
		var sp: Sprite2D = _sprite(StringName(_helpers.ghosts[i % _helpers.ghosts.size()]), _helpers.helper_height * 0.95)
		sp.position = Vector2(x, y)
		sp.set_meta("chat", "helper_ghost")
		sp.set_meta("h", _helpers.helper_height * 0.95)
		sp.material = _unshaded
		sp.modulate = GHOST_COLOR
		_main.add_child(sp)
		_helper_nodes.append(sp)
		x += _helpers.spacing
	var sleeping: Node2D = _main.get_node_or_null("SleepingDog") as Node2D
	if sleeping != null:
		sleeping.visible = not dog_awake
	if dog_awake:
		var dog: Sprite2D = _sprite(StringName(_helpers.dog_awake), _helpers.dog_height)
		dog.position = Vector2(x + 40.0, y)
		_main.add_child(dog)
		_helper_nodes.append(dog)


# ———————————————— 闲聊气泡（没有对话功能的人：自言自语，或者和旁边的人搭话） ————————————————
## 说话人头顶（世界坐标）；人已经走了（进门、帮手重建）返回 null
func _chat_head(src: Variant) -> Variant:
	if src is Dictionary:
		var g: Dictionary = src
		if not _ghosts.has(g) or bool(g.get("enter", false)) or float(g.get("a", 0.0)) < 0.5:
			return null
		return Vector2(float(g["x"]), _queue.position.y - float(g["h"]) * 1.02)
	var sp: Node2D = src as Node2D
	if sp == null or not is_instance_valid(sp) or not sp.is_inside_tree():
		return null
	return sp.position - Vector2(0.0, float(sp.get_meta("h", 300.0)) * 1.02)


## 头顶在屏幕里（留点边）的说话人
func _chat_on_screen(src: Variant) -> bool:
	var p: Variant = _chat_head(src)
	if p == null:
		return false
	var sp: Vector2 = _to_screen(p)
	var vp: Vector2 = get_viewport_rect().size if is_inside_tree() else Vector2(1920, REF_H)
	return sp.x > 120.0 and sp.x < vp.x - 120.0 and sp.y > 60.0 and sp.y < vp.y


## 这一类人的台词里挑一句今晚还没说过的（都说过了就重新来）
func _chat_line(kind: String) -> String:
	var lines: Array = (cfg.get("chatter", {}) as Dictionary).get(kind, [])
	var free: Array = lines.filter(func(t: Variant) -> bool: return not _chat_used.has(str(t)))
	if free.is_empty():
		free = lines
	if free.is_empty():
		return ""
	var t: String = str(free.pick_random())
	_chat_used[t] = true
	return t


func _chat_say(src: Variant, text: String) -> float:
	var life: float = clampf(2.6 + 0.09 * text.length(), 3.0, 6.0)
	var b: ChatterBubble = ChatterBubble.create(text, life)
	_ui.add_child(b)
	_chat.append({"bubble": b, "src": src})
	return life


func _update_chatter(dt: float) -> void:
	if _ui == null or (cfg.get("chatter", {}) as Dictionary).is_empty():
		return
	# 对话、商店开着时都收起来
	var hide: bool = _panel != null
	for c: Dictionary in _chat.duplicate():
		var b: ChatterBubble = c["bubble"]
		var p: Variant = _chat_head(c["src"])
		if hide or p == null or b.finished():
			b.queue_free()
			_chat.erase(c)
			continue
		b.place(_to_screen(p))
	for n: Dictionary in _chat_next.duplicate():
		n["t"] = float(n["t"]) - dt
		if float(n["t"]) <= 0.0:
			_chat_next.erase(n)
			if not hide and _chat_head(n["src"]) != null:
				_chat_say(n["src"], str(n["text"]))
	if hide:
		_chat_next.clear()
		return
	_chat_t -= dt
	if _chat_t > 0.0 or _chat.size() >= 2 or not _chat_next.is_empty():
		return
	_chat_t = randf_range(4.0, 8.0)
	# 镜头里、没在说话的人
	var busy: Array = _chat.map(func(c: Dictionary) -> Variant: return c["src"])
	var cands: Array = []
	for g: Dictionary in _ghosts:
		if not busy.has(g) and _chat_on_screen(g):
			cands.append(g)
	for nd: Node in _helper_nodes:
		if nd.has_meta("chat") and not busy.has(nd) and _chat_on_screen(nd):
			cands.append(nd)
	if cands.is_empty():
		return
	var src: Variant = cands.pick_random()
	if src is Dictionary:
		# 排队的亡魂：有时和后面那个搭话，有时按自己的身份嘀咕，不然说排队的闲话
		var i: int = _ghosts.find(src)
		var nb: Dictionary = _ghosts[i + 1] if i + 1 < _ghosts.size() else {}
		var pairs: Array = (cfg.get("chatter", {}) as Dictionary).get("pairs", [])
		if not nb.is_empty() and _chat_on_screen(nb) and not pairs.is_empty() and randf() < 0.35:
			var pr: Array = pairs.pick_random()
			var life: float = _chat_say(src, str(pr[0]))
			_chat_next.append({"src": nb, "text": str(pr[1]), "t": life * 0.7})
			return
		var own: String = _chat_line(str((src as Dictionary).get("key", ""))) if randf() < 0.55 else ""
		var text: String = own if own != "" else _chat_line("ghost")
		if text != "":
			_chat_say(src, text)
		return
	var text2: String = _chat_line(str((src as Node).get_meta("chat")))
	if text2 != "":
		_chat_say(src, text2)


# ———————————————— 西西弗斯与镜头 ————————————————
func _place_player(dir: float) -> void:
	_player.position = Vector2(player_x, ground + lane_front)
	if _aura != null:
		_aura.position = Vector2(player_x, _player.position.y + _aura_dy)
	if dir != 0.0:
		facing = 1 if dir > 0.0 else -1
	if _rig != null:
		_rig.scale.x = absf(_rig.scale.x) * float(facing)
		if dir != 0.0:
			_idle_t = 0.0
			_rig.set_phase(&"walk", _walk_dist / maxf(1.0, _rig.walk_stride * absf(_rig.scale.y)))
		elif _panel != null:
			_rig.play_state(&"talk")
		elif _idle_t > SIT_AFTER and _near_fire():
			_rig.play_state(&"sit_fire", 0.6)
		else:
			_rig.play_state(&"idle", 0.35)
		return
	var sprite: AnimatedSprite2D = _player as AnimatedSprite2D
	if sprite == null:
		return
	sprite.flip_h = facing < 0
	var anim: StringName = &"walk" if dir != 0.0 else &"idle"
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(anim) and sprite.animation != anim:
		sprite.play(anim)


## 火盆边、又不和哪位神叠在一起（坐下去会和坐着的赫斯提亚、哈迪斯糊成一团）才坐
func _near_fire() -> bool:
	for god: HubGod in _gods:
		if absf(god.global_position.x - player_x) < SIT_CLEAR:
			return false
	for fx: float in _fire_xs:
		if absf(fx - player_x) < FIRE_NEAR:
			return true
	return false


## 走一步（dir = -1 / 0 / 1）；夹在 WalkMin..WalkMax 之间
func step(dt: float, dir: float, run: bool = false) -> void:
	var x0: float = player_x
	player_x = clampf(player_x + dir * (run_speed if run else walk_speed) * dt, _walk_min, _walk_max)
	_walk_dist += absf(player_x - x0)
	if dir == 0.0:
		_idle_t += dt
	_place_player(dir if player_x != x0 else 0.0)


## 自动驾驶 / 测试：直接把西西弗斯放到 x，镜头跟过去
func teleport(x: float) -> void:
	player_x = x
	_place_player(0.0)
	_snap()


## 画质（设置 → 画面 → 夜宴光影 Settings.light_level）：
##   简 = 不用法线图（立体受光，每盏灯每个像素多一次采样）、火光不闪、光晕藏掉、火星 / 余烬 / 烟粒子减到四成；
##   中 = 法线图照旧、粒子七成；全 = 原样。只改各节点自己的属性（原值记在 meta 里），不动共享的贴图资源，切回来能还原。
## 建好时调一次；夜宴里改设置时 main 再调。
func apply_gfx() -> void:
	var lv: int = clampi(Settings.light_level, 0, 2)
	_flicker_on = lv > 0
	for n: Node in _all(self):
		var ci: CanvasItem = n as CanvasItem
		if ci == null:
			continue
		if n is CPUParticles2D:
			var cp: CPUParticles2D = n as CPUParticles2D
			if not cp.has_meta(&"gfx_amount"):
				cp.set_meta(&"gfx_amount", cp.amount)
			var want: int = maxi(1, roundi(int(cp.get_meta(&"gfx_amount")) * [0.4, 0.7, 1.0][lv]))
			if cp.amount != want:
				cp.amount = want
			continue
		if n is Sprite2D or n is Polygon2D:
			var tex: Texture2D = ci.get("texture") as Texture2D
			if lv == 0:
				var ct: CanvasTexture = tex as CanvasTexture
				if ct != null and ct.normal_texture != null:
					ci.set_meta(&"gfx_ct", ct)
					ci.set("texture", ct.diffuse_texture)
			elif ci.has_meta(&"gfx_ct"):
				ci.set("texture", ci.get_meta(&"gfx_ct"))
				ci.remove_meta(&"gfx_ct")
	for f: Dictionary in _flicker:
		var halo: Variant = f["halo"]
		if halo != null and is_instance_valid(halo):
			(halo as Sprite2D).visible = lv > 0
		if lv == 0:
			(f["light"] as PointLight2D).energy = float(f["base"])


## 盖着黑幕时调：下一帧把整个大厅缩小画出来，再下一帧镜头回到西西弗斯身上。第一次画到的材质 / 灯光组合要现编着色器
## （导出版在新机器上第一次启动时，一次几十到几百毫秒），趁黑幕编完，之后走到大厅另一头不再卡
func prewarm_view() -> void:
	_overview_frames = 2


func _snap() -> void:
	if _cam == null:
		return
	_cam.position = Vector2(player_x, REF_H / 2.0)
	if _cam.is_inside_tree():
		_cam.reset_smoothing()
	_update_parallax()


func _update_parallax() -> void:
	var c: float = _cam.get_screen_center_position().x if _cam.is_inside_tree() else player_x
	for l: HubParallax in _layers:
		l.apply(c)
	if _sky != null:
		# 黎明：从 dawn_from 处开始，到镜头能走到的最右边（width - 半屏）时完全天亮
		var half: float = (get_viewport_rect().size.x / maxf(0.01, _cam.zoom.x) if is_inside_tree() else 1920.0) / 2.0
		var x0: float = _sky.dawn_from * width
		var p: float = clampf((c - x0) / maxf(1.0, width - half - x0), 0.0, 1.0)
		_sky.dawn = p * p * (3.0 - 2.0 * p)
		_sky.scroll = c


# ———————————————— 站点与交互 ————————————————
func _build_stations() -> void:
	stations.clear()
	var holder: Node = get_node_or_null("Stations")
	if holder == null:
		return
	for c: Node in holder.get_children():
		var s: HubStation = c as HubStation
		if s == null:
			continue
		stations.append({"id": s.id, "x": s.position.x, "who": s.who, "action": s.action, "branches": s.branches, "title": s.title,
			"sub": s.subtitle, "verb": s.verb, "range": s.trigger_range, "name": s.display_name, "py": s.prompt_height, "until_moira": s.until_moira})


## 这个站点今晚有没有还没说的反应（离场的赫利俄斯不说，免得挡着天亮）
func pending_react(st: Dictionary) -> Dictionary:
	var id: String = str(st.get("id", ""))
	if id == "" or _reacted.has(id) or str(st.get("action", "")) == "exit":
		return {}
	return FeastReact.pick(cfg.get("react", []), id, str(st.get("who", "")), react_ctx)


## 这个站点现在是不是还只能交谈（shop 摊在摇到命运之前；提喀的盘口第 3 天起才开）
func talk_only(st: Dictionary) -> bool:
	var act: String = str(st.get("action", ""))
	if act == "bet":
		return sim == null or sim.day < BET_DAY
	return act != "shop" or (bool(st.get("until_moira", false)) and (sim == null or not ShopScreen.moira_open(sim)))


## 离 x 最近、又在范围内的站点（没有返回空字典）
func station_at(x: float) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = INF
	for s: Dictionary in stations:
		var d: float = absf(float(s["x"]) - x)
		if d <= float(s["range"]) and d < bd:
			bd = d
			best = s
	return best


func station(id: String) -> Dictionary:
	for s: Dictionary in stations:
		if str(s["id"]) == id:
			return s
	return {}


## 这几支（空 = 全部）里有没有现在买得起的节点
func affordable(branches: Array = []) -> bool:
	if sim == null:
		return false
	for n: NodeDef in content.nodes:
		if not branches.is_empty() and not branches.has(String(n.br)):
			continue
		if not Pricing.can_level(content, n, sim.levels, sim.stats):
			continue
		if Pricing.affordable(content, n, int(sim.levels.get(String(n.key), 0)), sim.stats, sim.money, sim.moira):
			return true
	return false


func _is_blocked() -> bool:
	return _panel != null or (blocked.is_valid() and bool(blocked.call()))


func _unhandled_input(ev: InputEvent) -> void:
	if handle_input(ev):
		get_viewport().set_input_as_handled()


## 交互 / 全场速览键。游戏里夜宴放在 GameViewport 子视口里收不到输入事件，由 main 转过来；返回 true = 用掉了这个事件
func handle_input(ev: InputEvent) -> bool:
	if not (ev is InputEventKey or ev is InputEventMouseButton) or not ev.is_pressed() or ev.is_echo() or _is_blocked():
		return false
	if ev.is_action_pressed(&"interact") or ev.is_action_pressed(&"strike") or ev.is_action_pressed(&"end_day"):
		interact()
		return true
	if ev.is_action_pressed(&"overview"):
		open_overview()
		return true
	return false


## main 把夜宴放进按渲染分辨率缩放的子视口；界面层（提示、金币标记、对话、商店）挪到 to（主视口）下：
## 文字保持原生分辨率、按钮收得到鼠标。坐标照旧用 _to_screen（子视口的画布变换是逻辑坐标，和主视口一致）
func detach_ui(to: Node) -> void:
	if _ui_layer != null and is_instance_valid(_ui_layer) and _ui_layer.get_parent() == self:
		_ui_layer.reparent(to, false)


func _notification(what: int) -> void:
	# 挪出去的界面层不是自己的子节点，夜宴释放时要一起释放
	if what == NOTIFICATION_PREDELETE and _ui_layer != null and is_instance_valid(_ui_layer) and _ui_layer.get_parent() != self:
		_ui_layer.queue_free()


func interact() -> void:
	var st: Dictionary = station_at(player_x)
	if st.is_empty():
		return
	Sfx.play(&"click")
	_face(st)
	# 今晚的事有话要说：先说这一句（每个站点每夜一次），下次再按才照常交谈 / 开店
	var rx: Dictionary = pending_react(st)
	if not rx.is_empty():
		_reacted[str(st["id"])] = true
		_react(st)
		_dialog([_page(str(st.get("who", "")), str(rx["text"]))], [], func(_i: int) -> void: pass)
		return
	match str(st.get("action", "talk")):
		"shop":
			if talk_only(st):
				_talk(st)
			else:
				_open_shop(st)
		"bet":
			if talk_only(st):
				_talk(st)
			else:
				_open_bet(st)
		"exit":
			try_leave()
		_:
			_talk(st)


func _open_panel(c: Control) -> void:
	_close_panel()
	_panel = c
	_ui_layer.add_child(c)
	_prompt.visible = false


func _close_panel() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null
	rebuild_helpers()
	_mark_t = 0.0


func _open_shop(st: Dictionary) -> void:
	_react(st)
	var sh: ShopScreen = ShopScreen.create()
	sh.sim = sim
	sh.mode = &"station"
	sh.branches = PackedStringArray(st.get("branches", []))
	sh.title = str(st.get("title", "")) if str(st.get("title", "")) != "" else str(st.get("name", ""))
	sh.subtitle = str(st.get("sub", ""))
	sh.closed.connect(_close_panel)
	_open_panel(sh)


## Tab：所有摊位的东西摆在一张表上，不用走路也能买完直接天亮
func open_overview() -> void:
	if sim == null:
		return
	var sh: ShopScreen = ShopScreen.create()
	sh.sim = sim
	sh.mode = &"overview"
	sh.title = Loc.t("hub_view.overview", "全场速览")
	sh.subtitle = Loc.t("hub_view.browse_every_stall_here", "各摊的东西都在这里（三女神的要去火堆旁找她们）")
	sh.closed.connect(_close_panel)
	sh.start_pressed.connect(leave_now)
	_open_panel(sh)


func _page(who: String, text: String) -> Dictionary:
	if who == "":
		return {"who": "", "text": text}
	var sp: Dictionary = (cfg.get("speakers", {}) as Dictionary).get(who, {})
	return {"who": who, "name": str(sp.get("name", who)), "greek": str(sp.get("greek", "")), "portraits": sp.get("portraits", []),
		"initial": str(sp.get("initial", "?")), "text": text}


func _fill(text: String) -> String:
	var day: int = sim.day if sim != null else 1
	var money: float = sim.money if sim != null else 0.0
	return text.replace("{n}", str(104729 + day * 3)).replace("{money}", NumFmt.fmt(money))


## 这一夜和这个站点的第几次交谈 → 台词（按天数轮换，同一夜再问换下一句）
func talk_line(id: String, who: String) -> String:
	var talk: Dictionary = cfg.get("talk", {})
	var lines: Array = talk.get(id, talk.get(who, []))
	if lines.is_empty():
		return "……"
	var n: int = int(_talked.get(id, 0))
	var day: int = sim.day if sim != null else 1
	return _fill(str(lines[(day + n + id.hash() % 7) % lines.size()]))


## 锤子落下：炉光一闪（火星由神像场景自己的特效出；没有会打铁的神时用场景里的 ForgeSparks）
func _forge_strike() -> void:
	_spark_t = 0.0
	if not _forge_by_god and _sparks != null:
		_sparks.restart()
		_sparks.emitting = true


## 说话 / 买东西时转身面朝站点对应的神（站点多半摆在神的一侧，免得西西弗斯整个挡在神前面）
func _face(st: Dictionary) -> void:
	var who: String = str(st.get("who", ""))
	if who == "":
		return
	for god: HubGod in _gods:
		if god.who == who:
			var dx: float = god.global_position.x - player_x
			if absf(dx) > 24.0:
				facing = 1 if dx > 0.0 else -1
				_place_player(0.0)
			return


## 让站点对应的神做说话动作
func _react(st: Dictionary) -> void:
	var who: String = str(st.get("who", ""))
	if who == "":
		return
	for god: HubGod in _gods:
		if god.who == who:
			god.react()


func _talk(st: Dictionary) -> void:
	_react(st)
	var id: String = str(st["id"])
	var who: String = str(st.get("who", ""))
	# 提喀开盘前：专门说一句什么时候开、押的是什么（hub.json 的 <站点>_soon）
	var key: String = id + "_soon" if str(st.get("action", "")) == "bet" and (cfg.get("talk", {}) as Dictionary).has(id + "_soon") else id
	var text: String = talk_line(key, who)
	_talked[id] = int(_talked.get(id, 0)) + 1
	_dialog([_page(who, text)], [], func(_i: int) -> void: pass)


func _dialog(pages: Array, choices: Array, done: Callable) -> void:
	var m: ModalRequest = ModalRequest.new()
	m.kind = ModalRequest.Kind.DIALOG
	m.payload = {"pages": pages, "choices": choices}
	m.n_choices = choices.size()
	var dp: DialogPanel = DialogPanel.create()
	dp.setup(m)
	dp.answered.connect(func(i: int) -> void:
		_close_panel()
		done.call(i)
		)
	_open_panel(dp)


## 赫利俄斯：确认天亮。还有买得起的东西时，赫尔墨斯先喊住你一次（每夜一次）
func try_leave() -> void:
	var ex: Dictionary = cfg.get("exit", {})
	if not warned and affordable():
		warned = true
		var pages: Array = []
		for l: Variant in ex.get("hermes_warn", []):
			pages.append(_page("hermes", _fill(str(l))))
		_dialog(pages, ex.get("hermes_choices", [{"label": Loc.t("hub_view.take_another_look", "回去看看")}, {"label": Loc.t("hub_view.let_sun_rise", "天亮吧")}]), func(i: int) -> void:
			if i == 1:
				leave_now()
			)
		return
	var pages2: Array = []
	for l: Variant in ex.get("helios", [Loc.t("hub_view.nearly_dawn", "天要亮了。")]):
		pages2.append(_page("helios", _fill(str(l))))
	_dialog(pages2, ex.get("confirm", [{"label": Loc.t("hub_view.let_sun_rise", "天亮吧")}, {"label": Loc.t("hub_view.stay_little_longer", "再待一会儿")}]), func(i: int) -> void:
		if i == 0:
			leave_now()
		)


## 提喀的盘口：影子推演一天（同一夜、同一份天赋只算一次）
func _bet_h_bot() -> float:
	var sig: String = _bet_sig()
	if str(_bet_cache.get("sig", "")) != sig:
		_bet_cache = {"sig": sig, "h": ShadowDay.run(content, sim.persist(), sim.meta)}
	return float(_bet_cache["h"])


## 影子推演依赖的东西：哪一天、天赋等级、点亮的祭坛
func _bet_sig() -> String:
	return "%d|%s|%d" % [sim.day, str(sim.levels.hash()), sim.boons.done.size()]


func _open_bet(st: Dictionary) -> void:
	_react(st)
	var bs: BetScreen = BetScreen.create()
	bs.sim = sim
	bs.h_bot = _bet_h_bot()
	bs.closed.connect(_close_panel)

	_open_panel(bs)


## 天亮封盘：押注之后又买了东西，赔率按现在的属性重算（提喀把你的骨头挪一挪）；封过的标 sealed（SimGame 开工时核对）
func _seal_bet() -> void:
	if sim == null or sim.bet.is_empty():
		return
	if str(sim.bet.get("lv", "")) == sim.levels_sig():
		sim.bet["sealed"] = true
		return
	var h_bot: float = _bet_h_bot()
	var m: Dictionary = BetOdds.model(h_bot, sim.run_stats.get("bet_hist", []))
	var o: float = BetOdds.odds(float(sim.bet["h"]), float(m["mu"]), float(m["s"]), sim.record, sim.record * sim.stats.start_frac)
	var old: float = float(sim.bet["odds"])
	sim.note_bet_pred(sim.day, h_bot)
	if o <= 0.0:
		sim.cancel_bet()
		sim.fx.toast(Loc.t("hub_view.tyche_returns_stake_all", "提喀把赌本退给你：你买了那么多东西，这个高度已经不开盘了。"), 4.0)
		return
	sim.bet["odds"] = o
	sim.bet["lv"] = sim.levels_sig()
	sim.bet["sealed"] = true
	if absf(o - old) >= 0.01:
		sim.fx.toast(Loc.t("hub_view.tyche_shifts_bone_marker", "提喀把你的骨头挪了挪：赔率 %s → %s") % [Js.to_fixed(old, 2), Js.to_fixed(o, 2)], 4.0)


func leave_now() -> void:
	_seal_bet()
	_close_panel()
	Sfx.play(&"sunriseDrone")
	left.emit()


# ———————————————— 界面（提示、金币标记、标题；在 UILayer/UI 里摆） ————————————————
func _build_ui() -> void:
	_ui_layer = get_node("UILayer") as CanvasLayer
	_ui = _ui_layer.get_node("UI") as Control
	_prompt = _ui.get_node("Prompt") as PanelContainer
	_prompt_label = _prompt.get_node("Label") as Label
	_prompt.visible = false
	for s: Dictionary in stations:
		if str(s.get("action", "")) != "shop":
			continue
		var mk: Control = _coin_mark(str(s["id"]) == "hermes")
		mk.visible = false
		_ui.add_child(mk)
		_marks[str(s["id"])] = mk
	react_ctx = FeastReact.context(sim) if sim != null else {}
	for s2: Dictionary in stations:
		if pending_react(s2).is_empty():
			continue
		var tm: Control = _talk_mark()
		tm.visible = false
		_ui.add_child(tm)
		_talk_marks[str(s2["id"])] = tm
	_money = _ui.get_node("MoneyRow/Money") as Label
	var hint: Label = _ui.get_node("Hint") as Label
	hint.text = hint_text()
	Settings.bindings_changed.connect(func() -> void: if is_instance_valid(hint): hint.text = hint_text())
	_title = _ui.get_node("Title") as Control
	var tc: Dictionary = cfg.get("title", {})
	var day: int = sim.day - 1 if sim != null else 1
	(_title.get_node("Head") as Label).text = Loc.t("hub_view.night", "%s · 第 %d 夜") % [str(tc.get("head", Loc.t("hub_view.f_e_s_t", "夜 宴"))), maxi(1, day)]
	(_title.get_node("Sub") as Label).text = str(tc.get("sub", ""))


## 底部操作提示：hub.json 的 hint 里 {left} {right} {interact} {overview} 换成当前绑定的键
func hint_text() -> String:
	return str(cfg.get("hint", "")).replace("{left}", Settings.short_label("push_left")).replace("{right}", Settings.short_label("push_right")) \
		.replace("{interact}", Settings.short_label("interact")).replace("{overview}", Settings.short_label("overview"))


## 神头顶的对话气泡（今晚的事有话要说）：奶白底、三个墨点
func _talk_mark() -> Control:
	var c: Control = Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = Vector2(42.0, 35.0)
	c.draw.connect(func() -> void:
		var body: Rect2 = Rect2(Vector2(1.0, 1.0), Vector2(40.0, 26.0))
		Glow.draw(c, body.get_center(), 44.0, Color(Palette.GOLD, 0.3))
		c.draw_rect(body, Palette.CREAM)
		c.draw_rect(body, UiKit.INK, false, 2.0)
		c.draw_colored_polygon(PackedVector2Array([Vector2(11.0, 26.5), Vector2(21.0, 26.5), Vector2(10.0, 34.0)]), Palette.CREAM)
		for i: int in 3:
			c.draw_circle(Vector2(12.0 + 9.0 * i, 14.0), 2.8, UiKit.INK)
		)
	return c


## 摊位上方的小金币（有买得起的东西）；赫尔墨斯那枚大一号，带感叹号
func _coin_mark(big: bool) -> Control:
	var c: Control = Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r: float = 17.0 if big else 11.0
	c.size = Vector2(r * 2.0, r * 2.0)
	c.draw.connect(func() -> void:
		var ctr: Vector2 = Vector2(r, r)
		Glow.draw(c, ctr, r * 2.4, Color(Palette.GOLD, 0.35))
		c.draw_circle(ctr, r, Palette.GOLD)
		c.draw_arc(ctr, r * 0.72, 0.0, TAU, 24, Color(UiKit.INK, 0.6), 1.5)
		if big:
			c.draw_line(ctr + Vector2(0, -r * 0.45), ctr + Vector2(0, r * 0.15), UiKit.INK, 3.0)
			c.draw_circle(ctr + Vector2(0, r * 0.42), 2.2, UiKit.INK)
		)
	return c


func _to_screen(p: Vector2) -> Vector2:
	if not is_inside_tree():
		return p
	return get_viewport().get_canvas_transform() * p


func _update_ui(dt: float) -> void:
	if _ui == null:
		return
	if sim != null:
		_money.text = NumFmt.fmt(sim.money)
		var mo: bool = ShopScreen.moira_open(sim)
		var row: Node = _money.get_parent()
		# 商店 / 对话面板开着时它们自己显示钱，夜宴这一栏藏起来（不然从面板的半透明底下透出一个重影）
		(row as CanvasItem).visible = _panel == null
		(row.get_node("Moira") as Label).visible = mo
		(row.get_node("MoiraUnit") as Label).visible = mo
		(row.get_node("Moira") as Label).text = NumFmt.fmt(sim.moira)
	if _title != null:
		_title.modulate.a = clampf(1.0 - (_t - 3.0) / 1.2, 0.0, 1.0) * clampf(_t / 0.6, 0.0, 1.0)
	var st: Dictionary = station_at(player_x)
	near_id = str(st.get("id", ""))
	_prompt.visible = not st.is_empty() and _panel == null
	if _prompt.visible:
		var verb: String = Loc.t("hub_view.talk", "交谈") if str(st.get("action", "")) in ["shop", "bet"] and talk_only(st) else (str(st.get("verb", "")) if str(st.get("verb", "")) != "" else Loc.t("hub_view.talk", "交谈"))
		_prompt_label.text = "%s   %s · %s" % [Settings.short_label("interact"), verb, str(st.get("name", ""))]
		_prompt.reset_size()
		var sp: Vector2 = _to_screen(Vector2(float(st["x"]), ground - float(st.get("py", 430))))
		_prompt.position = sp - Vector2(_prompt.size.x / 2.0, _prompt.size.y)
	# 摊位金币：每 0.5 秒刷新一次（买得起 = 这一支里有能升的节点且钱够）
	_mark_t -= dt
	if _mark_t <= 0.0:
		_mark_t = 0.5
		for s: Dictionary in stations:
			var id: String = str(s["id"])
			if _marks.has(id):
				(_marks[id] as Control).set_meta("on", not talk_only(s) and affordable(s.get("branches", [])))
	for id: String in _talk_marks:
		var tm: Control = _talk_marks[id]
		var s3: Dictionary = station(id)
		tm.visible = not _reacted.has(id) and _panel == null
		if tm.visible:
			var sp3: Vector2 = _to_screen(Vector2(float(s3["x"]), ground - float(s3.get("py", 430)) - (64.0 if near_id == id else 14.0)))
			tm.position = sp3 - tm.size / 2.0 + Vector2(0, sin(_t * 3.0 + 1.0) * 3.0)
			tm.queue_redraw()
	for id: String in _marks:
		var mk: Control = _marks[id]
		var s: Dictionary = station(id)
		# 有话要说时先显示对话气泡，金币等说完再出来
		var on: bool = bool(mk.get_meta("on", false)) and _panel == null and not (_talk_marks.has(id) and not _reacted.has(id))
		var sp: Vector2 = _to_screen(Vector2(float(s["x"]), ground - float(s.get("py", 430)) - (64.0 if near_id == id else 14.0)))
		mk.visible = on
		mk.position = sp - mk.size / 2.0 + Vector2(0, sin(_t * 3.0) * 3.0)
		mk.queue_redraw()


# ———————————————— 每帧 ————————————————
func _process(dt: float) -> void:
	_t += dt
	if not built:
		return
	var dir: float = 0.0
	if not _is_blocked():
		if Input.is_action_pressed(&"push_right"):
			dir += 1.0
		if Input.is_action_pressed(&"push_left"):
			dir -= 1.0
	step(dt, dir, Input.is_key_pressed(KEY_SHIFT))
	_cam.position = Vector2(player_x, REF_H / 2.0)
	var vp: Vector2 = get_viewport_rect().size if is_inside_tree() else Vector2(1920, REF_H)
	var z: float = vp.y / REF_H
	_cam.zoom = Vector2(z, z)
	if _overview_frames > 0:
		_overview_frames -= 1
		var zz: float = vp.x / width
		_cam.zoom = Vector2(zz, zz)
		_cam.position = Vector2(width / 2.0, REF_H / 2.0)
		_cam.reset_smoothing()
		if _overview_frames == 0:
			_cam.zoom = Vector2(z, z)
			_snap()
	_update_parallax()
	if _flicker_on:
		for f: Dictionary in _flicker:
			var ph: float = float(f["ph"])
			var k: float = 1.0 + 0.07 * sin(_t * 7.3 + ph) + 0.05 * sin(_t * 13.1 + ph * 2.0) + 0.03 * sin(_t * 23.7 + ph * 3.0)
			(f["light"] as PointLight2D).energy = float(f["base"]) * k
			var halo: Variant = f["halo"]
			if halo != null:
				(halo as Sprite2D).self_modulate.a = clampf(k, 0.0, 1.2)
	_spark_t += dt
	if not _forge_by_god and _sparks != null and _spark_t > 1.8:
		_forge_strike()
	if _forge_light != null:
		_forge_light.energy = _forge_base * (1.0 + 1.2 * exp(-_spark_t * 6.0))
	for god: HubGod in _gods:
		god.player_x = player_x
	_update_queue(dt)
	for s: HubPatrol in _servants:
		s.step(dt)
	_update_faders(dt)
	_update_ui(dt)
	_update_chatter(dt)


## 前景大物件挡住西西弗斯（身体或脚边）时淡出一部分，走开再淡回来
func _update_faders(dt: float) -> void:
	if _faders.is_empty():
		return
	var feet: float = ground + lane_front
	var body: Rect2 = Rect2(player_x - fade_half_width, feet - fade_body_height, fade_half_width * 2.0, fade_body_height + fade_below_feet)
	for f: Dictionary in _faders:
		var sp: Sprite2D = f["node"]
		var r: Rect2 = sp.global_transform * (f["rect"] as Rect2)
		var target: float = fade_alpha if r.intersects(body) else 1.0
		sp.modulate.a = move_toward(sp.modulate.a, target, fade_speed * dt)
