class_name MenuStage
extends Node2D
## 主菜单瓶腹上的画（设计画布 1920×1080 的坐标，由 MenuScreen 整体缩放）：一条地平线，右半边一道山坡升到右上角，
## 坡顶露出半座神庙；西西弗斯（游戏里同一套骨骼动画）在坡上永远推着那块石头——石头原地慢慢转，手跟着石面换手；
## 石头上方用希腊字母题名"ΣΙΣΥΦΟΣ"（黑绘陶瓶给人物题名的老规矩）。
## 山体和游戏里一样是深一档的陶土 + 浅色路沿 + 刻出来的大岩块，所以黑色的人和石头读得出来。

const INK: Color = Color("120c0a")
const IVORY: Color = Color("eadbb8")
const HILL: Color = Color(0.77, 0.53, 0.36)
const LIP: Color = Color(0.89, 0.76, 0.6)

## 地平线高度、山脚 x、坡角（度）
@export var ground_y: float = 930.0
@export var foot_x: float = 830.0
@export_range(5.0, 45.0, 0.5) var slope_deg: float = 24.0
## 每米多少像素（西西弗斯 2.1 米高）
@export var ppm: float = 150.0
## 石头半径（米）、石头圆心离山脚多远（沿坡，米）
@export var stone_r_m: float = 0.86
@export var stone_s_m: float = 5.2
## 石头原地转的速度（沿坡米 / 秒，换成弧度 = 除以半径）
@export var roll_speed: float = 0.32
@export var inscription: String = "ΣΙΣΥΦΟΣ"

var _rig: SisyphusRig = null
var _tex: Texture2D = null
var _greek: Font = null
var _roll: float = 0.0


func _ready() -> void:
	_rig = get_node_or_null("Rig") as SisyphusRig
	_tex = SpriteDB.tex(&"boulder_etched")
	_greek = load("res://present/ui/fonts/greek.tres") as Font
	if _rig != null:
		_rig.scale = Vector2.ONE * (2.1 * ppm / maxf(50.0, _rig.height_px))
		var ga: float = deg_to_rad(slope_deg)
		var g0: float = ground_y
		var fx: float = foot_x
		_rig.ground_fn = func(px: float) -> float: return g0 - tan(ga) * maxf(0.0, px - fx)
		_rig.play_state(&"push", 0.0)


## 坡上沿坡 s 米处（地表）
func on_slope(s: float) -> Vector2:
	var ga: float = deg_to_rad(slope_deg)
	return Vector2(foot_x, ground_y) + Vector2(cos(ga), -sin(ga)) * s * ppm


func stone_center() -> Vector2:
	var ga: float = deg_to_rad(slope_deg)
	return on_slope(stone_s_m) + Vector2(-sin(ga), -cos(ga)) * stone_r_m * ppm


func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	_roll += roll_speed / stone_r_m * dt
	if _rig != null:
		var ga: float = deg_to_rad(slope_deg)
		_rig.position = on_slope(stone_s_m - stone_r_m - 0.8)
		_rig.pose_on_slope(ga, true, dt)
		_rig.advance_push(dt, true)
		_rig.push_hands(stone_center(), stone_r_m * ppm, ga, _roll)
	queue_redraw()


func _draw() -> void:
	var ga: float = deg_to_rad(slope_deg)
	var t: float = tan(ga)
	var far_x: float = 2100.0
	var top_y: float = ground_y - t * (far_x - foot_x)
	var tan_dir: Vector2 = Vector2(cos(ga), -sin(ga))
	var n_in: Vector2 = Vector2(sin(ga), cos(ga))      # 垂直坡面朝里（往下）
	# 山体
	draw_colored_polygon(PackedVector2Array([Vector2(foot_x, ground_y), Vector2(far_x, top_y), Vector2(far_x, 1200.0), Vector2(foot_x, 1200.0)]), HILL)
	# 路沿：坡面下一条浅色带，上下黑线
	var lip_w: float = 18.0
	var a: Vector2 = Vector2(foot_x, ground_y)
	var b: Vector2 = Vector2(far_x, top_y)
	draw_colored_polygon(PackedVector2Array([a, b, b + n_in * lip_w, a + n_in * lip_w]), LIP)
	# 刻出来的两排大岩块：和坡面平行的两道缝，每排错开的竖缝（垂直坡面）
	var rows: Array = [[lip_w, 92.0, 0.0], [92.0, 190.0, 0.5]]
	for r: Array in rows:
		var d0: float = float(r[0])
		var d1: float = float(r[1])
		draw_line(a + n_in * d1, b + n_in * d1, Color(INK, 0.55), 2.0, true)
		var step: float = 230.0
		var s: float = -step * float(r[2])
		while s < (far_x - foot_x) / cos(ga):
			var jit: float = sin(s * 0.013 + d0) * 18.0
			var p: Vector2 = a + tan_dir * (s + jit)
			if s + jit > 10.0:
				draw_line(p + n_in * (d0 + 2.0), p + n_in * d1 + tan_dir * 8.0, Color(INK, 0.5), 2.0, true)
			s += step
	draw_line(a, b, INK, 3.0, true)
	draw_line(a + n_in * lip_w, b + n_in * lip_w, Color(INK, 0.8), 2.0, true)
	# 左边平地：瓶画的地平线（一粗一细两道）
	draw_line(Vector2(-200.0, ground_y), Vector2(foot_x, ground_y), INK, 3.0)
	draw_line(Vector2(-200.0, ground_y + 7.0), Vector2(foot_x + 2.0, ground_y + 7.0), Color(INK, 0.7), 1.5)
	# 石头（画在人后面：手按在石面上）
	var c: Vector2 = stone_center()
	var R: float = stone_r_m * ppm
	if _tex != null:
		draw_set_transform(c, _roll, Vector2.ONE)
		draw_texture_rect(_tex, Rect2(-R * 1.04, -R * 1.04, R * 2.08, R * 2.08), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(c, R, INK)
	# 题名：顺着坡写在石头上方
	if _greek != null and inscription != "":
		# 写在西西弗斯头顶上方，顺着坡
		var at: Vector2 = on_slope(stone_s_m - 1.66) + Vector2(-sin(ga), -cos(ga)) * 2.22 * ppm
		draw_set_transform(at, -ga, Vector2.ONE)
		var spaced: String = " ".join(inscription.split(""))
		draw_string(_greek, Vector2.ZERO, spaced, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, INK)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
