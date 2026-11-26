class_name RuleModule
extends RefCounted
## 赐福机制模块基类（一神一文件，= 网页 gods/<god>.js）。状态写成子类成员；每天 layout 前 reset_day()。
## 钩子合成规则（BoonSystem 分发，照抄 boons.js）：*_mul 连乘；on_space 任一为真；before_night_end 第一个真；extra_seals 求和。

var id: StringName = &""
var g: SimGame = null
var boons: BoonSystem = null
var tune: Dictionary = {}


func bind(p_g: SimGame, p_boons: BoonSystem, p_tune: Dictionary) -> void:
	g = p_g
	boons = p_boons
	tune = p_tune


func is_active(_st: Stats) -> bool: return false
func reset_day() -> void: pass
func layout(_objs: Array[CrushObj]) -> void: pass
func dusk_start(_objs: Array[CrushObj]) -> Array[CrushObj]: return []
func day_update(_dt: float) -> void: pass
func night_start() -> void: pass
func night_update(_dt: float) -> void: pass
func on_space() -> bool: return false
func value_mul(_o: CrushObj, _opt: Dictionary) -> float: return 1.0
func req_mul(_o: CrushObj) -> float: return 1.0
func drag_mul(_o: CrushObj) -> float: return 1.0
func grow_mul(_o: CrushObj) -> float: return 1.0
func on_crush(_o: CrushObj, _value: float, _opt: Dictionary) -> void: pass
func on_land(_info: Dictionary) -> void: pass
func extra_seals() -> int: return 0
func before_night_end(_reason: StringName) -> bool: return false
func on_night_end(_data: Dictionary) -> void: pass
## 给表现层：本模块要画的东西（只读数据）
func view_state() -> Dictionary: return {}
