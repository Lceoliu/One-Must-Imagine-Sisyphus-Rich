class_name World
extends RefCounted
## 山体地形（折线）+ 物件布局 + 几何查询。逐行移植 proto/js/world.js。
## 世界坐标单位是米，x 向右、y 向上；s 是沿地表的弧长。地形各段的 x 随 s 单调递增（所有段的坡角都在 ±90° 以内）。

const SUMMIT: float = 1000.0

var ramps: bool = false
var left_end: float = -340.0
var gate_x: float = -318.0
## 折线顶点（并行数组，比字典快）
var px: PackedFloat64Array = []
var py: PackedFloat64Array = []
var ps: PackedFloat64Array = []
var length: float = 0.0
var summit_x: float = 0.0
var jump_idx: PackedInt32Array = []
var jump_s: PackedFloat64Array = []
var s_foot: float = 0.0
var s_summit: float = 0.0
var s_gate: float = 0.0
## 地层刻线与裂纹（只给表现层画；sim 不用）
var strata: Array[PackedFloat64Array] = []
var cracks: Array[PackedFloat64Array] = []

# at() 的结果（避免每次分配）：调用 at() 之后立即读取
var ax: float = 0.0
var ay: float = 0.0
var aang: float = 0.0
var ai: int = 0


func _init(p_ramps: bool, terrain: Dictionary) -> void:
	ramps = p_ramps
	left_end = float(terrain.get("left_end", -340.0))
	gate_x = float(terrain.get("gate_x", -318.0))
	_build_terrain(terrain)


# —— 地形（world.js:35 buildTerrain）——
func _build_terrain(terrain: Dictionary) -> void:
	var R: JsRng = JsRng.new(float(terrain.get("terrain_seed", 7)))
	var ramp_alts: Array = terrain.get("ramp_alts", [210, 470, 720])
	var lip_alts: Array = terrain.get("lip_alts", [90, 380, 600, 860])
	# 按高度分段加陡（2026-10-16 平台 / 阶梯）：[{lo, hi, steep_add 陡坡加几度, gentle_add 缓坡加几度}]。不写 = 和网页逐点一致（随机数的调用顺序不变）
	var bands: Array = terrain.get("bands", [])
	var band_add: Callable = func(y: float, key: String) -> float:
		var add: float = 0.0
		for b: Variant in bands:
			if b is Dictionary and y >= float((b as Dictionary).get("lo", 0.0)) and y < float((b as Dictionary).get("hi", 0.0)):
				add += float((b as Dictionary).get(key, 0.0))
		return add
	var xs: PackedFloat64Array = [left_end, -6.0]
	var ys: PackedFloat64Array = [0.0, 0.0]
	var st: Array[float] = [-6.0, 0.0]   # 当前 x, y
	var push: Callable = func(deg: float, len: float) -> void:
		var a: float = deg * PI / 180.0
		st[0] += cos(a) * len
		st[1] += sin(a) * len
		xs.append(st[0])
		ys.append(st[1])
	push.call(6.0, 10.0)
	push.call(14.0, 26.0)
	var ramp_i: int = 0
	var lip_i: int = 0
	jump_idx = PackedInt32Array()
	while st[1] < SUMMIT:
		push.call(10.0 + R.next() * 6.0 + float(band_add.call(st[1], "gentle_add")), 10.0 + R.next() * 12.0)
		var y: float = st[1]
		if ramps and ramp_i < ramp_alts.size() and y > float(ramp_alts[ramp_i]):
			jump_idx.append(xs.size() - 1)
			push.call(-16.0, 8.0)
			push.call(8.0, 4.0)
			ramp_i += 1
		elif lip_i < lip_alts.size() and y > float(lip_alts[lip_i]):
			jump_idx.append(xs.size() - 1)
			push.call(-8.0, 4.0)
			push.call(6.0, 3.0)
			lip_i += 1
		var steep: float = 36.0 + R.next() * 14.0 + float(band_add.call(st[1], "steep_add"))
		push.call(steep, 50.0 + R.next() * 70.0)
		if R.next() < 0.35:
			push.call(steep - 8.0 + R.next() * 6.0, 20.0 + R.next() * 30.0)
	# 截到山顶高度
	var n: int = xs.size()
	if ys[n - 1] > SUMMIT:
		var t: float = (SUMMIT - ys[n - 2]) / (ys[n - 1] - ys[n - 2])
		xs[n - 1] = xs[n - 2] + (xs[n - 1] - xs[n - 2]) * t
		ys[n - 1] = SUMMIT
	var lx: float = xs[n - 1]
	xs.append(lx + 18.0); ys.append(SUMMIT + 1.5)
	xs.append(lx + 40.0); ys.append(SUMMIT - 4.0)
	xs.append(lx + 90.0); ys.append(SUMMIT - 60.0)
	summit_x = lx
	px = xs
	py = ys
	ps = PackedFloat64Array()
	ps.resize(px.size())
	var s: float = 0.0
	ps[0] = 0.0
	for i: int in range(1, px.size()):
		s += Js.hypot(px[i] - px[i - 1], py[i] - py[i - 1])
		ps[i] = s
	length = s
	jump_s = PackedFloat64Array()
	for i: int in jump_idx:
		jump_s.append(ps[i])
	s_foot = s_at_x(0.0)
	s_summit = s_at_x(summit_x)
	s_gate = s_at_x(gate_x)
	_build_strata(int(terrain.get("strata_seed", 11)))


# 地表下的刻线（地层）和裂纹（world.js:88 buildStrata）
func _build_strata(seed: int) -> void:
	var R: JsRng = JsRng.new(float(seed))
	strata.clear()
	for depth: float in [2.2, 5.5, 11.0, 19.0, 32.0]:
		var line: PackedFloat64Array = []
		var x: float = left_end
		while x <= summit_x + 80.0:
			line.append(x)
			line.append(y_at_x(x) - depth - sin(x * 0.05 + depth) * depth * 0.18)
			x += 6.0
		strata.append(line)
	cracks.clear()
	for i: int in 520:
		var x0: float = left_end + R.next() * (summit_x + 80.0 - left_end)
		var y0: float = y_at_x(x0) - 1.0 - R.next() * 40.0
		var seg: PackedFloat64Array = [x0, y0]
		var cx: float = x0
		var cy: float = y0
		var ang: float = -PI / 2.0 + (R.next() - 0.5) * 1.6
		var nn: int = 2 + int(floor(R.next() * 4.0))
		for k: int in nn:
			ang += (R.next() - 0.5) * 0.9
			var l: float = 1.0 + R.next() * 4.0
			cx += cos(ang) * l
			cy += sin(ang) * l
			if cy > y_at_x(cx) - 0.4:
				break
			seg.append(cx)
			seg.append(cy)
		if seg.size() > 2:
			cracks.append(seg)


# —— 查询 ——
func seg_index_by_s(s: float) -> int:
	var lo: int = 0
	var hi: int = ps.size() - 1
	while hi - lo > 1:
		var m: int = (lo + hi) >> 1
		if ps[m] <= s:
			lo = m
		else:
			hi = m
	return lo


func seg_index_by_x(x: float) -> int:
	var lo: int = 0
	var hi: int = px.size() - 1
	while hi - lo > 1:
		var m: int = (lo + hi) >> 1
		if px[m] <= x:
			lo = m
		else:
			hi = m
	return lo


## 写入 ax / ay / aang / ai：s 处的地表点与坡角（向右上为正）。返回坡角。
func at(s: float) -> float:
	s = maxf(0.0, minf(length, s))
	var i: int = seg_index_by_s(s)
	var j: int = mini(i + 1, ps.size() - 1)
	var l: float = ps[j] - ps[i]
	if l == 0.0:
		l = 1.0
	var t: float = (s - ps[i]) / l
	ax = px[i] + (px[j] - px[i]) * t
	ay = py[i] + (py[j] - py[i]) * t
	aang = atan2(py[j] - py[i], px[j] - px[i])
	ai = i
	return aang


func ang_at(s: float) -> float:
	return at(s)


func alt_at(s: float) -> float:
	at(s)
	return ay


func y_at_x(x: float) -> float:
	if x <= px[0]:
		return py[0]
	var i: int = seg_index_by_x(x)
	var j: int = mini(i + 1, px.size() - 1)
	var t: float = ((x - px[i]) / (px[j] - px[i])) if px[j] != px[i] else 0.0
	return py[i] + (py[j] - py[i]) * t


func s_at_x(x: float) -> float:
	var i: int = seg_index_by_x(x)
	var j: int = mini(i + 1, px.size() - 1)
	var t: float = ((x - px[i]) / (px[j] - px[i])) if px[j] != px[i] else 0.0
	return ps[i] + (ps[j] - ps[i]) * maxf(0.0, minf(1.0, t))


## 由海拔找 s（只在山坡部分，单调近似）
func s_at_alt(h: float) -> float:
	for i: int in range(1, px.size()):
		if py[i] >= h and px[i] >= 0.0:
			var t: float = ((h - py[i - 1]) / (py[i] - py[i - 1])) if py[i] != py[i - 1] else 0.0
			return ps[i - 1] + (ps[i] - ps[i - 1]) * maxf(0.0, minf(1.0, t))
	return s_summit


# —— 物件布局（world.js:167 layout）——
## aspect：Callable(type: StringName) -> float。day = nightSeed（也用于 min_day）；gen = 第几代。city_level = 山脚城镇的繁荣度。
func layout(content: ContentDB, st: Stats, city_level: int, aspect: Callable, day: int, gen: int = 1) -> Array[CrushObj]:
	var R: JsRng = JsRng.new(float(1000 + day + (maxi(1, gen) - 1) * 7919))
	# 高处空当里撒小物件用另一条随机流（bands.json 的 fill）：主物件的抽取和网页逐件一致
	var RF: JsRng = JsRng.new(float(52711 + day * 31 + (maxi(1, gen) - 1) * 7919))
	var objs: Array[CrushObj] = []
	var add: Callable = func(type: StringName, s: float, scale: float, vmul: float, flip: bool, city: bool, domino: int, dgroup: int) -> float:
		var d: ObjDef = content.object_by_id[type]
		var h: float = d.h * scale
		var w: float = h * float(aspect.call(type))
		at(s)
		var o: CrushObj = CrushObj.new()
		o.id = objs.size() + 1
		o.type = type
		o.def = d
		o.s = s
		o.x = ax
		o.ang = aang
		o.y = y_at_x(ax)
		o.w = w
		o.h = h
		o.req = d.req * scale
		o.value = d.value * vmul
		o.tier = d.tier
		o.flip = flip
		o.city = city
		o.domino = domino
		o.dgroup = dgroup
		objs.append(o)
		return w

	var potters: float = st.potters
	var pasture: float = st.pasture
	var domino_lv: float = st.domino
	var density: float = maxf(0.2, st.obj_density if st.obj_density != 0.0 else 1.0)
	var bands: Array[BandDef] = content.bands
	var near_ramp: Callable = func(s: float) -> bool:
		for rs: float in jump_s:
			if s - rs < 30.0 and rs - s < 18.0:
				return true
		return false

	var s: float = s_foot + 6.0
	while s < s_summit - 8.0:
		at(s)
		var alt: float = ay
		var band: BandDef = bands[bands.size() - 1]
		for b: BandDef in bands:
			if alt < b.top:
				band = b
				break
		if near_ramp.call(s):
			s += 4.0
			continue
		var choice: String = _pick(band, R, {"potters": potters, "pasture": pasture, "domino": domino_lv, "day": float(day), "alt": alt}, content, float(day), alt)
		var used: float = 0.0
		if choice == "@sheep" or choice == "@goat":
			var t: StringName = StringName(choice.substr(1))
			var n: int = 3 + int(floor(R.next() * 5.0))
			for k: int in n:
				used += float(add.call(t, s + used + 0.6, 1.0, 1.0, R.next() < 0.5, false, 0, -1)) + 0.5
		elif choice == "@horse":
			var n2: int = 3 + int(floor(R.next() * 3.0))
			var fl: bool = R.next() < 0.5
			for k: int in n2:
				used += float(add.call(&"horse", s + used + 0.6, 1.0, 1.0, fl, false, 0, -1)) + 0.3
		elif choice == "@hoplite":
			var n3: int = 4 + int(floor(R.next() * 5.0))
			for k: int in n3:
				used += float(add.call(&"hoplite", s + used + 0.5, 1.0, 1.0, true, false, 0, -1)) + 0.4
		elif choice == "@column":
			var n4: int = 5 + int(floor(R.next() * 4.0)) + int(domino_lv) * 2
			var gid: int = objs.size()
			for k: int in n4:
				used += float(add.call(&"column", s + used + 1.0, 1.0, 1.0, false, false, k + 1, gid)) + 1.4
		else:
			var ty: StringName = StringName(choice)
			var fl2: bool = R.next() < 0.3 and (content.object_by_id[ty] as ObjDef).living
			used = float(add.call(ty, s + 1.0, 1.0, 1.0, fl2, false, 0, -1)) + 1.0
		var gap: float = (band.gap_lo + R.next() * (band.gap_hi - band.gap_lo)) / density
		var fp: float = band.fill_prob({"potters": potters, "pasture": pasture, "domino": domino_lv, "day": float(day), "alt": alt})
		if fp > 0.0 and gap > band.fill_margin * 2.0 + 0.8 and RF.next() < fp:
			_fill_gap(band, RF, s + used, gap, content, aspect, add, objs, near_ramp)
		s += used + gap

	# 山脚城镇（docs/v05/town.md）：第一天就整座城都在；city_level 只是繁荣度
	_layout_town(content, st, city_level, aspect, objs, add)
	Js.stable_sort_by_s(objs)
	for i: int in objs.size():
		objs[i].id = i + 1
	return objs


## 两件主物件之间的空当 [s0, s0 + gap] 里撒 band.fill 的小物件：两头各留 fill_margin 米（默认 1.5），件与件之间 0.6–2.5 m，放不下就停；跳台附近不放。
## 撒的物件 ext["fill"] = true（布局对拍测试跳过它们）
func _fill_gap(band: BandDef, RF: JsRng, s0: float, gap: float, content: ContentDB, aspect: Callable, add: Callable, objs: Array[CrushObj], near_ramp: Callable) -> void:
	var n: int = band.fill_lo + int(floor(RF.next() * float(band.fill_hi - band.fill_lo + 1)))
	var mg: float = band.fill_margin
	var cur: float = s0 + mg + RF.next() * maxf(0.0, gap * 0.4 - mg)
	var end: float = s0 + gap - mg
	for k: int in n:
		var ty: StringName = StringName(band.fill_pick(RF.next()))
		var d: ObjDef = content.object_by_id.get(ty) as ObjDef
		var fl: bool = RF.next() < 0.5
		if d == null:
			continue
		var wd: float = d.h * float(aspect.call(ty))
		if cur + wd > end or near_ramp.call(cur):
			return
		add.call(ty, cur, 1.0, 1.0, fl, false, 0, -1)
		objs[objs.size() - 1].ext["fill"] = true
		cur += wd + 0.6 + RF.next() * 1.9


# —— 山脚城镇 ——
## 排：0 = 路面（照常挡石头），1 = 近排、2 = 远排（路边建筑，石头不够大只蹭过去，见 SimGame._collide）
const TOWN_ROWS: PackedStringArray = ["front", "near", "far"]


## 城镇布局表（content/world/city_levels.json 的 town；ContentDB 没有专门的定义类，直接读原始 JSON）
static func town_plan(content: ContentDB) -> Dictionary:
	var cl: Variant = content.raw.get("world/city_levels.json", {})
	if cl is Dictionary:
		var t: Variant = (cl as Dictionary).get("town", {})
		if t is Dictionary:
			return t
	return {}


## 繁荣度那一档的参数（越界取最近一档）
static func town_level(content: ContentDB, prosperity: int) -> Dictionary:
	var levels: Array[Dictionary] = content.city_levels
	if levels.is_empty():
		return {}
	return levels[clampi(prosperity, 0, levels.size() - 1)]


## 从山脚（x0）往冥府之门方向，一个街区接一个街区地排；每个街区里三排各自从街区右端往左排。
## 每件 = [类型, 前面留的空（米，负数 = 和前一件叠一点）, 标记]；标记：f = 镜像，pN = 繁荣度 ≥ N 才出现，d = 一排柱子（多米诺）。
## 布局固定、与天数 / 代数无关（城镇不会每天搬家），裂痕才能按 slot 跨夜保留；不满足繁荣度的件也占位，别的件不挪。
func _layout_town(content: ContentDB, st: Stats, prosperity: int, aspect: Callable, objs: Array[CrushObj], add: Callable) -> void:
	var plan: Dictionary = town_plan(content)
	var districts: Array = plan.get("districts", [])
	if districts.is_empty():
		return
	var lvl: Dictionary = town_level(content, prosperity)
	var vmul: float = st.city_value * float(lvl.get("value_mult", 1.0))
	# 神造之城（v0.6）：众神重建后城中物件更难碾（req_mult），会掉宝瓶的建筑陶罐档次更高（jar_add）
	var req_k: float = float(lvl.get("req_mult", 1.0))
	var jar_add: int = int(lvl.get("jar_add", 0))
	# 各排的价值系数（路面的人和货照价；整座城几十栋房子，每栋只值原价的一小份，否则城里的钱会压过山上）
	var row_value: Array = plan.get("row_value", [1.0, 1.0, 1.0])
	var R: JsRng = JsRng.new(float(plan.get("seed", 77)))
	# 「繁荣度」（rebuild）每级让路面的空当多冒出些小东西（city_levels.json 的 fillers）；另一条随机流，不买时城一模一样
	var RT: JsRng = JsRng.new(float(plan.get("seed", 77)) + 3001.0)
	var fill_p: float = 0.22 * st.rebuild
	var stop_x: float = gate_x + float(plan.get("gate_gap", 30.0))
	var x0: float = float(plan.get("x0", -10.0))
	for dv: Variant in districts:
		var dist: Dictionary = dv
		var did: String = String(dist.get("id", "?"))
		for row: int in TOWN_ROWS.size():
			var items: Array = dist.get(TOWN_ROWS[row], [])
			var cx: float = x0
			var dgroup: int = -1
			var dk: int = 0
			for k: int in items.size():
				var it: Array = items[k]
				var t: StringName = StringName(str(it[0]))
				var gap: float = float(it[1]) if it.size() > 1 else 0.0
				var flags: String = str(it[2]) if it.size() > 2 else ""
				var flip_r: float = R.next()
				if not content.object_by_id.has(t):
					continue
				var d: ObjDef = content.object_by_id[t]
				var w: float = d.h * float(aspect.call(t))
				if row == 0 and fill_p > 0.0 and gap > 1.6 and not content.city_fillers.is_empty() and RT.next() < fill_p:
					var ft: StringName = StringName(content.city_fillers[int(RT.next() * content.city_fillers.size()) % content.city_fillers.size()])
					if content.object_by_id.has(ft):
						var fd: ObjDef = content.object_by_id[ft]
						var fw: float = fd.h * float(aspect.call(ft))
						if fw + 0.6 <= gap and cx - gap / 2.0 - fw / 2.0 >= stop_x:
							add.call(ft, s_at_x(cx - gap / 2.0), 1.0, vmul * float(row_value[row]), RT.next() < 0.5, true, 0, -1)
							var fo: CrushObj = objs[objs.size() - 1]
							fo.ext["row"] = row
							fo.ext["fill"] = true
							fo.req *= req_k
				cx -= gap
				var fl: bool = (flip_r < 0.5) if d.living else flags.contains("f")
				var dom: int = 0
				if flags.contains("d"):
					if dgroup < 0:
						dgroup = objs.size()
					dk += 1
					dom = dk
				else:
					dgroup = -1
					dk = 0
				if prosperity >= _flag_num(flags, "p") and cx - w >= stop_x:
					add.call(t, s_at_x(cx - w / 2.0), 1.0, vmul * float(row_value[row]), fl, true, dom, dgroup if dom > 0 else -1)
					var o: CrushObj = objs[objs.size() - 1]
					o.ext["row"] = row
					o.ext["slot"] = "%s.%d.%d" % [did, row, k]
					o.req *= req_k
					if jar_add > 0 and d.jar > 0:
						o.ext["jar_add"] = jar_add
				cx -= w
		x0 -= float(dist.get("len", 40.0))


## 标记串里 key 后面的数字（"p2f" 的 p → 2）；没有就是 0
static func _flag_num(flags: String, key: String) -> int:
	var i: int = flags.find(key)
	if i < 0:
		return 0
	var j: int = i + key.length()
	var n: String = ""
	while j < flags.length() and flags[j] >= "0" and flags[j] <= "9":
		n += flags[j]
		j += 1
	return int(n) if n != "" else 0


# world.js:197 pick：过滤权重 ≤ 0、物件不存在、min_alt / min_day 不满足的项，然后按权重抽
func _pick(band: BandDef, R: JsRng, inputs: Dictionary, content: ContentDB, day: float, alt: float) -> String:
	var ok_i: PackedInt32Array = []
	var ok_w: PackedFloat64Array = []
	var tot: float = 0.0
	for i: int in band.types.size():
		var wv: float = band.weight(i, inputs)
		var ty: String = band.types[i]
		if not (wv > 0.0) or not content.object_by_id.has(StringName(ty.replace("@", ""))) or not band.allowed(i, day, alt):
			continue
		ok_i.append(i)
		ok_w.append(wv)
		tot += wv
	var r: float = R.next() * tot
	for k: int in ok_i.size():
		r -= ok_w[k]
		if r <= 0.0:
			return band.types[ok_i[k]]
	return band.types[ok_i[0]]
