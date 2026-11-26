class_name Loc
## 本地化入口（architecture §16，docs/i18n/双语合并改动清单.md）。静态函数，sim 也能用（不是 autoload）。
## 源语言 zh_CN 直接写在原处（内容 JSON、场景、代码）；英文在 i18n/strings.csv（Godot CSV 翻译表，导入后注册到 TranslationServer）。
## 三类 key：内容 JSON "文件#指针"、场景 "场景路径#节点路径.属性"、代码 "文件名.语义名"。
## 当前是中文时什么都不查，直接返回源文；切到英文后查表，查不到退回源文（测试 tests/unit/i18n.gd 保证表是全的）。
## 语言只由 set_locale() 改（Settings 启动时、设置界面切换时调用）；测试、机器人不调它，所以永远是中文，和系统语言无关。

const SOURCE_LOCALE: String = "zh_CN"
## 设置界面里能选的语言（顺序 = 下拉框顺序）
const LOCALES: PackedStringArray = ["zh_CN", "en"]
const TABLE_PATH: String = "res://i18n/strings.en.translation"

static var _en: bool = false
static var _locale: String = SOURCE_LOCALE
## key → 英文（切到英文时从翻译表整份读进来）
static var _map: Dictionary = {}


## 切换语言。返回实际用的语言（不认识的退回中文）
static func set_locale(l: String) -> String:
	_locale = l if LOCALES.has(l) else SOURCE_LOCALE
	_en = not _locale.begins_with("zh")
	if _en and _map.is_empty():
		_load_map()
	TranslationServer.set_locale(_locale)
	return _locale


static func locale() -> String:
	return _locale


static func is_en() -> bool:
	return _en


## 系统语言 → 默认语言（第一次启动用）：中文系统用中文，其他用英文
static func default_for(os_language: String) -> String:
	return SOURCE_LOCALE if os_language.begins_with("zh") else "en"


static func _load_map() -> void:
	var tr: Translation = TranslationServer.get_translation_object("en")
	if tr == null or tr.get_locale() != "en":
		tr = load(TABLE_PATH) as Translation
	if tr == null:
		return
	for k: String in tr.get_message_list():
		_map[k] = String(tr.get_message(StringName(k)))


static func t(key: String, src: String) -> String:
	if not _en:
		return src
	return String(_map.get(key, src))


## 翻译后再套数字模板：Loc.tf("card.x.hi", "推速 +{v|pct}", {"v": 0.4})。
static func tf(key: String, src: String, args: Dictionary) -> String:
	return TextFmt.fmt(t(key, src), args)


## 英文表里有没有这个 key（场景文字逐级找 key 时用）
static func has(key: String) -> bool:
	return _en and _map.has(key)


## 英文表里这个 key 的英文（没有返回 ""）
static func en_of(key: String) -> String:
	return String(_map.get(key, ""))


## 内容 JSON：当前是英文时，把每个有译文的字符串叶子换成英文（key = "文件#指针"，指针和 tools/text/copy_export.py 的「位置」一致）。
## 中文时原样返回。dict / 数组就地修改。
static func localize_json(v: Variant, file: String) -> Variant:
	if not _en:
		return v
	return _loc_node(v, file + "#")


static func _loc_node(v: Variant, ptr: String) -> Variant:
	match typeof(v):
		TYPE_STRING:
			return _map.get(ptr, v)
		TYPE_DICTIONARY:
			var d: Dictionary = v
			for k: Variant in d.keys():
				var c: Variant = d[k]
				if typeof(c) == TYPE_STRING:
					d[k] = _map.get(ptr + "/" + str(k), c)
				elif typeof(c) == TYPE_DICTIONARY or typeof(c) == TYPE_ARRAY:
					_loc_node(c, ptr + "/" + str(k))
		TYPE_ARRAY:
			var a: Array = v
			for i: int in a.size():
				var c: Variant = a[i]
				if typeof(c) == TYPE_STRING:
					a[i] = _map.get(ptr + "/" + str(i), c)
				elif typeof(c) == TYPE_DICTIONARY or typeof(c) == TYPE_ARRAY:
					_loc_node(c, ptr + "/" + str(i))
	return v
