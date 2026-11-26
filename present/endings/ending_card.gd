class_name EndingCard
extends Control
## 结局卡（= endings.js showEndingCard + css/story.css .story-card / .sc-box；布局在 ending_card.tscn）。
## 普通 / 真结局 / 收债：按钮"传给下一代"；假结局："醒来"。打开 0.6 秒内的按钮 / 回车 / 空格不算（防误触）。
## 文案：结局名、正文、spared、comp、reveal_text 来自 StoryDefs.Ending；kind 标签 / 按钮字来自 endings.json 的 card_kind / card_button。

signal confirmed

const OPEN_GUARD: float = 0.6
const LINE: Color = Color("#e9d3a8")
const CREAM: Color = Color("#f1e3c8")
const MUTED: Color = Color("#b9a58c")
## 真结局标题的金色渐变（= linear-gradient(180deg, #fff1b8, #ffe08a 40%, #f0b93a 70%, #a8700f)）
const GOLD_SHADER: String = """
shader_type canvas_item;
uniform float h = 48.0;
varying float vy;
void vertex() { vy = VERTEX.y; }
void fragment() {
	float k = clamp(vy / h, 0.0, 1.0);
	vec3 c0 = vec3(1.0, 0.945, 0.722);
	vec3 c1 = vec3(1.0, 0.878, 0.541);
	vec3 c2 = vec3(0.941, 0.725, 0.227);
	vec3 c3 = vec3(0.659, 0.439, 0.059);
	vec3 c = k < 0.4 ? mix(c0, c1, k / 0.4) : (k < 0.7 ? mix(c1, c2, (k - 0.4) / 0.3) : mix(c2, c3, (k - 0.7) / 0.3));
	COLOR = vec4(c, COLOR.a * texture(TEXTURE, UV).a);
}
"""

var def: StoryDefs.Ending
var kind_text: String = ""
var title_text: String = ""
var body_text: String = ""
var extra_text: String = ""
var comp_text: String = ""
var stats_text: String = ""
var button_text: String = ""
var fake: bool = false
var is_true: bool = false

var _age: float = 0.0
var _closed: bool = false
var _u: float = 1.0
var _box: MarginContainer
var _button: Button
var _dim: GradientTexture2D


## p_raw = content.raw["story/endings.json"]（取 card_kind / card_button；缺了用网页默认值）
func setup(p_def: StoryDefs.Ending, p_sim: SimGame, p_flags: Dictionary, p_raw: Dictionary) -> void:
	def = p_def
	fake = def.kind == &"fake"
	is_true = def.kind == &"true"
	var ck: Dictionary = p_raw.get("card_kind", {})
	var cb: Dictionary = p_raw.get("card_button", {})
	var kdef: Dictionary = {"true": Loc.t("ending_card.true_ending", "真结局 · ΤΕΛΟΣ"), "fake": Loc.t("ending_card.false_ending_not_recorded", "假结局 · 本结局不计入档案"), "normal-bad": Loc.t("ending_card.ending_overdue", "结局 · 逾期"), "normal": Loc.t("ending_card.ending", "结局 · ΤΕΛΟΣ")}
	var k: String = String(def.kind)
	kind_text = Loc.t("ending.card_kind." + k, str(ck.get(k, kdef.get(k, kdef["normal"]))))
	var bk: String = "fake" if fake else "other"
	button_text = Loc.t("ending.card_button." + bk, str(cb.get(bk, Loc.t("ending_card.wake_up", "醒来") if fake else Loc.t("ending_card.pass_next_generation", "传给下一代"))))
	title_text = def.text("name")
	body_text = def.text("reveal_text") if fake else def.text("text")
	if is_true and str(p_flags.get("thanatos", "none")) == "spared":
		extra_text = def.text("spared")
	if fake:
		comp_text = def.text("comp")
	else:
		var items: int = 0
		if str(p_flags.get("chain", "none")) == "owned":
			items += 1
		if str(p_flags.get("prometheus", "none")) == "freed":
			items += 1
		if bool(p_flags.get("echo", false)):
			items += 1
		var day: int = p_sim.day if p_sim != null else 0
		var seals: int = 0
		if p_sim != null:
			seals = int(p_sim.run_stats.get("max_seals", 0))
		if seals == 0:
			seals = int(p_flags.get("max_seals", 0))
		var summit: String = "" if def.kind == &"normal-bad" else Loc.t("ending.card.summit", " · 登顶")
		stats_text = Loc.t("ending.card.stats", "第 {day} 日{summit} · 最高破封 {seals} 重 · 信物 {items}/3").replace("{day}", str(day)).replace("{summit}", summit).replace("{seals}", str(seals)).replace("{items}", str(items))
		# 发行配置关掉了真结局（EA）：信物拿不到，不显示"信物 x/3"
		if p_sim != null and not p_sim.content.ending_on(&"true"):
			stats_text = stats_text.replace(Loc.t("ending_card.keepsakes_3", " · 信物 %d/3") % items, "")


const SCENE: String = "res://present/endings/ending_card.tscn"


static func create() -> EndingCard:
	return SceneCache.make(SCENE) as EndingCard


func _ready() -> void:
	_u = maxf(0.5, get_viewport_rect().size.y / 900.0)
	# .screen.dim：radial-gradient(ellipse at 50% 45%, rgba(18,12,10,.62) 0%, rgba(6,4,3,.86) 80%)
	var grad: Gradient = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
	grad.colors = PackedColorArray([Color(18.0 / 255.0, 12.0 / 255.0, 10.0 / 255.0, 0.62), Color(6.0 / 255.0, 4.0 / 255.0, 3.0 / 255.0, 0.86), Color(6.0 / 255.0, 4.0 / 255.0, 3.0 / 255.0, 0.86)])
	_dim = GradientTexture2D.new()
	_dim.gradient = grad
	_dim.width = 256
	_dim.height = 256
	_dim.fill = GradientTexture2D.FILL_RADIAL
	_dim.fill_from = Vector2(0.5, 0.45)
	_dim.fill_to = Vector2(1.25, 0.45)
	_build()


## 场景（ending_card.tscn）里的各行填上这张卡的字；空行连同它下面的间隔一起藏起来
func _build() -> void:
	_box = %Box
	_box.draw.connect(_draw_box)
	(%Kind as Label).text = kind_text
	var title: Label = %Title
	title.text = title_text
	var sh: Label = %TitleShadow
	sh.text = title_text
	sh.visible = is_true
	if is_true:
		var shader: Shader = Shader.new()
		shader.code = GOLD_SHADER
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = shader
		# 渐变只覆盖字形本身（大致是行高的中间 70%）
		mat.set_shader_parameter("h", title.get_theme_font("font").get_height(title.get_theme_font_size("font_size")))
		title.material = mat
	var rule: Control = %Rule
	rule.draw.connect(func() -> void: meander_strip(rule, Rect2(Vector2.ZERO, rule.size), rule.size.y, Color(LINE, 0.55)))
	var body: Label = %Body
	body.text = body_text
	if fake:
		body.add_theme_font_override("font", EndCanvas.italic(600))
	for pair: Array in [["Extra", "ExtraGap", extra_text], ["Comp", "CompGap", comp_text], ["Stats", "StatsGap", stats_text]]:
		var l: Label = get_node("%" + str(pair[0])) as Label
		l.text = str(pair[2])
		l.visible = str(pair[2]) != ""
		(get_node("%" + str(pair[1])) as Control).visible = l.visible
	_button = %Go
	_button.text = "◆ %s ◆" % button_text
	_button.pressed.connect(go)
	_box.modulate.a = 0.0


## 回纹带（= --meander-cream：14×14 的 SVG 路径 M1.5 12V2h10v7h-6V5.5h3M0 12h14，按 tile 缩放、横向平铺）
static func meander_strip(ci: CanvasItem, r: Rect2, tile: float, col: Color) -> void:
	var k: float = tile / 14.0
	var lw: float = maxf(1.0, 1.6 * k)
	var n: int = ceili(r.size.x / tile)
	for i: int in n:
		var ox: float = r.position.x + i * tile
		if ox >= r.end.x:
			break
		var pts: PackedVector2Array = [Vector2(1.5, 12), Vector2(1.5, 2), Vector2(11.5, 2), Vector2(11.5, 9), Vector2(5.5, 9), Vector2(5.5, 5.5), Vector2(8.5, 5.5)]
		for j: int in pts.size():
			pts[j] = Vector2(ox + minf(pts[j].x * k, r.end.x - ox), r.position.y + pts[j].y * k)
		ci.draw_polyline(pts, col, lw, true)
	ci.draw_line(Vector2(r.position.x, r.position.y + 12 * k), Vector2(r.end.x, r.position.y + 12 * k), col, lw, true)


func _draw_box() -> void:
	var u: float = _u
	var r: Rect2 = Rect2(Vector2.ZERO, _box.size)
	# 投影 0 18px 40px rgba(0,0,0,.65)：几层外扩的半透明墨
	for i: int in 5:
		var g: float = (5.0 + i * 7.0) * u
		_box.draw_rect(Rect2(r.position + Vector2(-g, -g + 18.0 * u), r.size + Vector2(g, g) * 2.0), Color(0, 0, 0, 0.11))
	# 外圈 5px 墨环
	_box.draw_rect(r.grow(5.0 * u), Color(18.0 / 255.0, 12.0 / 255.0, 10.0 / 255.0, 0.95))
	# 底色：rgba(26,17,13,.94) → rgba(10,6,4,.96)
	var top: Color = Color(26.0 / 255.0, 17.0 / 255.0, 13.0 / 255.0, 0.94)
	var bot: Color = Color(10.0 / 255.0, 6.0 / 255.0, 4.0 / 255.0, 0.96)
	_box.draw_polygon(EndCanvas.rect_pts(0, 0, r.size.x, r.size.y), PackedColorArray([top, top, bot, bot]))
	_box.draw_rect(r, LINE, false, 1.5 * u)
	# ::before 顶部回纹：left/right 10px，top 8px，高 10px，不透明度 .45
	meander_strip(_box, Rect2(10.0 * u, 8.0 * u, r.size.x - 20.0 * u, 10.0 * u), 10.0 * u, Color(LINE, 0.45))


func _draw() -> void:
	var a: float = clampf(_age / 0.25, 0.0, 1.0)
	draw_texture_rect(_dim, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, a))


func _process(dt: float) -> void:
	_age += dt
	if _box != null:
		var k: float = clampf(_age / 0.35, 0.0, 1.0)
		var e: float = 1.0 - pow(1.0 - k, 3.0)
		_box.modulate.a = e
		_box.pivot_offset = _box.size / 2.0
		_box.scale = Vector2.ONE * (0.97 + 0.03 * e)
	if _age < 0.4:
		queue_redraw()


## 确认（按钮 / 回车 / 空格）：打开 0.6 秒内无效
func go() -> void:
	if _closed or _age < OPEN_GUARD:
		return
	_closed = true
	Sfx.play(&"click")
	confirmed.emit()


## 给测试 / 机器人：立刻确认（跳过防误触）
func next() -> void:
	if _closed:
		return
	_closed = true
	confirmed.emit()


## 测试用：已打开多久
func age() -> float:
	return _age


func _input(ev: InputEvent) -> void:
	var k: InputEventKey = ev as InputEventKey
	if k == null or not k.pressed:
		return
	if k.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		if not k.echo:
			go()
