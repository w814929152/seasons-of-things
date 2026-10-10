class_name TopTop
extends RigidBody2D
##
## 陀螺实体：平移运动与碰撞交给 Godot 内置物理（RigidBody2D + CCD + PhysicsMaterial），
## 转速（血量/伤害来源）由 TopsRules 结算。自转朝向由本文件自管（lock_rotation）。
##
## 玩法约束（用户拍板）：**进场之后玩家不能操控**，陀螺只靠
##   ① 发射时给的那一下初速度
##   ② 自转进动漂移（真实陀螺会自己晃着走，也避免它静止变成靶子）
##   ③ 物理碰撞与弹开
## 主动推进（thrusting）只留给 AI 对手；玩家陀螺进场后 thrusting 恒为 false。
##
## 信号命名 snake_case、参数带类型（与《物候》工程约定一致）。
##

## 转速变化（用于 HUD 与反馈）
signal spin_changed(new_spin: float)
## 出局
signal died(top: TopTop)

## 进动漂移强度（相对 accel 的比例）
const DRIFT_ACCEL_RATIO := 0.16
const DRIFT_SPEED_CAP := 0.35   # 漂移只把陀螺推到 35% 上限速度，不至于变成 AI

var top_id: int = 0
var archetype: StringName = &"BALANCED"

# ── 逻辑属性 ──
var spin: float = 100.0
var spin_max: float = 100.0
var decay_mult: float = 1.0
var boosting: bool = false
var input_dir: Vector2 = Vector2.ZERO
var thrusting: bool = false
var facing: float = 0.0
var alive: bool = true
var kills: int = 0
var last_hit_by: int = -1
var wall_cooldown: float = 0.0
var contacts: int = 0
var wall_hits: int = 0
var last_contact: Dictionary = {}

# ── 手感属性 ──
var move_speed: float = 285.0
var accel: float = 700.0
var turn_rate: float = 4.2
var top_radius: float = 16.0

# ── 进动漂移（发射后唯一的自驱力）──
var drift_phase: float = 0.0
var drift_rate: float = 0.55

var trail: Array[Vector2] = []


static func create(arch: StringName, p_id: int) -> TopTop:
	var t := TopTop.new()
	var p: Dictionary = TopBody.ARCHETYPES.get(arch, TopBody.ARCHETYPES[&"BALANCED"])
	t.top_id = p_id
	t.archetype = arch
	t.name = "Top%d" % p_id
	t.mass = float(p["mass"])
	t.top_radius = float(p["radius"])
	t.move_speed = float(p["max_speed"])
	t.accel = float(p["accel"])
	t.turn_rate = float(p["turn_rate"])
	t.spin_max = float(p["spin_max"])
	t.decay_mult = float(p["decay_mult"])
	t.spin = t.spin_max
	t.drift_phase = randf() * TAU
	t.drift_rate = 0.42 + randf() * 0.36

	# ── 物理：真实碰撞判断交给引擎 ──
	t.gravity_scale = 0.0                       # ⚠ 俯视竞技场没有重力，默认 1 会让陀螺往下掉
	t.can_sleep = false                         # ⚠ 睡着了 apply_force 不生效，操控/漂移会失灵
	t.lock_rotation = true                      # 朝向自管，不让碰撞把本体打转
	t.linear_damp = 0.80                        # 与纸面模型的阻尼保持一致
	t.continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY  # 防高速穿透
	t.contact_monitor = true
	t.max_contacts_reported = 8
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.70
	pm.friction = 0.15
	t.physics_material_override = pm

	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = t.top_radius
	cs.shape = circle
	t.add_child(cs)

	t.body_entered.connect(t._on_body_entered)
	return t


## 发射阶段：陀螺在场地边缘待命，先不参与碰撞（免得还没发射就互相挤）
func set_collides(on: bool) -> void:
	collision_mask = 1 if on else 0


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not alive:
		state.linear_velocity = Vector2.ZERO
		return
	var dt: float = state.step
	var speed: float = state.linear_velocity.length()

	if thrusting and input_dir.length_squared() > 0.0:
		# 主动推进（仅 AI 使用）：转向 + 施力
		var ratio: float = clampf(speed / move_speed, 0.0, 1.0)
		var max_turn: float = turn_rate * (1.0 - 0.6 * ratio) * dt
		var diff: float = wrapf(input_dir.angle() - facing, -PI, PI)
		facing += clampf(diff, -max_turn, max_turn)

		var boost_mult: float = 1.70 if boosting else 1.0
		var fv := Vector2.from_angle(facing)
		if speed < move_speed * boost_mult or state.linear_velocity.dot(fv) < 0.0:
			state.apply_force(fv * (accel * boost_mult) * mass)
		return

	# 无主动推进 → 自转进动漂移：方向缓慢旋转的小推力，保证陀螺不会完全静止
	drift_phase += dt * drift_rate
	if speed < move_speed * DRIFT_SPEED_CAP:
		state.apply_force(Vector2.from_angle(drift_phase) * (accel * DRIFT_ACCEL_RATIO) * mass)
	facing = drift_phase


func _on_body_entered(other: Node2D) -> void:
	if other is TopTop:
		TopsRules.resolve_contact(self, other as TopTop)
	elif other.is_in_group(&"wall"):
		TopsRules.apply_wall(self)


## 出局：停住物理，交给绘制层画「倒下」
func kill() -> void:
	if not alive:
		return
	alive = false
	spin = 0.0
	thrusting = false
	boosting = false
	freeze = true
	linear_velocity = Vector2.ZERO
	died.emit(self)
