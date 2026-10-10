class_name TestHintLayout
extends RefCounted
##
## 提示条布局专项 —— 回归「文字提示被边框 / 画布底边切掉」。
##
## 背景（修复前实测，像素取样）：
##   提示条顶边钉死在 y=812、向下生长，高度按 `22 * 行数 + 12` 硬算：
##   · 连按 3 次 H（共 4 行）→ 第 4 行文字落在设计 y=904..908，
##     正好被 908 的画布底边切成两半，提示条自己的下边框整条跑到画外；
##   · `Tab` 观察一次会一口气 push 5 行 → 更严重；
##   · 硬算高度也追不上真实字体行高与自动折行 → 边框会压到文字上。
##
## 修复后应满足的三条不变量（本组断言）：
##   A. 提示条底边永远 ≤ 画布底边（908）——绝不越出画布被切；
##   B. 文字永远落在提示条**内边距以内** ——边框不压字；
##   C. 单行时提示条仍只压在网格最下一行（y=812..908，全是边界墙）上，
##      不遮挡任何可通行格。
##

const CANVAS := Vector2(1248.0, 908.0)
## 网格原点与格高（与 level_manager / environment_layer 一致）
const ORIGIN_Y := 140.0
const CELL := 96.0
## 提示条内边距下限（边框宽 2 + 呼吸感）
const MIN_PAD := 3.0


static func _mk(root: Node) -> Array:
	var lm = preload("res://src/level/level_manager.gd").new()
	root.add_child(lm)
	lm.start_level()
	var hud = preload("res://src/ui/hud.gd").new()
	root.add_child(hud)
	hud.bind_level(lm)
	return [lm, hud]


## 等两帧：容器的排序（PanelContainer 自适应高度）是延迟执行的
static func _settle(root: Node) -> void:
	await root.get_tree().process_frame
	await root.get_tree().process_frame


static func _panel_rect(hud) -> Rect2:
	var p: PanelContainer = hud._hint._panel
	return Rect2(p.global_position, p.size)


static func _label_rect(hud) -> Rect2:
	var l: Label = hud._hint._label
	return Rect2(l.global_position, l.size)


static func run_async(h: TestHarness, root: Node) -> void:
	h.suite("提示条布局（多行不被底边 / 边框切）")

	var pair := _mk(root)
	var lm = pair[0]
	var hud = pair[1]
	await _settle(root)
	h.ck(hud.is_node_ready(), "HUD 已就绪")

	# ---- C. 单行（常驻指令句）----
	var pr := _panel_rect(hud)
	h.ck(pr.size.y > 0.0, "常驻指令句：提示条已撑开高度（%.1f）" % pr.size.y)
	h.ck(pr.position.y + pr.size.y <= CANVAS.y + 0.5,
		"常驻指令句：提示条底边 %.1f ≤ 画布底 %.1f" % [pr.position.y + pr.size.y, CANVAS.y])
	h.ck(pr.position.y >= ORIGIN_Y + CELL * 7.0 - 0.5,
		"常驻指令句：提示条顶边 %.1f ≥ 最下一行顶（%.1f）→ 不遮挡可通行格"
			% [pr.position.y, ORIGIN_Y + CELL * 7.0])

	# ---- A + B. 逐行加压：直到 MAX_LINES 行 ----
	for i in range(hud._hint.MAX_LINES - 1):
		hud._hint.push("压测第 %d 行：这是一条用来把提示条撑到最大行数的测试文案。" % (i + 2))
		await _settle(root)
		pr = _panel_rect(hud)
		var lr := _label_rect(hud)
		var n: int = hud._hint._lines.size()
		h.ck(pr.position.y + pr.size.y <= CANVAS.y + 0.5,
			"%d 行：提示条底边 %.1f ≤ 画布底 %.1f（不被窗口切）"
				% [n, pr.position.y + pr.size.y, CANVAS.y])
		h.ck(pr.position.y >= 0.0,
			"%d 行：提示条顶边 %.1f ≥ 0（不越出画布顶）" % [n, pr.position.y])
		h.ck(lr.position.y - pr.position.y >= MIN_PAD - 0.01,
			"%d 行：文字上边距 %.1f ≥ %.1f（上边框不压字）"
				% [n, lr.position.y - pr.position.y, MIN_PAD])
		h.ck(pr.position.y + pr.size.y - (lr.position.y + lr.size.y) >= MIN_PAD - 0.01,
			"%d 行：文字下边距 %.1f ≥ %.1f（下边框不压字）"
				% [n, pr.position.y + pr.size.y - (lr.position.y + lr.size.y), MIN_PAD])

	h.eq(hud._hint._lines.size(), hud._hint.MAX_LINES, "行数已到上限 MAX_LINES")

	# ---- 超上限：旧行被挤掉，条本身不越长越高 ----
	var before := _panel_rect(hud).size.y
	hud._hint.push("再来一行，最旧的一行应被挤掉。")
	await _settle(root)
	h.eq(hud._hint._lines.size(), hud._hint.MAX_LINES, "超出上限后行数仍为 MAX_LINES")
	h.ck(absf(_panel_rect(hud).size.y - before) < 24.0,
		"超出上限后提示条高度不暴涨（%.1f → %.1f）" % [before, _panel_rect(hud).size.y])

	# ---- 极端：一行超长文本（模拟 Tab 观察的长描述）自动折行后仍不越界 ----
	hud._hint.clear()
	hud._hint.push("★".repeat(400))
	await _settle(root)
	pr = _panel_rect(hud)
	var lr2 := _label_rect(hud)
	h.ck(pr.position.y + pr.size.y <= CANVAS.y + 0.5,
		"超长折行：提示条底边 %.1f ≤ 画布底 %.1f" % [pr.position.y + pr.size.y, CANVAS.y])
	h.ck(lr2.position.y + lr2.size.y <= pr.position.y + pr.size.y - MIN_PAD + 0.01,
		"超长折行：文字底边 %.1f 在内边距以内（条底 %.1f）"
			% [lr2.position.y + lr2.size.y, pr.position.y + pr.size.y])

	# ---- 收起 ----
	hud._hint.clear()
	await _settle(root)
	h.ck(not hud._hint._panel.visible, "clear() 后提示条隐藏")

	root.remove_child(lm)
	root.remove_child(hud)
	lm.free()
	hud.free()
