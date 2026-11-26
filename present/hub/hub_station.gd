@tool
class_name HubStation
extends Marker2D
## 夜宴里的一个站点（站在它 ± range 之内按交互键）：交谈 / 买卖 / 天亮。
## 台词和说话人在 content/hub/hub.json（talk / speakers），这里只管位置和这个站点干什么。
## 编辑器里画出触发范围和提示框的位置。

## 站点 id（台词按它找：talk.<id>，找不到再按 who 找）
@export var id: String = ""
## 说话人（hub.json speakers 的 key）；空 = 旁白
@export var who: String = ""
## talk：交谈；shop：打开这几支天赋的摊；bet：提喀的高度盘（第 3 天起，之前只交谈）；exit：确认天亮
@export_enum("talk", "shop", "exit", "bet") var action: String = "talk"
## shop 卖哪几支天赋（branches.json 的 id）
@export var branches: PackedStringArray = []
## shop 摊在摇到第一个命运之前只能交谈（命运三女神：先告诉你她们收什么钱）
@export var until_moira: bool = false
## shop 摊的标题 / 副标题
@export var title: String = ""
@export_multiline var subtitle: String = ""
## 提示框上的动词（"E 买卖 · 阿瑞斯"）；空 = 交谈（hub_view 按当前语言补）
@export var verb: String = ""
## 显示名（空 = 用说话人的名字）
@export var display_name: String = ""
## 触发范围（像素，左右各这么宽）
@export var trigger_range: float = 120.0:
	set(v):
		trigger_range = v
		queue_redraw()
## 提示框离地面多高（像素）
@export var prompt_height: float = 430.0:
	set(v):
		prompt_height = v
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var c: Color = Color(1.0, 0.8, 0.3) if action == "shop" or action == "bet" else (Color(1.0, 0.55, 0.3) if action == "exit" else Color(0.6, 0.85, 1.0))
	draw_rect(Rect2(-trigger_range, -12.0, trigger_range * 2.0, 12.0), Color(c, 0.35))
	draw_line(Vector2(0, 0), Vector2(0, -prompt_height), Color(c, 0.6), 1.5)
	draw_rect(Rect2(-90, -prompt_height - 34.0, 180, 34), Color(c, 0.25))
	draw_rect(Rect2(-90, -prompt_height - 34.0, 180, 34), Color(c, 0.9), false, 2.0)
	var f: Font = ThemeDB.fallback_font
	var label: String = "%s · %s" % [verb if verb != "" else "交谈", display_name if display_name != "" else (who if who != "" else id)]  # i18n: skip（编辑器里画的辅助标签）
	draw_string(f, Vector2(-84, -prompt_height - 11.0), label, HORIZONTAL_ALIGNMENT_LEFT, 168, 15, Color(c, 1.0))
