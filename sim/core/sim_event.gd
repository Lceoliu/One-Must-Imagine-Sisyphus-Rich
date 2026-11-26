class_name SimEvent
extends RefCounted
## sim → 表现层的单向事件（architecture §4.5）。每拍一批，由 SimRunner 取走分发。
## kind 用 StringName：text dust shards sparks ring burst flyer smoke sfx music hit slowmo shake punch flash banner
## crush land bounce jump gate_hit gate_knock chest_drop chest_open fate urn_burst tier_up milestone push slip faint
## second_wind brace phase modal save_point module 等。字段含义随 kind 而定（见 SimFx 各方法）。

var kind: StringName = &""
var id: int = -1
var x: float = 0.0
var y: float = 0.0
var a: float = 0.0
var b: float = 0.0
var c: float = 0.0
var d: float = 0.0
var name: StringName = &""
var text: String = ""
var sub: String = ""
var color: Color = Color.WHITE
var data: Dictionary = {}
