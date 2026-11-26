# 自动生成，勿手改。源：content/stats/{core,shop,shrine,boons,meta,story}.json  sha1=a9330e46f966afb02c41ff7948a1e6024310f908
# 重新生成：node tools/content/codegen.mjs（检查：--check）
class_name Stats
extends RefCounted
## 一天的属性（= 网页 g.stats）。字段声明在 content/stats/*.json；构建顺序见 sim/content/stats_builder.gd（architecture §5.1）。
## DSL 用 get / set 按名字读写（ContentDB 加载期已校验名字和类型）；游戏代码直接读带类型的字段。

const SOURCE_SHA1: String = "a9330e46f966afb02c41ff7948a1e6024310f908"
const SOURCE_FILES: PackedStringArray = ["stats/core.json", "stats/shop.json", "stats/shrine.json", "stats/boons.json", "stats/meta.json", "stats/story.json"]

# —— stats/core.json ——
var push_power: float = 1.0
var stride: float = 0.4
var steep_bonus: float = 0.0
var slope_resist: float = 1.0
var hold_push: bool = false
var hold_rate: float = 4.5
var auto_push: float = 0.0
var helper_push: float = 0.0
var helper_mult: float = 1.0
var ghosts: float = 0.0
var spartans: float = 0.0
var charon: bool = false
var cerberus: bool = false
var stamina_max: float = 120.0
var stamina_regen: float = 20.0
var push_cost: float = 3.8
var no_stamina: bool = false
var slip_chance: float = 0.06
var stumble: float = 0.35
var backslide: float = 0.9
var start_frac: float = 0.0
var day_length: float = 60.0
var load_exp: float = 0.9
var sweat_pay: float = 0.0
var growth: float = 0.0075
var absorb: float = 1.0
var living_mult: float = 1.0
var mass_mult: float = 1.0
var value_mult: float = 1.0
var gold_vein: float = 0.0
var devour: bool = false
var req_mult: float = 1.0
var combo_window: float = 1.5
var combo_step: float = 0.1
var combo_cap: float = 3.0
var crit_perfect: float = 3.0
var crit_good: float = 1.5
var slam_charges: float = 1.0
var slam_radius: float = 2.2
var unstoppable: bool = false
var aftershock: float = 0.0
var pasture: float = 0.0
var potters: float = 0.0
var rebuild: float = 0.0
var city_value: float = 1.0
var ramps: bool = false
var domino: float = 0.0
var gate_mult: float = 1.0
var start_speed: float = 0.0
var tax: float = 0.1
var zeus: bool = false
var auto_crit: float = 0.0
var fire: float = 0.0
var size_exp: float = 0.35
var r0: float = 0.6
var rest_regen: float = 2.0
var idle_grace: float = 0.8
var faint_delay: float = 0.25
var faint_slide_mult: float = 1.5
var faint_slide_cap: float = 2.5
var faint_exit: float = 0.35
var second_wind: float = 0.2
var faint_guard: float = 0.0
var helper_guard: float = 0.0
var rhythm_step: float = 0.03
var rhythm_lo: float = 0.18
var rhythm_hi: float = 0.5
var dawn_push: float = 0.0
var am_push: float = 0.0
var pm_push: float = 0.0
var am_helper: float = 0.0
var start_size: float = 1.0
var night_speed: float = 1.0
var absorb_falloff: float = 4.0
var combo_growth: float = 0.0
var combo_growth_at: float = 25.0
var speed_value: float = 0.0
var speed_grow: float = 0.0
var speed_revel: float = 0.0
var air_value: float = 1.0
var auto_slam_on_land: bool = false
var slam_value: float = 1.5
var air_combo: bool = false
var land_combo: float = 0.0
var crit_window: float = 1.0
var revel_chance: float = 0.0
var revel_mult: float = 5.0
var helper_revel: float = 0.0
var crush_drag: float = 1.0
var crush_accel: float = 0.0
var helper_value: float = 0.0
var max_stuck: float = 70.0
var gate_seal_add: float = 0.0
var max_seals: float = 9.0
var seal_mult_per: float = 0.15
var seal_exp: bool = false
var no_gate_penalty: float = 0.0
var size_seals: float = 0.0
var combo_seals: float = 0.0
var amphora_mult: float = 1.0
var amphora_cap: float = 4.0
var amphora_common: float = 0.7
var magnet_mult: float = 1.0
var zeus_dur: float = 6.0
var obj_density: float = 1.0
# —— stats/shop.json ——
var branch_disc: Dictionary[String, float] = {}
var branch_tax: Dictionary[String, float] = {}
var node_disc: Dictionary[String, float] = {}
var node_tax: Dictionary[String, float] = {}
var shop_disc: float = 0.0
var shop_tax: float = 0.0
## 已解封的隐藏天赋 key（含 onefinger+）
var unlocked_nodes: Dictionary[String, bool] = {}
## 命运宝瓶：每份命运的倍率（三女神 · 纺锤）
var moira_mult: float = 1.0
## 命运宝瓶：每个转轮停在命运上的概率（三女神 · 量尺）
var moira_p: float = 0.4
## 最后一剪：夜里结算后整条山坡再结算的比例
var last_cut: float = 0.0
## 抵消掉的「大石头额外负重」比例（承重，tuning.heavy_*；2026-10-16 平台 / 阶梯）
var heavy_relief: float = 0.0
# —— stats/shrine.json ——
var shrine_extra: float = 0.0
var shrine_luck: float = 0.0
var shrine_blind: float = 0.0
var shrine_reroll: float = 0.0
var shrine_cards: float = 3.0
var gaze_chance: float = 0.25
var gaze_comp: float = 1.0
var no_zeus_gaze: bool = false
# —— stats/boons.json ——
var altar_cards: float = 3.0
var altar_reroll: float = 0.0
var trips_max: float = 0.0
var trip_height: float = 0.0
var trip_step: float = 0.0
var restock: float = 0.0
var trip_speed: float = 1.0
var trip_ring: float = 0.0
var combo_carry: bool = false
var faith_trips: bool = false
var express_rate: float = 0.0
var express_range: float = 15.0
var knock_max: float = 1.0
var knock_bounce: float = 0.5
var knock_pull: float = 0.0
var knock_pay: float = 0.0
var knock_accum: bool = false
var knock_min_seal: float = 0.0
var seal_exp_cap: float = 12.0
var styx_band: float = 0.0
var styx_value: float = 1.0
var gate2_alt: float = 0.0
var psycho_seal: float = 0.0
var day_clock: float = 1.0
var overtime: float = 0.0
var overtime_push: float = 0.8
var sunset_t: float = 0.0
var sunset_value: float = 0.0
var phaethon: bool = false
var sacred_cattle: float = 0.0
var core_keep: float = 0.0
var core_cap: float = 0.0
var core_cap_k: float = 0.0
var slide_on_big: float = 0.0
var children: float = 0.0
var child_frac: float = 0.4
var strata: float = 0.0
## 0 关 / 1 石头滚动时连碾不断 / 2 始终不断（网页是 false / true / 'always'）
var beat_keep: int = 0
var beat_period: float = 0.5
var harmony_max: float = 0.0
var harmony_val: float = 0.05
var harmony_floor: float = 0.0
var wave_every: float = 0.0
var wave_range: float = 12.0
var wave_tier: float = 2.0
var encore: float = 0.0
var laurel: float = 0.0
var civic_push: float = 0.0
var civic_cap: float = 0.3
var phalanx_rate: float = 0.0
var phalanx_range: float = 10.0
var phalanx_tier: float = 2.0
var helper_cap: float = 24.0
var helper_value_cap: float = 0.0
var hoplite: bool = false
var aegis: float = 0.0
var perseus: bool = false
var workshop_slam: float = 0.0
var track_from: float = 0.0
var track_to: float = 0.0
var track_boost: float = 0.0
var tripods: float = 0.0
var talos: float = 0.0
var auto_rhythm: bool = false
var net_window: float = 0.0
var revel_fill: float = 0.0
var revel_dur: float = 0.0
var revel_value: float = 1.0
var revel_req: float = 1.0
var revel_carry: float = 0.0
var revel_grow: float = 1.0
var revel_quake: float = 0.0
var stride_lo: float = 1.0
var stride_hi: float = 1.0
var thiasos: float = 0.0
var vine: float = 0.0
var delphi_fill: float = 0.0
var nysa_fill: float = 0.0
## 宿敌路障：神 id → 座数
var roadblocks: Dictionary[String, float] = {}
## 怨气冷脸：god_<神> → 神龛卡权重系数
var grudge_shrine_w: Dictionary[String, float] = {}
var drunkards: float = 0.0
var core_cap_add: float = 0.0
var net_air: float = 1.0
## 集齐三阶的主神 id（"" = 无；网页是 null）
var patron: StringName = &""
## 跳台是铜轨跳台卡白送的（网页临时字段 _hpRamps）
var hp_ramps_free: bool = false
# —— stats/meta.json ——
var path_push: float = 0.0
var path_alt: float = 0.0
## 本代石头 basic / moon / urn
var stone: StringName = &"basic"
var no_stick: bool = false
var speed_stack: float = 0.0
var speed_stack_cap: float = 0.0
var urn_cap: float = 0.0
var urn_mult: float = 1.5
var deadline: float = 0.0
## 祖传「老主顾」已计入 shop_disc（网页临时字段 _metaPatron）
var meta_patron: bool = false
# —— stats/story.json ——
var start_back: float = 0.0

## 字段名（声明顺序）
const FIELDS: PackedStringArray = [
	"push_power", "stride", "steep_bonus", "slope_resist", "hold_push", "hold_rate",
	"auto_push", "helper_push", "helper_mult", "ghosts", "spartans", "charon",
	"cerberus", "stamina_max", "stamina_regen", "push_cost", "no_stamina", "slip_chance",
	"stumble", "backslide", "start_frac", "day_length", "load_exp", "sweat_pay",
	"growth", "absorb", "living_mult", "mass_mult", "value_mult", "gold_vein",
	"devour", "req_mult", "combo_window", "combo_step", "combo_cap", "crit_perfect",
	"crit_good", "slam_charges", "slam_radius", "unstoppable", "aftershock", "pasture",
	"potters", "rebuild", "city_value", "ramps", "domino", "gate_mult",
	"start_speed", "tax", "zeus", "auto_crit", "fire", "size_exp",
	"r0", "rest_regen", "idle_grace", "faint_delay", "faint_slide_mult", "faint_slide_cap",
	"faint_exit", "second_wind", "faint_guard", "helper_guard", "rhythm_step", "rhythm_lo",
	"rhythm_hi", "dawn_push", "am_push", "pm_push", "am_helper", "start_size",
	"night_speed", "absorb_falloff", "combo_growth", "combo_growth_at", "speed_value", "speed_grow",
	"speed_revel", "air_value", "auto_slam_on_land", "slam_value", "air_combo", "land_combo",
	"crit_window", "revel_chance", "revel_mult", "helper_revel", "crush_drag", "crush_accel",
	"helper_value", "max_stuck", "gate_seal_add", "max_seals", "seal_mult_per", "seal_exp",
	"no_gate_penalty", "size_seals", "combo_seals", "amphora_mult", "amphora_cap", "amphora_common",
	"magnet_mult", "zeus_dur", "obj_density", "branch_disc", "branch_tax", "node_disc",
	"node_tax", "shop_disc", "shop_tax", "unlocked_nodes", "moira_mult", "moira_p",
	"last_cut", "heavy_relief", "shrine_extra", "shrine_luck", "shrine_blind", "shrine_reroll",
	"shrine_cards", "gaze_chance", "gaze_comp", "no_zeus_gaze", "altar_cards", "altar_reroll",
	"trips_max", "trip_height", "trip_step", "restock", "trip_speed", "trip_ring",
	"combo_carry", "faith_trips", "express_rate", "express_range", "knock_max", "knock_bounce",
	"knock_pull", "knock_pay", "knock_accum", "knock_min_seal", "seal_exp_cap", "styx_band",
	"styx_value", "gate2_alt", "psycho_seal", "day_clock", "overtime", "overtime_push",
	"sunset_t", "sunset_value", "phaethon", "sacred_cattle", "core_keep", "core_cap",
	"core_cap_k", "slide_on_big", "children", "child_frac", "strata", "beat_keep",
	"beat_period", "harmony_max", "harmony_val", "harmony_floor", "wave_every", "wave_range",
	"wave_tier", "encore", "laurel", "civic_push", "civic_cap", "phalanx_rate",
	"phalanx_range", "phalanx_tier", "helper_cap", "helper_value_cap", "hoplite", "aegis",
	"perseus", "workshop_slam", "track_from", "track_to", "track_boost", "tripods",
	"talos", "auto_rhythm", "net_window", "revel_fill", "revel_dur", "revel_value",
	"revel_req", "revel_carry", "revel_grow", "revel_quake", "stride_lo", "stride_hi",
	"thiasos", "vine", "delphi_fill", "nysa_fill", "roadblocks", "grudge_shrine_w",
	"drunkards", "core_cap_add", "net_air", "patron", "hp_ramps_free", "path_push",
	"path_alt", "stone", "no_stick", "speed_stack", "speed_stack_cap", "urn_cap",
	"urn_mult", "deadline", "meta_patron", "start_back",
]
## 字段 → 类型（float int bool name dict_float dict_bool）
const TYPES: Dictionary = {
	&"push_power": "float", &"stride": "float", &"steep_bonus": "float", &"slope_resist": "float", &"hold_push": "bool", &"hold_rate": "float",
	&"auto_push": "float", &"helper_push": "float", &"helper_mult": "float", &"ghosts": "float", &"spartans": "float", &"charon": "bool",
	&"cerberus": "bool", &"stamina_max": "float", &"stamina_regen": "float", &"push_cost": "float", &"no_stamina": "bool", &"slip_chance": "float",
	&"stumble": "float", &"backslide": "float", &"start_frac": "float", &"day_length": "float", &"load_exp": "float", &"sweat_pay": "float",
	&"growth": "float", &"absorb": "float", &"living_mult": "float", &"mass_mult": "float", &"value_mult": "float", &"gold_vein": "float",
	&"devour": "bool", &"req_mult": "float", &"combo_window": "float", &"combo_step": "float", &"combo_cap": "float", &"crit_perfect": "float",
	&"crit_good": "float", &"slam_charges": "float", &"slam_radius": "float", &"unstoppable": "bool", &"aftershock": "float", &"pasture": "float",
	&"potters": "float", &"rebuild": "float", &"city_value": "float", &"ramps": "bool", &"domino": "float", &"gate_mult": "float",
	&"start_speed": "float", &"tax": "float", &"zeus": "bool", &"auto_crit": "float", &"fire": "float", &"size_exp": "float",
	&"r0": "float", &"rest_regen": "float", &"idle_grace": "float", &"faint_delay": "float", &"faint_slide_mult": "float", &"faint_slide_cap": "float",
	&"faint_exit": "float", &"second_wind": "float", &"faint_guard": "float", &"helper_guard": "float", &"rhythm_step": "float", &"rhythm_lo": "float",
	&"rhythm_hi": "float", &"dawn_push": "float", &"am_push": "float", &"pm_push": "float", &"am_helper": "float", &"start_size": "float",
	&"night_speed": "float", &"absorb_falloff": "float", &"combo_growth": "float", &"combo_growth_at": "float", &"speed_value": "float", &"speed_grow": "float",
	&"speed_revel": "float", &"air_value": "float", &"auto_slam_on_land": "bool", &"slam_value": "float", &"air_combo": "bool", &"land_combo": "float",
	&"crit_window": "float", &"revel_chance": "float", &"revel_mult": "float", &"helper_revel": "float", &"crush_drag": "float", &"crush_accel": "float",
	&"helper_value": "float", &"max_stuck": "float", &"gate_seal_add": "float", &"max_seals": "float", &"seal_mult_per": "float", &"seal_exp": "bool",
	&"no_gate_penalty": "float", &"size_seals": "float", &"combo_seals": "float", &"amphora_mult": "float", &"amphora_cap": "float", &"amphora_common": "float",
	&"magnet_mult": "float", &"zeus_dur": "float", &"obj_density": "float", &"branch_disc": "dict_float", &"branch_tax": "dict_float", &"node_disc": "dict_float",
	&"node_tax": "dict_float", &"shop_disc": "float", &"shop_tax": "float", &"unlocked_nodes": "dict_bool", &"moira_mult": "float", &"moira_p": "float",
	&"last_cut": "float", &"heavy_relief": "float", &"shrine_extra": "float", &"shrine_luck": "float", &"shrine_blind": "float", &"shrine_reroll": "float",
	&"shrine_cards": "float", &"gaze_chance": "float", &"gaze_comp": "float", &"no_zeus_gaze": "bool", &"altar_cards": "float", &"altar_reroll": "float",
	&"trips_max": "float", &"trip_height": "float", &"trip_step": "float", &"restock": "float", &"trip_speed": "float", &"trip_ring": "float",
	&"combo_carry": "bool", &"faith_trips": "bool", &"express_rate": "float", &"express_range": "float", &"knock_max": "float", &"knock_bounce": "float",
	&"knock_pull": "float", &"knock_pay": "float", &"knock_accum": "bool", &"knock_min_seal": "float", &"seal_exp_cap": "float", &"styx_band": "float",
	&"styx_value": "float", &"gate2_alt": "float", &"psycho_seal": "float", &"day_clock": "float", &"overtime": "float", &"overtime_push": "float",
	&"sunset_t": "float", &"sunset_value": "float", &"phaethon": "bool", &"sacred_cattle": "float", &"core_keep": "float", &"core_cap": "float",
	&"core_cap_k": "float", &"slide_on_big": "float", &"children": "float", &"child_frac": "float", &"strata": "float", &"beat_keep": "int",
	&"beat_period": "float", &"harmony_max": "float", &"harmony_val": "float", &"harmony_floor": "float", &"wave_every": "float", &"wave_range": "float",
	&"wave_tier": "float", &"encore": "float", &"laurel": "float", &"civic_push": "float", &"civic_cap": "float", &"phalanx_rate": "float",
	&"phalanx_range": "float", &"phalanx_tier": "float", &"helper_cap": "float", &"helper_value_cap": "float", &"hoplite": "bool", &"aegis": "float",
	&"perseus": "bool", &"workshop_slam": "float", &"track_from": "float", &"track_to": "float", &"track_boost": "float", &"tripods": "float",
	&"talos": "float", &"auto_rhythm": "bool", &"net_window": "float", &"revel_fill": "float", &"revel_dur": "float", &"revel_value": "float",
	&"revel_req": "float", &"revel_carry": "float", &"revel_grow": "float", &"revel_quake": "float", &"stride_lo": "float", &"stride_hi": "float",
	&"thiasos": "float", &"vine": "float", &"delphi_fill": "float", &"nysa_fill": "float", &"roadblocks": "dict_float", &"grudge_shrine_w": "dict_float",
	&"drunkards": "float", &"core_cap_add": "float", &"net_air": "float", &"patron": "name", &"hp_ramps_free": "bool", &"path_push": "float",
	&"path_alt": "float", &"stone": "name", &"no_stick": "bool", &"speed_stack": "float", &"speed_stack_cap": "float", &"urn_cap": "float",
	&"urn_mult": "float", &"deadline": "float", &"meta_patron": "bool", &"start_back": "float",
}
## 字段 → 网页名（对拍用）
const PROTO_NAME: Dictionary = {
	&"push_power": "pushPower", &"stride": "stride", &"steep_bonus": "steepBonus", &"slope_resist": "slopeResist", &"hold_push": "holdPush", &"hold_rate": "holdRate",
	&"auto_push": "autoPush", &"helper_push": "helperPush", &"helper_mult": "helperMult", &"ghosts": "ghosts", &"spartans": "spartans", &"charon": "charon",
	&"cerberus": "cerberus", &"stamina_max": "staminaMax", &"stamina_regen": "staminaRegen", &"push_cost": "pushCost", &"no_stamina": "noStamina", &"slip_chance": "slipChance",
	&"stumble": "stumble", &"backslide": "backslide", &"start_frac": "startFrac", &"day_length": "dayLength", &"load_exp": "loadExp", &"sweat_pay": "sweatPay",
	&"growth": "growth", &"absorb": "absorb", &"living_mult": "livingMult", &"mass_mult": "massMult", &"value_mult": "valueMult", &"gold_vein": "goldVein",
	&"devour": "devour", &"req_mult": "reqMult", &"combo_window": "comboWindow", &"combo_step": "comboStep", &"combo_cap": "comboCap", &"crit_perfect": "critPerfect",
	&"crit_good": "critGood", &"slam_charges": "slamCharges", &"slam_radius": "slamRadius", &"unstoppable": "unstoppable", &"aftershock": "aftershock", &"pasture": "pasture",
	&"potters": "potters", &"rebuild": "rebuild", &"city_value": "cityValue", &"ramps": "ramps", &"domino": "domino", &"gate_mult": "gateMult",
	&"start_speed": "startSpeed", &"tax": "tax", &"zeus": "zeus", &"auto_crit": "autoCrit", &"fire": "fire", &"size_exp": "sizeExp",
	&"r0": "r0", &"rest_regen": "restRegen", &"idle_grace": "idleGrace", &"faint_delay": "faintDelay", &"faint_slide_mult": "faintSlideMult", &"faint_slide_cap": "faintSlideCap",
	&"faint_exit": "faintExit", &"second_wind": "secondWind", &"faint_guard": "faintGuard", &"helper_guard": "helperGuard", &"rhythm_step": "rhythmStep", &"rhythm_lo": "rhythmLo",
	&"rhythm_hi": "rhythmHi", &"dawn_push": "dawnPush", &"am_push": "amPush", &"pm_push": "pmPush", &"am_helper": "amHelper", &"start_size": "startSize",
	&"night_speed": "nightSpeed", &"absorb_falloff": "absorbFalloff", &"combo_growth": "comboGrowth", &"combo_growth_at": "comboGrowthAt", &"speed_value": "speedValue", &"speed_grow": "speedGrow",
	&"speed_revel": "speedRevel", &"air_value": "airValue", &"auto_slam_on_land": "autoSlamOnLand", &"slam_value": "slamValue", &"air_combo": "airCombo", &"land_combo": "landCombo",
	&"crit_window": "critWindow", &"revel_chance": "revelChance", &"revel_mult": "revelMult", &"helper_revel": "helperRevel", &"crush_drag": "crushDrag", &"crush_accel": "crushAccel",
	&"helper_value": "helperValue", &"max_stuck": "maxStuck", &"gate_seal_add": "gateSealAdd", &"max_seals": "maxSeals", &"seal_mult_per": "sealMultPer", &"seal_exp": "sealExp",
	&"no_gate_penalty": "noGatePenalty", &"size_seals": "sizeSeals", &"combo_seals": "comboSeals", &"amphora_mult": "amphoraMult", &"amphora_cap": "amphoraCap", &"amphora_common": "amphoraCommon",
	&"magnet_mult": "magnetMult", &"zeus_dur": "zeusDur", &"obj_density": "objDensity", &"branch_disc": "branchDisc", &"branch_tax": "branchTax", &"node_disc": "nodeDisc",
	&"node_tax": "nodeTax", &"shop_disc": "shopDisc", &"shop_tax": "shopTax", &"unlocked_nodes": "unlockedNodes", &"moira_mult": "moiraMult", &"moira_p": "moiraP",
	&"last_cut": "lastCut", &"heavy_relief": "heavyRelief", &"shrine_extra": "shrineExtra", &"shrine_luck": "shrineLuck", &"shrine_blind": "shrineBlind", &"shrine_reroll": "shrineReroll",
	&"shrine_cards": "shrineCards", &"gaze_chance": "gazeChance", &"gaze_comp": "gazeComp", &"no_zeus_gaze": "noZeusGaze", &"altar_cards": "altarCards", &"altar_reroll": "altarReroll",
	&"trips_max": "tripsMax", &"trip_height": "tripHeight", &"trip_step": "tripStep", &"restock": "restock", &"trip_speed": "tripSpeed", &"trip_ring": "tripRing",
	&"combo_carry": "comboCarry", &"faith_trips": "faithTrips", &"express_rate": "expressRate", &"express_range": "expressRange", &"knock_max": "knockMax", &"knock_bounce": "knockBounce",
	&"knock_pull": "knockPull", &"knock_pay": "knockPay", &"knock_accum": "knockAccum", &"knock_min_seal": "knockMinSeal", &"seal_exp_cap": "sealExpCap", &"styx_band": "styxBand",
	&"styx_value": "styxValue", &"gate2_alt": "gate2Alt", &"psycho_seal": "psychoSeal", &"day_clock": "dayClock", &"overtime": "overtime", &"overtime_push": "overtimePush",
	&"sunset_t": "sunsetT", &"sunset_value": "sunsetValue", &"phaethon": "phaethon", &"sacred_cattle": "sacredCattle", &"core_keep": "coreKeep", &"core_cap": "coreCap",
	&"core_cap_k": "coreCapK", &"slide_on_big": "slideOnBig", &"children": "children", &"child_frac": "childFrac", &"strata": "strata", &"beat_keep": "beatKeep",
	&"beat_period": "beatPeriod", &"harmony_max": "harmonyMax", &"harmony_val": "harmonyVal", &"harmony_floor": "harmonyFloor", &"wave_every": "waveEvery", &"wave_range": "waveRange",
	&"wave_tier": "waveTier", &"encore": "encore", &"laurel": "laurel", &"civic_push": "civicPush", &"civic_cap": "civicCap", &"phalanx_rate": "phalanxRate",
	&"phalanx_range": "phalanxRange", &"phalanx_tier": "phalanxTier", &"helper_cap": "helperCap", &"helper_value_cap": "helperValueCap", &"hoplite": "hoplite", &"aegis": "aegis",
	&"perseus": "perseus", &"workshop_slam": "workshopSlam", &"track_from": "trackFrom", &"track_to": "trackTo", &"track_boost": "trackBoost", &"tripods": "tripods",
	&"talos": "talos", &"auto_rhythm": "autoRhythm", &"net_window": "netWindow", &"revel_fill": "revelFill", &"revel_dur": "revelDur", &"revel_value": "revelValue",
	&"revel_req": "revelReq", &"revel_carry": "revelCarry", &"revel_grow": "revelGrow", &"revel_quake": "revelQuake", &"stride_lo": "strideLo", &"stride_hi": "strideHi",
	&"thiasos": "thiasos", &"vine": "vine", &"delphi_fill": "delphiFill", &"nysa_fill": "nysaFill", &"roadblocks": "roadblocks", &"grudge_shrine_w": "grudgeShrineW",
	&"drunkards": "drunkards", &"core_cap_add": "coreCapAdd", &"net_air": "netAir", &"patron": "patron", &"hp_ramps_free": "_hpRamps", &"path_push": "pathPush",
	&"path_alt": "pathAlt", &"stone": "stone", &"no_stick": "noStick", &"speed_stack": "speedStack", &"speed_stack_cap": "speedStackCap", &"urn_cap": "urnCap",
	&"urn_mult": "urnMult", &"deadline": "deadline", &"meta_patron": "_metaPatron", &"start_back": "startBack",
}
## 只由赐福卡按 max / min 叠加的字段：BoonSystem.apply_stats 先归到这些中性值（boon_data.js CARD_NEUTRAL）
const CARD_NEUTRAL: Dictionary = {&"trip_height": 0.0, &"revel_dur": 0.0, &"revel_value": 1.0, &"revel_req": 1.0}


## 深拷贝（字典字段各自复制）。
func copy() -> Stats:
	var o: Stats = Stats.new()
	for f: String in FIELDS:
		var v: Variant = get(f)
		o.set(f, v.duplicate() if v is Dictionary else v)
	return o


## 字段名 → 值（字典字段是副本）。调试面板、golden、hash 用。
func to_dict() -> Dictionary:
	var d: Dictionary = {}
	for f: String in FIELDS:
		var v: Variant = get(f)
		d[f] = v.duplicate() if v is Dictionary else v
	return d


## 网页名 → 网页值（类型清洗反向：beat_keep 0/1/2 → false/true/"always"；patron "" → null；name 字段转 String）。对拍网页导出的 stats 用。
func to_proto_dict() -> Dictionary:
	var d: Dictionary = {}
	for f: String in FIELDS:
		var v: Variant = get(f)
		if f == "beat_keep":
			v = "always" if beat_keep == 2 else beat_keep == 1
		elif f == "patron":
			v = null if patron == &"" else String(patron)
		elif v is StringName:
			v = String(v)
		elif v is Dictionary:
			v = v.duplicate()
		d[PROTO_NAME[StringName(f)]] = v
	return d


## 字段是否存在（DSL 校验用）。
static func has_field(f: StringName) -> bool:
	return TYPES.has(f)
