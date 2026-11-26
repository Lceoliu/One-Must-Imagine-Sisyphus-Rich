class_name ObjDef
extends RefCounted
## 可碾物件（content/world/objects.json，= config.js OBJ）。

const KEYS: PackedStringArray = ["id", "name", "h", "req", "value", "tier", "mat", "living", "voice", "sprite", "spawn", "jar"]
const MATS: PackedStringArray = ["ceramic", "wood", "stone", "flesh"]

var id: StringName
var h: float
var req: float
var value: float
var tier: int
var mat: StringName
var living: bool
## 叫声（bleat / cry / honk / squeal / low / neigh；空 = 无）
var voice: StringName
## 精灵 key（缺省 = id）
var sprite: StringName
## "rule" = 不进海拔带，由规则模块插入（路障、圣牛）
var spawn: StringName
## 碾碎时必掉一只命运宝瓶，档次 = jar（0 = 不掉；docs/v06/incremental.md 第 6.2 节）
var jar: int = 0
var _name_src: String

var name: String:
	get:
		return Loc.t("obj.%s.name" % id, _name_src)


static func from_dict(d: Dictionary, errors: PackedStringArray) -> ObjDef:
	var o: ObjDef = ObjDef.new()
	var w: String = "world/objects.json:%s" % d.get("id", "?")
	DefUtil.known(d, KEYS, w, errors)
	o.id = StringName(DefUtil.s(d, "id", w, errors))
	o._name_src = DefUtil.s(d, "name", w, errors)
	o.h = DefUtil.n(d, "h", w, errors)
	o.req = DefUtil.n(d, "req", w, errors)
	o.value = DefUtil.n(d, "value", w, errors)
	o.tier = DefUtil.i(d, "tier", w, errors)
	o.mat = StringName(DefUtil.s(d, "mat", w, errors))
	if not MATS.has(String(o.mat)):
		errors.append("%s：mat 只能是 %s" % [w, ", ".join(MATS)])
	o.living = DefUtil.b(d, "living", w, errors)
	o.voice = StringName(DefUtil.s(d, "voice", w, errors, false))
	o.sprite = StringName(DefUtil.s(d, "sprite", w, errors, false, String(o.id)))
	o.spawn = StringName(DefUtil.s(d, "spawn", w, errors, false))
	o.jar = DefUtil.i(d, "jar", w, errors, false)
	return o
