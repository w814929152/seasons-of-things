class_name TimeEntity
extends Node2D
##
## 道具节点基类（architecture §2.3）。
##
## 职责边界：**只读状态、只画出来**。
##   - 状态来自 TimeController.resolve_state 的结果（由 LevelManager 传入）
##   - 绝不反向写入游戏状态
##   - _draw() 读 _applied，按剪影守恒绘制
##
## 残影叠加（Tab 长按）：把同一实体在其它时刻的形态半透明同屏绘制。
##

var data: TimeEntityData = null
var cell_size: float = 96.0
var origin: Vector2 = Vector2.ZERO
## 当前时刻的光照方向（**指向光源**，由 LevelManager 每帧下发）。
## 道具落地阴影 = −该方向 → 影子随光角转动，是"现在是第几刻"的非色彩通道之一。
var light_dir: Vector2 = Vector2(0.0, -1.0)

var _applied: StateFrame = null
var _ghost: bool = false
var _ghost_forms: Array[StringName] = []
var _pressed: bool = false


func setup(d: TimeEntityData, cs: float, org: Vector2) -> void:
	data = d
	cell_size = cs
	origin = org
	name = String(d.id)


## 应用 resolve 结果（幂等：同样输入同样输出）
func apply_resolved(s: StateFrame, pressed: bool = false) -> void:
	_applied = s
	_pressed = pressed
	var gone := (s == null) or s.removed or s.pos == StateFrame.POS_VOID
	visible = not gone
	if not gone:
		position = origin + (Vector2(s.pos) + Vector2(0.5, 0.5)) * cell_size
	queue_redraw()


func set_ghost(forms: Array[StringName]) -> void:
	_ghost = forms.size() > 0
	_ghost_forms = forms
	queue_redraw()


func current_frame() -> StateFrame:
	return _applied


func _draw() -> void:
	if _applied == null or not visible:
		return
	_draw_base()
	if _ghost:
		_draw_ghosts()
	_draw_prop()


## 落地阴影：把道具从地板上「抬」起来，避免在暗色地板上糊成一片。
## 只画一次（残影不重复画），且不随时刻变色 —— 保证剪影恒定。
##
## ★ 阴影方向 = −光照方向（随时刻转动）：影子指向左侧 = 光从右侧来。四刻光角
##   15°/90°/300°/350° 各不相同，于是**不依赖任何颜色**也能看出当前是第几刻。
##   同时它把道具牢牢"钉"在地板上，图底关系比平涂更清楚。
func _draw_base() -> void:
	var pts := PackedVector2Array()
	var rx: float = cell_size * 0.30
	var ry: float = cell_size * 0.11
	var cx: float = -light_dir.x * cell_size * 0.22
	var cy: float = -light_dir.y * cell_size * 0.13 + cell_size * 0.27
	for i in 22:
		var a: float = float(i) / 22.0 * TAU
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	draw_colored_polygon(pts, Color(0.0, 0.0, 0.0, 0.38))


func _draw_ghosts() -> void:
	for f in _ghost_forms:
		if f == _applied.form:
			continue
		var save := modulate
		modulate = Color(save.r, save.g, save.b, 0.28)
		_draw_form(f, false)
		modulate = save


## 子类覆写：按剪影绘制当前形态
func _draw_prop() -> void:
	if _applied == null:
		return
	_draw_form(_applied.form, true)


func _draw_form(form: StringName, _is_current: bool) -> void:
	# 基类兜底：一个可辨认的占位剪影
	draw_rect(Rect2(-30, -30, 60, 60), Color("#8A8F98"))
	draw_rect(Rect2(-30, -30, 60, 60), Color("#2B2F36"), false, 3.0)
