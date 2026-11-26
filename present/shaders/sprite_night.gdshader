// 世界层夜间染色（= 网页 assets.js tinted()：米色刻线乘成冷蓝，黑色不变）。
// 全局 uniform night_k（0 白天 → 1 夜）由表现层每帧设置；画在本材质节点上的所有东西（精灵、地形、刻线）都乘一遍。
shader_type canvas_item;

global uniform float night_k;
global uniform vec4 night_tint;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	c.rgb *= mix(vec3(1.0), night_tint.rgb, clamp(night_k, 0.0, 1.0));
	COLOR = c;
}
