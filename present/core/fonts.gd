class_name Fonts
extends RefCounted
## 三种字体角色（architecture §15）：SERIF 正文（Noto Serif SC）、CINZEL 数字与拉丁标题、GREEK 希腊字母（GFS Didot）。
## 字体文件在 res://assets/fonts/（OFL）；缺文件时回退到系统字体。可变字体用 FontVariation 选字重，结果按字重缓存。
## 每个字重的 FontVariation 存成 res://present/ui/fonts/<serif|cinzel>_<字重>.tres（greek.tres），场景直接引用同一份资源；
## 没有 .tres 的字重现建一个（不存盘）。

const SERIF_FILE: String = "res://assets/fonts/NotoSerifSC-VariableFont_wght.ttf"
const CINZEL_FILE: String = "res://assets/fonts/Cinzel-VariableFont_wght.ttf"
const GREEK_FILE: String = "res://assets/fonts/GFSDidot-Regular.ttf"

static var _cache: Dictionary = {}


static func _base(path: String, fallback: PackedStringArray) -> Font:
	var key: String = "base|" + path
	if _cache.has(key):
		return _cache[key]
	var f: Font = null
	if ResourceLoader.exists(path):
		f = load(path) as Font
	if f == null:
		var sf: SystemFont = SystemFont.new()
		sf.font_names = fallback
		f = sf
	_cache[key] = f
	return f


const RES_DIR: String = "res://present/ui/fonts/"


## 字重资源的路径（serif_600.tres 之类）
static func res_path(family: String, weight: int) -> String:
	return "%s%s_%d.tres" % [RES_DIR, family, weight]


static func _weighted(family: String, path: String, fallback: PackedStringArray, weight: int, fallbacks: Array[Font]) -> Font:
	var key: String = "%s|%d" % [path, weight]
	if _cache.has(key):
		return _cache[key]
	var rp: String = res_path(family, weight)
	if ResourceLoader.exists(rp):
		var loaded: Font = load(rp) as Font
		if loaded != null:
			_cache[key] = loaded
			return loaded
	var fv: FontVariation = FontVariation.new()
	fv.base_font = _base(path, fallback)
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	if not fallbacks.is_empty():
		fv.fallbacks = fallbacks
	_cache[key] = fv
	return fv


## 正文（中文）。weight 400–900
static func serif(weight: int = 600) -> Font:
	return _weighted("serif", SERIF_FILE, ["Noto Serif SC", "Source Han Serif SC", "SimSun", "Microsoft YaHei"], weight, [])


## 数字、拉丁标题（缺字回退到正文）
static func cinzel(weight: int = 700) -> Font:
	return _weighted("cinzel", CINZEL_FILE, ["Cinzel", "Times New Roman"], weight, [serif(weight)])


## 希腊字母
static func greek() -> Font:
	var key: String = "greek"
	if _cache.has(key):
		return _cache[key]
	if ResourceLoader.exists(RES_DIR + "greek.tres"):
		var loaded: Font = load(RES_DIR + "greek.tres") as Font
		if loaded != null:
			_cache[key] = loaded
			return loaded
	var fv: FontVariation = FontVariation.new()
	fv.base_font = _base(GREEK_FILE, ["GFS Didot", "Times New Roman"])
	fv.fallbacks = [cinzel(700)]
	_cache[key] = fv
	return fv
