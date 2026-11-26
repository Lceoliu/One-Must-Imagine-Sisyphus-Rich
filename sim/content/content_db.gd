class_name ContentDB
extends RefCounted
## 唯一权威内容的运行时（architecture §6.2）：按固定清单读 content/**/*.json → 带类型的定义对象，
## 校验交叉引用，预编译全部表达式和效果列表。错误一律进 errors（不抛异常），测试要求它为空。
## 纯数据（RefCounted），sim 可以 new 多份（机器人、测试、热重载）；Content autoload 只持有一份并负责热重载。
## 读 JSON 一律走 JsonExact（Godot 自带 JSON 对 ≥13 位有效数字不精确，见 F1 handoff）。

## 固定清单（相对 root）；story/events/*.json 另外扫描
const FILES: PackedStringArray = [
	"tuning.json",
	"stats/core.json", "stats/shop.json", "stats/shrine.json", "stats/boons.json", "stats/meta.json", "stats/story.json", "stats/day_mods.json",
	"world/objects.json", "world/bands.json", "world/city_levels.json", "world/terrain.json", "world/size_tiers.json",
	"shop/branches.json", "shop/nodes.json", "shop/quips.json",
	"boons/gods.json", "boons/cards.json", "boons/altars.json", "rules/modules.json",
	"meta/heirlooms.json", "meta/pacts.json", "meta/stones.json", "meta/heat_rewards.json", "meta/achievements.json",
	"story/story.json", "story/narration.json", "story/summit.json", "story/endings.json", "story/lines.json",
	"art/sprites.json",
	"hub/hub.json",
]
const STAT_FILES: PackedStringArray = ["stats/core.json", "stats/shop.json", "stats/shrine.json", "stats/boons.json", "stats/meta.json", "stats/story.json"]

var root: String = "res://content"
var errors: PackedStringArray = []
## 每个文件的原始 JSON（只读；没有专门定义类的小表直接从这里取）
var raw: Dictionary = {}

var tuning: Tuning
## stats 字段声明（stats/*.json 合并，声明顺序）与今日修正字段声明
var stat_decls: Array[Dictionary] = []
var day_mod_decls: Array[Dictionary] = []

# —— 世界 ——
var objects: Array[ObjDef] = []
var object_by_id: Dictionary = {}
var bands: Array[BandDef] = []
## 城市等级：每级 {lv, name, items: PackedStringArray}
var city_levels: Array[Dictionary] = []
var city_fillers: PackedStringArray = []
var terrain: Dictionary = {}
## 石头尺寸等级 [{min, name}] 与碾碎长大量（按物件档位）
var size_tiers: Array[Dictionary] = []
var absorb_gain: PackedFloat64Array = []

# —— 商店 ——
var branches: Array[Dictionary] = []
var nodes: Array[NodeDef] = []
var node_by_key: Dictionary = {}

# —— 神与祭坛 ——
## 神（立绘、名字、台词；boons/gods.json）。卡（boons/cards.json）只剩插画、名字和效果库，不再发牌
var gods: Array[GodDef] = []
var god_by_id: Dictionary = {}
var cards: Array[CardDef] = []
var card_by_id: Dictionary = {}
## 固定海拔的赐福祭坛（boons/altars.json，按海拔从低到高）：{alt, god, card, name, hi, lo, line, fx: EffectList}
var altars: Array[Dictionary] = []
## [{id, script, view}]，顺序 = 钩子分发顺序（= 网页 MODULES）
var modules: Array[Dictionary] = []

# —— 元进度 ——
var heirlooms: Array[MetaDefs.Heirloom] = []
var heirloom_by_id: Dictionary = {}
var pacts: Array[MetaDefs.Pact] = []
var pact_by_id: Dictionary = {}
var stones: Array[MetaDefs.Stone] = []
var stone_by_id: Dictionary = {}
## 成就（meta/achievements.json）：{id, name, desc, k, ge}
var achievements: Array[Dictionary] = []

# —— 剧情 ——
## story.json：consts（大写常数）、flags（默认值，已类型清洗）、speakers
var story: Dictionary = {}
var story_true_ready: Expr
var passives: Array[StoryDefs.Passive] = []
var summit: Array[StoryDefs.Summit] = []
var endings: Array[StoryDefs.Ending] = []
var ending_by_id: Dictionary = {}
## 夜宴大厅的布局、站点、台词（hub/hub.json，原样；present/hub/hub_view.gd 解释）
var hub: Dictionary = {}
## story/events/*.json：id → DialogGraph（T 编写）
var dialogs: Dictionary = {}

## art/sprites.json：key → {path, w, h}
var sprites: Dictionary = {}

## 发行配置（content/profiles/<id>.json，比如 EA 版裁掉部分流派、结局）：不在 FILES 里，不参与校验和网页对拍。
## 游戏由 Content autoload 套上，机器人用 --profile=<id> 套上，单元测试默认不套（= 完整内容）。空 = 全开
var profile: Dictionary = {}


## 套上发行配置：记下开关表，并把剧情常量、剧情 flags 默认值、登顶菜单按配置改好。找不到或格式不对时记一条错误、不套
func apply_profile(id: String) -> bool:
	var p: String = root + "/profiles/" + id + ".json"
	if not FileAccess.file_exists(p):
		errors.append("缺少发行配置 profiles/%s.json" % id)
		return false
	var v: Variant = JsonExact.parse(FileAccess.get_file_as_string(p), "profiles/%s.json" % id)
	if not (v is Dictionary):
		errors.append("profiles/%s.json：顶层应为对象" % id)
		return false
	profile = v
	var consts: Dictionary = story.get("consts", {})
	var c2: Dictionary = profile.get("story_consts", {})
	for k: Variant in c2:
		consts[k] = c2[k]
	var flags: Dictionary = story.get("flags", {})
	var f2: Dictionary = profile.get("story_flags", {})
	for k: Variant in f2:
		flags[k] = f2[k]
	if profile.has("endings"):
		summit = summit.filter(func(s: StoryDefs.Summit) -> bool: return s.kind == &"continue" or ending_on(s.id))
	# 热度没开放：「带着契约登顶」这类成就拿不到，记录页不列
	if not heat_on():
		achievements = achievements.filter(func(a: Dictionary) -> bool: return str(a.get("k", "")) != "heat_summit")
	# 旁白：去掉指向已关支线的几句（日序 by_day 的键、海拔 by_alt 的 id）
	var noff: Dictionary = profile.get("narration_off", {})
	var nar: Dictionary = raw.get("story/narration.json", {})
	if not noff.is_empty() and not nar.is_empty():
		var bd: Dictionary = nar.get("by_day", {})
		for k: Variant in noff.get("by_day", []):
			bd.erase(str(k))
		var off_alt: Array = noff.get("by_alt", [])
		nar["by_alt"] = (nar.get("by_alt", []) as Array).filter(func(a: Variant) -> bool: return not off_alt.has(str((a as Dictionary).get("id", ""))))
	return true


## 开关：名单字段（pacts / endings / heat_rewards / stones）没写 = 全开
func _listed(field: String, id: StringName) -> bool:
	return not profile.has(field) or (profile[field] as Array).has(String(id))


## 热度机制（冥府契约 + 热度奖励）整体开关：配置写 "heat": false 就全关
func heat_on() -> bool:
	return bool(profile.get("heat", true))


func pact_on(id: StringName) -> bool:
	return heat_on() and _listed("pacts", id)


## 可选石头：没开放的在开局界面灰掉；西西弗斯之石永远开
func stone_on(id: StringName) -> bool:
	return id == &"basic" or _listed("stones", id)


func ending_on(id: StringName) -> bool:
	return _listed("endings", id)


func heat_reward_on(id: StringName) -> bool:
	return heat_on() and _listed("heat_rewards", id)


## 启用的结局（画廊、主菜单"x / N"用）
func endings_on() -> Array[StoryDefs.Ending]:
	return endings.filter(func(e: StoryDefs.Ending) -> bool: return ending_on(e.id))


## 读一个内容目录。root 可以是 res:// 或绝对路径（测试用 tests/fixtures/content_extra 之类的副本）。
static func load_dir(p_root: String = "res://content") -> ContentDB:
	var db: ContentDB = ContentDB.new()
	db.root = p_root.trim_suffix("/")
	db._load()
	return db


func _load() -> void:
	for f: String in FILES:
		var p: String = root + "/" + f
		if not FileAccess.file_exists(p):
			errors.append("缺少内容文件 %s" % f)
			continue
		var v: Variant = JsonExact.parse(FileAccess.get_file_as_string(p), f)
		if v == null:
			errors.append("%s：JSON 解析失败" % f)
			continue
		raw[f] = Loc.localize_json(v, f)
	_load_stats()
	_load_world()
	_load_shop()
	_load_boons()
	_load_meta()
	_load_story()
	sprites = _obj("art/sprites.json")
	hub = _obj("hub/hub.json")
	_validate_refs()


# ———————————————— 各表 ————————————————

func _arr(f: String) -> Array:
	var v: Variant = raw.get(f, [])
	if v is Array:
		return v
	errors.append("%s：顶层应为数组" % f)
	return []


func _obj(f: String) -> Dictionary:
	var v: Variant = raw.get(f, {})
	if v is Dictionary:
		return v
	errors.append("%s：顶层应为对象" % f)
	return {}


func _dicts(f: String, a: Variant, where: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (a is Array):
		errors.append("%s：%s 应为数组" % [f, where])
		return out
	for x: Variant in a:
		if x is Dictionary:
			out.append(x)
		else:
			errors.append("%s：%s 的元素应为对象" % [f, where])
	return out


func _load_stats() -> void:
	tuning = Tuning.new()
	for e: String in tuning.load_entries(_arr("tuning.json")):
		errors.append(e)
	var seen: Dictionary = {}
	for f: String in STAT_FILES:
		for d: Dictionary in _dicts(f, raw.get(f, []), "条目"):
			var id: String = str(d.get("id", ""))
			if seen.has(id):
				errors.append("%s：stat %s 重复声明（已在 %s）" % [f, id, seen[id]])
			seen[id] = f
			stat_decls.append(d)
			if not Stats.has_field(StringName(id)):
				errors.append("%s：stat %s 没有生成（运行 node tools/content/codegen.mjs）" % [f, id])
	if seen.size() != Stats.FIELDS.size():
		errors.append("stats/*.json 与生成的 Stats 字段数不一致（%d / %d），运行 node tools/content/codegen.mjs" % [seen.size(), Stats.FIELDS.size()])
	var sha: String = _sha1(STAT_FILES)
	if sha != "" and sha != Stats.SOURCE_SHA1:
		errors.append("sim/content/gen/stats.gd 过期（stats/*.json 改过），运行 node tools/content/codegen.mjs")
	day_mod_decls = _dicts("stats/day_mods.json", raw.get("stats/day_mods.json", []), "条目")
	for d: Dictionary in day_mod_decls:
		if not DayMods.FIELDS.has(str(d.get("id", ""))):
			errors.append("stats/day_mods.json：字段 %s 没有生成（运行 node tools/content/codegen.mjs）" % d.get("id", ""))
	var sha2: String = _sha1(["stats/day_mods.json"])
	if sha2 != "" and sha2 != DayMods.SOURCE_SHA1:
		errors.append("sim/content/gen/day_mods.gd 过期，运行 node tools/content/codegen.mjs")


func _load_world() -> void:
	for d: Dictionary in _dicts("world/objects.json", raw.get("world/objects.json", []), "条目"):
		var o: ObjDef = ObjDef.from_dict(d, errors)
		if object_by_id.has(o.id):
			errors.append("world/objects.json：物件 %s 重复" % o.id)
		objects.append(o)
		object_by_id[o.id] = o
	var i: int = 0
	for d: Dictionary in _dicts("world/bands.json", raw.get("world/bands.json", []), "条目"):
		bands.append(BandDef.from_dict(d, i, errors))
		i += 1
	var cl: Dictionary = _obj("world/city_levels.json")
	city_levels = _dicts("world/city_levels.json", cl.get("levels", []), "levels")
	for c: Dictionary in city_levels:
		c["items"] = PackedStringArray(c.get("items", []))
	city_fillers = DefUtil.strs(cl, "fillers", "world/city_levels.json", errors)
	terrain = _obj("world/terrain.json")
	var st: Dictionary = _obj("world/size_tiers.json")
	size_tiers = _dicts("world/size_tiers.json", st.get("tiers", []), "tiers")
	absorb_gain = DefUtil.nums(st, "absorb_gain", "world/size_tiers.json", errors)


func _load_shop() -> void:
	branches = _dicts("shop/branches.json", raw.get("shop/branches.json", []), "条目")
	for d: Dictionary in _dicts("shop/nodes.json", raw.get("shop/nodes.json", []), "条目"):
		var n: NodeDef = NodeDef.from_dict(d, errors)
		if node_by_key.has(n.key):
			errors.append("shop/nodes.json：节点 %s 重复" % n.key)
		nodes.append(n)
		node_by_key[n.key] = n


func _load_boons() -> void:
	for d: Dictionary in _dicts("boons/gods.json", _obj("boons/gods.json").get("gods", []), "gods"):
		var g: GodDef = GodDef.from_dict(d, errors)
		gods.append(g)
		god_by_id[g.id] = g
	for d: Dictionary in _dicts("boons/cards.json", raw.get("boons/cards.json", []), "条目"):
		var c: CardDef = CardDef.from_dict(d, errors)
		if card_by_id.has(c.id):
			errors.append("boons/cards.json：卡 %s 重复" % c.id)
		cards.append(c)
		card_by_id[c.id] = c
	var i: int = 0
	for d: Dictionary in _dicts("boons/altars.json", _obj("boons/altars.json").get("altars", []), "altars"):
		var w: String = "boons/altars.json:altars[%d]" % i
		i += 1
		var a: Dictionary = {"alt": float(d.get("alt", 0.0)), "god": StringName(str(d.get("god", ""))), "card": StringName(str(d.get("card", ""))),
			"name": str(d.get("name", "")), "hi": str(d.get("hi", "")), "lo": str(d.get("lo", "")), "line": str(d.get("line", "")),
			"fx": EffectList.compile(d.get("fx", []), [], w + ".fx", errors)}
		if not (float(a["alt"]) > 0.0):
			errors.append("%s：alt 必须 > 0" % w)
		if not altars.is_empty() and float(a["alt"]) <= float(altars[altars.size() - 1]["alt"]):
			errors.append("%s：祭坛要按海拔从低到高排" % w)
		altars.append(a)
	modules = _dicts("rules/modules.json", raw.get("rules/modules.json", []), "条目")


func _load_meta() -> void:
	for d: Dictionary in _dicts("meta/heirlooms.json", raw.get("meta/heirlooms.json", []), "条目"):
		var h: MetaDefs.Heirloom = MetaDefs.Heirloom.from_dict(d, errors)
		heirlooms.append(h)
		heirloom_by_id[h.id] = h
	for d: Dictionary in _dicts("meta/pacts.json", raw.get("meta/pacts.json", []), "条目"):
		var p: MetaDefs.Pact = MetaDefs.Pact.from_dict(d, errors)
		pacts.append(p)
		pact_by_id[p.id] = p
	for d: Dictionary in _dicts("meta/stones.json", raw.get("meta/stones.json", []), "条目"):
		var s: MetaDefs.Stone = MetaDefs.Stone.from_dict(d, errors)
		stones.append(s)
		stone_by_id[s.id] = s
	const ACH_KEYS: PackedStringArray = ["crushed", "buildings", "chickens", "living", "pushes", "best_night", "max_r", "max_seals", "moira_total",
		"jars", "jackpots", "bets", "bets_won", "bet_best_odds", "altars", "summit", "fast_summit", "city", "gen", "day", "heat_summit",
		"ending_sunrise", "fates_done", "dual_any", "wine_all"]
	var seen_ach: Dictionary = {}
	for d: Dictionary in _dicts("meta/achievements.json", _obj("meta/achievements.json").get("achievements", []), "achievements"):
		var id: String = str(d.get("id", ""))
		if id == "" or seen_ach.has(id):
			errors.append("meta/achievements.json：成就 id 为空或重复（%s）" % id)
		seen_ach[id] = true
		if not ACH_KEYS.has(str(d.get("k", ""))):
			errors.append("meta/achievements.json：成就 %s 的 k = %s 不在 Achievements.context() 里" % [id, d.get("k", "")])
		achievements.append(d)


func _load_story() -> void:
	story = _obj("story/story.json")
	story_true_ready = Expr.compile(str(story.get("true_ready", "false")), StoryDefs.INPUTS, "story/story.json:true_ready", errors)
	var i: int = 0
	for d: Dictionary in _dicts("story/story.json", story.get("passives", []), "passives"):
		passives.append(StoryDefs.Passive.from_dict(d, i, errors))
		i += 1
	for d: Dictionary in _dicts("story/summit.json", raw.get("story/summit.json", []), "条目"):
		summit.append(StoryDefs.Summit.from_dict(d, errors))
	for d: Dictionary in _dicts("story/endings.json", _obj("story/endings.json").get("endings", []), "endings"):
		var e: StoryDefs.Ending = StoryDefs.Ending.from_dict(d, errors)
		endings.append(e)
		ending_by_id[e.id] = e
	# 事件图（T 编写）：story/events/*.json
	var dir: String = root + "/story/events"
	if DirAccess.dir_exists_absolute(dir):
		var files: PackedStringArray = DirAccess.get_files_at(dir)
		files.sort()
		for f: String in files:
			if not f.ends_with(".json"):
				continue
			var rel: String = "story/events/" + f
			var v: Variant = JsonExact.parse(FileAccess.get_file_as_string(dir + "/" + f), rel)
			if not (v is Dictionary):
				errors.append("%s：顶层应为对象" % rel)
				continue
			v = _expand_line_refs(Loc.localize_json(v, rel), rel)
			raw[rel] = v
			var consts: PackedStringArray = []
			for k: Variant in (story.get("consts", {}) as Dictionary).keys():
				consts.append(str(k))
			var g: DialogGraph = DialogGraph.from_dict(v, rel, errors, consts)
			if dialogs.has(g.id):
				errors.append("%s：事件 id %s 重复" % [rel, g.id])
			dialogs[g.id] = g


## 事件图里的台词引用：say 里的 "@键"（= story/lines.json 的条目；"@a.b" 取子键，"@a.2" 取数组第 3 条）。
## 引用到数组时展开成多行；{"who": …, "text": "@键"} 展开后每行保留 who。选项 text 也可以用 "@键"（只能引用单条）。
## 台词只在 lines.json 写一份；事件文件里也可以直接写字面文字（以后改写剧情时两种都行）。
func _expand_line_refs(ev: Variant, rel: String) -> Variant:
	if not (ev is Dictionary) or not ((ev as Dictionary).get("nodes") is Dictionary):
		return ev
	var lines: Dictionary = raw.get("story/lines.json", {}) if raw.get("story/lines.json") is Dictionary else {}
	var nodes: Dictionary = ev["nodes"]
	for nn: Variant in nodes.keys():
		var nd: Variant = nodes[nn]
		if not (nd is Dictionary):
			continue
		var w: String = "%s:nodes.%s" % [rel, nn]
		if (nd as Dictionary).get("say") is Array:
			var out: Array = []
			for line: Variant in nd["say"]:
				var who: Variant = null
				var text: Variant = line
				if line is Dictionary:
					who = (line as Dictionary).get("who", "")
					text = (line as Dictionary).get("text", "")
				var got: Array = _line_ref(text, lines, w, true)
				for t: Variant in got:
					out.append({"who": who, "text": t} if who != null else t)
			nd["say"] = out
		if (nd as Dictionary).get("choices") is Array:
			for c: Variant in nd["choices"]:
				if c is Dictionary and (c as Dictionary).has("text"):
					var got2: Array = _line_ref(c["text"], lines, w + ".choices", false)
					c["text"] = got2[0] if not got2.is_empty() else ""
	return ev


func _line_ref(text: Variant, lines: Dictionary, w: String, allow_many: bool) -> Array:
	if typeof(text) != TYPE_STRING or not (text as String).begins_with("@"):
		return [text]
	var cur: Variant = lines
	for part: String in (text as String).substr(1).split("."):
		if cur is Dictionary and (cur as Dictionary).has(part):
			cur = cur[part]
		elif cur is Array and part.is_valid_int() and int(part) < (cur as Array).size():
			cur = cur[int(part)]
		else:
			errors.append("%s：台词引用 %s 在 story/lines.json 里找不到" % [w, text])
			return [""]
	if cur is Array:
		if not allow_many:
			errors.append("%s：选项文字 %s 引用到了多行台词" % [w, text])
			return [""]
		return (cur as Array).duplicate()
	return [str(cur)]


# ———————————————— 交叉引用 ————————————————

func _validate_refs() -> void:
	var w: String = "交叉引用"
	# 物件精灵
	for o: ObjDef in objects:
		if not sprites.has(String(o.sprite)):
			errors.append("%s：物件 %s 的精灵 %s 不在 art/sprites.json" % [w, o.id, o.sprite])
	# 海拔带、城市
	for b: BandDef in bands:
		for t: String in b.types:
			if not object_by_id.has(StringName(t.trim_prefix("@"))):
				errors.append("%s：world/bands.json 的物件 %s 不存在" % [w, t])
	for c: Dictionary in city_levels:
		for t: String in c["items"]:
			if not object_by_id.has(StringName(t)):
				errors.append("%s：world/city_levels.json 的物件 %s 不存在" % [w, t])
	for t: String in city_fillers:
		if not object_by_id.has(StringName(t)):
			errors.append("%s：city_levels.fillers 的物件 %s 不存在" % [w, t])
	# 天赋节点
	var brs: Dictionary = {}
	for b: Dictionary in branches:
		brs[StringName(str(b.get("id", "")))] = true
	for n: NodeDef in nodes:
		if not brs.has(n.br):
			errors.append("%s：节点 %s 的支 %s 不存在" % [w, n.key, n.br])
		if n.costs.is_empty() and (n.depth < 0 or n.depth >= tuning.depth_mult.size()):
			errors.append("%s：节点 %s 的 depth %d 超出 tuning.depth_mult" % [w, n.key, n.depth])
		if n.unlock_by != &"" and not god_by_id.has(n.unlock_by):
			errors.append("%s：节点 %s 的 unlock_by %s 不是主神" % [w, n.key, n.unlock_by])
	# 主神、卡、恩怨
	for g: GodDef in gods:
		if not brs.has(g.br):
			errors.append("%s：神 %s 的支 %s 不存在" % [w, g.id, g.br])
		if not god_by_id.has(g.nemesis):
			errors.append("%s：神 %s 的宿敌 %s 不存在" % [w, g.id, g.nemesis])
		for a: String in g.allies:
			if not god_by_id.has(StringName(a)):
				errors.append("%s：神 %s 的盟友 %s 不存在" % [w, g.id, a])
		if not object_by_id.has(g.roadblock):
			errors.append("%s：神 %s 的路障物件 %s 不存在" % [w, g.id, g.roadblock])
	for c: CardDef in cards:
		if not god_by_id.has(c.god):
			errors.append("%s：卡 %s 的神 %s 不存在" % [w, c.id, c.god])
		for g2: String in c.gods:
			if not god_by_id.has(StringName(g2)):
				errors.append("%s：卡 %s 的神 %s 不存在" % [w, c.id, g2])
	for a: Dictionary in altars:
		if not god_by_id.has(a["god"]):
			errors.append("%s：祭坛 %d m 的神 %s 不存在" % [w, int(a["alt"]), a["god"]])
		if a["card"] != &"" and not card_by_id.has(a["card"]):
			errors.append("%s：祭坛 %d m 的卡 %s 不存在" % [w, int(a["alt"]), a["card"]])
	for m: Dictionary in modules:
		var id: StringName = StringName(str(m.get("id", "")))
		if not god_by_id.has(id):
			errors.append("%s：rules/modules.json 的模块 %s 不是主神" % [w, id])
		if not str(m.get("script", "")).begins_with("res://"):
			errors.append("%s：模块 %s 的 script 必须是 res:// 路径" % [w, id])
	# 祖传前置
	for h: MetaDefs.Heirloom in heirlooms:
		for r: String in h.req:
			if not heirloom_by_id.has(StringName(r)):
				errors.append("%s：祖传 %s 的前置 %s 不存在" % [w, h.id, r])
	# 用到的 hook：必须是 "<模块>.<函数>" 且模块已登记
	var mods: Dictionary = {}
	for m: Dictionary in modules:
		mods[str(m.get("id", ""))] = true
	for hn: String in hook_names():
		if not mods.has(hn.get_slice(".", 0)):
			errors.append("%s：hook %s 的模块不在 rules/modules.json" % [w, hn])


## 全部效果列表里用到的 hook（"<模块>.<函数>"），B / S 要在对应模块实现 fx_<函数>。
func hook_names() -> PackedStringArray:
	var out: PackedStringArray = []
	var lists: Array[EffectList] = []
	for n: NodeDef in nodes:
		lists.append(n.fx)
	for c: CardDef in cards:
		lists.append(c.fx)
	for g: GodDef in gods:
		lists.append(g.faith_fx)
	for a: Dictionary in altars:
		lists.append(a["fx"])
	for h: MetaDefs.Heirloom in heirlooms:
		lists.append(h.fx)
	for p: MetaDefs.Pact in pacts:
		lists.append(p.fx)
	for s: MetaDefs.Stone in stones:
		lists.append(s.fx)
	for p: StoryDefs.Passive in passives:
		lists.append(p.fx)
	for fx: EffectList in lists:
		for h: String in fx.hook_names():
			if not out.has(h):
				out.append(h)
	return out


## 按 FILES 的给定子集求 SHA-1（与 tools/content/codegen.mjs 一致：按顺序拼接文件字节）。
func _sha1(files: PackedStringArray) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	for f: String in files:
		var p: String = root + "/" + f
		if not FileAccess.file_exists(p):
			return ""
		ctx.update(FileAccess.get_file_as_bytes(p))
	return ctx.finish().hex_encode()


# ———————————————— 便捷查询 ————————————————

## 剧情条件的标准输入表（缺的给 0；f 是 flags 字典）。
static func story_inputs(flags: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"day": 0.0, "money": 0.0, "cash": 0.0, "record": 0.0, "alt": 0.0, "tod": 0.0, "gen": 1.0, "f": flags}
	for k: Variant in extra.keys():
		d[k] = extra[k]
	return d


## story.json 的 consts 里取一个数（如 CHAIN_PRICE）。
func story_const(name: String) -> Variant:
	return (story.get("consts", {}) as Dictionary).get(name)


## 精灵宽高比（布局要用；不加载纹理）。缺 key 时返回 1（= assets.js aspect）。
func aspect(key: StringName) -> float:
	var s: Variant = sprites.get(String(key))
	if s is Dictionary and float((s as Dictionary).get("h", 0.0)) > 0.0:
		return float(s["w"]) / float(s["h"])
	return 1.0
