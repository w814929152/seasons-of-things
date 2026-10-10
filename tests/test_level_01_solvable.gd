class_name TestLevel01Solvable
extends RefCounted
##
## 关卡文档 §7「标准解法步骤表」的逐步自动化重放。
## 覆盖验收清单 1 / 2 / 3 / 4：
##   1) 按 §7 十步执行可通关
##   2) T2 用锈钥匙开门 → 折断，且 T1 钥匙仍存在（向过去不传播）
##   3) 砝码在 T1 放上压力板 → T2 闸门保持开启（正向传播）
##   4) 藤蔓在 T1 拔除 → T2 的 (8,1) 可通行
##

static func run(h: TestHarness) -> void:
	h.suite("关卡 01 · 标准解法重放（§7 十步）")

	var tc := TestHarness.new_game()
	var lv := tc.level
	var key := lv.get_entity(&"KEY")
	var gate := lv.get_entity(&"GATE")
	var vine := lv.get_entity(&"VINE")
	var weight := lv.get_entity(&"WEIGHT")

	# ---- 步 0：初始态 ----
	h.eq(tc.current_t, 2, "步0：初始时刻 T2")
	h.eq(tc.player_pos, Vector2i(3, 5), "步0：初始坐标 (3,5)")
	h.eq(tc.hourglass, 12, "步0：时砂 12")
	h.ck(tc.is_blocked(Vector2i(8, 1), 2), "步0：T2 藤蔓堵塞 (8,1)")
	h.ck(tc.is_blocked(Vector2i(7, 1), 2), "步0：T2 铁栅门关着")
	h.ck(tc.is_blocked(Vector2i(10, 2), 2), "步0：T2 闸门关着")

	# ---- 步 1：T2 取锈钥匙 ----
	tc.player_pos = Vector2i(3, 3)
	h.ck(tc.take(&"KEY"), "步1：T2 持取钥匙成功")
	h.eq(tc.inventory.size(), 1, "步1：背包 1 件")
	h.eq(String(tc.inventory.top().form), "KEY_RUSTY", "步1：冻结形态 = KEY_RUSTY")
	h.eq(tc.resolve_state(key, 2).pos, StateFrame.POS_VOID, "步1：T2 钥匙缺席（写入 pos=VOID）")

	# ---- 步 2：T2 用锈钥匙开铁栅 → 折断 ----
	tc.player_pos = Vector2i(6, 1)
	h.ck(tc.use(&"GATE"), "步2：USE 锈钥匙于铁栅（触发折断）")
	h.eq(tc.inventory.size(), 0, "步2：背包已空（钥匙断了）")
	h.eq(String(tc.resolve_state(key, 2).form), "KEY_BROKEN", "步2：T2 钥匙 = KEY_BROKEN")
	h.eq(tc.resolve_state(key, 2).pos, Vector2i(6, 1), "步2：残骸落在 (6,1)")
	# ★ 验收 2：向过去不传播
	var k1 := tc.resolve_state(key, 1)
	h.eq(String(k1.form), "KEY_NEW", "★ 验收2：T1 钥匙仍为 KEY_NEW")
	h.eq(k1.pos, Vector2i(3, 2), "★ 验收2：T1 钥匙仍在 (3,2)")
	h.ck(k1.available, "★ 验收2：T1 钥匙仍可取")
	h.ck(k1.tags.has("UNLOCKS:GATE"), "★ 验收2：T1 钥匙仍带 UNLOCKS:GATE")
	h.eq(String(tc.resolve_state(key, 0).form), "INGOT", "★ 验收2：T0 仍是金属锭")
	h.ck(not tc.resolve_state(gate, 1).open, "★ 验收2：T1 的门没被打开")

	# ---- 步 3：切到 T1 ----
	h.ck(tc.shift(-1), "步3：切换 T2 → T1")
	h.eq(tc.current_t, 1, "步3：当前时刻 = T1")
	h.eq(tc.hourglass, 11, "步3：时砂 11")

	# ---- 步 4：T1 取崭新钥匙 ----
	# 房间放大后「钥匙台北邻 (3,1)」与「大门西邻 (6,1)」不再同格，
	# 必须显式走回取钥匙站 (3,1)（原 10×5 布局里二者恰为同一格，故此处可省）。
	tc.player_pos = Vector2i(3, 1)
	h.ck(tc.take(&"KEY"), "步4：T1 持取钥匙")
	h.eq(String(tc.inventory.top().form), "KEY_NEW", "步4：冻结形态 = KEY_NEW")

	# ---- 步 5：T1 用新钥匙开铁栅 ----
	# 走到大门西邻 (6,1) 才能 USE 铁栅。
	tc.player_pos = Vector2i(6, 1)
	h.ck(tc.use(&"GATE"), "步5：USE 新钥匙于铁栅")
	h.ck(tc.resolve_state(gate, 1).open, "步5：T1 铁栅开启")
	h.ck(tc.resolve_state(gate, 2).open, "★ 验收3：T2 铁栅也开（正向传播）")
	h.ck(tc.resolve_state(gate, 3).open, "步5：T3 铁栅也开（正向传播）")
	h.ck(not tc.resolve_state(gate, 0).open, "★ T0 仍锁着（绝不向过去传播）")
	h.eq(tc.inventory.size(), 0, "步5：背包已空（钥匙留锁孔）")
	h.ck(not tc.is_blocked(Vector2i(7, 1), 1), "步5：T1 铁栅格可通行")

	# ---- 步 6：T1 取砝码 ----
	tc.player_pos = Vector2i(1, 3)
	h.ck(tc.take(&"WEIGHT"), "步6：T1 持取砝码")
	h.eq(String(tc.inventory.top().form), "WEIGHT_OK", "步6：冻结形态 = WEIGHT_OK")

	# ---- 步 7：T1 拔藤 ----
	tc.player_pos = Vector2i(7, 1)
	h.ck(tc.use(&"VINE"), "步7：USE 拔除藤蔓")
	h.ck(tc.resolve_state(vine, 1).removed, "步7：T1 藤蔓已清除")
	h.ck(tc.resolve_state(vine, 2).removed, "★ 验收4：T2 藤蔓已清除（正向传播）")
	h.ck(not tc.is_blocked(Vector2i(8, 1), 2), "★ 验收4：T2 的 (8,1) 可通行")
	h.ck(tc.is_blocked(Vector2i(8, 1), 0), "T0 藤蔓（SPROUT）同样阻挡 —— 拔除前四时刻皆不可过")

	# ---- 步 8：T1 把砝码放到压力板 ----
	tc.player_pos = Vector2i(9, 2)
	h.ck(tc.place(Vector2i(9, 3)), "步8：放置砝码于压力板 (9,3)")
	h.eq(tc.resolve_state(weight, 1).pos, Vector2i(9, 3), "步8：T1 砝码在压力板上")
	h.eq(tc.resolve_state(weight, 2).pos, Vector2i(9, 3), "★ 验收3：T2 砝码在压力板上（正向传播）")
	h.eq(String(tc.resolve_state(weight, 2).form), "WEIGHT_SEIZED", "★ 验收6：T2 形态仍是锈死 SEIZED")
	h.ck(tc.resolve_state(weight, 2).tags.has("IMMOVABLE"), "★ 验收6：T2 带 IMMOVABLE")
	h.ck(tc.plate_pressed(2), "★ 验收6：压力板仍 pressed（形态锁不影响压感）")
	h.ck(tc.grate_open(2), "★ 验收3：T2 闸门开启")
	h.ck(not tc.is_blocked(Vector2i(10, 2), 2), "★ 验收3：T2 闸门格可通行")

	# ---- 步 9：切回 T2 ----
	h.ck(tc.shift(1), "步9：切换 T1 → T2")
	h.eq(tc.current_t, 2, "步9：当前时刻 = T2")
	h.eq(tc.hourglass, 10, "步9：时砂 10（两次切换共耗 2）")
	h.ck(not tc.is_blocked(Vector2i(7, 1), 2), "步9 校验：GATE 开")
	h.ck(not tc.is_blocked(Vector2i(8, 1), 2), "步9 校验：VINE 不存在")
	h.ck(not tc.is_blocked(Vector2i(10, 2), 2), "步9 校验：GRATE 开")
	h.ck(not tc.is_blocked(Vector2i(11, 1), 2), "步9 校验：EXIT 完好可通行")

	# ---- 步 10：走到出口通关 ----
	var path := tc.find_path(Vector2i(9, 2), Vector2i(11, 1))
	h.ck(path.size() > 0, "步10：存在通往出口的路径（%d 格）" % path.size())
	tc.player_pos = Vector2i(9, 2)
	tc.walk_to(Vector2i(11, 1))
	h.eq(tc.player_pos, Vector2i(11, 1), "步10：抵达 (11,1)")
	h.ck(tc.won, "🏁 验收1：在 T2 站上出口 → 通关")
	h.eq(tc.hourglass, 10, "通关时时砂 = 10（最优耗 2）")

	h.ck(tc.overrides.size() > 0, "Override 日志非空（%d 条）" % tc.overrides.size())

	# ---- A5「状态冻结 / 携带」专项：手持物免疫时刻变化 ----
	var a5 := TestHarness.new_game()
	h.eq(String(a5.resolve_state(a5.level.get_entity(&"KEY"), 2).form), "KEY_RUSTY",
		"A5 对照：世界上的钥匙在 T2 已经是锈的")
	a5.shift(-1)                                        # → T1
	a5.player_pos = Vector2i(3, 3)
	h.ck(a5.take(&"KEY"), "A5：T1 取到崭新钥匙")
	var frozen_form := String(a5.inventory.top().form)
	h.eq(frozen_form, "KEY_NEW", "A5：拾取瞬间冻结为 KEY_NEW")
	a5.shift(1)                                         # → T2
	h.eq(String(a5.inventory.top().form), frozen_form,
		"★ A5：切到 T2 后手持物不变（世界变了，手上的没变）")
	a5.shift(1)                                         # → T3
	h.eq(String(a5.inventory.top().form), frozen_form, "★ A5：切到 T3 后手持物仍不变")
	a5.shift(-1)                                        # → T2
	a5.player_pos = Vector2i(6, 1)
	h.ck(a5.use(&"GATE"), "★ A5：把过去的新钥匙带回『现在』开门 → 成功")
	h.ck(a5.resolve_state(a5.level.get_entity(&"GATE"), 2).open, "A5：T2 铁栅已开")
	h.eq(a5.inventory.size(), 0, "A5：钥匙消耗（留在锁孔）")

	_vine_chokepoint(h)


## ─────────────────────────────────────────────────────────────────────────────
## 回归：藤蔓是**硬性咽喉**（锁死曾经的 P3 绕过漏洞）
##
## 曾经的缺陷：is_blocked() 对 VINE 只判 BLOCKING，而 T0(SPROUT)/T1(YOUNG)
## 的标签只有 PULLABLE ⇒ 幼苗/幼藤**不阻挡**。玩家于是可以：
##   切到「新光·昼」→ 直接走过 (8,1) 咽喉 → 在东区放好砝码 → 切回「现在」
## ⇒ 全程不必拔藤也能通关，P3 谜题被架空，§7「步 7 拔藤」沦为多余步骤。
## 现已给 SPROUT/YOUNG 补上 BLOCKING：**四形态一律阻挡，拔掉才通**。
## 本组同时锁死两件事：① 拔除前四时刻 (8,1) 全阻挡；② 拔除前寻路到不了东区。
## ─────────────────────────────────────────────────────────────────────────────
static func _vine_chokepoint(h: TestHarness) -> void:
	h.suite("关卡 01 · 藤蔓硬性咽喉（回归：P3 不可绕过）")

	# ---- 1) 拔除前，四时刻 (8,1) 全部阻挡 ----
	var f1 := TestHarness.new_game()
	var vine1 := f1.level.get_entity(&"VINE")
	for t in 4:
		h.ck(not f1.resolve_state(vine1, t).removed, "T%d：藤蔓未被拔除" % t)
		h.ck(f1.is_blocked(Vector2i(8, 1), t), "★ T%d：(8,1) 咽喉阻挡（幼苗/幼藤也不例外）" % t)
	# 阻挡与可拔是两件事：T0/T1 仍必须带 PULLABLE，否则拔不动
	h.ck(f1.resolve_state(vine1, 0).tags.has("PULLABLE"), "T0 仍带 PULLABLE（提防『加了 BLOCKING 却把可拔性弄丢』）")
	h.ck(f1.resolve_state(vine1, 1).tags.has("PULLABLE"), "T1 仍带 PULLABLE")
	h.ck(not f1.resolve_state(vine1, 2).tags.has("PULLABLE"), "T2 不可拔（TOO_THICK）")
	h.ck(f1.resolve_state(vine1, 2).tags.has("TOO_THICK"), "T2 带 TOO_THICK")

	# ---- 2) T1 · 铁栅已开 · 未拔藤 ⇒ 寻路到不了东区；拔藤后即通 ----
	var f2 := TestHarness.new_game()
	f2.shift(-1)                                        # T2 → T1
	f2.player_pos = Vector2i(3, 3)
	h.ck(f2.take(&"KEY"), "前提：T1 取到崭新钥匙")
	f2.player_pos = Vector2i(6, 1)
	h.ck(f2.use(&"GATE"), "前提：T1 开铁栅")
	h.ck(not f2.is_blocked(Vector2i(7, 1), 1), "前提：(7,1) 大门已开，可站")

	var cut: Array = f2.find_path(Vector2i(6, 1), Vector2i(9, 2))
	h.eq(cut.size(), 0, "★ 未拔藤 ⇒ 西厅 (6,1) 到不了东区 (9,2)")

	f2.player_pos = Vector2i(7, 1)                      # 站大门格，朝东够到 (8,1)
	h.ck(f2.use(&"VINE"), "T1 拔藤成功（形态带 PULLABLE）")
	h.ck(f2.resolve_state(f2.level.get_entity(&"VINE"), 1).removed, "T1 藤蔓 removed=true")
	var thru: Array = f2.find_path(Vector2i(6, 1), Vector2i(9, 2))
	h.ck(thru.size() > 0, "★ 拔藤后 ⇒ (6,1) → (9,2) 有路径（%d 格）" % thru.size())
	h.ck(not f2.is_blocked(Vector2i(8, 1), 2), "正向传播：T2 的 (8,1) 也通了")

	# ---- 3) 复现漏洞路径：未拔藤时「从大门走向咽喉」必须走不动 ----
	var f3 := TestHarness.new_game()
	f3.shift(-1)
	f3.player_pos = Vector2i(3, 3)
	f3.take(&"KEY")
	f3.player_pos = Vector2i(6, 1)
	f3.use(&"GATE")
	f3.player_pos = Vector2i(7, 1)
	var stuck_at := f3.player_pos
	f3.walk_to(Vector2i(9, 1))                          # 想穿过咽喉直奔东区
	h.eq(f3.player_pos, stuck_at, "★ 未拔藤时 (7,1) → (9,1) 走不动（坐标原地不动）")
	h.ck(not f3.resolve_state(f3.level.get_entity(&"VINE"), 1).removed, "此刻藤蔓仍未拔除")
	# ---- 4) 连带发现：T0 在数据上「可拔」，在玩法上**不可达** ----
	# (8,1) 的西侧唯一落脚点只有 (7,1)（北/南是墙，东是东区）。
	# 而 T0 的铁栅是锁的（开门结果只向前传播，不向过去传播）⇒ T0 站不上 (7,1)
	# ⇒ 「T0 也能拔藤」只是数据表上的一行，实际只有 T1 一条路。
	var f4 := TestHarness.new_game()
	f4.shift(-1)                                        # T1
	f4.shift(-1)                                        # T0
	h.eq(f4.current_t, 0, "前提：切到 T0")
	h.ck(not f4.resolve_state(f4.level.get_entity(&"GATE"), 0).open,
		"对照：T0 铁栅仍锁着（开锁结果不向过去传播）")
	h.ck(f4.is_blocked(Vector2i(8, 1), 0), "★ T0 藤蔓（SPROUT）也阻挡 —— 幼苗不再是空档")
	h.ck(f4.resolve_state(f4.level.get_entity(&"VINE"), 0).tags.has("PULLABLE"),
		"T0 数据层仍带 PULLABLE（可拔性未丢）")
	h.ck(f4.is_blocked(Vector2i(7, 1), 0), "T0 铁栅关着 ⇒ (7,1) 不可站")
	h.ck(f4.find_path(Vector2i(3, 3), Vector2i(6, 1)).size() > 0, "T0 玩家能走到 (6,1)")
	h.eq(f4.find_path(Vector2i(3, 3), Vector2i(7, 1)).size(), 0,
		"★ 但 T0 到不了 (7,1) —— 唯一的西侧落点 ⇒ T0 拔藤在玩法上不可达")
	# ⇒ 结论：取钥匙 / 搬砝码 / 拔藤 **全部唯一地只能发生在 T1**，通关唯一在 T2。
	#    本关因此不含「轻微多解」，标准解法的每一步都是强制的。


