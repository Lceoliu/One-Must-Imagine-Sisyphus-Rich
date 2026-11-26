class_name TerrainTex
extends RefCounted
## 山体着色器（terrain.gdshader）的贴图：拼成三个 Texture2DArray 绑到山体材质上——
##   地表截面 top（assets/native/rock3/r3_top_<段>.png，5 层）、深处岩层 deep（r3_deep_<段>.png，5 层）：彩色，参考图画风，
##     tools/assets/rock_strip.py 做成可平铺（规格见 rock3/manifest.json）；某段还没有图时借 mid 段的。
##   饰带 band（assets/native/terrain2/t2_rays.png、t2_palmettes.png）。
## 换图不用改代码：放进目录、跑 import_sprites.py 和 --import 即可（周期 / 米数要和材质参数一致）。
## 处理：转 RGBA8 → 尺寸统一成该组第一张 → 重新生成 mipmap（远看不闪）。岩块、路沿是距离场（R、B 是距离，不能预乘 alpha）；
## 饰带是明暗图，预乘 alpha（纹样边缘远看不发白边）。

const DIR: String = "res://assets/native/terrain2/"
const ROCK_DIR: String = "res://assets/native/rock3/"
const TOP: PackedStringArray = ["r3_top_foot", "r3_top_low", "r3_top_mid", "r3_top_high", "r3_top_summit"]
const DEEP: PackedStringArray = ["r3_deep_foot", "r3_deep_low", "r3_deep_mid", "r3_deep_high", "r3_deep_summit"]
const BAND: PackedStringArray = ["t2_rays", "t2_palmettes"]
## 某段还没有图时借哪一张
const FALLBACK_TOP: String = "r3_top_mid"
const FALLBACK_DEEP: String = "r3_deep_mid"

## 拼好的数组按组缓存（同一进程里重开一局不再拼）
static var _cache: Dictionary = {}


## 把三组贴图设到材质上
static func bind(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	mat.set_shader_parameter(&"top_tex", array_of(TOP, Color(0.76, 0.55, 0.39, 1), false, FALLBACK_TOP))
	mat.set_shader_parameter(&"deep_tex", array_of(DEEP, Color(0.66, 0.45, 0.32, 1), false, FALLBACK_DEEP))
	mat.set_shader_parameter(&"band_tex", array_of(BAND, Color(1, 1, 1, 0), true))


## 这一张用的是哪个文件（空字符串 = 没有）
static func path_of(key: String) -> String:
	for d: String in [ROCK_DIR, DIR]:
		var p: String = d + key + ".png"
		if ResourceLoader.exists(p) or FileAccess.file_exists(p):
			return p
	return ""


static func array_of(keys: PackedStringArray, blank: Color, premultiply: bool = true, fallback: String = "") -> Texture2DArray:
	var ck: String = ",".join(keys)
	if _cache.has(ck):
		return _cache[ck]
	var imgs: Array[Image] = []
	var size: Vector2i = Vector2i.ZERO
	for k: String in keys:
		var img: Image = null
		var p: String = path_of(k)
		if p == "" and fallback != "":
			p = path_of(fallback)
		if p != "":
			var tex: Texture2D = load(p) as Texture2D
			if tex != null:
				img = tex.get_image()
			# 无头模式（测试）下导入的贴图读不回像素：直接读源 PNG
			if (img == null or img.is_empty()) and FileAccess.file_exists(p):
				img = Image.load_from_file(ProjectSettings.globalize_path(p))
		if img != null:
			if img.is_compressed():
				img.decompress()
			img.clear_mipmaps()
			img.convert(Image.FORMAT_RGBA8)
			if size == Vector2i.ZERO:
				size = img.get_size()
		imgs.append(img)
	if size == Vector2i.ZERO:
		size = Vector2i(4, 4)
	for i: int in imgs.size():
		var img: Image = imgs[i]
		if img == null:
			img = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
			img.fill(blank)
		elif img.get_size() != size:
			img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
		if premultiply:
			img.premultiply_alpha()
		img.generate_mipmaps()
		imgs[i] = img
	var arr: Texture2DArray = Texture2DArray.new()
	arr.create_from_images(imgs)
	_cache[ck] = arr
	return arr
