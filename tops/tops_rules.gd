class_name TopsRules
extends RefCounted
##
## 陀螺规则层 —— 纯数据 + 纯函数，**零渲染依赖**（headless 可断言）。
##
## 分工（用户拍板：平移碰撞交给 Godot 内置 RigidBody2D）：
##   · 引擎负责：平移运动、碰撞检测与弹开（质量/恢复系数/摩擦/CCD）
##   · 本文件负责：转速经济 —— 伤害、摩擦转速交换、撞墙损耗、自然衰减、击倒回血、AI 决策
## 这样既拿到「真实物理碰撞判断」，又保住转速规则的可测性与 §4.2 的解耦铁律。
##

# ── 转速经济（初值沿用纸面模拟定稿值，见 docs/tops/numeric_sim_report.md §7）──
# 说明：物理版撞击频率远高于纸面模型（真实弹开会反复接触），
# 因此这些值全部做成可写静态量，便于 tests/tops_phys_sim.gd 批量扫参。
static var CHIP_DAMAGE := 0.25
static var SPIN_DAMAGE_COEFF := 0.15
static var ATTACKER_COST_RATIO := 0.60
static var WALL_SPIN_LOSS := 0.50
static var WALL_COOLDOWN := 1.00
static var CONTACT_COOLDOWN := 0.50
static var DECAY_PER_SEC := 0.12
static var EDGE_DECAY_MULT := 2.50
static var EDGE_RATIO := 0.75
static var KILL_HEAL := 20.0
static var BOOST_SPIN_COST := 1.20

## 切向滑动 → 转速交换系数。真实接触摩擦会把两个面速度拉平，
## 这里表现为「转速从高的一方流向低的一方」：高速擦身会快速拉平转速差。
static var SPIN_FRICTION_COEFF := 0.02

## 定稿值 = 物理版扫参 v_i（见 docs/tops/numeric_sim_report.md §10）
## 关键结论：真实物理把撞击频率抬到纸面模型的 4 倍以上，纸面定稿参数
## （chip 1.2 / wall 2.0 / decay 0.35）在物理版只剩 62 s；必须全线砍 sink，
## 并把伤害更彻底地挂到 Δspin 上（coeff 0.06→0.15）来拉开淘汰节奏。
const DEFAULTS := {
	"chip": 0.25, "coeff": 0.15, "atk_cost": 0.60,
	"wall": 0.50, "wall_cd": 1.00, "contact_cd": 0.50,
	"decay": 0.12, "edge_mult": 2.50, "edge_ratio": 0.75, "kill_heal": 20.0,
	"boost_cost": 1.20, "friction": 0.02,
}


## 扫参用：把一组键值套进规则层（缺失键保持当前值）
static func apply_tuning(d: Dictionary) -> void:
	if d.has("chip"):
		CHIP_DAMAGE = float(d["chip"])
	if d.has("coeff"):
		SPIN_DAMAGE_COEFF = float(d["coeff"])
	if d.has("atk_cost"):
		ATTACKER_COST_RATIO = float(d["atk_cost"])
	if d.has("wall"):
		WALL_SPIN_LOSS = float(d["wall"])
	if d.has("wall_cd"):
		WALL_COOLDOWN = float(d["wall_cd"])
	if d.has("contact_cd"):
		CONTACT_COOLDOWN = float(d["contact_cd"])
	if d.has("decay"):
		DECAY_PER_SEC = float(d["decay"])
	if d.has("edge_mult"):
		EDGE_DECAY_MULT = float(d["edge_mult"])
	if d.has("edge_ratio"):
		EDGE_RATIO = float(d["edge_ratio"])
	if d.has("kill_heal"):
		KILL_HEAL = float(d["kill_heal"])
	if d.has("boost_cost"):
		BOOST_SPIN_COST = float(d["boost_cost"])
	if d.has("friction"):
		SPIN_FRICTION_COEFF = float(d["friction"])


static func reset_tuning() -> void:
	apply_tuning(DEFAULTS)

## 由 main 每帧写入，供碰撞回调做冷却判定（避免碰撞回调里再去拿时钟）
static var now: float = 0.0


## 陀螺间接触结算。
## 1) 伤害只看**转速差**（§4.2 铁律：与速度无关）
## 2) 摩擦转速交换只看**切向相对滑动速度**（与转速差无关）
static func resolve_contact(a: TopTop, b: TopTop) -> void:
	if not a.alive or not b.alive:
		return
	var key: String = "%d_%d" % [mini(a.top_id, b.top_id), maxi(a.top_id, b.top_id)]
	if now - float(a.last_contact.get(key, -1000.0)) < CONTACT_COOLDOWN:
		return
	a.last_contact[key] = now
	b.last_contact[key] = now

	var d: Vector2 = b.global_position - a.global_position
	if d.length_squared() <= 0.0001:
		return
	var n: Vector2 = d.normalized()
	var rel: Vector2 = b.linear_velocity - a.linear_velocity
	var vn: float = rel.dot(n)
	if vn > 0.0:
		return  # 正在分离，不算一次撞击
	var vt: float = (rel - n * vn).length()  # 切向相对滑动
	a.contacts += 1
	b.contacts += 1

	# ---- 1) 伤害：转速差 ----
	var delta: float = absf(a.spin - b.spin)
	var dmg: float = CHIP_DAMAGE + SPIN_DAMAGE_COEFF * delta
	if a.spin >= b.spin:
		a.spin -= dmg * ATTACKER_COST_RATIO  # Pillar 1：占优方也付代价
		b.spin -= dmg
		b.last_hit_by = a.top_id
	else:
		b.spin -= dmg * ATTACKER_COST_RATIO
		a.spin -= dmg
		a.last_hit_by = b.top_id

	# ---- 2) 摩擦转速交换：高 → 低，按切向滑动量，且不超过差值的一半（防过冲）----
	var hi: TopTop = a if a.spin >= b.spin else b
	var lo: TopTop = b if a.spin >= b.spin else a
	var transfer: float = minf(SPIN_FRICTION_COEFF * vt, (hi.spin - lo.spin) * 0.5)
	if transfer > 0.0:
		hi.spin -= transfer
		lo.spin += transfer


## 撞墙：边缘是险地（Pillar 2）。带冷却，避免贴墙被瞬间刷死。
static func apply_wall(t: TopTop) -> void:
	if not t.alive or t.wall_cooldown > 0.0:
		return
	t.spin -= WALL_SPIN_LOSS
	t.wall_cooldown = WALL_COOLDOWN
	t.wall_hits += 1


## 自然衰减（边缘加倍）+ boost 额外损耗
static func decay(t: TopTop, dt: float, arena_center: Vector2, arena_radius: float) -> void:
	if not t.alive:
		return
	t.wall_cooldown = maxf(0.0, t.wall_cooldown - dt)
	var mult: float = EDGE_DECAY_MULT if t.global_position.distance_to(arena_center) \
			> arena_radius * EDGE_RATIO else 1.0
	var cost: float = DECAY_PER_SEC * t.decay_mult * mult
	if t.boosting:
		cost += BOOST_SPIN_COST * t.decay_mult
	t.spin -= cost * dt


## AI：预判拦截（转向有上限 → 直线追永远追不上）
static func ai_drive(t: TopTop, tops: Array[TopTop], strategy: String,
		arena_center: Vector2) -> void:
	if not t.alive:
		t.thrusting = false
		return
	var best: TopTop = null
	var bd := INF
	for o in tops:
		if o == t or not o.alive:
			continue
		var d: float = t.global_position.distance_to(o.global_position)
		if d < bd:
			bd = d
			best = o
	if best == null:
		t.input_dir = (arena_center - t.global_position).normalized()
		t.thrusting = true
		return
	var lead: float = clampf(bd / maxf(t.move_speed, 1.0), 0.0, 1.2)
	var aim: Vector2 = best.global_position + best.linear_velocity * lead
	if strategy == "slam":
		var outward: Vector2 = (aim - arena_center).normalized()
		if outward.length_squared() <= 0.0:
			outward = Vector2(1.0, 0.0)
		aim = aim - outward * (t.top_radius + best.top_radius + 55.0)
	t.input_dir = (aim - t.global_position).normalized()
	t.thrusting = true
