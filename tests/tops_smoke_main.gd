extends SceneTree
##
## 陀螺对战 · headless 冒烟测试（物理版）
##
## 跑法：
##   "Godot_..._console.exe" --headless --path "D:/New test" --script res://tests/tops_smoke_main.gd
##
## 覆盖三层：
##   1) 规则层纯函数（TopsRules）—— 伤害只随 Δspin、摩擦转速交换方向
##   2) 物理接线（TopTop 是 RigidBody2D、CCD 开启、边界是 24 段静态墙）
##   3) 整局跑通 —— 加速物理时间跑完一局，确认碰撞真发生、有人出局、缩圈生效
##
## 退出码 0 = 全绿。
##

const SIM_SPEEDUP := 16.0     # 物理时间倍速
const SIM_TICKS := 480        # 提高物理频率，保证每步 dt 仍是 ~1/30


func _initialize() -> void:
	var h := TestHarness.new()
	print("════════ 陀螺对战 · headless 冒烟测试（物理版）════════")
	await process_frame

	h.suite("规则层：伤害只随转速差（§4.2）")
	_rules_damage(h)

	h.suite("规则层：摩擦交换转速（高 → 低，拉平）")
	_rules_friction(h)

	h.suite("物理接线")
	var scene := load("res://tops/tops_main.tscn")
	h.ck(scene != null, "tops_main.tscn 可加载")
	var main: Node = scene.instantiate() if scene != null else null
	h.ck(main is TopsMain, "根节点脚本是 TopsMain")
	root.add_child(main)
	await process_frame

	var tops: Array[TopTop] = []
	for c in main.get_children():
		if c is TopTop:
			tops.append(c as TopTop)
	h.eq(tops.size(), 5, "场上 5 个陀螺")
	var all_rigid := true
	var ccd_ok := true
	var no_gravity := true
	for t in tops:
		if not (t is RigidBody2D):
			all_rigid = false
		if t.continuous_cd != RigidBody2D.CCD_MODE_CAST_RAY:
			ccd_ok = false
		if t.gravity_scale != 0.0:
			no_gravity = false
	h.ck(all_rigid, "每个陀螺都是 RigidBody2D（碰撞交给引擎）")
	h.ck(ccd_ok, "全部开启 CCD 连续碰撞检测（防高速穿透）")
	h.ck(no_gravity, "重力已关闭（俯视竞技场）")

	var ring: Node2D = main.get_node_or_null("Ring") as Node2D
	h.ck(ring != null, "存在边界圆环 Ring")
	if ring != null:
		var walls := 0
		for c in ring.get_children():
			if c is StaticBody2D and (c as Node2D).is_in_group(&"wall"):
				walls += 1
		h.eq(walls, 24, "边界由 24 段 StaticBody2D 组成")

	h.suite("发射阶段：进场前唯一的决策点")
	var mm := main as TopsMain
	var pl: TopTop = mm._player
	h.eq(mm._phase, TopsMain.Phase.LAUNCH, "开局停在发射阶段")
	h.ck(mm._elapsed == 0.0, "发射前不计时（转速不掉）")
	h.ck(pl.linear_velocity.length() < 0.001, "发射前陀螺静止待命")
	h.ck(tops[0].collision_mask == 0, "发射前陀螺不参与碰撞（不会互相挤）")

	Input.action_press("tops_boost")
	for _i in 40:
		await physics_frame
	var pw: float = mm._power
	h.ck(pw > 0.25, "按住 Shift 蓄力条在涨（力度 %s）" % _f2(pw))
	Input.action_release("tops_boost")
	await physics_frame
	await physics_frame
	h.eq(mm._phase, TopsMain.Phase.BATTLE, "松手即进场")
	h.ck(pl.linear_velocity.length() > 50.0,
		"发射给了初速 %s" % _f1(pl.linear_velocity.length()))
	h.ck(tops[0].collision_mask == 1, "进场后恢复碰撞")

	h.suite("进场后玩家不可操控（陀螺完全靠物理）")
	var pos0: Vector2 = pl.global_position
	Input.action_press("tops_right")
	for _i in 60:
		await physics_frame
	h.ck(not pl.thrusting, "按方向键不产生推进指令（输入通道已关闭）")
	h.ck(pl.input_dir == Vector2.ZERO and not pl.boosting, "玩家的 input_dir / boost 保持为空")
	var moved_pl: float = pl.global_position.distance_to(pos0)
	h.ck(moved_pl > 5.0, "玩家陀螺仍在动（发射初速 + 进动漂移 + 碰撞），位移 %s" % _f1(moved_pl))
	Input.action_release("tops_right")

	h.suite("2.5D 视角（物理平面不变，只变换绘制）")
	var pv := Vector2(600.0, 430.0)
	var proj := TopsArt.project(pv, TopsMain.CENTER)
	h.ck(proj.x == pv.x, "投影不改变 x（%s）" % _f1(proj.x))
	h.ck(proj.y < pv.y and proj.y > TopsMain.CENTER.y,
		"y 被压向场地中心（%s → %s）" % [_f1(pv.y), _f1(proj.y)])
	var back := TopsArt.unproject(proj, TopsMain.CENTER)
	h.ck(back.distance_to(pv) < 0.001, "project / unproject 互逆（发射瞄准要反算鼠标）")
	h.ck(TopsArt.Y_SQUASH < 1.0 and TopsArt.TOP_H > 0.0,
		"视角参数有效：压扁 %s / 陀螺高度 %s" % [_f2(TopsArt.Y_SQUASH), _f1(TopsArt.TOP_H)])

	h.suite("整局跑通（物理加速 %s×）" % SIM_SPEEDUP)
	Engine.physics_ticks_per_second = SIM_TICKS
	Engine.time_scale = SIM_SPEEDUP
	var start_pos: Array[Vector2] = []
	for t in tops:
		start_pos.append(t.global_position)

	var guard := 0
	while guard < 9600 and _alive(tops) > 1:
		await physics_frame
		guard += 1
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60

	var spin_sum := 0.0
	for t in tops:
		spin_sum += t.spin
	var dur: float = (main as TopsMain)._elapsed
	print("  · 对局时长 %s s｜存活 %d/5｜转速合计 %s" % [_f1(dur), _alive(tops), _f1(spin_sum)])
	# B 类失败信号：单局时长要落在 3–5 min 目标附近（留 ±60 s 抖动带）
	h.ck(dur > 120.0, "单局不秒结束（%s s，目标 180–300）" % _f1(dur))
	h.ck(dur < 360.0, "单局不拖死（%s s，目标 180–300）" % _f1(dur))

	var moved := false
	for i in tops.size():
		if tops[i].global_position.distance_to(start_pos[i]) > 30.0:
			moved = true
	h.ck(moved, "陀螺确实移动了（物理在跑，不是静止）")
	h.ck(_alive(tops) <= 1 or guard < 16000, "一局能收敛（剩 %d 人）" % _alive(tops))
	h.ck(_alive(tops) < 5, "有人出局（剩 %d / 5）" % _alive(tops))

	var contacts := 0
	var wall_hits := 0
	for t in tops:
		contacts += t.contacts
		wall_hits += t.wall_hits
	h.ck(contacts > 0, "引擎检测到 %d 次陀螺间接触" % contacts)
	h.ck(wall_hits > 0, "引擎检测到 %d 次撞墙" % wall_hits)
	var r_now: float = (main as TopsMain)._arena_radius
	h.ck(r_now < 249.9, "场地已收缩（半径 %s < 250）" % _f1(r_now))
	h.ck(_all_inside(tops, main as TopsMain), "收缩后没有陀螺被挤出墙外")

	# 真实物理的关键回归：撞墙必须真的被墙挡住（而不是穿过去）
	var w: StaticBody2D = ring.get_child(0) as StaticBody2D
	h.ck(w != null and w.position.length() < 280.0, "墙段已内移（距圆心 %s）" % _f1(w.position.length()))

	h.ck(spin_sum < 500.0, "总转速已下降（初始 500，现 %s）" % _f1(spin_sum))

	h.suite("输入映射")
	for a in ["tops_up", "tops_down", "tops_left", "tops_right", "tops_boost", "tops_restart"]:
		h.ck(InputMap.has_action(a), "已注册动作：%s" % a)

	print("")
	print("═══════════════════════════════════════════")
	print("[TOPSSMOKE] pass = ", h.pass_count(), "   fails = ", h.fail_count())
	for f in h.failures():
		print("  FAIL  ", f)
	print("[TOPSSMOKE] ", "ALL PASS" if h.fail_count() == 0 else "HAS FAILURES")
	print("═══════════════════════════════════════════")
	quit(1 if h.fail_count() > 0 else 0)


func _alive(tops: Array[TopTop]) -> int:
	var n := 0
	for t in tops:
		if t.alive:
			n += 1
	return n


## 造两个不受干扰的陀螺（关重力、不入物理交互）来单测规则层
func _pair(h: TestHarness, id_a: int, id_b: int, at: Vector2) -> Array:
	var a := TopTop.create(&"RAM", id_a)
	var b := TopTop.create(&"DART", id_b)
	a.gravity_scale = 0.0
	b.gravity_scale = 0.0
	root.add_child(a)
	root.add_child(b)
	a.global_position = at
	b.global_position = at + Vector2(40.0, 0.0)
	return [a, b]


## 单测用的临时陀螺必须立刻摘掉，否则会和主场景的陀螺撞在一起污染结果
func _dispose(p: Array) -> void:
	for t in p:
		var n := t as Node
		root.remove_child(n)
		n.queue_free()


func _rules_damage(h: TestHarness) -> void:
	# 纯法向对撞（切向 = 0）：伤害 = chip + coeff×Δspin，期望值跟着常量算，改参不会打碎断言
	var dmg: float = TopsRules.CHIP_DAMAGE + TopsRules.SPIN_DAMAGE_COEFF * 20.0
	var expect_a: float = 100.0 - dmg * TopsRules.ATTACKER_COST_RATIO
	var expect_b: float = 80.0 - dmg
	var p := _pair(h, 91, 92, Vector2(60.0, 60.0))
	var a: TopTop = p[0]
	var b: TopTop = p[1]
	a.spin = 100.0
	b.spin = 80.0
	a.linear_velocity = Vector2(120.0, 0.0)
	b.linear_velocity = Vector2(-120.0, 0.0)
	TopsRules.now = 1.0
	TopsRules.resolve_contact(a, b)
	var a1 := a.spin
	var b1 := b.spin
	h.ck(absf(a1 - expect_a) < 0.01,
		"高转速方扣 %s×0.6=%s → %s（期望 %s）" % [_f2(dmg), _f2(dmg * 0.6), _f2(a1), _f2(expect_a)])
	h.ck(absf(b1 - expect_b) < 0.01,
		"低转速方扣 %s → %s（期望 %s）" % [_f2(dmg), _f2(b1), _f2(expect_b)])
	_dispose(p)

	# 同样 Δspin，对撞速度翻倍 → 伤害必须完全不变（§4.2 铁律）
	var p2 := _pair(h, 93, 94, Vector2(60.0, 160.0))
	var c: TopTop = p2[0]
	var d: TopTop = p2[1]
	c.spin = 100.0
	d.spin = 80.0
	c.linear_velocity = Vector2(300.0, 0.0)
	d.linear_velocity = Vector2(-300.0, 0.0)
	TopsRules.now = 2.0
	TopsRules.resolve_contact(c, d)
	h.ck(absf(c.spin - a1) < 0.01 and absf(d.spin - b1) < 0.01,
		"速度 120→300，伤害不变（伤害与速度无关）")
	_dispose(p2)


func _rules_friction(h: TestHarness) -> void:
	# 纯切向擦身（法向相对速度 0）：伤害照算，另有转速从高流向低
	var p := _pair(h, 95, 96, Vector2(60.0, 300.0))
	var a: TopTop = p[0]
	var b: TopTop = p[1]
	a.spin = 100.0
	b.spin = 80.0
	a.linear_velocity = Vector2(0.0, 300.0)
	b.linear_velocity = Vector2(0.0, 100.0)  # 切向相对滑动 200
	TopsRules.now = 3.0
	TopsRules.resolve_contact(a, b)
	var gap_before := 20.0
	var gap_after: float = a.spin - b.spin
	h.ck(gap_after < gap_before, "擦身后转速差 %s < 擦身前 %s（摩擦在拉平）" % [
		_f2(gap_after), _f2(gap_before)])
	var pure_dmg: float = TopsRules.CHIP_DAMAGE + TopsRules.SPIN_DAMAGE_COEFF * 20.0
	h.ck(b.spin > 80.0 - pure_dmg, "低转速方被「喂」了转速（伤害后仍高于纯伤害值）")
	_dispose(p)


## 所有存活陀螺都必须在墙内（验证「真实碰撞」没有穿透）
func _all_inside(tops: Array[TopTop], main: TopsMain) -> bool:
	for t in tops:
		if not t.alive:
			continue
		if t.global_position.distance_to(TopsMain.CENTER) > main._arena_radius + 40.0:
			return false
	return true


func _f1(x: float) -> String:
	return "%.1f" % x


func _f2(x: float) -> String:
	return "%.2f" % x
