class_name HourglassHUD
extends Control
##
## 时砂 HUD（GDD §5 L1 设计红线：L1/L2 必须**常驻可见**，不可隐藏）。
## 耗尽时沙漏变灰；死锁时额外提示（不是 Game Over，只是「这条线走不通」）。
##
## ── 本轮 UI 优化 ──────────────────────────────────────────────────
## 旧布局是三块浮在黑色背板上的东西，谁也不挨着谁：沙漏图标画在控件**左上角原点**
## （= 图标中心就在 (0,0)），数字 Label 偏到 (26,-12)，说明「时砂」又跑到 (-18,36)
## 左下角 —— 数字和说明分列两侧、基线都不一致，看不出这是一组信息。
## 现在收进一块面板，排成 **[沙漏图标] [说明 / 12 / 12]** 的左图标右文字结构，
## 数字与说明共用同一左基线，整组视觉中心落在面板中线上。
##

var tc: TimeController = null
var _num: Label = null
var _cap: Label = null

const PLATE := Rect2(0, 0, 148, 108)
const ICON_AT := Vector2(44, 54)      # 沙漏图标中心
const TEXT_X := 76.0                  # 说明 / 数字共用左基线
const CAP_Y := 40.0                   # 说明「时砂」视觉中心
const NUM_Y := 64.0                   # 数字视觉中心


func bind(_tc: TimeController) -> void:
	tc = _tc


func _ready() -> void:
	_cap = UiFont.make_label("时砂", 13)
	_cap.add_theme_color_override("font_color", UiStyle.INK_MUTE)
	_cap.position = Vector2(TEXT_X, CAP_Y - 7.0)
	add_child(_cap)
	_num = UiFont.make_label("12 / 12", 20)
	_num.position = Vector2(TEXT_X - 2.0, NUM_Y - 11.0)
	add_child(_num)


func _draw() -> void:
	if tc == null:
		return
	UiStyle.draw_plate(self, PLATE)
	var ratio := tc.hourglass / float(maxi(1, tc.hourglass_cap))
	var empty := tc.hourglass <= 0
	var col := UiStyle.INK_DIM if empty else UiStyle.ACCENT

	var top := PackedVector2Array([Vector2(-16, -28), Vector2(16, -28), Vector2(2, -2), Vector2(-2, -2)])
	var bot := PackedVector2Array([Vector2(-2, 2), Vector2(2, 2), Vector2(16, 28), Vector2(-16, 28)])
	# 整组平移到 ICON_AT（旧代码把图标画在控件原点，等于图标中心 = 控件左上角）
	draw_set_transform(ICON_AT, 0.0, Vector2.ONE)
	draw_colored_polygon(top, Color("#4A5058"))
	draw_colored_polygon(bot, Color("#4A5058"))

	if ratio > 0.0:
		var h := 26.0 * ratio
		var fill := PackedVector2Array([
			Vector2(-16, 28), Vector2(16, 28),
			Vector2(16 - (1.0 - ratio) * 6.0, 28 - h),
			Vector2(-16 + (1.0 - ratio) * 6.0, 28 - h)])
		draw_colored_polygon(fill, col)

	for seg in [[Vector2(-16, -28), Vector2(16, -28)], [Vector2(16, -28), Vector2(2, -2)],
			[Vector2(2, -2), Vector2(-16, -28)], [Vector2(-2, 2), Vector2(16, 28)],
			[Vector2(16, 28), Vector2(-16, 28)], [Vector2(-16, 28), Vector2(-2, 2)]]:
		draw_line(seg[0], seg[1], UiStyle.EDGE_DK, 3.0)
	if not empty:
		draw_line(Vector2(0, -2), Vector2(0, 4), col, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 耗尽时：面板边框转警告色，整组一眼可辨（GDD §2.4 软锁提示）
	if empty:
		draw_rect(PLATE, UiStyle.WARN, false, UiStyle.BORDER_W)


func refresh() -> void:
	if _num != null and tc != null:
		_num.text = "%d / %d" % [tc.hourglass, tc.hourglass_cap]
		_num.add_theme_color_override("font_color",
			UiStyle.WARN if tc.hourglass <= 0 else UiStyle.INK)
	queue_redraw()
