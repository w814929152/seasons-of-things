class_name TestDeadlockAndWin
extends RefCounted
##
## 验收 5：T1 站在 (11,1) 不通关（门扇没把手）；T2 站上 (11,1) 通关。
## 死锁谓词（GDD §7.1）：本关经设计**永不为真** —— 谓词要实现并测试；
## 这里用一个伪造的「不可能需求」反向验证谓词确实在工作（不是空实现）。
##

static func run(h: TestHarness) -> void:
	h.suite("通关判定 / 死锁谓词")

	# ---- 验收 5：只有 T2 能通关 ----
	var tc := TestHarness.new_game()
	var lv := tc.level
	var exit_cell := Vector2i(11, 1)

	var ts: Array[int] = [0, 1, 2, 3]
	for t in ts:
		tc.current_t = t
		tc.player_pos = exit_cell
		var expect: bool = (t == 2)
		h.eq(tc.evaluate_win(), expect,
			"验收5：站在 (11,1) 于 T%d %s" % [t, "通关" if expect else "不通关"])

	# 出口各形态的通行性
	tc.current_t = 1
	h.ck(tc.is_blocked(exit_cell, 1), "T1 出口 NO_HANDLE → 阻挡")
	tc.current_t = 3
	h.ck(tc.is_blocked(exit_cell, 3), "T3 出口 COLLAPSED → 阻挡")
	tc.current_t = 0
	h.ck(tc.is_blocked(exit_cell, 0), "T0 出口 NOT_BUILT → 阻挡")
	tc.current_t = 2
	h.ck(not tc.is_blocked(exit_cell, 2), "T2 出口 INTACT → 可通行")

	# ---- 死锁谓词：本关永不为真 ----
	var fresh := TestHarness.new_game()
	h.ck(not fresh.is_deadlock(), "初始态：非死局")

	# 走一遍标准解法，全程都不该是死局
	# 注：布局放大后，「钥匙台北邻 (3,1)」与「大门西邻 (6,1)」不再是同一格 → 取钥匙 / 开门各站各的。
	fresh.player_pos = Vector2i(3, 1)
	fresh.take(&"KEY")
	fresh.player_pos = Vector2i(6, 1)
	fresh.use(&"GATE")                       # T2 折断
	h.ck(not fresh.is_deadlock(), "钥匙折断后：仍非死局（T1 自愈）")
	fresh.shift(-1)
	fresh.player_pos = Vector2i(3, 1)
	fresh.take(&"KEY")
	fresh.player_pos = Vector2i(6, 1)
	fresh.use(&"GATE")
	h.ck(not fresh.is_deadlock(), "开门后：仍非死局")
	fresh.player_pos = Vector2i(1, 3)
	fresh.take(&"WEIGHT")
	fresh.player_pos = Vector2i(9, 2)
	fresh.place(Vector2i(9, 3))
	h.ck(not fresh.is_deadlock(), "砝码上板后：仍非死局")
	fresh.player_pos = Vector2i(7, 1)
	fresh.use(&"VINE")
	h.ck(not fresh.is_deadlock(), "拔藤后：仍非死局")

	# 反向验证：把需求改成一个不可能满足的标签 → 谓词必须为 true
	var saved: Array = fresh.level.requirements
	fresh.level.requirements = [{"tag": "IMPOSSIBLE_TAG", "target": "NOWHERE"}]
	h.ck(fresh.is_deadlock(), "伪造不可能需求 → 死锁谓词返回 true（谓词非空实现）")
	fresh.level.requirements = saved
	h.ck(not fresh.is_deadlock(), "恢复需求后 → 仍非死局")

	# ---- 时砂 / 背包容量约束 ----
	var cap := TestHarness.new_game()
	h.eq(cap.level.backpack_cap, 2, "背包容量 = 2")
	cap.player_pos = Vector2i(3, 3)
	cap.take(&"KEY")
	cap.shift(-1)
	cap.player_pos = Vector2i(1, 3)
	cap.take(&"WEIGHT")
	h.eq(cap.inventory.size(), 2, "背包装到 2 件")
	cap.shift(1)
	cap.player_pos = Vector2i(3, 3)
	h.ck(not cap.take(&"KEY"), "背包满时拒绝持取")
	h.eq(cap.inventory.size(), 2, "背包仍为 2 件")
