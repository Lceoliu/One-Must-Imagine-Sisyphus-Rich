@tool
class_name HubFarLamps
extends Node2D
## 夜宴远景丘陵 / 海岸上的村庄灯火（= 白天 background_view.gd 的 _lamps_for + _draw_lamps，同一套种子和撒点规则，
## 所以和白天入夜时山脚下亮起的是同一批灯）。挂在平铺的背景 Sprite2D（region + 镜像平铺，centered = false）下面当子节点，
## 按父节点贴图的透明通道撒点；每一块平铺都画一遍（奇数块镜像）。材质用 unshaded（不被 CanvasModulate 压暗）。

## 撒几盏灯
@export var lamps: int = 14:
	set(v):
		lamps = v
		_pts = {}
		queue_redraw()
## 地平线上的渔船数（海岸用；0 = 不放，灯也不限制在地平线以上）
@export var fishing: int = 0:
	set(v):
		fishing = v
		_pts = {}
		queue_redraw()
## 随机种子（白天：丘陵 53，海岸 71）
@export var seed_value: int = 53:
	set(v):
		seed_value = v
		_pts = {}
		queue_redraw()
## 灯在屏幕上的大小（参考 1080 高的世界坐标：金点边长、光晕半径）
@export var dot: float = 2.0
@export var halo: float = 6.0
## 亮度（1 = 白天 night_k = 1 时的亮度）
@export var brightness: float = 1.0

var _pts: Dictionary = {}   # {lamps: Array[Vector4(u, v, 延迟, 相位)], boats: …}
## 撒点结果按（贴图、灯数、渔船、种子）缓存一局：要读贴图像素（导出版从显卡读回来），夜宴每晚重建，不缓存就每晚读一遍
static var _pts_cache: Dictionary = {}
var _t: float = 0.0


func _process(dt: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += dt
	queue_redraw()


func _parent_sprite() -> Sprite2D:
	return get_parent() as Sprite2D


func _points() -> Dictionary:
	if not _pts.is_empty():
		return _pts
	var sp: Sprite2D = _parent_sprite()
	var ck: String = ""
	if sp != null and sp.texture != null and sp.texture.resource_path != "" and not Engine.is_editor_hint():
		ck = "%s|%d|%d|%d" % [sp.texture.resource_path, lamps, fishing, seed_value]
		if _pts_cache.has(ck):
			_pts = _pts_cache[ck]
			return _pts
	_compute_points()
	if ck != "":
		_pts_cache[ck] = _pts
	return _pts


## 撒点（逐行移植 background_view.gd _lamps_for）
func _compute_points() -> Dictionary:
	if not _pts.is_empty():
		return _pts
	_pts = {"lamps": [], "boats": []}
	var sp: Sprite2D = _parent_sprite()
	if sp == null or sp.texture == null:
		return _pts
	var img: Image = sp.texture.get_image()
	if img == null:
		return _pts
	if img.is_compressed():
		img.decompress()
	var w: int = maxi(1, roundi(img.get_width() * 0.6))
	var h: int = maxi(1, roundi(img.get_height() * 0.6))
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var top: PackedInt32Array = []
	top.resize(w)
	for x: int in w:
		top[x] = -1
		for y: int in h:
			if img.get_pixel(x, y).a > 0.5:
				top[x] = y
				break
	var R: JsRng = JsRng.new(float(seed_value))
	var horizon: int = h
	if fishing > 0:
		var hist: Dictionary = {}
		for x: int in w:
			if top[x] >= 0:
				hist[top[x]] = int(hist.get(top[x], 0)) + 1
		var best: int = 0
		for y: Variant in hist.keys():
			if int(hist[y]) > best:
				best = int(hist[y])
				horizon = int(y)
	var out: Array = []
	var k: int = 0
	while k < 400 and out.size() < lamps:
		k += 1
		var x: int = 6 + int(floorf(R.next() * (w - 12)))
		if top[x] < 0:
			continue
		if fishing > 0 and top[x] > horizon - 6:
			continue
		var y: int = top[x] + 6 + int(floorf(R.next() * 34))
		if fishing > 0 and y > horizon - 2:
			continue
		if y >= h or img.get_pixel(x, y).a <= 200.0 / 255.0:
			continue
		var clash: bool = false
		for q: Vector4 in out:
			if absf(q.x * w - x) < 14.0 and absf(q.y * h - y) < 10.0:
				clash = true
				break
		if clash:
			continue
		out.append(Vector4(float(x) / w, float(y) / h, 0.3 + R.next() * 0.55, R.next() * 6.28))
	_pts["lamps"] = out
	var boats: Array = []
	k = 0
	while fishing > 0 and k < 200 and boats.size() < fishing:
		k += 1
		var bx: int = 20 + int(floorf(R.next() * (w - 40)))
		if absi(top[bx] - horizon) > 1:
			continue
		var near: bool = false
		for b: Vector4 in boats:
			if absf(b.x * w - bx) < w / 6.0:
				near = true
		if near:
			continue
		boats.append(Vector4(float(bx) / w, (horizon + 3.0 + R.next() * 5.0) / h, 0.35 + R.next() * 0.4, R.next() * 6.28))
	_pts["boats"] = boats
	return _pts


func _draw() -> void:
	var sp: Sprite2D = _parent_sprite()
	if sp == null or sp.texture == null:
		return
	var pts: Dictionary = _points()
	var tw: float = float(sp.texture.get_width())
	var th: float = float(sp.texture.get_height())
	var span: float = sp.region_rect.size.x if sp.region_enabled else tw
	var k: float = absf(sp.scale.x) if absf(sp.scale.x) > 0.0001 else 1.0
	var n: int = int(ceilf(span / tw))
	for i: int in n:
		var x0: float = float(i) * tw
		var mir: bool = (i & 1) == 1
		for p: Vector4 in pts["lamps"]:
			var x: float = (x0 + tw - p.x * tw) if mir else (x0 + p.x * tw)
			if x > span:
				continue
			_lamp(Vector2(x, p.y * th), brightness * (0.65 + 0.15 * sin(_t * 1.2566 + p.w)), dot / k, halo / k)
		for b: Vector4 in pts["boats"]:
			var bx: float = (x0 + tw - b.x * tw) if mir else (x0 + b.x * tw)
			if bx > span:
				continue
			var by: float = b.y * th
			_lamp(Vector2(bx, by), brightness * 0.6, dot * 0.75 / k, halo / k)
			# 渔火的倒影：下方 3 道断续的短线
			for kk: int in range(1, 4):
				var ww: float = (5.0 - kk + sin(_t * 2.0 + kk + b.w) * 1.2) / k
				draw_rect(Rect2(bx - ww / 2.0, by + (2.0 + kk * 2.2) / k, ww, 0.9 / k), Color(Palette.GOLD, brightness * 0.32))


func _lamp(c: Vector2, a: float, sz: float, r: float) -> void:
	if a <= 0.01:
		return
	# 背景细节"简"（设置 → 画面）：只画金点，不画光晕（和白天远景 background_view 一致）
	if Engine.is_editor_hint() or Settings.bg_level > 0:
		Glow.draw(self, c, r, Color(Palette.GOLD, a * 0.25))
	draw_rect(Rect2(c - Vector2(sz, sz) / 2.0, Vector2(sz, sz)), Color(Palette.GOLD, a))
