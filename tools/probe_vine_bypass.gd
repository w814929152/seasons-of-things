extends SceneTree
##
## 探针：藤蔓是不是硬性咽喉？（回归验证 P3 不可绕过）
##
## 背景：曾经 is_blocked() 对 VINE 只判 BLOCKING，而 T0(SPROUT)/T1(YOUNG)
##   的标签只有 PULLABLE ⇒ 幼苗/幼藤不阻挡。玩家可切到「新光·昼」直接穿过 (8,1)，
##   切回「现在」人已在东区 ⇒ 不必拔藤即可通关，P3 谜题被架空。
## 现已给 SPROUT/YOUNG 补 BLOCKING。本探针跑两条对照路线，证明：
##   甲路线（不拔藤）走不到东区；乙路线（拔藤）才通。
##
## 运行：godot_console --headless --path . --script res://tools/probe_vine_bypass.gd
##

const Harness = preload("res://tests/harness.gd")

const VINE_CELL := Vector2i(8, 1)
const WEST := Vector2i(1, 3)          # 西厅（砝码旁）
const EAST := Vector2i(9, 2)          # 东区（压力板正北）
const GATE_WEST := Vector2i(6, 1)     # 大门西邻，可对铁栅 USE
const CHOKE_WEST := Vector2i(7, 1)    # 大门格本身，可对藤蔓 USE
const EXIT := Vector2i(11, 1)


func _initialize() -> void:
	_bar("=")
	print("探针：藤蔓是否为硬性咽喉")
	_bar("=")

	_show_forms()

	var a := _route(Harness.new_game(), "甲 · 全程不拔藤", false)
	var b := _route(Harness.new_game(), "乙 · 拔掉藤蔓", true)

	_bar("=")
	print("对照结论")
	_bar("=")
	print("   甲（不拔藤）抵达东区 = %-5s   通关 = %s" % [str(a.arrived), str(a.won)])
	print("   乙（拔 藤）抵达东区 = %-5s   通关 = %s" % [str(b.arrived), str(b.won)])
	print("")
	if not a.arrived and not a.won and b.arrived and b.won:
		print("   ✓ 藤蔓是硬性咽喉：不拔过不去，拔了才通。P3 谜题成立。")
	else:
		print("   ✗ 异常：预期的对照关系不成立，请检查 VINE 的 BLOCKING 标签。")
	print("")
	quit(0)


func _bar(ch: String, n: int = 58) -> void:
	print(ch.repeat(n))


func _show_forms() -> void:
	var tc: TimeController = Harness.new_game()
	var vine := tc.level.get_entity(&"VINE")
	print("【藤蔓四时刻形态与阻挡】")
	for t in 4:
		var s := tc.resolve_state(vine, t)
		print("   T%d  form=%-8s  tags=%-26s  is_blocked(8,1)=%s" % [
			t, String(s.form), str(s.tags), str(tc.is_blocked(VINE_CELL, t))])
	print("")


## 跑一条路线，返回 {arrived, won}
func _route(tc: TimeController, title: String, pull_vine: bool) -> Dictionary:
	print("──────────────────────────────────────────────")
	print("【%s】" % title)
	print("──────────────────────────────────────────────")

	tc.shift(-1)                                        # T2 → T1
	print("  切到 T1（时砂 %d）" % tc.hourglass)

	tc.player_pos = Vector2i(3, 3)
	tc.take(&"KEY")
	print("  取崭新钥匙            → %s" % String(tc.inventory.top().form))

	tc.player_pos = GATE_WEST
	tc.use(&"GATE")
	print("  开铁栅门              → (7,1) 可通行 = %s" % str(not tc.is_blocked(Vector2i(7, 1), 1)))

	tc.player_pos = WEST
	tc.take(&"WEIGHT")
	print("  取黄铜砝码            → %s" % String(tc.inventory.top().form))

	# --- 拔藤（乙路线才有）---
	if pull_vine:
		tc.player_pos = CHOKE_WEST
		var ok: bool = tc.use(&"VINE")
		print("  站在 (7,1) 拔藤       → %s（removed=%s）" % [
			str(ok), str(tc.resolve_state(tc.level.get_entity(&"VINE"), 1).removed)])
	else:
		tc.player_pos = CHOKE_WEST
		print("  ★ 不拔藤，站在 (7,1) 尝试东进")

	# --- 关键：两条路线起点相同（都贴着咽喉口），只差拔没拔藤；只用寻路，不瞬移 ---
	tc.player_pos = CHOKE_WEST
	var path: Array = tc.find_path(CHOKE_WEST, EAST)
	print("  寻路 %s → %s ： %d 格 %s" % [CHOKE_WEST, EAST, path.size(), str(path)])
	tc.walk_to(EAST)
	var arrived: bool = tc.player_pos == EAST
	print("  实走结果              → 到达 %s   抵达东区 = %s" % [str(tc.player_pos), str(arrived)])

	if not arrived:
		print("  ✗ 走不过去 —— 咽喉堵死。")
		if not pull_vine:
			print("  ⇒ 不拔藤无法进入东区，通关路径被截断。")
		return {"arrived": false, "won": false}

	# --- 走到了东区，继续收尾 ---
	tc.place(Vector2i(9, 3))
	print("  放砝码上压力板        → grate_open(T2) = %s" % str(tc.grate_open(2)))

	tc.shift(1)                                         # → T2「现在」
	print("  切回 T2（时砂 %d）    → 位置 %s" % [tc.hourglass, str(tc.player_pos)])

	tc.walk_to(EXIT)
	var won: bool = tc.won
	print("  走向出口 (11,1)       → 到达 %s   通关 = %s" % [str(tc.player_pos), str(won)])
	return {"arrived": true, "won": won}
