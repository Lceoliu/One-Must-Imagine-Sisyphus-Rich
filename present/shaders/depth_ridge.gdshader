// 后景山肩（BackRidge 的 Fill）：同一座山在路后面隆起的肩部，比山体更淡、更冷、线更细、细节更少。
// 网格由 back_ridge.gd 按地形平滑抬高后的轮廓生成：UV.x = 层空间 x（米），UV.y = 轮廓线下方的竖直深度（米；负值 = 顶上抗锯齿的一小条），
// 顶点色 r = 1 − 山脚平地程度（0 = 城镇平地：山肩变成向后退去的田野带）。
// 画法：山肩里叠着几道小山（一档一档的平涂色带）：第 k 道的顶边在深度 b_k(x) = k · band_m + 起伏（hump，和 back_ridge.gd 同一公式，
//   装饰就站在这些顶边上）；越往下（越近）越深一档；每道小山的底部（下一道的顶边上方）向天色混一层薄雾；每道顶边一条细轮廓线。
//   坡上：每道小山里一两条断续的梯田 / 石墙线；平地：小山压扁成田块，田垄越往下越疏，田块之间短竖线分界。
//   整体向天色混 haze。颜色按全局 night_k 三档插值（白天 → 黄昏余晖 → 夜），再乘 tod_tint（和远景 / 山体同一套时刻染色）。
shader_type canvas_item;

global uniform float night_k;

uniform vec4 day_fill : source_color = vec4(0.70, 0.56, 0.46, 1.0);
uniform vec4 day_deep : source_color = vec4(0.58, 0.44, 0.36, 1.0);
uniform vec4 day_rim : source_color = vec4(0.42, 0.31, 0.26, 1.0);
uniform vec4 day_line : source_color = vec4(0.84, 0.74, 0.62, 1.0);
uniform vec4 dusk_fill : source_color = vec4(0.50, 0.36, 0.33, 1.0);
uniform vec4 dusk_deep : source_color = vec4(0.40, 0.28, 0.26, 1.0);
uniform vec4 dusk_rim : source_color = vec4(0.22, 0.13, 0.12, 1.0);
uniform vec4 dusk_line : source_color = vec4(0.66, 0.50, 0.44, 1.0);
uniform vec4 night_fill : source_color = vec4(0.15, 0.19, 0.28, 1.0);
uniform vec4 night_deep : source_color = vec4(0.12, 0.15, 0.24, 1.0);
uniform vec4 night_rim : source_color = vec4(0.06, 0.08, 0.13, 1.0);
uniform vec4 night_line : source_color = vec4(0.25, 0.31, 0.44, 1.0);
// 天色（脚本每帧设）、整体混向天色的比例、每道小山底部的薄雾（混向天色的比例、高度 米）
uniform vec4 sky : source_color = vec4(0.8, 0.75, 0.68, 1.0);
uniform float haze : hint_range(0.0, 1.0) = 0.3;
uniform float band_mist : hint_range(0.0, 1.0) = 0.45;
uniform float band_mist_m = 0.9;
uniform vec4 tod_tint : source_color = vec4(1.0);
// 1080p 逻辑像素 → 实际像素（线宽在任何分辨率下观感一致）
uniform float px_scale = 1.0;
// 轮廓线宽、细线宽（逻辑像素）、细线浓度
uniform float rim_px = 1.3;
uniform float line_px = 1.0;
uniform float line_alpha : hint_range(0.0, 1.0) = 0.5;
// 小山（色带）：下面四个由 back_ridge.gd 设（和装饰摆放共用），这里的值只是默认
uniform float band_m = 1.3;
uniform float band_amp = 0.55;
uniform float band_n = 4.0;
uniform float hump_a = 37.0;
uniform float hump_b = 16.3;
// 平地田垄：间距系数（第 k 条 ≈ furrow_a · k^1.35 米）
uniform float furrow_a = 0.22;

float h11(float n) {
	return fract(sin(n * 127.1 + 0.37) * 43758.5453);
}

vec3 tri(vec3 a, vec3 b, vec3 c, float k) {
	return k < 0.5 ? mix(a, b, k * 2.0) : mix(b, c, k * 2.0 - 1.0);
}

// 屏幕逻辑像素距离 → 覆盖率（宽 w 逻辑像素的线）
float cov(float dist_px, float w) {
	return clamp((w * 0.5 - dist_px) * px_scale + 0.5, 0.0, 1.0);
}

// 起伏（0..1，圆顶、尖谷：一个个小山包）。和 BackRidge.hump() 同一公式
float hump(float x, float k) {
	float tau = 6.2831853;
	return 0.6 * pow(abs(sin(x * tau / hump_a + 0.7 + k * 1.7)), 0.7) + 0.4 * pow(abs(sin(x * tau / hump_b + 2.1 + k * 2.9)), 0.7);
}

// 第 k 道小山顶边的深度（k ≥ 1）；amp = 起伏幅度（平地压扁）
float band_top(float x, float k, float amp) {
	return k * band_m + amp * (hump(x, k) - 0.5) * 2.0;
}

void fragment() {
	float x = UV.x;
	float d = UV.y;
	float slope = COLOR.r;
	// 每屏幕逻辑像素多少米（UV.x 在屏幕上线性）
	float mpp = max(1e-5, fwidth(UV.x)) * px_scale;
	float dpx = 1.0 / mpp;
	float nk = clamp(night_k, 0.0, 1.0);
	vec3 fill = tri(day_fill.rgb, dusk_fill.rgb, night_fill.rgb, nk);
	vec3 deep = tri(day_deep.rgb, dusk_deep.rgb, night_deep.rgb, nk);
	vec3 rim = tri(day_rim.rgb, dusk_rim.rgb, night_rim.rgb, nk);
	vec3 line = tri(day_line.rgb, dusk_line.rgb, night_line.rgb, nk);
	float amp = band_amp * mix(0.3, 1.0, slope);
	// 找所在的小山：top = 本道顶边深度，next = 下一道顶边深度
	float k = 0.0;
	float top = 0.0;
	float next = band_top(x, 1.0, amp);
	for (int i = 1; i <= 6; i++) {
		if (float(i) > band_n || d < next) {
			break;
		}
		k = float(i);
		top = next;
		next = max(band_top(x, k + 1.0, amp), top + 0.25);
	}
	if (k >= band_n) {
		next = top + 1e6;
	}
	vec3 col = mix(fill, deep, k / max(1.0, band_n));
	// 小山里的细线：坡上 = 一条断续的梯田 / 石墙线；平地 = 田垄（越往下越疏）+ 田块分界
	float dl = d - top;
	float lines = 0.0;
	float h = next - top;
	if (slope > 0.01) {
		float ly = h * 0.45 + sin(x * 0.21 + k * 3.1) * 0.08;
		float seg = floor(x / 5.0 + k * 0.37);
		float on = step(0.35, h11(seg + k * 17.0));
		lines = max(lines, cov(abs(dl - ly) * dpx, line_px) * on * smoothstep(5.0, 12.0, h * 0.45 * dpx) * slope);
	}
	if (slope < 0.99 && h < 1e5) {
		float kf = floor(pow(max(dl, 0.0) / furrow_a, 1.0 / 1.35) + 0.5);
		float lk = furrow_a * pow(kf, 1.35);
		float gap = furrow_a * (pow(kf + 1.0, 1.35) - pow(kf, 1.35));
		float fur = cov(abs(dl - lk) * dpx, line_px) * smoothstep(3.0, 8.0, gap * dpx) * step(0.05, lk);
		// 田块分界：每道小山里几段短竖线
		float plot = 5.0 + 7.0 * h11(k * 3.1);
		float px0 = (floor(x / plot) + h11(floor(x / plot) + k * 5.0)) * plot;
		float vd = cov(abs(x - px0) * dpx, line_px) * 0.7 * step(0.0, dl);
		lines = max(lines, max(fur, vd) * (1.0 - slope));
	}
	col = mix(col, line, lines * line_alpha);
	// 每道小山底部的薄雾（下一道顶边上方）
	float mist = smoothstep(next - band_mist_m, next, d) * band_mist;
	col = mix(col, sky.rgb, mist);
	// 顶边轮廓线（第 0 道 = 山肩轮廓，之后每道小山的顶边）
	float rim_cov = cov(abs(dl - rim_px * 0.5 * mpp) * dpx, rim_px) * (k == 0.0 ? 1.0 : 0.75);
	col = mix(col, rim, rim_cov);
	col = mix(col, sky.rgb, haze) * tod_tint.rgb;
	// 顶边抗锯齿（网格在轮廓线上方多出一小条）
	float a = clamp(d * dpx * px_scale + 0.5, 0.0, 1.0);
	COLOR = vec4(col, a * COLOR.a);
}
