class_name ShadowDay
extends RefCounted
## 盘口的影子推演（docs/v05/feast-hub.md §4.3 ①）：拿玩家现在的存档复制一局，让"标准推石手"推一天，返回当天的最高海拔 H_bot。
## 标准推石手 = 机器人的白天策略（tests/bot/bot.gd）：每 6 拍按一次该按的键（约 5 次/秒），双掌就一直按住；不歇。
## 只在内存里跑，不发事件、不写存档；推完就 dispose。

const DT: float = 1.0 / 30.0
const MAX_FRAMES: int = 30 * 600


## persist：SimGame.persist()；meta：同一局的元进度（祖传、契约要算进去）
static func run(content: ContentDB, persist: Dictionary, meta: Dictionary) -> float:
	var p: Dictionary = persist.duplicate(true)
	var g: SimGame = SimGame.new(content, p, meta)
	g.fx.enabled = false
	g.hooks = {}
	g.demo = false
	g.start_day()
	var f: int = 0
	while g.phase == &"day" and f < MAX_FRAMES:
		# 剧情对话、祭坛演出：一律选第一项
		for k: int in 4:
			if g.modal == null:
				break
			g.answer(0)
		if g.modal == null:
			_press(g, f)
		g.tick(DT)
		f += 1
	var alt: float = g.max_alt
	g.dispose()
	return alt


static func _press(g: SimGame, f: int) -> void:
	if g.stats.hold_push:
		g.keys[&"R"] = true
		return
	if f % 6 != 0:
		return
	var k: StringName = &"R" if g.expect_key == &"R" else &"L"
	g.key_down(k)
	g.key_up(k)
