class_name TestUndoRestore
extends RefCounted
##
## 验收 7：撤销 10 次后状态与初始态逐字段一致；时砂无负数、全额返还。
## 同时覆盖「重置时刻」与「撤销栈见底后不报错」。
##

static func run(h: TestHarness) -> void:
	h.suite("撤销复原 / 时砂账本")

	var tc := TestHarness.new_game()
	h.eq(tc.hourglass, 12, "初始时砂 = 12")
	h.eq(tc.current_t, 2, "初始时刻 = T2")
	h.eq(tc.player_pos, Vector2i(3, 5), "初始坐标 (3,5)")
	var pristine := tc.export_state()                     # ★ 关卡「出厂态」，reset() 应回到这里

	tc.player_pos = Vector2i(3, 1)                        # 站位（移动不计步、不入撤销栈）
	var baseline := tc.export_state()                     # ★ 撤销 10 次应当回到这一态

	# ---------- 执行 10 次真实操作 ----------
	var acted: int = 0
	var neg_seen := false

	if tc.take(&"KEY"): acted += 1
	tc.player_pos = Vector2i(6, 1)                        # 站位：大门西邻（布局放大后与钥匙台北邻不是同一格）
	if tc.use(&"GATE"): acted += 1                        # T1? 还在 T2 → 会折断
	tc.player_pos = Vector2i(3, 1)
	if tc.shift(-1): acted += 1                           # → T1
	if tc.take(&"KEY"): acted += 1
	tc.player_pos = Vector2i(6, 1)                        # 站位：大门西邻
	if tc.use(&"GATE"): acted += 1                        # 开锁
	tc.player_pos = Vector2i(1, 3)
	if tc.take(&"WEIGHT"): acted += 1
	tc.player_pos = Vector2i(9, 2)
	if tc.place(Vector2i(9, 3)): acted += 1
	tc.player_pos = Vector2i(7, 1)
	if tc.use(&"VINE"): acted += 1
	if tc.shift(1): acted += 1                            # → T2
	if tc.shift(-1): acted += 1                           # → T1

	h.eq(acted, 10, "已执行操作数 = 10（撤销同样 10 次，正好回到初始态）")
	h.eq(tc.hourglass, 9, "3 次切换后时砂 = 9")
	h.ck(tc.hourglass >= 0, "全过程时砂非负（当前 %d）" % tc.hourglass)

	# ---------- 撤销 10 次 ----------
	for i in 10:
		if not tc.undo_step():
			h.ck(false, "第 %d 次撤销失败（栈空了）" % (i + 1))
			neg_seen = true
	if not neg_seen:
		h.ck(true, "连续撤销 10 次全部成功")

	var diff := TimeController.state_diff(baseline, tc.export_state())
	h.ck(diff.is_empty(), "撤销后与初始态逐字段一致" + ("" if diff.is_empty() else "  diff=" + str(diff)))
	h.eq(tc.hourglass, 12, "撤销全额返还时砂 → 12")
	h.eq(tc.current_t, 2, "撤销回滚时刻 → T2")
	h.eq(tc.player_pos, Vector2i(3, 1), "撤销回滚坐标 → 回到首次操作前")
	h.eq(tc.overrides.size(), 0, "撤销清空全部 Override")
	h.eq(tc.inventory.size(), 0, "撤销清空背包")

	# ---------- 栈见底 ----------
	h.ck(not tc.can_undo(), "撤销栈已见底")
	h.ck(not tc.undo_step(), "栈空时撤销返回 false（不报错）")

	# ---------- 重置 ----------
	if tc.shift(-1):
		pass
	tc.player_pos = Vector2i(3, 1)
	tc.take(&"KEY")
	tc.player_pos = Vector2i(3, 1)
	tc.reset()
	diff = TimeController.state_diff(pristine, tc.export_state())
	h.ck(diff.is_empty(), "重置后与出厂态逐字段一致" + ("" if diff.is_empty() else "  diff=" + str(diff)))
	h.eq(tc.hourglass, 12, "重置全额返还时砂 → 12")
	h.eq(tc.player_pos, Vector2i(3, 5), "重置回滚坐标 → (3,5)")

	# ---------- 时砂耗尽不可切换 ----------
	var tc2 := TestHarness.new_game()
	var spent := 0
	while tc2.shift(-1 if tc2.current_t > 0 else 1):
		spent += 1
		if spent > 40:
			break
	h.ck(tc2.hourglass >= 0, "反复切换后时砂仍非负（剩余 %d，切了 %d 次）" % [tc2.hourglass, spent])
	h.eq(tc2.hourglass, 0, "时砂最终耗尽为 0")
	h.ck(not tc2.shift(1), "时砂耗尽后不可切换")
	h.ck(tc2.undo_step(), "时砂耗尽后仍可撤销")
	h.ck(tc2.hourglass > 0, "撤销后时砂返还（%d）" % tc2.hourglass)
