class_name BetBoard
extends Control
## 盘口墓碑上的刻度、金线和筹码（BetScreen 填数据，这里只画）。墓碑贴图 bet_stele 上刻好了一串刻度：
## 刻度从贴图的 y = TICK_BOT 到 y = TICK_TOP（原图像素），把 [lo, hi] 米线性地铺上去，每个大刻度旁写海拔。
## 不开盘的区域（太稳 / 赔率超过上限）压暗；金线（最高纪录）横穿碑面、挂一块「纪录 X m」的牌子，一直看得见；以上的刻度微微发亮。

signal height_dragged(h: float)

const TEX_H: float = 1487.0
const TEX_W: float = 372.0
const TICK_TOP: float = 358.0
const TICK_BOT: float = 1222.0
## 大刻度在原图上的 y（每 5 小格一个）
const MAJOR: PackedFloat32Array = [453.0, 548.0, 645.0, 741.0, 838.0, 935.0, 1030.0, 1128.0]
const GOLD: Color = Color("f0b93a")
const CREAM: Color = Color("eadbb8")
const INK: Color = Color("120c0a")

var lo: float = 0.0
var hi: float = 100.0
## 开盘区间（米）；open_lo < 0 = 不开盘
var open_lo: float = -1.0
var open_hi: float = -1.0
var gold_line: float = 0.0
## 玩家筹码的高度
var h: float = 50.0
## 众神的筹码：[{god, h}]
var chips: Array = []
var _drag: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


## 原图像素 y → 本控件的 y
func _ty(py: float) -> float:
	return py / TEX_H * size.y


## 海拔 → 本控件的 y
func y_of(alt: float) -> float:
	var k: float = (alt - lo) / maxf(1.0, hi - lo)
	return lerpf(_ty(TICK_BOT), _ty(TICK_TOP), k)


func alt_of(y: float) -> float:
	var k: float = (y - _ty(TICK_BOT)) / (_ty(TICK_TOP) - _ty(TICK_BOT))
	return lo + k * (hi - lo)


func _draw() -> void:
	var cx: float = size.x * 0.5
	var f: Font = Fonts.serif(700)
	var top: float = _ty(TICK_TOP)
	var bot: float = _ty(TICK_BOT)
	var w: float = size.x * 0.34
	# 不开盘的两头：只在刻度那一窄条上压暗（刻度淡下去），不画大方块
	var band: float = size.x * 0.075
	if open_lo >= 0.0:
		var y_lo: float = y_of(open_lo)
		var y_hi: float = y_of(open_hi)
		if y_lo < bot:
			_shade(cx, band, y_lo, bot + 6.0)
		if y_hi > top:
			_shade(cx, band, top - 6.0, y_hi)
	else:
		_shade(cx, band, top - 6.0, bot + 6.0)
	var yg: float = y_of(gold_line)
	# 大刻度的海拔数字
	for py: float in MAJOR:
		var y: float = _ty(py)
		var alt: float = alt_of(y)
		draw_string(f, Vector2(cx + w * 0.42, y + 6.0), "%d" % roundi(alt), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(CREAM, 0.75))
	# 金线（以上的刻度在开盘时微微发金：沿刻度画一道细金线）
	if open_lo >= 0.0 and yg > top:
		var y0: float = maxf(top, y_of(open_hi))
		var y1: float = minf(yg, bot)
		if y1 > y0:
			draw_line(Vector2(cx + band * 0.55, y0), Vector2(cx + band * 0.55, y1), Color(GOLD, 0.35), 2.0, true)
	if yg >= top - 2.0 and yg <= bot + 2.0:
		draw_line(Vector2(cx - w * 1.15, yg), Vector2(cx + w * 1.15, yg), GOLD, 3.5, true)
		# 纪录牌：挂在金线左端，墨底金边
		var txt: String = Loc.t("bet_board.best_m", "纪录 %d m") % roundi(gold_line)
		var fs: int = 17
		var tw: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var plate: Rect2 = Rect2(cx - w * 1.15 - tw - 22.0, yg - 15.0, tw + 18.0, 30.0)
		draw_rect(plate, Color(INK, 0.92))
		draw_rect(plate, GOLD, false, 2.0)
		draw_string(f, Vector2(plate.position.x + 9.0, yg + 6.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, GOLD)
	# 众神的筹码：钉在刻度左边，错开一点免得叠在一起
	var used: Array[float] = []
	for c: Dictionary in chips:
		var y: float = clampf(y_of(float(c["h"])), top, bot)
		var off: float = 0.0
		for u: float in used:
			if absf(u - y) < 22.0:
				off += 30.0
		used.append(y)
		_chip(StringName("chip2_" + String(c["god"])), Vector2(cx - w * 0.55 - off, y), 38.0, 0.92)
	# 玩家的筹码（金边）：刻度右边
	var yp: float = clampf(y_of(h), top, bot)
	draw_line(Vector2(cx - w * 0.3, yp), Vector2(cx + w * 0.3, yp), Color(GOLD, 0.9), 2.0, true)
	_chip(&"chip2_player", Vector2(cx + w * 0.62, yp), 44.0, 1.0)


## 刻度窄条上的一段墨（上下两头渐隐）
func _shade(cx: float, band: float, y0: float, y1: float) -> void:
	if y1 <= y0:
		return
	draw_rect(Rect2(cx - band, y0, band * 2.0, y1 - y0), Color(INK, 0.72))


func _chip(key: StringName, c: Vector2, wd: float, a: float) -> void:
	var tex: Texture2D = SpriteDB.tex(key)
	if tex == null:
		draw_circle(c, wd * 0.4, Color(CREAM, a))
		return
	var hgt: float = wd / maxf(0.1, float(tex.get_width()) / float(tex.get_height()))
	draw_texture_rect(tex, Rect2(c - Vector2(wd, hgt) / 2.0, Vector2(wd, hgt)), false, Color(1, 1, 1, a))


func _gui_input(ev: InputEvent) -> void:
	var mb: InputEventMouseButton = ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		_drag = mb.pressed
		if mb.pressed:
			height_dragged.emit(alt_of(mb.position.y))
		accept_event()
		return
	var mm: InputEventMouseMotion = ev as InputEventMouseMotion
	if mm != null and _drag:
		height_dragged.emit(alt_of(mm.position.y))
		accept_event()
