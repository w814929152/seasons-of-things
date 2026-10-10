class_name TimeRuler
extends Control
##
## 黄铜刻度尺（UI 隐喻，概念文档 §7 视觉锚点 4）：**不是进度条**。
## 罗马刻度 Ⅰ–Ⅳ 常驻 —— 这是色盲安全的**主**区分通道（色彩只是第 5 条）。
## 点击刻度、或刻度下方的**时刻名**，都能跳到该时刻（消耗 |Δt| 时砂）。
##
## ── 本轮 UI 优化（三个都是"看上去没做完 / 看不清"的问题）──────────────────
## ① **时刻名铭牌是空框**：旧代码在刻度下画了一块铭牌底色，却从没把 `tp.label`
##    画上去（4 个空荡荡的深色矩形）。现在把「铸造·晨 / 新光·昼 / 锈时·昏 / 沉寂·夜」
##    真正刻进铭牌 —— 这是除罗马刻度外**第二条非色彩通道**，也是玩家唯一能读懂刻度的入口。
## ② **游标压住当前罗马刻度**：旧游标是一条 10px 宽的浅色长条（y 8..70），
##    正好盖在当前刻度的数字上 —— 最该被看见的主标识反而被自己的游标挡住。
##    现在游标改成**尺身上方的三角指针 + 整列淡色高亮**，数字区完全让开。
## ③ **罗马刻度用笔画拼**（`PropArt.draw_roman`）读起来像条形码；改用系统字体的
##    真字形 `tp.roman`（权威数据字段）后，Ⅰ/Ⅱ/Ⅲ/Ⅳ 一眼可辨。
##

var tc: TimeController = null
var level: LevelData = null
var _hover: int = -1

## ── 布局（本控件局部坐标，由 hud.gd 摆放）────────────────────────────
const PLATE := Rect2(16, 16, 440, 108)      # 分组面板 16..124
const CAP_AT := Vector2(34, 30)             # 说明文字「时刻」的视觉中心
const BODY := Rect2(36, 44, 400, 44)        # 尺身 44..88
const NUM_Y := 60.0                         # 罗马刻度视觉中心
const TICK_Y := 74.0                        # 刻度线顶端
const NAME_Y := 106.0                       # 时刻名铭牌中心
const NAME_W := 56.0
const NAME_H := 20.0
const TICK_X: Array[float] = [70.0, 170.0, 270.0, 370.0]


func bind(_tc: TimeController, _lv: LevelData) -> void:
	tc = _tc
	level = _lv


func _tick_x(i: int) -> float:
	return TICK_X[i] if i < TICK_X.size() else 70.0 + i * 100.0


func _draw() -> void:
	if tc == null or level == null:
		return
	UiStyle.draw_plate(self, PLATE)
	# 尺身：黄铜底 + 深色描边 + 顶面受光
	draw_rect(BODY, UiStyle.BRASS)
	draw_rect(Rect2(BODY.position.x, BODY.position.y, BODY.size.x, 8), UiStyle.BRASS_LIT)
	draw_rect(BODY, UiStyle.EDGE_DK, false, 3.0)
	UiStyle.draw_text(self, "时刻", CAP_AT, 13, UiStyle.INK_MUTE, HORIZONTAL_ALIGNMENT_LEFT)

	# 当前列底衬（先画，落在所有刻印之下）
	var cur_x := _tick_x(tc.current_t)
	draw_rect(Rect2(cur_x - 24.0, BODY.position.y, 48.0, BODY.size.y), Color(UiStyle.ACCENT, 0.14))

	for i in level.timepoint_count():
		var tp := level.get_timepoint(i)
		var x := _tick_x(i)
		var unlocked := level.is_unlocked(i)
		var cur := (i == tc.current_t)
		if i == _hover and unlocked:
			draw_rect(Rect2(x - 22.0, BODY.position.y, 44.0, BODY.size.y), Color(UiStyle.ACCENT, 0.20))
		# 刻度线：当前刻度更高更亮
		var tick_h := 18.0 if cur else 12.0
		draw_rect(Rect2(x - (3.0 if cur else 2.0), BODY.end.y - tick_h,
			6.0 if cur else 4.0, tick_h), UiStyle.ACCENT if cur else UiStyle.INK_DIM)
		# 罗马刻度（色盲安全主标识）
		UiStyle.draw_text(self, tp.roman if tp != null else "?",
			Vector2(x, NUM_Y), 22, UiStyle.ACCENT_HI if cur else UiStyle.INK_DIM)
		# 锁定时刻显示为断裂刻度（GDD §5 L5）
		if not unlocked:
			draw_line(Vector2(x - 11.0, TICK_Y - 4.0), Vector2(x + 11.0, BODY.end.y),
				UiStyle.EDGE_DK, 5.0)
		# 时刻名铭牌
		var plate_r := Rect2(x - NAME_W * 0.5, NAME_Y - NAME_H * 0.5, NAME_W, NAME_H)
		draw_rect(plate_r, Color(UiStyle.ACCENT if cur else UiStyle.INK_MUTE, 0.22 if cur else 0.10))
		UiStyle.draw_text(self, tp.label if tp != null else "",
			Vector2(x, NAME_Y), 12, UiStyle.ACCENT_HI if cur else UiStyle.INK_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, NAME_W)

	# 游标：尺身**上方**的三角指针（绝不压住罗马刻度）
	var tri := PackedVector2Array([
		Vector2(cur_x - 7.0, 34.0), Vector2(cur_x + 7.0, 34.0), Vector2(cur_x, 47.0)])
	draw_colored_polygon(tri, UiStyle.ACCENT_HI)
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), UiStyle.EDGE_DK, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _tick_at(event.position)
		if i >= 0 and tc != null and level.is_unlocked(i):
			tc.goto_t(i)
	elif event is InputEventMouseMotion:
		_hover = _tick_at(event.position)
		queue_redraw()


## 命中区覆盖「刻度线 + 罗马数字 + 时刻名铭牌」三处，点名字也能跳
func _tick_at(p: Vector2) -> int:
	if p.y < 26.0 or p.y > NAME_Y + NAME_H * 0.5 + 4.0:
		return -1
	var n: int = level.timepoint_count() if level != null else TICK_X.size()
	for i in n:
		if absf(p.x - _tick_x(i)) < 28.0:
			return i
	return -1
