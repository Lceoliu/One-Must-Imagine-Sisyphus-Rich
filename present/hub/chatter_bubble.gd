class_name ChatterBubble
extends PanelContainer
## 夜宴里没有对话功能的人偶尔冒的气泡（自言自语，或者和旁边的人搭话）。样式在 chatter_bubble.tscn。
## 不拦输入；hub_view 每帧用 place() 把它挪到说话人头顶（屏幕坐标），说完淡出，finished() 后由 hub_view 删掉。

const SCENE: String = "res://present/hub/chatter_bubble.tscn"

## 一行放不下就折行的宽度（像素）
@export var max_width: float = 340.0
@export var fade_in: float = 0.25
@export var fade_out: float = 0.45
## 小尾巴的高度（气泡底边到说话人头顶）
@export var tail_h: float = 10.0

var life: float = 3.5
var _t: float = 0.0


static func create(text: String, life_s: float) -> ChatterBubble:
	var b: ChatterBubble = SceneCache.make(SCENE) as ChatterBubble
	b.life = life_s
	b.set_text(text)
	return b


func set_text(text: String) -> void:
	var lb: Label = get_node("Label") as Label
	lb.text = text
	lb.autowrap_mode = TextServer.AUTOWRAP_OFF
	lb.custom_minimum_size.x = 0.0
	if lb.get_minimum_size().x > max_width:
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.custom_minimum_size.x = max_width
	reset_size()


func _process(dt: float) -> void:
	_t += dt
	var a: float = clampf(_t / fade_in, 0.0, 1.0) * clampf((life - _t) / fade_out, 0.0, 1.0)
	modulate.a = a
	var tail: Polygon2D = get_node_or_null("Tail") as Polygon2D
	if tail != null:
		tail.position = Vector2(size.x * 0.5, size.y - 1.0)


func finished() -> bool:
	return _t >= life


## 尾巴尖对准屏幕上的点 p（说话人头顶）
func place(p: Vector2) -> void:
	position = p - Vector2(size.x * 0.5, size.y + tail_h)
