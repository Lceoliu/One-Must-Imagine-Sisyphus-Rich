class_name FxView
extends Node2D
## 特效层（屏幕空间，移植 fx.js 的粒子与 coins.js 的看得见的金币）：粒子按世界米存，绘制时投影到屏幕。
## 金币：碾碎时按价值炸开 → 落地停顿 → 被石头吸附（或落后太久被吸回）→ 拾取时 collected += 面值（HUD 的"今夜碾得"追它）。
## 数据布局（2026-10-16 改，字典数组每帧读写太慢）：大量的小粒子（尘土 / 碎屑 / 火星 / 烟 / 装饰币）是结构数组——
## 种类 _k + 各字段一条 PackedFloat64Array，预分配 MAX_P 格、前 _n 格有效，过期用最后一格填洞；
## 少量带字符串 / 颜色的（飘字 / 冲击环 / 飞出的物件）放 _misc 字典数组。金币也按字段分开存（_c*），删除保持顺序。
## 尘土、烟、碎屑的几何是单位模板（PackedVector2Array）× Transform2D 一次变换整团，不再逐点算。

const GOLD: Color = Color("f0b93a")
const GOLD_HI: Color = Color("ffe08a")
const INK: Color = Color("120c0a")
const LINE: Color = Color("e9d3a8")
const MAX_P: int = 800          # 碾城时碎屑太多会掉帧（2026-10-15：1600 → 800）；实际上限再乘画质"特效数量"
const MAX_COINS: int = 350
const COIN_GRAV: float = 30.0
const MAG_BASE: float = 4.0

# 结构数组里的粒子种类（碎屑落地静止后改成 K_SHARD_REST，不再更新）
const K_DUST: int = 0
const K_SHARD: int = 1
const K_SHARD_REST: int = 2
const K_SPARK: int = 3
const K_SMOKE: int = 4
const K_DECO: int = 5

# 尘土 / 刻线的颜色（白天浅陶土、夜里浅石板蓝）
const DUST_DAY: Color = Color("dcc0a0")
const DUST_NIGHT: Color = Color("3c4a68")
const DUST_LINE_DAY: Color = Color("f1e3c8")
const DUST_LINE_NIGHT: Color = Color("6f80a4")

## HUD（金币飞向它的德拉克马图标；main 设置）
var hud_view: HudView = null
var wv: WorldView = null
var sim: SimGame = null
var runner: SimRunner = null
## 拾取到的金币面值（夜里 HUD 显示用）
var collected: float = 0.0
var on_pickup: Callable = Callable()
# —— 拾取音（= 网页 coins.js note()）：沿多利亚音阶上升的"叮"，0.6s 没拾取回到底音；令牌桶限流 ——
const NOTE_RATE: float = 18.0      # 每秒最多约 18 个
const NOTE_BURST: float = 2.0      # 令牌桶容量
const NOTE_FRAME: int = 2          # 每帧最多 2 个
const CHAIN_RESET: float = 0.6
var _note_step: int = 0
var _note_last_t: float = -9.0
var _note_tokens: float = NOTE_BURST
var _note_frame: int = 0

# —— 小粒子（结构数组）：_s 大小；_a 尘土=grow / 碎屑=rot / 烟=ph / 装饰币=spin；_b 碎屑=vr ——
var _n: int = 0
var _k: PackedInt32Array = []
var _x: PackedFloat64Array = []
var _y: PackedFloat64Array = []
var _vx: PackedFloat64Array = []
var _vy: PackedFloat64Array = []
var _t: PackedFloat64Array = []
var _life: PackedFloat64Array = []
var _s: PackedFloat64Array = []
var _a: PackedFloat64Array = []
var _b: PackedFloat64Array = []
## 飘字 / 冲击环 / 飞出的物件（字典，"k" = &"text" / &"ring" / &"flyer"）
var _misc: Array[Dictionary] = []
# —— 金币（结构数组，按出生顺序；状态 0 飞 → 1 停 → 2 吸向石头 → 3 飞向 HUD）——
var _cx: PackedFloat64Array = []
var _cy: PackedFloat64Array = []
var _cvx: PackedFloat64Array = []
var _cvy: PackedFloat64Array = []
var _cval: PackedFloat64Array = []
var _ck: PackedFloat64Array = []      # 重力 / 速度倍率（按镜头高度）
var _ct: PackedFloat64Array = []
var _cspin: PackedFloat64Array = []
var _cspv: PackedFloat64Array = []
var _csx: PackedFloat64Array = []     # 进状态 3 时的屏幕位置
var _csy: PackedFloat64Array = []
var _cpx: PackedFloat64Array = []     # 状态 3 当前屏幕位置
var _cpy: PackedFloat64Array = []
var _ctier: PackedInt32Array = []
var _cst: PackedInt32Array = []


func _init() -> void:
	_k.resize(MAX_P)
	_x.resize(MAX_P)
	_y.resize(MAX_P)
	_vx.resize(MAX_P)
	_vy.resize(MAX_P)
	_t.resize(MAX_P)
	_life.resize(MAX_P)
	_s.resize(MAX_P)
	_a.resize(MAX_P)
	_b.resize(MAX_P)


func clear() -> void:
	_n = 0
	_misc.clear()
	for i: int in range(_cx.size() - 1, -1, -1):
		_coin_remove(i)
	collected = 0.0


## 场上的小粒子 + 飘字等的个数（测试用）
func part_count() -> int:
	return _n + _misc.size()


## 同屏飘字上限：碾城时一件一个「+价值」，几十个叠在一起既看不清又费时间（每个要画两遍字）
const MAX_TEXT: int = 24


func _drop_oldest_text() -> void:
	var n: int = 0
	var first: int = -1
	for i: int in _misc.size():
		if _misc[i]["k"] == &"text":
			n += 1
			if first < 0:
				first = i
	if n >= MAX_TEXT and first >= 0:
		_misc.remove_at(first)


## 同屏粒子上限（画质"特效数量"：少 0.4 / 中 0.7 / 多 1.0 倍）
static func cap_for(mult: float) -> int:
	return roundi(MAX_P * mult)


## 一次生成的粒子数乘画质倍率：原来是 0 还是 0，否则至少 1 个
static func scaled_count(n: int, mult: float) -> int:
	return 0 if n <= 0 else maxi(1, roundi(n * mult))


## 飘字、冲击环、飞出的物件：不跟着画质"特效数量"减（那是收入和碾压的反馈），上限仍是原来的总数 MAX_P
func _push_misc(p: Dictionary) -> void:
	if _n + _misc.size() < MAX_P:
		_misc.append(p)


## 结构数组末尾加一个粒子（调用前已确认没满）
func _add(k: int, x: float, y: float, vx: float, vy: float, s: float, a: float, b: float, life: float) -> void:
	var i: int = _n
	_k[i] = k
	_x[i] = x
	_y[i] = y
	_vx[i] = vx
	_vy[i] = vy
	_t[i] = 0.0
	_life[i] = life
	_s[i] = s
	_a[i] = a
	_b[i] = b
	_n = i + 1


## 删第 i 个：最后一个搬进来填洞
func _kill(i: int) -> void:
	var j: int = _n - 1
	if i != j:
		_k[i] = _k[j]
		_x[i] = _x[j]
		_y[i] = _y[j]
		_vx[i] = _vx[j]
		_vy[i] = _vy[j]
		_t[i] = _t[j]
		_life[i] = _life[j]
		_s[i] = _s[j]
		_a[i] = _a[j]
		_b[i] = _b[j]
	_n = j


func on_events(list: Array[SimEvent]) -> void:
	var mult: float = Settings.fx_mult()
	var cap: int = cap_for(mult)
	for e: SimEvent in list:
		match e.kind:
			&"dust":
				for i: int in scaled_count(int(e.a), mult):
					if _n + _misc.size() >= cap:
						break
					_add(K_DUST, e.x + (randf() - 0.5) * e.b, e.y + randf() * e.b * 0.3, (randf() - 0.5) * e.c * 2.0, randf() * e.c * 0.5,
						e.b * (0.4 + randf() * 0.6), e.b * (0.8 + randf()), 0.0, 0.8 + randf() * 0.9)
			&"shards":
				for i: int in scaled_count(int(e.a), mult):
					if _n + _misc.size() >= cap:
						break
					var a: float = randf() * PI - PI * 0.05
					var v: float = e.b * (0.35 + randf() * 0.9)
					var y0: float = e.y + randf() * e.c
					var vx0: float = cos(a) * v * (-1.0 if randf() < 0.5 else 1.0)
					_add(K_SHARD, e.x, y0, vx0, absf(sin(a)) * v + v * 0.3, e.c * (0.25 + randf() * 0.75), randf() * 6.0, (randf() - 0.5) * 14.0, 2.5 + randf() * 2.0)
			&"sparks":
				for i: int in scaled_count(int(e.a), mult):
					if _n + _misc.size() >= cap:
						break
					var a2: float = randf() * TAU
					var v2: float = e.b * (0.4 + randf())
					_add(K_SPARK, e.x, e.y, cos(a2) * v2, sin(a2) * v2, 0.0, 0.0, 0.0, 0.35 + randf() * 0.4)
			&"ring":
				_push_misc({"k": &"ring", "x": e.x, "y": e.y, "r0": e.a, "r1": e.b, "t": 0.0, "life": e.c, "color": e.color, "w": e.d, "max": float(e.data.get("max_h_frac", 0.0))})
			&"text":
				_drop_oldest_text()
				_push_misc({"k": &"text", "x": e.x, "y": e.y, "s": e.text, "size": e.a, "color": e.color, "t": 0.0, "life": e.b, "vy": 3.0})
			&"smoke":
				for i: int in scaled_count(int(e.a), mult):
					if _n + _misc.size() >= cap:
						break
					var vy: float = 1.4 + randf() * 0.5
					_add(K_SMOKE, e.x + (randf() - 0.5) * 1.2, e.y, 0.25 + randf() * 0.35, vy, 0.5 + randf() * 0.3, randf() * 6.28, 0.0, 6.0 / vy)
			&"flyer":
				_push_misc({"k": &"flyer", "spr": e.name, "x": e.x, "y": e.y, "w": e.a, "h": e.b, "vx": e.c, "vy": e.d, "rot": 0.0, "vr": (randf() - 0.5) * 9.0, "t": 0.0, "life": 2.2})
			&"coins":
				for i: int in scaled_count(int(e.a), mult):
					if _n + _misc.size() >= cap:
						break
					var a3: float = PI / 2.0 + (randf() - 0.5) * 1.6
					var v3: float = 6.0 + randf() * 9.0
					_add(K_DECO, e.x, e.y, cos(a3) * v3, sin(a3) * v3, 0.0, randf() * 6.0, 0.0, 1.6)
			&"burst":
				_burst(e.x, e.y, e.a, int(e.b), bool(e.data.get("big", false)), bool(e.data.get("gold", false)))
			&"bonus":
				_burst(e.x, e.y, float(e.data.get("v", 0.0)), 2, true, String(e.data.get("label", "")) == Loc.t("chests.fate_urn", "命运宝瓶"))
			&"crush":
				var d: Dictionary = e.data
				if d.get("voice", &"") != &"" and randf() < 0.7:
					_push_misc({"k": &"text", "x": e.x, "y": e.y + float(d["h"]) * 0.6 + 1.5, "s": String(d["voice_txt"]), "size": 14.0, "color": Color("f1e3c8"), "t": 0.0, "life": 0.7, "vy": 3.0})
				if bool(d.get("fly", false)) and randf() < 0.06 + 0.04 * int(d["tier"]):
					_push_misc({"k": &"flyer", "spr": d["type"], "x": e.x, "y": e.y, "w": float(d["w"]) * 0.9, "h": float(d["h"]) * 0.25,
						"vx": float(d["vx"]) * 0.6 + (randf() - 0.5) * 6.0, "vy": 10.0 + randf() * 10.0, "rot": 0.0, "vr": (randf() - 0.5) * 9.0, "t": 0.0, "life": 2.2})
			&"night_settled":
				_vacuum_all()
			&"phase":
				if e.data.get("phase", &"") == &"day":
					clear()


# —— 金币 ——
func _burst(x: float, y: float, value: float, tier: int, big: bool, gold: bool) -> void:
	if value <= 0.0:
		return
	var n: int = clampi(roundi(2.0 + 3.2 * Js.log10(1.0 + value) + 2.0 * tier + (4.0 if big else 0.0)), 1, 24)
	# 爆金币声（真实采样，sfx_samples.json 的 coinBurst）：按炸出的枚数分轻 / 中 / 重三档，大额奖励（宝瓶等）直接最重一档
	Sfx.play(&"coinBurst", [1.0 if big or gold else clampf((n - 2.0) / 14.0, 0.0, 1.0)])
	if _cx.size() + n > MAX_COINS:
		# 场上满了：并进最后一枚
		if not _cx.is_empty():
			_cval[_cval.size() - 1] += value
			return
		collected += value
		return
	var b: Boulder = sim.stone
	var bvx: float = b.vx if b.air else b.v * cos(b.ang)
	var bvy: float = b.vy if b.air else b.v * sin(b.ang)
	var k: float = maxf(1.0, sim.cam_view_h / 14.0)
	var each: float = value / n
	for i: int in n:
		var inh: float = 0.55 + randf() * 0.6
		var a: float = PI / 2.0 + (randf() - 0.5) * 1.8
		var sp: float = (4.0 + randf() * 4.5) * k
		var tier_c: int = 2 if gold or each > 200.0 else (1 if each > 20.0 else 0)
		_cx.append(x)
		_cy.append(y)
		_cvx.append(bvx * inh + cos(a) * sp)
		_cvy.append(bvy * inh + sin(a) * sp)
		_cval.append(each)
		_ctier.append(tier_c)
		_ck.append(k)
		_cst.append(0)
		_ct.append(0.0)
		_cspin.append(randf() * 6.0)
		_cspv.append((10.0 + randf() * 10.0) * (-1.0 if randf() < 0.5 else 1.0))
		_csx.append(0.0)
		_csy.append(0.0)
		_cpx.append(0.0)
		_cpy.append(0.0)


func _coin_remove(i: int) -> void:
	_cx.remove_at(i)
	_cy.remove_at(i)
	_cvx.remove_at(i)
	_cvy.remove_at(i)
	_cval.remove_at(i)
	_ck.remove_at(i)
	_ct.remove_at(i)
	_cspin.remove_at(i)
	_cspv.remove_at(i)
	_csx.remove_at(i)
	_csy.remove_at(i)
	_cpx.remove_at(i)
	_cpy.remove_at(i)
	_ctier.remove_at(i)
	_cst.remove_at(i)


func _vacuum_all() -> void:
	var n: int = 0
	for i: int in _cx.size():
		if _cst[i] < 3:
			n += 1
			var s: Vector2 = wv.to_screen(_cx[i], _cy[i])
			_cst[i] = 3
			_ct[i] = 0.0
			_csx[i] = s.x
			_csy[i] = s.y
			_cpx[i] = s.x
			_cpy[i] = s.y
	# 网页 coins.js collectAll：夜晚结束一次性吸入时放一串"锵锵"
	if n > 0:
		Sfx.play(&"coinsCascade", [mini(30, n), 0.35])


func _process(real_dt: float) -> void:
	var _pt: int = Prof.t()
	_process_impl(real_dt)
	Prof.add(&"fx.process", _pt)


func _process_impl(real_dt: float) -> void:
	if sim == null or wv == null:
		return
	var rate: float = runner.rate if runner != null else 1.0
	var dt: float = real_dt * (rate if rate > 0.0 else 0.15)
	_note_tokens = minf(NOTE_BURST, _note_tokens + NOTE_RATE * real_dt)
	_note_frame = 0
	_update_parts(dt, sim.world)
	_update_misc(dt)
	_update_coins(dt, real_dt)
	queue_redraw()


func _update_parts(dt: float, w: World) -> void:
	var dust_damp: float = exp(-2.0 * dt)
	var i: int = _n - 1
	while i >= 0:
		var t: float = _t[i] + dt
		if t > _life[i]:
			_kill(i)
			i -= 1
			continue
		_t[i] = t
		var k: int = _k[i]
		if k == K_DUST:
			var vx: float = _vx[i]
			_x[i] += vx * dt
			_y[i] += _vy[i] * dt
			_vx[i] = vx * dust_damp
			_s[i] += _a[i] * dt * 0.8
		elif k == K_SHARD:
			var vy: float = _vy[i] - 26.0 * dt
			var x: float = _x[i] + _vx[i] * dt
			var y: float = _y[i] + vy * dt
			_a[i] += _b[i] * dt
			if w != null:
				var gy: float = w.y_at_x(x)
				if y < gy:
					y = gy
					if absf(vy) < 3.0:
						_k[i] = K_SHARD_REST
					else:
						vy *= -0.3
						_vx[i] *= 0.5
			_x[i] = x
			_y[i] = y
			_vy[i] = vy
		elif k == K_SPARK or k == K_DECO:
			_x[i] += _vx[i] * dt
			_y[i] += _vy[i] * dt
			_vy[i] -= (20.0 if k == K_SPARK else 30.0) * dt
		elif k == K_SMOKE:
			_x[i] += (_vx[i] + sin(t * 1.6 + _a[i]) * 0.45) * dt
			_y[i] += _vy[i] * dt
			_s[i] += dt * 0.32
		i -= 1


func _update_misc(dt: float) -> void:
	for i: int in range(_misc.size() - 1, -1, -1):
		var p: Dictionary = _misc[i]
		p["t"] = float(p["t"]) + dt
		if float(p["t"]) > float(p["life"]):
			# 保序删除（件数少）：_drop_oldest_text 要靠先后找最旧的飘字，叠放顺序也不乱
			_misc.remove_at(i)
			continue
		match p["k"]:
			&"flyer":
				p["vy"] = float(p["vy"]) - 22.0 * dt
				p["x"] = float(p["x"]) + float(p["vx"]) * dt
				p["y"] = float(p["y"]) + float(p["vy"]) * dt
				p["rot"] = float(p["rot"]) + float(p["vr"]) * dt
			&"text":
				p["y"] = float(p["y"]) + float(p["vy"]) * dt
				p["vy"] = float(p["vy"]) * exp(-2.5 * dt)


## 金币状态：0 飞 → 1 停 → 2 吸向石头 → 3 飞向 HUD（屏幕空间）
func _update_coins(dt: float, real_dt: float) -> void:
	if _cx.is_empty():
		return
	var b: Boulder = sim.stone
	var w: World = sim.world
	var mm: float = sim.mods.magnet_mult * sim.stats.magnet_mult
	var mag_r: float = (MAG_BASE + 0.8 * b.r) * mm
	var hud: Vector2 = hud_view.money_target() if hud_view != null else HudView.money_anchor(get_viewport_rect().size)
	var night: bool = sim.phase == &"night"
	var bspd: float = b.speed()
	var pick_r: float = b.r * 0.9 + 0.3
	for i: int in range(_cx.size() - 1, -1, -1):
		var t: float = _ct[i] + dt
		_ct[i] = t
		_cspin[i] += _cspv[i] * dt
		var st: int = _cst[i]
		if st == 0:
			var vy: float = _cvy[i] - COIN_GRAV * _ck[i] * dt
			var x: float = _cx[i] + _cvx[i] * dt
			var y: float = _cy[i] + vy * dt
			var gy: float = w.y_at_x(x)
			if y <= gy + 0.15:
				y = gy + 0.15
				if absf(vy) > 4.0:
					vy = absf(vy) * 0.35
					_cvx[i] *= 0.6
				else:
					_cst[i] = 1
					_ct[i] = 0.0
			_cx[i] = x
			_cy[i] = y
			_cvy[i] = vy
		elif st == 1:
			var d: float = Vector2(_cx[i] - b.x, _cy[i] - b.y).length()
			if (t > 0.25 and d < mag_r) or t > 2.2 or not night:
				_cst[i] = 2
				_ct[i] = 0.0
		elif st == 2:
			var dx: float = b.x - _cx[i]
			var dy: float = b.y - _cy[i]
			var dist: float = sqrt(dx * dx + dy * dy)
			var spd: float = 12.0 + t * 60.0 + bspd
			if dist < pick_r:
				_pickup(i)
				_coin_remove(i)
				continue
			_cx[i] += dx / maxf(0.01, dist) * minf(dist, spd * dt)
			_cy[i] += dy / maxf(0.01, dist) * minf(dist, spd * dt)
		elif st == 3:
			var k: float = minf(1.0, t / 0.3)
			var e: float = k * k
			_cpx[i] = lerpf(_csx[i], hud.x, e)
			_cpy[i] = lerpf(_csy[i], hud.y, e)
			if k >= 1.0:
				_pickup(i)
				_coin_remove(i)


func _pickup(i: int) -> void:
	_note(_ctier[i])
	var val: float = _cval[i]
	collected += val
	if on_pickup.is_valid():
		on_pickup.call(val)


## 拾取一枚的音（合成的 pickup：tier 0 铜 / 1 银 / 2 金，step = 连拾序号）
func _note(tier: int) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _note_last_t > CHAIN_RESET:
		_note_step = 0
	_note_last_t = now
	if _note_frame < NOTE_FRAME and _note_tokens >= 1.0:
		_note_tokens -= 1.0
		_note_frame += 1
		Sfx.play(&"pickup", [tier, _note_step])
		_note_step += 1


# ———————————————— 绘制 ————————————————
func _draw() -> void:
	var _pt: int = Prof.t()
	_draw_impl()
	Prof.add(&"fx.draw", _pt)


func _draw_impl() -> void:
	if sim == null or wv == null or sim.world == null:
		return
	var ppm: float = wv.ppm_screen()
	# 世界米 → 屏幕像素（= wv.to_screen，变换只取一次）
	var ct: Transform2D = wv.get_viewport().get_canvas_transform()
	var mpx: float = WorldView.PPM
	var vh: float = get_viewport_rect().size.y
	var night: bool = sim.night_k() > 0.5
	var coin_tex: Array[Texture2D] = [SpriteDB.tex(COIN_SPR[0]), SpriteDB.tex(COIN_SPR[1]), SpriteDB.tex(COIN_SPR[2])]
	_build_batches(ct, mpx, ppm, night)
	var deco_r: float = maxf(5.0, minf(14.0, 0.35 * ppm))
	for i: int in _deco_p.size():
		_coin(coin_tex[1], _deco_p[i], deco_r, _deco_s[i], _deco_a[i], 1)
	if not _misc.is_empty():
		_draw_misc(ct, mpx, ppm, vh, night)
	if not _tri.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), _tri, _tri_c)
	if not _seg.is_empty():
		draw_multiline_colors(_seg, _seg_c, 1.0)
	if not _seg2.is_empty():
		draw_multiline_colors(_seg2, _seg2_c, 2.0)
	var cr: float = clampf(0.3 * ppm, 5.0, 12.0)
	for i: int in _cx.size():
		var pos: Vector2
		var tier: int = clampi(_ctier[i], 0, 2)
		if _cst[i] == 3:
			pos = Vector2(_cpx[i], _cpy[i])
		else:
			pos = ct * Vector2(_cx[i] * mpx, -_cy[i] * mpx)
		var tex: Texture2D = coin_tex[tier]
		if tex == null:
			_coin(tex, pos, cr * (0.85 + 0.15 * tier), _cspin[i], 1.0, tier)
			continue
		# = _coin 的贴图分支，内联省掉几百次函数调用
		var sx: float = absf(cos(_cspin[i])) * 0.75 + 0.25
		var rr: float = cr * (0.85 + 0.15 * tier) * 1.25
		draw_texture_rect(tex, Rect2(pos.x - rr * sx, pos.y - rr, rr * 2.0 * sx, rr * 2.0), false, Color.WHITE)


# —— 每帧攒的批次（_build_batches 写，_draw_impl 画）——
var _tri: PackedVector2Array = []
var _tri_c: PackedColorArray = []
var _seg: PackedVector2Array = []      # 碎屑描边（1 像素）
var _seg_c: PackedColorArray = []
var _seg2: PackedVector2Array = []     # 尘土刻线、火星（2 像素）
var _seg2_c: PackedColorArray = []
var _deco_p: PackedVector2Array = []   # 装饰币：屏幕位置、翻转角、透明度（逐个画贴图）
var _deco_s: PackedFloat64Array = []
var _deco_a: PackedFloat64Array = []


## 小粒子攒成批次：碎屑、灰尘、烟、火星攒成三角形一批、线段两批一次画完，不逐个粒子设变换、画多边形——
## 碾城时几百个粒子逐个画，特效层每帧要 3 毫秒（2026-10-15 实测）。每团几何 = 单位模板 × Transform2D（引擎里一次算完），
## 同色的一团颜色先 fill 进暂存数组再整段追加；循环里不调 GDScript 函数（调用本身就贵）
func _build_batches(ct: Transform2D, mpx: float, ppm: float, night: bool) -> void:
	var ink: Color = Color("05070f") if night else INK
	var line: Color = Color("8fb0d8") if night else LINE
	# 尘土：瓶画式的卷云小团（三瓣扁云 + 一道卷曲刻线），比陶土山体（terrain_mat.tres）浅一档；
	# 白天浅陶土色、夜里浅石板蓝。单个正圆在人物身上像半透明气泡，所以不用
	var dust_c: Color = DUST_NIGHT if night else DUST_DAY
	var dust_a: float = 0.26 if night else 0.42
	var dline_c: Color = DUST_LINE_NIGHT if night else DUST_LINE_DAY
	var dline_a: float = 0.32 if night else 0.55
	var dust_tri: PackedVector2Array = _dust_tri
	var arc1: PackedVector2Array = _dust_arc1
	var arc2: PackedVector2Array = _dust_arc2
	var smoke_tri: PackedVector2Array = _smoke_tri
	var fill_d: PackedColorArray = []
	fill_d.resize(dust_tri.size())
	var fill_a: PackedColorArray = []
	fill_a.resize((arc1.size() + arc2.size()) >> 1)
	var fill_s: PackedColorArray = []
	fill_s.resize(smoke_tri.size())
	var tri: PackedVector2Array = []
	var tri_c: PackedColorArray = []
	var seg: PackedVector2Array = []
	var seg_c: PackedColorArray = []
	var seg2: PackedVector2Array = []
	var seg2_c: PackedColorArray = []
	var deco_p: PackedVector2Array = []
	var deco_s: PackedFloat64Array = []
	var deco_a: PackedFloat64Array = []
	for i: int in _n:
		var a: float = 1.0 - _t[i] / _life[i]
		var s: Vector2 = ct * Vector2(_x[i] * mpx, -_y[i] * mpx)
		var k: int = _k[i]
		if k == K_DUST:
			var r: float = maxf(2.0, _s[i] * ppm)
			var sd: float = fposmod(_a[i] * 7.13, 1.0)
			tri.append_array(Transform2D(Vector2(r, 0.0), Vector2(0.0, r), s + Vector2((sd - 0.5) * 0.2 * r, 0.0)) * dust_tri)
			fill_d.fill(Color(dust_c, dust_a * a))
			tri_c.append_array(fill_d)
			if r > 5.0:
				var a0: float = PI * (0.9 + sd * 0.4)
				seg2.append_array(Transform2D(a0, Vector2(r * 0.42, r * 0.42), 0.0, s + Vector2(0.05, -0.1) * r) * arc1)
				seg2.append_array(Transform2D(a0, Vector2(r * 0.2, r * 0.2), 0.0, s + Vector2(0.18, -0.06) * r) * arc2)
				fill_a.fill(Color(dline_c, dline_a * a))
				seg2_c.append_array(fill_a)
		elif k == K_SHARD or k == K_SHARD_REST:
			var sz: float = maxf(2.0, _s[i] * ppm)
			var xf: Transform2D = Transform2D(_a[i], Vector2(sz, sz), 0.0, s)
			var aa: float = minf(1.0, a * 3.0)
			var fc: Color = Color(ink, aa)
			var lc: Color = Color(line, aa)
			tri.append_array(xf * SHARD_TRI)
			tri_c.push_back(fc)
			tri_c.push_back(fc)
			tri_c.push_back(fc)
			seg.append_array(xf * SHARD_SEG)
			seg_c.push_back(lc)
			seg_c.push_back(lc)
			seg_c.push_back(lc)
		elif k == K_SPARK:
			seg2.push_back(s)
			seg2.push_back(s + Vector2(-_vx[i], _vy[i]) * 0.03 * ppm)
			seg2_c.push_back(Color(GOLD_HI, a))
		elif k == K_SMOKE:
			var k2: float = _t[i] / _life[i]
			var r3: float = maxf(2.0, _s[i] * ppm)
			var fade: float = minf(1.0, _t[i] / 0.5) * (1.0 - k2) * (1.0 - k2)
			tri.append_array(Transform2D(Vector2(r3, 0.0), Vector2(0.0, r3), s) * smoke_tri)
			fill_s.fill(Color(ink, 0.72 * fade))
			tri_c.append_array(fill_s)
		elif k == K_DECO:
			deco_p.push_back(s)
			deco_s.push_back(_a[i])
			deco_a.push_back(a)
	_tri = tri
	_tri_c = tri_c
	_seg = seg
	_seg_c = seg_c
	_seg2 = seg2
	_seg2_c = seg2_c
	_deco_p = deco_p
	_deco_s = deco_s
	_deco_a = deco_a


## 飘字、冲击环、飞出的物件（数量少，逐个画）
func _draw_misc(ct: Transform2D, mpx: float, ppm: float, vh: float, night: bool) -> void:
	var font: Font = Fonts.cinzel(700)
	for p: Dictionary in _misc:
		var a: float = 1.0 - float(p["t"]) / float(p["life"])
		var s: Vector2 = ct * Vector2(float(p["x"]) * mpx, -float(p["y"]) * mpx)
		match p["k"]:
			&"flyer":
				var tex: Texture2D = SpriteDB.tex(p["spr"])
				if tex != null:
					var fw: float = float(p["w"]) * ppm
					var fh: float = float(p["h"]) * ppm
					draw_set_transform(s, float(p["rot"]), Vector2.ONE)
					var tint: Color = Color(0.62, 0.72, 0.88) if night else Color.WHITE
					draw_texture_rect(tex, Rect2(-fw / 2.0, -fh / 2.0, fw, fh), false, Color(tint, minf(1.0, a * 2.0)))
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			&"ring":
				var k: float = float(p["t"]) / float(p["life"])
				var e: float = 1.0 - pow(1.0 - k, 3.0)
				var r1: float = float(p["r1"]) * ppm
				var r0: float = float(p["r0"]) * ppm
				var mx: float = float(p["max"]) * vh
				if mx > 0.0 and r1 > mx:
					r0 *= mx / r1
					r1 = mx
				draw_arc(s, r0 + (r1 - r0) * e, 0.0, TAU, 48, Color(p["color"] as Color, (1.0 - k) * (1.0 - k)), maxf(0.6, float(p["w"]) * (1.0 - 0.7 * e)), true)
			&"text":
				var pop: float = 1.0 + (0.12 - float(p["t"])) * 5.0 if float(p["t"]) < 0.12 else 1.0
				var fs: int = maxi(8, roundi(float(p["size"]) * pop))
				var str: String = p["s"]
				# 字宽按字号记在飘字上（弹出那 0.12 秒字号在变，之后不变，不必每帧量）
				var tw: float
				if int(p.get("tw_fs", -1)) == fs:
					tw = p["tw"]
				else:
					tw = font.get_string_size(str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
					p["tw_fs"] = fs
					p["tw"] = tw
				var aa2: float = minf(1.0, a * 2.5)
				draw_string_outline(font, s - Vector2(tw / 2.0, 0.0), str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85 * aa2))
				draw_string(font, s - Vector2(tw / 2.0, 0.0), str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(p["color"] as Color, aa2))


# —— 几何模板（单位尺寸，绘制时 × Transform2D 一次变换整团）——
const DUST_LOBES: Array[Vector3] = [Vector3(-0.55, 0.12, 0.62), Vector3(0.05, -0.18, 0.78), Vector3(0.6, 0.1, 0.56)]
## 尘土三瓣扁云（各 10 片扇形），半径 1 = r
static var _dust_tri: PackedVector2Array = _build_dust_tri()
## 尘土卷曲刻线两段弧（起角 0，绘制时转 a0）：大弧 1.3π 分 8 段，小弧从 1.3π 到 2.4π 分 5 段
static var _dust_arc1: PackedVector2Array = _build_arc(0.0, PI * 1.3, 8)
static var _dust_arc2: PackedVector2Array = _build_arc(PI * 1.3, PI * 2.4, 5)
## 烟：一大团（12 片）+ 右上一小团（10 片）
static var _smoke_tri: PackedVector2Array = _build_smoke_tri()
const SHARD_TRI: PackedVector2Array = [Vector2(-0.6, -0.4), Vector2(0.7, -0.2), Vector2(-0.1, 0.6)]
const SHARD_SEG: PackedVector2Array = [Vector2(-0.6, -0.4), Vector2(0.7, -0.2), Vector2(0.7, -0.2), Vector2(-0.1, 0.6), Vector2(-0.1, 0.6), Vector2(-0.6, -0.4)]


static func _build_dust_tri() -> PackedVector2Array:
	var out: PackedVector2Array = []
	var cols: PackedColorArray = []
	for lobe: Vector3 in DUST_LOBES:
		_fan(out, cols, Vector2(lobe.x, lobe.y * 0.7), lobe.z, lobe.z * 0.72, Color.WHITE, 10)
	return out


static func _build_smoke_tri() -> PackedVector2Array:
	var out: PackedVector2Array = []
	var cols: PackedColorArray = []
	_fan(out, cols, Vector2.ZERO, 1.0, 1.0, Color.WHITE, 12)
	_fan(out, cols, Vector2(0.55, -0.35), 0.6, 0.6, Color.WHITE, 10)
	return out


static func _build_arc(a0: float, a1: float, n: int) -> PackedVector2Array:
	var out: PackedVector2Array = []
	var cols: PackedColorArray = []
	_arc(out, cols, Vector2.ZERO, 1.0, a0, a1, n, Color.WHITE)
	return out


## 实心椭圆（扇形三角形）攒进批次
static func _fan(pts: PackedVector2Array, cols: PackedColorArray, c: Vector2, rx: float, ry: float, col: Color, n: int) -> void:
	var prev: Vector2 = c + Vector2(rx, 0.0)
	for i: int in range(1, n + 1):
		var th: float = TAU * float(i) / float(n)
		var q: Vector2 = c + Vector2(cos(th) * rx, sin(th) * ry)
		pts.append_array([c, prev, q])
		cols.append_array([col, col, col])
		prev = q


## 弧线（折线段）攒进批次
static func _arc(pts: PackedVector2Array, cols: PackedColorArray, c: Vector2, r: float, a0: float, a1: float, n: int, col: Color) -> void:
	var prev: Vector2 = c + Vector2(cos(a0), sin(a0)) * r
	for i: int in range(1, n + 1):
		var th: float = lerpf(a0, a1, float(i) / float(n))
		var q: Vector2 = c + Vector2(cos(th), sin(th)) * r
		pts.append_array([prev, q])
		cols.append(col)
		prev = q


const COIN_SPR: Array[StringName] = [&"coin_obol", &"coin_drachma", &"coin_stater"]


func _coin(tex: Texture2D, pos: Vector2, r: float, spin: float, alpha: float, tier: int) -> void:
	var sx: float = absf(cos(spin)) * 0.75 + 0.25
	if tex != null:
		# 翻转只压扁宽度：直接算矩形，不设变换（同一张图的金币才能合成一批）
		var rr: float = r * 1.25
		draw_texture_rect(tex, Rect2(pos.x - rr * sx, pos.y - rr, rr * 2.0 * sx, rr * 2.0), false, Color(1, 1, 1, alpha))
		return
	draw_set_transform(pos, 0.0, Vector2(sx, 1.0))
	var face: Color = [Color("b87333"), Color("c9c4b8"), GOLD][clampi(tier, 0, 2)]
	draw_circle(Vector2(0, 1), r, Color(0.48, 0.3, 0.05, alpha))
	draw_circle(Vector2.ZERO, r, Color(face, alpha))
	draw_arc(Vector2.ZERO, r * 0.68, 0.0, TAU, 16, Color(0.54, 0.35, 0.07, alpha), maxf(1.0, r * 0.14))
	draw_circle(Vector2(-r * 0.3, -r * 0.3), r * 0.22, Color(GOLD_HI, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
