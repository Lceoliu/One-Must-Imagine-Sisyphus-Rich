// 层间雾带（借 depth_b1 的"层间雾带"）：沿一条基线（路面 / 山肩轮廓）的横向柔雾，底部最浓、向上渐隐。
// 网格由 mist_band.gd 生成：UV.x = 世界 / 层空间 x（米），UV.y = 0 在雾带底（基线下方 below_m 处）… 1 在雾带顶。
// 雾的颜色取天色（脚本每帧设 sky；夜里换成冷雾 night_mist），按全局 night_k 混合；有一点缓慢飘动的疏密（value noise）。
shader_type canvas_item;

global uniform float night_k;

uniform vec4 sky : source_color = vec4(0.85, 0.8, 0.72, 1.0);
uniform vec4 night_mist : source_color = vec4(0.25, 0.30, 0.42, 1.0);
// 雾色在天色基础上再乘的染色（白 = 原样）
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 tod_tint : source_color = vec4(1.0);
// 浓度（底部最大不透明度）、夜里浓度倍率
uniform float density : hint_range(0.0, 1.0) = 0.55;
uniform float night_density = 0.8;
// 竖向轮廓：底部从 0 升到满浓度的比例（0..1）、向上衰减的指数
uniform float rise = 0.18;
uniform float falloff = 1.6;
// 疏密：噪声尺度（米）、起伏幅度、飘动速度（米 / 秒）
uniform float wisp_m = 14.0;
uniform float wisp_amp : hint_range(0.0, 1.0) = 0.35;
uniform float drift = 0.6;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float v = clamp(UV.y, 0.0, 1.0);
	float prof = smoothstep(0.0, max(0.001, rise), v) * pow(1.0 - v, falloff);
	vec2 q = vec2(UV.x / wisp_m + TIME * drift / wisp_m, v * 1.7);
	float n = vnoise(q) * 0.65 + vnoise(q * 2.3 + vec2(5.2, 1.3)) * 0.35;
	float wisp = mix(1.0, 0.45 + n * 1.1, wisp_amp);
	float nk = clamp(night_k, 0.0, 1.0);
	vec3 col = mix(sky.rgb * tint.rgb, night_mist.rgb, nk) * tod_tint.rgb;
	float a = density * mix(1.0, night_density, nk) * prof * wisp;
	COLOR = vec4(col, clamp(a, 0.0, 1.0) * COLOR.a);
}
