class_name GalleryScreen
extends Control
## 结局画廊（= 网页 ui.js showGallery，布局在 gallery_screen.tscn）：已见结局可以重看；没见过的写"？？？"。

signal replay(id: StringName)
signal back_pressed

## 不是 const：文字要按当前语言取（Loc.t），所以每次建界面时现算
var KIND_LABEL: Dictionary = {&"normal": Loc.t("gallery_screen.ending", "结局"), &"true": Loc.t("gallery_screen.true_ending", "真结局"), &"fake": Loc.t("gallery_screen.ending", "结局"), &"normal-bad": Loc.t("gallery_screen.ending_overdue", "结局 · 逾期")}

const SCENE: String = "res://present/ui/gallery_screen.tscn"

var content: ContentDB
var meta: Dictionary = {}


static func create() -> GalleryScreen:
	return SceneCache.make(SCENE) as GalleryScreen


func _ready() -> void:
	var seen: Dictionary = meta.get("endings", {})
	var n_seen: int = 0
	for e: StoryDefs.Ending in content.endings_on():
		if seen.has(String(e.id)):
			n_seen += 1
	(%Count as Label).text = Loc.t("gallery_screen.seen_each_vase_depicts", "已见 %d / %d · 每只陶瓶上画着一个结局") % [n_seen, content.endings_on().size()]
	var grid: GridContainer = %Grid
	for c: Node in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	for e: StoryDefs.Ending in content.endings_on():
		var s: Dictionary = seen.get(String(e.id), {})
		var pc: PanelContainer = PanelContainer.new()
		pc.custom_minimum_size = Vector2(300, 130)
		var col: Color = UiKit.GOLD_HI if e.kind == &"true" else (UiKit.GOLD if not s.is_empty() else Color(UiKit.MUTED, 0.4))
		pc.add_theme_stylebox_override("panel", UiKit.box(UiKit.INK, col, 2, 8, 12))
		var v: VBoxContainer = VBoxContainer.new()
		pc.add_child(v)
		v.add_child(UiKit.label(str(KIND_LABEL.get(e.kind, "")), 13, UiKit.MUTED, 600))
		v.add_child(UiKit.label(e.text("name") if not s.is_empty() else Loc.t("gallery_screen.locked", "？？？"), 22, UiKit.CREAM, 800))
		v.add_child(UiKit.label((Loc.t("gallery_screen.first_seen_generation_times", "第 %d 代初见 · 见过 %d 次") % [int(s.get("first", 1)), int(s.get("n", 1))]) if not s.is_empty() else Loc.t("gallery_screen.not_yet_seen", "尚未见过"), 13, UiKit.MUTED, 500))
		if not s.is_empty():
			var b: Button = UiKit.button(Loc.t("gallery_screen.replay", "重看"), false, 15)
			var id: StringName = e.id
			b.pressed.connect(func() -> void: replay.emit(id))
			v.add_child(b)
		grid.add_child(pc)
	var st: Array = meta.get("steles", [])
	(%Summary as Label).text = (Loc.t("gallery_screen.ancestral_steles_fastest_summit", "先祖石碑 %d 座 · 最快 %s 天登顶") % [st.size(), str(meta.get("best_day", 0)) if int(meta.get("best_day", 0)) > 0 else "—"]) if not st.is_empty() else ""
	(%Back as Button).pressed.connect(func() -> void: back_pressed.emit())


func _unhandled_input(ev: InputEvent) -> void:
	var k: InputEventKey = ev as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		back_pressed.emit()
