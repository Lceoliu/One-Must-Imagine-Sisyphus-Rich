# 自动生成，勿手改。源：content/tuning.json（只含 id 与 type；数值在运行时读）  sha1=0a4a479a52ee024938efd71886bb6bbe4471d194
# 重新生成：node tools/content/codegen.mjs（检查：--check）
class_name Tuning
extends RefCounted
## 设计可调常数（architecture §6.1 tuning.json）。字段由 codegen 生成，数值由 ContentDB 从 JSON 读入（热重载时重新赋值）。

const SHAPE_SHA1: String = "0a4a479a52ee024938efd71886bb6bbe4471d194"

## 山顶海拔（米）（config.js SUMMIT）
var summit: float
## 初始石头半径（米）；stats.r0 是实际使用值（config.js R0）
var r0: float
## 滚动加速度 = 9.8 × 0.714 × 1.6（config.js G_ROLL）
var g_roll: float
## upgrades.js COST_MULT
var cost_mult: float
## upgrades.js GROW_ADD
var grow_add: float
## 按节点深度的价格倍率（upgrades.js DEPTH_MULT）
var depth_mult: PackedFloat64Array
## upgrades.js DISC_CAP
var disc_cap: float
## upgrades.js TAX_CAP
var tax_cap: float
## 顶住：每按一次接下来多少秒倒滑减速（game.js BRACE_T）
var brace_t: float
## 顶住时倒滑速度倍率（game.js BRACE_K）
var brace_k: float
## 每夜最多几个命运宝瓶（stats.amphora_cap 可改）（coins.js CHEST_MAX）
var chest_max: float
## 命运宝瓶：每个停在德拉克马上的转轮 = 今夜已碾价值的这个比例（单个宝瓶的金币合计不超过 15%）（v0.6）
var jar_coin: float
## 命运宝瓶：每份命运再乘 (1 + 这个数 × 石头尺寸档)（卵石 0 档 … 奥林匹斯 6 档），石头越大碾出的命运越多（v0.6）
var jar_tier_k: float
## 命运宝瓶：三个转轮都停在命运上时，命运再乘这个数（v0.6）
var jar_jackpot: float
## 本夜第几次 burst 掉宙斯雷霆（coins.js THUNDER_AT）
var thunder_at: PackedFloat64Array
## meta.js HEAT_CAP
var heat_cap: float
## meta.js STELE_SHOW
var stele_show: float
## meta.js DEADLINE_EMBERS
var deadline_embers: PackedFloat64Array
## 砸地本身的收益：每夜第 1 次砸地 +这么多，之后每次翻倍（2026-10-16 用户定：跳台位置固定，太容易空砸）（v0.6）
var slam_pay: float
## 单次砸地收益的上限（v0.6）
var slam_pay_cap: float
## 第几天起白天会打滑（v0.3 按用户反馈改到第 3 天；2026-10-16 用户定改回第 1 天，靠「踩稳」两级台阶解掉）（game.js L300）
var slip_from_day: float
## 打滑一次石头退多少米（网页 0.3；2026-10-16 用户定 0.4）（game.js L300）
var slip_back: float
## 打滑概率整体倍率（乘在 stats.slip_chance 上；数值搜索用，定下来后折回默认值）（v0.6）
var slip_scale: float
## 负重指数偏移（加在 stats.load_exp 上：石头越大越难推、越费体力；数值搜索用）（v0.6）
var load_k: float
## 大石头额外负重的拐点半径（米）：半径超过它，推起来按 heavy_k 额外变重（推力和体力消耗都吃），封顶 heavy_cap；99 = 关（v0.6）
var heavy_r: float
## 每超过拐点 1 米半径，负重多乘的比例（v0.6）
var heavy_k: float
## 额外负重的上限（1 = 最多重一倍）；承重（stats.heavy_relief）按比例抵消（v0.6）
var heavy_cap: float
## 裂痕保底：城里挡路的东西每晚第一次被撞，至少裂掉这么多（裂痕跨夜保留，攒满就塌）。石头再小，撞几晚也能撞开（2026-10-16 用户定：润物无声的引导，不飘数字）（v0.6）
var crack_pity: float

const FIELDS: PackedStringArray = [
	"summit", "r0", "g_roll", "cost_mult", "grow_add", "depth_mult",
	"disc_cap", "tax_cap", "brace_t", "brace_k", "chest_max", "jar_coin",
	"jar_tier_k", "jar_jackpot", "thunder_at", "heat_cap", "stele_show", "deadline_embers",
	"slam_pay", "slam_pay_cap", "slip_from_day", "slip_back", "slip_scale", "load_k",
	"heavy_r", "heavy_k", "heavy_cap", "crack_pity",
]
const TYPES: Dictionary = {
	&"summit": "float", &"r0": "float", &"g_roll": "float", &"cost_mult": "float", &"grow_add": "float", &"depth_mult": "float_array",
	&"disc_cap": "float", &"tax_cap": "float", &"brace_t": "float", &"brace_k": "float", &"chest_max": "float", &"jar_coin": "float",
	&"jar_tier_k": "float", &"jar_jackpot": "float", &"thunder_at": "float_array", &"heat_cap": "float", &"stele_show": "float", &"deadline_embers": "float_array",
	&"slam_pay": "float", &"slam_pay_cap": "float", &"slip_from_day": "float", &"slip_back": "float", &"slip_scale": "float", &"load_k": "float",
	&"heavy_r": "float", &"heavy_k": "float", &"heavy_cap": "float", &"crack_pity": "float",
}

## 从 tuning.json 的条目数组读入；返回错误列表（空 = 成功）。
func load_entries(arr: Array) -> PackedStringArray:
	var errs: PackedStringArray = []
	var seen: Dictionary = {}
	for e: Variant in arr:
		if not (e is Dictionary) or not (e as Dictionary).has("id"):
			errs.append("tuning.json：条目缺少 id")
			continue
		var d: Dictionary = e
		var id: StringName = StringName(str(d["id"]))
		if not TYPES.has(id):
			errs.append("tuning.json：未生成的字段 %s（运行 node tools/content/codegen.mjs）" % id)
			continue
		var ty: String = TYPES[id]
		if str(d.get("type", "")) != ty:
			errs.append("tuning.json：%s 的 type 与生成代码不一致" % id)
			continue
		var v: Variant = d.get("value")
		match ty:
			"float":
				if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
					errs.append("tuning.json：%s 应为数" % id)
					continue
				set(id, float(v))
			"int":
				set(id, int(v))
			"float_array":
				if not (v is Array):
					errs.append("tuning.json：%s 应为数组" % id)
					continue
				set(id, PackedFloat64Array(v))
			"float_table":
				var rows: Array[PackedFloat64Array] = []
				for r: Variant in v:
					rows.append(PackedFloat64Array(r))
				set(id, rows)
		seen[id] = true
	for f: String in FIELDS:
		if not seen.has(StringName(f)):
			errs.append("tuning.json：缺少字段 %s" % f)
	return errs
