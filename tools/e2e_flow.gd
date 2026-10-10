extends SceneTree
##
## 全流程端到端走查（**真 main.tscn + 真实输入事件**）。
##
## 与 tests/ 的区别：tests/ 直接调 TimeController / LevelManager 的方法断言数值；
## 这里走的是**输入层**——InputEventAction 按 InputMap 动作名派发、鼠标左键经
## `_unhandled_input` 寻路——所以能覆盖到 tests/ 覆盖不到的接线问题：
##   InputMap 动作缺失 / 动作→动词接错 / 切时刻冷却误锁 / HUD 未刷新 / 通关信号未连。
##
## 它抓到过的真问题：`LevelManager._transition` 曾挂在 `tc.moment_changed` 上，
## 而该信号在每次持取/放置/使用/走路都会发 → 任意动作都会把「切换时刻」静默锁 0.35 s。
## 现在冷却只在**时刻真的变了**时才武装（见 `_on_moment_changed`）。
##
## 第八轮（移动输入）后本工具的第二重职责：**验证移动是异步逐格推进的** ——
## 所有"走到某格"都改成"点一下 → 等精灵真的抵达 → 再断言"，并显式检查
## 「点击瞬间逻辑坐标不动」「点到出口的瞬间不通关」。
##
## 用法：
##   "$GD" --headless --path "D:/New test" --script res://tools/e2e_flow.gd
## 退出码 0 = 全绿；1 = 有失败；2 = 看门狗触发（协程中断挂死）。
##

const ORIGIN := Vector2(0.0, 140.0)
const CELL := 96.0
## 单次"等到达"的帧数上限。headless 下帧间隔极小，一格 ≈ 0.111 s 游戏时间
## 可能要上千帧；给足余量，真实卡死仍会被它和看门狗双双兜住。
const MAX_WAIT := 120000
## 等"长按自动再迈一步"的帧数上限（比 MAX_WAIT 小：正常只需等到 STEP_REPEAT）
const MAX_WAIT_STEP := 20000
## 加速时间流逝，纯粹为了缩短墙钟耗时：movement / 冷却都是按 delta 积分的，
## 放大 time_scale 不改变任何逻辑分支，只是让"0.111 s 一格"更快走完。
const TIME_SCALE := 4.0

var _ok := 0
var _bad := 0
var _msgs: Array[String] = []
var _lm: Object = null


func _initialize() -> void:
	Engine.time_scale = TIME_SCALE
	_watchdog()
	await _run()


## 兜底：脚本若因运行时错误中断（协程不再恢复），45 秒后强制退出，避免挂死。
## ⚠ ignore_time_scale = true：否则会被上面的 TIME_SCALE 提前触发。
func _watchdog() -> void:
	await create_timer(45.0, true, false, true).timeout
	printerr("[e2e] WATCHDOG 触发：脚本未在 45s 内自行结束，强制退出")
	quit(2)


func _ck(cond: bool, label: String) -> void:
	if cond:
		_ok += 1
		print("  [e2e] PASS   ", label)
	else:
		_bad += 1
		print("  [e2e] FAIL   ", label)


func _eq(a: Variant, b: Variant, label: String) -> void:
	_ck(str(a) == str(b), "%s  (实际=%s / 期望=%s)" % [label, str(a), str(b)])


## 取背包顶部的冻结形态（空背包返回 "-"，避免空指针中断整条走查）
func _top_form(tc: Object) -> String:
	var inv = tc.get("inventory")
	if inv == null or inv.size() == 0:
		return "-"
	return str(inv.top().form)


# ---------------------------------------------------------------- 输入模拟 ---

## 按一次动作（按下 + 抬起），走真实的 InputEventAction 管线。
## ⚠ 只适用于**事件驱动**的动词（切时刻/持取/放置/使用/观察/撤销/提示/重置）。
##   方向键移动是 `_process` **轮询** Input 动作状态实现的（为的是支持"按住不放"），
##   而 InputEventAction 只在按下瞬间产生一次事件 —— 移动必须用 _hold/_release。
func _press(action: StringName) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame


## 按住 / 松开一个动作（不产生事件，只改 Input 的动作状态表）—— 供移动用。
func _hold(action: StringName) -> void:
	Input.action_press(action)


func _release(action: StringName) -> void:
	Input.action_release(action)


func _cell_pos(c: Vector2i) -> Vector2:
	return ORIGIN + (Vector2(c) + Vector2(0.5, 0.5)) * CELL


## 注入鼠标按键事件。用 push_input(ev, true) 直接送**视口局部坐标**：
## headless 下 Input.parse_input_event 的鼠标事件不会走到 _unhandled_input。
func _mouse_button(pressed: bool, c: Vector2i) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = _cell_pos(c)
	ev.global_position = ev.position
	root.push_input(ev, true)


func _mouse_motion(c: Vector2i) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _cell_pos(c)
	ev.global_position = ev.position
	root.push_input(ev, true)


## 点一格并**等精灵真正走到**（逐格推进 ⇒ 点击不再立即改坐标）。
func _click_cell(c: Vector2i) -> void:
	_mouse_button(true, c)
	await process_frame
	_mouse_button(false, c)
	await process_frame
	await _arrive()


## 等移动走完（精灵抵达路线终点）。超时算失败，而不是静默死等。
func _arrive(tag: String = "") -> void:
	var g := 0
	while _lm != null and bool(_lm.call("is_moving")) and g < MAX_WAIT:
		await process_frame
		g += 1
	if g >= MAX_WAIT:
		_ck(false, "移动未在有限帧内结束%s" % (("（" + tag + "）") if tag != "" else ""))


## 从玩家当前位置，按候选顺序挑第一个"路径 ≥ min_size 格"的可达格。
## 用它代替写死坐标：本关有多处拓扑约束（墙格 / 被砝码占住的压力板 / 唯一咽喉），
## 写死的目标格很容易正好踩在"那一刻不可达"的格上，让走查变成维护负担。
func _pick(tc: Object, cands: Array, min_size: int) -> Vector2i:
	var from: Vector2i = tc.get("player_pos")
	for c in cands:
		var p: Array = tc.call("find_path", from, c)
		if p.size() >= min_size:
			return c
	return Vector2i(-1, -1)


## 等切时刻冷却走完（顺带验证冷却真的会自动清零）
func _settle(lm: Object) -> void:
	var guard := 0
	while float(lm.get("_transition")) > 0.0 and guard < 60000:
		await process_frame
		guard += 1
	_ck(guard < 60000, "切时刻冷却在有限帧内自动清零（用了 %d 帧）" % guard)


# ------------------------------------------------------------------- 主流程 ---

func _run() -> void:
	print("===== 全流程走查（真 main.tscn + 真实输入） =====")

	# ---- 0. 输入映射存在性 ----
	for a in ["shift_prev", "shift_next", "take", "place", "use", "observe", "undo",
			"hint", "reset", "move_up", "move_down", "move_left", "move_right"]:
		_ck(InputMap.has_action(a), "InputMap 有动作 `%s`" % a)

	# ---- 1. 启动真场景 ----
	var packed: PackedScene = load("res://src/main/main.tscn")
	_ck(packed != null, "main.tscn 可加载")
	if packed == null:
		_finish()
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	for _i in 6:
		await process_frame

	var lm: Node = main.get("level")
	_ck(lm != null, "main.tscn 装配出 LevelManager")
	if lm == null:
		_finish()
		return
	_lm = lm
	var tc = lm.get("tc")
	var lv = lm.get("level")
	_ck(tc != null and lv != null, "TimeController / LevelData 就绪")
	lm.level_message.connect(func(t: String) -> void: _msgs.append(t))

	var hud: Node = main.get("hud")
	_ck(hud != null, "main.tscn 装配出 HUD")

	# ---- 2. 初始态 ----
	_eq(tc.get("current_t"), 2, "初始时刻 = T2")
	_eq(tc.get("player_pos"), Vector2i(3, 5), "初始坐标 (3,5)")
	_eq(tc.get("hourglass"), 12, "初始时砂 12")
	_eq(tc.get("inventory").size(), 0, "初始背包为空")
	_eq(lv.get("grid_size"), Vector2i(13, 8), "网格 13×8")

	# ---- 2b. 路径预览：开局可达性（拓扑约束：咽喉以东走不通）----
	lm.set("_hover_cell", Vector2i(11, 1))
	_ck(not bool(lm.call("preview_reachable")), "预览：开局 T2 的出口不可达")
	_eq(lm.call("preview_path").size(), 0, "预览：不可达则不画线")
	lm.set("_hover_cell", Vector2i(9, 2))
	_ck(not bool(lm.call("preview_reachable")),
		"预览：开局 T2 的 (9,2) 也不可达（唯一咽喉 (7,1) 大门 + (8,1) 藤蔓未解）")
	lm.set("_hover_cell", Vector2i(3, 4))
	_ck(bool(lm.call("preview_reachable")), "预览：开局 (3,4) 可达（就在头顶）")
	_eq(lm.call("preview_path").size(), 2, "预览：(3,5)→(3,4) 最短路 2 格")
	_eq(lm.call("preview_path").back(), Vector2i(3, 4), "预览：路线终点 = 悬停格")
	lm.set("_hover_cell", Vector2i(-1, -1))

	# ---- 3. 键盘移动：按住即走 + 长按连走 ----
	# 用键盘（而非点击）走到 (3,3)：正好替代原来那一步点击寻路，且顺带验收"按住不放"。
	# ⚠ 这里只断言"最终落点"，不在帧边界上断言"坐标还没变" ——
	#   headless 下帧间隔抖动很大，同一句断言可能恰好落在"已提交"的那一帧上（曾实际踩到）。
	#   "人未到不结算"的**强断言**放在 tests/test_movement.gd：那边手动驱动 _process，
	#   步长完全可控，是确定性的。
	_hold(&"move_up")
	await process_frame
	_ck(bool(lm.call("is_moving")), "键盘：按下 ↑ 后下一帧即产生在途移动")
	var g1 := 0
	while tc.get("player_pos") == Vector2i(3, 5) and g1 < MAX_WAIT_STEP:
		await process_frame
		g1 += 1
	_eq(tc.get("player_pos"), Vector2i(3, 4), "键盘：★ 不点鼠标，纯按键走出第一格 → (3,4)")
	# 仍按着不放：不再有任何新输入，精灵应自己继续迈下一格
	var g2 := 0
	while tc.get("player_pos") == Vector2i(3, 4) and g2 < MAX_WAIT_STEP:
		await process_frame
		g2 += 1
	_release(&"move_up")
	_eq(tc.get("player_pos"), Vector2i(3, 3), "★ 键盘：长按持续走 → 自动再迈一格到 (3,3)")
	_ck(g1 < MAX_WAIT_STEP and g2 < MAX_WAIT_STEP,
		"键盘：两步都在有限帧内完成（%d / %d 帧）" % [g1, g2])
	await _arrive("键盘")
	_ck(not bool(lm.call("is_moving")), "键盘：松开并走完后不再有在途移动")

	# ---- 3b. 鼠标点击寻路：**同步**断言"点击瞬间不结算" ----
	# Viewport.push_input 是**同步**派发到 _unhandled_input 的，所以这里不 await，
	# 读到的一定是"按下那一刻"的状态 —— 没有任何帧时序竞态。
	var before3: Vector2i = tc.get("player_pos")
	_mouse_button(true, Vector2i(3, 3))
	if before3 == Vector2i(3, 3):
		_ck(lm.get("_route").size() == 0, "已在目标格上点击 → 不产生路线")
	else:
		_ck(lm.get("_route").size() > 0, "★ 按下瞬间已规划出路线")
		_eq(tc.get("player_pos"), before3, "★ 按下瞬间逻辑坐标**不动**（同步断言，无帧竞态）")
	_mouse_button(false, Vector2i(3, 3))
	await _arrive("点击")
	_eq(tc.get("player_pos"), Vector2i(3, 3), "鼠标点击 → 走完抵达 (3,3)")

	# ---- 4. T2 取锈钥匙 ----
	await _press(&"take")
	_eq(tc.get("inventory").size(), 1, "T2 持取钥匙 → 背包 1")
	_eq(_top_form(tc), "KEY_RUSTY", "冻结形态 = KEY_RUSTY")

	# ---- 5. T2 用锈钥匙开铁栅 → 折断 ----
	await _click_cell(Vector2i(6, 1))
	_eq(tc.get("player_pos"), Vector2i(6, 1), "走到大门西邻 (6,1)")
	await _press(&"use")
	_eq(tc.get("inventory").size(), 0, "锈钥匙折断 → 背包空")
	_eq(str(tc.resolve_state(lv.get_entity(&"KEY"), 2).form), "KEY_BROKEN", "T2 钥匙 = KEY_BROKEN")
	_ck(not tc.resolve_state(lv.get_entity(&"GATE"), 2).open, "T2 铁栅仍锁着（教学负反馈）")

	# ---- 6. 切到 T1（真实动作 + 冷却）----
	await _press(&"shift_prev")
	await _settle(lm)
	_eq(tc.get("current_t"), 1, "按 shift_prev → T1")
	_eq(tc.get("hourglass"), 11, "时砂 11")

	# ---- 7. T1 取崭新钥匙 ----
	await _click_cell(Vector2i(3, 3))
	await _press(&"take")
	_eq(tc.get("inventory").size(), 1, "T1 持取钥匙 → 背包 1")
	_eq(_top_form(tc), "KEY_NEW", "T1 冻结形态 = KEY_NEW")
	_eq(str(tc.resolve_state(lv.get_entity(&"KEY"), 1).form), "KEY_NEW", "T1 钥匙台上有崭新的钥匙")

	# ---- 8. T1 开门（正向传播）----
	await _click_cell(Vector2i(6, 1))
	await _press(&"use")
	_ck(tc.resolve_state(lv.get_entity(&"GATE"), 1).open, "T1 铁栅开启")
	_ck(tc.resolve_state(lv.get_entity(&"GATE"), 2).open, "★ 正向传播：T2 铁栅也开")
	_ck(not tc.resolve_state(lv.get_entity(&"GATE"), 0).open, "★ 不向过去传播：T0 仍锁")
	_eq(tc.get("inventory").size(), 0, "钥匙留在锁孔 → 背包空")

	# ---- 9. T1 取砝码 ----
	await _click_cell(Vector2i(1, 3))
	_eq(tc.get("player_pos"), Vector2i(1, 3), "走到砝码南邻 (1,3)")
	await _press(&"take")
	_eq(tc.get("inventory").size(), 1, "T1 持取砝码 → 背包 1")
	_eq(_top_form(tc), "WEIGHT_OK", "T1 冻结形态 = WEIGHT_OK")

	# ---- 10. T1 拔藤（经已开的大门进咽喉）----
	await _click_cell(Vector2i(7, 1))
	_eq(tc.get("player_pos"), Vector2i(7, 1), "走到大门格 (7,1)（T1 已开）")
	await _press(&"use")
	_ck(tc.resolve_state(lv.get_entity(&"VINE"), 1).removed, "T1 藤蔓已拔除")
	_ck(tc.resolve_state(lv.get_entity(&"VINE"), 2).removed, "★ 正向传播：T2 藤蔓也不在")
	_ck(not tc.is_blocked(Vector2i(8, 1), 2), "T2 的 (8,1) 咽喉可通行")

	# ---- 11. T1 放砝码上压力板 ----
	await _click_cell(Vector2i(9, 2))
	_eq(tc.get("player_pos"), Vector2i(9, 2), "走到压力板北邻 (9,2)")
	await _press(&"place")
	_eq(tc.resolve_state(lv.get_entity(&"WEIGHT"), 1).pos, Vector2i(9, 3), "T1 砝码落在压力板 (9,3)")
	_ck(tc.plate_pressed(1), "T1 压力板被压住")
	_ck(tc.grate_open(1), "T1 闸门开启")
	_eq(tc.get("inventory").size(), 0, "放下砝码 → 背包空")

	# ---- 12. 切回 T2 ----
	await _press(&"shift_next")
	await _settle(lm)
	_eq(tc.get("current_t"), 2, "按 shift_next → 切回 T2")
	_eq(tc.get("hourglass"), 10, "时砂 10（两次切换共耗 2）")
	_ck(not tc.is_blocked(Vector2i(7, 1), 2), "T2 大门可通行")
	_ck(not tc.is_blocked(Vector2i(8, 1), 2), "T2 咽喉可通行")
	_ck(not tc.is_blocked(Vector2i(10, 2), 2), "T2 闸门可通行")
	_ck(not tc.is_blocked(Vector2i(11, 1), 2), "T2 出口完好可通行")

	# ---- 13. 走到出口通关：★ 必须是"人踏进去"才结算 ----
	var path: Array[Vector2i] = tc.find_path(Vector2i(9, 2), Vector2i(11, 1))
	_ck(path.size() > 0, "存在 (9,2) → (11,1) 的路径（%d 格）" % path.size())
	# 同步断言：push_input 立刻派发，读到的一定是"刚按下"那一刻
	_mouse_button(true, Vector2i(11, 1))
	_ck(not bool(tc.get("won")), "★ 点击出口的瞬间**未**通关（同步断言，无帧竞态）")
	_eq(tc.get("player_pos"), Vector2i(9, 2), "★ 点击出口的瞬间逻辑坐标仍在 (9,2)")
	_ck(bool(lm.call("is_moving")), "★ 点击出口后确实产生了在途移动")
	_mouse_button(false, Vector2i(11, 1))
	await process_frame
	var guard := 0
	while not bool(tc.get("won")) and guard < MAX_WAIT:
		await process_frame
		guard += 1
	_ck(bool(tc.get("won")), "🏁 人踏进出口那一格才通关")
	await _arrive("通关")
	_eq(tc.get("player_pos"), Vector2i(11, 1), "走到出口 (11,1)")
	_ck(_has_msg("通关"), "收到通关文案消息")
	_eq(tc.get("hourglass"), 10, "通关时时砂 = 10（最优耗 2）")

	# ---- 14. HUD 未崩、状态文本同步 ----
	lm.refresh_all()
	var st: String = lm.call("status_text")
	_ck(st.length() > 0, "状态文本非空：" + st)
	_ck(st.contains("(11,1)"), "状态文本含通关坐标 (11,1)")
	_ck(String(lm.call("target_label")).length() >= 0, "面向标签可读")

	# ---- 14b. 观察面板必须反映**派生**状态（门开 / 闸开 / 板被压）----
	var obs: String = tc.call("observe_text")
	_ck(obs.contains("敞开的铁栅门"), "观察面板：铁栅门显示为已开（不是「锁着」）")
	_ck(obs.contains("开启的闸门"), "观察面板：闸门显示为已开（不是裸 id GRATE）")
	_ck(obs.contains("被压住的压力板"), "观察面板：压力板显示为被压住（不是裸 id PLATE）")

	# ---- 14c. 鼠标长按拖拽：目的地随指针实时改变（RTS 式持续走）----
	# 站在 (11,1)。→ (11,2) → (10,2) → (9,2) 共 3 步。
	# ⚠ 不要用 (10,1)：它在本关是**墙**（出口只能经闸门 (10,2) 那一侧抵达）。
	# 全程同步断言（不 await），因此与帧时序无关。
	var drag_a := Vector2i(9, 2)
	var drag_b := Vector2i(10, 2)
	_eq(tc.find_path(Vector2i(11, 1), drag_a).size(), 4, "拖拽前置：(11,1) → (9,2) 是 3 步")
	_mouse_button(true, drag_a)
	_ck(bool(lm.get("_mouse_hold")), "拖拽：左键按下 → 进入按住态")
	_ck(bool(lm.call("is_moving")), "拖拽：按下即开始逐格推进")
	_eq(tc.get("player_pos"), Vector2i(11, 1), "拖拽：按下瞬间仍未结算坐标（同步断言）")
	_ck(lm.get("_route").size() > 0, "拖拽：按下后路线非空")
	_eq(lm.get("_route").back(), drag_a, "拖拽：目的地 = 按下处的格子")
	_mouse_motion(drag_b)
	_eq(lm.get("_hover_cell"), drag_b, "拖拽：指针移动更新悬停格")
	_ck(lm.get("_route").size() > 0, "拖拽：改目的地后路线仍非空")
	_eq(lm.get("_route").back(), drag_b, "★ 拖拽：目的地实时改为 (10,2)")
	_mouse_button(false, drag_b)
	_ck(not bool(lm.get("_mouse_hold")), "拖拽：抬起 → 退出按住态")
	await _arrive("拖拽")
	_eq(tc.get("player_pos"), drag_b, "拖拽：最终抵达新目的地 (10,2)")

	# ---- 14d. 路径预览：移动中画**真实剩余路线** ----
	var tgt := _pick(tc, [Vector2i(1, 3), Vector2i(3, 5), Vector2i(3, 3), Vector2i(6, 4)], 3)
	_ck(tgt != Vector2i(-1, -1), "预览前置：找到 ≥2 步的可达目标（%s）" % str(tgt))
	_mouse_button(true, tgt)
	var pv: Array = lm.call("preview_path")
	_ck(pv.size() >= 2, "预览（移动中）：路线 ≥2 格（实际 %d）" % pv.size())
	_ck(lm.get("_route").size() > 0, "预览（移动中）：移动仍在途")
	if lm.get("_route").size() > 0:
		_eq(pv[0], lm.get("_route")[0], "预览（移动中）：首格 = 当前在途目标")
	_mouse_button(false, tgt)
	await _arrive("预览后走完")
	_eq(tc.get("player_pos"), tgt, "预览：走完抵达目标格")

	# ---- 14e. 路径预览：静止时按悬停格现场算路 ----
	lm.set("_hover_cell", Vector2i(11, 1))
	_ck(bool(lm.call("preview_reachable")), "预览（静止）：(11,1) 可达")
	var pv2: Array = lm.call("preview_path")
	_ck(pv2.size() >= 2, "预览（静止）：路线 ≥2 格（实际 %d）" % pv2.size())
	_eq(pv2[0], tc.get("player_pos"), "预览（静止）：从玩家当前格起算")
	_eq(pv2.back(), Vector2i(11, 1), "预览（静止）：终点 = 悬停格")
	lm.set("_hover_cell", Vector2i(-1, -1))
	_eq(lm.call("preview_path").size(), 0, "预览：悬停哨兵格 → 不画线")

	# ---- 15. 撤销 / 重置 / 提示 不报错 ----
	await _press(&"undo")
	_ck(true, "撤销动作不报错")
	await _press(&"hint")
	_ck(true, "提示动作不报错")
	await _press(&"observe")
	await _press(&"observe")
	_ck(true, "观察（残影）开关不报错")
	await _press(&"reset")
	_ck(true, "重置动作不报错")
	_eq(tc.get("hourglass"), 12, "重置后时砂回到 12")
	_ck(not bool(tc.get("won")), "重置后通关标记清空")
	_eq(tc.get("player_pos"), Vector2i(3, 5), "重置后坐标回到起点 (3,5)")
	_ck(not bool(lm.call("is_moving")), "重置后没有残留的在途移动")

	# ---- 16. 空手按 Q：只应产生 1 条提示（曾经刷 5 条把提示条冲掉）----
	var before := _msgs.size()
	await _press(&"place")
	_eq(_msgs.size() - before, 1, "空手按 Q 只产生 1 条提示")

	_finish()


func _has_msg(sub: String) -> bool:
	for m in _msgs:
		if m.contains(sub):
			return true
	return false


func _finish() -> void:
	Engine.time_scale = 1.0
	print("──────────────────────────────────────────────")
	print("[e2e] pass = %d   fails = %d" % [_ok, _bad])
	print("[e2e] %s" % ("ALL PASS" if _bad == 0 else "HAS FAILURES"))
	print("──────────────────────────────────────────────")
	quit(1 if _bad > 0 else 0)
