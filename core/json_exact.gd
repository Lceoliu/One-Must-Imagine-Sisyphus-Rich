class_name JsonExact
## 数字逐位精确的 JSON 读取。
## 原因（4.5.1 实测）：JSON.parse_string / String.to_float 遇到 13–17 位有效数字的数会差 1–数 ulp
## （网页 JSON.stringify 写出的 0.9500000000000001 被读成 0.95）。内容、golden、对拍数据都要与网页逐位相等，所以一律用本类读。
## 做法：结构仍交给 Godot 的 JSON（快）；另用正则按文本顺序取出全部数字记号，深度优先遍历解析结果（Dictionary 保留插入顺序，
## 遍历顺序 = 文本顺序），把长数字换成 Js.parse_num 的精确结果。数字一律是 float（与 JSON.parse_string 相同）。

static var _re: RegEx = null


## 解析 JSON 文本；失败时 push_error 并返回 null。
static func parse(text: String, where: String = "") -> Variant:
	var j: JSON = JSON.new()
	if j.parse(text) != OK:
		push_error("JSON 解析失败 %s 第 %d 行：%s" % [where, j.get_error_line(), j.get_error_message()])
		return null
	var data: Variant = j.data
	if _re == null:
		_re = RegEx.new()
		_re.compile("\"(?:[^\"\\\\]|\\\\.)*\"|-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?")
	var toks: PackedStringArray = []
	for m: RegExMatch in _re.search_all(text):
		var s: String = m.get_string()
		if not s.begins_with("\""):
			toks.append(s)
	var st: Array[int] = [0]
	var out: Variant = _fix(data, toks, st)
	if st[0] != toks.size():
		push_error("JsonExact：数字个数对不上（文本 %d / 结构 %d）%s" % [toks.size(), st[0], where])
		return data
	return out


## 读文件（res:// 或绝对路径）。
static func load_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("JsonExact：文件不存在 " + path)
		return null
	return parse(FileAccess.get_file_as_string(path), path)


static func _fix(v: Variant, toks: PackedStringArray, st: Array[int]) -> Variant:
	match typeof(v):
		TYPE_FLOAT, TYPE_INT:
			var i: int = st[0]
			st[0] = i + 1
			if i < toks.size() and (toks[i].length() >= 13 or toks[i].containsn("e")):
				return Js.parse_num(toks[i])
			return v
		TYPE_ARRAY:
			var a: Array = v
			for k: int in a.size():
				a[k] = _fix(a[k], toks, st)
			return a
		TYPE_DICTIONARY:
			var d: Dictionary = v
			for key: Variant in d.keys():
				d[key] = _fix(d[key], toks, st)
			return d
	return v
