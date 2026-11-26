class_name DefUtil
## 定义类 from_dict 共用的取值工具：类型不对或缺字段时把错误追加进 errors（不抛异常、不中断加载）。
## JSON 数字一律是 float，int 字段在这里显式 int()。


static func s(d: Dictionary, k: String, where: String, errors: PackedStringArray, required: bool = true, dflt: String = "") -> String:
	if not d.has(k):
		if required:
			errors.append("%s：缺少字段 %s" % [where, k])
		return dflt
	var v: Variant = d[k]
	if typeof(v) != TYPE_STRING:
		errors.append("%s：%s 应为字符串" % [where, k])
		return dflt
	return v


static func n(d: Dictionary, k: String, where: String, errors: PackedStringArray, required: bool = true, dflt: float = 0.0) -> float:
	if not d.has(k):
		if required:
			errors.append("%s：缺少字段 %s" % [where, k])
		return dflt
	var v: Variant = d[k]
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		errors.append("%s：%s 应为数字" % [where, k])
		return dflt
	return float(v)


static func i(d: Dictionary, k: String, where: String, errors: PackedStringArray, required: bool = true, dflt: int = 0) -> int:
	return int(n(d, k, where, errors, required, float(dflt)))


static func b(d: Dictionary, k: String, where: String, errors: PackedStringArray, dflt: bool = false) -> bool:
	if not d.has(k):
		return dflt
	var v: Variant = d[k]
	if typeof(v) != TYPE_BOOL:
		errors.append("%s：%s 应为布尔" % [where, k])
		return dflt
	return v


static func strs(d: Dictionary, k: String, where: String, errors: PackedStringArray, required: bool = true) -> PackedStringArray:
	var out: PackedStringArray = []
	if not d.has(k):
		if required:
			errors.append("%s：缺少字段 %s" % [where, k])
		return out
	var v: Variant = d[k]
	if not (v is Array):
		errors.append("%s：%s 应为字符串数组" % [where, k])
		return out
	for x: Variant in v:
		if typeof(x) != TYPE_STRING:
			errors.append("%s：%s 里有非字符串元素" % [where, k])
			continue
		out.append(x)
	return out


static func nums(d: Dictionary, k: String, where: String, errors: PackedStringArray, required: bool = true) -> PackedFloat64Array:
	var out: PackedFloat64Array = []
	if not d.has(k):
		if required:
			errors.append("%s：缺少字段 %s" % [where, k])
		return out
	var v: Variant = d[k]
	if not (v is Array):
		errors.append("%s：%s 应为数字数组" % [where, k])
		return out
	for x: Variant in v:
		if typeof(x) != TYPE_FLOAT and typeof(x) != TYPE_INT:
			errors.append("%s：%s 里有非数字元素" % [where, k])
			continue
		out.append(float(x))
	return out


static func dict(d: Dictionary, k: String, where: String, errors: PackedStringArray, required: bool = false) -> Dictionary:
	if not d.has(k):
		if required:
			errors.append("%s：缺少字段 %s" % [where, k])
		return {}
	var v: Variant = d[k]
	if not (v is Dictionary):
		errors.append("%s：%s 应为对象" % [where, k])
		return {}
	return v


## 检查对象里没有未知字段（防止拼错键名后被静默忽略）。note 字段一律允许。
static func known(d: Dictionary, keys: PackedStringArray, where: String, errors: PackedStringArray) -> void:
	for k: Variant in d.keys():
		if k == "note":
			continue
		if not keys.has(str(k)):
			errors.append("%s：未知字段 %s（允许：%s）" % [where, k, ", ".join(keys)])
