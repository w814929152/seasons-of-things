extends SceneTree
##
## headless 断言测试入口。
##
## 跑法（Windows / console 版 exe）：
##   "C:/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" \
##     --headless --path "D:/New test" --script res://tests/test_main.gd
##
## 退出码 0 = 全部通过；1 = 有失败。
## 门禁要求：PASS 全绿 **且** 日志里 ERROR 计数 = 0。
##

func _initialize() -> void:
	var h := TestHarness.new()

	# ★ 必须等一帧再建节点：SceneTree 的 root 在 _initialize() 阶段
	#   is_inside_tree() 仍是 false（实测），此时 add_child() **不会**触发子节点的
	#   _ready()，任何依赖 _ready 建控件的用例（HUD 刻度尺/沙漏/背包）都会拿到 null
	#   并刷出一堆 ERROR。等一个 process_frame 后 root 就绪，行为与真实运行时一致。
	await process_frame

	print("════════ 《物候》headless 断言测试 ════════")
	TestResolvePure.run(h)
	TestUndoRestore.run(h)
	TestImmovablePressure.run(h)
	TestLevel01Solvable.run(h)
	TestDeadlockAndWin.run(h)
	TestSceneWiring.run(h, root)
	TestPlaceTargetP1P6.run(h, root)
	TestHudRefresh.run(h, root)
	TestHudLayout.run(h, root)
	TestMovement.run(h, root)
	TestAcceptance11.run(h)
	# 提示条布局专项需要等容器排序帧，因此是协程 —— 用 await 接住
	await TestHintLayout.run_async(h, root)

	# ---- 输入映射（关卡文档 §10 键位表）----
	h.suite("输入映射 / 键位冲突排查")
	var want: Array[String] = ["shift_prev", "shift_next", "take", "place",
		"use", "observe", "undo", "hint", "reset",
		"move_up", "move_down", "move_left", "move_right"]
	for a in want:
		h.ck(InputMap.has_action(a), "已注册输入动作：%s" % a)

	# ⚠ E 只绑定 Use，绝不复用为切时刻
	# （只统计本项目的动作；ui_* 是引擎内置的编辑器/文本编辑动作，不属于游戏动词）
	var e_owners: Array[String] = []
	for a in want:
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey and (ev as InputEventKey).keycode == KEY_E:
				e_owners.append(String(a))
	h.eq(e_owners, ["use"], "E 键只绑定 use（实际绑定：%s）" % str(e_owners))

	# A/D 只绑定切时刻
	var ad_owners: Array[String] = []
	for a in want:
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey:
				var kc := (ev as InputEventKey).keycode
				if kc == KEY_A or kc == KEY_D:
					ad_owners.append(String(a))
	ad_owners.sort()
	h.eq(ad_owners, ["shift_next", "shift_prev"], "A/D 只绑定切时刻")

	# 空格只绑定持取
	var sp_owners: Array[String] = []
	for a in want:
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey and (ev as InputEventKey).keycode == KEY_SPACE:
				sp_owners.append(String(a))
	h.eq(sp_owners, ["take"], "空格只绑定持取")

	# ★ 方向键只做移动（第七轮改造：切时刻收敛到 A/D，把 ←↑↓→ 让给移动）
	var arrow_keys := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
	var arrow_owners: Array[String] = []
	for a in want:
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey and arrow_keys.has((ev as InputEventKey).keycode):
				arrow_owners.append(String(a))
	arrow_owners.sort()
	h.eq(arrow_owners, ["move_down", "move_left", "move_right", "move_up"],
		"方向键只绑定 move_*（实际绑定：%s）" % str(arrow_owners))

	# 每个 move_* 恰好绑一个键，且确实是方向键 —— 防止误配成 u/i/j/k 之类
	var arrow_expect := {
		"move_up": KEY_UP, "move_down": KEY_DOWN,
		"move_left": KEY_LEFT, "move_right": KEY_RIGHT,
	}
	for a in arrow_expect.keys():
		var evs := InputMap.action_get_events(a)
		h.eq(evs.size(), 1, "%s 恰好绑定 1 个键" % a)
		if evs.size() == 1 and evs[0] is InputEventKey:
			h.eq((evs[0] as InputEventKey).keycode, arrow_expect[a],
				"%s 绑定 %s" % [a, OS.get_keycode_string(arrow_expect[a])])

	print("")
	print("═══════════════════════════════════════════")
	print("[SELFTEST] pass = ", h.pass_count(), "   fails = ", h.fail_count())
	for f in h.failures():
		print("  FAIL  ", f)
	print("[SELFTEST] ", "ALL PASS" if h.fail_count() == 0 else "HAS FAILURES")
	print("═══════════════════════════════════════════")
	quit(1 if h.fail_count() > 0 else 0)
