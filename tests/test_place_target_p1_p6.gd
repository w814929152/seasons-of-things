class_name TestPlaceTargetP1P6
extends RefCounted
##
## 关卡文档 §11.1「放置目标选择专项」P1–P6。
##
## 背景：place 曾缺少兜底扫描（U1/U2/U3），玩家无法把砝码放上压力板 → 关卡不可解。
## 文档原话：**本组不通过 = 质量门不通过**，无论 §11 上面 9 条是否全绿。
##
## 与既有用例的区别：
##   既有 test_level_01_solvable / test_scene_wiring 都是**直接给 tc.place(目标格)**
##   —— 那是「假设玩家已经选对了格子」，绕过了真正出问题的那一段：
##   LevelManager._do_place() 的**目标格选择算法**（GDD §6.2.2）。
##   本组用例一律走 `lm._do_place()`（玩家按 Q 的真实入口），只喂朝向与坐标。
##
## 几何约束（文档 §11.1 末）：
##   (9,2) 四邻 = 北(9,1)地板 / 南(9,3)压力板 / 东(10,2)闸门 / 西(8,2)墙
##   闸门开启需砝码已上板 → 从东面进入是循环依赖，不可达；西面是墙。
##   ⇒ 只有「北进」(P1) 与「南进」(P2/P3) 两条真实进入路径，本组已穷尽。
##

const PLATE := Vector2i(9, 3)
const STAND_AT := Vector2i(9, 2)
const NORTH_OF := Vector2i(9, 1)


# ------------------------------------------------------------------ 夹具 ---

## 建一个挂到树上的 LevelManager（headless 下可安全 add_child）
static func _mk_lm(root: Node) -> Node:
	var lm = preload("res://src/level/level_manager.gd").new()
	if root != null:
		root.add_child(lm)
	lm.start_level()
	return lm


## 布置到「T1 · 铁栅已开 · 藤蔓已拔 · 手持砝码 · 玩家站在 at」
## 说明：布置阶段允许直接写 tc（那是 arrange），
##      被测动作（走 / 放 / 切）一律走 LevelManager 的玩家入口。
static func _arm(lm, at: Vector2i, take_weight: bool = true) -> void:
	lm._transition = 0.0
	lm._try_shift(-1)                 # T2 → T1
	# 取崭新钥匙
	lm.tc.player_pos = Vector2i(3, 3)
	lm._facing = Vector2i(0, -1)
	lm._do_take()
	# 开铁栅
	lm.tc.player_pos = Vector2i(6, 1)
	lm._facing = Vector2i(1, 0)
	lm._do_use()
	if take_weight:
		# 取砝码
		lm.tc.player_pos = Vector2i(1, 3)
		lm._facing = Vector2i(0, -1)
		lm._do_take()
	# 拔藤蔓
	lm.tc.player_pos = Vector2i(7, 1)
	lm._facing = Vector2i(1, 0)
	lm._do_use()
	lm.tc.player_pos = at


static func _weight_at(lm) -> Vector2i:
	return lm.tc.resolve_state(lm.level.get_entity(&"WEIGHT"), lm.tc.current_t).pos


# ------------------------------------------------------------------ 用例 ---

static func run(h: TestHarness, root: Node) -> void:
	h.suite("§11.1 放置目标选择专项 P1–P6（不通过 = 质量门不通过）")

	# ---------------------------------------------------------------- P1 ---
	# 从 (9,1) 走向 (9,2) 后按 Q：末步方向 (0,1)，面向格就是压力板 → 应落 (9,3)
	var lm1 := _mk_lm(root)
	_arm(lm1, NORTH_OF)
	h.eq(lm1.tc.current_t, 1, "P1 前置：当前 T1")
	h.eq(lm1.tc.inventory.size(), 1, "P1 前置：手持砝码 1 件")
	h.eq(lm1.tc.player_pos, NORTH_OF, "P1 前置：站在 (9,1)")

	lm1._teleport_to(STAND_AT)
	h.eq(lm1.tc.player_pos, STAND_AT, "P1：已走到 (9,2)")
	h.eq(lm1._facing, Vector2i(0, 1), "P1：朝向 = 末步方向 (0,1)")
	lm1._do_place()
	h.eq(_weight_at(lm1), PLATE, "P1：砝码落在压力板 (9,3)")
	h.ck(lm1.tc.plate_pressed(1), "P1：plate_pressed(T1) == true")
	h.eq(lm1.tc.inventory.size(), 0, "P1：背包已空")

	# ---------------------------------------------------------------- P2 ---
	# 从南面 (9,3) 进入 (9,2)：朝向 (0,-1)，面向格是**空地 (9,1)** → 仍应落 (9,3)
	var lm2 := _mk_lm(root)
	_arm(lm2, PLATE)
	h.eq(lm2.tc.player_pos, PLATE, "P2 前置：站在压力板 (9,3)")
	lm2._teleport_to(STAND_AT)
	h.eq(lm2._facing, Vector2i(0, -1), "P2：朝向 = 末步方向 (0,-1)")
	h.eq(lm2._facing_cell(), NORTH_OF, "P2：面向格是空地 (9,1)")
	lm2._do_place()
	h.eq(_weight_at(lm2), PLATE, "P2：★ 仍落在 (9,3)（U3 容器格吸附优先于空地）")
	h.ck(lm2.tc.plate_pressed(1), "P2：plate_pressed(T1) == true")
	# ---- 诊断（用于严重度评估，不是验收点）：放错格子后的实际后果 ----
	h.ck(not lm2.tc.is_blocked(NORTH_OF, 1), "P2-诊断（修复后）：砝码已上压力板 (9,3)，(9,1) 咽喉保持畅通")
	h.ck(lm2.tc.take(&"WEIGHT"), "P2-诊断：仍可从 (6,2) 把砝码取回（可自救，非硬死局）")

	# ---------------------------------------------------------------- P3 ---
	# 纯逻辑隔离：不走步，直接构造 _facing=(0,-1)，排除走路因素
	var lm3 := _mk_lm(root)
	_arm(lm3, STAND_AT)
	lm3._facing = Vector2i(0, -1)
	h.eq(lm3._facing_cell(), NORTH_OF, "P3 前置：面向格 = 空地 (9,1)")
	lm3._do_place()
	h.eq(_weight_at(lm3), PLATE, "P3：★ 落在 (9,3) 而非 (9,1)（隔离走路，定位 U1 还是 U3）")
	h.ck(lm3.tc.plate_pressed(1), "P3：plate_pressed(T1) == true")

	# ---------------------------------------------------------------- P4 ---
	# 接 P1：放置结果跨时刻正向传播
	lm1._transition = 0.0
	lm1._try_shift(1)                 # T1 → T2
	h.eq(lm1.tc.current_t, 2, "P4：已切到 T2")
	h.eq(lm1.tc.resolve_state(lm1.level.get_entity(&"WEIGHT"), 2).pos, PLATE,
		"P4：★ resolve_state(WEIGHT,T2).pos == (9,3)")
	h.ck(lm1.tc.plate_pressed(2), "P4：★ plate_pressed(T2) == true")
	h.ck(lm1.tc.grate_open(2), "P4：★ grate_open(T2) == true")
	h.ck(not lm1.tc.is_blocked(Vector2i(10, 2), 2), "P4：闸门格 (10,2) 在 T2 可通行")

	# ---------------------------------------------------------------- P5 ---
	# 接 P4：端到端通关 + 时砂 10（验证 start_t=2 是免费起点、不计 SHIFT 消耗）
	lm1._teleport_to(Vector2i(11, 1))
	h.eq(lm1.tc.player_pos, Vector2i(11, 1), "P5：抵达 (11,1)")
	h.ck(lm1.tc.won, "P5：★ check_win == true")
	h.ck(lm1.tc.evaluate_win(), "P5：evaluate_win() == true")
	h.eq(lm1.tc.hourglass, 10, "P5：★ 时砂剩余 10（12 − 2 次相邻切换）")

	# ---------------------------------------------------------------- P6 ---
	# 朝向随走路更新：从 (3,5) 走到 (9,2)，末步必为 (0,1)（(9,2) 只能从北/南进，
	# 而南面的 (9,3) 只能经 (9,2) 到达 ⇒ BFS 必经 (9,1)→(9,2)）
	var lm6 := _mk_lm(root)
	_arm(lm6, Vector2i(3, 5), false)
	h.eq(lm6.tc.player_pos, Vector2i(3, 5), "P6 前置：站在起点 (3,5)")
	h.eq(lm6.tc.inventory.size(), 0, "P6 前置：空手")
	# 先看路径（find_path 不移动玩家，纯查询），再走 lm 的入口刷新 _facing
	var path6: Array = lm6.tc.find_path(Vector2i(3, 5), STAND_AT)
	h.ck(path6.size() >= 2, "P6：(3,5) → (9,2) 路径存在（%d 格）" % path6.size())
	if path6.size() >= 2:
		var last_step: Vector2i = path6[path6.size() - 1] - path6[path6.size() - 2]
		h.eq(last_step, Vector2i(0, 1), "P6：路径末步方向 = (0,1)（(9,2) 只能从北/南进，南面必经 (9,2)）")
	lm6._teleport_to(STAND_AT)
	h.eq(lm6.tc.player_pos, STAND_AT, "P6：已走到 (6,2)")
	h.eq(lm6._facing, Vector2i(0, 1), "P6：★ 到达时 _facing == (0,1)")
	h.eq(lm6._facing_cell(), PLATE, "P6：★ 面向格 = (9,3)，take/use 命中的是压力板")
	var tgt = lm6._interactive_at(lm6._facing_cell())
	h.ck(tgt != null and String(tgt.id) == "PLATE",
		"P6：面向格上的实体 = PLATE（实际：%s）" % (String(tgt.id) if tgt != null else "null"))

	for lm in [lm1, lm2, lm3, lm6]:
		if root != null:
			root.remove_child(lm)
		lm.free()
