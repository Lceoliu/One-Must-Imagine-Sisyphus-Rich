// 夜宴受光的公共部分（hub_lit / hub_lit_recolor 共用）：黑绘的底色是纯黑，普通 2D 灯光（乘在颜色上）只能照亮刻线，照不出体积。
// 这里自定义 light()：刻线照常受光（= 默认），另外按法线贴图（由 alpha 自动生成的圆角斜面，见 tools/assets/make_normals.py）
// 叠一圈朝向光源的轮廓光——火盆、吊灯在剪影边缘留下一道暖边，月光（DirectionalLight2D）留一道冷边。
// 需要贴图是 CanvasTexture（diffuse + normal）；没有法线时 NORMAL 朝外，轮廓光自然为 0。

// 点光源（火、灯）的轮廓光强度
uniform float rim = 3.0;
// 平行光（月光）的轮廓光强度
uniform float moon_rim = 1.6;
// 黑底子在火边也微微透出暖色（不然近火的人物仍是死黑一块）
uniform float body = 0.07;
// 轮廓光只出现在斜面上：法线倾斜多少算"边"
uniform float edge_gain = 1.8;

void light() {
	float edge = clamp(length(NORMAL.xy) * edge_gain, 0.0, 1.0);
	vec2 to_light = normalize(LIGHT_DIRECTION.xy + vec2(0.0001));
	float facing = max(dot(normalize(NORMAL.xy + vec2(0.0001)), to_light), 0.0);
	float r = edge * facing;
	if (LIGHT_IS_DIRECTIONAL) {
		LIGHT = vec4(LIGHT_COLOR.rgb * LIGHT_ENERGY * r * moon_rim, LIGHT_COLOR.a);
	} else {
		vec3 base = (COLOR.rgb + vec3(body)) * LIGHT_COLOR.rgb * LIGHT_ENERGY;
		LIGHT = vec4(base + LIGHT_COLOR.rgb * LIGHT_ENERGY * r * rim, LIGHT_COLOR.a);
	}
}
