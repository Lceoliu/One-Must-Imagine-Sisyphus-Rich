// 视差层上的精灵（后景山肩的装饰、前景剪影）：黑釉 + 奶油刻线的素材按亮度重新上色成"远 / 近"的样子。
//   后景：墨色、线色都向天色混（haze），刻线对比压低（line_keep），mip 偏移让细节糊掉一点（mip_bias）。
//   前景：近黑的暖褐、刻线对比压得更低，轻虚化（blur_px 屏幕像素的 5 点模糊 + mip 偏移；贴图要开 mipmap），
//         离"焦点"（西西弗斯、石头）近的像素失焦（defocus_px 额外模糊）、轻微变透到 min_alpha；HUD 关键区域（zones）同样处理。
// 颜色：白天 day_* → 黄昏余晖 dusk_* → 夜 night_*，按全局 night_k 插值（和 terrain.gdshader 同一套），再乘 tod_tint（时刻染色）。
// 焦点、区域都在画布坐标（= World 节点的本地坐标，米 · 100，y 朝下）里给：脚本每帧算好传进来，和视差缩放无关。
shader_type canvas_item;

global uniform float night_k;

uniform vec4 day_ink : source_color = vec4(0.11, 0.07, 0.05, 1.0);
uniform vec4 day_line : source_color = vec4(0.36, 0.24, 0.17, 1.0);
uniform vec4 dusk_ink : source_color = vec4(0.09, 0.05, 0.045, 1.0);
uniform vec4 dusk_line : source_color = vec4(0.30, 0.18, 0.14, 1.0);
uniform vec4 night_ink : source_color = vec4(0.03, 0.04, 0.07, 1.0);
uniform vec4 night_line : source_color = vec4(0.13, 0.16, 0.24, 1.0);
// 天色（脚本每帧设）与混向天色的比例
uniform vec4 sky : source_color = vec4(0.8, 0.75, 0.68, 1.0);
uniform float haze : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tod_tint : source_color = vec4(1.0);
// 刻线阈值（按亮度在墨色和线色之间插值）
uniform float lo = 0.15;
uniform float hi = 0.75;
// 刻线保留多少（0 = 实心剪影，1 = 线色原样）
uniform float line_keep : hint_range(0.0, 1.0) = 1.0;
// 虚化：mip 偏移（档）、额外的 5 点模糊半径（屏幕像素）
uniform float mip_bias = 0.0;
uniform float blur_px = 0.0;
// 整体不透明度
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
// 焦点淡出：focus[i] = (画布 x, 画布 y, 内半径, 外半径)，内半径以内 = min_alpha
uniform vec4 focus[4];
uniform int focus_n = 0;
// 区域淡出：zones[i] = 画布矩形 (x0, y0, x1, y1)，zone_soft = 边缘渐变宽（画布像素）
uniform vec4 zones[4];
uniform int zone_n = 0;
uniform float zone_soft = 60.0;
uniform float min_alpha : hint_range(0.0, 1.0) = 1.0;
// 失焦：离焦点越近，额外模糊 defocus_px 屏幕像素（12 点圆盘采样 + mip 偏移），不透明度只降到 min_alpha（0 = 不用失焦、按 min_alpha 淡出，后景用）
uniform float defocus_px = 0.0;
// 底部渐隐：贴图下面这么大比例（0..1）的高度里不透明度从 1 渐到 0（前景的底边落在山体黑釉里，不留一条硬底边；后景 0）
uniform float base_fade : hint_range(0.0, 1.0) = 0.0;

varying vec2 v_canvas;

void vertex() {
	v_canvas = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

vec3 tri(vec3 a, vec3 b, vec3 c, float k) {
	return k < 0.5 ? mix(a, b, k * 2.0) : mix(b, c, k * 2.0 - 1.0);
}

// 预乘：模糊时透明像素的颜色（抠图残留）不混进来
vec4 premul(vec4 c) {
	return vec4(c.rgb * c.a, c.a);
}

// 采样（TEXTURE 不能当函数参数传，用宏）
#define SAMP(uv) premul(texture(TEXTURE, uv, mip_bias))

// 焦点、区域的"清晰度"：1 = 清晰，0 = 在焦点 / HUD 区域里
float focus_k(vec2 p) {
	float fade = 1.0;
	for (int i = 0; i < 4; i++) {
		if (i >= focus_n) {
			break;
		}
		float dd = length(p - focus[i].xy);
		fade = min(fade, smoothstep(focus[i].z, max(focus[i].z + 0.001, focus[i].w), dd));
	}
	for (int i = 0; i < 4; i++) {
		if (i >= zone_n) {
			break;
		}
		vec4 z = zones[i];
		vec2 o = max(z.xy - p, p - z.zw);
		float out_d = max(o.x, o.y);
		fade = min(fade, smoothstep(0.0, zone_soft, out_d));
	}
	return fade;
}

void fragment() {
	float fade = focus_k(v_canvas);
	float r = blur_px + defocus_px * (1.0 - fade);
	vec4 src;
	if (r > 0.01) {
		vec2 d = fwidth(UV) * r;
		float bias = mip_bias + log2(max(1.0, r * 0.5));
		src = premul(texture(TEXTURE, UV, bias)) * 0.16;
		for (int k = 0; k < 6; k++) {
			float a = 6.2831853 * float(k) / 6.0;
			src += premul(texture(TEXTURE, UV + vec2(cos(a), sin(a)) * d * 0.5, bias)) * 0.06;
			src += premul(texture(TEXTURE, UV + vec2(cos(a + 0.5236), sin(a + 0.5236)) * d, bias)) * 0.08;
		}
	} else {
		src = SAMP(UV);
	}
	float lum = dot(src.rgb, vec3(0.299, 0.587, 0.114)) / max(src.a, 0.001);
	float t = clamp((lum - lo) / max(0.001, hi - lo), 0.0, 1.0);
	t = t * t * (3.0 - 2.0 * t) * line_keep;
	float nk = clamp(night_k, 0.0, 1.0);
	vec3 ink = tri(day_ink.rgb, dusk_ink.rgb, night_ink.rgb, nk);
	vec3 line = tri(day_line.rgb, dusk_line.rgb, night_line.rgb, nk);
	vec3 rgb = mix(ink, line, t);
	rgb = mix(rgb, sky.rgb, haze) * tod_tint.rgb;
	float a = src.a * COLOR.a * opacity;
	a *= mix(min_alpha, 1.0, fade);
	if (base_fade > 0.0) {
		a *= 1.0 - smoothstep(1.0 - base_fade, 1.0, UV.y);
	}
	COLOR = vec4(rgb, a);
}
