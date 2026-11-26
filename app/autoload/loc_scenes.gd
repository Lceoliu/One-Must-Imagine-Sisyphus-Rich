extends Node
## autoload `LocScenes`：场景（.tscn）里直接写的中文，在英文下换成翻译表里的英文（docs/i18n/双语合并改动清单.md）。
## 场景里的中文一律不改，编辑器里看到的还是中文；key = "场景路径#节点路径.属性"
## （和 tools/i18n/i18n_common.py 的 scan_tscn 同一套拼法），节点进场景树时查一次。
## 外层场景对实例子节点的覆盖优先：先用最外层场景算 key，再往里，最后是节点自己所在的场景。
## 切语言时（Settings.locale_changed）把整棵树重新过一遍：换成英文时把中文记在 meta 里，切回中文时还原。
## 代码里后来改过的文字（和当初换上去的英文不一样了）不动，由代码自己按新语言重设。

const PROPS: PackedStringArray = ["text", "tooltip_text", "placeholder_text", "display_name", "verb", "title", "subtitle"]


func _ready() -> void:
	get_tree().node_added.connect(func(n: Node) -> void: localize(n))
	var s: Node = get_node_or_null(^"/root/Settings")
	if s != null:
		s.connect(&"locale_changed", func() -> void: localize_tree(get_tree().root))


## 一个节点：按当前语言换场景里写的文字
static func localize(n: Node) -> void:
	if n.owner == null and n.scene_file_path == "":
		return
	var en: bool = Loc.is_en()
	for prop: String in PROPS:
		var zk: StringName = StringName("_loc_zh_" + prop)
		var ek: StringName = StringName("_loc_en_" + prop)
		if not en and not n.has_meta(zk):
			continue
		if not (prop in n):
			continue
		var v: Variant = n.get(prop)
		if typeof(v) != TYPE_STRING:
			continue
		var cur: String = v
		if not en:
			# 切回中文：只还原我们换上去、之后代码没改过的
			if cur == String(n.get_meta(ek, "")):
				n.set(prop, n.get_meta(zk))
			n.remove_meta(zk)
			n.remove_meta(ek)
			continue
		var zh: String = cur
		if n.has_meta(zk):
			if cur != String(n.get_meta(ek, "")) and cur != String(n.get_meta(zk)):
				continue
			zh = String(n.get_meta(zk))
		if not _has_cjk(zh):
			continue
		for key: String in keys_for(n, prop):
			if Loc.has(key):
				var e: String = Loc.en_of(key)
				n.set_meta(zk, zh)
				n.set_meta(ek, e)
				n.set(prop, e)
				break


## 整棵树
static func localize_tree(root: Node) -> void:
	localize(root)
	for c: Node in root.get_children(true):
		localize_tree(c)


## 这个节点这个属性可能的 key（外层场景在前）
static func keys_for(n: Node, prop: String) -> PackedStringArray:
	var owners: Array[Node] = []
	var o: Node = n.owner
	while o != null:
		owners.push_front(o)
		o = o.owner
	var out: PackedStringArray = []
	for ow: Node in owners:
		if ow.scene_file_path != "":
			out.append("%s#%s.%s" % [ow.scene_file_path.trim_prefix("res://"), String(ow.get_path_to(n)), prop])
	if n.scene_file_path != "":
		out.append("%s#..%s" % [n.scene_file_path.trim_prefix("res://"), prop])
	return out


static func _has_cjk(s: String) -> bool:
	for i: int in s.length():
		var c: int = s.unicode_at(i)
		if c >= 0x3000 and c <= 0x9fff or c >= 0xff00 and c <= 0xffef:
			return true
	return false
