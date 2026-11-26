# 自动生成，勿手改。源：content/stats/day_mods.json  sha1=79df698a1091e11f7f8822903f1a56e4ea21e2e8
# 重新生成：node tools/content/codegen.mjs（检查：--check）
class_name DayMods
extends RefCounted
## 今日修正（= 网页 events.js 的 ev.mods）。字段、默认值、合成方式和钳制区间声明在 content/stats/day_mods.json；
## 合成（recompute）由 ShrineSystem 实现（S），可按 SPEC 通用处理。

const SOURCE_SHA1: String = "79df698a1091e11f7f8822903f1a56e4ea21e2e8"

var push_mult: float = 1.0
var stamina_cost_mult: float = 1.0
var no_backslide: bool = false
var slip_immune: float = 0.0
var day_time_add: float = 0.0
var night_value_mult: float = 1.0
var night_speed_mult: float = 1.0
var start_size_mult: float = 1.0
var growth_mult: float = 1.0
var combo_no_break: bool = false
var magnet_mult: float = 1.0
var gate_seal_bonus: float = 0.0
var faint_guard: float = 0.0
var faint_regen: float = 1.0
var regen_mult: float = 1.0
var am_push: float = 0.0
var helper_mult: float = 1.0
var day_time_mult: float = 1.0
var living_mult: float = 1.0
var combo_window_add: float = 0.0
var crit_window_mult: float = 1.0
var req_mult: float = 1.0
var seal_mult_per_mult: float = 1.0
var auto_crit_all: bool = false
var auto_crit_every: float = 0.0

const FIELDS: PackedStringArray = [
	"push_mult", "stamina_cost_mult", "no_backslide", "slip_immune", "day_time_add", "night_value_mult",
	"night_speed_mult", "start_size_mult", "growth_mult", "combo_no_break", "magnet_mult", "gate_seal_bonus",
	"faint_guard", "faint_regen", "regen_mult", "am_push", "helper_mult", "day_time_mult",
	"living_mult", "combo_window_add", "crit_window_mult", "req_mult", "seal_mult_per_mult", "auto_crit_all",
	"auto_crit_every",
]
const PROTO_NAME: Dictionary = {
	&"push_mult": "pushMult", &"stamina_cost_mult": "staminaCostMult", &"no_backslide": "noBackslide", &"slip_immune": "slipImmune", &"day_time_add": "dayTimeAdd", &"night_value_mult": "nightValueMult",
	&"night_speed_mult": "nightSpeedMult", &"start_size_mult": "startSizeMult", &"growth_mult": "growthMult", &"combo_no_break": "comboNoBreak", &"magnet_mult": "magnetMult", &"gate_seal_bonus": "gateSealBonus",
	&"faint_guard": "faintGuard", &"faint_regen": "faintRegen", &"regen_mult": "regenMult", &"am_push": "amPush", &"helper_mult": "helperMult", &"day_time_mult": "dayTimeMult",
	&"living_mult": "livingMult", &"combo_window_add": "comboWindowAdd", &"crit_window_mult": "critWindowMult", &"req_mult": "reqMult", &"seal_mult_per_mult": "sealMultPerMult", &"auto_crit_all": "autoCritAll",
	&"auto_crit_every": "autoCritEvery",
}
## 字段 → {src, combine, clamp?, offset?, clamp_on?}（照抄 day_mods.json，note 除外）
const SPEC: Dictionary = {
	&"push_mult": {"src": "push", "combine": "mul", "clamp": [0.0, 4.0]},
	&"stamina_cost_mult": {"src": "cost", "combine": "mul", "clamp": [0.0, 2.0]},
	&"no_backslide": {"src": "no_back", "combine": "or"},
	&"slip_immune": {"src": "slip", "combine": "add"},
	&"day_time_add": {"src": "day_add", "combine": "add"},
	&"night_value_mult": {"src": "night.value", "combine": "add", "clamp": [0.0, 3.0], "offset": 1.0, "clamp_on": "sum"},
	&"night_speed_mult": {"src": "night.speed", "combine": "mul", "clamp": [0.5, 1.6]},
	&"start_size_mult": {"src": "night.size", "combine": "mul", "clamp": [0.5, 2.0]},
	&"growth_mult": {"src": "night.growth", "combine": "mul", "clamp": [0.5, 3.0]},
	&"combo_no_break": {"src": "night.combo", "combine": "or"},
	&"magnet_mult": {"src": "night.magnet", "combine": "mul", "clamp": [0.5, 4.0]},
	&"gate_seal_bonus": {"src": "night.seal", "combine": "add", "clamp": [0.0, 4.0]},
	&"faint_guard": {"src": "faint_guard", "combine": "max", "clamp": [0.0, 2.0]},
	&"faint_regen": {"src": "faint_regen", "combine": "max", "clamp": [1.0, 2.0]},
	&"regen_mult": {"src": "day_boost.regen_mult", "combine": "mul", "clamp": [0.5, 3.0]},
	&"am_push": {"src": "am_push", "combine": "add", "clamp": [0.0, 1.0]},
	&"helper_mult": {"src": "helper_mult", "combine": "mul", "clamp": [1.0, 3.0]},
	&"day_time_mult": {"src": "day_time_mult", "combine": "min", "clamp": [0.5, 1.0]},
	&"living_mult": {"src": "night.living", "combine": "add", "clamp": [1.0, 3.0], "offset": 1.0, "clamp_on": "value"},
	&"combo_window_add": {"src": "night.combo_win", "combine": "add", "clamp": [0.0, 2.0]},
	&"crit_window_mult": {"src": "night.crit_win", "combine": "mul", "clamp": [1.0, 3.0]},
	&"req_mult": {"src": "night.req", "combine": "mul", "clamp": [0.6, 1.0]},
	&"seal_mult_per_mult": {"src": "night.seal_per", "combine": "mul", "clamp": [1.0, 3.0]},
	&"auto_crit_all": {"src": "night.auto_crit_all", "combine": "or"},
	&"auto_crit_every": {"src": "night.auto_crit_every", "combine": "min_nz"},
}

## 全部字段回到默认值（= Object.assign(mods, defaultMods())，保持对象引用不变）。
func reset() -> void:
	push_mult = 1.0
	stamina_cost_mult = 1.0
	no_backslide = false
	slip_immune = 0.0
	day_time_add = 0.0
	night_value_mult = 1.0
	night_speed_mult = 1.0
	start_size_mult = 1.0
	growth_mult = 1.0
	combo_no_break = false
	magnet_mult = 1.0
	gate_seal_bonus = 0.0
	faint_guard = 0.0
	faint_regen = 1.0
	regen_mult = 1.0
	am_push = 0.0
	helper_mult = 1.0
	day_time_mult = 1.0
	living_mult = 1.0
	combo_window_add = 0.0
	crit_window_mult = 1.0
	req_mult = 1.0
	seal_mult_per_mult = 1.0
	auto_crit_all = false
	auto_crit_every = 0.0


func copy() -> DayMods:
	var o: DayMods = DayMods.new()
	for f: String in FIELDS:
		o.set(f, get(f))
	return o


func to_dict() -> Dictionary:
	var d: Dictionary = {}
	for f: String in FIELDS:
		d[f] = get(f)
	return d


## 网页名 → 值（对拍用）。
func to_proto_dict() -> Dictionary:
	var d: Dictionary = {}
	for f: String in FIELDS:
		d[PROTO_NAME[StringName(f)]] = get(f)
	return d
