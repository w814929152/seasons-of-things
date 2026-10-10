class_name TopSimRun
extends RefCounted
##
## 陀螺数值纸面模拟（design/tops/core_mechanic_design.md §7「纸面验证计划」）。
##
## 五个实验：
##   S0 解耦      —— 证明「伤害只随 Δspin、击飞只随 Δp」（§4.2 必须拍死的地雷）
##   S1 单次撞击  —— 5 个典型对撞的手算对照，看是否产生有意义决策
##   S2 1v1 胜率  —— A 类失败信号：是否存在「高转速纯碾压」
##   S3 5 人混战  —— B 类失败信号：单局时长是否 3–5 min、后期是否沉闷
##   S4 苟活      —— Pillar 2：蹲边缘是否真的比待中心更早死
##   S5 扫参      —— 自然衰减 × 击倒回血 → 单局时长，给出满足 3–5 min 的组合
##
## 全部纯逻辑，headless 可跑；dt 固定，结果可复现。
##

const DT: float = 1.0 / 30.0
const MATCH_MAX: float = 420.0
const DUEL_MAX: float = 240.0


## 修订参数覆盖层（v0.3 定稿用）。key 必须命中 TUNING_KEYS，否则忽略。
static var tuning: Dictionary = {}

const TUNING_KEYS: Array[String] = [
	"arena_radius", "restitution", "tangent_friction", "wall_restitution",
	"chip_damage", "spin_damage_coeff", "attacker_cost_ratio",
	"wall_spin_loss", "decay_per_sec", "edge_decay_mult", "edge_ratio",
	"kill_heal", "contact_min_normal_speed", "contact_cooldown_time",
	"wall_cooldown_time", "knock_coeff", "recoil_ratio", "drag_per_sec",
]


static func set_tuning(d: Dictionary) -> void:
	tuning = d


static func new_arena() -> TopArena:
	var a := TopArena.new()
	for k in tuning:
		if TUNING_KEYS.has(String(k)):
			a.set(String(k), tuning[k])
	return a


## 建体：允许 tuning 统一覆盖转速上限（性格差异改由质量/速度/衰减倍率承担）
static func make(arch: StringName, id: int) -> TopBody:
	var b := TopBody.create(arch, id)
	if tuning.has("spin_max_override"):
		b.spin_max = float(tuning["spin_max_override"])
		b.spin = b.spin_max
	if tuning.has("decay_mult_scale"):
		var s: float = float(tuning["decay_mult_scale"])
		b.decay_mult = 1.0 + (b.decay_mult - 1.0) * s
	return b


# ═════════════════════════════════════════════════════════════
# S0 · 双轴解耦证明
# ═════════════════════════════════════════════════════════════

static func single_hit(arch_a: StringName, spin_a: float, speed_a: float,
		arch_b: StringName, spin_b: float, speed_b: float) -> Dictionary:
	var arena := new_arena()
	var a := make(arch_a, 1)
	var b := make(arch_b, 2)
	a.spin = spin_a
	b.spin = spin_b
	a.pos = Vector2(-(a.radius - 1.0), 0.0)
	b.pos = Vector2(b.radius - 1.0, 0.0)
	a.vel = Vector2(speed_a, 0.0)
	b.vel = Vector2(-speed_b, 0.0)
	var va0 := a.vel
	var vb0 := b.vel
	arena.resolve_pair(a, b)
	return {
		"spin_a": a.spin, "spin_b": b.spin,
		"dmg_a": spin_a - a.spin, "dmg_b": spin_b - b.spin,
		"knock_a": (a.vel - va0).length(), "knock_b": (b.vel - vb0).length(),
		"speed_a": a.vel.length(), "speed_b": b.vel.length(),
		"knock_bonus": arena.last_knock_bonus,
	}


## 固定 Δspin=20，只改速度 → 伤害必须完全不变
static func s_decouple_damage() -> Array:
	var rows: Array = []
	for sp in [40.0, 120.0, 240.0, 320.0]:
		var r := single_hit(&"BALANCED", 100.0, sp, &"BALANCED", 80.0, sp)
		rows.append({"speed": sp, "dmg_high": r["dmg_a"], "dmg_low": r["dmg_b"],
			"knock_low": r["knock_b"], "speed_low": r["speed_b"]})
	return rows


## 固定速度，只改质量组合（动量差变）→ 伤害不变，击飞显著变
static func s_decouple_knock() -> Array:
	var rows: Array = []
	var combos: Array = [
		[&"BALANCED", &"BALANCED"], [&"RAM", &"DART"], [&"DART", &"RAM"], [&"RAM", &"RAM"],
	]
	for c in combos:
		var r := single_hit(c[0], 100.0, 250.0, c[1], 80.0, 250.0)
		var a := make(c[0], 1)
		var b := make(c[1], 2)
		rows.append({"pair": "%s vs %s" % [String(c[0]), String(c[1])],
			"dp": absf(a.mass * 250.0 - b.mass * 250.0),
			"dmg_low": r["dmg_b"], "knock_bonus": r["knock_bonus"],
			"speed_low": r["speed_b"]})
	return rows


# ═════════════════════════════════════════════════════════════
# S1 · 五种典型对撞
# ═════════════════════════════════════════════════════════════

static func s_hits() -> Array:
	var cases: Array = [
		{"name": "势均力敌", "a": &"BALANCED", "sa": 100.0, "va": 250.0,
			"b": &"BALANCED", "sb": 100.0, "vb": 250.0},
		{"name": "以逸待劳", "a": &"DART", "sa": 115.0, "va": 0.0,
			"b": &"RAM", "sb": 82.0, "vb": 320.0},
		{"name": "冲撞车正面", "a": &"RAM", "sa": 82.0, "va": 320.0,
			"b": &"DART", "sb": 115.0, "vb": 250.0},
		{"name": "刺客主动撞", "a": &"DART", "sa": 115.0, "va": 250.0,
			"b": &"RAM", "sb": 82.0, "vb": 0.0},
		{"name": "残血被冲", "a": &"DART", "sa": 18.0, "va": 0.0,
			"b": &"RAM", "sb": 78.0, "vb": 320.0},
	]
	var rows: Array = []
	for c in cases:
		var r := single_hit(c["a"], c["sa"], c["va"], c["b"], c["sb"], c["vb"])
		rows.append({
			"name": c["name"],
			"desc": "%s(sp%.0f,v%.0f) × %s(sp%.0f,v%.0f)" % [
				String(c["a"]), c["sa"], c["va"], String(c["b"]), c["sb"], c["vb"]],
			"dmg_a": r["dmg_a"], "dmg_b": r["dmg_b"],
			"knock_a": r["knock_a"], "knock_b": r["knock_b"],
			"speed_a": r["speed_a"], "speed_b": r["speed_b"],
			"spin_a": r["spin_a"], "spin_b": r["spin_b"],
		})
	return rows


# ═════════════════════════════════════════════════════════════
# S2 · 1v1 胜率矩阵（A 类失败信号：纯碾压）
# ═════════════════════════════════════════════════════════════

static func duel(arch_a: StringName, arch_b: StringName, seed: int,
		strat_a: String = "chase", strat_b: String = "chase") -> Dictionary:
	var arena := new_arena()
	var a := make(arch_a, 1)
	var b := make(arch_b, 2)
	arena.add(a)
	arena.add(b)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ang: float = rng.randf() * TAU
	var d := Vector2.from_angle(ang) * 190.0
	a.reset_state(d, ang + PI)
	b.reset_state(-d, ang)
	while arena.alive_count() > 1 and arena.time < DUEL_MAX:
		_drive_ai(a, arena, strat_a)
		_drive_ai(b, arena, strat_b)
		arena.step(DT)
	var winner: StringName = &"DRAW"
	if arena.alive_count() == 1:
		winner = a.archetype if a.alive else b.archetype
	return {"winner": winner, "time": arena.time, "collisions": arena.collisions}


static func _drive_ai(b: TopBody, arena: TopArena, strat: String) -> void:
	if strat == "slam":
		TopArena.ai_slam(b, arena)
	else:
		TopArena.ai_chase(b, arena)


## S2b 策略反制实验：同一对位换打法，看胜率是否可被动摇
## （若换打法也救不回来 → 真碾压；若显著变化 → 操控曲线有取舍）
static func s_duel_strategy(n: int) -> Array:
	var cases: Array = [
		{"a": &"DART", "b": &"RAM", "sa": "chase", "sb": "chase"},
		{"a": &"DART", "b": &"RAM", "sa": "chase", "sb": "slam"},
		{"a": &"DART", "b": &"BALANCED", "sa": "chase", "sb": "chase"},
		{"a": &"RAM", "b": &"BALANCED", "sa": "chase", "sb": "chase"},
		{"a": &"RAM", "b": &"BALANCED", "sa": "slam", "sb": "chase"},
	]
	var rows: Array = []
	for c in cases:
		var wins_a := 0
		var t_sum := 0.0
		for i in n:
			var r := duel(c["a"], c["b"], 5000 + i, c["sa"], c["sb"])
			if r["winner"] == c["a"]:
				wins_a += 1
			t_sum += float(r["time"])
		rows.append({"desc": "%s(%s) vs %s(%s)" % [String(c["a"]), c["sa"],
			String(c["b"]), c["sb"]], "wr_a": float(wins_a) / float(n),
			"avg_time": t_sum / float(n)})
	return rows


static func s_duel(n: int) -> Array:
	var pairs: Array = [[&"DART", &"RAM"], [&"DART", &"BALANCED"], [&"RAM", &"BALANCED"]]
	var rows: Array = []
	for p in pairs:
		var wins_a := 0
		var wins_b := 0
		var draws := 0
		var t_sum := 0.0
		for i in n:
			var r := duel(p[0], p[1], 1000 + i)
			if r["winner"] == p[0]:
				wins_a += 1
			elif r["winner"] == p[1]:
				wins_b += 1
			else:
				draws += 1
			t_sum += float(r["time"])
		rows.append({
			"a": String(p[0]), "b": String(p[1]),
			"wr_a": float(wins_a) / float(n),
			"wr_b": float(wins_b) / float(n),
			"draws": draws, "avg_time": t_sum / float(n), "n": n,
		})
	return rows


# ═════════════════════════════════════════════════════════════
# S3 / S5 · N 人混战
# ═════════════════════════════════════════════════════════════

static func melee(seed: int, decay: float, heal: float,
		cd: float = 0.4, coeff: float = 0.18) -> Dictionary:
	var arena := new_arena()
	arena.decay_per_sec = decay
	arena.kill_heal = heal
	arena.contact_cooldown_time = cd
	arena.spin_damage_coeff = coeff
	var archs: Array[StringName] = [&"DART", &"RAM", &"BALANCED", &"DART", &"BALANCED"]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in archs.size():
		var b := make(archs[i], i + 1)
		var ang: float = rng.randf() * TAU
		var rad: float = arena.arena_radius * (0.55 + rng.randf() * 0.25)
		b.reset_state(Vector2.from_angle(ang) * rad, ang + PI)
		arena.add(b)
	var marks: Array = []
	var counted := 0
	while arena.alive_count() > 1 and arena.time < MATCH_MAX:
		for b in arena.bodies:
			if b.alive:
				TopArena.ai_chase(b, arena)
		arena.step(DT)
		# ⚠ 必须累加到「当前秒」的槽位：逐帧覆盖只会留下最后一帧的增量
		var sec: int = int(arena.time)
		while marks.size() <= sec:
			marks.append(0)
		marks[sec] = int(marks[sec]) + arena.collisions - counted
		counted = arena.collisions
	var dur: float = arena.time
	var third: float = dur / 3.0
	var early := 0
	var late := 0
	for i in marks.size():
		if float(i) < third:
			early += int(marks[i])
		elif float(i) >= 2.0 * third:
			late += int(marks[i])
	var d_early: float = float(early) / maxf(third, 1.0)
	var d_late: float = float(late) / maxf(third, 1.0)
	# 四等分撞击分布：看「开局冷场 / 中段爆炸 / 收尾拖沓」的形状
	var quarters: Array = [0, 0, 0, 0]
	var first_hit: float = -1.0
	for i in marks.size():
		var q: int = mini(int(float(i) / maxf(dur, 0.001) * 4.0), 3)
		quarters[q] = int(quarters[q]) + int(marks[i])
		if first_hit < 0.0 and int(marks[i]) > 0:
			first_hit = float(i)
	var winner_spin := 0.0
	for b in arena.bodies:
		if b.alive:
			winner_spin = b.spin
	return {
		"time": dur, "collisions": arena.collisions, "wall_hits": arena.wall_hits,
		"density_early": d_early, "density_late": d_late,
		"boredom": d_late / maxf(d_early, 0.0001), "winner_spin": winner_spin,
		"quarters": quarters, "first_hit": first_hit,
	}


static func s_melee(n: int, decay: float, heal: float,
		cd: float = 0.4, coeff: float = 0.18) -> Dictionary:
	var t_sum := 0.0
	var c_sum := 0.0
	var w_sum := 0.0
	var b_sum := 0.0
	var s_sum := 0.0
	var timeout := 0
	var q_sum: Array = [0.0, 0.0, 0.0, 0.0]
	var fh_sum := 0.0
	for i in n:
		var r := melee(2000 + i, decay, heal, cd, coeff)
		t_sum += r["time"]
		c_sum += float(r["collisions"])
		w_sum += float(r["wall_hits"])
		b_sum += r["boredom"]
		s_sum += r["winner_spin"]
		var q: Array = r["quarters"]
		for k in 4:
			q_sum[k] = float(q_sum[k]) + float(q[k])
		fh_sum += float(r["first_hit"])
		if r["time"] >= MATCH_MAX - DT * 2.0:
			timeout += 1
	return {
		"n": n, "decay": decay, "heal": heal,
		"avg_time": t_sum / float(n), "avg_collisions": c_sum / float(n),
		"avg_wall": w_sum / float(n), "boredom": b_sum / float(n),
		"winner_spin": s_sum / float(n), "timeouts": timeout,
		"quarters": [q_sum[0] / float(n), q_sum[1] / float(n),
			q_sum[2] / float(n), q_sum[3] / float(n)],
		"first_hit": fh_sum / float(n),
	}


static func s_sweep(n: int) -> Array:
	var rows: Array = []
	for decay in [0.2, 0.4, 0.6, 0.8, 1.2, 2.0]:
		for heal in [0.0, 15.0]:
			var r := s_melee(n, decay, heal)
			rows.append(r)
	return rows


## S6 伤害节流扫参：接触冷却 × 转速差系数 → 单局时长
## （B 类信号触发后的主要调参旋钮：撞击太密 → 局太短）
static func s_sweep2(n: int) -> Array:
	var rows: Array = []
	for cd in [0.4, 0.8, 1.5]:
		for coeff in [0.18, 0.10, 0.05]:
			var r := s_melee(n, 0.4, 15.0, cd, coeff)
			r["cd"] = cd
			r["coeff"] = coeff
			rows.append(r)
	return rows


# ═════════════════════════════════════════════════════════════
# S4 · 苟活测试（Pillar 2：中心是福地，边缘是险地）
# ═════════════════════════════════════════════════════════════

static func survive(arch: StringName, mode: String, edge_mult: float) -> float:
	var arena := new_arena()
	arena.edge_decay_mult = edge_mult
	var b := make(arch, 1)
	arena.add(b)
	match mode:
		"center_idle":
			b.reset_state(Vector2.ZERO, 0.0)
			b.thrusting = false
			b.input_dir = Vector2.ZERO
		"edge_camp":
			b.reset_state(Vector2(arena.arena_radius * 0.9, 0.0), 0.0)
			b.thrusting = false
			b.input_dir = Vector2.ZERO
		"edge_hug":
			b.reset_state(Vector2(arena.arena_radius * 0.95, 0.0), 0.0)
			b.thrusting = true
			b.input_dir = Vector2(-1.0, 0.0)  # 一直往墙里顶
		_:
			b.reset_state(Vector2.ZERO, 0.0)
	while b.alive and arena.time < MATCH_MAX:
		arena.step(DT)
	return arena.time


static func s_camp() -> Array:
	var rows: Array = []
	for mult in [1.0, 2.5]:
		for mode in ["center_idle", "edge_camp", "edge_hug"]:
			rows.append({"edge_mult": mult, "mode": mode,
				"life": survive(&"BALANCED", mode, mult)})
	return rows


# ═════════════════════════════════════════════════════════════
# 汇总
# ═════════════════════════════════════════════════════════════

static func run_all(duel_n: int = 40, melee_n: int = 20, sweep_n: int = 6) -> Dictionary:
	return {
		"decouple_damage": s_decouple_damage(),
		"decouple_knock": s_decouple_knock(),
		"hits": s_hits(),
		"duel": s_duel(duel_n),
		"duel_strategy": s_duel_strategy(duel_n),
		"melee": s_melee(melee_n, 0.4, 15.0),
		"sweep": s_sweep(sweep_n),
		"sweep2": s_sweep2(sweep_n),
		"camp": s_camp(),
	}


static func _fmt_quarters(q: Variant) -> String:
	var parts: Array[String] = []
	for v in q:
		parts.append(f1(float(v)))
	return " / ".join(parts)


## v0.3 修订参数：由本轮模拟反推（依据见 docs/tops/numeric_sim_report.md）
## 核心改动：① 转速上限归一，性格差异改由质量/速度/衰减倍率承担
##           ② 大幅下调每次撞击的转速消耗（撞击密度才是局时长的真旋钮）
##           ③ 撞墙损耗减半并延长冷却（贴墙不再秒死）
##           ④ 场地放大，降低撞击频率
static func tuning_v03() -> Dictionary:
	return {
		"spin_max_override": 100.0,
		"arena_radius": 400.0,
		"chip_damage": 1.2,
		"spin_damage_coeff": 0.06,
		"wall_spin_loss": 2.0,
		"wall_cooldown_time": 0.60,
		"contact_cooldown_time": 0.50,
		"decay_per_sec": 0.35,
		"kill_heal": 15.0,
	}


## v0.4 修订参数：在 v0.3 基础上继续降消耗密度，并压缩性格衰减倍率差距
## （v0.3 的教训：衰减倍率差距一旦放大，它就取代转速成为新的支配项）
static func tuning_v04() -> Dictionary:
	return {
		"spin_max_override": 100.0,
		"decay_mult_scale": 0.35,
		"arena_radius": 480.0,
		"chip_damage": 0.8,
		"spin_damage_coeff": 0.04,
		"wall_spin_loss": 1.0,
		"wall_cooldown_time": 1.0,
		"contact_cooldown_time": 0.60,
		"decay_per_sec": 0.25,
		"kill_heal": 12.0,
	}


## 只跑「定稿验证」所需的三组实验（快）
static func run_tuned(duel_n: int = 40, melee_n: int = 20, variant: String = "v03") -> Dictionary:
	set_tuning(tuning_v03() if variant == "v03" else tuning_v04())
	var r := {
		"duel": s_duel(duel_n),
		"duel_strategy": s_duel_strategy(duel_n),
		"melee": s_melee(melee_n, 0.35, 15.0, 0.5, 0.06),
		"camp": s_camp(),
	}
	set_tuning({})
	return r


static func to_text_tuned(r: Dictionary) -> String:
	var L: PackedStringArray = PackedStringArray()
	L.append("### S2 1v1 胜率（修订参数 v0.3）")
	L.append("| 对位 | 左胜率 | 右胜率 | 平局 | 平均时长 s |")
	L.append("|---|---|---|---|---|")
	for row in r["duel"]:
		L.append("| %s vs %s | %s | %s | %d | %s |" % [row["a"], row["b"],
			f2(row["wr_a"]), f2(row["wr_b"]), row["draws"], f1(row["avg_time"])])
	L.append("")
	L.append("### S2b 策略反制（修订参数 v0.3）")
	L.append("| 对位（左策略 vs 右策略） | 左胜率 | 平均时长 s |")
	L.append("|---|---|---|")
	for row in r["duel_strategy"]:
		L.append("| %s | %s | %s |" % [row["desc"], f2(row["wr_a"]), f1(row["avg_time"])])
	L.append("")
	var m: Dictionary = r["melee"]
	L.append("### S3 5 人混战（修订参数 v0.3，%d 局）" % m["n"])
	L.append("| 指标 | 值 |")
	L.append("|---|---|")
	L.append("| 平均单局时长 s | %s |" % f1(m["avg_time"]))
	L.append("| 平均撞击次数 | %s |" % f1(m["avg_collisions"]))
	L.append("| 平均撞墙次数 | %s |" % f1(m["avg_wall"]))
	L.append("| 首次撞击时刻 s | %s |" % f1(m["first_hit"]))
	L.append("| 四等分撞击分布 | %s |" % _fmt_quarters(m["quarters"]))
	L.append("| 胜者剩余转速 | %s |" % f1(m["winner_spin"]))
	L.append("| 超时未分胜负局数 | %d |" % m["timeouts"])
	L.append("")
	L.append("### S4 苟活（修订参数 v0.3）")
	L.append("| 边缘倍率 | 站位 | 存活时长 s |")
	L.append("|---|---|---|")
	for row in r["camp"]:
		L.append("| %s | %s | %s |" % [f2(row["edge_mult"]), row["mode"], f1(row["life"])])
	return "\n".join(L)


static func f2(x: float) -> String:
	return "%.2f" % x


static func f1(x: float) -> String:
	return "%.1f" % x


static func to_text(r: Dictionary) -> String:
	var L: PackedStringArray = PackedStringArray()
	L.append("### S0-A 伤害 vs 速度（Δspin 固定 20）")
	L.append("| 对撞速度 | 高转速方扣 | 低转速方扣 | 低转速方撞后速度 |")
	L.append("|---|---|---|---|")
	for row in r["decouple_damage"]:
		L.append("| %s | %s | %s | %s |" % [f1(row["speed"]), f2(row["dmg_high"]),
			f2(row["dmg_low"]), f1(row["speed_low"])])
	L.append("")
	L.append("### S0-B 击飞 vs 动量差（速度固定 250，Δspin 固定 20）")
	L.append("| 组合 | 撞前动量差 Δp | 低转速方扣 | 击飞加成 Δv | 低转速方撞后速度 |")
	L.append("|---|---|---|---|---|")
	for row in r["decouple_knock"]:
		L.append("| %s | %s | %s | %s | %s |" % [row["pair"], f1(row["dp"]),
			f2(row["dmg_low"]), f1(row["knock_bonus"]), f1(row["speed_low"])])
	L.append("")
	L.append("### S1 单次撞击")
	L.append("| 场景 | 配置 | A 扣转速 | B 扣转速 | A 撞后速度 | B 撞后速度 | A 余转速 | B 余转速 |")
	L.append("|---|---|---|---|---|---|---|---|")
	for row in r["hits"]:
		L.append("| %s | %s | %s | %s | %s | %s | %s | %s |" % [row["name"], row["desc"],
			f2(row["dmg_a"]), f2(row["dmg_b"]), f1(row["speed_a"]), f1(row["speed_b"]),
			f1(row["spin_a"]), f1(row["spin_b"])])
	L.append("")
	L.append("### S2 1v1 胜率（A 类失败信号：任一方 >70%% 即碾压）")
	L.append("| 对位 | 左胜率 | 右胜率 | 平局 | 平均时长 s |")
	L.append("|---|---|---|---|---|")
	for row in r["duel"]:
		L.append("| %s vs %s | %s | %s | %d | %s |" % [row["a"], row["b"],
			f2(row["wr_a"]), f2(row["wr_b"]), row["draws"], f1(row["avg_time"])])
	L.append("")
	L.append("### S2b 策略反制：同一对位换打法的胜率变化")
	L.append("| 对位（左策略 vs 右策略） | 左胜率 | 平均时长 s |")
	L.append("|---|---|---|")
	for row in r["duel_strategy"]:
		L.append("| %s | %s | %s |" % [row["desc"], f2(row["wr_a"]), f1(row["avg_time"])])
	L.append("")
	var m: Dictionary = r["melee"]
	L.append("### S3 5 人混战（decay=%s heal=%s，%d 局）" % [f1(m["decay"]), f1(m["heal"]), m["n"]])
	L.append("| 指标 | 值 |")
	L.append("|---|---|")
	L.append("| 平均单局时长 s | %s |" % f1(m["avg_time"]))
	L.append("| 平均撞击次数 | %s |" % f1(m["avg_collisions"]))
	L.append("| 平均撞墙次数 | %s |" % f1(m["avg_wall"]))
	L.append("| 沉闷指数（后1/3 ÷ 前1/3 撞击密度） | %s |" % f2(m["boredom"]))
	L.append("| 胜者剩余转速 | %s |" % f1(m["winner_spin"]))
	L.append("| 首次撞击时刻 s | %s |" % f1(m["first_hit"]))
	L.append("| 四等分撞击分布 | %s |" % _fmt_quarters(m["quarters"]))
	L.append("| 超时未分胜负局数 | %d |" % m["timeouts"])
	L.append("")
	L.append("### S5 扫参：自然衰减 × 击倒回血 → 单局时长")
	L.append("| 衰减 /s | 击倒回血 | 平均时长 s | 平均撞击 | 沉闷指数 | 超时局 |")
	L.append("|---|---|---|---|---|---|")
	for row in r["sweep"]:
		L.append("| %s | %s | %s | %s | %s | %d |" % [f1(row["decay"]), f1(row["heal"]),
			f1(row["avg_time"]), f1(row["avg_collisions"]), f2(row["boredom"]),
			row["timeouts"]])
	L.append("")
	L.append("### S6 扫参：接触冷却 × 转速差系数 → 单局时长")
	L.append("| 接触冷却 s | 转速差系数 | 平均时长 s | 平均撞击 | 平均撞墙 | 沉闷指数 |")
	L.append("|---|---|---|---|---|---|")
	for row in r["sweep2"]:
		L.append("| %s | %s | %s | %s | %s | %s |" % [f1(row["cd"]), f2(row["coeff"]),
			f1(row["avg_time"]), f1(row["avg_collisions"]), f1(row["avg_wall"]),
			f2(row["boredom"])])
	L.append("")
	L.append("### S4 苟活（Edge 衰减倍率对存活时长的影响）")
	L.append("| 边缘倍率 | 站位 | 存活时长 s |")
	L.append("|---|---|---|")
	for row in r["camp"]:
		L.append("| %s | %s | %s |" % [f2(row["edge_mult"]), row["mode"], f1(row["life"])])
	return "\n".join(L)
