class_name TopsMain
extends Node2D
##
## 陀螺对战 · 主场景（物理版 + 2.5D 视角）
##
## 玩法（用户拍板）：
##   · **发射阶段**：玩家在场地边缘待命，用鼠标 / ←→ 调方向，按住 Shift 或左键蓄力，松手进场。
##   · **战斗阶段**：进场后玩家**完全不能操控**，陀螺只靠发射初速 + 自转进动漂移 + 物理碰撞运动。
##     AI 对手保留主动推进（它们是电脑），玩家的取舍全部集中在「发射」这一次决策上。
##
## 分工：平移碰撞交给 Godot 内置物理；转速经济走零渲染依赖的 TopsRules（可 headless 断言）。
## 场地边界用 24 段 StaticBody2D 拼成圆环，缩圈靠等比内移墙段实现。
##
## 2.5D：物理平面仍是纯 2D（碰撞照常算），绘制时经 TopsArt.project() 压 y 成椭圆地面，
## 陀螺加视觉高度与落地阴影，并按 y 排序绘制 → 斜俯视伪 3D。
##

const CENTER := Vector2(480.0, 330.0)
const BASE_RADIUS := 250.0
const TRAIL_STEP := 0.05
const TRAIL_MAX := 16

# 缩圈节奏（可写静态量，扫参时调它）
static var SHRINK_START := 60.0
static var SHRINK_RATIO_PER_SEC := 0.006
static var SHRINK_MIN_RATIO := 0.50

# 发射参数
const SPAWN_RADIUS_RATIO := 0.88   # 待命位置：场地边缘内侧
const POWER_MIN := 0.15
const POWER_MAX := 1.00
const POWER_RATE := 1.15           # 蓄力条每秒充能速度（往返）
const LAUNCH_SPEED_MIN := 0.35     # 发射初速 = (0.35 + 0.85×力度) × max_speed
const LAUNCH_SPEED_SPAN := 0.85
const AIM_TURN_RATE := 2.2         # 键盘调方向的角速度（rad/s）

enum Phase { LAUNCH, BATTLE }

var _ring: Node2D
var _segs: Array[StaticBody2D] = []
var _seg_dirs: Array[Vector2] = []
var _tops: Array[TopTop] = []
var _player: TopTop
var _strategies: Dictionary = {}

var _phase: int = Phase.LAUNCH
var _aim_dir := Vector2(0.0, -1.0)
var _power: float = POWER_MIN
var _charging := false
var _charge_up := true

var _arena_radius: float = BASE_RADIUS
var _elapsed: float = 0.0
var _trail_t: float = 0.0

var _finished: bool = false
var _won: bool = false
var _place: int = 0
var _flash: float = 0.0


func _ready() -> void:
	_reset()


func _reset() -> void:
	for c in get_children():
		c.queue_free()
	_tops.clear()
	_strategies.clear()
	_segs.clear()
	_seg_dirs.clear()
	_arena_radius = BASE_RADIUS
	_elapsed = 0.0
	_trail_t = 0.0
	_finished = false
	_won = false
	_place = 0
	_flash = 0.0
	_phase = Phase.LAUNCH
	_power = POWER_MIN
	_charging = false
	_charge_up = true

	_ring = _build_ring()
	add_child(_ring)

	# 属性归一：转速上限一律 100，性格只影响手感（决策 B3）
	var lineup: Array[StringName] = [&"BALANCED", &"DART", &"RAM", &"DART", &"BALANCED"]
	var strats: Array[String] = ["player", "chase", "slam", "chase", "slam"]
	for i in lineup.size():
		var t := TopTop.create(lineup[i], i + 1)
		t.spin_max = 100.0
		t.spin = 100.0
		t.decay_mult = 1.0 + (t.decay_mult - 1.0) * 0.35
		var ang: float = _spawn_angle(i, lineup.size())
		t.global_position = CENTER + Vector2.from_angle(ang) * BASE_RADIUS * SPAWN_RADIUS_RATIO
		t.facing = ang + PI
		t.drift_phase = t.facing
		t.linear_velocity = Vector2.ZERO
		t.thrusting = false
		t.set_collides(false)   # 发射前互不碰撞
		t.freeze = true         # 发射前连进动漂移也冻住，老老实实在边缘待命
		t.died.connect(_on_top_died)
		add_child(t)
		_tops.append(t)
		_strategies[t.top_id] = strats[i]
		if strats[i] == "player":
			_player = t

	_aim_dir = (CENTER - _player.global_position).normalized()
	queue_redraw()


## 玩家永远从场地正下方（屏幕近端）进场，AI 均匀分布在其余角度
func _spawn_angle(i: int, n: int) -> float:
	if i == 0:
		return PI * 0.5
	return PI * 0.5 + TAU * float(i) / float(n)


func _build_ring() -> Node2D:
	var ring := Node2D.new()
	ring.name = "Ring"
	ring.position = CENTER
	for i in 24:
		var ang: float = TAU * float(i) / 24.0
		var dir := Vector2.from_angle(ang)
		var sb := StaticBody2D.new()
		sb.name = "Seg%d" % i
		sb.add_to_group(&"wall")
		sb.position = dir * (BASE_RADIUS + 30.0)
		sb.rotation = ang + PI * 0.5
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(2.0 * PI * BASE_RADIUS / 24.0 + 14.0, 60.0)
		cs.shape = rect
		sb.add_child(cs)
		ring.add_child(sb)
		_segs.append(sb)
		_seg_dirs.append(dir)
	return ring


func _physics_process(delta: float) -> void:
	TopsRules.now = _elapsed
	if _finished:
		if Input.is_action_just_pressed("tops_restart"):
			_reset()
		_flash = maxf(0.0, _flash - delta * 1.2)
		queue_redraw()
		return

	if _phase == Phase.LAUNCH:
		_update_launch_input(delta)
		queue_redraw()
		return

	# ── 战斗阶段 ──
	_elapsed += delta
	for t in _tops:
		if t == _player or not t.alive:
			continue
		TopsRules.ai_drive(t, _tops, String(_strategies[t.top_id]), CENTER)

	for t in _tops:
		TopsRules.decay(t, delta, CENTER, _arena_radius)
		_check_death(t)

	_update_shrink(delta)
	_update_trails(delta)

	if _alive_count() <= 1:
		_finished = true
		_won = _player.alive
		_flash = 1.0
		if _place == 0:
			_place = 1
	queue_redraw()


# ── 发射阶段：玩家唯一的决策点 ──
func _update_launch_input(delta: float) -> void:
	var mouse: Vector2 = TopsArt.unproject(get_local_mouse_position(), CENTER)
	var to_mouse: Vector2 = mouse - _player.global_position
	if to_mouse.length_squared() > 100.0:
		_aim_dir = to_mouse.normalized()

	var turn := 0.0
	if Input.is_action_pressed("tops_left"):
		turn -= 1.0
	if Input.is_action_pressed("tops_right"):
		turn += 1.0
	if turn != 0.0:
		_aim_dir = _aim_dir.rotated(turn * AIM_TURN_RATE * delta).normalized()

	var hold: bool = Input.is_action_pressed("tops_boost") \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if hold:
		_charging = true
		_power += (POWER_RATE if _charge_up else -POWER_RATE) * delta
		if _power >= POWER_MAX:
			_power = POWER_MAX
			_charge_up = false
		elif _power <= POWER_MIN:
			_power = POWER_MIN
			_charge_up = true
	elif _charging:
		_launch(_power)


func _launch(power: float) -> void:
	for t in _tops:
		var dir: Vector2
		var pw: float
		if t == _player:
			dir = _aim_dir
			pw = power
		else:
			var to_center: Vector2 = (CENTER - t.global_position).normalized()
			dir = to_center.rotated(randf_range(-0.6, 0.6))
			pw = randf_range(0.55, 1.0)
		t.facing = dir.angle()
		t.drift_phase = t.facing
		t.freeze = false        # 解冻后速度才生效
		t.linear_velocity = dir * (t.move_speed * (LAUNCH_SPEED_MIN + LAUNCH_SPEED_SPAN * pw))
		t.thrusting = false      # 玩家的陀螺从此不再接受任何方向输入
		t.boosting = false
		t.set_collides(true)
	_phase = Phase.BATTLE
	_charging = false
	queue_redraw()


func _alive_count() -> int:
	var n := 0
	for t in _tops:
		if t.alive:
			n += 1
	return n


func _check_death(t: TopTop) -> void:
	if not t.alive or t.spin > 0.0:
		return
	if t == _player:
		_place = _alive_count()  # 玩家是第几名（其余存活者 + 自己）
	t.kill()


func _on_top_died(top: TopTop) -> void:
	var killer_id: int = top.last_hit_by
	for t in _tops:
		if t.top_id == killer_id and t.alive:
			t.kills += 1
			t.spin = minf(t.spin + TopsRules.KILL_HEAL, t.spin_max)


func _update_shrink(delta: float) -> void:
	if _elapsed <= SHRINK_START:
		return
	var floor_r: float = BASE_RADIUS * SHRINK_MIN_RATIO
	_arena_radius = maxf(_arena_radius - BASE_RADIUS * SHRINK_RATIO_PER_SEC * delta, floor_r)
	# 缩圈用「移动墙段」而不是缩放节点：Godot 2D 物理对缩放静态体支持不可靠，
	# 直接重设每段位置最稳，段宽不变还保证收缩后不会露出缝隙。
	for i in _segs.size():
		_segs[i].position = _seg_dirs[i] * (_arena_radius + 30.0)


func _update_trails(delta: float) -> void:
	_trail_t += delta
	if _trail_t < TRAIL_STEP:
		return
	_trail_t = 0.0
	for t in _tops:
		t.trail.append(t.global_position)
		while t.trail.size() > TRAIL_MAX:
			t.trail.remove_at(0)


func _draw() -> void:
	TopsArt.draw_world(self, CENTER, _arena_radius, TopsRules.EDGE_RATIO)

	# 2.5D 的遮挡关系：按物理 y 从小到大（远 → 近）绘制
	var order: Array = []
	for t in _tops:
		order.append(t)
	order.sort_custom(func(a: TopTop, b: TopTop) -> bool:
		return a.global_position.y < b.global_position.y)

	for t in order:
		var ground := TopsArt.project(t.global_position, CENTER)
		var vis := PackedVector2Array()
		for p in t.trail:
			vis.append(TopsArt.project(p, CENTER))
		TopsArt.draw_top(self, ground, TopsArt.top_color(t.top_id), t.spin, t.spin_max,
			t.top_radius, t.linear_velocity, t.facing, t.alive, t.boosting, t == _player,
			TopsRules.now, vis)

	if _phase == Phase.LAUNCH and not _finished:
		TopsArt.draw_launch(self, TopsArt.project(_player.global_position, CENTER),
			_aim_dir, _power)

	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(960.0, 640.0)), Color(1, 1, 1, _flash * 0.35))

	TopsArt.draw_hud(self, {
		"alive": _alive_count(),
		"total": _tops.size(),
		"time": _elapsed,
		"spin": _player.spin,
		"spin_max": _player.spin_max,
		"place": _place,
		"finished": _finished,
		"won": _won,
		"shrinking": _elapsed > SHRINK_START,
		"phase": "launch" if _phase == Phase.LAUNCH and not _finished else "battle",
	})
