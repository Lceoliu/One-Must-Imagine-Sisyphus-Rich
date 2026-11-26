class_name Boulder
extends RefCounted
## 石头（= 网页 game.b）。白天沿 s 平滑移动；夜里沿 s 一维滚动，只在唇口处腾空（x/y/vx/vy 二维抛物线）。

var s: float = 0.0
var ts: float = 0.0
var x: float = 0.0
var y: float = 0.0
var r: float = 0.6
var rot: float = 0.0
var v: float = 0.0
var air: bool = false
var vx: float = 0.0
var vy: float = 0.0
var ang: float = 0.0
## 粘上去的东西：[{type, a, h, out}]
var stuck: Array[Dictionary] = []
# 上一拍的值（渲染插值用）
var prev_x: float = 0.0
var prev_y: float = 0.0
var prev_rot: float = 0.0
var prev_r: float = 0.6


func save_prev() -> void:
	prev_x = x
	prev_y = y
	prev_rot = rot
	prev_r = r


func speed() -> float:
	return Js.hypot(vx, vy) if air else absf(v)
