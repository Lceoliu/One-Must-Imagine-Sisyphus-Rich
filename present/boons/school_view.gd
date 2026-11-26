class_name SchoolView
extends RefCounted
## 流派画面基类（一神一文件，路径写在 content/rules/modules.json 的 view；= 网页 gods/<god>.js 的 drawNight / drawHUD）。
## st = 对应 RuleModule.view_state()（只读）。世界坐标是米，用 WorldView.p(x, y) 换成画布像素。
## 三层：world（染色层：精灵，跟着夜色变暗）、gold（不染色：金线、火光）、hud（屏幕空间）。
## view_state 里的 "hud" 字符串由 BoonView 统一画在连碾下方，子类不用管。

const GOLD: Color = Color("f0b93a")
const GOLD_HI: Color = Color("ffe08a")
const CREAM: Color = Color("f1e3c8")
const INK: Color = Color("120c0a")
const TERRA: Color = Color("b0705a")
const PPM: float = WorldView.PPM


func world(_c: CanvasItem, _wv: WorldView, _sim: SimGame, _st: Dictionary, _vr: Vector2) -> void: pass
func gold(_c: CanvasItem, _wv: WorldView, _sim: SimGame, _st: Dictionary, _vr: Vector2) -> void: pass
func hud(_h: HudView, _sim: SimGame, _st: Dictionary, _vp: Vector2) -> void: pass


## 在世界 (x, y) 处画精灵：底边中点对齐，高 hm 米
static func spr(c: CanvasItem, key: StringName, x: float, y: float, hm: float, alpha: float = 1.0, flip: bool = false, rot: float = 0.0, scl: Vector2 = Vector2.ONE) -> bool:
	var tex: Texture2D = SpriteDB.tex(key)
	if tex == null:
		return false
	var h: float = hm * PPM
	var w: float = h * SpriteDB.aspect(key)
	c.draw_set_transform(WorldView.p(x, y), rot, Vector2(-scl.x if flip else scl.x, scl.y))
	c.draw_texture_rect(tex, Rect2(-w / 2.0, -h, w, h), false, Color(1, 1, 1, alpha))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## 第一个存在的精灵 key（都没有返回 &""）
static func first_key(keys: Array[StringName]) -> StringName:
	for k: StringName in keys:
		if SpriteDB.has(k):
			return k
	return &""


## 沿地表的一条折线（x 从 x0 到 x1，离地 off(x) 米）
static func ground_line(c: CanvasItem, w: World, x0: float, x1: float, step: float, off: Callable, col: Color, width: float) -> void:
	var pts: PackedVector2Array = []
	var x: float = x0
	while x <= x1:
		pts.append(WorldView.p(x, w.y_at_x(x) + float(off.call(x))))
		x += step
	if pts.size() >= 2:
		c.draw_polyline(pts, col, width, true)
