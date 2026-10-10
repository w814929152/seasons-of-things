class_name BackpackHUD
extends Control
##
## 背包 HUD：2 格常驻（GDD §5 L2）。
## 格内显示**冻结的形态** —— 手持物免疫时刻变化，这是 A5「状态冻结/携带」的可视证据。
##
## ── 本轮 UI 优化 ──────────────────────────────────────────────────
## ① 旧背包是两块**没有任何说明的深色方块**，浮在黑背板上：玩家看不出这是背包、
##    也看不到 "0/2" 的容量。现在收进面板并加上「背包 x/2」铭文 ——
##    容量数字从 HUD 底部那行 debug 状态文本（原先重复显示时砂/背包/时刻）
##    搬到了它真正该在的地方。
## ② 「冻结」角标原先是**一块不透明的金色矩形**（`draw_rect(14×12, ACCENT)`），
##    看上去像贴了张便签。现在改成程序化画的**六芒雪花徽章**，语义与形状对上了。
##

var tc: TimeController = null
var _cap: Label = null
const SLOT := 56.0
const GAP := 8.0
const PLATE := Rect2(0, 0, 168, 108)
const CAP_AT := Vector2(20, 24)
const SLOT_Y := 44.0


func bind(_tc: TimeController) -> void:
	tc = _tc


func _ready() -> void:
	_cap = UiFont.make_label("背包 0/2", 13)
	_cap.add_theme_color_override("font_color", UiStyle.INK_MUTE)
	_cap.position = Vector2(CAP_AT.x, CAP_AT.y - 7.0)
	add_child(_cap)


func _slot_rect(i: int) -> Rect2:
	var n := maxi(1, tc.inventory.cap) if tc != null else 2
	var total := n * SLOT + (n - 1) * GAP
	var x0 := (PLATE.size.x - total) * 0.5
	return Rect2(x0 + i * (SLOT + GAP), SLOT_Y, SLOT, SLOT)


func _draw() -> void:
	if tc == null:
		return
	UiStyle.draw_plate(self, PLATE)
	for i in tc.inventory.cap:
		var s := _slot_rect(i)
		draw_rect(s, UiStyle.BG_SLOT)
		draw_rect(s, UiStyle.EDGE_DK, false, 3.0)
		if i < tc.inventory.size():
			var it: InventoryItem = tc.inventory.items[i]
			draw_rect(s.grow(-4.0), UiStyle.BG_SLOT_IN)
			var c := s.position + Vector2(SLOT * 0.5, SLOT * 0.5)
			draw_set_transform(c, 0.0, Vector2(0.62, 0.62))
			match it.silhouette:
				&"KEY": PropArt.draw_key(self, it.form)
				&"WEIGHT": PropArt.draw_weight(self, it.form)
				_:
					draw_rect(Rect2(-14, -14, 28, 28), Color("#8A8F98"))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_draw_freeze_badge(s.position + Vector2(SLOT - 10.0, 10.0))
		else:
			# 空槽：内描一圈极淡的黄铜细线，免得读成"两个死方块"
			draw_rect(s.grow(-6.0), Color(UiStyle.BRASS, 0.40), false, 1.0)


## 「冻结」徽章：程序化六芒雪花（GDD §5 L4：手持物免疫时刻变化）
func _draw_freeze_badge(at: Vector2) -> void:
	draw_circle(at, 8.0, Color("#0E1216", 0.88))
	draw_arc(at, 8.0, 0.0, TAU, 24, UiStyle.BRASS, 1.5, true)
	for k in 3:
		var d := Vector2(cos(PI * k / 3.0), sin(PI * k / 3.0)) * 5.0
		draw_line(at - d, at + d, UiStyle.ACCENT, 1.6, true)


func refresh() -> void:
	if _cap != null and tc != null:
		_cap.text = "背包 %d/%d" % [tc.inventory.size(), tc.inventory.cap]
		_cap.add_theme_color_override("font_color",
			UiStyle.INK_DIM if tc.inventory.size() > 0 else UiStyle.INK_MUTE)
	queue_redraw()
