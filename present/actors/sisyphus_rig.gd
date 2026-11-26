@tool
class_name SisyphusRig
extends Node2D
## 西西弗斯的分部位骨骼（白天推石和夜宴共用一套）：Skeleton2D + Bone2D，躯干、头是挂在骨头下的 Sprite2D（刚体剪纸），
## 整条腿 / 整条手臂、手（四种手型各一张）、裙子是蒙皮网格（Skeleton 下的 Polygon2D；手和手臂在腕部用同一个权重，一起弯）。场景 present/actors/sisyphus.tscn 由 tests/tools/rig/make_sisyphus.gd 生成，
## 之后在编辑器里改骨头 / 部位 / 动画都行（动画面板里每个动作一条，轨道是骨头的 rotation / position，以及手型 hand_n / hand_f、闭眼 sleep_head）。
## 原点 = 两脚之间的地面；朝右。远侧的手脚（far）画在身体后面、颜色压暗一点。
##
## 每帧动画之后做三件事（post）：
##   腿：ground_states 里的动作，两只脚都踩到地面上——最低的脚贴地，另一只本来着地的脚用两节 IK 吸到地面；
##       slope ≠ 0（白天的坡）时人保持直立，身体跟着更低的那只脚，高处那条腿弯膝去够坡面，着地的脚掌顺着坡。
##       seat_states 里的坐姿：整个人上下挪到脚跟落在 y = 0（臀和坐姿裙压在地面上，不陷进地里）。
##   裙：下摆前半跟最靠前的大腿、后半跟最靠后的大腿转，上沿跟躯干前倾转一点；坐在地上时换坐姿裙（sit_skirt），
##       它的下半片骨头摆到近侧大腿根、跟大腿转。带混合切动作时裙子、手型等姿势过半再换（不在站姿上露出坐姿裙）。
##   手：reach_n / reach_f 设了点时，手臂用两节 IK 把手腕送到那里（推石时贴住石面）。
## 推石：已确认的 3 秒双步姿态烘焙到 sis_push / sis_push_steep；advance_push 用真实时间推进，不因快按而加速。
##   后跟自由抬起，ToeN/F 保持趾垫支撑；承力手绑定石头材质坐标，换掌时单手松开再贴合。
## 编辑器里（@tool）：拖动画时间轴、改关键帧，裙子照样跟着腿和腰动（_process 在编辑器里只跑 _skirt），看到的就是游戏里的裙子。
## 两份动作保持相同的沿坡姿态/相位，仍通过 steep_blend_deg 混合，编辑器可继续调关键帧。
## 手脚位置（2026-10-14）：推石动作里给 IK 下四个点（FootN / FootF 两只脚踝、HandN / HandF 两只手腕，N = 近侧）打了位置关键帧，
##   四肢自动用两节 IK 够到这四个点（编辑器里、游戏里都是）——调动作只要拖这四个点、插位置关键帧，腿和手臂自己弯好。
##   没有这四条轨道的动作（走路、坐……）照旧按骨头关键帧。

const SHAPES: Array[String] = ["relax", "push", "fist", "open"]

## 光照：true = 夜宴（hub_lit 材质 + 法线轮廓光），false = 白天（部位用父节点的材质，跟着世界一起染色）
@export var lit: bool = false:
	set(v):
		lit = v
		if is_inside_tree():
			_apply_materials()
## 白天跟着父节点的材质染色（世界的夜色）；放进 CanvasGroup 由组的着色器统一染色时设 false
@export var parent_tint: bool = true
## 远侧手脚的压暗
@export var far_tint: Color = Color(0.72, 0.74, 0.8)
## 这些动作里两只脚踩地（坐、躺之类不在表里的动作按动画原样）
@export var ground_states: PackedStringArray = ["stand", "idle", "walk", "talk", "push", "heave", "tired", "cheer", "kick", "bet", "pick", "strike", "slip"]
## 走路动画一个循环走多远（本节点坐标，未乘自身缩放）：外面按走过的路程推进走路动画，脚才不打滑
@export var walk_stride: float = 120.0
## 身高基准：这么高（本节点像素）算 2.1 米，外面按它换算缩放。固定值——手调推石动作改了下蹲深浅，人在游戏里也不会变大变小
@export var height_px: float = 257.0
## 近侧 / 远侧手的手型（动画里有离散轨道）
@export_enum("relax", "push", "fist", "open") var hand_n: int = 0:
	set(v):
		hand_n = v
		_apply_hands()
@export_enum("relax", "push", "fist", "open") var hand_f: int = 0:
	set(v):
		hand_f = v
		_apply_hands()
## 闭眼的头（睡觉）
@export var sleep_head: bool = false:
	set(v):
		sleep_head = v
		_apply_hands()
## 坐姿裙：0 = 普通裙子，1、2… = 换上第几条坐姿裙（坐在地上时：腰带跟躯干，下半片搭在大腿上、垂到地面；
## 每条照着一个坐姿画：1 = sit_fire，2 = sit；动画里有离散轨道）
@export_range(0, 4) var sit_skirt: int = 0:
	set(v):
		sit_skirt = v
		# 不在混合过渡里（编辑器、测试、动画自己的键）：直接整条换上
		if _blend_len <= 0.0:
			_skirt_from = v
		_apply_hands()
## 裙摆跟大腿转的比例、最多转多少度；裙子上沿跟躯干前倾转的比例
## （skirt_lean 原来是 0.45，但以前按名字找骨头时找到了同名的裙子网格，这一项实际一直没生效；
##   真生效后陡坡推石时裙子跟着上身前倾、后摆翘成扇形，不如顺重力垂着好看，所以默认 0）
## （skirt_follow / skirt_max_deg 原来 0.75 / 55°：陡坡推石、拾取时前片跟着抬高的大腿转太多，网格从腰到下摆挤扁，
##   褶线糊成一片发亮的渐变；现在前片只微微扬起，抬起的大腿从下摆底下伸出来，像陶瓶上奔跑的人）
@export var skirt_follow: float = 0.35
@export var skirt_max_deg: float = 25.0
## 前片（裙摆前半）跟抬起的大腿：大腿往前抬过 skirt_lift_from 度之后，前片按 skirt_lift_k 跟着往上掀（最多 skirt_lift_max 度）——
## 抬膝迈步时大腿从裙摆下面伸出去，裙摆搭在大腿上，不会露出大腿根的圆头
@export var skirt_lift_from: float = 20.0
@export var skirt_lift_k: float = 0.75
@export var skirt_lift_max: float = 70.0
@export var skirt_lean: float = 0.45
## 裙子垂坠：腰带（Skirt 骨头）在世界里偏离直立多少，下摆（前后两片）就往回转这么多倍（1 = 下摆始终朝地心）
@export_range(0.0, 1.0, 0.01) var skirt_hang: float = 0.8
## 躺下时裙子后半片（朝天那一半）竖向压到多少
@export var skirt_lie_squash: float = 0.7
## 动画里离地不到这么多（本节点像素）的脚算"着地"，会被吸到地面上
@export var snap_px: float = 6.0
## 坐在地上的动作：整个人挪到脚跟落地（动画里坐姿整体低了几个像素，臀、脚跟会陷进地面线）
@export var seat_states: PackedStringArray = ["sit", "sit_fire"]
## 带混合切动作时，过渡进度到多少才换裙子、手型、闭眼（之前姿势还更像旧动作）。
## 试过两条裙子交叉淡化：半透明的黑裙子透出背景，像一团影子，不如在姿势过半时干脆换
@export_range(0.0, 1.0) var swap_at: float = 0.5

@export_group("陡坡动作")
## 坡角从 x 到 y 度之间，从 push 渐变成 push_steep（没有 push_steep 就一直用 push）
@export var steep_blend_deg: Vector2 = Vector2(18.0, 34.0)
## push_steep 是照着多陡的坡调的（度）：编辑场景按这个角度把人斜过来；游戏里躯干、头保持在这个坡上调出来的朝向
@export var steep_ref_deg: float = 40.0
@export_group("")

@export_group("推石姿势")
## 推石时躯干在世界里的前倾（度，离竖直；动画的发力起伏在它上下）= 90 − 坡角 − push_lean_over，夹在 min..max；
## push_t_base = 推石动画蓄力姿势里躯干的前倾（gen_push.py PULSE 第一行，改动画时同步）
@export var push_lean_over: float = -6.0
@export var push_lean_min: float = 24.0
@export var push_lean_max: float = 56.0
@export var push_t_base: float = 56.0
## 陡坡上手臂顺着身子轴线举过头顶：坡角从 x 到 y 度之间从"动画里的手臂方向"过渡过去；
## 手臂比身子轴线再往前倾多少度；按多长的手臂去对接触点（1 = 动画里肩到手掌的距离；小于 1 = 肘略弯）
@export var push_overhead_deg: Vector2 = Vector2(18.0, 38.0)
@export var push_arm_fwd_deg: float = 14.0
@export_range(0.5, 1.2, 0.01) var push_arm_reach: float = 1.0
## 陡坡上头额外低下多少度
@export var push_head_tuck: float = 22.0
## 手掌接触点最高按在石头赤道往上多少度、最低在石头半径的多少倍高
@export var hand_top_deg: float = 50.0
## 手贴在石头后背上最高到赤道往上几度（石头动的时候手跟着石头那一点走）：小石头不再把手按到石头顶上
@export_range(0.0, 80.0, 0.5) var grip_top_deg: float = 15.0
## 头、肩离石面至少留多少（本节点像素，乘自身缩放）：人不压进石头里
@export_range(0.0, 60.0, 0.5) var stone_clear_px: float = 4.0
@export_range(0.0, 1.0, 0.01) var hand_low_k: float = 0.25
## 手贴石面时整个人最多沿坡挪多少（本节点父坐标像素，乘了缩放之前的世界像素）
@export var hand_shift_max: float = 300.0
## 力竭、欢呼时：坡度里让整个人顺坡转的比例、最多交给腿部 IK 的坡度（弧度）
@export_range(0.0, 1.0, 0.01) var stand_tilt: float = 0.7
@export_range(0.0, 1.0, 0.01) var stand_keep: float = 0.3
@export_group("")

## 脚下的坡（弧度，正 = 右边高），本节点坐标里；白天由 world_view 每帧写入，夜宴为 0
var slope: float = 0.0
## 骨骼顺坡转的比例（推石 1、站着 stand_tilt 之间平滑过渡中的值）
var _tilt_vis: float = 0.7
## 地面：父节点坐标 x → y（着地的脚压到真实地形上，坡面有折角时不悬空 / 不陷进去）；不设就只按本节点里的坡线
var ground_fn: Callable = Callable()
## 着地的脚最多往真实地形上挪多少（父节点坐标像素）
@export var terrain_snap_max: float = 30.0
## set_phase 停在哪（0..1），repost 用
var _phase_f: float = 0.0
## 陡坡动作 push_steep 的权重（pose_on_slope 按坡角算）
var steep_k: float = 0.0
## 手脚位置点（IK 下的 Marker2D）和它们拉的两节链：点、第一节、第二节、伸直时弯的方向（-1 膝盖朝前，+1 手肘朝下后）
const IK_TARGETS: Array[String] = ["FootN", "FootF", "HandN", "HandF"]
const IK_CHAINS: Array = [["FootN", "ThighN", "ShinN", -1.0], ["FootF", "ThighF", "ShinF", -1.0],
	["HandN", "ArmN", "ForearmN", 1.0], ["HandF", "ArmF", "ForearmF", 1.0]]
## 每个动作有没有手脚位置轨道（按动作名缓存）
var _has_targets: Dictionary = {}
## 躯干额外前倾（弧度）：陡坡上整个人顺坡转了一部分时，用它把上身压回"向坡里倾"
var lean: float = 0.0
## 头额外低下（弧度，正 = 低头）：陡坡上顶大石头时头埋在两臂之间
var head_lean: float = 0.0
## 手腕要够到的点（本节点坐标；x 为 NAN = 不用）
var reach_n: Vector2 = Vector2(NAN, NAN)
var reach_f: Vector2 = Vector2(NAN, NAN)

var _anim: AnimationPlayer = null
var _state: StringName = &""
static var _lit_tex: Dictionary = {}
## 混合过渡（play_state 带 blend）：过渡时长、上次看到的动画位置（循环绕回 = 过渡已结束）、
## 过渡前穿的裙子、过半再套上的离散值（手型、闭眼）
var _blend_len: float = 0.0
var _blend_last: float = 0.0
var _skirt_from: int = 0
var _pending: Dictionary = {}
## 骨头按名字的缓存（每帧要找二十多次）
var _bones: Dictionary = {}
## 推石：一个循环 3 秒、左右腿各推一步（每步 1.5 秒），按真实时间走，按键快慢不改变动作速度（advance_push）
const PUSH_CYCLE_SECONDS: float = 3.0
var _push_seconds: float = 0.0
var _grips: Dictionary = {}
var _grip_pinned: Dictionary = {"N": false, "F": false}
var _push_dt: float = 1.0 / 60.0
var _push_toes_ready: bool = false


func _ready() -> void:
	_anim = get_node_or_null("Anim") as AnimationPlayer
	_prepare_push_toes()
	_apply_materials()
	_apply_hands()
	# 编辑器里放映动画时，先让动画播放器摆好关键帧，再解手脚 IK（数越大越晚）
	process_priority = 100
	if Engine.is_editor_hint():
		return
	if _anim != null:
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL


func _process(dt: float) -> void:
	if Engine.is_editor_hint():
		# 编辑器里调动画：四肢够到手脚位置点（拖点马上看到腿、手臂怎么弯），裙子跟着腿、腰走
		if _player() != null and _anim.assigned_animation != "":
			_limbs_to_targets()
			_skirt()
		return
	if _anim == null:
		return
	if _anim.is_playing():
		_anim.advance(dt)
		post()


func _apply_materials() -> void:
	var mat: Material = load("res://present/hub/mat_lit.tres") as Material if lit else null
	# 部位贴图比画出来大好几倍：用 mipmap 缩小才不闪
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# 白天：整条链（根、骨架、骨头、部位）都用父材质，世界的夜色染色才传得下来；夜宴：部位各自用受光材质 + 法线
	use_parent_material = not lit and parent_tint
	for n: Node in find_children("*", "CanvasItem", true, false):
		var ci: CanvasItem = n as CanvasItem
		var is_part: bool = (ci is Sprite2D and String(ci.name) != "Shadow") or ci is Polygon2D
		ci.use_parent_material = not lit or not is_part
		if not is_part:
			continue
		ci.material = mat
		ci.light_mask = 3 if lit else 1
		if ci.has_meta(&"far"):
			ci.self_modulate = far_tint
		var base: Texture2D = ci.get_meta(&"diffuse") as Texture2D if ci.has_meta(&"diffuse") else ci.get("texture") as Texture2D
		if base == null:
			continue
		if not ci.has_meta(&"diffuse"):
			ci.set_meta(&"diffuse", base)
		ci.set("texture", _lit_texture(base) if lit else base)


static func _lit_texture(base: Texture2D) -> Texture2D:
	if not _lit_tex.has(base.resource_path):
		_lit_tex[base.resource_path] = RigBuilder.canvas_texture(base)
	return _lit_tex[base.resource_path]


func _apply_hands() -> void:
	if get_child_count() == 0:
		return
	for side: String in ["N", "F"]:
		var shape: String = SHAPES[clampi(hand_n if side == "N" else hand_f, 0, SHAPES.size() - 1)]
		for h: Node2D in _hand_nodes(side):
			h.visible = str(h.get_meta(&"shape")) == shape
	var head: Sprite2D = part_sprite("Head")
	var sleep: Sprite2D = part_sprite("HeadSleep")
	if head != null and sleep != null:
		head.visible = not sleep_head
		sleep.visible = sleep_head
	_apply_skirts()


## 此刻该穿哪条裙子（0 = 普通裙子，1、2… = 坐姿裙）：混合过渡没过半时还穿过渡前那条（_skirt_from）
func _skirt_now() -> int:
	if _blend_len > 0.0 and _blend_progress() < swap_at:
		return _skirt_from
	return sit_skirt


## 坐姿裙和普通裙子只显示一条
func _apply_skirts() -> void:
	var skel: Node = get_node_or_null("Skeleton")
	if skel == null:
		return
	var want: int = _skirt_now()
	for c: Node in skel.get_children():
		if c.has_meta(&"sit_skirt"):
			(c as Node2D).visible = int(c.get_meta(&"sit_skirt")) == want
		elif String(c.name) == "Skirt":
			(c as Node2D).visible = want == 0


## 一只手的四种手型节点（蒙皮网格挂在 Skeleton 下，带 meta hand = "N" / "F"；旧版是手骨头下的精灵）
func _hand_nodes(side: String) -> Array[Node2D]:
	var out: Array[Node2D] = []
	var skel: Node = get_node_or_null("Skeleton")
	if skel != null:
		for c: Node in skel.get_children():
			if c is Node2D and c.has_meta(&"shape") and str(c.get_meta(&"hand", "")) == side:
				out.append(c as Node2D)
	if out.is_empty():
		var bone: Node = find_child("Hand" + side, true, false)
		if bone != null:
			for c2: Node in bone.get_children():
				if c2 is Node2D and c2.has_meta(&"shape"):
					out.append(c2 as Node2D)
	return out


## AnimationPlayer（_ready 之前、或不在场景树里时也能用：测试和工具里常这样）
func _player() -> AnimationPlayer:
	_prepare_push_toes()
	if _anim == null:
		_anim = get_node_or_null("Anim") as AnimationPlayer
		if _anim != null and not Engine.is_editor_hint():
			_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return _anim


## 切换到某个动作（循环动作循环播；一次性动作播完停在最后一帧）
func play_state(state: StringName, blend: float = 0.2) -> void:
	_player()
	if _anim == null or not _anim.has_animation(state):
		return
	if _state == state and _anim.is_playing():
		return
	_state = state
	if state != &"push":
		_push_seconds = 0.0
		_grips.clear()
	var from_skirt: int = _skirt_now()          # 上一段过渡还没换裙子时，接着从正在显示的那条换
	_finish_blend()
	_anim.play(state, blend)
	# 混合过渡时，离散轨道（手型、闭眼、坐姿裙）在 t = 0 的键会被旧动作盖掉，要等新动作循环一圈才生效，所以自己套上：
	# 不混合就马上套；混合时等过渡到 swap_at（姿势已经更像新动作）再换：坐姿裙先记下目标、由 _apply_skirts 按进度挑，手型、闭眼暂存
	var vals: Dictionary = _discrete_values(_anim.get_animation(state), 0.0)
	if blend <= 0.0:
		_set_all(vals)
		return
	_blend_len = blend
	_blend_last = 0.0
	_skirt_from = from_skirt
	if vals.has("sit_skirt"):
		sit_skirt = int(vals["sit_skirt"])
		vals.erase("sit_skirt")
	_pending = vals
	_apply_skirts()


## 混合过渡的进度 0..1（按新动作已经播了多久算；不在过渡里 = 1）
func _blend_progress() -> float:
	if _blend_len <= 0.0 or _anim == null:
		return 1.0
	var pos: float = _anim.current_animation_position
	if pos < _blend_last - 0.0001 or pos >= _anim.current_animation_length - 0.0001:
		return 1.0          # 循环绕回了 / 一次性动作播完了：过渡早就结束
	return clampf(pos / _blend_len, 0.0, 1.0)


## 每帧（post）推进混合过渡：过半套上暂存的手型、闭眼，结束后只留新裙子
func _update_blend() -> void:
	if _blend_len <= 0.0:
		return
	var k: float = _blend_progress()
	if _anim != null:
		_blend_last = _anim.current_animation_position
	if k >= swap_at and not _pending.is_empty():
		var vals: Dictionary = _pending
		_pending = {}
		_set_all(vals)
	if k >= 1.0:
		_finish_blend()
	_apply_skirts()


## 立刻结束混合过渡：暂存的离散值全部套上，裙子只留当前那条
func _finish_blend() -> void:
	_blend_len = 0.0
	if not _pending.is_empty():
		var vals: Dictionary = _pending
		_pending = {}
		_set_all(vals)
	_skirt_from = sit_skirt


func _set_all(vals: Dictionary) -> void:
	for k: String in vals:
		set(k, vals[k])


## 动作里根节点属性的离散轨道（hand_n / hand_f / sleep_head / sit_skirt）在 time 时的值
func _discrete_values(a: Animation, time: float) -> Dictionary:
	var out: Dictionary = {}
	if a == null:
		return out
	for t: int in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_VALUE or a.value_track_get_update_mode(t) != Animation.UPDATE_DISCRETE:
			continue
		var path: NodePath = a.track_get_path(t)
		if path.get_name_count() != 1 or String(path.get_name(0)) != "." or a.track_get_key_count(t) == 0:
			continue
		out[String(path.get_concatenated_subnames())] = a.value_track_interpolate(t, time)
	return out


## 直接把某个动作停在 0..1 的位置（推石：跟按键走，不按就停住）
func set_phase(state: StringName, f: float) -> void:
	_player()
	if _anim == null or not _anim.has_animation(state):
		return
	# 暂停后 current_animation 会变成空字符串（4.5 实测），所以用 assigned_animation 判断
	if _anim.assigned_animation != String(state):
		_finish_blend()
		_anim.play(state)
		_state = state
	_anim.pause()
	_anim.seek(fposmod(f, 1.0) * _anim.current_animation_length, true)
	_phase_f = f
	_mix_steep()
	post()


## 外面挪了位置之后重摆一遍姿势（着地的脚按新位置重新压到地形上）：set_phase 停住的动作回到同一位置，播放中的动作原地再 seek
func repost() -> void:
	if _player() == null or _anim.assigned_animation == "":
		return
	if not _anim.is_playing():
		_anim.seek(fposmod(_phase_f, 1.0) * _anim.current_animation_length, true)
	else:
		_anim.seek(_anim.current_animation_position, true)
	_mix_steep()
	post()


## 推石时按 steep_k 把陡坡动作 push_steep 同一时刻的姿势混进来：旋转按角度插值、位置线性插值；手型等离散值过半就换
func _mix_steep() -> void:
	if steep_k <= 0.001 or _anim.assigned_animation != "push" or not _anim.has_animation(&"push_steep"):
		return
	var a: Animation = _anim.get_animation(&"push_steep")
	var root: Node = _anim.get_node_or_null(_anim.root_node)
	if root == null:
		return
	var t: float = fposmod(_anim.current_animation_position, a.length)
	for ti: int in a.get_track_count():
		if a.track_get_type(ti) != Animation.TYPE_VALUE or a.track_get_key_count(ti) == 0:
			continue
		var path: NodePath = a.track_get_path(ti)
		var node: Node = root.get_node_or_null(NodePath(path.get_concatenated_names()))
		var prop: StringName = path.get_concatenated_subnames()
		if node == null or prop == &"":
			continue
		var v: Variant = a.value_track_interpolate(ti, t)
		if a.value_track_get_update_mode(ti) == Animation.UPDATE_DISCRETE:
			if steep_k >= 0.5:
				node.set(prop, v)
		elif prop == &"rotation":
			node.set(prop, lerp_angle(float(node.get(prop)), float(v), steep_k))
		elif v is Vector2:
			node.set(prop, (node.get(prop) as Vector2).lerp(v as Vector2, steep_k))


func state() -> StringName:
	return _state


## 当前姿势下从脚底（y = 0）到最高点的高度（本节点坐标，未乘自身缩放）；外面按它把身高换算成缩放
func pose_height() -> float:
	var top: float = 0.0
	for n: Node in find_children("*", "Sprite2D", true, false):
		var sp: Sprite2D = n as Sprite2D
		if String(sp.name) == "Shadow" or not sp.visible:
			continue
		var r: Rect2 = sp.get_rect()
		var xf: Transform2D = local_xf(sp)
		for c: Vector2 in [r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]:
			top = minf(top, (xf * c).y)
	# 手（蒙皮网格）：按手骨头算贴图四角（举起拳头时手是最高点）
	for side: String in ["N", "F"]:
		var hb: Node = find_child("Hand" + side, true, false)
		for h: Node2D in _hand_nodes(side):
			if hb == null or not h.visible or not h.has_meta(&"corners"):
				continue
			var hx: Transform2D = local_xf(hb)
			for c2: Vector2 in h.get_meta(&"corners") as PackedVector2Array:
				top = minf(top, (hx * c2).y)
	return -top


## 按名字找部位精灵（骨头和部位同名，find_child 会先找到骨头，所以限定 Sprite2D）
func part_sprite(part: String) -> Sprite2D:
	var found: Array[Node] = find_children(part, "Sprite2D", true, false)
	return found[0] as Sprite2D if not found.is_empty() else null


## 某个部位矩形里一点在本节点坐标里的位置（找不到返回 NAN 向量）
func part_point(part: String, at: Vector2 = Vector2(0.5, 0.5)) -> Vector2:
	var sp: Sprite2D = part_sprite(part)
	if sp == null:
		return Vector2(NAN, NAN)
	var r: Rect2 = sp.get_rect()
	return local_xf(sp) * (r.position + r.size * at)


## 手掌中心（当前手型那张图的中心），side = "N" / "F"
func palm_point(side: String) -> Vector2:
	var bone: Node = find_child("Hand" + side, true, false)
	if bone == null:
		return Vector2(NAN, NAN)
	for h: Node2D in _hand_nodes(side):
		if not h.visible:
			continue
		if h.has_meta(&"palm"):
			return local_xf(bone) * (h.get_meta(&"palm") as Vector2)
		if h is Sprite2D:
			var sp: Sprite2D = h as Sprite2D
			var r: Rect2 = sp.get_rect()
			return local_xf(sp) * (r.position + r.size * 0.5)
	return local_xf(bone) * Vector2.ZERO


## 某个子孙节点到本节点坐标的变换：沿父节点链乘局部变换（seek 之后同一帧里 global_transform 可能还没刷新）
func local_xf(n: Node) -> Transform2D:
	var xf: Transform2D = Transform2D.IDENTITY
	var cur: Node = n
	while cur != null and cur != self:
		var c2d: Node2D = cur as Node2D
		if c2d != null:
			xf = c2d.transform * xf
		cur = cur.get_parent()
	return xf


## 兼容旧名字（预览工具调用）
func ground_now() -> void:
	post()


## 动画之后的修正：腿踩地、裙摆跟腿、手够目标
func post() -> void:
	var torso: Bone2D = _bone("Torso")
	if torso != null and absf(lean) > 0.0001:
		torso.rotation += lean
	var headb: Bone2D = _bone("Head")
	if headb != null and absf(head_lean) > 0.0001:
		headb.rotation += head_lean
	_update_blend()
	_limbs_to_targets()
	_push_toes()
	_legs()
	_skirt()
	_arms()


# ———————————————— 腿 ————————————————
func _bone(nm: String) -> Bone2D:
	# 缓存的骨头还在本节点底下才用（编辑器里重建场景后会失效）
	var hit: Variant = _bones.get(nm)
	if is_instance_valid(hit) and is_ancestor_of(hit as Node):
		return hit as Bone2D
	# 只找 Bone2D：蒙皮网格（Skeleton 的直接子节点）有和骨头同名的（Skirt），find_child 会先找到它
	var found: Array[Node] = find_children(nm, "Bone2D", true, false)
	var b: Bone2D = found[0] as Bone2D if not found.is_empty() else null
	if b != null:
		_bones[nm] = b
	return b


## 一只脚的鞋底点（沿脚底轮廓，本节点坐标），side = "N" / "F"（测试和外部检查用）
func sole_points(side: String) -> PackedVector2Array:
	return _sole(side)


## 一只脚鞋底两点（本节点坐标）：优先用脚骨头上记的鞋底点（腿是整条网格时），否则用脚精灵
func _sole(side: String) -> PackedVector2Array:
	var out: PackedVector2Array = []
	var fb: Bone2D = _bone("Foot" + side)
	var toe: Bone2D = _bone("Toe" + side)
	if toe != null and _player().assigned_animation == "push":
		out.append(local_xf(fb) * Vector2(-9.804, 12.901))
		out.append(local_xf(toe) * Vector2(17.0, 3.0))
		return out
	if fb != null and fb.has_meta(&"sole"):
		var bx: Transform2D = local_xf(fb)
		for q: Vector2 in fb.get_meta(&"sole") as PackedVector2Array:
			out.append(bx * q)
		return out
	var sp: Sprite2D = part_sprite("Foot" + side)
	if sp == null:
		return out
	var xf: Transform2D = local_xf(sp)
	var pts: PackedVector2Array = sp.get_meta(&"sole", PackedVector2Array()) as PackedVector2Array
	if pts.is_empty():
		var r: Rect2 = sp.get_rect()
		out.append(xf * (r.position + Vector2(0, r.size.y)))
		out.append(xf * r.end)
		return out
	for p: Vector2 in pts:
		out.append(xf * (sp.offset + p))
	return out


func _legs() -> void:
	var skel: Node2D = get_node_or_null("Skeleton") as Node2D
	if skel == null or _player() == null:
		return
	skel.position = Vector2.ZERO
	if seat_states.has(_anim.assigned_animation):
		# 坐姿：整个人挪到最低的鞋底（脚跟）落在 y = 0；从站姿混合过来时鞋底本来就在地上，不会跳
		var seat: float = -INF
		for side0: String in ["N", "F"]:
			for q1: Vector2 in _sole(side0):
				seat = maxf(seat, q1.y)
		if seat > -INF:
			skel.position.y = -seat
		# 坐在坡上（slope ≠ 0）：臀落在胯下方那一点的坡面上，两只脚各自用 IK 踩到自己脚下的坡面、脚掌顺坡
		if absf(slope) > 0.001:
			var ts: float = tan(slope)
			var hip: Bone2D = _bone("Hip")
			var hx: float = local_xf(hip).origin.x if hip != null else 0.0
			skel.position.y += -ts * hx
			for side1: String in ["N", "F"]:
				var pts: PackedVector2Array = _sole(side1)
				var fx: float = 0.0
				for q2: Vector2 in pts:
					fx += q2.x
				fx /= maxf(1.0, pts.size())
				var dy: float = -ts * (fx - hx)
				_ik(_bone("Thigh" + side1), _bone("Shin" + side1), _bone("Foot" + side1), Vector2(0, dy), -1.0, -slope)
		return
	if not ground_states.has(_anim.assigned_animation):
		return
	# 动画里每只脚的最低点（平地）
	var low: Dictionary = {}
	var cx: Dictionary = {}
	for side: String in ["N", "F"]:
		var s: PackedVector2Array = _sole(side)
		if s.size() < 2:
			return
		var lo: float = -INF
		var sx: float = 0.0
		for q0: Vector2 in s:
			lo = maxf(lo, q0.y)
			sx += q0.x
		low[side] = lo
		cx[side] = sx / s.size()
	var lowest: float = maxf(float(low["N"]), float(low["F"]))
	var t: float = tan(slope)
	# 每只脚处的地面高度（y 朝下：右边高 → x 越大地面 y 越小）
	var gy: Dictionary = {"N": -t * float(cx["N"]), "F": -t * float(cx["F"])}
	var body: float = maxf(float(gy["N"]), float(gy["F"]))
	skel.position.y = body - lowest
	var planted: Dictionary = {}
	for side2: String in ["N", "F"]:
		var gap: float = lowest - float(low[side2])          # 动画里这只脚离地多高（≥ 0）
		planted[side2] = gap < snap_px
		# 这只脚要挪的竖直距离：坡面高差，加上"本来就该着地"的吸附
		var dy: float = float(gy[side2]) - body + (gap if bool(planted[side2]) else 0.0)
		var rot: float = -slope if bool(planted[side2]) else -slope * 0.5
		if absf(dy) > 0.05 or absf(rot) > 0.0005:
			_ik(_bone("Thigh" + side2), _bone("Shin" + side2), _bone("Foot" + side2), Vector2(0, dy), -1.0, rot)
	# 复核：脚掌绕踝转平之后，着地的脚离坡面还差多少（e < 0 = 悬空）——整体下移到最低那只脚，另一只再用 IK 补差
	if absf(slope) > 0.0005:
		var e: Dictionary = {}
		var m: float = -INF
		for side3: String in ["N", "F"]:
			if not bool(planted[side3]):
				continue
			var worst: float = -INF
			for q: Vector2 in _sole(side3):
				worst = maxf(worst, q.y + t * q.x)
			e[side3] = worst
			m = maxf(m, worst)
		if m > -INF:
			skel.position.y -= m
			for side4: String in e:
				var rest_gap: float = m - float(e[side4])
				if rest_gap > 0.3:
					_ik(_bone("Thigh" + side4), _bone("Shin" + side4), _bone("Foot" + side4), Vector2(0, rest_gap), -1.0)
	_snap_to_terrain(planted)


## 着地的脚压到真实地形上（ground_fn）：坡面不是一条直线（折角、起伏），本节点里的坡线和真实地面差一点的地方，
## 用腿部 IK 把最低的鞋底点挪到地面上（最多 terrain_snap_max）
func _snap_to_terrain(planted: Dictionary) -> void:
	if not ground_fn.is_valid() or not is_inside_tree():
		return
	var inv: Transform2D = transform.affine_inverse()
	for side: String in ["N", "F"]:
		if not bool(planted.get(side, false)):
			continue
		var worst: float = -INF
		var at: float = 0.0
		for q: Vector2 in _sole(side):
			var pq: Vector2 = transform * q
			var d: float = float(ground_fn.call(pq.x)) - pq.y        # > 0 = 鞋底在地面上方（悬空）
			if is_inf(worst) or d < worst:
				worst = d
				at = pq.x
		if is_inf(worst) or absf(worst) < 0.5:
			continue
		var dw: Vector2 = Vector2(0.0, clampf(worst, -terrain_snap_max, terrain_snap_max))
		_ik(_bone("Thigh" + side), _bone("Shin" + side), _bone("Foot" + side), inv.basis_xform(dw), -1.0)


# ———————————————— 手脚位置 → 四肢 IK ————————————————
## 当前动作有手脚位置轨道时，四条两节链各自够到自己的点（脚踝、手腕）；脚掌、手掌保持关键帧里的朝向
func _limbs_to_targets() -> void:
	if _player() == null:
		return
	var an: StringName = _anim.assigned_animation
	if an == &"":
		return
	if not _has_targets.has(an):
		var a: Animation = _anim.get_animation(an)
		_has_targets[an] = a != null and a.find_track(NodePath("IK/FootN:position"), Animation.TYPE_VALUE) >= 0
	if not bool(_has_targets[an]):
		return
	var ik: Node2D = get_node_or_null("IK") as Node2D
	if ik == null:
		return
	# 先清掉上一帧贴地时整体挪的那一下（_legs 每帧重新算），不然它会被 IK 当成姿势的一部分，一帧帧越积越多
	var skel: Node2D = get_node_or_null("Skeleton") as Node2D
	if skel != null:
		skel.position = Vector2.ZERO
	for ch: Array in IK_CHAINS:
		var m: Node2D = ik.get_node_or_null(str(ch[0])) as Node2D
		var end: Bone2D = _bone(str(ch[0]))
		if m == null or end == null:
			continue
		var cur: Vector2 = local_xf(end).origin
		var want: Vector2 = ik.transform * m.position
		if cur.distance_squared_to(want) > 0.0001:
			_ik(_bone(str(ch[1])), _bone(str(ch[2])), end, want - cur, float(ch[3]))


# ———————————————— 推石姿势（白天 world_view 和调试台 tests/tools/rig/push_lab.tscn 共用）————————————————
## 按坡角摆整个人：ga = 脚下坡角（弧度，上坡为正）。推石：整个人完全顺坡转（关键帧里的腿、步子都在"沿坡"的坐标里），
## 躯干另按坡角摆前倾、陡坡上低头；站着（力竭、欢呼）：大半坡度顺坡转、剩下交给腿部 IK。dt = 0 时直接到位（不平滑）
func pose_on_slope(ga: float, pushing: bool, dt: float, sway: float = 0.0) -> void:
	var want: float = 1.0 if pushing else stand_tilt
	_tilt_vis = move_toward(_tilt_vis, want, dt * 3.0) if dt > 0.0 else want
	var keep: float = ga * (1.0 - _tilt_vis)
	if not pushing:
		keep = clampf(keep, -stand_keep, stand_keep)
	rotation = -(ga - keep) + sway
	slope = keep
	lean = ga - keep
	head_lean = 0.0
	steep_k = 0.0
	if pushing and _player() != null and _anim.has_animation(&"push_steep"):
		steep_k = smoothstep(steep_blend_deg.x, steep_blend_deg.y, rad_to_deg(ga))
	if pushing:
		# push / push_steep 里已经是沿坡的完整姿势（躯干、头都调好了），不再按坡角补前倾、低头
		lean = 0.0
		head_lean = 0.0
	else:
		_push_seconds = 0.0
		_grips.clear()
	reach_n = Vector2(NAN, NAN)
	reach_f = Vector2(NAN, NAN)


## 推石时手贴石面（c = 石头圆心、R = 半径，都在父节点坐标；ga = 坡角）：先定近侧手掌的接触点——按手掌离坡面多高
## （垂直坡面量）取石头朝下坡那一面同样高的点，最高按在"肩"上（赤道往上 hand_top_deg 度）；陡坡上用"虚拟手掌"
## （肩 + 顺着身子轴线举过头顶的方向 × 稍短的臂长）去定。然后把整个人沿坡挪到手掌正对接触点（最多 hand_shift_max），
## 再用手臂 IK 把近侧手掌送到接触点、远侧手掌送到离它最近的石面点上。返回 (沿坡挪了多少, 接触点高 / R)
func push_hands(c: Vector2, R: float, ga: float, roll: float = NAN, surface_radius: Callable = Callable()) -> Vector2:
	if not is_nan(roll):
		return _push_locked_hands(c, R, ga, roll, surface_radius)
	var pn: Vector2 = palm_point("N")
	if is_nan(pn.x):
		return Vector2.ZERO
	var tan_dir: Vector2 = Vector2(cos(ga), -sin(ga))      # 父坐标里的上坡方向（y 朝下）
	var n_dir: Vector2 = Vector2(-sin(ga), -cos(ga))       # 垂直坡面朝外
	var pw0: Vector2 = transform * pn
	var armb: Bone2D = _bone("ArmN")
	var torb: Bone2D = _bone("Torso")
	var headb: Bone2D = _bone("Head")
	if armb != null and torb != null and headb != null:
		var sh: Vector2 = transform * local_xf(armb).origin
		var ax: Vector2 = (transform * local_xf(headb).origin - transform * local_xf(torb).origin).normalized()
		# 陡坡动作自己调好了手臂，不再往头顶拉
		var k: float = smoothstep(push_overhead_deg.x, push_overhead_deg.y, rad_to_deg(ga)) * (1.0 - steep_k)
		var a_anim: Vector2 = pw0 - sh
		var dir: Vector2 = Vector2.from_angle(lerp_angle(a_anim.angle(), ax.rotated(deg_to_rad(push_arm_fwd_deg)).angle(), k))
		pw0 = sh + dir * a_anim.length() * lerpf(1.0, push_arm_reach, k)
	var g0: Vector2 = c - n_dir * R                        # 石头压在坡上的那一点
	var h: float = clampf((pw0 - g0).dot(n_dir), hand_low_k * R, R + R * sin(deg_to_rad(hand_top_deg)))
	var contact: Vector2 = c - tan_dir * sqrt(maxf(0.0, R * R - (h - R) * (h - R))) + n_dir * (h - R)
	var shift: float = (contact - pw0).dot(tan_dir)
	position += tan_dir * clampf(shift, -hand_shift_max, hand_shift_max)
	# 挪了位置：着地的脚按新位置重新压到地形上
	repost()
	var inv: Transform2D = transform.affine_inverse()
	for side: String in ["N", "F"]:
		var pl: Vector2 = palm_point(side)
		if is_nan(pl.x):
			continue
		var pw: Vector2 = transform * pl
		var at: Vector2 = contact if side == "N" else c + (pw - c).normalized() * R
		var wrist: Vector2 = local_xf(_bone("Hand" + side)) * Vector2.ZERO
		var tgt: Vector2 = wrist + (inv * at - pl)
		if side == "N":
			reach_n = tgt
		else:
			reach_f = tgt
	apply_reach()
	return Vector2(shift, h / maxf(1.0, R))


## 推石动作往前走 dt 秒（active = 正在推；不推就停在当前姿势，再推接着走）。连按得再快也不加速
func advance_push(dt: float, active: bool) -> void:
	_push_dt = dt
	if active:
		_push_seconds += dt
	set_phase(&"push", _push_seconds / PUSH_CYCLE_SECONDS)


## 推石时脚趾能弯：运行时给两只脚各加一根脚趾骨头 ToeN / ToeF，把腿网格脚掌前段的权重分给它；其他动作脚趾不转，脚型不变。
## 编辑器里不加——这里改的是网格的骨头权重，在编辑器里改了、一保存场景就写进 sisyphus.tscn，下次运行又分一遍。
func _prepare_push_toes() -> void:
	# 测试、工具里常在 _ready 之前就 seek 刚实例化的场景，所以 _player() 里也会调到这里
	if _push_toes_ready or Engine.is_editor_hint():
		return
	_push_toes_ready = true
	for side: String in ["N", "F"]:
		var foot: Bone2D = _bone("Foot" + side)
		var toe: Bone2D = Bone2D.new()
		toe.name = "Toe" + side
		toe.position = Vector2(15.0, 16.0)
		toe.rest = Transform2D(0.0, toe.position)
		toe.set_autocalculate_length_and_angle(false)
		toe.length = 17.0
		toe.bone_angle = 0.0
		foot.add_child(toe)
		var mesh: Polygon2D = get_node("Skeleton/Leg" + side) as Polygon2D
		var foot_path: NodePath = NodePath("Hip/Thigh%s/Shin%s/Foot%s" % [side, side, side])
		var inv: Transform2D = local_xf(foot).affine_inverse()
		for bi: int in mesh.get_bone_count():
			if mesh.get_bone_path(bi) != foot_path:
				continue
			var weights: PackedFloat32Array = mesh.get_bone_weights(bi)
			var toes: PackedFloat32Array = weights.duplicate()
			for vi: int in weights.size():
				var x: float = (inv * mesh.polygon[vi]).x
				toes[vi] *= smoothstep(10.0, 25.0, x)
				weights[vi] -= toes[vi]
			mesh.set_bone_weights(bi, weights)
			mesh.add_bone(NodePath(str(foot_path) + "/Toe" + side), toes)
			break
		# 推掌的掌心取画出来的掌垫，不用图片外框的中心（那里是透明的）
		for hand: Node2D in _hand_nodes(side):
			if str(hand.get_meta(&"shape", "")) == "push":
				hand.set_meta(&"palm", Vector2(10.0, 15.0))


func _push_toes() -> void:
	for side: String in ["N", "F"]:
		var toe: Bone2D = _bone("Toe" + side)
		if toe != null:
			toe.rotation = -local_xf(_bone("Foot" + side)).get_rotation() if _anim.assigned_animation == "push" else 0.0


## 推石时手贴石面（传了 roll 时走这里）：承力的手掌记在石头自己的坐标里（石头滚，手跟着那一点走），
## 只在换手的时候松开、挪到新位置再贴上，两只手不同时松开
func _push_locked_hands(c: Vector2, radius: float, ga: float, roll: float, surface_radius: Callable) -> Vector2:
	var tangent: Vector2 = Vector2(cos(ga), -sin(ga))
	var normal: Vector2 = Vector2(-sin(ga), -cos(ga))
	var contacts: Dictionary = {}
	var q: float = fposmod(_phase_f * 2.0, 1.0)
	for side: String in ["N", "F"]:
		var authored: Vector2 = transform * palm_point(side)
		var h: float = clampf((authored - (c - normal * radius)).dot(normal), hand_low_k * radius, radius * (1.0 + sin(deg_to_rad(grip_top_deg))))
		var face: Vector2 = -tangent * sqrt(maxf(0.0, radius * radius - pow(h - radius, 2))) + normal * (h - radius)
		var ideal: float = face.angle() - roll
		if not _grips.has(side):
			_grips[side] = {"angle": ideal, "release": false, "from": ideal, "age": 0.0, "duration": 0.21, "window": -1}
		var grip: Dictionary = _grips[side]
		grip["ideal_height"] = h
		grip["ideal"] = ideal
		var start: float = 0.70 if side == "F" else 0.84
		var end: float = 0.84 if side == "F" else 0.98
		var other: String = "F" if side == "N" else "N"
		var other_free: bool = not _grips.has(other) or not bool(_grips[other]["release"])
		var window: int = int(floor(_phase_f * 2.0))
		var scheduled: bool = q >= start and q < end and int(grip["window"]) != window
		# 游戏里会停、会往回滚、会比参考推得快：手被带出动作里的位置太远时，提前换一次手
		var misplaced: bool = absf(angle_difference(float(grip["angle"]), ideal)) > 0.16
		if not bool(grip["release"]) and other_free and (scheduled or misplaced):
			grip["release"] = true
			grip["from"] = grip["angle"]
			grip["age"] = 0.0
			grip["duration"] = 0.21 if scheduled else 0.10
			grip["window"] = window
		var lift: float = 0.0
		if bool(grip["release"]):
			grip["age"] = float(grip["age"]) + _push_dt
			var u: float = minf(1.0, float(grip["age"]) / float(grip["duration"]))
			grip["angle"] = lerp_angle(float(grip["from"]), ideal, smoothstep(0.0, 1.0, u))
			lift = sin(PI * u) * 8.0 * scale.x
			if u >= 1.0:
				grip["release"] = false
		_grip_pinned[side] = not bool(grip["release"])
		var a: float = float(grip["angle"])
		var rr: float = float(surface_radius.call(a)) if surface_radius.is_valid() else radius
		contacts[side] = c + Vector2.from_angle(a + roll) * (rr + lift)
	var near_hand: Bone2D = _bone("HandN")
	var near_xf: Transform2D = transform * local_xf(near_hand)
	var near_at: Vector2 = contacts["N"]
	var near_turn: float = angle_difference(near_xf.get_rotation(), (near_at-c).angle()+PI*0.5)
	var near_offset: Vector2 = (transform * palm_point("N") - near_xf.origin).rotated(near_turn)
	# 站位：近侧肩到手腕的距离保持动作里的（肘弯多少照原样，只把手臂转向接触点），沿坡挪整个人去凑。
	# 接触点比动作里的手低（小石头）时人往后站、手臂往前伸，不会挤到石头跟前把手臂折起来
	var near_sh: Vector2 = transform * local_xf(_bone("ArmN")).origin
	var arm_len: float = near_xf.origin.distance_to(near_sh)
	var v: Vector2 = near_at - near_offset - near_sh
	var shift: float = v.dot(tangent) - sqrt(maxf(0.0, arm_len * arm_len - pow(v.dot(normal), 2)))
	# 两只手都要够得着贴住的那一点、手臂不拉直：不够就把整个人沿坡往石头挪（只挪整个人，不改动作）
	for side: String in ["N", "F"]:
		var hand: Bone2D = _bone("Hand" + side)
		var at: Vector2 = contacts[side]
		var xf: Transform2D = transform * local_xf(hand)
		var turn: float = angle_difference(xf.get_rotation(), (at - c).angle() + PI * 0.5)
		var offset: Vector2 = (transform * palm_point(side) - xf.origin).rotated(turn)
		var shoulder: Vector2 = transform * local_xf(_bone("Arm" + side)).origin
		var delta: Vector2 = at - offset - shoulder - tangent * shift
		var reach: float = (_bone("Forearm" + side).position.length() + hand.position.length() - 0.55) * scale.x
		var along: float = sqrt(maxf(0.0, reach * reach - pow(delta.dot(normal), 2)))
		shift += maxf(0.0, delta.dot(tangent) - along)
	shift = _clear_of_stone(c, radius, roll, surface_radius, tangent, normal, shift)
	position += tangent * shift
	repost()
	var inv: Transform2D = transform.affine_inverse()
	for side: String in ["N", "F"]:
		var at: Vector2 = contacts[side]
		var hand: Bone2D = _bone("Hand" + side)
		var orientation: float = (at - c).angle() + PI * 0.5
		var current: float = (transform * local_xf(hand)).get_rotation()
		hand.rotation += angle_difference(current, orientation)
		var wrist: Vector2 = local_xf(hand).origin
		var target: Vector2 = wrist + inv * at - palm_point(side)
		if side == "N":
			reach_n = target
		else:
			reach_f = target
	apply_reach()
	return Vector2(shift, ((contacts["N"] as Vector2) - c).dot(normal) / radius + 1.0)


## 整个人沿坡挪 shift 之后，头、两肩不能压进石头（离石面至少 stone_clear_px）：压进去了就再往后（下坡）挪，返回挪完的 shift。
## 宁可手臂伸直一点、手离开石面一点，也不让人和石头叠在一起
func _clear_of_stone(c: Vector2, radius: float, roll: float, surface_radius: Callable, tangent: Vector2, normal: Vector2, shift: float) -> float:
	var pts: Array = []
	var hs: Sprite2D = part_sprite("Head")
	if hs != null:
		pts.append([transform * part_point("Head"), hs.get_rect().size.y * 0.4 * absf(scale.y)])
	for side: String in ["N", "F"]:
		var arm: Bone2D = _bone("Arm" + side)
		if arm != null:
			pts.append([transform * local_xf(arm).origin, 0.0])
	var out: float = shift
	for e: Array in pts:
		var u: Vector2 = (e[0] as Vector2) + tangent * out - c
		var rr: float = float(surface_radius.call(u.angle() - roll)) if surface_radius.is_valid() else radius
		var need: float = rr + float(e[1]) + stone_clear_px * absf(scale.y)
		var un: float = u.dot(normal)
		if absf(un) >= need:
			continue
		var lim: float = -sqrt(need * need - un * un)
		var ut: float = u.dot(tangent)
		if ut > lim:
			out -= ut - lim
	return out


## 某根骨头静止姿势时在本节点坐标里的朝向（沿骨链累加 rest）
func _rest_rot(nm: String) -> float:
	var r: float = 0.0
	var n: Node = _bone(nm)
	while n is Bone2D:
		r += (n as Bone2D).rest.get_rotation()
		n = n.get_parent()
	return r


## 两节 IK：把 upper → lower → end（end 骨头的原点 = 踝 / 腕）这条链的末端在本节点坐标里挪 delta；
## 弯的方向保持和动画里一样（直的时候用 bend：-1 = 膝盖朝前，+1 = 肘朝下后）；end_rot 加在末端骨头的朝向上
func _ik(upper: Bone2D, lower: Bone2D, end: Bone2D, delta: Vector2, bend: float, end_rot: float = 0.0) -> void:
	if upper == null or lower == null or end == null:
		return
	var par: Node = upper.get_parent()
	var to_par: Transform2D = local_xf(par).affine_inverse()
	var root: Vector2 = upper.position
	var knee_l: Vector2 = lower.position
	var end_l: Vector2 = end.position
	var L1: float = knee_l.length()
	var L2: float = end_l.length()
	if L1 < 0.01 or L2 < 0.01:
		return
	var cur_knee: Vector2 = upper.transform * knee_l
	var cur_end: Vector2 = upper.transform * (lower.transform * end_l)
	var end_world0: float = upper.rotation + lower.rotation + end.rotation
	var tgt: Vector2 = cur_end + to_par.basis_xform(delta)
	var v: Vector2 = tgt - root
	var d: float = clampf(v.length(), absf(L1 - L2) + 0.5, L1 + L2 - 0.5)
	var phi: float = v.angle()
	var aa: float = acos(clampf((L1 * L1 + d * d - L2 * L2) / (2.0 * L1 * d), -1.0, 1.0))
	var side0: float = (cur_end - root).cross(cur_knee - root)
	var want: float = signf(side0) if absf(side0) > 1.0 else bend
	var th: float = phi + aa
	var k1: Vector2 = root + Vector2.from_angle(th) * L1
	if signf(v.cross(k1 - root)) != want:
		th = phi - aa
	upper.rotation = th - knee_l.angle()
	var knee: Vector2 = root + Vector2.from_angle(th) * L1
	var th2: float = (root + v.normalized() * d - knee).angle()
	lower.rotation = th2 - end_l.angle() - upper.rotation
	end.rotation = end_world0 - upper.rotation - lower.rotation + end_rot


# ———————————————— 裙 ————————————————
func _skirt() -> void:
	var tn: Bone2D = _bone("ThighN")
	var tf: Bone2D = _bone("ThighF")
	var skirt: Bone2D = _bone("Skirt")
	var torso: Bone2D = _bone("Torso")
	if tn == null or tf == null or skirt == null:
		return
	var pleats: Array[Bone2D] = []
	for i: int in 8:
		var pb: Bone2D = _bone("SkirtP%d" % i)
		if pb == null:
			break
		pleats.append(pb)
	if pleats.size() < 2:
		return
	var lim: float = deg_to_rad(skirt_max_deg)
	# 腰带跟躯干转多少（只跟动画里躯干的弯：累弯腰、拾取、推石前倾；不跟 world_view 在陡坡上额外加的 lean）；躺下时不跟
	var hip0: Bone2D = _bone("Hip")
	var lying: float = smoothstep(PI / 6.0, PI / 3.0, absf(angle_difference(hip0.rest.get_rotation(), hip0.rotation))) if hip0 != null else 0.0
	var waist: float = 0.0
	if torso != null:
		waist = angle_difference(torso.rest.get_rotation(), torso.rotation - lean) * skirt_lean * (1.0 - lying)
	skirt.rotation = skirt.rest.get_rotation() + waist
	# 垂坠：腰带在世界里偏离直立多少（含髋、整个人顺坡转），褶片往回转 skirt_hang 倍（下摆朝地心）；躺下时不转
	var g: float = global_rotation if is_inside_tree() else 0.0
	var dev: float = angle_difference(_rest_rot("Skirt"), g + local_xf(skirt).get_rotation())
	var hk: float = skirt_hang * (1.0 - smoothstep(deg_to_rad(55.0), deg_to_rad(80.0), absf(dev)))
	# 大腿相对髋摆了多少（负 = 往前抬）：最靠前、最靠后的两条
	var an: float = angle_difference(tn.rest.get_rotation(), tn.rotation)
	var af: float = angle_difference(tf.rest.get_rotation(), tf.rotation)
	var fwd: float = minf(an, af)
	var bwd: float = maxf(an, af)
	# 前面的褶片跟抬起的大腿往上掀（越靠前掀得越多），后面的跟往后蹬的大腿扬一点；中间的平滑过渡。
	# 每片是绕腰带中点的刚体转动，相邻两片之间只有顶点权重的线性过渡，下摆展开成扇形、褶线跟着散开，不会挤成一块
	var lift: float = clampf((-fwd - deg_to_rad(skirt_lift_from)) * skirt_lift_k, 0.0, deg_to_rad(skirt_lift_max))
	var n: int = pleats.size()
	for i2: int in n:
		var u: float = float(i2) / float(n - 1)          # 0 = 最后，1 = 最前
		var follow: float = lerpf(clampf(bwd * skirt_follow, -lim, lim), clampf(fwd * skirt_follow, -lim, lim), u)
		var lift_i: float = lift * pow(u, 1.6)
		var pb2: Bone2D = pleats[i2]
		pb2.rotation = pb2.rest.get_rotation() + follow - dev * hk - lift_i
		pb2.scale = Vector2.ONE
	# 躺下（髋转过 45° 以上）：朝天的后几片顺着重力贴在臀腿上，不翘出身体轮廓
	if hip0 != null and absf(angle_difference(hip0.rest.get_rotation(), hip0.rotation)) > PI / 4.0:
		for i3: int in n / 2:
			pleats[i3].scale = Vector2(1.0, skirt_lie_squash)
	# 坐在地上（sit / sit_fire）换坐姿裙（sit_skirt），上面这条普通裙子只管站、走、躺
	_skirt_sit(torso, tn)


## 正在显示的坐姿裙（混合过渡里可能两条）的下半片骨头（躯干的子骨头）：原点挪到近侧大腿根，
## 按"大腿相对躯干的角"比画图时（ref_rot）多转了多少来转
func _skirt_sit(torso: Bone2D, thigh: Bone2D) -> void:
	var skel: Node = get_node_or_null("Skeleton")
	if skel == null or torso == null or thigh == null:
		return
	var tx: Transform2D = local_xf(torso)
	var hx: Transform2D = local_xf(thigh)
	var rel: float = angle_difference(tx.get_rotation(), hx.get_rotation())
	for c: Node in skel.get_children():
		if not c.has_meta(&"sit_skirt") or not (c as CanvasItem).visible:
			continue
		var ss: Bone2D = _bone(str(c.get_meta(&"drape")))
		if ss == null:
			continue
		ss.position = tx.affine_inverse() * hx.origin
		ss.rotation = angle_difference(float(ss.get_meta(&"ref_rot", rel)), rel)


# ———————————————— 手 ————————————————
## 只重算手臂（外面设好 reach_n / reach_f 之后调；腿和裙不动）
func apply_reach() -> void:
	_arms()


func _arms() -> void:
	for side: String in ["N", "F"]:
		var tgt: Vector2 = reach_n if side == "N" else reach_f
		if is_nan(tgt.x):
			continue
		var hand: Bone2D = _bone("Hand" + side)
		if hand == null:
			continue
		var wrist: Vector2 = local_xf(hand) * Vector2.ZERO
		_ik(_bone("Arm" + side), _bone("Forearm" + side), hand, tgt - wrist, 1.0)
