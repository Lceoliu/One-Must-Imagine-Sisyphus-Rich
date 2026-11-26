class_name SceneCache
extends RefCounted
## 界面场景（工资条、对话框、闲聊气泡、商店、菜单……）的 PackedScene 第一次读进来后一直留着：
## 以前每个 create() 都 load(SCENE)，用完没人拿着引用就被释放，下次打开又从硬盘读一遍（2026-10-16 实测一晚夜宴读了五十多次）。

static var _scenes: Dictionary = {}


static func clear() -> void:
	_scenes.clear()


static func make(path: String) -> Node:
	var ps: PackedScene = _scenes.get(path) as PackedScene
	if ps == null:
		ps = load(path) as PackedScene
		_scenes[path] = ps
	return ps.instantiate()
