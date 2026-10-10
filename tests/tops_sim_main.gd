extends SceneTree
##
## 陀螺对战 · 纸面数值模拟入口（design/tops/core_mechanic_design.md §7）
##
## 跑法（Windows / console 版 exe）：
##   "C:/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" \
##     --headless --path "D:/New test" --script res://tests/tops_sim_main.gd              # 全量实验
##   ... --script res://tests/tops_sim_main.gd -- tuned                                   # 只跑定稿验证
##
## 退出码 0 = 三类失败信号均未触发；1 = 有信号触发（数值需要重画）。
## 结果表写入 res://docs/tops/sim_results.md（tuned 模式写 sim_results_tuned.md）
##

# 判定阈值（对应 §7 失败信号）
const DUEL_WR_MIN: float = 0.25       # A 类：胜率低于此 = 被碾压
const DUEL_WR_MAX: float = 0.75       # A 类：胜率高于此 = 纯碾压
const MATCH_MIN: float = 150.0        # B 类：单局时长下限（3 min - 30s）
const MATCH_MAX_OK: float = 330.0     # B 类：单局时长上限（5 min + 30s）
const FIRST_HIT_MAX: float = 20.0     # B 类：开局冷场上限
const QUARTER_MIN: float = 0.20       # B 类：最冷 1/4 段撞击占比 ≥ 峰值段的此比例
const CAMP_RATIO_MAX: float = 0.70    # Pillar 2：蹲边缘寿命 / 待中心寿命，高于此 = 苟得住

const OUT_FULL := "res://docs/tops/sim_results.md"
const OUT_TUNED := "res://docs/tops/sim_results_tuned.md"


func _initialize() -> void:
	var h := TestHarness.new()
	var mode := "full"
	var variant := "v03"
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s == "tuned":
			mode = "tuned"
		elif s == "v04":
			mode = "tuned"
			variant = "v04"

	var quick := false
	for a in OS.get_cmdline_user_args():
		if String(a) == "quick":
			quick = true

	print("════════ 陀螺对战 · 纸面数值模拟（mode=%s / %s / quick=%s）════════"
		% [mode, variant, str(quick)])
	var r: Dictionary
	if mode == "tuned":
		r = TopSimRun.run_tuned(24, 10, variant) if quick else TopSimRun.run_tuned(40, 20, variant)
	else:
		r = TopSimRun.run_all(24, 10, 3) if quick else TopSimRun.run_all(40, 20, 6)

	if r.has("decouple_damage"):
		_check_decouple(h, r)
	if r.has("hits"):
		_check_pillar1(h, r)
	_check_duel(h, r)
	_check_melee(h, r)
	if r.has("camp"):
		_check_camp(h, r)

	var text := TopSimRun.to_text_tuned(r) if mode == "tuned" else TopSimRun.to_text(r)
	print("")
	print(text)
	var out: String = OUT_FULL
	if mode == "tuned":
		out = OUT_TUNED if variant == "v03" else OUT_TUNED.replace(".md", "_v04.md")
	_write(out, text)

	print("")
	print("═══════════════════════════════════════════")
	print("[TOPSIM] pass = ", h.pass_count(), "   fails = ", h.fail_count())
	for f in h.failures():
		print("  FAIL  ", f)
	print("[TOPSIM] ", "ALL PASS" if h.fail_count() == 0 else "HAS FAILURES")
	print("═══════════════════════════════════════════")
	quit(1 if h.fail_count() > 0 else 0)


# ── S0 双轴解耦 ──
func _check_decouple(h: TestHarness, r: Dictionary) -> void:
	h.suite("S0-A 解耦：扣转速只随 Δspin，与速度无关")
	var dd: Array = r["decouple_damage"]
	var dmg0: float = float(dd[0]["dmg_low"])
	var same: bool = true
	for row in dd:
		if absf(float(row["dmg_low"]) - dmg0) > 0.0001:
			same = false
	h.ck(same, "对撞速度 40→320，低转速方扣血恒为 %s（速度不影响伤害）" % TopSimRun.f2(dmg0))
	var speeds: Array = []
	for row in dd:
		speeds.append(float(row["speed_low"]))
	h.ck(speeds[3] > speeds[0] * 2.0,
		"同一 Δspin 下，速度 320 的撞后速度 %s 远大于速度 40 的 %s（速度只服务位置控制）"
		% [TopSimRun.f1(speeds[3]), TopSimRun.f1(speeds[0])])

	h.suite("S0-B 解耦：击飞只随 Δp，与 Δspin 无关")
	var dk: Array = r["decouple_knock"]
	var bal_bonus := 0.0
	var ram_bonus := 0.0
	var bal_speed := 0.0
	var ram_speed := 0.0
	var dmg_same := true
	for row in dk:
		if String(row["pair"]).begins_with("BALANCED vs BALANCED"):
			bal_bonus = float(row["knock_bonus"])
			bal_speed = float(row["speed_low"])
		if String(row["pair"]).begins_with("RAM vs DART"):
			ram_bonus = float(row["knock_bonus"])
			ram_speed = float(row["speed_low"])
		if absf(float(row["dmg_low"]) - dmg0) > 0.0001:
			dmg_same = false
	h.ck(dmg_same, "质量组合改变（Δp 变），低转速方扣血不变（伤害与动量无关）")
	h.ck(bal_bonus < 0.0001, "Δp=0（BAL×BAL 等速对撞）时击飞加成为 0")
	h.ck(ram_bonus > 1.0, "Δp=225（RAM×DART）时击飞加成 %s > 0（击飞只由动量差产生）"
		% TopSimRun.f1(ram_bonus))
	h.ck(ram_speed > bal_speed * 1.5, "RAM×DART 低转速方撞后速度 %s 显著大于 BAL×BAL 的 %s"
		% [TopSimRun.f1(ram_speed), TopSimRun.f1(bal_speed)])


# ── S1 Pillar 1 ──
func _check_pillar1(h: TestHarness, r: Dictionary) -> void:
	h.suite("S1 Pillar 1：撞击双方都付出转速代价")
	for row in r["hits"]:
		h.ck(float(row["dmg_a"]) > 0.0 and float(row["dmg_b"]) > 0.0,
			"「%s」双方均掉转速（A -%s / B -%s）" % [row["name"],
			TopSimRun.f2(row["dmg_a"]), TopSimRun.f2(row["dmg_b"])])


# ── S2 A 类失败信号 ──
func _check_duel(h: TestHarness, r: Dictionary) -> void:
	h.suite("S2 A 类失败信号：是否存在纯碾压")
	for row in r["duel"]:
		var wa: float = float(row["wr_a"])
		h.ck(wa >= DUEL_WR_MIN and wa <= DUEL_WR_MAX,
			"%s vs %s 胜率 %s / %s 落在 [%s, %s]（无碾压）" % [row["a"], row["b"],
			TopSimRun.f2(wa), TopSimRun.f2(row["wr_b"]),
			TopSimRun.f2(DUEL_WR_MIN), TopSimRun.f2(DUEL_WR_MAX)])


# ── S3 B 类失败信号 ──
func _check_melee(h: TestHarness, r: Dictionary) -> void:
	h.suite("S3 B 类失败信号：单局时长 / 节奏形状")
	var m: Dictionary = r["melee"]
	h.ck(float(m["avg_time"]) >= MATCH_MIN and float(m["avg_time"]) <= MATCH_MAX_OK,
		"平均单局 %s s 落在 3–5 min 区间（%s–%s）" % [TopSimRun.f1(m["avg_time"]),
		TopSimRun.f1(MATCH_MIN), TopSimRun.f1(MATCH_MAX_OK)])
	if m.has("first_hit"):
		h.ck(float(m["first_hit"]) <= FIRST_HIT_MAX,
			"首次撞击在 %s s 内（开局不冷场）" % TopSimRun.f1(m["first_hit"]))
		var q: Array = m["quarters"]
		var peak := 0.0
		var low := INF
		for v in q:
			peak = maxf(peak, float(v))
			low = minf(low, float(v))
		h.ck(low >= peak * QUARTER_MIN,
			"最冷 1/4 段撞击 %s ≥ 峰值段 %s 的 %s（四等分 %s，后期不闷）"
			% [TopSimRun.f1(low), TopSimRun.f1(peak), TopSimRun.f2(QUARTER_MIN),
			TopSimRun._fmt_quarters(q)])
	if m.has("boredom") and r.has("sweep"):
		h.ck(float(m["boredom"]) >= 0.20,
			"沉闷指数 %s ≥ 0.20（后 1/3 未断流）" % TopSimRun.f2(m["boredom"]))
	h.ck(int(m["timeouts"]) == 0, "无超时未分胜负局（%d 局）" % int(m["timeouts"]))


# ── S4 Pillar 2 ──
func _check_camp(h: TestHarness, r: Dictionary) -> void:
	h.suite("S4 Pillar 2：蹲边缘苟不住")
	var center_life := 0.0
	var camp_life := 0.0
	for row in r["camp"]:
		if float(row["edge_mult"]) > 2.0 and String(row["mode"]) == "center_idle":
			center_life = float(row["life"])
		if float(row["edge_mult"]) > 2.0 and String(row["mode"]) == "edge_camp":
			camp_life = float(row["life"])
	h.ck(camp_life < center_life * CAMP_RATIO_MAX,
		"蹲边缘寿命 %s s < 待中心 %s s 的 %s 倍（苟不住）" % [TopSimRun.f1(camp_life),
		TopSimRun.f1(center_life), TopSimRun.f2(CAMP_RATIO_MAX)])


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("tops_sim_main: 无法写入 %s" % path)
		return
	f.store_string(text)
	f.close()
	print("结果表已写入：", path)
