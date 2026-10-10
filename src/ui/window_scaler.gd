class_name WindowScaler
extends RefCounted
##
## 窗口等比放大（让场景 / 道具更大更清晰）。
##
## 背景：本游戏的**一切**都按 1248×908 的「设计分辨率」绘制 ——
##   13×8 网格、每格 96 px，横向 13×96 = 1248 正好铺满，纵向 768 px，
##   HUD 占顶部 140 px。也就是说画布已被网格填满，**内部没有可榨的空间**。
##
## 因此「把场景变大、让道具更清晰」的唯一杠杆，就是把这整块设计画布**等比放大**。
## project.godot 里 `window/stretch/mode = "canvas_items"` —— 该模式下 2D 内容
## 按窗口分辨率重新光栅化，放大后是**清晰缩放**（不是拉伸位图，不会糊）。
##
## 本脚本只做一件事：开局把窗口设成「屏幕上放得下的最大等比尺寸」，并居中。
##
## ⚠ 只读环境信息，绝不触碰游戏状态（与渲染层同一条硬约束）。
##

## 设计分辨率，必须与 project.godot 的 window/size/viewport_width|height 保持一致
const DESIGN := Vector2(1248.0, 908.0)

## 缩放上限：超大屏幕上也不至于撑出一个夸张的大窗口
const MAX_SCALE := 2.0

## 自动模式下的屏幕占比：留出边距，避免窗口顶到任务栏 / 屏幕边缘
const SCREEN_FILL := 0.92

## 强制倍率：<= 0 走自动（按屏幕可用区域算）；想写死就改成正数，例如 1.5
static var FORCE_SCALE := 0.0


## 返回实际使用的缩放倍率（headless / 取不到屏幕信息时返回 1.0）
static func apply(scale_override: float = -1.0) -> float:
	# headless（测试 / 扫参）下没有真实显示服务器，绝不动窗口
	if DisplayServer.get_name() == "headless":
		return 1.0

	var screen: int = DisplayServer.window_get_current_screen()
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return 1.0

	var s: float = scale_override if scale_override > 0.0 else FORCE_SCALE
	if s <= 0.0:
		var fit: float = minf(float(usable.size.x) / DESIGN.x, float(usable.size.y) / DESIGN.y)
		s = clampf(fit * SCREEN_FILL, 1.0, MAX_SCALE)

	var win := Vector2i((DESIGN * s).round())
	DisplayServer.window_set_size(win)
	DisplayServer.window_set_position(usable.position + (usable.size - win) / 2)
	return s
