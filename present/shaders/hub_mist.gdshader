// 夜宴的薄雾 / 地面烟雾：贴图（GradientTexture2D）的 alpha 给竖向轮廓，这里叠两层慢慢飘的噪声，让雾有疏有密。
// 不受光（unshaded），颜色就是 tint；层与层之间各放一条，越远越冷越淡（大气透视）。
shader_type canvas_item;
render_mode unshaded;

uniform vec4 tint : source_color = vec4(0.42, 0.52, 0.74, 0.35);
// 横向噪声的疏密（整条上有多少团）
uniform float puffs = 40.0;
// 飘动速度（每秒挪动多少团）
uniform float drift = 0.05;
// 噪声的影响：0 = 均匀一条，1 = 很碎
uniform float breakup = 0.7;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float prof = texture(TEXTURE, UV).a;
	vec2 p = vec2(UV.x * puffs, UV.y * 3.0);
	float n = noise(p + vec2(TIME * drift, 0.0)) * 0.6 + noise(p * 2.3 + vec2(-TIME * drift * 1.7, 0.0)) * 0.4;
	float k = mix(1.0, smoothstep(0.2, 0.85, n) * 1.4, breakup);
	COLOR = vec4(tint.rgb, tint.a * prof * k * COLOR.a);
}
