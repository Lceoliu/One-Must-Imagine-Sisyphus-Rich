// 夜宴的暗角（UILayer 之下、所有场景之上的一层 ColorRect）：四角和底边压暗一点，把视线收到中间的走道上，
// 也让最前面的碎石场在画面底边慢慢沉进黑里（不是一块平的暗色）。不受光。
shader_type canvas_item;
render_mode unshaded;

uniform vec4 tint : source_color = vec4(0.01, 0.012, 0.03, 1.0);
// 角上的浓度
uniform float strength = 0.55;
// 从中心多远开始变暗（0 = 中心，1 = 边）
uniform float inner = 0.45;
// 底边额外压暗的高度（占屏高）与浓度
uniform float bottom = 0.12;
uniform float bottom_strength = 0.35;

void fragment() {
	vec2 d = (UV - vec2(0.5)) * 2.0;
	d.x *= 0.85;
	float v = smoothstep(inner, 1.35, length(d));
	float b = smoothstep(1.0 - bottom, 1.0, UV.y) * bottom_strength;
	COLOR = vec4(tint.rgb, clamp(v * strength + b, 0.0, 1.0));
}
