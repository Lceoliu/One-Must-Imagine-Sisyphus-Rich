class_name PickCard
extends PanelContainer
## 三选一的一张卡（布局在 pick_card.tscn）：顶行（序号 / 神像 / 谁 · 阶）、卡名、主效果、副效果、怨气、说明、俏皮话；
## 盖着的卡（blind）画卡背（瓶画圆章）。PickPanel 用 setup() 填内容。
## 卡面是瓶画边框（VaseFrame：回纹带、棕榈叶角花，青铜 / 白银 / 黄金 / 神话四档各一张），在 _draw 里按九宫格画在内容后面。

const SCENE: String = "res://present/ui/pick_card.tscn"


static func create() -> PickCard:
	return SceneCache.make(SCENE) as PickCard


## 边框画多大：贴图边距 × FRAME_K（屏幕像素）；内容离卡边的距离
const FRAME_K: float = 0.38
const PAD: Vector4 = Vector4(38, 48, 38, 44)

var _tier: int = 0
var _blind: bool = false
## 贴图在 setup 里先加载好（在 _draw 里才 load 的贴图第一帧还没传到显卡，会画成一块白）
var _frame_tex: Texture2D = null
var _back_tex: Texture2D = null


func setup(face: Dictionary, i: int) -> void:
	var tier: int = int(face.get("tier", 0))
	var col: Color = Palette.TIER_COLORS[clampi(tier, 0, 3)]
	var sb: StyleBoxEmpty = StyleBoxEmpty.new()
	sb.content_margin_left = PAD.x
	sb.content_margin_top = PAD.y
	sb.content_margin_right = PAD.z
	sb.content_margin_bottom = PAD.w
	add_theme_stylebox_override("panel", sb)
	_tier = tier
	var blind: bool = bool(face.get("blind", false))
	_blind = blind
	_frame_tex = VaseFrame.tier_tex(tier)
	_back_tex = load(VaseFrame.BACK) as Texture2D if blind else null
	queue_redraw()
	(%VB as Control).visible = not blind
	(%Blind as Control).visible = blind
	if blind:
		# 卡背本身就是图（瓶画圆章），不再叠问号和说明文字
		(%Blind as Control).visible = false
		return
	var key: Label = %Key
	key.text = str(i + 1)
	key.add_theme_color_override("font_color", col)
	_medal(%Medal, String(face.get("medal", "")))
	_medal(%Medal2, String(face.get("medal2", "")))
	(%WhoName as Label).text = String(face.get("who", ""))
	var meta: Label = %Meta
	meta.text = " · ".join(PackedStringArray(face.get("meta", [])))
	meta.add_theme_color_override("font_color", col)
	(%Name as Label).text = String(face.get("name", ""))
	(%Hi as Label).text = String(face.get("hi", ""))
	(%Lo as Label).text = String(face.get("lo", ""))
	var costs: VBoxContainer = %Costs
	for c: Node in costs.get_children():
		costs.remove_child(c)
		c.queue_free()
	var cost_lines: Array = face.get("cost_lines", [])
	(%CostHead as Control).visible = not cost_lines.is_empty()
	for cl: Dictionary in cost_lines:
		var up: bool = bool(cl.get("up", false))
		var has_god: bool = String(cl.get("god", "")) != ""
		var c_lbl: Label = UiKit.label(String(cl.get("text", "")), 15, UiKit.TERRA if up else (UiKit.GOLD if has_god else UiKit.MUTED), 600)
		c_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c_lbl.custom_minimum_size.x = 268
		costs.add_child(c_lbl)
	var cost: Label = %Cost
	cost.text = String(face.get("cost", "")) if cost_lines.is_empty() else ""
	cost.visible = cost.text != ""
	(%Desc as Label).text = String(face.get("desc", ""))
	(%Quip as Label).text = String(face.get("quip", ""))
	# 文字精简（2026-10-15）：卡面只留名称 + 主效果 + 副效果；desc（主副效果的重述）和风味台词不上卡面
	(%Desc as Label).visible = false
	(%Quip as Label).visible = false


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	# 投影（卡底下一圈暗影，卡浮在桌面上）
	draw_rect(Rect2(r.position + Vector2(3, 6), r.size), Color(0, 0, 0, 0.35))
	if _blind:
		if _back_tex != null:
			draw_texture_rect(_back_tex, r, false)
		return
	VaseFrame.draw(self, _frame_tex, r, FRAME_K)


## 神像圆章：god_<名> → ic_<名>；都没有就藏起来
static func _medal(tr: TextureRect, god: String) -> void:
	if god == "":
		tr.visible = false
		return
	var key: StringName = StringName(god if god.begins_with("god_") else "god_" + god)
	if not SpriteDB.has(key):
		key = StringName("ic_" + god.trim_prefix("god_"))
	tr.visible = SpriteDB.has(key)
	tr.texture = SpriteDB.tex(key)
