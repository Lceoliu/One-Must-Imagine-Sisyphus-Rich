// 西西弗斯（CanvasGroup）的"留白轮廓"：黑绘陶瓶上两个黑剪影重叠时，画师用一道刻线 / 一条底色缝把它们分开。
// 这里在人物剪影外面描一圈陶土底色（夜里是石板蓝）：在陶土山坡上几乎看不出来，叠在黑色建筑、石头上时就成了一道分隔缝。
// CanvasGroup 的子节点先画进屏幕纹理，本着色器从里面取：剪影本身照常画（再乘上世界的夜色），剪影外 gap_px 以内画缝。
shader_type canvas_item;

global uniform float night_k;
global uniform vec4 night_tint;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
// 缝宽（屏幕像素）
uniform float gap_px = 2.2;
uniform vec4 day_gap : source_color = vec4(0.7255, 0.5176, 0.3882, 1.0);
uniform vec4 night_gap : source_color = vec4(0.1843, 0.2275, 0.3333, 1.0);

void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);
	float k = clamp(night_k, 0.0, 1.0);
	c.rgb *= mix(vec3(1.0), night_tint.rgb, k);
	if (c.a < 0.98) {
		// 8 个方向 × 2 圈取最大不透明度：剪影外缘一圈
		float m = 0.0;
		for (int i = 0; i < 8; i++) {
			float a = 6.2831853 * float(i) / 8.0;
			vec2 d = vec2(cos(a), sin(a)) * SCREEN_PIXEL_SIZE;
			m = max(m, textureLod(screen_texture, SCREEN_UV + d * gap_px, 0.0).a);
			m = max(m, textureLod(screen_texture, SCREEN_UV + d * gap_px * 0.5, 0.0).a);
		}
		vec4 g = mix(day_gap, night_gap, k);
		g.a = clamp(m, 0.0, 1.0);
		// 剪影本身的抗锯齿边压在缝上
		c = vec4(mix(g.rgb, c.rgb / max(c.a, 0.001), c.a), max(g.a, c.a));
	}
	COLOR = c;
}
