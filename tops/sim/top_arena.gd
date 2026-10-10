class_name TopArena
extends RefCounted
##
## 陀螺竞技场 —— 确定性离散步进模拟器。**零渲染依赖**，headless 可跑批量对局。
##
## 严格实现核心机制设计 §5.1 的「矢量碰撞结算四步」：
##   1) 法向   : 沿中心连线，按动量守恒 + 恢复系数交换速度分量
##   2) 切向   : 保留切向分量 × 切向摩擦系数（擦身有代价）
##   3) 伤害   : 按**转速差**结算，与速度无关（§4.2 地雷）
##   4) 击飞   : 按**动量差**结算位移，与转速无关
## 另含：边界反弹损耗、自然衰减（边缘加倍）、击倒回血、接触冷却。
##

# ---- 场地 ----
var arena_radius: float = 300.0

# ---- 碰撞物理 ----
var restitution: float = 0.70
var tangent_friction: float = 0.70
var wall_restitution: float = 0.60

# ---- 转速经济（spin 是唯一血量）----
var chip_damage: float = 3.0
var spin_damage_coeff: float = 0.18
var attacker_cost_ratio: float = 0.60
var wall_spin_loss: float = 5.0
var decay_per_sec: float = 0.40
var edge_decay_mult: float = 2.50
var edge_ratio: float = 0.75
var kill_heal: float = 15.0

# ---- 碰撞节流（防贴脸摩擦刷伤害 / 防贴墙刷损耗）----
var contact_min_normal_speed: float = 30.0
var contact_cooldown_time: float = 0.40
var wall_cooldown_time: float = 0.35

# ---- 击飞 ----
var knock_coeff: float = 0.10
var recoil_ratio: float = 0.25

# ---- 运动 ----
var drag_per_sec: float = 0.80
var overspeed_cap: float = 2.50

# ---- 加速（boost）----
var boost_accel_mult: float = 1.70
var boost_spin_cost: float = 1.20

# ---- 缩圈：默认关闭（shrink_start 极大）----
## 开局多少秒后开始缩圈。默认 9999 = 不缩圈，保持纸面模拟行为不变。
var shrink_start: float = 9999.0
## 每秒缩掉初始半径的比例
var shrink_ratio_per_sec: float = 0.0035
## 缩到初始半径的多少为止
var shrink_min_ratio: float = 0.45
var base_radius: float = 0.0

var bodies: Array[TopBody] = []
var time: float = 0.0
var collisions: int = 0
var wall_hits: int = 0
var deaths: int = 0

## 上一次结算的击飞加成（Δv，单位/秒）。仅供模拟诊断/断言读取。
var last_knock_bonus: float = 0.0

var _last_hit_time: Dictionary = {}


func add(b: TopBody) -> void:
	bodies.append(b)


func alive_count() -> int:
	var n := 0
	for b in bodies:
		if b.alive:
			n += 1
	return n


func find(p_id: int) -> TopBody:
	for b in bodies:
		if b.id == p_id:
			return b
	return null


# ─────────────────────────────────────────────────────────────
# 主步进
# ─────────────────────────────────────────────────────────────

func step(dt: float) -> void:
	time += dt
	_update_shrink(dt)

	for b in bodies:
		if not b.alive:
			continue
		b.survival_time += dt
		b.wall_cooldown = maxf(0.0, b.wall_cooldown - dt)
		_decay(b, dt)
		_drive(b, dt)
		b.pos += b.vel * dt

	for i in bodies.size():
		for j in range(i + 1, bodies.size()):
			resolve_pair(bodies[i], bodies[j])

	for b in bodies:
		if b.alive:
			_resolve_wall(b)
			if b.vel.length() > b.max_speed * overspeed_cap:
				b.vel = b.vel.limit_length(b.max_speed * overspeed_cap)

	_reap()


func _update_shrink(dt: float) -> void:
	if base_radius <= 0.0:
		base_radius = arena_radius
	if time <= shrink_start:
		return
	var floor_r: float = base_radius * shrink_min_ratio
	arena_radius = maxf(arena_radius - base_radius * shrink_ratio_per_sec * dt, floor_r)


## 自然衰减：中心是福地，边缘是险地（Pillar 2）；boost 额外损耗
func _decay(b: TopBody, dt: float) -> void:
	var mult := edge_decay_mult if b.pos.length() > arena_radius * edge_ratio else 1.0
	var cost: float = decay_per_sec * b.decay_mult * mult
	if b.boosting:
		cost += boost_spin_cost * b.decay_mult
	b.spin -= cost * dt


## 推进 + 转向。转向角速度与速度反比（§5：快车难急转，可被预判反杀）
func _drive(b: TopBody, dt: float) -> void:
	b.vel -= b.vel * drag_per_sec * dt
	if not b.thrusting or b.input_dir.length_squared() <= 0.0:
		return
	var target_angle: float = b.input_dir.angle()
	var speed_ratio: float = clampf(b.vel.length() / b.max_speed, 0.0, 1.0)
	var max_turn: float = b.turn_rate * (1.0 - 0.6 * speed_ratio) * dt
	var diff: float = wrapf(target_angle - b.facing, -PI, PI)
	b.facing += clampf(diff, -max_turn, max_turn)
	var accel: float = b.accel * (boost_accel_mult if b.boosting else 1.0)
	if b.vel.length() < b.max_speed * (boost_accel_mult if b.boosting else 1.0) \
			or b.vel.dot(b.facing_vec()) < 0.0:
		b.vel += b.facing_vec() * accel * dt


# ─────────────────────────────────────────────────────────────
# §5.1 四步结算
# ─────────────────────────────────────────────────────────────

func resolve_pair(a: TopBody, b: TopBody) -> void:
	if not a.alive or not b.alive:
		return
	var d := b.pos - a.pos
	var dist: float = d.length()
	var min_dist: float = a.radius + b.radius
	if dist >= min_dist or dist <= 0.0001:
		return
	var n := d / dist  # a → b 的单位法向

	# ⚠ 动量必须在**撞击前**取样：撞后速度已被法向冲量改写，
	#   若此时再判胜负，轻的那方被弹开后反而变成「动量赢家」，会被二次加成弹飞。
	var pa: float = a.momentum()
	var pb: float = b.momentum()

	# 先解除重叠（按质量反比分摊），否则会连续多帧重复结算
	var overlap: float = min_dist - dist
	var sum_mass: float = a.mass + b.mass
	a.pos -= n * overlap * (b.mass / sum_mass)
	b.pos += n * overlap * (a.mass / sum_mass)

	var v_rel: float = (a.vel - b.vel).dot(n)  # > 0 表示正在靠近
	var approaching: bool = v_rel > 0.0

	# ---- 1) 法向：动量守恒 + 恢复系数 ----
	if approaching:
		var inv_a: float = 1.0 / a.mass
		var inv_b: float = 1.0 / b.mass
		var j: float = -(1.0 + restitution) * v_rel / (inv_a + inv_b)
		a.vel += n * (j * inv_a)
		b.vel -= n * (j * inv_b)

	# ---- 2) 切向：保留方向但损耗 ----
	var na: float = a.vel.dot(n)
	var nb: float = b.vel.dot(n)
	a.vel = n * na + (a.vel - n * na) * tangent_friction
	b.vel = n * nb + (b.vel - n * nb) * tangent_friction

	# ---- 3) 伤害：只看转速差，与速度无关 ----
	if approaching and v_rel >= contact_min_normal_speed and _hit_ready(a, b):
		collisions += 1
		var delta: float = absf(a.spin - b.spin)
		var dmg: float = chip_damage + spin_damage_coeff * delta
		if a.spin >= b.spin:
			a.spin -= dmg * attacker_cost_ratio   # Pillar 1：进攻方也付代价
			b.spin -= dmg
			b.last_hit_by = a.id
		else:
			b.spin -= dmg * attacker_cost_ratio
			a.spin -= dmg
			a.last_hit_by = b.id

	# ---- 4) 击飞：只看动量差，与转速无关 ----
	last_knock_bonus = 0.0
	var winner: TopBody = a if pa >= pb else b
	var loser: TopBody = b if pa >= pb else a
	var dp: float = absf(pa - pb)
	if dp > 0.0:
		var sep: Vector2 = (loser.pos - winner.pos).normalized()
		last_knock_bonus = knock_coeff * dp / loser.mass
		loser.vel += sep * last_knock_bonus
		winner.vel -= sep * (knock_coeff * dp * recoil_ratio / winner.mass)


func _hit_ready(a: TopBody, b: TopBody) -> bool:
	var key: String = "%d:%d" % [mini(a.id, b.id), maxi(a.id, b.id)]
	var last: float = float(_last_hit_time.get(key, -1000.0))
	if time - last < contact_cooldown_time:
		return false
	_last_hit_time[key] = time
	return true


func _resolve_wall(b: TopBody) -> void:
	var limit: float = arena_radius - b.radius
	var dist: float = b.pos.length()
	if dist <= limit or dist <= 0.0001:
		return
	var n := b.pos / dist
	b.pos = n * limit
	var vn: float = b.vel.dot(n)
	if vn <= 0.0:
		return
	b.vel -= n * ((1.0 + wall_restitution) * vn)
	if b.wall_cooldown <= 0.0:
		b.spin -= wall_spin_loss
		wall_hits += 1
		b.wall_cooldown = wall_cooldown_time


func _reap() -> void:
	for b in bodies:
		if not b.alive or b.spin > 0.0:
			continue
		b.alive = false
		b.spin = 0.0
		deaths += 1
		var killer := find(b.last_hit_by)
		if killer != null and killer.alive:
			killer.kills += 1
			killer.spin = minf(killer.spin + kill_heal, killer.spin_max)


# ─────────────────────────────────────────────────────────────
# 简易 AI：追最近的活人，无人可追则回中心（Pillar 2 让中心成为争夺点）
# ─────────────────────────────────────────────────────────────

static func nearest(b: TopBody, arena: TopArena) -> TopBody:
	var best := INF
	var found: TopBody = null
	for o in arena.bodies:
		if o == b or not o.alive:
			continue
		var d: float = o.pos.distance_to(b.pos)
		if d < best:
			best = d
			found = o
	return found


## 预判拦截：转向有上限 → 直线追永远追不上（追尾巴），必须打提前量
static func _aim_lead(b: TopBody, target: TopBody) -> Vector2:
	var dist: float = b.pos.distance_to(target.pos)
	var lead: float = clampf(dist / maxf(b.max_speed, 1.0), 0.0, 1.2)
	return target.pos + target.vel * lead


## 策略 A「直冲」：扑最近的活人（带提前量）
static func ai_chase(b: TopBody, arena: TopArena) -> void:
	var target := nearest(b, arena)
	b.thrusting = true
	if target == null:
		b.input_dir = (-b.pos).normalized()
		return
	b.input_dir = (_aim_lead(b, target) - b.pos).normalized()


## 策略 B「推墙」：绕到目标的内侧再撞，把它往场外顶（把击飞换成边缘衰减伤害）
static func ai_slam(b: TopBody, arena: TopArena) -> void:
	var target := nearest(b, arena)
	b.thrusting = true
	if target == null:
		b.input_dir = (-b.pos).normalized()
		return
	var aim_point: Vector2 = _aim_lead(b, target)
	var outward: Vector2 = aim_point.normalized()
	if outward.length_squared() <= 0.0:
		outward = Vector2(1.0, 0.0)
	var aim: Vector2 = aim_point - outward * (target.radius + b.radius + 55.0)
	b.input_dir = (aim - b.pos).normalized()
