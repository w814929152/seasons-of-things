class_name TestResolvePure
extends RefCounted
##
## 验收 1：resolve_state 是纯函数 —— 同输入必同输出；且**绝不**影响 t < t_index 的时刻。
## 验收 8：override 绝不向过去传播（对每个 t 逐字段比对基线）。
##

static func run(h: TestHarness) -> void:
	h.suite("resolve_state 纯函数 / 绝不向过去传播")

	var tc := TestHarness.new_game()
	var lv := tc.level
	var key := lv.get_entity(&"KEY")

	# --- 纯函数：无 override 时重复求值结果一致 ---
	var a1 := tc.resolve_state(key, 1)
	var a2 := tc.resolve_state(key, 1)
	h.ck(a1.equals(a2), "同一输入两次求值结果一致")
	h.eq(String(a1.form), "KEY_NEW", "T1 基线形态 = KEY_NEW")
	h.eq(a1.pos, Vector2i(3, 2), "T1 基线位置 = (3,2)")
	h.ck(a1.available, "T1 基线可取")

	# --- 基线：全部时刻、全部实体的快照 ---
	var base: Array = tc.snapshot_all()

	# --- 在 T2 写入一条 forward override（模拟「T2 取走钥匙」）---
	tc.add_override(&"pos", &"KEY", StateFrame.POS_VOID, 2)
	var after: Array = tc.snapshot_all()

	# t=0 / t=1 必须逐字段完全不变
	var d01 := TestHarness.diff_snapshots([base[0], base[1]], [after[0], after[1]])
	h.ck(d01.is_empty(), "写入 @T2 后，T0/T1 逐字段无变化" + ("  diff=" + str(d01) if not d01.is_empty() else ""))

	# t=2 / t=3 必须生效
	h.eq(tc.resolve_state(key, 2).pos, StateFrame.POS_VOID, "T2 生效：钥匙缺席")
	h.eq(tc.resolve_state(key, 3).pos, StateFrame.POS_VOID, "T3 生效（forward 传播）")
	h.eq(String(tc.resolve_state(key, 0).form), "INGOT", "T0 仍是金属锭（不受影响）")
	h.eq(String(tc.resolve_state(key, 1).form), "KEY_NEW", "T1 仍是崭新钥匙（不受影响）")

	# --- 再在 T1 写一条：T0 必须仍然不变 ---
	var base2: Array = tc.snapshot_all()
	tc.add_override(&"pos", &"KEY", StateFrame.POS_VOID, 1)
	h.eq(tc.resolve_state(key, 0).pos, Vector2i(3, 2), "写入 @T1 后 T0 位置仍为 (3,2)")
	var d0 := TestHarness.diff_snapshots([base2[0]], [tc.snapshot(0)])
	h.ck(d0.is_empty(), "写入 @T1 后 T0 逐字段无变化")
	h.eq(tc.resolve_state(key, 1).pos, StateFrame.POS_VOID, "T1 生效（写入点自身生效）")

	# --- 后写覆盖先写（seq 升序）---
	var fresh := TestHarness.new_game()
	fresh.add_override(&"pos", &"KEY", Vector2i(9, 9), 0)
	fresh.add_override(&"pos", &"KEY", Vector2i(1, 1), 0)
	h.eq(fresh.resolve_state(fresh.level.get_entity(&"KEY"), 0).pos, Vector2i(1, 1),
		"后写覆盖先写（seq 升序）")

	# --- 锚定物不接受未许可字段 ---
	var gate := fresh.level.get_entity(&"GATE")
	fresh.add_override(&"pos", &"GATE", Vector2i(0, 0), 0)
	h.eq(fresh.resolve_state(gate, 0).pos, Vector2i(7, 1), "锚定门不接受 pos 覆盖")
	fresh.add_override(&"open", &"GATE", true, 0)
	h.ck(fresh.resolve_state(gate, 0).open, "锚定门接受 open 覆盖（GDD §6）")

	# --- 纯函数：带 override 时重复求值一致 ---
	var r1 := fresh.resolve_state(fresh.level.get_entity(&"KEY"), 2)
	var r2 := fresh.resolve_state(fresh.level.get_entity(&"KEY"), 2)
	h.ck(r1.equals(r2), "带 override 时重复求值结果一致")

	# --- 越界保护 ---
	h.ck(fresh.level.timepoint_count() == 4, "时刻数 = 4")
