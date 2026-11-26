extends SchoolView
## 雅典娜 · 城邦：方阵冲锋——每次远程碾压，在物件右边闪过一个持盾步兵剪影，0.4 秒内往下坡冲 4 米并淡出。


func world(c: CanvasItem, _wv: WorldView, sim: SimGame, st: Dictionary, _vr: Vector2) -> void:
	if sim.phase != &"night":
		return
	var key: StringName = first_key([&"spartan_pusher", &"hoplite"])
	if key == &"":
		return
	for ch: Dictionary in st.get("charges", []):
		var k: float = float(ch["t"]) / 0.4
		var x: float = float(ch["x"]) - k * 4.0
		WorldView.spr_ground(c, sim.world, key, x, 2.1, 0.85 * (1.0 - k), true, 0.0, true)
