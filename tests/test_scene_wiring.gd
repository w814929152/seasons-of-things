class_name TestSceneWiring
extends RefCounted
##
## 场景装配冒烟：LevelManager 能否真的把关卡建出来、把 5 个动词接上、
## 并把 resolve 结果派发给 9 个 TimeEntity 节点（渲染层）。
## 这一层**不**断言数值（数值由 core 用例断言），只断言「接线没断」。
##

static func run(h: TestHarness, root: Node) -> void:
	h.suite("场景装配 / LevelManager 接线")

	var lm = preload("res://src/level/level_manager.gd").new()
	if root != null:
		root.add_child(lm)
	lm.start_level()

	h.ck(lm.tc != null, "LevelManager 建出 TimeController")
	h.ck(lm.level != null, "LevelManager 载入关卡数据")
	h.eq(String(lm.level.level_id), "L01_FORGE_HALL", "关卡 ID = L01_FORGE_HALL")
	h.ck(lm.get_node_or_null("Environment") != null, "环境层已挂载")
	h.ck(lm.get_node_or_null("Player") != null, "玩家节点已挂载")
	var ents := lm.get_node_or_null("Entities")
	h.ck(ents != null, "道具容器已挂载")
	if ents != null:
		h.eq(ents.get_child_count(), 9, "生成 9 个 TimeEntity 节点")

	# 注意：GDScript 的 lambda 捕获是**按值**的，所以标志位要放在引用类型里
	var messages: Array[String] = []
	lm.level_message.connect(func(t: String) -> void: messages.append(t))
	var flags := {"won": false}
	lm.level_goal.connect(func() -> void: flags["won"] = true)

	# ---- 用 LevelManager 的动词接口重放标准解法 ----
	lm.tc.player_pos = Vector2i(3, 5)
	lm._facing = Vector2i(0, -1)

	# 切到 T1
	lm._transition = 0.0
	lm._try_shift(-1)
	h.eq(lm.tc.current_t, 1, "场景层：切到 T1")

	# 取钥匙：站 (3,3) 面朝 (3,2)
	lm.tc.player_pos = Vector2i(3, 3)
	lm._facing = Vector2i(0, -1)
	lm._do_take()
	h.eq(lm.tc.inventory.size(), 1, "场景层：持取钥匙成功")

	# 开门：站 (6,1) 面朝 (7,1)
	lm.tc.player_pos = Vector2i(6, 1)
	lm._facing = Vector2i(1, 0)
	lm._do_use()
	h.ck(lm.tc.resolve_state(lm.level.get_entity(&"GATE"), 1).open, "场景层：铁栅已开")

	# 取砝码：站 (1,3) 面朝 (1,2)... 上面是 (1,2)，用 (0,-1)
	lm.tc.player_pos = Vector2i(1, 3)
	lm._facing = Vector2i(0, -1)
	lm._do_take()
	h.eq(lm.tc.inventory.size(), 1, "场景层：持取砝码成功")

	# 放砝码：站 (10,2)? 闸门关着进不去 —— 改走 (9,2) 面朝 (9,3)
	lm.tc.player_pos = Vector2i(9, 2)
	lm._facing = Vector2i(0, 1)
	lm._do_place()
	h.eq(lm.tc.resolve_state(lm.level.get_entity(&"WEIGHT"), 1).pos, Vector2i(9, 3),
		"场景层：砝码已放上压力板")
	h.ck(lm.tc.plate_pressed(1), "场景层：压力板被压住")

	# 拔藤：站 (7,1) 面朝 (8,1)
	lm.tc.player_pos = Vector2i(7, 1)
	lm._facing = Vector2i(1, 0)
	lm._do_use()
	h.ck(lm.tc.resolve_state(lm.level.get_entity(&"VINE"), 1).removed, "场景层：藤蔓已拔除")

	# 观察（残影叠加）
	lm._do_observe()
	h.ck(true, "场景层：残影开关不报错")
	lm._do_observe()

	# 提示
	lm._do_hint()
	h.ck(not messages.is_empty(), "场景层：提示/反馈文案有输出（%d 条）" % messages.size())

	# 切回 T2 并走到出口
	lm._transition = 0.0
	lm._try_shift(1)
	h.eq(lm.tc.current_t, 2, "场景层：切回 T2")
	h.ck(not lm.tc.is_blocked(Vector2i(10, 2), 2), "场景层：T2 闸门可通行")
	lm.tc.player_pos = Vector2i(9, 2)
	lm._teleport_to(Vector2i(11, 1))
	lm.tc.player_pos = Vector2i(11, 1)
	lm.tc._after_change(false)
	h.ck(bool(flags["won"]), "🏁 场景层：抵达出口并触发通关信号")

	# 派生状态渲染入参
	lm.refresh_all()
	h.ck(true, "refresh_all 不报错")
	h.ck(lm.status_text().length() > 0, "状态文本非空：" + lm.status_text())

	if root != null:
		root.remove_child(lm)
	lm.free()
