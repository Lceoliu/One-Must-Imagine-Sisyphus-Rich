@tool
class_name HubShadows
extends Node2D
## 夜宴的接地阴影：在 targets 里每个节点的脚下（x、y = 节点的位置，y 再低 lift）画一团压扁的柔边黑影，让人物、道具"踩"在地上而不是贴在上面。
## 放在 Main 里、z_index 低于所有站在地上的东西（但高于地面）。每帧跟着目标走（西西弗斯、侍者会动；神像以后换成骨骼实例也不用改）。
## 宽度：widths 里对应位置 > 0 就用它，否则按目标贴图宽 × auto_width 自动估（Sprite2D / AnimatedSprite2D）。编辑器里同样画出来。

## 要投影的节点（相对本节点的路径）
@export var targets: Array[NodePath] = []:
	set(v):
		targets = v
		queue_redraw()
## 每个目标的阴影宽（参考 1080 高的世界坐标；0 = 自动）
@export var widths: PackedFloat32Array = []:
	set(v):
		widths = v
		queue_redraw()
## 自动宽度 = 贴图显示宽 × 这个比例
@export var auto_width: float = 0.72
## 阴影厚度 = 宽 × 这个比例
@export var flatness: float = 0.16
## 阴影中心比目标的脚（节点的 y）再低这么多（后道整体抬高了，阴影跟着各自的脚走）
@export var lift: float = 6.0
## 浓度
@export_range(0.0, 1.0) var strength: float = 0.62:
	set(v):
		strength = v
		queue_redraw()
## 阴影颜色（偏冷的近黑，被火照到的地面上也压得住）
@export var tint: Color = Color(0.0, 0.0, 0.02, 1.0)


func _process(_dt: float) -> void:
	queue_redraw()


func _width_of(n: Node2D, i: int) -> float:
	if i < widths.size() and widths[i] > 0.0:
		return widths[i]
	var w: float = 0.0
	var sp: Sprite2D = n as Sprite2D
	if sp != null and sp.texture != null:
		w = (sp.region_rect.size.x if sp.region_enabled else float(sp.texture.get_width())) * absf(sp.global_scale.x)
	var an: AnimatedSprite2D = n as AnimatedSprite2D
	if an != null and an.sprite_frames != null and an.sprite_frames.has_animation(an.animation):
		var tex: Texture2D = an.sprite_frames.get_frame_texture(an.animation, 0)
		if tex != null:
			w = float(tex.get_width()) * absf(an.global_scale.x)
	return maxf(60.0, w * auto_width)


func _draw() -> void:
	var tex: Texture2D = Glow.tex()
	var inv: Transform2D = global_transform.affine_inverse()
	for i: int in targets.size():
		var n: Node2D = get_node_or_null(targets[i]) as Node2D
		if n == null or not n.is_visible_in_tree():
			continue
		var w: float = _width_of(n, i)
		var c: Vector2 = inv * (n.global_position + Vector2(0.0, lift))
		var h: float = w * flatness
		# 两层：外圈淡而宽，内圈浓而窄（脚下最黑）
		draw_texture_rect(tex, Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), false, Color(tint, strength * 0.75))
		draw_texture_rect(tex, Rect2(c - Vector2(w, h) * 0.3, Vector2(w, h) * 0.6), false, Color(tint, strength))
