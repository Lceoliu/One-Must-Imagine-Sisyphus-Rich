class_name VaseFrame
extends RefCounted
## 瓶画边框的九宫格（assets/native/ui_cards/card_<档>.png，Codex 画的：四角棕榈叶、上下回纹带、左右双线点带、中间平涂黑釉）。
## Godot 自带的九宫格按贴图像素画边框，高清贴图的边框会画得很宽；这里把贴图按 k 缩小画：
## 四个角按 k 缩放、上下左右四条带拉伸（回纹带只拉不重复，接缝不会错位）、中间拉伸。

## 每档的贴图；src = 贴图上的九宫格边距（像素，左 上 右 下）
const TEX: Array[String] = ["res://assets/native/ui_cards/card_bronze.png", "res://assets/native/ui_cards/card_silver.png",
	"res://assets/native/ui_cards/card_gold.png", "res://assets/native/ui_cards/card_mythic.png"]
const BACK: String = "res://assets/native/ui_cards/card_back.png"
const SRC: Vector4 = Vector4(80, 118, 80, 118)


static func tier_tex(tier: int) -> Texture2D:
	return load(TEX[clampi(tier, 0, TEX.size() - 1)]) as Texture2D


## 在 rect 里画九宫格边框；k = 画出来的边框 / 贴图边距
static func draw(ci: CanvasItem, tex: Texture2D, rect: Rect2, k: float, src: Vector4 = SRC, mod: Color = Color.WHITE) -> void:
	if tex == null:
		return
	var tw: float = tex.get_width()
	var th: float = tex.get_height()
	var l: float = src.x
	var t: float = src.y
	var r: float = src.z
	var b: float = src.w
	var dl: float = l * k
	var dt: float = t * k
	var dr: float = r * k
	var db: float = b * k
	var x0: float = rect.position.x
	var y0: float = rect.position.y
	var x1: float = rect.end.x
	var y1: float = rect.end.y
	var mw_s: float = tw - l - r
	var mh_s: float = th - t - b
	var mw_d: float = maxf(0.0, rect.size.x - dl - dr)
	var mh_d: float = maxf(0.0, rect.size.y - dt - db)
	# 中间
	ci.draw_texture_rect_region(tex, Rect2(x0 + dl, y0 + dt, mw_d, mh_d), Rect2(l, t, mw_s, mh_s), mod)
	# 上下两条带：拉伸
	ci.draw_texture_rect_region(tex, Rect2(x0 + dl, y0, mw_d, dt), Rect2(l, 0, mw_s, t), mod)
	ci.draw_texture_rect_region(tex, Rect2(x0 + dl, y1 - db, mw_d, db), Rect2(l, th - b, mw_s, b), mod)
	# 左右两条带：拉伸（卡片高宽比和贴图接近，拉得不多，圆点不会明显变形）
	ci.draw_texture_rect_region(tex, Rect2(x0, y0 + dt, dl, mh_d), Rect2(0, t, l, mh_s), mod)
	ci.draw_texture_rect_region(tex, Rect2(x1 - dr, y0 + dt, dr, mh_d), Rect2(tw - r, t, r, mh_s), mod)
	# 四个角
	ci.draw_texture_rect_region(tex, Rect2(x0, y0, dl, dt), Rect2(0, 0, l, t), mod)
	ci.draw_texture_rect_region(tex, Rect2(x1 - dr, y0, dr, dt), Rect2(tw - r, 0, r, t), mod)
	ci.draw_texture_rect_region(tex, Rect2(x0, y1 - db, dl, db), Rect2(0, th - b, l, b), mod)
	ci.draw_texture_rect_region(tex, Rect2(x1 - dr, y1 - db, dr, db), Rect2(tw - r, th - b, r, b), mod)
