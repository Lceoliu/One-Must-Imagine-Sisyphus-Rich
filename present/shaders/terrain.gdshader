// 山体（世界层地形）：陶瓶式的分区（效果图 concept/steep_a.png，"浅层斜岩"）——地表路沿 → 两层刻出来的大岩块 → 瓶足饰带 → 平整的黑釉。
// 饰带顺着地表、固定埋在 band_m 米深（陡坡、拉远都不变）：岩块只是路面下薄薄一层，下面一大片安静的黑釉，像瓶身下半截，不抢人和石头的视觉重心。
// 网格由 WorldView._build_terrain_mesh 按地形折线生成（一个网格一次绘制）：
//   UV.x = 正上方地表点的弧长 s（米），UV.y = 该点在地表下方的竖直深度 d（米；负值 = 地表上方的草丛带）；
//   顶点色 r = 1 − 山脚平地（城镇）程度，g = 平滑后的地表坡角（0.5 + 角度 / π；左右各 10 米弧长取弦的方向）；
//   世界坐标从 VERTEX 里取（Terrain 节点在世界原点，1 米 = 100 像素，y 朝下）。
// "沿地表坐标"：along = s − d·sinθ（沿地表）、perp = d·cosθ（垂直地表的深度），θ 是平滑坡角。
//   (x, 竖直深度) 在陡坡上是剪切的（圆变斜条、饰带变薄）；沿地表坐标处处连续、陡坡上也不变形，所以路沿、分档、饰带、岩块都在这里画。
// 贴图（WorldView 用 TerrainTex 拼成 Texture2DArray；画风按效果图 concept/depth_a2.png，tools/assets/rock_strip.py 做成可平铺）：
//   top_tex 5 层（foot / low / mid / high / summit）：地表那一截的彩色截面——上方草丛碎石（透明）、浅色夯土路沿、两三层大岩块；
//     只横向平铺，一个周期 top_period_m 米，第 top_surface_m 米处是地表线，贴图共 top_h_m 米高；
//   deep_tex 5 层：更深处的岩层（横竖都平铺，竖向周期 deep_h_m 米切在一道水平岩缝上），每一层岩带横向错开一段，不叠成砖墙；
//   band_tex 2 层（光芒纹 / 棕榈叶纹，纹样黑、底透明，左右无缝）。
// 白天直接用贴图的颜色（只乘时刻染色）；黄昏、夜里把贴图亮度映射到 dusk_* / night_* 调色板（保留岩块的明暗和纹理）。
// 海拔段之间按"地表海拔 + 二维噪声"平滑交错混合（band_edges 三个分界、各 ± band_blend 米），不一刀切。
// 颜色：白天 day_*、黄昏 dusk_*、夜 night_* 三档，按全局 night_k 插值（不走 sprite_night 的乘色：夜里山体要比人物亮一档），
//   再乘 tod_tint（和远景同一套时刻染色，WorldView 每帧设）。
shader_type canvas_item;

global uniform float night_k;

group_uniforms day;
// 陶土面、背光面、刻线、路沿 / 饰带底色、黑釉
uniform vec4 day_fill : source_color = vec4(0.761, 0.545, 0.388, 1.0);
uniform vec4 day_shade : source_color = vec4(0.635, 0.427, 0.298, 1.0);
uniform vec4 day_ink : source_color = vec4(0.165, 0.098, 0.067, 1.0);
uniform vec4 day_lip : source_color = vec4(0.851, 0.69, 0.537, 1.0);
uniform vec4 day_glaze : source_color = vec4(0.11, 0.071, 0.051, 1.0);
group_uniforms dusk;
uniform vec4 dusk_fill : source_color = vec4(0.541, 0.345, 0.29, 1.0);
uniform vec4 dusk_shade : source_color = vec4(0.443, 0.275, 0.235, 1.0);
uniform vec4 dusk_ink : source_color = vec4(0.11, 0.059, 0.051, 1.0);
uniform vec4 dusk_lip : source_color = vec4(0.62, 0.42, 0.345, 1.0);
uniform vec4 dusk_glaze : source_color = vec4(0.075, 0.043, 0.039, 1.0);
group_uniforms night;
uniform vec4 night_fill : source_color = vec4(0.184, 0.227, 0.333, 1.0);
uniform vec4 night_shade : source_color = vec4(0.149, 0.184, 0.278, 1.0);
uniform vec4 night_ink : source_color = vec4(0.035, 0.047, 0.086, 1.0);
uniform vec4 night_lip : source_color = vec4(0.243, 0.29, 0.408, 1.0);
uniform vec4 night_glaze : source_color = vec4(0.047, 0.059, 0.11, 1.0);
group_uniforms;
// 时刻染色（乘色；正午 = 白）
uniform vec4 tod_tint : source_color = vec4(1.0);
// 下面的"像素"都是 1080p 逻辑像素；px_scale = 实际像素 / 逻辑像素（WorldView 每帧设置），线宽在任何分辨率下观感一致
uniform float px_scale = 1.0;

group_uniforms textures;
uniform sampler2DArray top_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray deep_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray band_tex : filter_linear_mipmap, repeat_enable;
// 地表截面：周期、总高、地表线离贴图顶多少米（manifest.json 的 period_m、size / px_per_m、surface_row / px_per_m）
uniform float top_period_m = 14.71;
uniform float top_h_m = 5.70;
uniform float top_surface_m = 0.866;
// 深处岩层：周期、竖向周期
uniform float deep_period_m = 14.64;
uniform float deep_h_m = 2.693;
// 两张贴图交界、深处每层岩带之间那道水平岩缝的宽（米）
uniform float joint_w_m = 0.05;
// 白天贴图颜色的饱和度、亮度微调
uniform float day_sat = 1.0;
uniform float day_gain = 1.0;
// 山顶路沿积雪：路沿面（贴图里最亮的那一档）在山顶染成这个颜色
uniform vec4 snow : source_color = vec4(0.93, 0.89, 0.82, 1.0);

group_uniforms altitude;
// low|mid、mid|high、high|summit 的分界海拔（米）与各自的过渡半宽；噪声让过渡交错（0 = 平滑渐变）
uniform vec3 band_edges = vec3(120.0, 350.0, 650.0);
uniform float band_blend = 40.0;
uniform float band_noise : hint_range(0.0, 2.0) = 1.0;
// 交错边界的软硬（段坐标里的半宽；默认只有抗锯齿的 1 像素，调大就变成叠化）
uniform float band_soft : hint_range(0.0, 0.5) = 0.0;
// 城镇平地 → 坡的过渡海拔（米）：路沿 foot（石板路）→ low、岩块 foot（土层卵石）→ low 都用它
uniform vec2 foot_alt = vec2(0.3, 2.5);

group_uniforms band;
// 瓶足饰带顶的深度（米，垂直地表量）：山坡上 / 城镇平地；饰带高；城镇 → 山坡的深度过渡（相对山脚弧长 foot_s 的范围）
// 山坡上 = 路沿 + 两层岩块（地表截面贴图里第二层岩块的中段），城镇 = 路沿 + 一层多
uniform float band_m = 2.75;
uniform float foot_band_m = 2.75;
uniform float band_h_m = 0.8;
// 饰带底色：陶土面 → 路沿色之间的位置（0 = 和岩块一样的陶土色）
uniform float band_bg_k = 0.3;
uniform vec2 band_ramp = vec2(-4.0, 26.0);
// 山脚的弧长（WorldView 设 = World.s_foot）；纹样在 foot_s + band_switch_m 处整格地从棕榈叶纹换成光芒纹
uniform float foot_s = 0.0;
uniform float band_switch_m = 6.0;
// 黑釉里饰带下方那道细线（离饰带底多少米、浓度）
uniform float glaze_line_m = 0.22;
uniform float glaze_line_a = 0.5;

group_uniforms lines;
// 分档线、饰带框线的宽（逻辑像素）
uniform float line_px = 1.4;
uniform float frame_px = 2.2;
// 远处（拉远时）贴图里的细节压低对比：每像素多少米时开始、到底；到底时贴图明暗保留多少
uniform vec2 far_mpp = vec2(0.02, 0.06);
uniform float far_contrast = 0.6;
group_uniforms;

varying vec2 wpos;

void vertex() {
	wpos = vec2(VERTEX.x, -VERTEX.y) * 0.01;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// 三档插值：白天 → 黄昏余晖 → 夜
vec3 tri(vec4 a, vec4 b, vec4 c, float k) {
	return k < 0.5 ? mix(a.rgb, b.rgb, k * 2.0) : mix(b.rgb, c.rgb, k * 2.0 - 1.0);
}

// 逻辑像素距离 → 覆盖率（宽 w 逻辑像素的线，1 个实际像素抗锯齿）
float cov(float dist_px, float w) {
	return clamp((w * 0.5 - dist_px) * px_scale + 0.5, 0.0, 1.0);
}

// 海拔 → 连续的段坐标（0..3：low、mid、high、summit）
float band_of(float alt) {
	return smoothstep(band_edges.x - band_blend, band_edges.x + band_blend, alt)
		+ smoothstep(band_edges.y - band_blend, band_edges.y + band_blend, alt)
		+ smoothstep(band_edges.z - band_blend, band_edges.z + band_blend, alt);
}

// 两段之间的交错边界：段坐标的小数部分 f（已加噪声）过 0.5 处一刀换图（抗锯齿 1 像素），不叠化——
// 两张线稿叠在一起只会是重影。返回 (权重, 边界到这里的像素距离)，边界上另刻一道线（两种岩体的接触线）
vec2 interlock(float f) {
	float h = (f - 0.5) * 2.0;
	float g = max(1e-5, fwidth(h));
	float w = max(band_soft, g);
	float edge = (f > 0.0 && f < 1.0) ? abs(h) / g : 1e5;
	return vec2(smoothstep(-w, w, h), edge);
}

void fragment() {
	float s = UV.x;
	float d = UV.y;
	float th = (COLOR.g - 0.5) * PI;
	float along = s - d * sin(th);
	float perp = d * cos(th);
	// 地表海拔（竖直往上 d 米就是地表）
	float alt = wpos.y + d;
	// perp 方向每逻辑像素多少米。导数都在分支外取
	float gp = max(1e-5, length(vec2(dFdx(perp), dFdy(perp)))) * px_scale;

	vec3 c_fill = tri(day_fill, dusk_fill, night_fill, night_k);
	vec3 c_shade = tri(day_shade, dusk_shade, night_shade, night_k);
	vec3 c_ink = tri(day_ink, dusk_ink, night_ink, night_k);
	vec3 c_lip = tri(day_lip, dusk_lip, night_lip, night_k);
	vec3 c_glaze = tri(day_glaze, dusk_glaze, night_glaze, night_k);

	// —— 城镇 → 山坡：饰带深度过渡（固定深度：陡坡、拉远都不变）——
	float slope_k = smoothstep(foot_s + band_ramp.x, foot_s + band_ramp.y, along);
	float btop = mix(foot_band_m, band_m, slope_k);

	// —— 海拔段（交错）——
	// 噪声只沿坡面变（不随深度变）：换岩的边界是一道道竖着穿过整个岩层的缝，不会在薄薄的岩层里冒出一块圆斑
	float bn = (vnoise(vec2(along / 9.0, 0.5)) - 0.5) * 2.0 * band_blend * band_noise;
	float bb = smoothstep(foot_alt.x, foot_alt.y, alt + bn * (foot_alt.y - foot_alt.x) * 0.5 / max(1.0, band_blend)) + band_of(alt + bn);
	float bi = min(floor(bb), 3.0);
	vec2 bil = interlock(bb - bi);
	float layer = bi + step(0.5, bil.x);

	// —— 采样（全部在分支外：隐式 LOD 需要导数）——
	float mpp = max(1e-5, max(fwidth(along), fwidth(perp)));
	float tv = (perp + top_surface_m) / top_h_m;
	// 竖向不平铺：夹住，免得地表上方透明区的顶行和贴图底部的岩石（repeat）在双线性过滤时混出一道线
	vec4 ttop = texture(top_tex, vec3(along / top_period_m, clamp(tv, 0.004, 0.996), layer));
	float dz = (perp - (top_h_m - top_surface_m)) / deep_h_m;
	float drow = floor(dz);
	vec4 tdeep = texture(deep_tex, vec3((along + h21(vec2(drow, 3.7)) * deep_period_m) / deep_period_m, fract(dz), layer));
	vec4 bt = texture(band_tex, vec3(0.0));
	float per = band_h_m * float(textureSize(band_tex, 0).x) / max(1.0, float(textureSize(band_tex, 0).y));
	float cellb = floor(along / per);
	float blayer = (cellb + 0.5) * per < foot_s + band_switch_m ? 1.0 : 0.0;
	bt = texture(band_tex, vec3(along / per, (perp - btop) / band_h_m, blayer));
	vec2 band = vec2(bt.r / max(bt.a, 1e-3), bt.a);

	// —— 岩体颜色：地表截面（tv ≤ 1）或深处岩层 ——
	vec4 tx = tv <= 1.0 ? ttop : tdeep;
	vec3 day = tx.rgb;
	float l = dot(day, vec3(0.299, 0.587, 0.114));
	day = mix(vec3(l), day, day_sat) * day_gain;
	// 拉远：压低贴图明暗的对比（大气透视，远看不满屏碎纹）
	float fk = smoothstep(far_mpp.x, far_mpp.y, mpp);
	vec3 mean = mix(c_fill, c_shade, 0.35);
	day = mix(day, mix(mean, day, far_contrast), fk);
	// 黄昏 / 夜：亮度 → 调色板（墨 → 背光 → 陶土面 → 路沿）
	float lt = clamp((l - 0.08) / 0.62, 0.0, 1.0);
	vec3 dusk_c = lt < 0.5 ? mix(dusk_ink.rgb, dusk_shade.rgb, lt * 2.0) : mix(dusk_shade.rgb, mix(dusk_fill.rgb, dusk_lip.rgb, lt * 0.6), lt * 2.0 - 1.0);
	vec3 night_c = lt < 0.5 ? mix(night_ink.rgb, night_shade.rgb, lt * 2.0) : mix(night_shade.rgb, mix(night_fill.rgb, night_lip.rgb, lt * 0.6), lt * 2.0 - 1.0);
	vec3 rock = night_k < 0.5 ? mix(day, dusk_c, night_k * 2.0) : mix(dusk_c, night_c, night_k * 2.0 - 1.0);
	// 山顶：路沿面（最亮的那档）染成雪
	float snow_k = smoothstep(band_edges.z - band_blend, band_edges.z + band_blend * 2.0, alt) * smoothstep(0.62, 0.8, l) * step(tv, 0.32);
	rock = mix(rock, snow.rgb * mix(vec3(1.0), night_lip.rgb / max(day_lip.rgb, vec3(1e-3)), night_k), snow_k);

	vec3 col;
	float alpha = 1.0;
	if (perp < btop) {
		col = rock;
		// 两种岩体的交界刻一道接缝（像两块岩石拼在一起）
		col = mix(col, c_ink, cov(bil.y, line_px) * step(0.0, perp) * 0.85);
		// 地表截面和深处岩层之间、深处每层岩带之间的水平岩缝
		float jd = min(abs(perp - (top_h_m - top_surface_m)), perp > top_h_m - top_surface_m ? abs(fract(dz + 0.5) - 0.5) * deep_h_m : 1e3);
		col = mix(col, c_ink, clamp((joint_w_m * 0.5 - jd) / mpp + 0.5, 0.0, 1.0));
		// 地表上方：贴图的 alpha（草丛、碎石）
		if (perp < 0.0) {
			alpha = tv >= 0.0 ? ttop.a : 0.0;
		}
	} else if (perp < btop + band_h_m) {
		// —— 瓶足饰带：陶土底（陶土面往路沿色提 band_bg_k）+ 黑色纹样 ——
		col = mix(mix(c_fill, c_lip, band_bg_k), c_glaze, band.y * (1.0 - band.x));
		col = mix(col, c_lip, band.y * band.x);
	} else {
		// —— 黑釉 ——
		col = c_glaze;
		col = mix(col, c_lip, cov(abs(perp - btop - band_h_m - glaze_line_m) / gp, line_px) * glaze_line_a);
	}
	// 饰带上下框线
	float fr = max(cov(abs(perp - btop) / gp, frame_px), cov(abs(perp - btop - band_h_m) / gp, frame_px));
	col = mix(col, c_ink, fr);
	// 白天贴图自带颜色，不再乘陶土色调；时刻染色照乘
	COLOR = vec4(col * tod_tint.rgb, alpha);
}
