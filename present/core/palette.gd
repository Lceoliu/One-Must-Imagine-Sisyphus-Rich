class_name Palette
## 全局配色（只读常量）。出处：config.js PALETTE / GOLD / GOLD_HI / NIGHT_TINT；style.css :root；render.js:564 HUD_PAL；events.js:75 TIERS 颜色。
## 主题（theme_builder）、HUD、世界层都从这里取色，不在各处硬编码。
## 网页里的 rgba(...) 换成带 alpha 的 Color；Color 分量是 sRGB 值，与 canvas 一致。

# —— config.js：世界的昼/夜配色 ——
const DAY: Dictionary = {
	"sky_top": Color("#d97a3c"), "sky_bot": Color("#b4521d"), "far": Color("#9c4518"), "far2": Color("#a94f1e"),
	"ground": Color("#120c0a"), "line": Color("#e9d3a8"), "line_dim": Color(233.0 / 255.0, 211.0 / 255.0, 168.0 / 255.0, 0.35),
	"frame": Color("#120c0a"), "frame_line": Color("#c8642a"), "text": Color("#f1e3c8"), "sun": Color("#120c0a"),
}
const NIGHT: Dictionary = {
	"sky_top": Color("#132449"), "sky_bot": Color("#3f5f99"), "far": Color("#1b2e5a"), "far2": Color("#26407a"),
	"ground": Color("#05070f"), "line": Color("#8fb0d8"), "line_dim": Color(143.0 / 255.0, 176.0 / 255.0, 216.0 / 255.0, 0.3),
	"frame": Color("#05070f"), "frame_line": Color("#2c4a80"), "text": Color("#dfe8f5"), "sun": Color("#dfe8f5"),
}
const GOLD: Color = Color("#f0b93a")
const GOLD_HI: Color = Color("#ffe08a")
const NIGHT_TINT: Color = Color("#9db8e0")      ## 夜里精灵的米色刻线乘成冷蓝（= project.godot 的全局 uniform night_tint）

# —— style.css :root ——
const CLAY: Color = Color("#c8642a")
const CLAY_HI: Color = Color("#d97a3c")
const CLAY_DK: Color = Color("#8a3f17")
const BLACK: Color = Color("#120c0a")
const INK: Color = Color("#1d0f08")
const CREAM: Color = Color("#f1e3c8")
const LINE: Color = Color("#e9d3a8")
const MUTED: Color = Color("#b9a58c")
const RED: Color = Color("#ff8a6a")
const NIGHT_BG: Color = Color("#0b1328")        ## css --night

# —— gods/util.js 的常用色 ——
const NIGHT_CREAM: Color = Color("#dfe8f5")
const TERRA: Color = Color("#b0705a")

# —— render.js:564 HUD_PAL：白天黑釉陶片 ↔ 夜里月光蓝釉 ——
const HUD_DAY: Dictionary = {
	"ink": Color("#120c0a"), "cream": Color("#f1e3c8"), "dim": Color(241.0 / 255.0, 227.0 / 255.0, 200.0 / 255.0, 0.66),
	"line": Color("#e9d3a8"), "line_dim": Color(233.0 / 255.0, 211.0 / 255.0, 168.0 / 255.0, 0.32),
	"edge": Color("#c8642a"), "core": Color("#5e2a10"), "glaze_top": Color("#2e1d14"), "glaze_bot": Color("#0e0806"),
	"track": Color("#24160f"), "fill": Color("#c8642a"), "inlay": Color("#d27a3e"),
}
const HUD_NIGHT: Dictionary = {
	"ink": Color("#05070f"), "cream": Color("#dfe8f5"), "dim": Color(223.0 / 255.0, 232.0 / 255.0, 245.0 / 255.0, 0.64),
	"line": Color("#8fb0d8"), "line_dim": Color(143.0 / 255.0, 176.0 / 255.0, 216.0 / 255.0, 0.3),
	"edge": Color("#4a6aa6"), "core": Color("#0f1d3d"), "glaze_top": Color("#1b305e"), "glaze_bot": Color("#07102a"),
	"track": Color("#0a1430"), "fill": Color("#3f5f99"), "inlay": Color("#6f8fc8"),
}

# —— events.js:75 TIERS：神龛四档颜色（黄铜 / 白银 / 黄金 / 神话）——
const TIER_COLORS: Array[Color] = [Color("#9a7a55"), Color("#c9c4b8"), Color("#f0b93a"), Color("#ffe08a")]


## 世界配色按 night_k（0 = 白天，1 = 夜）混合；key 见 DAY/NIGHT。
static func world(key: String, night_k: float) -> Color:
	var a: Color = DAY[key]
	var b: Color = NIGHT[key]
	return a.lerp(b, clampf(night_k, 0.0, 1.0))


## HUD 配色按 mix 混合（architecture §9：HudPal.lerp(day, night, mix)，不再画两遍）。
static func hud(key: String, mix: float) -> Color:
	var a: Color = HUD_DAY[key]
	var b: Color = HUD_NIGHT[key]
	return a.lerp(b, clampf(mix, 0.0, 1.0))
