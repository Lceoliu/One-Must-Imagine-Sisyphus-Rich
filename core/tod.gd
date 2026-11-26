class_name Tod
## 一天里的时刻 tod（逐行移植 tod.js）：白天 0→1 对应 06:00→18:00；黄昏 1→1.06；夜 1.06→1.56（18:00 起每 0.5 = 6 小时）。
## 主控（sim）算出 tod，这里只负责换算成钟点和标签（HUD、剧情共用）。

const NOON: float = 0.5
const SUNSET: float = 0.94      # 17:15 日落


## 移植自 tod.js:7 isMorning。
static func is_morning(tod: float) -> bool:
	return tod < NOON


## 移植自 tod.js:12 clockOf(tod) → {h, m, text: "09:40", label: 上午|正午|下午|黄昏|夜}。
## 非有限数按正午处理（= `Number.isFinite(tod) ? tod : NOON`）。
static func clock_of(tod: float) -> Dictionary:
	if is_nan(tod) or is_inf(tod):
		tod = NOON
	var mins: float
	if tod <= 1.0:
		mins = 360.0 + maxf(0.0, tod) * 720.0
	else:
		mins = minf(1440.0, 1080.0 + (tod - 1.0) * 720.0)
	mins = floorf(mins)
	var h: int = floori(mins / 60.0)
	var m: int = int(mins) % 60
	var label: String
	if tod > 1.06:
		label = Loc.t("tod.night", "夜")
	elif tod >= SUNSET:
		label = Loc.t("tod.dusk", "黄昏")
	elif mins >= 705.0 and mins <= 735.0:          # 11:45–12:15
		label = Loc.t("tod.noon", "正午")
	else:
		label = Loc.t("tod.morning", "上午") if mins < 720.0 else Loc.t("tod.afternoon", "下午")
	return {"h": h, "m": m, "text": _pad(h) + ":" + _pad(m), "label": label}


static func _pad(n: int) -> String:
	return ("0" if n < 10 else "") + str(n)
