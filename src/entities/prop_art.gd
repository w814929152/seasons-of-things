class_name PropArt
extends RefCounted
##
## 全程序化绘制（**零外部美术资源**）。
##
## ★ 剪影守恒（硬约束 P1 / 视觉锚点 2）：同一实体的四个形态**共用同一剪影**
##   （KEY = 条状带齿端 / WEIGHT = 梯形带提环 / VINE = 自地面旋上的藤），
##   只变材质、侵蚀层级与细节。玩家必须一眼认出「是同一个东西」。
##   因此每种道具只有一个 draw_xxx 函数，形态差异只改颜色与细节层数。
##
## 侵蚀分级 0–3：0 崭新 / 1 使用痕迹 / 2 锈斑 / 3 崩解
##

const NEW_BRASS := Color("#E8C56A")
const BRASS_DK := Color("#8C6A2A")
const RUST := Color("#B5743A")
const RUST_DK := Color("#6E4522")
const STEEL := Color("#9AA0A8")
const STEEL_DK := Color("#4A5058")
const HOT := Color("#E2763A")
const WOOD := Color("#6B5334")
const DARK := Color("#2B2F36")
const GREY := Color("#8E8E88")
const GREEN := Color("#5E8A46")
const GREEN_DK := Color("#33512A")
const PLATE_C := Color("#7E838C")


# ------------------------------------------------------------------ KEY ---

## 剪影：一条带齿端的长条 + 顶端圆环（钥匙）。四形态共用。
static func draw_key(c: CanvasItem, form: StringName) -> void:
	var body := NEW_BRASS
	var edge := BRASS_DK
	var erosion := 0
	match form:
		&"INGOT": body = HOT; edge = Color("#7A3A18"); erosion = 0
		&"KEY_NEW": erosion = 0
		&"KEY_RUSTY": body = RUST; edge = RUST_DK; erosion = 2
		&"RUST_LUMP": body = RUST_DK; edge = DARK; erosion = 3
		&"KEY_BROKEN": body = RUST; edge = RUST_DK; erosion = 3
	if form == &"INGOT":
		# 金属锭：同一条状剪影，只是没有齿
		c.draw_rect(Rect2(-26, -12, 52, 26), body)
		c.draw_rect(Rect2(-26, -12, 52, 26), edge, false, 3.0)
		c.draw_rect(Rect2(-26, -12, 52, 8), Color(body, 0.55))
		if erosion == 0:
			c.draw_circle(Vector2(0, 0), 5, Color("#FFD79A", 0.5))
		return
	# 钥匙本体：竖杆 + 顶环 + 底部齿
	var shaft := Rect2(-7, -26, 14, 52)
	c.draw_rect(shaft, body)
	c.draw_rect(shaft, edge, false, 2.0)
	c.draw_arc(Vector2(0, -24), 11, 0, TAU, 20, body, 6.0, true)
	c.draw_arc(Vector2(0, -24), 11, 0, TAU, 20, edge, 2.0, true)
	if form == &"KEY_BROKEN":
		# 断成两截：同一剪影，中间断开
		c.draw_rect(Rect2(-7, -6, 14, 10), Color(body, 0.0))
		c.draw_rect(Rect2(-7, -4, 14, 6), DARK)
		c.draw_rect(Rect2(-7, 22, 14, 8), body)
		return
	# 齿端
	for i in 3:
		c.draw_rect(Rect2(7, 12 + i * 8, 13, 5), body)
		c.draw_rect(Rect2(7, 12 + i * 8, 13, 5), edge, false, 1.5)
	# 侵蚀斑点
	if erosion >= 2:
		for i in 5:
			var p := Vector2(-5 + (i * 7) % 12, -20 + (i * 13) % 44)
			c.draw_circle(p, 3.2 - erosion * 0.4, Color(RUST_DK, 0.75))
	if erosion >= 3:
		c.draw_circle(Vector2(4, 8), 7, Color(DARK, 0.35))


# --------------------------------------------------------------- WEIGHT ---

## 剪影：梯形 + 顶部提环。四形态共用。
static func draw_weight(c: CanvasItem, form: StringName) -> void:
	var body := NEW_BRASS
	var edge := BRASS_DK
	match form:
		&"MOLTEN": body = HOT; edge = Color("#7A3A18")
		&"WEIGHT_SEIZED": body = RUST; edge = RUST_DK
		&"WEIGHT_BURIED": body = Color("#8A7A63"); edge = Color("#5A4C3A")
	if form == &"MOLTEN":
		c.draw_colored_polygon(PackedVector2Array([
			Vector2(-30, 12), Vector2(-18, -8), Vector2(18, -8), Vector2(30, 12)]), body)
		c.draw_circle(Vector2(0, -4), 8, Color("#FFCE8A", 0.55))
		c.draw_circle(Vector2(12, 4), 4, Color("#FFE0AE", 0.35))
		return
	# 提环（剪影的一部分，四形态都在）
	c.draw_arc(Vector2(0, -22), 9, 0, TAU, 18, edge, 4.0, true)
	# 梯形本体
	var pts := PackedVector2Array([
		Vector2(-28, 20), Vector2(-19, -14), Vector2(19, -14), Vector2(28, 20)])
	c.draw_colored_polygon(pts, body)
	c.draw_line(Vector2(-28, 20), Vector2(-19, -14), edge, 3.0)
	c.draw_line(Vector2(19, -14), Vector2(28, 20), edge, 3.0)
	c.draw_line(Vector2(-19, -14), Vector2(19, -14), edge, 3.0)
	c.draw_line(Vector2(-28, 20), Vector2(28, 20), edge, 3.0)
	match form:
		&"WEIGHT_SEIZED":
			for i in 4:
				c.draw_circle(Vector2(-16 + i * 11, -4 + (i % 2) * 16), 4, Color(RUST_DK, 0.8))
			# 与地面锈成一体的锈斑
			c.draw_rect(Rect2(-30, 18, 60, 6), Color(RUST_DK, 0.9))
		&"WEIGHT_BURIED":
			# 落灰掩埋：只露出上半截 + 灰堆
			c.draw_colored_polygon(PackedVector2Array([
				Vector2(-34, 22), Vector2(-14, 4), Vector2(16, 2), Vector2(36, 22)]),
				Color("#6E6558"))
			c.draw_circle(Vector2(-8, 6), 5, Color("#8A8172", 0.6))
			c.draw_circle(Vector2(12, 8), 4, Color("#8A8172", 0.5))
		_:
			c.draw_line(Vector2(-24, 12), Vector2(24, 12), Color(NEW_BRASS, 0.5), 2.0)


# ----------------------------------------------------------------- VINE ---

## 剪影：自地面旋上的藤。四形态共用（大小/密度/颜色不同）。
static func draw_vine(c: CanvasItem, form: StringName) -> void:
	var col := GREEN
	var thick := 3.0
	var turns := 2
	var amp := 14.0
	match form:
		&"SPROUT": col = Color("#8FBF6A"); thick = 2.0; turns = 1; amp = 7.0
		&"YOUNG": col = GREEN; thick = 3.0; turns = 2; amp = 13.0
		&"THICK": col = GREEN_DK; thick = 6.0; turns = 3; amp = 20.0
		&"WITHERED": col = Color("#7A7264"); thick = 5.0; turns = 3; amp = 19.0
	var pts := PackedVector2Array()
	for i in 25:
		var u := float(i) / 24.0
		var y := 34.0 - u * 68.0
		var x := sin(u * TAU * turns) * amp * (1.0 - u * 0.35)
		pts.append(Vector2(x, y))
	c.draw_polyline(pts, col, thick, true)
	# 叶片（THICK 时成墙）
	var leaves := 3
	if form == &"THICK": leaves = 8
	if form == &"WITHERED": leaves = 4
	if form == &"SPROUT": leaves = 2
	for i in leaves:
		var u := float(i) / float(maxi(1, leaves - 1)) * 0.8
		var y := 30.0 - u * 60.0
		var x := sin(u * TAU * turns) * amp * (1.0 - u * 0.35)
		var lr := 1.0 if i % 2 == 0 else -1.0
		var leaf := PackedVector2Array([
			Vector2(x, y), Vector2(x + lr * 15, y - 7), Vector2(x + lr * 11, y + 7)])
		c.draw_colored_polygon(leaf, Color(col, 0.9))
	if form == &"THICK":
		c.draw_rect(Rect2(-40, -36, 80, 72), Color(GREEN_DK, 0.18))


# ----------------------------------------------------------------- GATE ---

static func draw_gate(c: CanvasItem, form: StringName, open: bool) -> void:
	var col := STEEL
	match form:
		&"BARRED_RUSTY": col = RUST
		&"BARRED_ROTTEN": col = Color("#6A6A62")
	# 门框（剪影骨架恒定）
	c.draw_rect(Rect2(-44, -44, 88, 88), DARK)
	c.draw_rect(Rect2(-38, -38, 76, 76), Color("#3E434B"))
	if open:
		# 开：栅条滑向一侧
		for i in 4:
			var x := -30.0 + i * 15.0
			c.draw_rect(Rect2(x + 26, -34, 7, 68), Color(col, 0.75))
		c.draw_rect(Rect2(-38, -38, 76, 76), Color(NEW_BRASS, 0.10), true)
		return
	for i in 5:
		var x := -32.0 + i * 15.0
		c.draw_rect(Rect2(x, -34, 8, 68), col)
		c.draw_rect(Rect2(x, -34, 8, 68), STEEL_DK, false, 1.5)
	# 锁
	c.draw_rect(Rect2(-10, -8, 20, 18), Color(col, 0.95))
	c.draw_rect(Rect2(-10, -8, 20, 18), DARK, false, 2.0)
	c.draw_arc(Vector2(0, 2), 5, 0, TAU, 14, DARK, 2.5, true)
	if form == &"BARRED_RUSTY":
		c.draw_circle(Vector2(10, 20), 5, Color(RUST_DK, 0.7))
	if form == &"BARRED_ROTTEN":
		c.draw_rect(Rect2(-32, 22, 12, 12), DARK)


# ---------------------------------------------------------------- GRATE ---

static func draw_grate(c: CanvasItem, form: StringName, open: bool) -> void:
	c.draw_rect(Rect2(-44, -44, 88, 88), DARK)
	c.draw_rect(Rect2(-38, -38, 76, 76), Color("#363B42"))
	if open:
		c.draw_rect(Rect2(-38, -38, 76, 16), STEEL_DK)
		c.draw_rect(Rect2(-38, -38, 76, 76), Color(GREEN, 0.12), true)
		for i in 5:
			c.draw_circle(Vector2(-26 + i * 13, 20), 2.5, Color(NEW_BRASS, 0.5))
		return
	for i in 5:
		var y := -34.0 + i * 15.0
		c.draw_rect(Rect2(-38, y, 76, 8), STEEL)
		c.draw_rect(Rect2(-38, y, 76, 8), STEEL_DK, false, 1.5)


# ---------------------------------------------------------------- PLATE ---

static func draw_plate(c: CanvasItem, form: StringName, pressed: bool) -> void:
	c.draw_rect(Rect2(-40, -40, 80, 80), Color("#33383F"))
	c.draw_rect(Rect2(-34, -34, 68, 68), Color("#454B54"))
	var inner := Color(PLATE_C, 1.0) if not pressed else Color("#5C6068")
	c.draw_rect(Rect2(-26, -26, 52, 52), inner)
	c.draw_rect(Rect2(-26, -26, 52, 52), DARK, false, 2.5)
	if pressed:
		c.draw_rect(Rect2(-20, -20, 40, 40), Color("#3C4048"))
		c.draw_rect(Rect2(-20, -20, 40, 40), NEW_BRASS, false, 3.0)
		for i in 4:
			c.draw_line(Vector2(-26, -26 + i * 17), Vector2(26, -30 + i * 17),
				Color(NEW_BRASS, 0.35), 2.0)
	else:
		c.draw_rect(Rect2(-20, -20, 40, 40), Color(PLATE_C, 0.6))
		c.draw_rect(Rect2(-20, -20, 40, 40), Color("#22262B"), false, 2.0)


# ----------------------------------------------------------------- EXIT ---

static func draw_exit(c: CanvasItem, form: StringName) -> void:
	c.draw_rect(Rect2(-44, -44, 88, 88), DARK)
	match form:
		&"NOT_BUILT":
			c.draw_rect(Rect2(-38, -38, 76, 76), Color("#2E3238"))
			for i in 4:
				c.draw_line(Vector2(-38, -38 + i * 25), Vector2(38, -38 + i * 25),
					Color("#4A5058", 0.5), 2.0)
		&"NO_HANDLE":
			c.draw_rect(Rect2(-34, -38, 68, 76), WOOD)
			c.draw_rect(Rect2(-34, -38, 68, 76), Color("#3A2C1C"), false, 3.0)
			c.draw_line(Vector2(-34, 0), Vector2(34, 0), Color("#3A2C1C"), 2.0)
			c.draw_circle(Vector2(22, 4), 4, Color("#2E3238"))   # 把手位空缺
		&"INTACT":
			c.draw_rect(Rect2(-34, -38, 68, 76), WOOD)
			c.draw_rect(Rect2(-34, -38, 68, 76), Color("#3A2C1C"), false, 3.0)
			c.draw_line(Vector2(-34, 0), Vector2(34, 0), Color("#3A2C1C"), 2.0)
			c.draw_circle(Vector2(22, 4), 5, NEW_BRASS)          # 有把手
			c.draw_arc(Vector2(22, 4), 5, 0, TAU, 12, BRASS_DK, 2.0, true)
			c.draw_rect(Rect2(-34, -38, 68, 76), Color(NEW_BRASS, 0.10), true)
		&"COLLAPSED":
			c.draw_rect(Rect2(-38, -38, 76, 76), Color("#3A3A36"))
			for i in 5:
				var p := Vector2(-30 + (i * 17) % 60, -28 + (i * 23) % 56)
				c.draw_rect(Rect2(p, Vector2(16, 11)), Color("#5A5147"))
				c.draw_rect(Rect2(p, Vector2(16, 11)), DARK, false, 1.5)
			c.draw_line(Vector2(-38, 30), Vector2(38, 14), Color("#6B6156"), 5.0)


# ---------------------------------------------------------------- STAND ---

static func draw_stand(c: CanvasItem, form: StringName) -> void:
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(-24, 34), Vector2(-15, -6), Vector2(15, -6), Vector2(24, 34)]), WOOD)
	c.draw_rect(Rect2(-30, -18, 60, 14), Color("#8A6B45"))
	c.draw_rect(Rect2(-30, -18, 60, 14), Color("#3A2C1C"), false, 2.5)
	c.draw_rect(Rect2(-30, -22, 60, 5), NEW_BRASS)


# ---------------------------------------------------------------- FORGE ---

static func draw_forge(c: CanvasItem, form: StringName) -> void:
	c.draw_rect(Rect2(-40, -34, 80, 74), Color("#4A4038"))
	c.draw_rect(Rect2(-40, -34, 80, 74), DARK, false, 3.0)
	c.draw_rect(Rect2(-26, -4, 52, 44), Color("#241F1C"))
	c.draw_rect(Rect2(-26, -4, 52, 44), Color("#6A5A48"), false, 2.0)
	c.draw_circle(Vector2(0, 20), 12, Color(HOT, 0.35))
	c.draw_circle(Vector2(0, 20), 6, Color("#E8A55A", 0.55))
	# 烟囱
	c.draw_rect(Rect2(18, -44, 14, 14), Color("#4A4038"))
	c.draw_rect(Rect2(18, -44, 14, 14), DARK, false, 2.0)
	c.draw_line(Vector2(-16, 34), Vector2(16, 34), Color("#7A6A55"), 3.0)


# ------------------------------------------------------------------ 通用 ---

## 侵蚀等级 0–3（供 HUD / 调试显示）
static func erosion_level(form: StringName) -> int:
	match form:
		&"INGOT", &"MOLTEN", &"SPROUT", &"KEY_NEW", &"WEIGHT_OK", &"YOUNG": return 0
		&"BARRED", &"GRATE", &"PLATE", &"STAND", &"FORGE": return 1
		&"KEY_RUSTY", &"WEIGHT_SEIZED", &"THICK", &"BARRED_RUSTY": return 2
	return 3


## 罗马刻度 I / II / III / IV —— 用线段绘制，规避字体缺字（色盲安全主标识）
static func draw_roman(c: CanvasItem, index: int, at: Vector2, h: float, col: Color) -> void:
	var w := maxf(2.0, h * 0.16)
	match index:
		0:
			_bar(c, at.x, at.y, w, h, col)
		1:
			_bar(c, at.x - w * 1.4, at.y, w, h, col)
			_bar(c, at.x + w * 1.4, at.y, w, h, col)
		2:
			_bar(c, at.x - w * 2.8, at.y, w, h, col)
			_bar(c, at.x, at.y, w, h, col)
			_bar(c, at.x + w * 2.8, at.y, w, h, col)
		3:
			_bar(c, at.x - w * 2.8, at.y, w, h, col)
			_bar(c, at.x + w * 2.8, at.y, w, h, col)
			# V：必须**对称居中**在两根竖杠之间，否则 Ⅳ 会读成 "|V|" 偏到一边
			c.draw_line(Vector2(at.x - w * 1.6, at.y - h * 0.5),
				Vector2(at.x, at.y + h * 0.5), col, w, true)
			c.draw_line(Vector2(at.x, at.y + h * 0.5),
				Vector2(at.x + w * 1.6, at.y - h * 0.5), col, w, true)
		_:
			_bar(c, at.x, at.y, w, h, col)


static func _bar(c: CanvasItem, x: float, y: float, w: float, h: float, col: Color) -> void:
	c.draw_rect(Rect2(x - w * 0.5, y - h * 0.5, w, h), col)
