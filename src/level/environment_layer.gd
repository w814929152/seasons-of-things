class_name EnvironmentLayer
extends Node2D
##
## 静态环境层（重设计 v3）：**连续场景**，不是"一格一格"。
##
## ── 与 v2 的区别 ────────────────────────────────────────────────
## v2 为了可读性，把每个格子都画出了轮廓（棋盘地板 + 逐格砖缝斜切墙块）。结果是：
## 逻辑网格（当时是 10×5，v4 已放大到 13×8）被画成了**视觉网格**，场景看起来像一张表格，而不像一间屋子。
##
## v3 的目标：**保留逻辑网格，但把它从画面里彻底隐藏**。
##   ① **地板 = 一整片**：所有非墙格铺同一基色、**不画任何格线/棋盘** →
##      相邻格之间没有缝，读起来是连成一片的地面。
##   ② **墙 = 连续实体块**：逐格填同色（不描边）→ 相邻墙格自然并成一块；
##      斜面与描边**只画在"墙 ↔ 非墙"的交界上**，于是得到的是**一圈连续的外轮廓**，
##      而不是每格一个小方块。
##   ③ **靠光与影给体积**：墙根环境遮蔽(AO) + 沿 −光照方向的整体投影 + 交界处的
##      受光/背光斜面。没有网格线，体积感全部由光影承担。
##
## 保留下来的三条 v2 原则（仍然成立）：
##   · **图底分离**：环境冷色低饱和，暖色全留给道具；
##   · **对比恒定**：调色板是基色，不随时刻改色；时刻色温 = 一条**乘法调色** `_light`
##     同步施加到环境与道具（道具经 `modulate` 接收）；墙/地板亮度比 ≥2×；
##   · **光向可见**：墙斜面、墙投影、道具落地影都按 −光照方向取向 —— 非色彩通道。
##
## 绘制顺序：房间外 → 地板(整片) → 墙根 AO → 墙投影 → 墙体 → 交界斜面 → 外轮廓 → 粒子。
## （道具 / 目标格光晕 / 玩家由 LevelManager 的 Entities、GoalMarker、Player 节点在上层绘制）
##

const CELL := 96.0
const ORIGIN := Vector2(0.0, 140.0)

# ── 基色调色板（不随时刻变化 → 图底对比恒定）──
# 明度阶梯：外域 0.02 < 地板 0.15 < 墙 0.30 < 道具 0.35–0.78 < 玩家 0.85
#   · 地板压暗成一整片 → 暖色道具（黄铜/木/锈/藤）弹得最狠；
#   · 墙比地板亮 ≥2×，靠投影 + 墙根 AO + 斜面读作"立起来的厚墙"。
const C_VOID      := Color("#05070B")   # 房间之外
const C_FLOOR     := Color("#232A34")   # 地板（单一基色，整片连续）
const C_WALL      := Color("#4C5769")   # 墙体主色（大面积，必须明显亮于地板）
const C_WALL_LIT  := Color("#74839A")   # 交界斜面 · 朝光
const C_WALL_MID  := Color("#39424F")   # 交界斜面 · 侧向
const C_WALL_DK   := Color("#2A313B")   # 交界斜面 · 背光
const C_WALL_EDGE := Color("#080B0F")   # 墙外轮廓

# ── 光影参数 ──
const BEVEL := 8.0              # 墙交界的斜面宽度（px）
const CONTOUR_W := 2.5          # 墙外轮廓线宽
const WALL_SHADOW_OFF := 15.0   # 墙体投影长度（沿 −光照方向，px）
const WALL_SHADOW_A := 0.42
const AO_BANDS := 5             # 墙根环境遮蔽的层数
const AO_BAND_W := 6.0          # 每层宽度（px）
const AO_MAX := 0.24            # 贴墙处最暗

# ── 时刻级"乘法调色" ──
const K_TINT := 0.55      # 时刻 tint 混入白光的比例：越大，色温分期越明显
const LUM_MIN := 0.55     # brightness=0 时的整体亮度
const LUM_MAX := 1.00     # brightness=1 时的整体亮度

var grid: Grid = null
var cell_size: float = CELL
var origin: Vector2 = ORIGIN
var tint: Color = Color.WHITE
var light_angle: float = 90.0
var brightness: float = 1.0
var particle: String = "DUST"

## 当前时刻的乘法调色（= 色温 tint × 亮度）。默认白光 = 不受影响
var _light: Color = Color.WHITE

var _parts: Array[Vector2] = []
var _pvel: Array[Vector2] = []


func setup(g: Grid, cs: float, org: Vector2) -> void:
	grid = g
	cell_size = cs
	origin = org
	_recompute_light()
	_spawn_particles()
	queue_redraw()


func set_timepoint(tp: TimepointDef) -> void:
	if tp == null:
		return
	tint = tp.tint
	light_angle = tp.light_angle
	brightness = tp.brightness
	particle = tp.particle
	_recompute_light()
	queue_redraw()


# ------------------------------------------------------------- 时刻调色 ---

##
## 把"色温 + 亮度"折算成一个**乘法因子**：
##   ① tint 按 K_TINT 混向白光，保留色相但不过度压暗；
##   ② 按最亮通道归一化 —— 只发生"偏色"，不发生"变暗"；
##   ③ 乘上亮度系数（LUM_MIN–LUM_MAX）。
## 结果恒 ≤ 1 → 只等比压暗 + 偏色，对比度不被冲掉。
##
func _recompute_light() -> void:
	var l: Color = Color.WHITE.lerp(tint, K_TINT)
	var m: float = maxf(l.r, maxf(l.g, l.b))
	if m > 0.001:
		l = Color(l.r / m, l.g / m, l.b / m, 1.0)
	var k: float = lerpf(LUM_MIN, LUM_MAX, clampf(brightness, 0.0, 1.0))
	_light = Color(l.r * k, l.g * k, l.b * k, 1.0)


## 供渲染层取用：把同一因子施加到道具上，保证"环境与道具被同一束光照射"
func light_color() -> Color:
	return _light


## 当前时刻的光照方向（**指向光源**）。投影方向 = −该向量。
func light_dir() -> Vector2:
	return _dir_from_angle(light_angle)


## 基色 → 施加时刻调色（保留 alpha）
func _g(c: Color) -> Color:
	return Color(c.r * _light.r, c.g * _light.g, c.b * _light.b, c.a)


func _dir_from_angle(deg: float) -> Vector2:
	var r := deg2rad(deg)
	return Vector2(cos(r), -sin(r))


func deg2rad(d: float) -> float:
	return d * 3.14159265 / 180.0


# ------------------------------------------------------------- 粒子 ------

func _spawn_particles() -> void:
	_parts.clear()
	_pvel.clear()
	if grid == null:
		return
	var w: float = float(grid.size.x) * cell_size
	var h: float = float(grid.size.y) * cell_size
	for i in 54:
		_parts.append(origin + Vector2(randf() * w, randf() * h))
		_pvel.append(Vector2(randf() - 0.5, randf() - 0.5) * 18.0)


func _process(delta: float) -> void:
	var drift := Vector2.ZERO
	var speed := 1.0
	match particle:
		"SPARK": drift = Vector2(0, -26); speed = 1.6
		"DUST": drift = Vector2(6, -4); speed = 0.5
		"RUST": drift = Vector2(-8, 14); speed = 0.9
		"ASH": drift = Vector2(0, 12); speed = 0.35
	var span := Vector2(10.0, 5.0)
	if grid != null:
		span = Vector2(grid.size)
	var r := Rect2(origin, span * cell_size)
	for i in _parts.size():
		var p: Vector2 = _parts[i]
		p += (_pvel[i] * speed + drift) * delta
		if p.x < r.position.x - 10.0: p.x = r.end.x + 10.0
		if p.x > r.end.x + 10.0: p.x = r.position.x - 10.0
		if p.y < r.position.y - 10.0: p.y = r.end.y + 10.0
		if p.y > r.end.y + 10.0: p.y = r.position.y - 10.0
		_parts[i] = p
	queue_redraw()


# ------------------------------------------------------------- 绘制 ------

const SIDES := [
	[Vector2i(0, -1), Vector2(0.0, -1.0)],
	[Vector2i(1, 0), Vector2(1.0, 0.0)],
	[Vector2i(0, 1), Vector2(0.0, 1.0)],
	[Vector2i(-1, 0), Vector2(-1.0, 0.0)],
]


func _cell_rect(c: Vector2i) -> Rect2:
	return Rect2(origin + Vector2(c) * cell_size, Vector2(cell_size, cell_size))


func _is_floor(c: Vector2i) -> bool:
	return grid != null and grid.is_inside(c) and not grid.is_wall(c)


func _is_wall(c: Vector2i) -> bool:
	return grid != null and grid.is_inside(c) and grid.is_wall(c)


func _draw() -> void:
	if grid == null:
		return
	var ld := light_dir()

	# ① 房间之外：房间（13×8 格）正好铺满设计画布，所以只需铺「HUD 背板」那一条带；
	#    下面那条仅在"画布比房间高"时才有内容（当前为 0，留着是为了不写死画布尺寸）。
	var room_w: float = float(grid.size.x) * cell_size
	var room_h: float = float(grid.size.y) * cell_size
	draw_rect(Rect2(0.0, 0.0, room_w, origin.y), _g(C_VOID))
	var below: float = get_viewport_rect().size.y - origin.y - room_h
	if below > 0.5:
		draw_rect(Rect2(0.0, origin.y + room_h, room_w, below), _g(C_VOID))

	# ② 地板：**一整片**。同一基色铺满所有非墙格、不画任何格线/棋盘 →
	#    相邻格之间没有任何缝，整片读作一块连续的地面。
	for y in grid.size.y:
		for x in grid.size.x:
			var c := Vector2i(x, y)
			if grid.is_wall(c):
				continue
			draw_rect(_cell_rect(c), _g(C_FLOOR))

	# ③ 墙根环境遮蔽：紧贴墙的地面压暗一圈（凹角自然更暗）——
	#    没有格线的情况下，这是把"地面贴着墙"读出来的主力。
	for y in grid.size.y:
		for x in grid.size.x:
			var c := Vector2i(x, y)
			if _is_floor(c):
				_draw_cell_ao(c)

	# ④ 墙体投影（逐格矩形在同一个平移下互不重叠 → 并起来是无缝的一整片影子）
	_draw_wall_shadows(ld)

	# ⑤ 墙体：逐格填同色、**不描边** → 相邻墙格自然并成一块连续实体
	for y in grid.size.y:
		for x in grid.size.x:
			var c := Vector2i(x, y)
			if grid.is_wall(c):
				draw_rect(_cell_rect(c), _g(C_WALL))

	# ⑥ 交界斜面：只在"墙 ↔ 非墙"的边界上画 → 得到连续的一圈受光/背光边
	_draw_wall_bevels(ld)

	# ⑦ 墙外轮廓：同样只画交界边 → 一整条连续轮廓线
	_draw_wall_contour()

	# ⑧ 粒子
	_draw_particles()


## 一格地板的墙根压暗：对每条邻墙的边，从墙往格内铺 AO_BANDS 条递减的暗带
func _draw_cell_ao(c: Vector2i) -> void:
	var r := _cell_rect(c)
	for s in SIDES:
		var d: Vector2i = s[0]
		if _is_floor(c + d):
			continue
		for i in AO_BANDS:
			var t: float = float(i) / float(AO_BANDS)
			var a: float = AO_MAX * (1.0 - t) * (1.0 - t)   # 二次衰减：越贴墙越暗
			var w: float = AO_BAND_W
			var band: Rect2
			if d == Vector2i(0, -1):
				band = Rect2(r.position.x, r.position.y + i * w, r.size.x, w)
			elif d == Vector2i(0, 1):
				band = Rect2(r.position.x, r.end.y - (i + 1) * w, r.size.x, w)
			elif d == Vector2i(-1, 0):
				band = Rect2(r.position.x + i * w, r.position.y, w, r.size.y)
			else:
				band = Rect2(r.end.x - (i + 1) * w, r.position.y, w, r.size.y)
			draw_rect(band, Color(0.0, 0.0, 0.0, a))


## 墙体投影：沿 −光照方向把"整块墙"平移一层黑影。
## ⚠ 同一个平移量作用在互不相交的格子上，平移后依然互不相交 → 半透明矩形
##   并起来**不会有重叠接缝**（这是能放心用 alpha 铺影子的原因）。
func _draw_wall_shadows(ld: Vector2) -> void:
	var off: Vector2 = -ld * WALL_SHADOW_OFF
	for y in grid.size.y:
		for x in grid.size.x:
			var c := Vector2i(x, y)
			if not grid.is_wall(c):
				continue
			var r := _cell_rect(c)
			draw_rect(Rect2(r.position + off, r.size), Color(0.0, 0.0, 0.0, WALL_SHADOW_A))


## 交界斜面：墙与非墙之间的那条边，往墙内偏 BEVEL 画一条带，颜色随光向变化。
## 内部接缝（墙挨墙）跳过 → 相邻墙格自然并成一块，不会出现"每格一个方块"。
func _draw_wall_bevels(ld: Vector2) -> void:
	for y in grid.size.y:
		for x in grid.size.x:
			var c := Vector2i(x, y)
			if not grid.is_wall(c):
				continue
			var r := _cell_rect(c)
			for s in SIDES:
				var d: Vector2i = s[0]
				var n: Vector2 = s[1]
				if _is_wall(c + d):
					continue
				var band: Rect2
				if d == Vector2i(0, -1):
					band = Rect2(r.position.x, r.position.y, r.size.x, BEVEL)
				elif d == Vector2i(0, 1):
					band = Rect2(r.position.x, r.end.y - BEVEL, r.size.x, BEVEL)
				elif d == Vector2i(-1, 0):
					band = Rect2(r.position.x, r.position.y, BEVEL, r.size.y)
				else:
					band = Rect2(r.end.x - BEVEL, r.position.y, BEVEL, r.size.y)
				draw_rect(band, _g(_side_color(n, ld)))


## 墙外轮廓：只在交界边画线。逐格线段首尾相接 → 视觉上是一条连续轮廓。
func _draw_wall_contour() -> void:
	var col := _g(C_WALL_EDGE)
	for y in grid.size.y:
		for x in grid.size.x:
			var c := Vector2i(x, y)
			if not grid.is_wall(c):
				continue
			var r := _cell_rect(c)
			var p := r.position
			var s := r.size
			for spec in SIDES:
				var d: Vector2i = spec[0]
				if _is_wall(c + d):
					continue
				if d == Vector2i(0, -1):
					draw_line(p, Vector2(p.x + s.x, p.y), col, CONTOUR_W)
				elif d == Vector2i(0, 1):
					draw_line(Vector2(p.x, p.y + s.y), p + s, col, CONTOUR_W)
				elif d == Vector2i(-1, 0):
					draw_line(Vector2(p.x, p.y + s.y), p, col, CONTOUR_W)
				else:
					draw_line(Vector2(p.x + s.x, p.y), p + s, col, CONTOUR_W)


## 斜面配色：朝向光源 → 亮；背向 → 暗；侧向 → 中间调
func _side_color(n: Vector2, ld: Vector2) -> Color:
	var f: float = n.dot(ld)
	if f > 0.35:
		return C_WALL_LIT
	if f < -0.35:
		return C_WALL_DK
	return C_WALL_MID


func _draw_particles() -> void:
	var pc := Color.WHITE
	var ps := 1.8
	match particle:
		"SPARK": pc = Color("#E2763A"); ps = 2.4
		"DUST": pc = Color("#E8DFC8"); ps = 1.7
		"RUST": pc = Color("#C98A4B"); ps = 2.1
		"ASH": pc = Color("#B9B9B4"); ps = 1.5
	pc = _g(pc)
	for p in _parts:
		# 柔光晕 + 实心核：比单点更易被看见，但仍不抢道具
		draw_circle(p, ps * 2.6, Color(pc.r, pc.g, pc.b, 0.10))
		draw_circle(p, ps, Color(pc.r, pc.g, pc.b, 0.62))
