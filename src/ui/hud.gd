class_name HUD
extends CanvasLayer
##
## HUD 根（architecture §2.1 UILayer）：与关卡解耦，只订阅信号、只读状态。
## 用户操作经 UI → 调 TimeController / LevelManager 的公开方法；UI 从不持有游戏真相。
##
## 常驻元素（GDD §5 设计红线）：当前时刻罗马刻度 + 时砂 + 背包 2 格 + 撤销按钮。
##
## ── 本轮 UI 优化（版式 + 一致性）────────────────────────────────────
## 诊断：三组常驻信息 + 三个按钮各自浮在一片近黑底上，彼此没有关联、上下没有分界，
## 读起来像**调试浮层**而不是"仪表面板"。具体四条：
##   ① **没有背板也没有分界**：HUD 区其实是世界 void（#05070B）被时刻色调染过的一片，
##      底部没有任何东西把"仪表"与"场景"切开 → 场景顶端像被硬压了一条黑边。
##   ② **按钮用的是 Godot 默认主题**（圆角灰玻璃），与场景里全部程序化绘制的
##      方角黄铜风格是两套语言，一眼出戏。
##   ③ **底部状态行在重复信息**：时刻 / 时砂 / 背包都已经在刻度尺与表盘上常驻了，
##      这行又整抄一遍；真正独有的「坐标 / 面向」反被淹没在冗余里。
##   ④ 三组元素没有统一的面板语言（时砂那组还是"图标画在控件原点、数字与说明分列两侧"）。
## 改法：
##   · HUD 自绘**背板 + 黄铜分界线 + 世界侧三级软阴影** → 一条读得出来的"仪表台"；
##   · 三组统一为 `UiStyle.draw_plate()` 的**面板 + 铭文**（时刻 / 时砂 / 背包 0/2）；
##   · 按钮改为**方角黄铜自适应主题**（normal / hover / pressed / disabled 四态 + 热键角标）；
##   · 状态行只留**独有信息**（坐标 / 面向），弱化配色、右对齐到按钮下方；
##   · 顺带补上 GDD §7 只写在设计文档里的反馈：**死锁时撤销按钮高亮呼吸**。
##

const DESIGN_W := 1248.0          # 设计分辨率宽（与 window_scaler / project.godot 一致）
const BAND_H := UiStyle.BAND_H    # 140 —— 同时是世界网格原点，**不可改**
const PAD := 16.0
const BTN_W := 74.0
const BTN_H := 34.0
const BTN_GAP := 8.0
const BTN_Y := 36.0
const STATUS_W := 320.0
const STATUS_Y := 80.0

var _band: Control = null
var _ruler: TimeRuler = null
var _glass: HourglassHUD = null
var _pack: BackpackHUD = null
var _hint: HintLayer = null
var _status: Label = null
var _lm: LevelManager = null
var _undo_btn: Button = null
var _undo_sb: StyleBoxFlat = null
## 死锁后的"去按撤销"提示脉冲剩余时长（GDD §7）
var _pulse_t := 0.0


func _ready() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 背板垫在最底层（先 add_child → 先绘制）
	_band = Control.new()
	_band.name = "Band"
	_band.set_anchors_preset(Control.PRESET_FULL_RECT)
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.draw.connect(_draw_band)
	root.add_child(_band)

	# ★ 这里原本还有一层全屏 ColorRect 色调叠加（tint × 0.16）。
	#   已移除：时刻的"色温分期"改由 EnvironmentLayer 的**乘法调色**统一承担，
	#   并同步施加到道具上。加色叠加会把暗部整体抬亮、压低对比度，正是可读性的敌人。
	#   本轮再往上补的"背板"是**恒定色**（不参与时刻调色）—— 仪表读数是稳定量，
	#   不该跟着世界一起变色，这也延续了设计红线里"图底对比恒定"的思路。

	# ── 三组常驻仪表：同一套「面板 + 铭文」语言，组间 12px ──────────────
	_ruler = TimeRuler.new()
	_ruler.position = Vector2.ZERO
	_ruler.size = Vector2(456, BAND_H)
	_ruler.mouse_filter = Control.MOUSE_FILTER_STOP   # 刻度要能点
	root.add_child(_ruler)

	_glass = HourglassHUD.new()
	_glass.position = Vector2(468, 16)
	_glass.size = Vector2(148, 108)
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_glass)

	_pack = BackpackHUD.new()
	_pack.position = Vector2(628, 16)
	_pack.size = Vector2(168, 108)
	_pack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_pack)

	# ── 按钮：方角黄铜主题 + 热键角标，整组贴右边缘 ────────────────────
	var bx := DESIGN_W - PAD - (BTN_W * 3.0 + BTN_GAP * 2.0)
	for spec in [["撤销", "Z", "_on_undo"], ["重置", "R", "_on_reset"], ["提示", "H", "_on_hint"]]:
		var b := Button.new()
		b.text = String(spec[0])
		b.position = Vector2(bx, BTN_Y)
		b.size = Vector2(BTN_W, BTN_H)
		b.focus_mode = Control.FOCUS_NONE
		UiFont.apply(b, 14)
		var box := _apply_button_style(b)
		if String(spec[2]) == "_on_undo":
			_undo_btn = b
			_undo_sb = box
		b.pressed.connect(Callable(self, String(spec[2])))
		root.add_child(b)
		# 热键角标：与按钮文字分开配色，别再糊成 "撤销Z" 一串
		var k := UiFont.make_label(String(spec[1]), 11)
		k.add_theme_color_override("font_color", UiStyle.INK_MUTE)
		k.position = Vector2(BTN_W - 20.0, 9.0)
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(k)
		bx += BTN_W + BTN_GAP

	# 状态行：只保留**别处没有的**信息（坐标 / 面向），弱化到"仪表读数"的份量
	_status = UiFont.make_label("", 13)
	_status.add_theme_color_override("font_color", UiStyle.INK_MUTE)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.position = Vector2(DESIGN_W - PAD - STATUS_W, STATUS_Y)
	_status.size = Vector2(STATUS_W, 22)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_status)

	_hint = HintLayer.new()
	# ★ 提示条**底边锚定、向上生长**（内部用 PanelContainer 自适应高度）。
	#   旧版把顶边钉在 y=812 往下长，行数一多就顶出 908 的画布底边，最后几行被切掉。
	#   现在给 HintLayer 一块"从底边往上够长"的矩形：底边 = 908（画布底），
	#   内容少时提示条仍只压在网格最下一行（y=7，全是边界墙）上，不遮挡可通行格；
	#   内容多时向上长，永远不出画布。
	_hint.position = Vector2(16, 640)
	_hint.size = Vector2(1216, 268)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint)

	_hint.push("《物候 · 钟械工坊前厅》｜ ↑↓←→ 移动(按住连走) · A/D 切时刻 · 空格 持取 · Q 放置 · E 使用 · Tab 观察 · Z 撤销 · H 提示 · 左键点击/拖动走位")


## HUD 背板 + 与世界的分界：黄铜细线 + 世界侧三级软阴影。
## 背板取 #0E1216（略亮于世界 void #05070B）→ 读成一块"台面"，而不是把场景压黑。
func _draw_band() -> void:
	var w: float = _band.size.x
	_band.draw_rect(Rect2(0, 0, w, BAND_H), Color(UiStyle.BG_BAND, 0.94))
	for k in 3:
		_band.draw_rect(Rect2(0, BAND_H + k * 4.0, w, 4.0), Color(0, 0, 0, 0.16 - k * 0.05))
	UiStyle.hline(_band, BAND_H - 1.0, 0.0, w, UiStyle.BRASS, UiStyle.HAIRLINE_W)


func _apply_button_style(b: Button) -> StyleBoxFlat:
	var sb_n := UiStyle.button_box(Color("#1A1F25"), UiStyle.BRASS, 18.0)
	b.add_theme_stylebox_override("normal", sb_n)
	b.add_theme_stylebox_override("hover", UiStyle.button_box(Color("#242A31"), UiStyle.ACCENT, 18.0))
	b.add_theme_stylebox_override("pressed", UiStyle.button_box(Color("#12161A"), UiStyle.BRASS_LIT, 18.0))
	b.add_theme_stylebox_override("disabled", UiStyle.button_box(Color("#14171B"), Color("#3A342A"), 18.0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", UiStyle.INK)
	b.add_theme_color_override("font_hover_color", UiStyle.ACCENT_HI)
	b.add_theme_color_override("font_pressed_color", UiStyle.ACCENT)
	b.add_theme_color_override("font_disabled_color", Color("#6B6B63"))
	return sb_n


func bind_level(lm: LevelManager) -> void:
	_lm = lm
	_ruler.bind(lm.tc, lm.level)
	_glass.bind(lm.tc)
	_pack.bind(lm.tc)
	lm.level_message.connect(func(text: String) -> void: _hint.push(text))
	lm.refreshed.connect(_on_refresh)
	# GDD §7：这条时间线走不通时，把玩家推向"免费且无损的撤销"
	lm.tc.deadlock_detected.connect(func() -> void: _pulse_t = 4.0)
	_on_refresh()


## 死锁脉冲：撤销按钮边框在 4 s 内呼吸一次，之后收回常态黄铜。
## 只做"注意力提示"，不改变任何游戏状态。
func _process(delta: float) -> void:
	if _pulse_t <= 0.0:
		return
	_pulse_t = maxf(0.0, _pulse_t - delta)
	if _undo_sb == null or _undo_btn == null:
		return
	if _pulse_t <= 0.0:
		_undo_sb.border_color = UiStyle.BRASS
	else:
		var k := 0.5 + 0.5 * sin(_pulse_t * 8.0)
		_undo_sb.border_color = UiStyle.BRASS.lerp(UiStyle.ACCENT_HI, k)
	_undo_btn.queue_redraw()


func _on_refresh() -> void:
	if _lm == null:
		return
	_ruler.queue_redraw()
	_glass.refresh()
	_pack.refresh()
	if _status != null:
		# ★ 只显示别处没有的信息：时刻在刻度尺上、时砂在沙漏表盘上、背包在背包面板上。
		#   这里再抄一遍只会把真正独有的「坐标 / 面向」淹掉。
		_status.text = "坐标 (%d,%d) ｜ 面向：%s" % [
			_lm.tc.player_pos.x, _lm.tc.player_pos.y, _lm.target_label()]


func _on_undo() -> void:
	if _lm != null:
		_lm.tc.undo_step()
		_lm.refresh_all()


func _on_reset() -> void:
	if _lm != null:
		_lm.tc.reset()
		_lm.refresh_all()


func _on_hint() -> void:
	if _lm != null:
		_lm._do_hint()
