extends SceneTree
##
## 陀螺 · **物理版**批量数值模拟（headless）
##
## 为什么还要再来一个模拟器：纸面模型（tops/sim + tests/tops_sim_main.gd）假设
## 撞击是离散事件；换成真实 RigidBody2D 后，弹开会引发反复接触，撞击频率涨了 4 倍以上
## （纸面 0.32 次/秒 → 物理 1.44 次/秒），纸面定稿参数不再成立。本文件直接在真物理上扫参。
##
## 跑法：
##   "Godot_..._console.exe" --headless --path "D:/New test" --script res://tests/tops_phys_sim.gd
##   "Godot_..._console.exe" --headless --path "D:/New test" --script res://tests/tops_phys_sim.gd -- quick
##
## 每帧物理步长固定为 1/30 s（physics_ticks × time_scale 同比例放大），
## 与实机 1/60 s 有细微差别，但足以比较参数组的相对趋势。
##

const TICKS := 1200          # 物理频率
const SPEEDUP := 40.0        # 时间倍速 → 每步 dt = 40/1200 = 1/30 s
const MATCHES := 3           # 每组参数跑几局
const GUARD := 30000         # 步数上限（≈1000 s 游戏时间）


func _initialize() -> void:
	var mode := "all"
	for a in OS.get_cmdline_user_args():
		if a == "quick":
			mode = "quick"
		elif a == "late":
			mode = "late"
	print("════════ 陀螺 · 物理版批量数值模拟 ════════")
	await process_frame

	var variants := _variants()
	if mode == "quick":
		variants = variants.slice(0, mini(3, variants.size()))
	elif mode == "late":
		variants = variants.slice(12, 15)

	for v in variants:
		await _run_variant(v)

	print("")
	print("═══════════════════════════════════════════")
	print("[TOPSPHYS] 扫参完成")
	print("═══════════════════════════════════════════")
	TopsRules.reset_tuning()
	quit(0)


func _variants() -> Array[Dictionary]:
	return [
		{"name": "v_base 当前默认（物理版初值）", "d": {
			"shrink_start": 40.0, "shrink_rate": 0.004}},
		{"name": "v_a 砍撞墙：wall 2.0→0.8 / cd 0.6→1.0", "d": {
			"wall": 0.8, "wall_cd": 1.0, "shrink_start": 40.0, "shrink_rate": 0.004}},
		{"name": "v_b 再砍撞击：chip 1.2→0.6 / cd 0.25→0.5", "d": {
			"wall": 0.8, "wall_cd": 1.0, "chip": 0.6, "contact_cd": 0.5,
			"shrink_start": 40.0, "shrink_rate": 0.004}},
		{"name": "v_c 再砍衰减：decay 0.35→0.18", "d": {
			"wall": 0.8, "wall_cd": 1.0, "chip": 0.6, "contact_cd": 0.5, "decay": 0.18,
			"shrink_start": 40.0, "shrink_rate": 0.004}},
		{"name": "v_d v_c + 缩圈延后加快（60s 起 / 0.006）", "d": {
			"wall": 0.8, "wall_cd": 1.0, "chip": 0.6, "contact_cd": 0.5, "decay": 0.18,
			"shrink_start": 60.0, "shrink_rate": 0.006}},
		{"name": "v_e v_d + 击倒回血减半（15→8）", "d": {
			"wall": 0.8, "wall_cd": 1.0, "chip": 0.6, "contact_cd": 0.5, "decay": 0.18,
			"shrink_start": 60.0, "shrink_rate": 0.006, "kill_heal": 8.0}},
		{"name": "v_f 全面再砍一刀（wall .5 / chip .45 / decay .12）", "d": {
			"wall": 0.5, "wall_cd": 1.0, "chip": 0.45, "contact_cd": 0.5, "decay": 0.12,
			"shrink_start": 60.0, "shrink_rate": 0.006, "kill_heal": 10.0}},
		{"name": "v_g v_f + 缩圈更早（30s 起 / 0.008）", "d": {
			"wall": 0.5, "wall_cd": 1.0, "chip": 0.45, "contact_cd": 0.5, "decay": 0.12,
			"shrink_start": 30.0, "shrink_rate": 0.008, "kill_heal": 10.0}},
		{"name": "v_h v_f + 衰减更低（decay .08）", "d": {
			"wall": 0.5, "wall_cd": 1.0, "chip": 0.45, "contact_cd": 0.5, "decay": 0.08,
			"shrink_start": 60.0, "shrink_rate": 0.006, "kill_heal": 10.0}},
		# ↓ 第二轮：主线是「让出局分散开」。等速掉血必然 everybody 一起死，
		#   只有把伤害更彻底地挂到 Δspin 上（差距自我放大）+ 提高击倒回血，才能拉开淘汰节奏。
		{"name": "v_i 放大分化：chip .45→.25 / coeff .06→.15 / heal 20", "d": {
			"wall": 0.5, "wall_cd": 1.0, "chip": 0.25, "coeff": 0.15, "contact_cd": 0.5,
			"decay": 0.12, "shrink_start": 60.0, "shrink_rate": 0.006, "kill_heal": 20.0}},
		{"name": "v_j 更极端分化：chip .15 / coeff .25 / heal 25", "d": {
			"wall": 0.5, "wall_cd": 1.0, "chip": 0.15, "coeff": 0.25, "contact_cd": 0.5,
			"decay": 0.12, "shrink_start": 60.0, "shrink_rate": 0.006, "kill_heal": 25.0}},
		{"name": "v_k 只提回血：v_f + heal 10→25", "d": {
			"wall": 0.5, "wall_cd": 1.0, "chip": 0.45, "contact_cd": 0.5,
			"decay": 0.12, "shrink_start": 60.0, "shrink_rate": 0.006, "kill_heal": 25.0}},
		# ↓ 第三轮：v_i 已进 180–300s 区间，但首个淘汰仍在 66% 处。试三招把它往前推。
		{"name": "v_l v_i + 缩圈更早更快（30s / 0.010）", "d": {
			"wall": 0.5, "wall_cd": 1.0, "chip": 0.25, "coeff": 0.15, "contact_cd": 0.5,
			"decay": 0.12, "shrink_start": 30.0, "shrink_rate": 0.010, "kill_heal": 20.0}},
		{"name": "v_m v_i + 衰减回到 0.20", "d": {
			"wall": 0.5, "wall_cd": 1.0, "chip": 0.25, "coeff": 0.15, "contact_cd": 0.5,
			"decay": 0.20, "shrink_start": 60.0, "shrink_rate": 0.006, "kill_heal": 20.0}},
		# ↓ 第四轮：用「位置」而不是「时间」制造分化（直接服务 Pillar 2 中心福地/边缘险地）
		{"name": "v_o v_i + 边缘惩罚加倍（decay .10 / edge 4.5 / band .65）", "d": {
			"wall": 0.5, "wall_cd": 1.0, "chip": 0.25, "coeff": 0.15, "contact_cd": 0.5,
			"decay": 0.10, "edge_mult": 4.5, "edge_ratio": 0.65,
			"shrink_start": 60.0, "shrink_rate": 0.006, "kill_heal": 20.0}},
		{"name": "v_p v_o + 回血 25", "d": {
			"wall": 0.5, "wall_cd": 1.0, "chip": 0.25, "coeff": 0.15, "contact_cd": 0.5,
			"decay": 0.10, "edge_mult": 4.5, "edge_ratio": 0.65,
			"shrink_start": 60.0, "shrink_rate": 0.006, "kill_heal": 25.0}},
		{"name": "v_n v_i + 撞墙回到 0.8", "d": {
			"wall": 0.8, "wall_cd": 1.0, "chip": 0.25, "coeff": 0.15, "contact_cd": 0.5,
			"decay": 0.12, "shrink_start": 60.0, "shrink_rate": 0.006, "kill_heal": 20.0}},
	]


func _run_variant(v: Dictionary) -> void:
	TopsRules.reset_tuning()
	var d: Dictionary = v["d"]
	TopsRules.apply_tuning(d)
	TopsMain.SHRINK_START = float(d.get("shrink_start", 40.0))
	TopsMain.SHRINK_RATIO_PER_SEC = float(d.get("shrink_rate", 0.004))
	TopsMain.SHRINK_MIN_RATIO = float(d.get("shrink_min", 0.50))

	var dur_sum := 0.0
	var contact_sum := 0.0
	var wall_sum := 0.0
	var first_sum := 0.0
	var quarter: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var wins: Dictionary = {}
	var timeouts := 0
	var death_slots: Array[float] = [0.0, 0.0, 0.0, 0.0]

	for m in MATCHES:
		var r := await _run_match(m + 1)
		dur_sum += float(r["dur"])
		contact_sum += float(r["contacts"])
		wall_sum += float(r["walls"])
		first_sum += float(r["first_death"])
		for i in 4:
			quarter[i] += float((r["quarters"] as Array)[i])
		if bool(r["timeout"]):
			timeouts += 1
		var ds: Array = r["deaths"]
		for i in mini(ds.size(), 4):
			death_slots[i] += float(ds[i])
		var w: String = r["winner"]
		wins[w] = int(wins.get(w, 0)) + 1

	var n := float(MATCHES)
	var dur: float = dur_sum / n
	print("")
	print("── %s" % String(v["name"]))
	print("   时长 %s s｜撞击 %s 次（%s 次/秒）｜撞墙 %s 次｜首杀 %s s｜超时 %d" % [
		_f1(dur), _f1(contact_sum / n),
		_f2(contact_sum / n / maxf(dur, 1.0)), _f1(wall_sum / n), _f1(first_sum / n), timeouts])
	var qs := ""
	for i in 4:
		qs += "Q%d=%s " % [i + 1, _f1(quarter[i] / n)]
	print("   撞击四等分：%s（越均匀越不沉闷）" % qs)
	var ds := ""
	for i in 4:
		ds += "第%d人=%ss " % [i + 1, _f1(death_slots[i] / n)]
	print("   出局时刻：%s（越分散越有来有回）" % ds)
	var ws := ""
	for k in wins.keys():
		ws += "%s×%d " % [k, int(wins[k])]
	print("   胜者：%s" % ws)


func _run_match(seed_i: int) -> Dictionary:
	var scene := load("res://tops/tops_main.tscn")
	var main: TopsMain = scene.instantiate() as TopsMain
	root.add_child(main)
	await process_frame

	# 每局把起始角度随机偏一点，避免多局完全重复
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * seed_i + 13
	for t in main._tops:
		var off: float = rng.randf_range(-0.6, 0.6)
		var p: Vector2 = t.global_position - TopsMain.CENTER
		t.global_position = TopsMain.CENTER + p.rotated(off)
		t.facing += off
	# 玩家不可操控 → 模拟器直接替玩家发射（力度也随机，覆盖发射强度这个决策维度）
	main._launch(rng.randf_range(0.5, 1.0))

	Engine.physics_ticks_per_second = TICKS
	Engine.time_scale = SPEEDUP

	var series_t: Array[float] = []
	var series_c: Array[float] = []
	var first_death := -1.0
	var deaths: Array[float] = []
	var prev_alive := 5
	var guard := 0
	var sample := 0
	while guard < GUARD and not main._finished:
		await physics_frame
		guard += 1
		sample += 1
		var now_alive: int = main._alive_count()
		if now_alive < prev_alive:
			for _k in prev_alive - now_alive:
				deaths.append(main._elapsed)
			prev_alive = now_alive
			if first_death < 0.0:
				first_death = main._elapsed
		if sample >= 30:  # 每 30 步采样一次（≈1 s 游戏时间）
			sample = 0
			series_t.append(main._elapsed)
			series_c.append(float(_total(main, "contacts")))

	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60

	var dur: float = main._elapsed
	var contacts: int = _total(main, "contacts")
	var walls: int = _total(main, "wall_hits")
	var winner := "-"
	for t in main._tops:
		if t.alive:
			winner = t.archetype

	var quarters := _split_quarters(series_t, series_c, dur)
	root.remove_child(main)
	main.free()
	return {
		"dur": dur, "contacts": contacts, "walls": walls,
		"first_death": first_death if first_death >= 0.0 else dur,
		"winner": winner, "quarters": quarters, "deaths": deaths,
		"timeout": guard >= GUARD,
	}


func _total(main: TopsMain, key: String) -> int:
	var s := 0
	for t in main._tops:
		s += int(t.get(key))
	return s


## 把累计序列按时间切成四等分：先插值出四个边界上的累计值，再差分
func _split_quarters(ts: Array[float], cs: Array[float], dur: float) -> Array:
	var out: Array = [0.0, 0.0, 0.0, 0.0]
	if dur <= 0.0 or ts.size() < 2:
		return out
	var bounds: Array[float] = [0.0]
	for q in 4:
		bounds.append(dur * float(q + 1) / 4.0)
	for q in 4:
		out[q] = _cum_at(ts, cs, bounds[q + 1]) - _cum_at(ts, cs, bounds[q])
	return out


## 累计曲线在时刻 t 的取值（线性插值 + 两端夹紧）
func _cum_at(ts: Array[float], cs: Array[float], t: float) -> float:
	if ts.size() == 0:
		return 0.0
	if t <= float(ts[0]):
		return float(cs[0])
	if t >= float(ts[ts.size() - 1]):
		return float(cs[cs.size() - 1])
	for i in ts.size() - 1:
		var t0: float = ts[i]
		var t1: float = ts[i + 1]
		if t >= t0 and t <= t1:
			return _interp(t0, float(cs[i]), t1, float(cs[i + 1]), t)
	return float(cs[cs.size() - 1])


func _interp(t0: float, v0: float, t1: float, v1: float, t: float) -> float:
	if absf(t1 - t0) < 0.0001:
		return v1
	return v0 + (v1 - v0) * (t - t0) / (t1 - t0)


func _f1(x: float) -> String:
	return "%.1f" % x


func _f2(x: float) -> String:
	return "%.2f" % x
