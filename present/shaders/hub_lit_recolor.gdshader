// 夜宴的废墟、地面、碎石堆：先像 bg_recolor 那样按亮度在 fill（底色）与 line（刻线色）之间重新上色，再按 hub_light 受光。
// 底色不用纯黑而用一点暖灰，火光照过来时整块石头会被照暖（纯黑乘什么光都还是黑）；刻线色压得比人物暗，让人物站在前面。
// line_fade > 0 时刻线往贴图下沿渐暗；fade_bottom > 0 时贴图下沿那一段渐隐（后沿碎石堤埋进走道里，不留一条硬底边）。
shader_type canvas_item;

#include "res://present/shaders/hub_light.gdshaderinc"

uniform vec4 fill_color : source_color = vec4(0.08, 0.075, 0.075, 1.0);
uniform vec4 line_color : source_color = vec4(0.62, 0.58, 0.52, 1.0);
uniform float lo = 0.15;
uniform float hi = 0.75;
uniform float fade_bottom = 0.0;
// 刻线往贴图下沿渐暗（0 = 不变暗；1 = 最下沿的刻线压到底色）：近景碎石越靠画面底越安静，不和人物抢
uniform float line_fade = 0.0;

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float lum = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	float t = clamp((lum - lo) / max(0.001, hi - lo), 0.0, 1.0);
	t = t * t * (3.0 - 2.0 * t);
	t *= 1.0 - line_fade * smoothstep(0.15, 1.0, fract(UV.y));
	vec3 rgb = mix(fill_color.rgb, line_color.rgb, t);
	float a = src.a * COLOR.a;
	if (fade_bottom > 0.0) {
		a *= 1.0 - smoothstep(1.0 - fade_bottom, 1.0, fract(UV.y));
	}
	COLOR = vec4(rgb * COLOR.rgb, a);
}
