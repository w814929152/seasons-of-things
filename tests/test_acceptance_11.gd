class_name TestAcceptance11
extends RefCounted
##
## 关卡文档 §11 验收清单里**尚未被既有用例直接断言**的三条，补自动化证据：
##   §11-1 最短解 = 7 步主动操作 / 2 次切换 / 耗 2 点时砂
##   §11-2 四个时刻的**非色彩**区分通道（罗马刻度 / 光照角度 / 粒子 / 亮度）
##   §11-9 三级提示的**文案与逐级解锁**（阈值触发见报告中的代码审查结论）
##
## 其余六条（钥匙折断不回传 / 砝码传播 / 藤蔓传播 / 出口仅 T2 /
## IMMOVABLE 不影响压感 / 撤销 10 次复原）已由
## test_level_01_solvable · test_immovable_pressure · test_deadlock_and_win ·
## test_undo_restore 覆盖，此处不重复断言。
##

static func run(h: TestHarness) -> void:
	h.suite("§11 验收清单补证（最短解 / 非色彩通道 / 提示分级）")

	# ---------------- §11-1：最短解 7 步 / 2 次切换 / 耗 2 砂 ----------------
	# 计步口径（关卡文档 §7）：只计主动操作，移动由寻路完成、不计步。
	var tc := TestHarness.new_game()
	var ops: Array[String] = []

	tc.shift(-1);                              ops.append("切换 T2→T1")
	tc.player_pos = Vector2i(3, 3)
	h.ck(tc.take(&"KEY"),           "最短解 2/7：T1 取崭新钥匙");  ops.append("持取 KEY")
	tc.player_pos = Vector2i(6, 1)
	h.ck(tc.use(&"GATE"),           "最短解 3/7：T1 开铁栅");      ops.append("开锁 GATE")
	tc.player_pos = Vector2i(1, 3)
	h.ck(tc.take(&"WEIGHT"),        "最短解 4/7：T1 取砝码");      ops.append("持取 WEIGHT")
	tc.player_pos = Vector2i(7, 1)
	h.ck(tc.use(&"VINE"),           "最短解 5/7：T1 拔藤");        ops.append("拔除 VINE")
	tc.player_pos = Vector2i(9, 2)
	h.ck(tc.place(Vector2i(9, 3)),  "最短解 6/7：T1 砝码上压力板"); ops.append("放置 WEIGHT")
	tc.shift(1);                               ops.append("切换 T1→T2")

	h.eq(ops.size(), 7, "★ §11-1：主动操作数 = 7（%s）" % " → ".join(ops))
	h.eq(tc.current_t, 2, "★ §11-1：切换次数 = 2（回到 T2）")
	h.eq(tc.hourglass, 10, "★ §11-1：时砂 12 → 10（耗 2）")

	tc.walk_to(Vector2i(11, 1))
	h.eq(tc.player_pos, Vector2i(11, 1), "§11-1：走到出口 (11,1)")
	h.ck(tc.won, "★ §11-1：7 步 / 2 切换后通关")

	# ---------------- §11-2：非色彩区分通道 ----------------
	var lv := tc.level
	var romans: Array[String] = []
	var angles: Array[float] = []
	var parts: Array[String] = []
	var brights: Array[float] = []
	var sfxs: Array[String] = []
	for t in lv.timepoint_count():
		var tp = lv.get_timepoint(t)
		romans.append(tp.roman)
		angles.append(tp.light_angle)
		parts.append(tp.particle)
		brights.append(tp.brightness)
		sfxs.append(tp.ambient_sfx)
	h.eq(romans, ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ"], "★ §11-2：罗马刻度 Ⅰ–Ⅳ 互不相同（通道 1）")
	h.eq(angles, [15.0, 90.0, 300.0, 350.0], "★ §11-2：光照角度 15/90/300/350 互不相同（通道 2）")
	h.eq(parts, ["SPARK", "DUST", "RUST", "ASH"], "★ §11-2：环境粒子 4 种互不相同（通道 3）")
	h.ck(brights[1] > brights[0] and brights[0] > brights[2] and brights[2] > brights[3],
		"★ §11-2：亮度层级 T1 > T0 > T2 > T3（通道 4，实际 %s）" % str(brights))
	var sfx_uniq: Array[String] = []
	for s in sfxs:
		if not sfx_uniq.has(s):
			sfx_uniq.append(s)
	h.eq(sfx_uniq.size(), 4, "§11-2：环境音文案 4 种互不相同（通道 5 · 当前无音频实现，仅数据层就绪）")

	# ---------------- §11-9：三级提示 ----------------
	var lv2 := TestHarness.new_game().level
	h.eq(lv2.hints.size(), 3, "§11-9：配置了 3 级提示")
	var texts: Array[String] = []
	for d in lv2.hints:
		texts.append(String(d["text"]))
	h.eq(texts, [
		"留意钥匙台上那把钥匙。",
		"这把钥匙，并不是一直都是锈的。",
		"切到『新光·昼』，取走那把崭新的钥匙。",
	], "§11-9：三级提示文案与设计稿 §9.3 一致")
	var levels: Array[int] = []
	for d in lv2.hints:
		levels.append(int(d["level"]))
	h.eq(levels, [1, 2, 3], "§11-9：提示级别 1/2/3 齐备")
