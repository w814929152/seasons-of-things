class_name TestMovement
extends RefCounted
##
## 移动输入专项（第七轮改造验收）。
##
## 覆盖四项裁定：
##   1) 键盘移动         —— 方向键按下即走、长按连续步进
##   2) 中途点击不错位   —— 逐格推进 ⇒ 精灵永远沿相邻格前进，不斜穿墙角
##   3) 人未到不先结算   —— 逻辑坐标只在"精灵真正抵达该格"时才提交
##   4) 长按持续走+预览  —— 拖拽改目的地 / find_path 预览可达性
## 另含两条工程不变量：整段移动只占 1 条撤销记录；切时刻取消在途移动并吸附精灵。
##
## ⚠ 本组**故意**不走 `_teleport_to`（那是给"我只关心逻辑结果"的用例准备的原语），
##   全部用 `move_to` + 手动驱动 `_process` 来复现真实的逐格推进。
##

const EPS := 0.005


# ============================================================ 小工具 ====

static func _mk(root: Node):
	var lm = preload("res://src/level/level_manager.gd").new()
	root.add_child(lm)
	lm.start_level()
	return lm


## 一格的行走时长（秒）
static func _cell_time(lm) -> float:
	return 1.0 / float(lm.WALK_SPEED)


## 用固定步长驱动 _process 直到移动结束；返回调用次数。
static func _run_until_idle(lm, dt: float = 0.02, limit: int = 400) -> int:
	var n := 0
	while lm.is_moving() and n < limit:
		lm._process(dt)
		n += 1
	return n


## 4 邻接不变量：每一跳必须恰好是上下左右一格
static func _all_adjacent(cells: Array) -> bool:
	for i in range(1, cells.size()):
		var d: Vector2i = cells[i] - cells[i - 1]
		if absi(d.x) + absi(d.y) != 1:
			return false
	return true


static func _all_open(tc, cells: Array) -> bool:
	for c in cells:
		if tc.is_blocked(c, tc.current_t):
			return false
	return true


## 在网格里找"离玩家最远、路径最长"的可达格
static func _find_far(tc, min_len: int) -> Vector2i:
	var sz: Vector2i = tc.grid.size
	var best := Vector2i(-1, -1)
	var best_len := 0
	for y in sz.y:
		for x in sz.x:
			var c := Vector2i(x, y)
			if c == tc.player_pos:
				continue
			var p: Array = tc.find_path(tc.player_pos, c)
			if p.size() > best_len:
				best_len = p.size()
				best = c
	return best if best_len >= min_len else Vector2i(-1, -1)


## 与 cell 相邻、可通行、且不是 avoid 的第二条出路
static func _other_neighbor(tc, cell: Vector2i, avoid: Vector2i) -> Vector2i:
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var c: Vector2i = cell + d
		if c == avoid or not tc.grid.is_inside(c):
			continue
		if not tc.is_blocked(c, tc.current_t):
			return c
	return Vector2i(-1, -1)


## 复现关卡文档 §7 标准解法（步 1–9），让闸门/铁栅/藤蔓都就位。
## 只走逻辑层 —— 这里要的是"世界已解好"这个前提，不是验证解法本身。
static func _solve(tc) -> void:
	tc.player_pos = Vector2i(3, 3)
	tc.take(&"KEY")
	tc.player_pos = Vector2i(6, 1)
	tc.use(&"GATE")
	tc.shift(-1)
	tc.player_pos = Vector2i(3, 1)
	tc.take(&"KEY")
	tc.player_pos = Vector2i(6, 1)
	tc.use(&"GATE")
	tc.player_pos = Vector2i(1, 3)
	tc.take(&"WEIGHT")
	tc.player_pos = Vector2i(7, 1)
	tc.use(&"VINE")
	tc.player_pos = Vector2i(9, 2)
	tc.place(Vector2i(9, 3))
	tc.shift(1)


# ============================================================== 主流程 ====

static func run(h: TestHarness, root: Node) -> void:
	h.suite("移动输入 · 逐格推进 / 键盘 / 长按 / 路径预览")
	var made: Array = []

	# ------------------------------------------------------------------
	# A. 逐格推进：人未到，不结算
	# ------------------------------------------------------------------
	var lm = _mk(root)
	made.append(lm)
	var tc = lm.tc
	var start: Vector2i = tc.player_pos                       # (3,5)
	var far := _find_far(tc, 4)
	h.ck(far != Vector2i(-1, -1), "A 前置：存在 ≥4 格的可达目标（%s）" % str(far))
	var path: Array = tc.find_path(start, far)
	h.ck(_all_adjacent(path), "A 前置：路径每一跳都是相邻格（%d 格）" % path.size())
	h.ck(_all_open(tc, path), "A 前置：路径上每一格都可通行")

	h.ck(lm.move_to(far), "A1：move_to 成功规划路线")
	h.eq(tc.player_pos, start, "A2：★ 出发瞬间逻辑坐标**不动**（人未到不结算）")
	h.eq(lm._route.size(), path.size() - 1, "A3：剩余路线 = 路径去掉起点格")
	h.eq(lm._route[0], path[1], "A4：第一个航点 = 路径第 2 格")
	h.ck(lm.is_moving(), "A5：is_moving() 为真")

	# 走半格 —— 不该结算
	lm._process(_cell_time(lm) * 0.5)
	h.eq(tc.player_pos, start, "A6：走过半格仍未结算")
	h.eq(lm._route[0], path[1], "A7：仍在前往路径第 2 格")

	# 走满一格 —— 结算
	lm._process(_cell_time(lm) * 0.6)
	h.eq(tc.player_pos, path[1], "A8：★ 走满一格才提交坐标")
	h.eq(lm._facing, path[1] - path[0], "A9：每走一格同步更新朝向")

	var frames := _run_until_idle(lm)
	h.ck(frames < 400, "A10：路线在有限帧内走完（%d 帧）" % frames)
	h.eq(tc.player_pos, far, "A11：走完路线后逻辑坐标 == 目标格")
	h.ck(not lm.is_moving(), "A12：移动结束，路线已清空")
	h.ck(lm._player.position.distance_to(lm._cell_center(far)) < 0.5,
		"A13：精灵恰好停在目标格心（逻辑与画面同格）")

	# ------------------------------------------------------------------
	# B. 整段连续移动 = 1 条撤销记录
	# ------------------------------------------------------------------
	var n0: int = tc._undo_stack.size()
	h.ck(lm.move_to(start), "B1：规划返程")
	_run_until_idle(lm)
	h.eq(tc.player_pos, start, "B2：已走回起点格")
	h.eq(tc._undo_stack.size(), n0 + 1, "B3：★ 整段移动只占 1 条撤销记录")
	h.ck(tc.undo_step(), "B4：撤销成功")
	h.eq(tc.player_pos, far, "B5：★ 一次撤销回滚**整段**移动")

	# ------------------------------------------------------------------
	# C. 中途改目标：不穿墙，且不白跑
	# ------------------------------------------------------------------
	var lm2 = _mk(root)
	made.append(lm2)
	var tc2 = lm2.tc
	var far2 := _find_far(tc2, 3)
	var p2: Array = tc2.find_path(tc2.player_pos, far2)
	var other := _other_neighbor(tc2, p2[0], p2[1])
	h.ck(other != Vector2i(-1, -1), "C 前置：起点存在第二条出路（%s）" % str(other))

	# C1）越过半格后改目标 → 走完当前这一步再拐弯（不回头）
	lm2.move_to(far2)
	lm2._player.position = lm2._cell_center(p2[0]).lerp(lm2._cell_center(p2[1]), 0.6)
	h.ck(lm2.move_to(other), "C1：过半后改目标成功")
	h.eq(lm2._route[0], p2[1], "C2：★ 过半 → 先走完当前这格，不倒退")
	var plan: Array = [tc2.player_pos]
	plan.append_array(lm2._route)
	h.ck(_all_adjacent(plan), "C3：★ 计划路径每一跳都相邻（不可能斜穿墙角）")
	h.ck(_all_open(tc2, plan), "C4：★ 计划路径没有一格是阻挡格")
	h.eq(plan.back(), other, "C5：计划终点 == 新目标格")
	_run_until_idle(lm2)
	h.eq(tc2.player_pos, other, "C6：最终抵达新目标格")

	# C2）未过半就改目标 → 退回本格格心再走（不浪费那半格）
	var lm2b = _mk(root)
	made.append(lm2b)
	var tc2b = lm2b.tc
	var far2b := _find_far(tc2b, 3)
	var p2b: Array = tc2b.find_path(tc2b.player_pos, far2b)
	var other2 := _other_neighbor(tc2b, p2b[0], p2b[1])
	lm2b.move_to(far2b)
	lm2b._player.position = lm2b._cell_center(p2b[0]).lerp(lm2b._cell_center(p2b[1]), 0.3)
	lm2b.move_to(other2)
	h.eq(lm2b._route[0], tc2b.player_pos, "C7：未过半 → 先退回本格格心（不浪费半格）")
	h.eq(lm2b._route.back(), other2, "C8：退回后再前往新目标")
	# ⚠ 这里不能把 tc.player_pos 拼到路线前面：退回航点**本来就是**当前格，
	#   拼上去会出现 (s,s) 这种"零位移"，不是穿墙。检查路线自身即可。
	h.ck(_all_adjacent(lm2b._route), "C9：退回路线逐格相邻（首个航点=当前格，属正常收步）")
	h.ck(_all_open(tc2b, lm2b._route), "C9b：退回路线全部可通行")
	_run_until_idle(lm2b)
	h.eq(tc2b.player_pos, other2, "C10：最终抵达新目标格")

	# ------------------------------------------------------------------
	# D. 键盘移动：按下即走 + 长按连续步进
	# ------------------------------------------------------------------
	var lm3 = _mk(root)
	made.append(lm3)
	var tc3 = lm3.tc
	var s3: Vector2i = tc3.player_pos
	# 挑一个"连走两格都不撞墙"的方向，并记下它对应的输入动作
	var dirs := [
		{"d": Vector2i(1, 0), "a": "move_right"},
		{"d": Vector2i(-1, 0), "a": "move_left"},
		{"d": Vector2i(0, -1), "a": "move_up"},
		{"d": Vector2i(0, 1), "a": "move_down"},
	]
	var dir := Vector2i.ZERO
	var act := ""
	for cand in dirs:
		var d: Vector2i = cand["d"]
		var c1: Vector2i = s3 + d
		var c2: Vector2i = s3 + d * 2
		if tc3.grid.is_inside(c1) and tc3.grid.is_inside(c2) \
				and not tc3.is_blocked(c1, tc3.current_t) \
				and not tc3.is_blocked(c2, tc3.current_t):
			dir = d
			act = String(cand["a"])
			break
	h.ck(dir != Vector2i.ZERO, "D 前置：存在连续两格畅通的方向（%s）" % act)

	Input.action_press(act)
	lm3._process(0.016)
	h.ck(lm3.is_moving(), "D1：★ 按下方向键立即开始移动")
	h.eq(tc3.player_pos, s3, "D2：首帧尚未结算（同样是『人未到不结算』）")
	h.eq(lm3._route[0], s3 + dir, "D3：首格目标 = 起点 + 方向")
	lm3._process(_cell_time(lm3) + 0.02)
	h.eq(tc3.player_pos, s3 + dir, "D4：★ 走满一格即结算")
	h.eq(lm3._facing, dir, "D5：朝向 = 按键方向")
	lm3._process(lm3.STEP_REPEAT + 0.14)
	h.eq(tc3.player_pos, s3 + dir * 2, "D6：★ 长按持续走，累计前进 2 格")

	var before_n: int = lm3._route.size()
	Input.action_release(act)
	lm3._process(0.016)
	h.eq(lm3._hold_dir, Vector2i.ZERO, "D7：松开后重置保持态")
	h.eq(lm3._route.size(), before_n, "D8：松开后不再新增步进")

	# 长按整段也只占 1 条撤销
	var lm3b = _mk(root)
	made.append(lm3b)
	var n3: int = lm3b.tc._undo_stack.size()
	Input.action_press(act)
	lm3b._process(0.016)
	lm3b._process(lm3b.STEP_REPEAT + 0.14)
	lm3b._process(lm3b.STEP_REPEAT + 0.14)
	Input.action_release(act)
	h.eq(lm3b.tc._undo_stack.size(), n3 + 1, "D9：长按整段移动也只占 1 条撤销记录")

	# ------------------------------------------------------------------
	# E. 鼠标：按下出发 / 拖拽实时改目的地 / 抬起后走完
	# ------------------------------------------------------------------
	var lm4 = _mk(root)
	made.append(lm4)
	var tc4 = lm4.tc
	var start4: Vector2i = tc4.player_pos
	var t4 := _find_far(tc4, 3)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = lm4._cell_center(t4)
	lm4._unhandled_input(down)
	h.ck(lm4._mouse_hold, "E1：左键按下 → 进入按住态")
	h.ck(lm4.is_moving(), "E2：按下即开始逐格推进")
	h.eq(tc4.player_pos, start4, "E3：按下瞬间逻辑坐标仍在起点格（人未到不结算）")
	h.eq(lm4._hover_cell, t4, "E3b：按下同时更新悬停格 = 目的地")
	var t4b := _other_neighbor(tc4, tc4.player_pos, lm4._route[0])
	h.ck(t4b != Vector2i(-1, -1), "E3c：起点存在第二条出路（%s）" % str(t4b))
	var mv := InputEventMouseMotion.new()
	mv.position = lm4._cell_center(t4b)
	lm4._unhandled_input(mv)
	h.eq(lm4._hover_cell, t4b, "E4：拖拽更新悬停格")
	h.eq(lm4._route.back(), t4b, "E5：拖拽实时改目的地")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = lm4._cell_center(t4b)
	lm4._unhandled_input(up)
	h.ck(not lm4._mouse_hold, "E6：抬起 → 退出按住态")
	h.ck(lm4.is_moving(), "E7：抬起后已规划路线继续走完")
	_run_until_idle(lm4)
	h.eq(tc4.player_pos, t4b, "E8：最终抵达拖拽目标格")

	# ------------------------------------------------------------------
	# F. 路径预览
	# ------------------------------------------------------------------
	lm4._cancel_move()
	var reach := _find_far(tc4, 3)
	lm4._hover_cell = reach
	h.ck(lm4.preview_reachable(), "F1：可达格 → preview_reachable() 为真")
	var pv: Array = lm4.preview_path()
	h.ck(pv.size() >= 3, "F2：预览路线 ≥3 格（实际 %d）" % pv.size())
	h.eq(pv[0], tc4.player_pos, "F3：预览路线从玩家当前格起算")
	h.eq(pv.back(), reach, "F4：预览路线终止于悬停格")
	h.ck(_all_adjacent(pv), "F5：预览路线逐格相邻")
	h.ck(_all_open(tc4, pv), "F6：预览路线全部可通行")

	# 开局 T2：闸门/铁栅/藤蔓都未处理 ⇒ 出口 (11,1) 不可达
	var lm5 = _mk(root)
	made.append(lm5)
	lm5._hover_cell = Vector2i(11, 1)
	h.ck(not lm5.preview_reachable(), "F7：★ 开局 T2 的出口不可达（三处障碍未解）")
	h.eq(lm5.preview_path().size(), 0, "F8：不可达则不画线")
	h.ck(not lm5.tc.is_blocked(Vector2i(11, 1), 2), "F9：出口格本身并非阻挡格 —— 不可达≠阻挡")
	lm5._hover_cell = lm5._pos_to_cell(Vector2(0.0, 0.0))
	h.eq(lm5._hover_cell, Vector2i(-1, -1), "F10：越界坐标 → 哨兵格")
	h.ck(not lm5.preview_reachable(), "F11：越界格不可达")
	h.eq(lm5.preview_path().size(), 0, "F12：越界不画线")
	lm5._hover_cell = Vector2i(-1, -1)

	# ------------------------------------------------------------------
	# G. 通关只在"人踏进出口那一格"时结算
	# ------------------------------------------------------------------
	var lm6 = _mk(root)
	made.append(lm6)
	var tc6 = lm6.tc
	_solve(tc6)
	lm6.refresh_all()          # 逻辑坐标已到 (9,2)，把精灵也吸附过去
	h.eq(tc6.player_pos, Vector2i(9, 2), "G1 前置：解完关卡后站在 (9,2)")
	h.ck(not tc6.won, "G2 前置：尚未通关")
	var exit_path: Array = tc6.find_path(Vector2i(9, 2), Vector2i(11, 1))
	# ⚠ 不写死走哪条路：BFS 在「(9,1)→(10,1) 咽喉」与「(10,2) 闸门→(11,2)」两条
	#   同为 3 步的最短路之间取哪条是实现细节（本关闸门已开，两条都合法）。
	#   要钉住的是"步数"与"逐格相邻"，而不是具体选了哪条。
	h.eq(exit_path.size(), 4, "G3：出口路径共 4 格（3 步）")
	h.eq(exit_path[0], Vector2i(9, 2), "G3a：路径起点 = (9,2)")
	h.eq(exit_path.back(), Vector2i(11, 1), "G3b：路径终点 = 出口 (11,1)")
	h.ck(_all_adjacent(exit_path), "G3c：出口路径逐格相邻")
	h.ck(_all_open(tc6, exit_path), "G3d：出口路径全部可通行（闸门/铁栅/藤蔓已解）")
	h.ck(lm6.move_to(Vector2i(11, 1)), "G4：规划前往出口")
	h.ck(not tc6.won, "G5：★ 路线已规划但**尚未结算**（通关标志未提前置位）")
	h.eq(tc6.player_pos, Vector2i(9, 2), "G6：逻辑坐标仍停在起点格")
	var steps: Array = exit_path.slice(1)
	for i in steps.size():
		lm6._process(_cell_time(lm6) + EPS)
		h.eq(tc6.player_pos, steps[i], "G·step%d：第 %d 步结算于 %s" % [i + 1, i + 1, str(steps[i])])
		if i < steps.size() - 1:
			h.ck(not tc6.won, "G·mid%d：走完 %d 格仍未通关（还剩 %d 格）"
				% [i + 1, i + 1, steps.size() - 1 - i])
	h.ck(tc6.won, "G·win：★ 踏进出口那一格才通关")

	# ------------------------------------------------------------------
	# H. 原子瞬移原语 & 切时刻取消移动
	# ------------------------------------------------------------------
	h.ck(lm6._teleport_to(Vector2i(9, 2)), "H1：_teleport_to 成功")
	h.eq(tc6.player_pos, Vector2i(9, 2), "H2：立即改坐标（原子语义，供轻量用例使用）")
	h.ck(not lm6.is_moving(), "H3：瞬移不产生在途移动")
	h.ck(lm6._player.position.distance_to(lm6._cell_center(Vector2i(9, 2))) < 0.5,
		"H4：精灵同步吸附到目标格心")

	var lm7 = _mk(root)
	made.append(lm7)
	var tc7 = lm7.tc
	lm7.move_to(_find_far(tc7, 3))
	h.ck(lm7.is_moving(), "H5 前置：存在在途移动")
	lm7._transition = 0.0
	lm7._try_shift(-1)
	h.ck(not lm7.is_moving(), "H6：★ 切时刻取消在途移动")
	h.ck(lm7._player.position.distance_to(lm7._cell_center(tc7.player_pos)) < 0.5,
		"H7：精灵被吸回逻辑格（不会悬在半路）")
	h.eq(tc7.current_t, 1, "H8：时刻确实切换了")

	# ---------------------------------------------------------------- 清理
	for lm_i in made:
		root.remove_child(lm_i)
		lm_i.free()
