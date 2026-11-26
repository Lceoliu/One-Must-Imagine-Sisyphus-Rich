// 火盆的"前沿"：同一张盆的贴图再画一遍、叠在火焰上面，只留盆口前沿以下（盆身）——火苗底部藏进盆里，
// 不会像贴在盆沿外面。盆口是贴图顶上的一个椭圆（贴图 UV：中心 rim_c、半轴 rim_r），前沿 = 椭圆的下半圈，再往下 rim_drop。
// 受光同 hub_lit（hub_light.gdshaderinc）。
shader_type canvas_item;

#include "res://present/shaders/hub_light.gdshaderinc"

uniform vec2 rim_c = vec2(0.5, 0.036);
uniform vec2 rim_r = vec2(0.49, 0.024);
uniform float rim_drop = 0.006;

void fragment() {
	float dx = clamp((UV.x - rim_c.x) / rim_r.x, -1.0, 1.0);
	float front = rim_c.y + rim_r.y * sqrt(max(0.0, 1.0 - dx * dx)) + rim_drop;
	if (UV.y < front) {
		discard;
	}
	COLOR = texture(TEXTURE, UV) * COLOR;
}
