// 背景双色层重新上色（= 网页 background.js recolor()）：按亮度在 fill（黑）与 line（白）之间平滑插值，保留 alpha。
// lo / hi：刻线阈值；edge：左右渐隐宽度（占整张图的比例，0 = 不渐隐）；mask_lo / mask_hi：竖向遮罩（只保留上方的刻线，0 = 关闭）。
// 平铺时奇数块水平镜像由绘制方负责（uv 已经翻转），所以 edge 用 UV.x 计算两端即可。
shader_type canvas_item;

uniform vec4 fill_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 line_color : source_color = vec4(1.0);
uniform float lo = 0.15;
uniform float hi = 0.75;
uniform float edge = 0.0;
uniform float mask_lo = 0.0;
uniform float mask_hi = 0.0;
uniform float alpha = 1.0;

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float lum = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	float t = clamp((lum - lo) / max(0.001, hi - lo), 0.0, 1.0);
	t = t * t * (3.0 - 2.0 * t);
	if (mask_hi > mask_lo) {
		t *= 1.0 - smoothstep(mask_lo, mask_hi, UV.y);
	}
	vec3 rgb = mix(fill_color.rgb, line_color.rgb, t);
	float a = src.a * alpha * COLOR.a;
	if (edge > 0.0) {
		float e = min(UV.x, 1.0 - UV.x) / edge;
		if (e < 1.0) {
			a *= e * e * (3.0 - 2.0 * e);
		}
	}
	COLOR = vec4(rgb, a);
}
