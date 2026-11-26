extends Node
## autoload `Sfx`：音效总管（architecture §13、arch-present §1.11）。
## 网页 audio.js 是 WebAudio 实时合成；这里不合成，播放 tools/sfx_render 离线渲染好的 WAV（godot/assets/sfx/），
## 清单在 present/data/sfx_bank.json（渲染脚本生成：每个音效的参数网格、变体文件、总线、限流参数、音乐闪避）。
##
## 公开 API（与网页 sfx 同名）：
##   play(name, args)        一次性音效；args 按网页函数的实参，例如 play(&"crunch", [tier, size])。
##                            名字也可以是 rumble / chorus / ambience / slowmo / stopAll（转到对应的持续音接口）。
##                            未知名字只 push_warning 一次，不报错。
##   music(track, args)      chorus / ambience / rumble / stop 的别名入口；menu / day / feast / off 转到 bgm()。
##   bgm(track)              背景音乐 &"menu" / &"day" / &"feast" / &"off"（交叉淡入淡出，Music 总线）。
##                            白天 / 黄昏 / 夜里由 phase 事件自动切（day → 白天曲，其余 → 关）；首页、夜宴由 main 调。
##   rumble(speed01, size01) 滚石隆隆（可每帧调用）。follow_stone(sim) 按网页 game.js:638 的公式从 sim 算好再调它。
##   chorus(level 0..5)      合唱团层数。ambience(mode)  &"day" / &"night" / &"off"（也接受 0.0 = 白天、1.0 = 夜里）。
##   slowmo(on)              World 总线 LowPass + PitchShift 平滑进出（1100Hz、-150 音分）。
##   set_master(v) set_muted(b) set_bus_volume(bus, v) stop_all()
##   on_events(list)         SimEvent 入口：sfx / slowmo / phase / crush 四种 kind（见 _on_event）。
##
## 总线（present/audio/default_bus_layout.tres；缺失时 _ensure_buses 用代码补建）：
##   Master[Compressor(-6dB, 20:1，= 网页 limiter), HardLimiter] ← World[LowPass, PitchShift（慢动作才开）] ← SFX / Music / Amb
##   UI → Master（按钮类音效不受慢动作影响）。混响已烘进 WAV（离线渲染用的就是网页的卷积混响），所以没有单独的混响总线。
##
## 真实采样（第二份清单 present/data/sfx_samples.json，手写，render.js 不会覆盖）：
##   sounds  采样音效（CC0 素材加工成的 WAV，在 assets/sfx/real/），可直接 play(名字)；可按实参分档（tiers）、按实参加减增益。
##   hooks   合成音效名 → 采样："replace" 代替合成（step → push）；"before" 先放采样、隔 delay 秒再放原合成
##           （gateImpact：先一记撞门，再放原来那段像结算的和声）；"with" 同时叠放。只认调用时的名字，别名（faith）不经过 hook。
##   music   背景音乐曲目（assets/music/*.ogg，循环），g = 默认音量 dB。

const BANK_PATH: String = "res://present/data/sfx_bank.json"
const SAMPLES_PATH: String = "res://present/data/sfx_samples.json"
const MAX_VOICES: int = 24          # 网页 MAX_VOICES：一次性音效并发上限（prio 1 额外 +8，prio 2 不受限）
const POOL_SIZE: int = 40           # 播放器个数：24 + 8 + 给 prio 2 留的余量
const MASTER_TRIM: float = 0.8      # 网页 MASTER_TRIM（主音量 = 1 时进入限幅器前的增益）
const SLOW_CENTS: float = -150.0    # 网页 SLOW_CENTS
const SLOW_LP_HZ: float = 1100.0    # 网页 SLOW_LP_HZ
const LP_OPEN_HZ: float = 20000.0
const SLOW_IN_SEC: float = 0.25     # 网页 applySlowmo：进入 0.25s，退出 0.45s
const SLOW_OUT_SEC: float = 0.45
const BUS_NAMES: Dictionary = {"sfx": &"SFX", "music": &"Music", "amb": &"Amb", "ui": &"UI"}

# —— 清单 ——
var _loaded: bool = false
var _sounds: Dictionary = {}        # 名字(String) → 条目
var _aliases: Dictionary = {}
var _loops: Dictionary = {}
var _dir: String = "res://assets/sfx/"
var _streams: Dictionary = {}       # 文件名 → AudioStream（懒加载缓存）
var _rot: Dictionary = {}           # 名字|格 → 下一个变体序号
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# —— 采样清单（sfx_samples.json）——
var _smp: Dictionary = {}           # 采样音效名 → 条目
var _hooks: Dictionary = {}         # 合成音效名 → {mode, to, delay}
var _smp_dir: String = "res://assets/sfx/real/"
var _smp_last: Dictionary = {}      # 名字|档 → 上次用的文件序号（避免连续两次同一个）
var _pending: Array[Dictionary] = []   # hook "before" 延后播放的合成音效：{at, name, args}

# —— 未知名字 ——
var _warned: Dictionary = {}
## 已发出的"未知音效"警告条数（测试读）
var warn_count: int = 0

# —— 限流（= 网页 lastFire / liveEnds）——
var _last_fire: Dictionary = {}     # key → 秒
var _live_end: PackedFloat64Array = []
var _live_key: Array[StringName] = []
## 测试用：≥ 0 时代替真实时钟（秒）
var clock_override: float = -1.0

# —— 播放池 ——
var _pool: Array[AudioStreamPlayer] = []
var _pool_prio: PackedInt32Array = []
var _pool_t: PackedFloat64Array = []

# —— 音量 ——
var _master: float = 1.0
var _muted: bool = false
var _bus_user: Dictionary = {&"SFX": 1.0, &"Music": 1.0, &"Amb": 1.0, &"UI": 1.0}
var _duck_gain: float = 1.0
var _duck_target: float = 1.0
var _duck_release_at: float = 0.0

# —— 慢动作 ——
var _slow_on: bool = false
var _slow_k: float = 0.0            # 0 = 正常，1 = 完全进入慢动作
var _night: bool = false
var _auto_slow: bool = false
var _fc_slow: float = 1.0           # 复刻 FeelClock（网页 time.slow），用于"夜里且 slow < 0.8 才开滤波"
var _fc_hold: float = 0.0
var _fc_from: float = 1.0
var _fc_recover: float = 0.3
var _fc_t: float = 0.0

# —— 滚石隆隆 ——
var _rum_players: Array[AudioStreamPlayer] = []
var _rum_vol_i: PackedFloat32Array = []
var _rum_gain_i: PackedFloat32Array = []
var _rum_speeds: PackedFloat32Array = []
var _rum_sizes: PackedFloat32Array = []
var _rum_ts: float = 0.0            # 目标
var _rum_tz: float = 0.0
var _rum_s: float = 0.0             # 平滑后
var _rum_z: float = 0.0
var _rum_v: float = 0.0
var _rum_idle: float = 0.0

# —— 合唱团：0..4 = 第 1..5 层，5 = 鼓型 4，6 = 鼓型 5 ——
var _cho_players: Array[AudioStreamPlayer] = []
var _cho_db: PackedFloat32Array = []
var _cho_gain: PackedFloat32Array = []
var _cho_target: PackedFloat32Array = []
var _cho_tau: PackedFloat32Array = []
var _cho_at: PackedFloat64Array = []
var _cho_level: int = 0

# —— 背景音乐：两个播放器交叉淡入淡出 ——
var _music_cfg: Dictionary = {}
var _bgm_players: Array[AudioStreamPlayer] = []
var _bgm_track: PackedStringArray = ["", ""]
var _bgm_gain: PackedFloat32Array = [0.0, 0.0]
var _bgm_target: PackedFloat32Array = [0.0, 0.0]
var _bgm_cur: StringName = &"off"

# —— 环境声：0 = 白天，1 = 夜里 ——
var _amb_players: Array[AudioStreamPlayer] = []
var _amb_db: PackedFloat32Array = []
var _amb_gain: PackedFloat32Array = [0.0, 0.0]
var _amb_target: PackedFloat32Array = [0.0, 0.0]
var _amb_tau: PackedFloat32Array = [0.8, 0.8]
var _amb_mode: StringName = &"off"


func _ready() -> void:
	Prof.mark("Sfx 开始")
	_rng.randomize()
	_ensure_loaded()
	_ensure_buses()
	for i: int in POOL_SIZE:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		add_child(p)
		_pool.append(p)
		_pool_prio.append(0)
		_pool_t.append(0.0)
	_apply_volumes()
	Prof.mark("Sfx 完成")


func _process(delta: float) -> void:
	var _pt: int = Prof.t()
	_process_impl(delta)
	Prof.add(&"audio.process", _pt)


func _process_impl(delta: float) -> void:
	advance(delta)


func _exit_tree() -> void:
	# 退出时先停掉所有播放器，避免播放中的流在引擎清理时仍被占用
	for c: Node in get_children():
		var p: AudioStreamPlayer = c as AudioStreamPlayer
		if p != null:
			p.stop()
			p.stream = null


# ———————————————————— 一次性音效 ————————————————————
## 播放一条音效。args 与网页 sfx.<name>(...) 的实参一致；数值以外的参数忽略。
func play(sfx_name: StringName, args: Array = []) -> void:
	_ensure_loaded()
	var key: String = String(sfx_name)
	match key:
		"rumble":
			rumble(_arg(args, 0, 0.0), _arg(args, 1, 0.0))
			return
		"chorus":
			chorus(_arg(args, 0, 0.0))
			return
		"ambience":
			ambience(_first(args))
			return
		"slowmo":
			slowmo(args.size() > 0 and bool(args[0]))
			return
		"stopAll", "stop_all":
			stop_all()
			return
		"init", "resume", "suspend":
			return
	# 采样清单：hook 只认调用时的名字（别名不经过）
	if _hooks.has(key):
		var hk: Dictionary = _hooks[key]
		var to: StringName = StringName(str(hk.get("to", "")))
		match str(hk.get("mode", "replace")):
			"replace":
				play_sample(to, args)
				return
			"before":
				play_sample(to, args)
				_pending.append({"at": _now() + float(hk.get("delay", 0.3)), "name": key, "args": args})
				return
			"with":
				play_sample(to, args)
	elif _smp.has(key):
		play_sample(sfx_name, args)
		return
	_play_bank(key, args)


## 合成清单（sfx_bank.json）里的一条：别名 → 吸附参数格 → 准入 → 播放。不经过 hooks。
func _play_bank(key: String, args: Array) -> void:
	var sfx_name: StringName = StringName(key)
	var call_args: Array = args
	if _aliases.has(key):
		var al: Dictionary = _aliases[key]
		key = str(al.get("to", ""))
		call_args = al.get("args", []) as Array
	if not _sounds.has(key):
		_warn_once(sfx_name)
		return
	if _muted or _master <= 0.0:
		return   # 网页 ready()：静音时直接不放
	var snd: Dictionary = _sounds[key]
	var cell_key: String = cell_key_for(key, call_args)
	var cells: Dictionary = snd.get("cells", {})
	if not cells.has(cell_key):
		_warn_once(StringName(key + "#" + cell_key))
		return
	var cell: Dictionary = cells[cell_key]
	var adm: Dictionary = cell.get("admit", {})
	var prio: int = int(adm.get("prio", 0))
	if not admit(StringName(str(adm.get("key", key))), float(adm.get("gap", 0.0)), float(adm.get("dur", 0.5)), prio, int(adm.get("max_same", 0))):
		return
	var files: Array = cell.get("files", [])
	if files.is_empty():
		return
	var rk: String = key + "|" + cell_key
	var n: int = int(_rot.get(rk, _rng.randi_range(0, files.size() - 1)))
	_rot[rk] = (n + 1) % files.size()
	var fe: Dictionary = files[n % files.size()]
	var duck: Variant = cell.get("duck", null)
	if duck is Array and (duck as Array).size() >= 2:
		_duck(float((duck as Array)[0]), float((duck as Array)[1]))
	if _pool.is_empty():
		return   # 不在场景树里（单元测试直接 new 出来的实例）：只走准入逻辑
	var stream: AudioStream = _stream(str(fe.get("f", "")))
	if stream == null:
		return
	var p: AudioStreamPlayer = _pick_player(prio)
	if p == null:
		return
	var pj: float = float(snd.get("pitch_jitter", 0.0))
	var vj: float = float(snd.get("vol_jitter_db", 0.0))
	p.stream = stream
	p.bus = _bus_of(str(snd.get("bus", "sfx")))
	p.volume_db = float(fe.get("g", 0.0)) + (_rng.randf_range(-vj, vj) * 0.5 if vj > 0.0 else 0.0)
	p.pitch_scale = 1.0 + (_rng.randf_range(-pj, pj) if pj > 0.0 else 0.0)
	p.play()


## 播放采样清单里的一条（sfx_samples.json 的 sounds）。args[param] 是 0..1 的强度：选档（tiers）、加减增益（param_gain_db）。
func play_sample(smp_name: StringName, args: Array = []) -> void:
	_ensure_loaded()
	var key: String = String(smp_name)
	if not _smp.has(key):
		_warn_once(StringName("sample:" + key))
		return
	if _muted or _master <= 0.0:
		return
	var s: Dictionary = _smp[key]
	var v: float = clampf(_arg(args, int(s.get("param", 0)), 0.0), 0.0, 1.0)
	var files: Array = s.get("files", [])
	var g: float = float(s.get("g", 0.0))
	var adm: Dictionary = s.get("admit", {})
	var tier_i: int = -1
	var tiers: Array = s.get("tiers", [])
	for i: int in tiers.size():
		if v >= float((tiers[i] as Dictionary).get("min", 0.0)):
			tier_i = i
	if tier_i >= 0:
		var t: Dictionary = tiers[tier_i]
		files = t.get("files", [])
		g += float(t.get("g", 0.0))
		adm = t.get("admit", adm)
	var pg: Array = s.get("param_gain_db", [])
	if pg.size() >= 2:
		g += lerpf(float(pg[0]), float(pg[1]), v)
	var prio: int = int(adm.get("prio", 0))
	if not admit(StringName(str(adm.get("key", key))), float(adm.get("gap", 0.0)), float(adm.get("dur", 0.5)), prio, int(adm.get("max_same", 0))):
		return
	if files.is_empty() or _pool.is_empty():
		return   # 不在场景树里（单元测试）：只走准入
	# 随机挑一个，但不和上一次相同
	var lk: String = key + "|" + str(tier_i)
	var n: int = _rng.randi_range(0, files.size() - 1)
	if files.size() > 1 and n == int(_smp_last.get(lk, -1)):
		n = (n + 1 + _rng.randi_range(0, files.size() - 2)) % files.size()
	_smp_last[lk] = n
	var stream: AudioStream = _stream_path(_smp_dir + str(files[n]) + ".wav")
	if stream == null:
		return
	var p: AudioStreamPlayer = _pick_player(prio)
	if p == null:
		return
	var pj: float = float(s.get("pitch_jitter", 0.0))
	var vj: float = float(s.get("vol_jitter_db", 0.0))
	p.stream = stream
	p.bus = _bus_of(str(s.get("bus", "sfx")))
	p.volume_db = g + (_rng.randf_range(-vj, vj) * 0.5 if vj > 0.0 else 0.0)
	p.pitch_scale = 1.0 + (_rng.randf_range(-pj, pj) if pj > 0.0 else 0.0)
	p.play()


## 采样清单里的名字（测试用）
func sample_names() -> PackedStringArray:
	_ensure_loaded()
	return PackedStringArray(_smp.keys())


## 参数吸附到网格：返回 sfx_bank.json 里 cells 的键（各参数网格下标用 | 连接，无参数为 "-"）。
func cell_key_for(sfx_name: String, args: Array) -> String:
	_ensure_loaded()
	var snd: Dictionary = _sounds.get(sfx_name, {})
	var params: Array = snd.get("params", [])
	if params.is_empty():
		return "-"
	var parts: PackedStringArray = []
	for i: int in params.size():
		var p: Dictionary = params[i]
		var vals: Array = p.get("values", [])
		var v: float = float(p.get("def", 0.0)) if p.get("def", null) != null else 0.0
		if i < args.size() and (args[i] is float or args[i] is int):
			v = float(args[i])
		if p.has("cycle") and not vals.is_empty():
			var cyc: Array = p["cycle"]
			var st: float = float(cyc[0])
			if v > float(vals[vals.size() - 1]):
				v = st + fposmod(floorf(v) - st, float(cyc[1]))
		parts.append(str(_nearest(vals, v)))
	return "|".join(parts)


## 限流 + 并发上限（逐行照搬网页 admit）。prio：0 普通，1 重要（上限 +8），2 必播；max_same ≤ 0 表示不限同类数。
func admit(key: StringName, gap: float, dur: float, prio: int = 0, max_same: int = 0) -> bool:
	var now: float = _now()
	if _last_fire.has(key) and now - float(_last_fire[key]) < gap:
		return false
	var ends: PackedFloat64Array = []
	var keys: Array[StringName] = []
	for i: int in _live_end.size():
		if _live_end[i] > now:
			ends.append(_live_end[i])
			keys.append(_live_key[i])
	_live_end = ends
	_live_key = keys
	if prio < 2 and _live_end.size() >= MAX_VOICES + (8 if prio > 0 else 0):
		return false
	if max_same > 0 and _live_key.count(key) >= max_same:
		return false
	_last_fire[key] = now
	_live_end.append(now + dur)
	_live_key.append(key)
	return true


## 当前在播（按网页 liveEnds 计）的一次性音效数。
func live_voices() -> int:
	var now: float = _now()
	var n: int = 0
	for e: float in _live_end:
		if e > now:
			n += 1
	return n


# ———————————————————— 持续音 ————————————————————
## 滚石隆隆：speed01 = 0 静音；size01 越大越低沉越响。可每帧调用。
func rumble(speed01: float, size01: float) -> void:
	_ensure_loaded()
	_rum_ts = clampf(speed01, 0.0, 1.0)
	_rum_tz = clampf(size01, 0.0, 1.0)
	if _rum_ts > 0.0 and _rum_players.is_empty() and is_inside_tree():
		_start_rumble()


## 按网页 game.js:638 从模拟状态算出 rumble 参数（只读 sim）。表现层每帧调一次即可；不在夜里时不动。
func follow_stone(sim: SimGame) -> void:
	if sim == null or sim.phase != &"night":
		return
	var b: Boulder = sim.stone
	var vx: float = b.vx if b.air else b.v * cos(b.ang)
	var vy: float = b.vy if b.air else b.v * sin(b.ang)
	rumble(0.0 if b.air else clampf(sqrt(vx * vx + vy * vy) / 35.0, 0.0, 1.0), sim.mass_norm(b.r))


## 合唱团层数 0..5：层自下而上逐个淡入（间隔 0.45s）、自上而下淡出；第 4 层起带鼓。
func chorus(level: float) -> void:
	_ensure_loaded()
	var lv: int = clampi(roundi(level), 0, 5)
	if lv == _cho_level:
		return
	var prev: int = _cho_level
	_cho_level = lv
	if not is_inside_tree():
		return
	if _cho_players.is_empty():
		if lv == 0 or not _start_chorus():
			return
	var now: float = _now()
	if prev == 0:
		# 从静音进入：如果之前的尾音已经淡完，从第一小节重新开始（网页 cho.bar = 0）
		var quiet: bool = true
		for gn: float in _cho_gain:
			quiet = quiet and gn < 0.01
		if quiet or not _cho_players[0].playing:
			for p: AudioStreamPlayer in _cho_players:
				p.play(0.0)
	for i: int in 5:
		var on: bool = i < lv
		var was: bool = i < prev
		if on == was:
			continue
		var order: int = i - prev if on else prev - 1 - i
		_cho_set(i, 1.0 if on else 0.0, now + order * 0.45, 0.45 if on else 0.6)
		if i == 3:   # 网页：第 4 层的开关同时开关鼓
			_cho_set(5, 1.0 if on and lv == 4 else 0.0, now + order * 0.45, 0.3)
			_cho_set(6, 1.0 if on and lv >= 5 else 0.0, now + order * 0.45, 0.3)
	if prev >= 4 and lv >= 4:   # 鼓一直开着，只换鼓型（网页在下一小节换）
		_cho_set(5, 1.0 if lv == 4 else 0.0, now, 0.1)
		_cho_set(6, 1.0 if lv >= 5 else 0.0, now, 0.1)


## 环境声：&"day" / &"night" / &"off"；数字 0.0 = 白天、1.0 = 夜里（SimEvent 约定）。
func ambience(mode: Variant) -> void:
	_ensure_loaded()
	var m: StringName = &"off"
	if mode is float or mode is int:
		m = &"night" if float(mode) >= 0.5 else &"day"
	elif mode is String or mode is StringName:
		var s: String = str(mode)
		m = StringName(s) if s == "day" or s == "night" else &"off"
	if m == _amb_mode:
		return
	_amb_mode = m
	if not is_inside_tree():
		return
	if m != &"off" and _amb_players.is_empty() and not _start_ambience():
		return
	if _amb_players.is_empty():
		return
	_amb_target[0] = 1.0 if m == &"day" else 0.0
	_amb_target[1] = 1.0 if m == &"night" else 0.0
	for i: int in 2:
		_amb_tau[i] = 0.8 if _amb_target[i] > 0.0 else 0.5
		if _amb_target[i] > 0.0 and not _amb_players[i].playing:
			_amb_players[i].play(0.0)


# ———————————————————— 慢动作 / 音量 ————————————————————
## 慢动作：World 总线低通 20k → 1100Hz（0.25s）+ 降调 -150 音分；退出 0.45s。UI 总线不受影响。
func slowmo(on: bool) -> void:
	_slow_on = on


func is_slowmo() -> bool:
	return _slow_on


## 主音量 0..1。
func set_master(v: float) -> void:
	_master = clampf(v, 0.0, 1.0)
	_apply_volumes()


func set_muted(b: bool) -> void:
	_muted = b
	_apply_volumes()


## 分总线音量 0..1（&"SFX" / &"Music" / &"Amb" / &"UI"）。
func set_bus_volume(bus: StringName, v: float) -> void:
	_bus_user[bus] = clampf(v, 0.0, 1.0)
	_apply_volumes()


## 回主菜单：停掉所有持续音和背景音乐、退出慢动作（一次性音效让它自然放完，同网页 stopAll）。
func stop_all() -> void:
	_pending.clear()
	bgm(&"off")
	chorus(0.0)
	ambience(&"off")
	rumble(0.0, 0.0)
	_auto_slow = false
	_night = false
	_fc_slow = 1.0
	_fc_hold = 0.0
	slowmo(false)


## 背景音乐入口（保留 F1 占位的签名）：track = chorus / ambience / rumble / stop，或 bgm 曲目 menu / day / feast / off。
func music(track: StringName, args: Array = []) -> void:
	if track != &"off" and (_music_cfg.get("tracks", {}) as Dictionary).has(String(track)):
		bgm(track)
		return
	match track:
		&"chorus":
			chorus(_arg(args, 0, 0.0))
		&"ambience":
			ambience(_first(args))
		&"rumble":
			rumble(_arg(args, 0, 0.0), _arg(args, 1, 0.0))
		&"stop", &"off":
			chorus(0.0)
			bgm(&"off")
		_:
			_warn_once(StringName("music:" + String(track)))


# ———————————————————— SimEvent 入口 ————————————————————
## 模拟事件分发（main 的 _on_events 里调用）。只读事件，不改 sim。
func on_events(list: Array[SimEvent]) -> void:
	for e: SimEvent in list:
		_on_event(e)


func _on_event(e: SimEvent) -> void:
	match e.kind:
		&"sfx":
			match e.name:
				&"rumble":
					rumble(e.a, e.b)
				&"chorus":
					chorus(e.a)
				&"ambience":
					ambience(e.a)   # 0.0 = 白天，1.0 = 夜里
				&"step":
					# 网页 game.js:314：S('step'); 30% 概率再 pushGrunt(load/6)。Godot 的 sim 把 load/6 放在 a 里
					# （step 被采样清单换成 push，load 决定推动声的轻重；pushGrunt 换成很轻的人声，自带 1.1s 限流）
					play(&"step", [e.a])
					if _rng.randf() < 0.3:
						play(&"pushGrunt", [e.a])
				_:
					play(e.name, [e.a, e.b])
		&"slowmo":
			_feel_slowmo(e.a, e.b, e.c)
		&"phase":
			var ph: StringName = StringName(str(e.data.get("phase", "")))
			_night = ph == &"night"
			# 白天放白天曲；黄昏（铜锣）、夜里（合唱团接管）、登顶等待都关掉
			bgm(&"day" if ph == &"day" else &"off")
		&"crush":
			# 网页 game.js:867：有叫声的物件 70% 概率叫一声（sim 把 voice 放在 crush 事件里，不单独发 sfx）
			var vo: String = str(e.data.get("voice", ""))
			if vo != "" and _rng.randf() < 0.7:
				play(StringName(vo))


## 每帧推进（_process 调用；测试可直接调）：慢动作滤波、音乐闪避、持续音的音量平滑。
func advance(dt: float) -> void:
	_step_pending()
	_step_bgm(dt)
	_step_feel(dt)
	var want: bool = _night and _fc_slow < 0.8
	if want != _auto_slow:
		_auto_slow = want
		slowmo(want)
	_step_slow(dt)
	_step_duck(dt)
	_step_rumble(dt)
	_step_chorus(dt)
	_step_ambience(dt)


# ———————————————————— 内部：清单与总线 ————————————————————
func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(BANK_PATH):
		push_warning("[Sfx] 缺少 " + BANK_PATH + "（先跑 tools/sfx_render）")
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(BANK_PATH))
	if not d is Dictionary:
		push_warning("[Sfx] sfx_bank.json 解析失败")
		return
	var bank: Dictionary = d
	_sounds = bank.get("sounds", {})
	_aliases = bank.get("aliases", {})
	_loops = bank.get("loops", {})
	_dir = str(bank.get("dir", _dir))
	# 第二份清单：真实采样 + 背景音乐（手写；缺失时只用合成音效）
	if FileAccess.file_exists(SAMPLES_PATH):
		var sd: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAMPLES_PATH))
		if sd is Dictionary:
			var sm: Dictionary = sd
			_smp = sm.get("sounds", {})
			_hooks = sm.get("hooks", {})
			_smp_dir = str(sm.get("dir", _smp_dir))
			_music_cfg = sm.get("music", {})
		else:
			push_warning("[Sfx] sfx_samples.json 解析失败")


## 清单里的全部名字（含别名），测试用。
func bank_names() -> PackedStringArray:
	_ensure_loaded()
	var out: PackedStringArray = []
	for k: Variant in _sounds.keys():
		out.append(str(k))
	for k: Variant in _aliases.keys():
		out.append(str(k))
	return out


## 默认总线布局没加载上时（例如被别的布局覆盖）用代码补建缺的总线。
func _ensure_buses() -> void:
	if AudioServer.get_bus_index(&"World") < 0:
		var w: int = AudioServer.bus_count
		AudioServer.add_bus(w)
		AudioServer.set_bus_name(w, "World")
		AudioServer.set_bus_send(w, &"Master")
		var lp: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
		lp.cutoff_hz = LP_OPEN_HZ
		AudioServer.add_bus_effect(w, lp)
		AudioServer.add_bus_effect(w, AudioEffectPitchShift.new())
		AudioServer.set_bus_effect_enabled(w, 0, false)
		AudioServer.set_bus_effect_enabled(w, 1, false)
	for bn: StringName in [&"SFX", &"Music", &"Amb", &"UI"]:
		if AudioServer.get_bus_index(bn) < 0:
			var i: int = AudioServer.bus_count
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, String(bn))
			AudioServer.set_bus_send(i, &"Master" if bn == &"UI" else &"World")


func _bus_of(b: String) -> StringName:
	return BUS_NAMES.get(b, &"SFX") as StringName


func _stream(fname: String) -> AudioStream:
	return _stream_path(_dir + fname + ".wav")


## 按完整路径加载（缓存；失败只警告一次）
func _stream_path(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path] as AudioStream
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
	if s == null:
		_warn_once(StringName("file:" + path))
	_streams[path] = s
	return s


func _warn_once(n: StringName) -> void:
	if _warned.has(n):
		return
	_warned[n] = true
	warn_count += 1
	push_warning("[Sfx] 未知音效（只提示一次）：" + String(n))


func _now() -> float:
	return clock_override if clock_override >= 0.0 else Time.get_ticks_usec() / 1e6


func _arg(args: Array, i: int, def: float) -> float:
	if i < args.size() and (args[i] is float or args[i] is int or args[i] is bool):
		return float(args[i])
	return def


func _first(args: Array) -> Variant:
	if args.is_empty():
		return &"off"
	return args[0]


func _nearest(vals: Array, v: float) -> int:
	var best: int = 0
	var bd: float = INF
	for i: int in vals.size():
		var dd: float = absf(float(vals[i]) - v)
		if dd < bd - 1e-9:
			bd = dd
			best = i
	return best


## 挑一个空闲播放器；都忙时抢占"优先级不高于自己、开播最早"的那个。
func _pick_player(prio: int) -> AudioStreamPlayer:
	var now: float = _now()
	var victim: int = -1
	for i: int in _pool.size():
		if not _pool[i].playing:
			victim = i
			break
	if victim < 0:
		for i: int in _pool.size():
			if _pool_prio[i] <= prio and (victim < 0 or _pool_prio[i] < _pool_prio[victim] or (_pool_prio[i] == _pool_prio[victim] and _pool_t[i] < _pool_t[victim])):
				victim = i
	if victim < 0:
		return null
	_pool_prio[victim] = prio
	_pool_t[victim] = now
	return _pool[victim]


func _apply_volumes() -> void:
	var mi: int = AudioServer.get_bus_index(&"Master")
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi, linear_to_db(maxf(_master * MASTER_TRIM, 1e-5)))
		AudioServer.set_bus_mute(mi, _muted or _master <= 0.0)
	for bn: StringName in [&"SFX", &"Music", &"Amb", &"UI"]:
		var bi: int = AudioServer.get_bus_index(bn)
		if bi >= 0:
			var v: float = float(_bus_user.get(bn, 1.0)) * (_duck_gain if bn == &"Music" else 1.0)
			AudioServer.set_bus_volume_db(bi, linear_to_db(maxf(v, 1e-5)))


static func _approach(cur: float, target: float, tau: float, dt: float) -> float:
	if tau <= 0.0:
		return target
	return target + (cur - target) * exp(-dt / tau)


# ———————————————————— 内部：闪避 / 慢动作 ————————————————————
## 网页 duck()：大冲击时把合唱团压低一会儿。
func _duck(depth: float, hold: float) -> void:
	_duck_target = minf(1.0 - clampf(depth, 0.0, 0.9), _duck_gain)
	_duck_release_at = _now() + hold


func _step_duck(dt: float) -> void:
	var releasing: bool = _now() >= _duck_release_at
	var tgt: float = 1.0 if releasing else _duck_target
	var ng: float = _approach(_duck_gain, tgt, 0.6 if releasing else 0.03, dt)
	if absf(ng - _duck_gain) > 1e-5:
		_duck_gain = ng
		_apply_volumes()


## 复刻 FeelClock.slowmo（网页 time.slowmo），只用来判断 time.slow < 0.8。
func _feel_slowmo(factor: float, hold: float, recover: float) -> void:
	if _fc_hold > 0.0 and factor >= _fc_slow:
		_fc_hold = maxf(_fc_hold, hold)
		return
	_fc_slow = factor
	_fc_from = factor
	_fc_hold = hold
	_fc_recover = maxf(recover, 1e-3)
	_fc_t = 0.0


func _step_feel(dt: float) -> void:
	if _fc_hold > 0.0:
		_fc_hold -= dt
	elif _fc_slow < 1.0:
		_fc_t += dt
		var k: float = minf(1.0, _fc_t / _fc_recover)
		_fc_slow = _fc_from + (1.0 - _fc_from) * (1.0 - pow(1.0 - k, 3.0))


func _step_slow(dt: float) -> void:
	var tgt: float = 1.0 if _slow_on else 0.0
	if _slow_k == tgt:
		return
	var rate: float = 1.0 / (SLOW_IN_SEC if _slow_on else SLOW_OUT_SEC)
	_slow_k = minf(tgt, _slow_k + rate * dt) if _slow_on else maxf(tgt, _slow_k - rate * dt)
	apply_slow_k(_slow_k)


## 把慢动作进度 k（0..1）写到 World 总线的效果器上（测试可直接调）。
func apply_slow_k(k: float) -> void:
	_slow_k = clampf(k, 0.0, 1.0)
	var wi: int = AudioServer.get_bus_index(&"World")
	if wi < 0 or AudioServer.get_bus_effect_count(wi) < 2:
		return
	var lp: AudioEffectLowPassFilter = AudioServer.get_bus_effect(wi, 0) as AudioEffectLowPassFilter
	var ps: AudioEffectPitchShift = AudioServer.get_bus_effect(wi, 1) as AudioEffectPitchShift
	var active: bool = _slow_k > 1e-4
	if lp != null:
		lp.cutoff_hz = exp(lerpf(log(LP_OPEN_HZ), log(SLOW_LP_HZ), _slow_k))
	if ps != null:
		ps.pitch_scale = pow(2.0, SLOW_CENTS * _slow_k / 1200.0)
	AudioServer.set_bus_effect_enabled(wi, 0, active)
	AudioServer.set_bus_effect_enabled(wi, 1, active)


# ———————————————————— 内部：持续音 ————————————————————
func _loop_player(fname: String, bus: StringName, label: String) -> AudioStreamPlayer:
	var s: AudioStream = _stream(fname)
	if s == null:
		return null
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.name = label
	p.stream = s
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	return p


func _start_rumble() -> void:
	var lp: Dictionary = _loops.get("rumble", {})
	if lp.is_empty():
		_warn_once(&"loop:rumble")
		return
	_rum_speeds = PackedFloat32Array(lp.get("speeds", []) as Array)
	_rum_sizes = PackedFloat32Array(lp.get("sizes", []) as Array)
	var files: Dictionary = lp.get("files", {})
	for si: int in _rum_speeds.size():
		for zi: int in _rum_sizes.size():
			var fe: Dictionary = files.get("%d|%d" % [si, zi], {})
			var p: AudioStreamPlayer = _loop_player(str(fe.get("f", "")), _bus_of(str(lp.get("bus", "sfx"))), "Rumble%d_%d" % [si, zi])
			if p == null:
				for q: AudioStreamPlayer in _rum_players:
					q.queue_free()
				_rum_players.clear()
				return
			_rum_players.append(p)
			_rum_vol_i.append(float(fe.get("vol", 1.0)))
			_rum_gain_i.append(db_to_linear(float(fe.get("g", 0.0))))
	for p: AudioStreamPlayer in _rum_players:
		p.play(0.0)


## 网页 setRumble 的 vol 公式。
static func rumble_vol(s: float, z: float) -> float:
	return 0.0 if s <= 0.001 else (0.12 + 0.88 * pow(s, 0.8)) * lerpf(0.4, 1.0, z) * 0.6


func _seg(grid: PackedFloat32Array, v: float) -> Vector2:
	# 返回 (下标 i, 权重 t)：v 落在 grid[i]..grid[i+1] 之间
	if grid.size() < 2 or v <= grid[0]:
		return Vector2(0, 0)
	for i: int in grid.size() - 1:
		if v <= grid[i + 1]:
			return Vector2(i, (v - grid[i]) / maxf(grid[i + 1] - grid[i], 1e-6))
	return Vector2(grid.size() - 2, 1)


func _step_rumble(dt: float) -> void:
	if _rum_players.is_empty():
		return
	var tv: float = rumble_vol(_rum_ts, _rum_tz)
	_rum_v = _approach(_rum_v, tv, 0.15 if tv == 0.0 else 0.08, dt)
	_rum_s = _approach(_rum_s, _rum_ts, 0.08, dt)
	_rum_z = _approach(_rum_z, _rum_tz, 0.08, dt)
	if tv == 0.0 and _rum_v < 1e-4:
		_rum_idle += dt
		if _rum_idle > 0.5:   # 静音半秒后停掉，省 CPU；再响时从头起播
			for p: AudioStreamPlayer in _rum_players:
				p.queue_free()
			_rum_players.clear()
			_rum_vol_i.clear()
			_rum_gain_i.clear()
			_rum_v = 0.0
			return
	else:
		_rum_idle = 0.0
	var ss: Vector2 = _seg(_rum_speeds, _rum_s)
	var zs: Vector2 = _seg(_rum_sizes, _rum_z)
	var nz: int = _rum_sizes.size()
	for si: int in _rum_speeds.size():
		var ws: float = (1.0 - ss.y) if si == int(ss.x) else (ss.y if si == int(ss.x) + 1 else 0.0)
		var rate: float = (0.8 + 0.35 * _rum_s) / (0.8 + 0.35 * _rum_speeds[si])
		for zi: int in nz:
			var wz: float = (1.0 - zs.y) if zi == int(zs.x) else (zs.y if zi == int(zs.x) + 1 else 0.0)
			var idx: int = si * nz + zi
			# 噪声类素材用等功率交叉淡化：振幅权重取 sqrt
			var amp: float = sqrt(ws * wz) * _rum_v / maxf(_rum_vol_i[idx], 1e-4) * _rum_gain_i[idx]
			var p: AudioStreamPlayer = _rum_players[idx]
			p.volume_db = linear_to_db(maxf(amp, 1e-5))
			p.pitch_scale = clampf(rate, 0.5, 2.0)


func _start_chorus() -> bool:
	var lp: Dictionary = _loops.get("chorus", {})
	if lp.is_empty():
		_warn_once(&"loop:chorus")
		return false
	var names: Array = (lp.get("stems", []) as Array).duplicate()
	names.append(lp.get("drums4", ""))
	names.append(lp.get("drums5", ""))
	var gains: Dictionary = lp.get("gains", {})
	var bus: StringName = _bus_of(str(lp.get("bus", "music")))
	for i: int in names.size():
		var p: AudioStreamPlayer = _loop_player(str(names[i]), bus, "Chorus%d" % i)
		if p == null:
			for q: AudioStreamPlayer in _cho_players:
				q.queue_free()
			_cho_players.clear()
			return false
		_cho_players.append(p)
		_cho_db.append(float((gains.get(str(names[i]), {}) as Dictionary).get("g", 0.0)))
		_cho_gain.append(0.0)
		_cho_target.append(0.0)
		_cho_tau.append(0.45)
		_cho_at.append(0.0)
	return true


func _cho_set(i: int, target: float, at: float, tau: float) -> void:
	if i >= _cho_target.size():
		return
	_cho_target[i] = target
	_cho_at[i] = at
	_cho_tau[i] = tau


func _step_chorus(dt: float) -> void:
	if _cho_players.is_empty():
		return
	var now: float = _now()
	var all_quiet: bool = true
	for i: int in _cho_players.size():
		if now >= _cho_at[i]:
			_cho_gain[i] = _approach(_cho_gain[i], _cho_target[i], _cho_tau[i], dt)
		all_quiet = all_quiet and _cho_gain[i] < 1e-3 and _cho_target[i] == 0.0
		_cho_players[i].volume_db = linear_to_db(maxf(_cho_gain[i], 1e-5)) + _cho_db[i]
	if all_quiet and _cho_level == 0:
		for p: AudioStreamPlayer in _cho_players:
			p.stop()


# ———————————————————— 背景音乐 ————————————————————
## 切换背景音乐：&"menu" / &"day" / &"feast"；&"off" 或未知曲目 = 淡出。同一首正在放时不重来。
func bgm(track: StringName) -> void:
	_ensure_loaded()
	var tracks: Dictionary = _music_cfg.get("tracks", {})
	var t: String = String(track) if tracks.has(String(track)) else ""
	if t == "" and track != &"off":
		_warn_once(StringName("bgm:" + String(track)))
	_bgm_cur = StringName(t) if t != "" else &"off"
	if not is_inside_tree():
		return
	if _bgm_players.is_empty():
		if t == "":
			return
		for i: int in 2:
			var p: AudioStreamPlayer = AudioStreamPlayer.new()
			p.name = "Bgm%d" % i
			p.bus = &"Music"
			p.volume_db = -80.0
			add_child(p)
			_bgm_players.append(p)
	# 已经在某个播放器上（可能正在淡出）：把它拉回来，另一个淡出
	var slot: int = -1
	for i: int in 2:
		if t != "" and _bgm_track[i] == t and _bgm_players[i].playing:
			slot = i
	if slot < 0 and t != "":
		# 用较安静的那个播放器起新曲
		slot = 0 if _bgm_gain[0] <= _bgm_gain[1] else 1
		var cfg: Dictionary = tracks[t]
		var st: AudioStream = _stream_path(str(_music_cfg.get("dir", "res://assets/music/")) + str(cfg.get("f", "")))
		if st == null:
			slot = -1
		else:
			if st is AudioStreamOggVorbis:
				(st as AudioStreamOggVorbis).loop = true
			elif st is AudioStreamMP3:
				(st as AudioStreamMP3).loop = true
			_bgm_track[slot] = t
			_bgm_gain[slot] = 0.0
			_bgm_players[slot].stream = st
			_bgm_players[slot].play(0.0)
	for i: int in 2:
		_bgm_target[i] = 1.0 if i == slot else 0.0


## 当前背景音乐曲目（&"off" = 没有）
func bgm_track() -> StringName:
	return _bgm_cur


func _step_bgm(dt: float) -> void:
	if _bgm_players.is_empty():
		return
	var tracks: Dictionary = _music_cfg.get("tracks", {})
	var fin: float = maxf(0.05, float(_music_cfg.get("fade_in", 2.0)))
	var fout: float = maxf(0.05, float(_music_cfg.get("fade_out", 1.2)))
	for i: int in 2:
		var p: AudioStreamPlayer = _bgm_players[i]
		var tg: float = _bgm_target[i]
		# 线性淡入淡出（按振幅）
		if _bgm_gain[i] < tg:
			_bgm_gain[i] = minf(tg, _bgm_gain[i] + dt / fin)
		elif _bgm_gain[i] > tg:
			_bgm_gain[i] = maxf(tg, _bgm_gain[i] - dt / fout)
		var g: float = float((tracks.get(_bgm_track[i], {}) as Dictionary).get("g", 0.0))
		p.volume_db = linear_to_db(maxf(_bgm_gain[i], 1e-5)) + g
		if tg == 0.0 and _bgm_gain[i] <= 0.0 and p.playing:
			p.stop()
			_bgm_track[i] = ""


## hook "before"：到点放原合成音效（不再经过 hooks）
func _step_pending() -> void:
	if _pending.is_empty():
		return
	var now: float = _now()
	var keep: Array[Dictionary] = []
	for it: Dictionary in _pending:
		if now >= float(it["at"]):
			_play_bank(str(it["name"]), it["args"] as Array)
		else:
			keep.append(it)
	_pending = keep


## 等待延后播放的合成音效数（测试用）
func pending_count() -> int:
	return _pending.size()


func _start_ambience() -> bool:
	var lp: Dictionary = _loops.get("ambience", {})
	var files: Dictionary = lp.get("files", {})
	if files.is_empty():
		_warn_once(&"loop:ambience")
		return false
	var bus: StringName = _bus_of(str(lp.get("bus", "amb")))
	for mode: String in ["day", "night"]:
		var fe: Dictionary = files.get(mode, {})
		var p: AudioStreamPlayer = _loop_player(str(fe.get("f", "")), bus, "Amb_" + mode)
		if p == null:
			for q: AudioStreamPlayer in _amb_players:
				q.queue_free()
			_amb_players.clear()
			_amb_db.clear()
			return false
		_amb_players.append(p)
		_amb_db.append(float(fe.get("g", 0.0)))
	return true


func _step_ambience(dt: float) -> void:
	if _amb_players.is_empty():
		return
	for i: int in 2:
		_amb_gain[i] = _approach(_amb_gain[i], _amb_target[i], _amb_tau[i], dt)
		var p: AudioStreamPlayer = _amb_players[i]
		p.volume_db = linear_to_db(maxf(_amb_gain[i], 1e-5)) + _amb_db[i]
		if _amb_target[i] == 0.0 and _amb_gain[i] < 1e-3 and p.playing:
			p.stop()
