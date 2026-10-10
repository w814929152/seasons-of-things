class_name TestHudRefresh
extends RefCounted
##
## HUD 刷新专项 —— 用于独立裁决「工程侧称 HUD 文本滞后是测试驱动方式所致」这一争议。
##
## 判据（GDD §5 设计红线）：L1 时砂 / L2 背包**必须常驻可见**。
## 若 HUD 在真实玩家流程中确实不刷新 → 严重缺陷 → 质量门 FAIL。
##
## 本组做三件事：
##   A. 全程走 LevelManager 的**玩家入口**（_try_shift / _do_take / _do_use /
##      _do_place / _walk_to），每一步核对 HUD 显示的时砂与背包数字。
##      这是最接近真实操作的路径（_input() 里调的就是这几个函数）。
##   B. 反向验证工程侧的解释：直接调 tc.shift()（逻辑层）后 HUD 是否仍刷新。
##      —— 若仍刷新，则「测试直接调 tc.shift() 导致 HUD 滞后」的解释不成立。
##   C. 定位 headless 场景测试的真正陷阱：LevelManager._transition 冷却
##      在 headless 下没有 _process 帧来递减，连续 _try_shift() 会被静默吞掉。
##      （这才会让用例看到「时砂没减」「背包没变」这类滞后数字。）
##

static func _mk(h: TestHarness, root: Node) -> Array:
	var lm = preload("res://src/level/level_manager.gd").new()
	root.add_child(lm)
	lm.start_level()
	var hud = preload("res://src/ui/hud.gd").new()
	root.add_child(hud)
	# 依赖 test_main.gd 里的 `await process_frame`：此后 root 已 ready，
	# add_child 会正常触发 hud._ready()（子控件由此建立），与真实运行时一致。
	h.ck(hud.is_node_ready(), "HUD 已就绪（_ready 已由引擎触发）")
	hud.bind_level(lm)
	return [lm, hud]


static func _glass(hud) -> String:
	return hud._glass._num.text


## 背包容量现在由**背包面板自己的铭文**承担（原先是抄在底部状态行里的重复信息）
static func _pack(hud) -> String:
	return hud._pack._cap.text


static func _status(hud) -> String:
	return hud._status.text


## HUD 是否同时满足「硬编码期望值」与「与 tc 真相一致」
static func _chk(h, hud, lm, sand: int, pack: int, tag: String) -> void:
	var cap: int = lm.tc.hourglass_cap
	var want_glass: String = "%d / %d" % [sand, cap]
	h.eq(_glass(hud), want_glass, "%s：HUD 时砂 = %s" % [tag, want_glass])
	h.eq(lm.tc.hourglass, sand, "%s：tc 真相 时砂 = %d" % [tag, sand])
	var want_pack: String = "背包 %d/%d" % [pack, lm.tc.inventory.cap]
	h.eq(_pack(hud), want_pack, "%s：背包面板铭文 = %s" % [tag, want_pack])
	h.eq(lm.tc.inventory.size(), pack, "%s：tc 真相 背包 = %d" % [tag, pack])
	# 状态行不该再重复时刻 / 时砂 / 背包 —— 只留独有信息（坐标 / 面向）
	h.ck(not _status(hud).contains("背包") and not _status(hud).contains("时砂"),
		"%s：状态行不再重复时砂 / 背包" % tag)


static func run(h: TestHarness, root: Node) -> void:
	h.suite("HUD 刷新专项（争议裁决）")

	# ================= A. 真实玩家入口全程核对 =================
	var pair := _mk(h, root)
	var lm = pair[0]
	var hud = pair[1]

	h.eq(lm.tc.current_t, 2, "A0：初始 T2")
	_chk(h, hud, lm, 12, 0, "A0 绑定后")

	# 1) 切 T1（玩家入口）
	lm._transition = 0.0
	lm._try_shift(-1)
	h.eq(lm.tc.current_t, 1, "A1：已切到 T1")
	_chk(h, hud, lm, 11, 0, "A1 切时刻后")

	# 2) 取钥匙
	lm.tc.player_pos = Vector2i(3, 3)
	lm._facing = Vector2i(0, -1)
	lm._do_take()
	_chk(h, hud, lm, 11, 1, "A2 持取钥匙后")

	# 3) 开铁栅
	lm.tc.player_pos = Vector2i(6, 1)
	lm._facing = Vector2i(1, 0)
	lm._do_use()
	_chk(h, hud, lm, 11, 0, "A3 开锁后（钥匙留锁孔）")

	# 4) 取砝码
	lm.tc.player_pos = Vector2i(1, 3)
	lm._facing = Vector2i(0, -1)
	lm._do_take()
	_chk(h, hud, lm, 11, 1, "A4 持取砝码后")

	# 5) 拔藤
	lm.tc.player_pos = Vector2i(7, 1)
	lm._facing = Vector2i(1, 0)
	lm._do_use()
	_chk(h, hud, lm, 11, 1, "A5 拔藤后")

	# 6) 走过去放砝码（玩家入口：走路更新朝向 → 按 Q）
	lm._teleport_to(Vector2i(9, 1))
	lm._teleport_to(Vector2i(9, 2))
	lm._do_place()
	_chk(h, hud, lm, 11, 0, "A6 放置砝码后")

	# 7) 切回 T2
	lm._transition = 0.0
	lm._try_shift(1)
	h.eq(lm.tc.current_t, 2, "A7：已切回 T2")
	_chk(h, hud, lm, 10, 0, "A7 切回 T2 后")

	# 8) 走到出口通关
	lm._teleport_to(Vector2i(11, 1))
	h.ck(lm.tc.won, "A8：通关")
	_chk(h, hud, lm, 10, 0, "A8 通关时")

	# 9) 撤销（UI 按钮路径 _on_undo）
	# 栈顶是「走到出口」这一步（walk_to 也会入撤销栈），所以撤销先回滚坐标
	hud._on_undo()
	h.eq(lm.tc.player_pos, Vector2i(9, 2), "A9：撤销一步 → 坐标回滚到 (9,2)")
	h.eq(lm.tc.hourglass, 10, "A9：撤销移动不改变时砂（移动不计步）→ 10")
	h.eq(_glass(hud), "10 / 12", "A9：HUD 时砂随撤销刷新为 10 / 12")

	# 10) 重置（UI 按钮路径 _on_reset）
	hud._on_reset()
	_chk(h, hud, lm, 12, 0, "A10 重置后")

	# ================= B. 反向验证工程侧的解释 =================
	# 若「测试直接调 tc.shift() 而非走输入事件」真会让 HUD 滞后，
	# 那么下面这条必然失败；反之则解释不成立。
	var pair2 := _mk(h, root)
	var lm2 = pair2[0]
	var hud2 = pair2[1]
	lm2.tc.shift(-1)                        # ★ 直接调逻辑层，不经过 _try_shift
	h.eq(lm2.tc.current_t, 1, "B1：直接 tc.shift() 生效 → T1")
	h.eq(_glass(hud2), "11 / 12", "B1：★ 直接调 tc.shift() 后 HUD 仍刷新为 11 / 12")
	lm2.tc.player_pos = Vector2i(3, 3)
	lm2.tc.take(&"KEY")                     # ★ 直接调逻辑层
	h.ck(_pack(hud2) == "背包 1/2", "B2：★ 直接调 tc.take() 后背包面板仍刷新为 背包 1/2")

	# ================= C. headless 场景测试的真正陷阱 =================
	var pair3 := _mk(h, root)
	var lm3 = pair3[0]
	var hud3 = pair3[1]
	lm3._transition = 0.0
	lm3._try_shift(-1)
	h.eq(lm3.tc.current_t, 1, "C1：第一次 _try_shift 生效 → T1")
	h.eq(_glass(hud3), "11 / 12", "C1：HUD 时砂 11 / 12（HUD 并未滞后）")

	# 立刻再切一次：_transition = 0.35 s 冷却（GDD §2.3 L6），
	# headless 下没有 _process 帧来递减 ⇒ 被静默吞掉
	lm3._try_shift(-1)
	h.eq(lm3.tc.current_t, 1, "C2：★ 第二次 _try_shift 被冷却吞掉（仍停在 T1）")
	h.eq(_glass(hud3), "11 / 12", "C2：★ 于是 HUD 停在 11/12 —— 表现为『滞后』")

	# 模拟真实游戏的一帧：_process 递减冷却后再切，就正常了
	lm3._process(0.4)
	lm3._try_shift(-1)
	h.eq(lm3.tc.current_t, 0, "C3：模拟 _process(0.4) 冷却清零后再切 → T0（真实游戏有帧循环）")
	h.eq(_glass(hud3), "10 / 12", "C3：HUD 时砂 10 / 12（真实游戏路径下 HUD 不滞后）")

	for p in [pair, pair2, pair3]:
		root.remove_child(p[0])
		root.remove_child(p[1])
		p[0].free()
		p[1].free()
