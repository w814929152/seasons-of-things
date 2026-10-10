class_name HintLayer
extends Control
##
## 提示 / 反馈层（GDD §7.3 三级提示 + §2.3 反馈）。
## 只显示文本；绝不直接给答案（L1 指向 → L2 缩窄 → L3 明示）。
## 同时承载「动作被拒绝的原因」文案（形态锁：太烫 / 锈死 / 太粗）。
##
## ── 布局：底边锚定 + 向上生长 ─────────────────────────────────────────
## 旧实现把提示条**顶部钉死在 y=812、往下长**，高度还按 `22 * 行数 + 12` 硬算：
##   ① 行数一多（Tab 观察、连按 H）就顶出 908 的画布底边 → 最后几行被边框切掉；
##   ② 硬算高度跟不上真实字体行高与自动折行 → 边框会压到文字上。
## 现在底 / 边框 / 内边距全部由 StyleBoxFlat 承担，**高度随文本真实高度撑开**，
## 且整条**贴住画布底边向上生长** —— 行数再多也只是往上长，永远不会被切。
## 边框始终在文字之外（内边距 ≥ 8px）。
##

var _lines: Array[String] = []
var _panel: PanelContainer = null
var _label: Label = null
const MAX_LINES := 5
## 提示条宽度：画布 1248 - 左右各 16 外边距 = 1216
const BOX_W := 1216.0
## 内边距：保证文字与边框之间始终有呼吸感（旧实现只有 6~8px 且被折行吃掉）
const PAD_X := 12.0
const PAD_Y := 8.0
## 距画布底边的留白：避免边框压在窗口最下一行像素上被"吃掉"
const BOTTOM_MARGIN := 8.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 万一内容多到超过自身高度，也让它是**往上**长，保持底边不动
	grow_vertical = Control.GROW_DIRECTION_BEGIN

	_panel = PanelContainer.new()
	_panel.name = "HintBox"
	# 不拦截鼠标：关卡靠 `_unhandled_input` 收左键点击寻路，面板一旦 STOP 就会吞掉点击
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 贴左下角 + 向上生长
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = 0.0
	_panel.offset_right = BOX_W
	_panel.offset_bottom = -BOTTOM_MARGIN
	_panel.add_theme_stylebox_override("panel", _make_stylebox())
	_panel.visible = false
	add_child(_panel)

	_label = UiFont.make_label("", 15)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)


## 底板 + 边框 + 内边距，全都交给 StyleBox —— 容器按文字真实高度自适应，
## 边框永远不会和文字重叠。
func _make_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#15181C", 0.72)
	sb.border_color = Color("#6B5334")
	sb.set_border_width_all(2)
	sb.content_margin_left = PAD_X
	sb.content_margin_right = PAD_X
	sb.content_margin_top = PAD_Y
	sb.content_margin_bottom = PAD_Y
	return sb


func push(text: String) -> void:
	for line in text.split("\n"):
		if line.strip_edges() == "":
			continue
		_lines.append(line)
	while _lines.size() > MAX_LINES:
		_lines.remove_at(0)
	if _label == null:
		return
	_label.text = "\n".join(_lines)
	_panel.visible = not _lines.is_empty()


func clear() -> void:
	_lines.clear()
	if _label != null:
		_label.text = ""
	if _panel != null:
		_panel.visible = false
