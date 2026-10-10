class_name TopsArt
extends RefCounted
##
## 陀螺对战 · 程序化绘制层（零外部美术资源，与《物候》同一套做法）。
##
## 只读状态、只画画面 —— **绝不反向写入游戏状态**（硬约束 §0.1）。
##
## 2.5D 视角：物理世界仍是纯 2D 平面（碰撞/动量照常算），绘制时把 y 轴压扁
## （Y_SQUASH）成椭圆地面，再给陀螺一个视觉高度 TOP_H + 落地阴影 + y 排序，
## 得到「斜俯视伪 3D」。物理平面不改 → 碰撞判定与 2D 版完全一致。
##
## 可读性通道（Pillar 3）：转速环弧长 + 环色 + 朝向线 + 动量箭头 + 尾迹 + boost 光环。
##

const C_BG := Color("#0E1117")
const C_FLOOR := Color("#1B212B")
const C_FLOOR_RISK := Color("#36201D")
const C_RING := Color("#454E60")
const C_GRID := Color("#232A35")
const C_WALL := Color("#2C3442")
const C_WALL_FAR := Color("#232A36")

const C_PLAYER := Color("#5DCAA5")
const C_FOE := Color("#E9A23B")
const C_FOE2 := Color("#D4537E")
const C_DEAD := Color("#3C3F47")

const C_SPIN_HI := Color("#5DCAA5")
const C_SPIN_MID := Color("#EF9F27")
const C_SPIN_LO := Color("#E24B4A")

const C_TEXT := Color("#E8EAED")
const C_TEXT_DIM := Color("#9AA1AC")

## 2.5D 视角参数
const Y_SQUASH := 0.62    # 物理 y → 视觉 y 的压缩比（越小越"躺平"）
const TOP_H := 16.0       # 陀螺顶面相对地面的视觉高度
const WALL_H := 15.0      # 远端围墙高度


# ── 2.5D 坐标变换 ──
## 物理平面点 → 视觉地面点
static func project(p: Vector2, center: Vector2) -> Vector2:
	return Vector2(p.x, center.y + (p.y - center.y) * Y_SQUASH)


## 视觉地面点 → 物理平面点（发射瞄准要把鼠标位置反算回物理方向）
static func unproject(p: Vector2, center: Vector2) -> Vector2:
	return Vector2(p.x, center.y + (p.y - center.y) / Y_SQUASH)


## 物理平面方向 → 视觉方向（同样压 y）
static func dir_visual(d: Vector2) -> Vector2:
	return Vector2(d.x, d.y * Y_SQUASH)


## draw_polyline 遇到 <2 个点会往控制台喷 ERROR，统一走这个守卫
static func polyline(c: CanvasItem, pts: PackedVector2Array, color: Color, width: float,
		closed: bool = false) -> void:
	if pts.size() < 2:
		return
	c.draw_polyline(pts, color, width, closed)


static func top_color(top_id: int) -> Color:
	if top_id == 1:
		return C_PLAYER
	return C_FOE if top_id % 2 == 0 else C_FOE2


static func spin_color(ratio: float) -> Color:
	if ratio > 0.55:
		return C_SPIN_HI
	if ratio > 0.28:
		return C_SPIN_MID
	return C_SPIN_LO


# ── 椭圆/弧的点集（Godot 的 draw_arc 只能画正圆，2.5D 全部改用手搓椭圆）──
static func ellipse_pts(c: Vector2, rx: float, ry: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func arc_pts(c: Vector2, rx: float, ry: float, a0: float, a1: float,
		n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if a1 <= a0:
		return pts
	for i in n + 1:
		var a: float = a0 + (a1 - a0) * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func draw_world(c: CanvasItem, center: Vector2, r: float, edge_ratio: float) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, Vector2(960.0, 640.0)), C_BG)

	var ry: float = r * Y_SQUASH
	var ry_in: float = r * edge_ratio * Y_SQUASH

	# 远端围墙（只画上半椭圆那一段，近端不画，否则挡住场地）
	_draw_wall_band(c, center, r, ry, PI, TAU, WALL_H)
	_draw_wall_band(c, center, r, ry, 0.0, PI, WALL_H * 0.28)

	# 险地区（外圈 0.75R→R）用偏红底色，中心是福地（Pillar 2）
	c.draw_colored_polygon(ellipse_pts(center, r, ry, 56), C_FLOOR_RISK)
	c.draw_colored_polygon(ellipse_pts(center, r * edge_ratio, ry_in, 48), C_FLOOR)

	# 同心参考椭圆：让「我在哪、离边缘多远」一眼可读
	var i := 1
	while i <= 3:
		var rr: float = r * edge_ratio * float(i) / 3.0
		polyline(c, ellipse_pts(center, rr, rr * Y_SQUASH, 40), C_GRID, 1.0, true)
		i += 1
	polyline(c, ellipse_pts(center, r * edge_ratio, ry_in, 56), C_GRID, 1.5, true)
	polyline(c, ellipse_pts(center, r, ry, 64), C_RING, 3.0, true)

	# 中心十字
	c.draw_line(center - Vector2(9.0, 0.0), center + Vector2(9.0, 0.0), C_RING, 1.5)
	c.draw_line(center - Vector2(0.0, 9.0 * Y_SQUASH),
		center + Vector2(0.0, 9.0 * Y_SQUASH), C_RING, 1.5)


## 一段围墙：下沿贴地、上沿抬高 h，逐段梯形填充（远端高、近端矮）
static func _draw_wall_band(c: CanvasItem, center: Vector2, r: float, ry: float,
		a0: float, a1: float, h: float) -> void:
	var segs := 28
	for i in segs:
		var s0: float = a0 + (a1 - a0) * float(i) / float(segs)
		var s1: float = a0 + (a1 - a0) * float(i + 1) / float(segs)
		var p0 := center + Vector2(cos(s0) * r, sin(s0) * ry)
		var p1 := center + Vector2(cos(s1) * r, sin(s1) * ry)
		var q0 := p0 + Vector2(0.0, -h)
		var q1 := p1 + Vector2(0.0, -h)
		var quad := PackedVector2Array()
		quad.append(p0)
		quad.append(p1)
		quad.append(q1)
		quad.append(q0)
		c.draw_colored_polygon(quad, C_WALL_FAR if h > WALL_H * 0.5 else C_WALL)
	# 上沿描边，强化"这是一堵墙"
	var lip := PackedVector2Array()
	for i in segs + 1:
		var s: float = a0 + (a1 - a0) * float(i) / float(segs)
		lip.append(center + Vector2(cos(s) * r, sin(s) * ry) + Vector2(0.0, -h))
	polyline(c, lip, C_RING, 1.5)


## 画一个陀螺。ground = **已投影**的地面点（main 里按 y 排序后传入）。
static func draw_top(c: CanvasItem, ground: Vector2, base: Color, spin: float,
		spin_max: float, rr: float, vel: Vector2, facing: float, alive: bool,
		boosting: bool, is_player: bool, time: float, trail_vis: PackedVector2Array) -> void:
	if trail_vis.size() > 1:
		polyline(c, trail_vis, Color(base.r, base.g, base.b, 0.30), 2.0)

	if not alive:
		_draw_dead(c, ground, rr)
		return

	# 落地阴影（2.5D 的"离地感"全靠它）
	c.draw_colored_polygon(
		ellipse_pts(ground + Vector2(2.0, 1.0), rr * 1.18, rr * 1.18 * Y_SQUASH, 20),
		Color(0.0, 0.0, 0.0, 0.38))

	var top := ground + Vector2(0.0, -TOP_H)
	var rr_t: float = rr * 0.96

	# 侧面柱体 + 底盘（露出一点，读作"厚度"）
	var side := PackedVector2Array()
	side.append(ground + Vector2(-rr, 1.0))
	side.append(ground + Vector2(rr, 1.0))
	side.append(top + Vector2(rr_t, 0.0))
	side.append(top + Vector2(-rr_t, 0.0))
	c.draw_colored_polygon(side, base.darkened(0.58))
	c.draw_colored_polygon(ellipse_pts(ground, rr, rr * Y_SQUASH, 20), base.darkened(0.68))

	# 顶面
	c.draw_colored_polygon(ellipse_pts(top, rr_t, rr_t * Y_SQUASH, 24), base.darkened(0.10))
	polyline(c, ellipse_pts(top, rr_t, rr_t * Y_SQUASH, 24), base, 2.0, true)
	# 顶心亮点：读起来像金属陀螺的轴心
	c.draw_colored_polygon(ellipse_pts(top, rr_t * 0.30, rr_t * 0.30 * Y_SQUASH, 12),
		base.lightened(0.35))

	# 转速环：弧长 = 剩余转速，颜色 = 健康度（Pillar 3 主通道）
	var ratio: float = clampf(spin / maxf(spin_max, 1.0), 0.0, 1.0)
	var ring_r: float = rr_t + 6.0
	var ring_c: Vector2 = top + Vector2(0.0, -1.5)
	polyline(c, arc_pts(ring_c, ring_r, ring_r * Y_SQUASH, -PI * 0.5, -PI * 0.5 + TAU * ratio, 40),
		spin_color(ratio), 3.5)
	# 转速满时"剩余弧"长度为 0，必须跳过（draw_polyline 不接受 <2 个点）
	if ratio < 0.999:
		polyline(c, arc_pts(ring_c, ring_r, ring_r * Y_SQUASH, -PI * 0.5 + TAU * ratio, PI * 1.5, 40),
			Color(1.0, 1.0, 1.0, 0.10), 3.5)

	if boosting:
		polyline(c, ellipse_pts(ring_c, ring_r + 5.0, (ring_r + 5.0) * Y_SQUASH, 24),
			Color("#FAC775"), 2.0, true)

	# 朝向线（想去哪）与动量箭头（被推去哪）—— 画在地面平面，压 y 后仍然直观
	var fv := dir_visual(Vector2.from_angle(facing))
	c.draw_line(ground, ground + fv.normalized() * (rr + 14.0), Color(1, 1, 1, 0.85), 2.0)
	if vel.length() > 12.0:
		var mv: Vector2 = dir_visual(vel).normalized() * minf(vel.length() * 0.16, 34.0)
		c.draw_line(ground, ground + mv, Color("#85B7EB", 0.9), 3.0)
		var tip: Vector2 = ground + mv
		var perp: Vector2 = Vector2(-mv.y, mv.x).normalized()
		c.draw_line(tip, tip - mv.normalized() * 6.0 - perp * 4.0, Color("#85B7EB", 0.9), 2.0)
		c.draw_line(tip, tip - mv.normalized() * 6.0 + perp * 4.0, Color("#85B7EB", 0.9), 2.0)

	if is_player:
		var pulse: float = 0.5 + 0.5 * sin(time * 4.0)
		polyline(c, 
			ellipse_pts(ground, rr + 15.0, (rr + 15.0) * Y_SQUASH, 32),
			Color(1.0, 1.0, 1.0, 0.22 + 0.25 * pulse), 1.5, true)


static func _draw_dead(c: CanvasItem, ground: Vector2, rr: float) -> void:
	# 倒下：贴地躺平的一枚盘 + 灰色
	c.draw_colored_polygon(
		ellipse_pts(ground + Vector2(1.0, 1.0), rr * 1.25, rr * 0.55, 20),
		Color(0.0, 0.0, 0.0, 0.32))
	c.draw_colored_polygon(ellipse_pts(ground, rr * 1.05, rr * 0.42, 20), C_DEAD)
	c.draw_line(ground + Vector2(-rr, 0.0), ground + Vector2(rr, 0.0), C_DEAD.darkened(0.3), 3.0)


## 发射阶段的瞄准线 + 蓄力条
static func draw_launch(c: CanvasItem, ground: Vector2, aim: Vector2, power: float) -> void:
	var d: Vector2 = dir_visual(aim).normalized()
	var length: float = 70.0 + power * 190.0
	var step := 15.0
	var t := 0.0
	while t < length:
		var p0: Vector2 = ground + d * t
		var p1: Vector2 = ground + d * minf(t + step * 0.55, length)
		c.draw_line(p0, p1, Color(1.0, 1.0, 1.0, 0.55), 2.0)
		t += step
	var tip: Vector2 = ground + d * length
	var perp: Vector2 = Vector2(-d.y, d.x)
	c.draw_line(tip, tip - d * 9.0 + perp * 5.0, Color(1.0, 1.0, 1.0, 0.8), 2.0)
	c.draw_line(tip, tip - d * 9.0 - perp * 5.0, Color(1.0, 1.0, 1.0, 0.8), 2.0)

	var bw := 9.0
	var bh := 48.0
	var bx: float = ground.x + 26.0
	var by: float = ground.y - TOP_H - 14.0 - bh
	c.draw_rect(Rect2(bx, by, bw, bh), Color(1.0, 1.0, 1.0, 0.15))
	c.draw_rect(Rect2(bx, by + bh * (1.0 - power), bw, bh * power), spin_color(power))


static func draw_hud(c: CanvasItem, ctx: Dictionary) -> void:
	var font := UiFont.get_font()
	var alive_n: int = int(ctx["alive"])
	var total: int = int(ctx["total"])
	var t: float = float(ctx["time"])
	var spin: float = float(ctx["spin"])
	var spin_max: float = float(ctx["spin_max"])
	var place: int = int(ctx["place"])
	var shrink: bool = bool(ctx["shrinking"])
	var phase: String = String(ctx.get("phase", "battle"))

	c.draw_string(font, Vector2(16.0, 28.0), "存活 %d / %d" % [alive_n, total],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_TEXT)
	c.draw_string(font, Vector2(16.0, 50.0), "%.1f s" % t,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_TEXT_DIM)
	if shrink:
		c.draw_string(font, Vector2(16.0, 72.0), "场地收缩中",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#F09595"))

	# 玩家转速条
	var bw := 180.0
	var bx := 960.0 - bw - 16.0
	var by := 20.0
	var ratio: float = clampf(spin / maxf(spin_max, 1.0), 0.0, 1.0)
	c.draw_rect(Rect2(bx, by, bw, 14.0), Color(1, 1, 1, 0.10))
	c.draw_rect(Rect2(bx, by, bw * ratio, 14.0), spin_color(ratio))
	c.draw_string(font, Vector2(bx, by + 32.0), "转速 %d / %d" % [int(spin), int(spin_max)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_TEXT_DIM)

	if phase == "launch":
		c.draw_string(font, Vector2(16.0, 636.0),
			"鼠标 / ← → 调方向 · 按住空格或左键蓄力 · 松手发射（进场后无法操控）",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_TEXT)
		c.draw_string(font, Vector2(300.0, 96.0), "发射进场",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#FAC775"))
	else:
		c.draw_string(font, Vector2(16.0, 636.0),
			"已进场 · 陀螺完全靠物理碰撞运动（不可操控）· R 重开",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_TEXT_DIM)

	if bool(ctx["finished"]):
		var title: String = "最后还在转的是你" if bool(ctx["won"]) else "你倒了 · 第 %d 名" % place
		c.draw_rect(Rect2(0.0, 250.0, 960.0, 130.0), Color("#0E1117", 0.88))
		c.draw_string(font, Vector2(300.0, 310.0), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 28, C_TEXT)
		c.draw_string(font, Vector2(300.0, 344.0), "用时 %.1f s · 按 R 再来一局" % t,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_TEXT_DIM)
