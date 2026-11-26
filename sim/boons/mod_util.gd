class_name ModUtil
extends RefCounted
## 机制模块共用的小工具（= 网页 gods/util.js）。


static func alive(o: CrushObj) -> bool:
	return o != null and not o.is_flat()


## 石头下坡方向 dist 米以内、门槛够、tier ≤ max_tier 的物件（最近的在前）；r：判门槛用的半径（默认石头）
static func objs_ahead(g: SimGame, dist: float, max_tier: int = 9, from: float = NAN, r: float = -1.0) -> Array[CrushObj]:
	var s0: float = g.stone.s if is_nan(from) else from
	var rr: float = g.stone.r if r < 0.0 else r
	var out: Array[CrushObj] = []
	for o: CrushObj in g.objs:
		if o.is_flat() or o.tier > max_tier or o.s > s0 or o.s < s0 - dist:
			continue
		if g.eff_req(o) > rr:
			continue
		out.append(o)
	out.sort_custom(func(a: CrushObj, b: CrushObj) -> bool: return a.s > b.s)
	return out


static func remote(g: SimGame, o: CrushObj, by: StringName = &"remote", k: float = 1.0, grow: float = 1.0) -> bool:
	if not alive(o):
		return false
	return g.crush_remote(o, k, grow, by)


## 一圈冲击：s 附近 radius 米内（两侧）门槛够、tier ≤ max_tier 的全部远程碾压；返回件数
static func shock(g: SimGame, s: float, radius: float, max_tier: int = 9, k: float = 1.0, by: StringName = &"shock") -> int:
	var n: int = 0
	var rr: float = g.stone.r
	var hits: Array[CrushObj] = []
	for o: CrushObj in g.objs:
		if o.is_flat() or o.tier > max_tier or absf(o.s - s) > radius + o.w / 2.0:
			continue
		if g.eff_req(o) > rr:
			continue
		hits.append(o)
	for o: CrushObj in hits:
		if remote(g, o, by, k):
			n += 1
	return n


static func speed_of(g: SimGame) -> float:
	return g.stone.speed()


static func v_term(g: SimGame) -> float:
	return (22.0 + 3.0 * g.stone.r) * g.mods.night_speed_mult * g.stats.night_speed * g.v_t_boost


## 在 s 处造一个物件（与 world.layout 的 add 同格式）。def 缺失时用 fallback 字典临时补一份定义
static func make_obj(g: SimGame, type: StringName, s: float, h: float, req: float, value: float, tier: int, flip: bool = false, alias: StringName = &"") -> CrushObj:
	var d: ObjDef = g.content.object_by_id.get(type)
	var w: World = g.world
	w.at(s)
	var o: CrushObj = CrushObj.new()
	o.type = type
	o.def = d
	o.s = s
	o.x = w.ax
	o.y = w.y_at_x(w.ax)
	o.ang = w.aang
	var asp: float = g.aspect_of(type) if g.content.sprites.has(String(type)) else (g.aspect_of(alias) if alias != &"" else 1.0)
	o.h = h
	o.w = h * asp
	o.req = req
	o.value = value
	o.tier = tier
	o.flip = flip
	o.id = 100000 + g.objs.size() + randi_safe(g)
	if alias != &"":
		o.ext["alias"] = alias
	return o


static func randi_safe(g: SimGame) -> int:
	return int(g.rand.next(SimRandom.Use.COSMETIC) * 100000.0)
