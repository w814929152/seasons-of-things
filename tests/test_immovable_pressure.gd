class_name TestImmovablePressure
extends RefCounted
##
## 验收 6（GDD §3.4 硬规则）：
##   IMMOVABLE / OCCLUDED / HOT **只影响玩家能否持取**，绝不影响占位与压感。
##   砝码在压力板上锈死 → 压力板照样被压住 → 闸门照样开着。这是**正确行为**。
##

static func run(h: TestHarness) -> void:
	h.suite("形态锁不影响占位/压感")

	var tc := TestHarness.new_game()
	var w := tc.level.get_entity(&"WEIGHT")
	var plate := Vector2i(9, 3)

	# 基线：T2 砝码形态 = WEIGHT_SEIZED，带 IMMOVABLE + PRESSER
	var s2 := tc.resolve_state(w, 2)
	h.eq(String(s2.form), "WEIGHT_SEIZED", "T2 砝码形态 = WEIGHT_SEIZED")
	h.ck(s2.tags.has("IMMOVABLE"), "T2 砝码带 IMMOVABLE")
	h.ck(s2.tags.has("PRESSER"), "T2 砝码仍带 PRESSER（形态锁不摘标签）")
	h.ck(not s2.available, "T2 砝码不可取（形态锁生效）")
	h.ck(not tc.plate_pressed(2), "初始 T2 压力板未压（砝码还在 (1,2)）")

	# 在 T1 把砝码搬到压力板：只写 pos，forward 传播
	tc.add_override(&"pos", &"WEIGHT", plate, 1)
	h.eq(tc.resolve_state(w, 1).pos, plate, "T1 砝码已在压力板上")
	h.eq(tc.resolve_state(w, 2).pos, plate, "T2 砝码仍在压力板上（正向传播）")
	h.eq(tc.resolve_state(w, 3).pos, plate, "T3 砝码仍在压力板上（正向传播）")
	h.eq(tc.resolve_state(w, 0).pos, Vector2i(1, 2), "T0 不受影响（绝不向过去传播）")

	# ★ 核心断言：T2 形态是 IMMOVABLE，但压力板照样 pressed
	var t2 := tc.resolve_state(w, 2)
	h.eq(String(t2.form), "WEIGHT_SEIZED", "T2 形态仍是锈死（放置不冻结形态）")
	h.ck(t2.tags.has("IMMOVABLE"), "T2 仍是 IMMOVABLE")
	h.ck(tc.plate_pressed(2), "★ 压力板仍为 pressed —— 形态锁不影响压感")
	h.ck(tc.grate_open(2), "★ 闸门随之开启（派生：open = pressed）")
	h.ck(not tc.is_blocked(Vector2i(10, 2), 2), "★ 闸门格 (10,2) 在 T2 可通行")

	# T3（OCCLUDED）同样不影响压感
	var t3 := tc.resolve_state(w, 3)
	h.eq(String(t3.form), "WEIGHT_BURIED", "T3 形态 = WEIGHT_BURIED")
	h.ck(t3.tags.has("OCCLUDED"), "T3 带 OCCLUDED")
	h.ck(tc.plate_pressed(3), "★ T3 压力板仍为 pressed（OCCLUDED 不影响压感）")

	# T0（HOT）同样带 PRESSER
	var t0 := tc.resolve_state(w, 0)
	h.eq(String(t0.form), "MOLTEN", "T0 形态 = MOLTEN")
	h.ck(t0.tags.has("HOT"), "T0 带 HOT")
	h.ck(t0.tags.has("PRESSER"), "T0 也带 PRESSER")

	# 形态锁确实阻止持取（另一面：它**只**阻止持取）
	var fresh := TestHarness.new_game()
	fresh.player_pos = Vector2i(1, 3)
	h.ck(not fresh.take(&"WEIGHT"), "T2 锈死：持取被拒绝")
	h.eq(fresh.inventory.size(), 0, "背包仍为空")
	fresh.shift(-1)                                        # → T1
	h.eq(String(fresh.resolve_state(fresh.level.get_entity(&"WEIGHT"), 1).form), "WEIGHT_OK", "T1 形态完好")
	h.ck(fresh.take(&"WEIGHT"), "T1 可取（形态锁只在该时刻生效）")
