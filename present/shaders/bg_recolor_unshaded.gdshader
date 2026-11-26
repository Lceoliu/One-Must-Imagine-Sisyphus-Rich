// = bg_recolor.gdshader 的不受光版本（夜宴远景用）：夜宴有 CanvasModulate 压冷月色，远景（奥林匹斯、云带、远山、丘陵、海岸）
// 用 unshaded 跳过它，颜色就和白天入夜（background_view.gd 的 PAL / ATMOS 在 night_k = 1、海拔 0 时）完全一样。
// 和 bg_recolor 的区别：render_mode unshaded；edge 按每一块平铺（fract(UV.x)）计算，所以一个 region 很宽、texture_repeat = 镜像的 Sprite2D 就能铺满整条。
shader_type canvas_item;
render_mode unshaded;

uniform vec4 fill_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 line_color : source_color = vec4(1.0);
uniform float lo = 0.15;
uniform float hi = 0.75;
uniform float edge = 0.0;
uniform float alpha = 1.0;

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float lum = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	float t = clamp((lum - lo) / max(0.001, hi - lo), 0.0, 1.0);
	t = t * t * (3.0 - 2.0 * t);
	vec3 rgb = mix(fill_color.rgb, line_color.rgb, t);
	float a = src.a * alpha * COLOR.a;
	if (edge > 0.0) {
		float u = fract(UV.x);
		float e = min(u, 1.0 - u) / edge;
		if (e < 1.0) {
			a *= e * e * (3.0 - 2.0 * e);
		}
	}
	COLOR = vec4(rgb, a);
}
