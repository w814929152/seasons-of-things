class_name UiStyle
extends RefCounted
##
## HUD 统一视觉语言（调色板 + 面板 / 分界 / 文字绘制），全程序化，零外部美术资源。
##
## 为什么单列一个文件：调色板原先以字面量散落在 hud / time_ruler / hourglass_hud /
## backpack_hud / hint_layer 五处，改一次要搜五个文件、极易走样。这里收成唯一真相源，
## 取值沿用世界层已经定下的那套（黄铜 + 深底 + 暖白字），所以 HUD 与场景是**同一套语言**。
##

# ── 调色板 ──────────────────────────────────────────────────────────
const BG_BAND      := Color("#0E1216")   # HUD 背板（略亮于世界 void #05070B → 形成"仪表台"）
const BG_PANEL     := Color("#161A1F")   # 分组面板底
const BG_SLOT      := Color("#3A3F46")   # 空槽底
const BG_SLOT_IN   := Color("#4A5560")   # 槽内高光
const BRASS        := Color("#6B5334")   # 黄铜：边框主色
const BRASS_LIT    := Color("#8A6B45")   # 黄铜：亮面
const ACCENT       := Color("#E8C56A")   # 强调：当前 / 可用
const ACCENT_HI    := Color("#FFE9B0")   # 最亮：游标 / 当前文字
const INK          := Color("#F0E4C8")   # 正文（暖白）
const INK_DIM      := Color("#C9BFA8")   # 次级文字
const INK_MUTE     := Color("#7A6A55")   # 弱化说明文字
const EDGE_DK      := Color("#2B2F36")   # 深色描边
const WARN         := Color("#E0763A")   # 警告 / 耗尽

const BORDER_W     := 2.0
const HAIRLINE_W   := 2.0
## HUD 背板高度（= 世界网格原点，**不可改**：网格与关卡坐标都挂在这个数上）
const BAND_H       := 140.0


## 分组面板：深底 + 黄铜细边。HUD 上每个"仪表分组"都用它，读起来是一台机器的三个表盘。
static func draw_plate(c: CanvasItem, r: Rect2, bg: Color = BG_PANEL,
		border: Color = BRASS, w: float = BORDER_W) -> void:
	c.draw_rect(r, bg)
	c.draw_rect(r, border, false, w)


## 水平细线（分界用）。y 为线中心。
static func hline(c: CanvasItem, y: float, x0: float, x1: float,
		col: Color, w: float = HAIRLINE_W) -> void:
	c.draw_rect(Rect2(x0, y - w * 0.5, x1 - x0, w), col)


## 画一段文字，`at.y` 传的是**视觉中心**而不是基线 —— 想把文字对到某个 y 中线时，
## 不用再手工试 baseline 偏移（旧代码到处是 `位置 + 12` 这类魔法数）。
## `width > 0` 时按对齐方式在 [at.x, at.x + width) 内排版（用于刻度名居中）。
static func draw_text(c: CanvasItem, text: String, at: Vector2, size: int, col: Color,
		align: int = HORIZONTAL_ALIGNMENT_CENTER, width: float = -1.0) -> void:
	if text == "":
		return
	var f := UiFont.get_font()
	var baseline := at.y + (f.get_ascent(size) - f.get_descent(size)) * 0.5
	c.draw_string(f, Vector2(at.x, baseline), text, align, width, size, col)


## 供 Button 用的方角扁平样式（项目里没有任何圆角，全部是方角黄铜）
static func button_box(bg: Color, border: Color, pad_right: float = 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(BORDER_W))
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0 + pad_right
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb
