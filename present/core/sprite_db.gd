extends Node
## autoload `SpriteDB`（architecture §3.2、K11）：精灵清单与纹理的惰性加载。
## - 清单 = res://content/art/sprites.json（tools/assets/import_sprites.py 读 PNG 文件头生成，勿手改）：key → {path, w, h[, repeat]}。
## - aspect()/size() 只读清单，从不加载纹理（布局与平衡只依赖它，sim 侧由 ContentDB 读同一份 JSON）。
## - tex() 第一次用到时才 load；找不到的 key 或加载失败返回 null，同一个 key 只警告一次（= assets.js 的容错：缺图走占位绘制）。
## - 启动时在后台线程预加载物件图集的几页：否则夜里碾进城、第一次见到某种建筑时同步加载，整帧卡 300 毫秒（2026-10-15 实测）。
##   全部 719 张一起预加载要 500 MB 以上显存，不做。
## - 无头运行时默认不加载纹理（tex() 返回 null），测试可把 load_textures 设回 true。
## - 物件图集（2026-10-15）：山坡和城里的物件、金币合成几张 4096 的图集（tools/assets/pack_atlas.py → assets/atlas/、content/art/atlas.json），
##   tex() 对这些 key 返回 AtlasTexture（同一页的物件能合成一批绘制，碾城时少几百次绘制调用）；调用方不用改。
##   按单张贴图 0–1 坐标做效果的着色器（depth_sprite：前景、远山装饰）要用 tex_plain() 取单图。

const MANIFEST: String = "res://content/art/sprites.json"
## 换画（重画旧素材但不动平衡）：key → 新图的 key（都在 sprites.json 里）。aspect()/size() 仍读原 key（宽高比是平衡输入），
## 只有 tex() 返回新图。新图必须和原图同宽高比（tools/assets/art_override.py 会补透明边对齐，底边不动）。
const OVERRIDES: String = "res://content/art/overrides.json"

## 是否真的加载纹理（无头时默认关）
var load_textures: bool = true

var _entries: Dictionary = {}          # key → {path, w, h, repeat?}
var _over: Dictionary = {}             # key → 换画后的 key
var _loaded: bool = false
var _tex: Dictionary = {}              # key → Texture2D（成功加载的缓存）
var _warned: Dictionary = {}           # key → true（已警告过）
const OBJECTS: String = "res://content/world/objects.json"
const ATLAS: String = "res://content/art/atlas.json"
var _atlas: Dictionary = {}            # key → [页, x, y, w, h]
var _atlas_pages: PackedStringArray = []
var _plain: Dictionary = {}            # tex_plain() 的单图缓存
var _feet: Dictionary = {}             # key → [左, 右, 底部透明边]（atlas.json 的 foot，离线算好）
var _masks: Dictionary = {}            # key → base64 的 48×48 不透明遮罩（atlas.json 的 mask）
var _mask_img: Dictionary = {}         # key → 解开后的 Image
var _mask_n: int = 48


func _ready() -> void:
	Prof.mark("SpriteDB 开始")
	load_textures = DisplayServer.get_name() != "headless"
	set_process(false)
	if load_textures:
		preload_world_objects()
	Prof.mark("SpriteDB 完成")


## 后台预加载山坡和城里会被碾碎的物件贴图：有图集就只加载图集那几页；没有图集时逐张（id、id_xxx 变体、换画后的图）。
## 都排进 AssetWarmer（一次只在后台读一个：兼容渲染器下多个线程同时建贴图会崩，见 HubView.preload_scene），排在最前面
func preload_world_objects() -> void:
	_ensure_manifest()
	if not _atlas_pages.is_empty():
		AssetWarmer.enqueue_front(_atlas_pages)
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(OBJECTS))
	if not (data is Array):
		return
	_ensure_manifest()
	var ids: Dictionary = {}
	for o: Variant in data:
		if o is Dictionary and (o as Dictionary).has("id"):
			ids[str(o["id"])] = true
	var keys: PackedStringArray = []
	for k: String in _entries:
		var base: String = k
		var cut: int = k.rfind("_")
		if not ids.has(base) and cut > 0:
			base = k.substr(0, cut)
		if ids.has(k) or ids.has(base):
			keys.append(k)
			if _over.has(k):
				keys.append(str(_over[k]))
	preload_keys(keys)


## 这些 key 的贴图排进 AssetWarmer 后台预加载（读好后留在资源缓存里，tex() 第一次取时直接拿到）
func preload_keys(keys: PackedStringArray) -> void:
	if not load_textures:
		return
	_ensure_manifest()
	var paths: PackedStringArray = []
	for k: String in keys:
		if _tex.has(k) or not _entries.has(k):
			continue
		paths.append(str((_entries[k] as Dictionary)["path"]))
	AssetWarmer.enqueue_front(paths)


## 清单里有没有这个 key。
func has(key: StringName) -> bool:
	_ensure_manifest()
	return _entries.has(String(key))


## 全部 key（清单顺序）。
func keys() -> PackedStringArray:
	_ensure_manifest()
	return PackedStringArray(_entries.keys())


## 宽高比 w/h（= assets.js aspect()：没有这张图时返回 1）。只读清单。
## 贴图里不透明像素的包围盒（贴图像素坐标；读不到像素或是压缩格式时为空 Rect2i，调用方退回整张图）。按资源路径缓存一局：
## 导出版里 get_image() 要把整张图连同 mipmap 从显卡读回来（glGetTexImage，几到几十毫秒、渲染管线还得停下来等；
## 编辑器里有 CPU 端缓存所以量不出来）。夜宴的前景淡出、侍者遮挡每晚都要用，以前每晚都读一遍。
static var _used_px: Dictionary = {}


static func used_px(tex: Texture2D) -> Rect2i:
	if tex == null:
		return Rect2i()
	var key: String = tex.resource_path
	if key != "" and _used_px.has(key):
		return _used_px[key]
	var img: Image = tex.get_image()
	var u: Rect2i = Rect2i()
	if img != null and not img.is_empty() and not img.is_compressed():
		u = img.get_used_rect()
	if key != "":
		_used_px[key] = u
	return u


func aspect(key: StringName) -> float:
	var e: Dictionary = _entry(key)
	if e.is_empty():
		return 1.0
	return float(e["w"]) / float(e["h"])


## 原图像素尺寸；没有这张图时返回 (0, 0)。
func size(key: StringName) -> Vector2i:
	var e: Dictionary = _entry(key)
	if e.is_empty():
		return Vector2i.ZERO
	return Vector2i(int(e["w"]), int(e["h"]))


## res:// 路径；没有这张图时返回空串。
func path(key: StringName) -> String:
	var e: Dictionary = _entry(key)
	return "" if e.is_empty() else str(e["path"])


## 这张图建议的平铺方式（背景条带是 MIRROR；Godot 4 的平铺属于 CanvasItem.texture_repeat，不在导入设置里）。
func texture_repeat(key: StringName) -> CanvasItem.TextureRepeat:
	var e: Dictionary = _entry(key)
	if not e.is_empty() and str(e.get("repeat", "")) == "mirror":
		return CanvasItem.TEXTURE_REPEAT_MIRROR
	return CanvasItem.TEXTURE_REPEAT_PARENT_NODE


## 纹理（惰性加载）。找不到 key、加载失败或无头模式返回 null。在物件图集里的 key 返回 AtlasTexture（见文件头）。
func tex(key: StringName) -> Texture2D:
	_ensure_manifest()
	var k: String = String(key)
	if _over.has(k) and _entries.has(str(_over[k])):
		k = str(_over[k])
	if _tex.has(k):
		return _tex[k]
	if not load_textures:
		return null
	if _atlas.has(k):
		var at: Texture2D = _atlas_tex(k)
		if at != null:
			_tex[k] = at
			return at
	return _load_plain(k)


## 单张原图（不走图集）：按单张贴图 0–1 坐标做效果的着色器用（depth_sprite：前景、远山装饰）
func tex_plain(key: StringName) -> Texture2D:
	_ensure_manifest()
	var k: String = String(key)
	if _over.has(k) and _entries.has(str(_over[k])):
		k = str(_over[k])
	if not _atlas.has(k):
		return tex(StringName(k))
	if _plain.has(k):
		return _plain[k]
	if not load_textures:
		return null
	var t: Texture2D = _load_plain(k, false)
	if t != null:
		_plain[k] = t
	return t


## 图集物件的"脚"（离线算好，见 pack_atlas.py）：Vector3(左, 右, 底部透明边)，不在图集里返回 null（调用方自己读像素）
func foot_of(key: StringName) -> Variant:
	var k: String = _resolve(key)
	if not _feet.has(k):
		return null
	var f: Array = _feet[k]
	return Vector3(float(f[0]), float(f[1]), float(f[2]))


## 图集物件的 48×48 不透明遮罩（离线算好）：LA8 图，get_pixel().a 就是不透明与否；不在图集里返回 null
func mask_of(key: StringName) -> Image:
	var k: String = _resolve(key)
	if _mask_img.has(k):
		return _mask_img[k]
	if not _masks.has(k):
		return null
	var bits: PackedByteArray = Marshalls.base64_to_raw(str(_masks[k]))
	var n: int = _mask_n
	var data: PackedByteArray = []
	data.resize(n * n * 2)
	for i: int in n * n:
		var on: bool = (bits[i >> 3] >> (7 - (i & 7))) & 1 == 1
		data[i * 2] = 255
		data[i * 2 + 1] = 255 if on else 0
	var img: Image = Image.create_from_data(n, n, false, Image.FORMAT_LA8, data)
	_mask_img[k] = img
	return img


## 换画后的 key
func _resolve(key: StringName) -> String:
	_ensure_manifest()
	var k: String = String(key)
	if _over.has(k) and _entries.has(str(_over[k])):
		k = str(_over[k])
	return k


## 图集里的一块
func _atlas_tex(k: String) -> Texture2D:
	var e: Array = _atlas[k]
	var page_i: int = int(e[0])
	if page_i < 0 or page_i >= _atlas_pages.size():
		return null
	var page: Texture2D = ResourceLoader.load(_atlas_pages[page_i]) as Texture2D
	if page == null:
		_warn_once(k, "图集页加载失败：%s" % _atlas_pages[page_i])
		return null
	var at: AtlasTexture = AtlasTexture.new()
	at.atlas = page
	at.region = Rect2(float(e[1]), float(e[2]), float(e[3]), float(e[4]))
	return at


## 从清单路径加载单张图；cache = 是否放进 tex() 的缓存
func _load_plain(k: String, cache: bool = true) -> Texture2D:
	var e: Dictionary = _entry(StringName(k))
	if e.is_empty():
		return null
	var p: String = str(e["path"])
	var res: Resource = null
	if ResourceLoader.exists(p):
		res = ResourceLoader.load(p)
	var t: Texture2D = res as Texture2D
	if t == null:
		_warn_once(k, "纹理加载失败：%s" % p)
		return null
	if cache:
		_tex[k] = t
	return t


## 已经警告过的 key（调试面板和测试用）。
func warned_keys() -> PackedStringArray:
	return PackedStringArray(_warned.keys())


## 测试用：丢掉缓存和"已警告"记录，下次重新读清单。
func reset() -> void:
	_entries.clear()
	_over.clear()
	_tex.clear()
	_warned.clear()
	_atlas.clear()
	_atlas_pages = PackedStringArray()
	_feet.clear()
	_masks.clear()
	_mask_img.clear()
	_plain.clear()
	_loaded = false


func _entry(key: StringName) -> Dictionary:
	_ensure_manifest()
	var k: String = String(key)
	if not _entries.has(k):
		_warn_once(k, "清单里没有精灵 %s（走占位绘制）" % k)
		return {}
	return _entries[k]


func _warn_once(k: String, msg: String) -> void:
	if _warned.has(k):
		return
	_warned[k] = true
	push_warning("[SpriteDB] " + msg)


func _ensure_manifest() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(MANIFEST):
		push_warning("[SpriteDB] 缺少 %s，全部精灵走占位绘制（先跑 python tools/assets/import_sprites.py）" % MANIFEST)
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[SpriteDB] %s 不是 JSON 对象" % MANIFEST)
		return
	_entries = data
	if FileAccess.file_exists(ATLAS):
		var at: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATLAS))
		if at is Dictionary:
			_atlas = ((at as Dictionary).get("sprites", {}) as Dictionary).duplicate()
			_atlas_pages = PackedStringArray((at as Dictionary).get("pages", []))
			_feet = ((at as Dictionary).get("foot", {}) as Dictionary).duplicate()
			_masks = ((at as Dictionary).get("mask", {}) as Dictionary).duplicate()
			_mask_n = int((at as Dictionary).get("mask_size", 48))
	if FileAccess.file_exists(OVERRIDES):
		var ov: Variant = JSON.parse_string(FileAccess.get_file_as_string(OVERRIDES))
		if ov is Dictionary:
			for kk: Variant in (ov as Dictionary):
				if not str(kk).begins_with("_"):
					_over[str(kk)] = str((ov as Dictionary)[kk])


## 换画表里这个 key 换成了哪张图（没换返回原 key）
func art_key(key: StringName) -> StringName:
	_ensure_manifest()
	return StringName(_over.get(String(key), String(key)))
