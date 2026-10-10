class_name TestHudLayout
extends RefCounted
##
## HUD 版式专项 —— 回归「三组仪表 + 按钮挤成一团 / 溢出 / 压在场景上」这类问题。
##
## 背景（优化前的实测状态）：
##   · 时刻刻度尺、时砂、背包、三个按钮各自浮在世界 void 上，**没有背板也没有分界**；
##   · 按钮是 Godot 默认主题（圆角灰玻璃），与全程序化绘制的方角黄铜风格两套语言；
##   · 底部状态行把「时刻 / 时砂 / 背包」又抄了一遍，独有的「坐标 / 面向」被淹没；
##   · 刻度尺的 4 块时刻名铭牌是**空框**（代码画了底色却从没写文字）。
##
## 本组锁死三条不变量：
##   A. 三组面板 + 三个按钮**互不重叠**，且全部落在 1248×140 的仪表带内（右/左各留 16px）；
##   B. HUD 带高 = 世界网格原点（140），**不可漂移** —— 漂了这个数整关坐标全错；
##   C. 刻度名铭牌可点（点名字能跳到该时刻）、状态行不再重复别处已有的信息、
##      死锁脉冲会在有限时间内自行收回。
##

const BAND_H := 140.0
const DESIGN_W := 1248.0
const PAD := 16.0


static func _mk(root: Node) -> Array:
	var lm = preload("res://src/level/level_manager.gd").new()
	root.add_child(lm)
	lm.start_level()
	var hud = preload("res://src/ui/hud.gd").new()
	root.add_child(hud)
	hud.bind_level(lm)
	return [lm, hud]


static func _buttons(hud) -> Array[Button]:
	var out: Array[Button] = []
	for c in hud._ruler.get_parent().get_children():
		if c is Button:
			out.append(c)
	return out


static func _plates(hud) -> Array:
	return [
		["时刻", Rect2(hud._ruler.position + TimeRuler.PLATE.position, TimeRuler.PLATE.size)],
		["时砂", Rect2(hud._glass.position + HourglassHUD.PLATE.position, HourglassHUD.PLATE.size)],
		["背包", Rect2(hud._pack.position + BackpackHUD.PLATE.position, BackpackHUD.PLATE.size)],
	]


static func run(h: TestHarness, root: Node) -> void:
	h.suite("HUD 版式（面板不重叠 / 不越界 / 分界与铭文）")

	# B. HUD 带高必须等于世界网格原点
	h.eq(UiStyle.BAND_H, BAND_H, "HUD 带高 = 世界网格原点 140（改了这个数整关坐标全错）")
	h.eq(HUD.BAND_H, BAND_H, "HUD 引用的带高与 UiStyle 一致")

	var pair := _mk(root)
	var lm = pair[0]
	var hud = pair[1]
	h.ck(hud.is_node_ready(), "HUD 已就绪")

	# A1. 三组面板互不重叠，且在带内、在画布内
	var plates := _plates(hud)
	h.eq(plates.size(), 3, "有三组仪表面板：时刻 / 时砂 / 背包")
	for p in plates:
		var name: String = p[0]
		var r: Rect2 = p[1]
		h.ck(r.position.y >= 0.0 and r.end.y <= BAND_H,
			"%s 面板纵向落在 HUD 带内  [%.0f..%.0f]" % [name, r.position.y, r.end.y])
		h.ck(r.position.x >= PAD - 0.5 and r.end.x <= DESIGN_W - PAD + 0.5,
			"%s 面板横向留出 %.0fpx 边距  [%.0f..%.0f]" % [name, PAD, r.position.x, r.end.x])
		h.ck(r.size.x > 0.0 and r.size.y > 0.0, "%s 面板尺寸有效 %s" % [name, str(r.size)])
	for i in plates.size():
		for j in range(i + 1, plates.size()):
			h.ck(not (plates[i][1] as Rect2).intersects(plates[j][1] as Rect2),
				"面板不重叠：%s ↔ %s" % [plates[i][0], plates[j][0]])

	# A2. 三个按钮：尺寸一致、互不重叠、不越界、不压面板
	var btns := _buttons(hud)
	h.eq(btns.size(), 3, "有三个 HUD 按钮：撤销 / 重置 / 提示")
	var btn_rects: Array[Rect2] = []
	for b in btns:
		btn_rects.append(Rect2(b.position, b.size))
		h.eq(b.size, Vector2(HUD.BTN_W, HUD.BTN_H), "按钮「%s」尺寸统一" % b.text)
		h.ck(b.position.x >= 0.0 and b.position.x + b.size.x <= DESIGN_W - PAD + 0.5,
			"按钮「%s」不越过右边缘 %.0fpx 边距" % [b.text, PAD])
		h.ck(b.position.y >= 0.0 and b.position.y + b.size.y <= BAND_H,
			"按钮「%s」在 HUD 带内" % b.text)
		for p in plates:
			h.ck(not Rect2(b.position, b.size).intersects(p[1] as Rect2),
				"按钮「%s」不压 %s 面板" % [b.text, p[0]])
	for i in btn_rects.size():
		for j in range(i + 1, btn_rects.size()):
			h.ck(not btn_rects[i].intersects(btn_rects[j]), "按钮不重叠 #%d ↔ #%d" % [i, j])

	# A3. 状态行在带内、右对齐到与按钮同一右边界
	h.ck(hud._status.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "状态行右对齐")
	h.eq(hud._status.position.x + hud._status.size.x, DESIGN_W - PAD, "状态行右边界 = 画布右 - 16px")
	h.ck(hud._status.position.y + hud._status.size.y <= BAND_H, "状态行在 HUD 带内")

	# C1. 时刻名铭牌：数据有名字，且点名字能命中该刻度（旧代码铭牌是空框，也没接命中）
	for i in lm.level.timepoint_count():
		h.ck(lm.level.get_timepoint(i).label != "", "时刻 %d 有名字：%s" % [i, lm.level.get_timepoint(i).label])
	for i in lm.level.timepoint_count():
		var hit: int = hud._ruler._tick_at(Vector2(TimeRuler.TICK_X[i], TimeRuler.NAME_Y))
		h.eq(hit, i, "点击第 %d 个时刻名铭牌 → 命中该刻度" % (i + 1))
	h.eq(hud._ruler._tick_at(Vector2(TimeRuler.TICK_X[0], 4.0)), -1,
		"尺身以上（说明文字区）不误命中刻度")

	# C2. 状态行只留独有信息，不再重复时刻 / 时砂 / 背包
	var st: String = hud._status.text
	h.ck(st.contains("坐标") and st.contains("面向"), "状态行含独有信息：坐标 / 面向")
	h.ck(not st.contains("时砂") and not st.contains("背包") and not st.contains("时刻"),
		"状态行不再重复时刻 / 时砂 / 背包（实际：%s）" % st)

	# C3. 死锁脉冲：触发后有限时间内自行收回，且收回到常态黄铜
	h.eq(hud._pulse_t, 0.0, "初始无脉冲")
	lm.tc.deadlock_detected.emit()
	h.ck(hud._pulse_t > 0.0, "死锁信号 → 撤销按钮进入脉冲（%.1fs）" % hud._pulse_t)
	hud._process(0.2)
	h.ck(hud._undo_sb.border_color != UiStyle.BRASS, "脉冲进行中：撤销按钮边框偏离常态黄铜")
	hud._process(10.0)
	h.eq(hud._pulse_t, 0.0, "脉冲自行结束（不需要玩家做任何事）")
	h.eq(hud._undo_sb.border_color, UiStyle.BRASS, "脉冲结束后边框收回常态黄铜")

	# C4. 按钮四态都套了自绘样式（不再吃 Godot 默认主题）
	for b in btns:
		for st_name in ["normal", "hover", "pressed", "disabled"]:
			h.ck(b.get_theme_stylebox(st_name) is StyleBoxFlat,
				"按钮「%s」的 %s 态是自绘 StyleBoxFlat" % [b.text, st_name])
		h.ck(b.get_theme_stylebox("hover").border_color == UiStyle.ACCENT,
			"按钮「%s」悬停边框转强调色" % b.text)

	root.remove_child(lm)
	root.remove_child(hud)
	lm.free()
	hud.free()
