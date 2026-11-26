@tool
class_name HubPatrol
extends Sprite2D
## 来回走的幽魂侍者：从摆放位置起，在 [0, span] 之间往返（速度 speed 像素/秒），轻轻上下浮动；走到两头各停 dwell 秒。
## 走到 veils 里的东西（躺椅）后面时按被挡住的比例淡到 veil_alpha —— 不然躺椅腿之间会露出半截幽魂，像钻在床底下。
## 编辑器里画出走动范围。

@export var span: float = 600.0:
	set(v):
		span = v
		queue_redraw()
@export var speed: float = 45.0
## 走到一头停多久（端着酒壶在躺椅边候着）
@export var dwell: float = 0.0
## 会挡住他的东西（躺椅等 Sprite2D），走到它们后面时淡出
@export var veils: Array[NodePath] = []
## 整个人被挡住时的不透明度（相对场景里摆的 modulate.a）
@export_range(0.0, 1.0) var veil_alpha: float = 0.0
## 身体半宽（像素，世界坐标），算被挡住多少
@export var half_width: float = 80.0
var _x0: float = NAN
var _dir: float = 1.0
var _t: float = 0.0
var _y0: float = 0.0
var _wait: float = 0.0
var _a0: float = 1.0
## 每个 veil 在世界里的左右范围（第一次 step 时量）
var _veil_x: Array[Vector2] = []


func _ready() -> void:
	_t = randf() * TAU


func _measure() -> void:
	_x0 = position.x
	_y0 = position.y
	_a0 = modulate.a
	_veil_x.clear()
	for p: NodePath in veils:
		var v: Sprite2D = get_node_or_null(p) as Sprite2D
		if v == null:
			continue
		var r: Rect2 = v.global_transform * _opaque(v)
		_veil_x.append(Vector2(r.position.x, r.end.x))


## 精灵本地坐标里不透明像素的包围盒（读不到图像时退回整张贴图）
static func _opaque(sp: Sprite2D) -> Rect2:
	var r: Rect2 = sp.get_rect()
	var ct: CanvasTexture = sp.texture as CanvasTexture
	var tex: Texture2D = ct.diffuse_texture if ct != null else sp.texture
	var u: Rect2i = SpriteDB.used_px(tex)   # 按贴图缓存（导出版读像素要从显卡读回来）
	if u.size == Vector2i.ZERO:
		return r
	var k: Vector2 = r.size / tex.get_size()
	return Rect2(r.position + Vector2(u.position) * k, Vector2(u.size) * k)


## 身体 [x − half_width, x + half_width] 被挡住的比例（0..1）
func hidden_frac() -> float:
	var gx: float = global_position.x
	var best: float = 0.0
	for v: Vector2 in _veil_x:
		var o: float = minf(gx + half_width, v.y) - maxf(gx - half_width, v.x)
		best = maxf(best, clampf(o / (half_width * 2.0), 0.0, 1.0))
	return best


func step(dt: float) -> void:
	if is_nan(_x0):
		_measure()
	_t += dt
	if _wait > 0.0:
		_wait -= dt
	else:
		position.x += _dir * speed * dt
		if position.x > _x0 + span or position.x < _x0:
			_dir = -_dir
			position.x = clampf(position.x, _x0, _x0 + span)
			# 只在看得见的那头停（躲在躺椅后面那头直接折回）
			_wait = dwell if hidden_frac() < 0.5 else 0.0
	# 停着的时候朝着刚才走来的方向（面向躺椅上的神），走起来朝前
	flip_h = (-_dir if _wait > 0.0 else _dir) < 0.0
	position.y = _y0 + sin(_t * 1.6) * 3.0
	var f: float = smoothstep(0.1, 0.65, hidden_frac())
	modulate.a = _a0 * lerpf(1.0, veil_alpha, f)


func _draw() -> void:
	if not Engine.is_editor_hint() or scale.x == 0.0:
		return
	var k: float = 1.0 / scale.x
	draw_line(Vector2(0, 8.0 * k), Vector2(span * k, 8.0 * k), Color(0.7, 0.85, 1.0, 0.8), 3.0 * k)
	draw_circle(Vector2(span * k, 8.0 * k), 6.0 * k, Color(0.7, 0.85, 1.0, 0.8))
