class_name AssetWarmer
extends RefCounted
## 后台预热（2026-10-16）：把"之后才会用到"的资源趁菜单和白天空闲提前读好，不等到用的那一帧在主线程同步读。
## 实测（导出版 --verbose）：第一晚碾城时要临时读近百个音效、几十张碎屑贴图；进夜宴时要读西西弗斯五十多张法线图。
## 一次只在后台读一个（load_threaded_request 不开子线程：兼容渲染器下多个线程同时建贴图会崩，见 HubView.preload_scene），
## 读完收下引用再读下一个。贴图传显卡在主线程、在它读完的那一帧做；一次一个 → 每帧最多传一张，不会连卡。
## main 每帧调 step()；谁需要就 enqueue()（先排的先读），急用的 enqueue_front()。读好的资源一直留着引用（这些东西每局都会用到）。
## **游戏里所有后台读取都走这一条队列**（SpriteDB 的图集页、夜宴场景和依赖、warm.json），不要另发 load_threaded_request：
## 两个后台读取同时在建贴图，就是 2026-10-16 导出版偶发崩溃那种情况。
## 清单：content/art/warm.json（tools/assets/record_warm.py 跑一局录下来的"游戏中途同步读过的资源"）+ 夜宴的依赖（HubView）。

const MANIFEST: String = "res://content/art/warm.json"

static var _queue: PackedStringArray = []
static var _qi: int = 0
static var _known: Dictionary = {}
static var _busy: String = ""
static var _refs: Array[Resource] = []
## 关掉 = step() 什么都不做（无头测试、录像工具）
static var enabled: bool = true


## 排进队尾（已经排过 / 读过的跳过）
static func enqueue(paths: PackedStringArray) -> void:
	for p: String in paths:
		if p == "" or _known.has(p):
			continue
		_known[p] = true
		_queue.append(p)


## 插到队首（还没读到的；已经排着但没轮到的也提到前面）：急用的先读（图集页、快要进夜宴时的夜宴场景）
static func enqueue_front(paths: PackedStringArray) -> void:
	var first: PackedStringArray = []
	var moved: Dictionary = {}
	for p: String in paths:
		if p == "" or moved.has(p):
			continue
		if _known.has(p):
			var at: int = _queue.find(p, _qi)
			if at < 0:
				continue    # 已经读过 / 正在读
			_queue.remove_at(at)
		_known[p] = true
		moved[p] = true
		first.append(p)
	if first.is_empty():
		return
	var rest: PackedStringArray = _queue.slice(_qi)
	_queue = _queue.slice(0, _qi)
	_queue.append_array(first)
	_queue.append_array(rest)


## 读 warm.json 的若干组（按给的顺序排队）
static func enqueue_manifest(groups: PackedStringArray) -> void:
	if not FileAccess.file_exists(MANIFEST):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not (d is Dictionary):
		return
	for g: String in groups:
		var lst: PackedStringArray = []
		for p: Variant in (d as Dictionary).get(g, []):
			lst.append(str(p))
		enqueue(lst)


## 每帧一次：上一个读完了就收下，再发下一个请求
static func step() -> void:
	if not enabled:
		return
	var _pt: int = Prof.t()
	var was: String = _busy
	_step()
	if Prof.on:
		Prof.add(&"warm.step", _pt)
		var ms: float = (Time.get_ticks_usec() - _pt) / 1000.0
		if ms > 20.0:
			print("[warm] 慢的一步 %.0f ms：%s → %s" % [ms, was, _busy])


static func _step() -> void:
	if _busy != "":
		var st: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(_busy)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			var r: Resource = ResourceLoader.load_threaded_get(_busy)
			if r != null:
				_refs.append(r)
		_busy = ""
	while _qi < _queue.size():
		var p: String = _queue[_qi]
		_qi += 1
		if ResourceLoader.has_cached(p):
			# 已经在缓存里（别人正用着）：也收一份引用，免得那边释放后又要重读
			_refs.append(ResourceLoader.load(p))
			continue
		if not ResourceLoader.exists(p):
			continue
		if ResourceLoader.load_threaded_request(p, "", false) == OK:
			_busy = p
			return


## 队列读空了（没有在读的、也没有排着的）
static func idle() -> bool:
	return _busy == "" and _qi >= _queue.size()


## 某个路径是否已经读好（排过队且已经轮过去）
static func has_warmed(p: String) -> bool:
	return _known.has(p) and ResourceLoader.has_cached(p)


## 退出时放掉全部引用（main._exit_tree）
static func clear() -> void:
	if _busy != "" and ResourceLoader.load_threaded_get_status(_busy) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_get(_busy)
	_busy = ""
	_refs.clear()
	_queue = PackedStringArray()
	_qi = 0
	_known.clear()


## 测试用：[已处理, 总数]
static func progress() -> Vector2i:
	return Vector2i(_qi, _queue.size())


## 一个场景 / 资源的全部依赖（深度优先，子场景 / 材质 / 动画帧里的贴图排在它们前面；脚本不用预热）
static func collect_deps(path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	_collect(path, {}, out)
	return out


static func _collect(path: String, seen: Dictionary, out: PackedStringArray) -> void:
	for d: String in ResourceLoader.get_dependencies(path):
		var p: String = dep_path(d)
		if p == "" or seen.has(p) or p.ends_with(".gd"):
			continue
		seen[p] = true
		if p.ends_with(".tscn") or p.ends_with(".tres") or p.ends_with(".scn") or p.ends_with(".res"):
			_collect(p, seen, out)
		out.append(p)


## get_dependencies 的一条："res://…"，或导出版的 "uid://…::类型::res://…"
static func dep_path(d: String) -> String:
	for s: String in d.split("::", false):
		if s.begins_with("res://"):
			return s
	var u: String = d.get_slice("::", 0)
	if u.begins_with("uid://"):
		var id: int = ResourceUID.text_to_id(u)
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
	return ""
