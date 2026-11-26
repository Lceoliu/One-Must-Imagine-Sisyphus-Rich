class_name ChestSystem
extends RefCounted
## 命运宝瓶（docs/v06/incremental.md 第 6.2 节）：某些建筑（ObjDef.jar > 0）夜里碾碎时必掉一只，档次 = jar；石头碰到就开，
## 三个转轮（克罗托 / 拉刻西斯 / 阿特洛波斯）各停在「命运」或「德拉克马」上：
##   每个命运格 = 档次 × moira_mult ×（1 + jar_tier_k × 石头尺寸档）份命运；三格全是命运 × jar_jackpot（三女神点头）；
##   每个德拉克马格 = 今夜已碾价值的 jar_coin（单个宝瓶的金币合计不超过 15%）；三格全是德拉克马 → 迈达斯之触 8 秒。
## 看得见的金币、线团、转盘动画都在表现层；这里只发事件。转盘按模拟时间推进。

const GRAV: float = 30.0
## stats.amphora_cap 的默认值（契约在它上面加减，上限按差值算）
const AMPHORA_BASE: float = 4.0

var g: SimGame = null
## {x, y, vx, vy, k, h, state: &"fall"|&"idle"|&"open", t, given, res, grade, reels: [0 德拉克马 | 1 命运] ×3, moira}
## res：0 有命运也有德拉克马（或开之前）、1 三格命运（大奖）、2 三格德拉克马（迈达斯）
var chests: Array[Dictionary] = []
var wheel_q: Array[Dictionary] = []
var wheel: Dictionary = {}              # {ch, res, t, apply_at, end, applied}
var burst_count: int = 0
var chests_dropped: int = 0
var midas_t: float = 0.0
var midas_chest: Dictionary = {}


func bind(p_g: SimGame) -> void:
	g = p_g


func clear() -> void:
	chests.clear()
	wheel_q.clear()
	wheel = {}
	burst_count = 0
	chests_dropped = 0
	midas_t = 0.0
	midas_chest = {}


func _view_k() -> float:
	return maxf(1.0, g.cam_view_h / 14.0)


func _stone_vel() -> Array[float]:
	var b: Boulder = g.stone
	if b.air:
		return [b.vx, b.vy]
	var a: float = b.ang
	return [b.v * cos(a), b.v * sin(a)]


## 碾碎物件时（coins.js:198 burst 的经济部分）：迈达斯差额记账、会掉宝瓶的建筑掉宝瓶；发出看得见的金币事件
## jar：这件掉的宝瓶档次（ObjDef.jar，神造之城再加 jar_add；0 = 不掉）
func on_burst(x: float, y: float, value: float, tier: int, big: bool, type: StringName, jar: int = -1) -> void:
	if not (value > 0.0):
		return
	var v: float = value
	var gold: bool = false
	if midas_t > 0.0 and not midas_chest.is_empty() and g.night_total_valid:
		var budget: float = maxf(0.0, 0.15 * g.night_total - float(midas_chest["given"]))
		var extra: float = minf(v, budget)
		if extra > 0.0:
			g.add_night_bonus(extra, Loc.t("chests.midas_touch", "迈达斯之触"), NAN, NAN, false)   # 金币已经并进这次碾碎的金币里
			midas_chest["given"] = float(midas_chest["given"]) + extra
			v += extra
		gold = true
	burst_count += 1
	g.fx.burst(x, y, v, tier, big, type, gold)
	var st: Stats = g.stats
	if jar < 0:
		var od: ObjDef = g.content.object_by_id.get(type)
		jar = od.jar if od != null else 0
	# 每夜上限 = chest_max；amphora_cap 的默认值是 4（网页时代的旧上限），契约在它上面加减
	var cap: float = g.content.tuning.chest_max + st.amphora_cap - AMPHORA_BASE
	if jar > 0 and chests_dropped < int(cap) and g.phase == &"night":
		_drop_chest(x, y, jar)


func _drop_chest(x: float, y: float, grade: int) -> void:
	chests_dropped += 1
	var k: float = _view_k()
	var h: float = clampf(g.cam_view_h * 0.1, 1.5, 7.0)
	var bv: Array[float] = _stone_vel()
	var ch: Dictionary = {"x": x, "y": y, "vx": bv[0] * 0.9 - (3.0 + g.stone.r) * k * 0.5, "vy": 9.0 * k, "k": k, "h": h,
		"state": &"fall", "t": 0.0, "given": 0.0, "res": -1, "id": chests_dropped, "grade": grade, "reels": [], "moira": 0.0}
	chests.append(ch)
	g.fx.event(&"chest_drop", {"id": ch["id"], "h": h}, x, y)


func update(dt: float) -> void:
	if midas_t > 0.0:
		midas_t -= dt
	var b: Boulder = g.stone
	for i: int in range(chests.size() - 1, -1, -1):
		var ch: Dictionary = chests[i]
		ch["t"] = float(ch["t"]) + dt
		var state: StringName = ch["state"]
		if state == &"fall":
			ch["vy"] = float(ch["vy"]) - GRAV * float(ch["k"]) * dt
			ch["x"] = float(ch["x"]) + float(ch["vx"]) * dt
			ch["y"] = float(ch["y"]) + float(ch["vy"]) * dt
			ch["vx"] = float(ch["vx"]) * exp(-0.8 * dt)
			if float(ch["x"]) < g.world.gate_x + 6.0:
				ch["x"] = g.world.gate_x + 6.0
				ch["vx"] = 0.0
			var gy: float = g.world.y_at_x(ch["x"])
			if float(ch["y"]) <= gy and float(ch["vy"]) < 0.0:
				ch["y"] = gy
				ch["state"] = &"idle"
				ch["t"] = 0.0
				g.fx.dust(ch["x"], gy, 4, float(ch["h"]) * 0.3, 2.0)
		elif state == &"idle":
			if float(ch["x"]) - b.x > -(b.r + float(ch["h"]) * 0.45 + 0.5) and b.y - b.r < float(ch["y"]) + float(ch["h"]) * 1.3 + 2.0 * float(ch["k"]):
				_open(ch)
		elif state == &"open":
			if float(ch["t"]) > 3.2:
				chests.remove_at(i)
	_update_wheel(dt)


func _open(ch: Dictionary) -> void:
	ch["state"] = &"open"
	ch["t"] = 0.0
	_roll(ch)
	g.fx.slowmo(0.3, 0.5, 0.5)
	g.fx.shake(0.2)
	g.fx.sfx(&"chestOpen")
	g.fx.sparks(ch["x"], float(ch["y"]) + float(ch["h"]) * 0.6, 18, 8)
	g.fx.event(&"chest_open", {"id": ch["id"], "res": ch["res"]}, ch["x"], ch["y"])
	wheel_q.append(ch)


## 三个转轮各自停在命运（1）或德拉克马（0）
func _roll(ch: Dictionary) -> void:
	# 第一座祭坛点亮之前：照常摇（迈达斯大奖的概率不变，前几天的收入和以前一样），但转出命运的格子改付德拉克马、
	# 画面上也显示成金币——命运和三女神开张都在第一座祭坛之后（节奏：先祭坛、再命运；后代带祖传跑得快也一样；演示局不管）
	var before_altar: bool = not g.demo and g.boons.done.is_empty()
	var p: float = clampf(g.stats.moira_p, 0.0, 1.0)
	var reels: Array = []
	var n: int = 0
	for i: int in 3:
		var m: int = 1 if g.rand.next(SimRandom.Use.CHEST) < p else 0
		reels.append(m)
		n += m
	ch["res"] = 1 if n == 3 else (2 if n == 0 else 0)
	if before_altar:
		reels = [0, 0, 0]
		if int(ch["res"]) == 1:
			ch["res"] = 0
	ch["reels"] = reels
	g.run_stats["jars"] = int(g.run_stats.get("jars", 0)) + 1
	if n == 3:
		g.run_stats["jackpots"] = int(g.run_stats.get("jackpots", 0)) + 1


# 转盘：三格依次停下（0.5 / 0.85 / 1.2–1.6s），停完结算，再展示 1.35s
func _update_wheel(dt: float) -> void:
	if wheel.is_empty():
		if wheel_q.is_empty():
			return
		var ch: Dictionary = wheel_q.pop_front()
		wheel = {"ch": ch, "res": ch["res"], "t": 0.0, "apply_at": 1.4, "end": 1.4 + 1.35, "applied": false}
		g.fx.event(&"wheel_start", {"id": ch["id"], "res": ch["res"]})
	wheel["t"] = float(wheel["t"]) + dt
	if not wheel["applied"] and float(wheel["t"]) >= float(wheel["apply_at"]):
		_apply_fate()
	if float(wheel["t"]) >= float(wheel["end"]):
		wheel = {}


## 金币雨：每个德拉克马格 = 今夜已碾价值的 jar_coin；单个宝瓶的金币（含迈达斯差额）合计不超过当夜已碾价值的 15%
func chest_rain(ch: Dictionary) -> float:
	var nt: float = g.night_total if g.night_total_valid else 0.0
	var coins: int = 0
	for r: Variant in ch["reels"]:
		if int(r) == 0:
			coins += 1
	var cap: float = maxf(0.0, 0.15 * nt - float(ch["given"]))
	return minf(g.content.tuning.jar_coin * coins * nt, cap)


## 命运：每个命运格 = 档次 × moira_mult × (1 + jar_tier_k × 石头尺寸档)；三格全中再 × jar_jackpot
func chest_moira(ch: Dictionary) -> float:
	var n: int = 0
	for r: Variant in ch["reels"]:
		n += int(r)
	var tk: float = 1.0 + g.content.tuning.jar_tier_k * g.size_tier(g.stone.r)
	var v: float = roundf(n * int(ch["grade"]) * g.stats.moira_mult * tk)
	return v * g.content.tuning.jar_jackpot if n == 3 else v


func _apply_fate() -> void:
	wheel["applied"] = true
	var ch: Dictionary = wheel["ch"]
	var res: int = wheel["res"]
	_pay(ch)
	if res == 2:
		midas_t = 8.0
		midas_chest = ch
	g.fx.shake(0.45 if res != 0 else 0.15)
	g.fx.sfx(&"fate", res)
	g.fx.event(&"fate", {"id": ch["id"], "res": res, "value": float(ch["given"]), "moira": float(ch["moira"])}, ch["x"], ch["y"])


## 按转轮结果付钱：金币雨 + 命运
func _pay(ch: Dictionary) -> void:
	var rain: float = chest_rain(ch)
	if rain > 0.0 and g.night_total_valid:
		g.add_night_bonus(rain, Loc.t("chests.fate_urn", "命运宝瓶"), float(ch["x"]), float(ch["y"]) + float(ch["h"]) * 0.4)
		ch["given"] = float(ch["given"]) + rain
	var mo: float = chest_moira(ch)
	if mo > 0.0:
		g.add_moira(mo, float(ch["x"]), float(ch["y"]) + float(ch["h"]) * 0.6)
		ch["moira"] = float(ch["moira"]) + mo


## 夜晚结束（coins.js:604 collectAll 的经济部分）：没揭晓的宝瓶立即按结果结算，地上没开的现在摇（不演）
func collect_all() -> void:
	if not wheel.is_empty() and not wheel["applied"]:
		wheel["applied"] = true
		_pay(wheel["ch"])
	for ch: Dictionary in wheel_q:
		_pay(ch)
	wheel_q.clear()
	for ch: Dictionary in chests:
		if ch["state"] != &"open":
			_roll(ch)
			_pay(ch)
	var kept: Array[Dictionary] = []
	for c: Dictionary in chests:
		if c["state"] == &"open":
			kept.append(c)
	chests = kept
	midas_t = 0.0
	midas_chest = {}
