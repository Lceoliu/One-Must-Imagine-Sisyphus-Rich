// 山脚城镇的近排 / 远排建筑（docs/v05/town.md）：路边建筑全是黑釉剪影，路面上的人、牲畜、车也是黑的，
// 叠在一起会糊成一片。这里按大气透视把后排的黑釉抬到一档（haze），刻线也往 haze 靠一点，
// 路面那排（照常画在 Tinted 上）就从建筑前面跳出来。
// 先乘 sprite_night 的冷蓝，再抬色：白天抬到暖褐（haze），夜里抬到比夜空略亮的石板蓝（haze_night），
// 不然暖褐乘冷蓝会变成发灰的褐色鬼影。
shader_type canvas_item;

global uniform float night_k;
global uniform vec4 night_tint;

// 黑釉抬到的颜色（越远越浅）：白天、夜里
uniform vec4 haze : source_color = vec4(0.2, 0.155, 0.13, 1.0);
uniform vec4 haze_night : source_color = vec4(0.07, 0.085, 0.14, 1.0);
// 刻线往 haze 靠的比例（后排的纹饰退一档，别和路面上的人抢）
uniform float line_fade = 0.18;
// 神造之城（v0.6，city_levels.json 第 6 档 gilded）：众神用金子重建，亮的刻线描成金，黑釉身子不动。WorldView 按繁荣度设
uniform float gild : hint_range(0.0, 1.0) = 0.0;
uniform vec4 gild_color : source_color = vec4(0.86, 0.64, 0.27, 1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float k = clamp(night_k, 0.0, 1.0);
	c.rgb *= mix(vec3(1.0), night_tint.rgb, k);
	vec3 hz = mix(haze.rgb, haze_night.rgb, k);
	c.rgb = mix(max(c.rgb, hz), hz, line_fade);
	// 描金：只动亮的刻线（亮度越高越金），夜里金色跟着冷一点
	float l = max(c.r, max(c.g, c.b));
	float kl = smoothstep(0.18, 0.5, l) * gild;
	vec3 gold = gild_color.rgb * mix(1.0, 0.75, k) * (0.55 + 0.45 * l);
	c.rgb = mix(c.rgb, gold, kl);
	COLOR = c;
}
