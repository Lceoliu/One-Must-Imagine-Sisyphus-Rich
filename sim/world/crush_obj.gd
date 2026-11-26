class_name CrushObj
extends RefCounted
## 山坡上的一件可碾物（= 网页 world.js layout 里 objs 的一项）。
## 规则字段由 sim 读写；t / rise / shake / flat_dur / flat_x 只给表现层做动画（sim 只在黄昏写 rise）。

enum State { STAND, CRACKED, FLAT }

var id: int = 0
var type: StringName = &""
var def: ObjDef = null
var s: float = 0.0
var x: float = 0.0
var y: float = 0.0
var ang: float = 0.0
var w: float = 0.0
var h: float = 0.0
var req: float = 0.0
var value: float = 0.0
var tier: int = 1
var state: State = State.STAND
var dmg: float = 0.0
var hit_cool: float = 0.0
var flip: bool = false
var city: bool = false
var domino: int = 0
var dgroup: int = -1
var roadblock: StringName = &""
var resold: int = 0
## 赐福模块的临时标记（日车点燃 lit 等）
var ext: Dictionary = {}

# —— 表现用 ——
var t: float = 0.0
var rise: float = 1.0
var rise_delay: float = 0.0
var shake: float = 0.0
var flat_dur: float = 0.08
var flat_x: float = 1.3


func is_flat() -> bool:
	return state == State.FLAT


func copy() -> CrushObj:
	var o: CrushObj = CrushObj.new()
	for p: Dictionary in get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			o.set(p["name"], get(p["name"]))
	o.ext = ext.duplicate()
	return o
