class_name LevelManager
extends Node2D
##
## 关卡管理器（architecture §3.11）：把 LevelData 变成可玩的场景。
##
## 职责：建世界 / 转发输入到 TimeController 的 5 个动词 / 把 resolve 结果
## 派发给 TimeEntity 绘制 / 播放 0.35 s 过渡。**不持有游戏真相** —— 真相在
## TimeController（src/core，零渲染依赖）。
##

const CELL := 96.0
const ORIGIN := Vector2(0.0, 140.0)
const TRANSITION := 0.35       # GDD §2.3 冷却
const WALK_SPEED := 9.0        # 格/秒
const STEP_REPEAT := 0.13      # 长按方向键的连续步进间隔（≈ 走一格 0.111 s，略大以免抖动）
## 「没有格子」哨兵。(-1,-1) 在 13×8 网格外，永远不会是合法格。
const NO_CELL := Vector2i(-1, -1)
const COL_PATH := Color("#F0CE78")      # 可达路径：黄铜
const COL_PATH_BAD := Color("#8A5A52")  # 不可达：暗红（不闪不跳，只是"这条路走不通"）

const PROP_SCRIPTS := {
	&"KEY": preload("res://src/entities/props/key.gd"),
	&"WEIGHT": preload("res://src/entities/props/weight.gd"),
	&"VINE": preload("res://src/entities/props/vine.gd"),
	&"GATE": preload("res://src/entities/props/gate.gd"),
	&"GRATE": preload("res://src/entities/props/grate.gd"),
	&"PLATE": preload("res://src/entities/props/plate.gd"),
	&"EXIT": preload("res://src/entities/props/exit.gd"),
	&"STAND": preload("res://src/entities/props/stand.gd"),
	&"FORGE": preload("res://src/entities/props/forge.gd"),
}

signal refreshed()
signal level_message(text: String)
signal level_goal()

var tc: TimeController = null
var level: LevelData = null

var _env: EnvironmentLayer = null
var _entities_node: Node2D = null
var _goal: Node2D = null
var _preview: Node2D = null
var _cursor: Node2D = null
var _player: Node2D = null
var _nodes: Dictionary = {}
var _transition: float = 0.0
## 上一次"真正切换到的时刻"。用来把切换冷却限定在**时刻变化**上：
## tc.moment_changed 在每次 _after_change（含持取/放置/使用/走路）都会发，
## 若不加区分，任何一个动作都会让"切换时刻"被静默锁住 0.35 s。
var _last_moment: int = -999
var _facing := Vector2i(0, -1)
## ★ 逐格推进的剩余路线：每项 = 精灵将要**到达**的格子，含当前正在前往的那一格。
##   逻辑坐标 tc.player_pos 只在这一格真正抵达时才前进 —— 于是「人未到不会先结算」，
##   而精灵永远沿着一串**相邻格**前进，不可能斜穿墙角（修掉中途点击错位）。
var _route: Array[Vector2i] = []
## 长按方向键：当前方向 + 已保持时长（换方向会立刻响应并重置计时）
var _hold_dir := Vector2i.ZERO
var _hold_t := 0.0
## 鼠标按住 / 拖拽：按住时拖到别格会实时改目的地（RTS 式持续走）
var _mouse_hold := false
var _hover_cell := NO_CELL
var _hint_level: int = 0
var _ghost: bool = false
var _ghost_held: bool = false


# ------------------------------------------------------------------ 构建 ---

func start_level() -> void:
	level = LevelLoader.load_level_01()
	tc = TimeController.new()
	tc.setup(level)
	_last_moment = tc.current_t      # 起始时刻即"当前时刻"，不算一次切换

	tc.moment_changed.connect(func(t: int) -> void: _on_moment_changed(t))
	tc.message.connect(func(text: String) -> void: level_message.emit(text))
	tc.goal_reached.connect(func() -> void:
		level_message.emit("🏁 通关 —— 你在『现在』走出了前厅。")
		level_goal.emit())
	tc.deadlock_detected.connect(func() -> void:
		level_message.emit("这条时间线似乎走不通了 —— 按 Z 可以无损回溯。"))
	tc.inventory_changed.connect(func() -> void: refresh_all())
	tc.override_added.connect(func(_o: Override) -> void: refresh_all())

	_env = EnvironmentLayer.new()
	_env.name = "Environment"
	_env.setup(tc.grid, CELL, ORIGIN)
	add_child(_env)

	# 路径预览（"地面足迹"）：地板之上、道具之下 —— 它是地面指示，不该盖住钥匙/砝码。
	_preview = Node2D.new()
	_preview.name = "PathPreview"
	_preview.draw.connect(_draw_path_trail)
	add_child(_preview)
	_redraw_preview()

	_entities_node = Node2D.new()
	_entities_node.name = "Entities"
	add_child(_entities_node)

	# 悬停光标（可达环 / 不可达叉角）：必须画在**道具之上**才看得见 ——
	# ★ 实测踩过的坑：把不可达的暗红叉放在 PathPreview 层时，它会被出口门那块
	#   占满整格的贴图**完全盖住**，等于"悬停到门上什么反馈都没有"。
	#   光标是"指针"语义，天然该浮在最上面；足迹才是地面层。
	_cursor = Node2D.new()
	_cursor.name = "HoverCursor"
	_cursor.draw.connect(_draw_hover_cursor)
	add_child(_cursor)
	_cursor.queue_redraw()

	# 目标格标记：必须画在**道具之上**（出口门会把它整个盖住），所以单独一层，
	# 排在 Entities 之后、Player 之前。
	_goal = Node2D.new()
	_goal.name = "GoalMarker"
	_goal.position = _cell_center(level.win_pos)
	_goal.draw.connect(_draw_goal_marker)
	add_child(_goal)
	_goal.queue_redraw()

	for e in level.entities:
		var scr: GDScript = PROP_SCRIPTS.get(e.id, preload("res://src/entities/time_entity.gd"))
		var node := scr.new() as TimeEntity
		node.setup(e, CELL, ORIGIN)
		_entities_node.add_child(node)
		_nodes[String(e.id)] = node

	_player = Node2D.new()
	_player.name = "Player"
	_player.position = _cell_center(tc.player_pos)
	_player.draw.connect(_draw_player)
	add_child(_player)
	# ⚠ 空 Node2D 不会自行触发重绘：不调用 queue_redraw()，draw 信号永远不会发出，
	#   玩家角色就从头到尾不可见（实测截图确认 (3,5) 起点格是空的）。
	_player.queue_redraw()

	refresh_all()


func _cell_center(c: Vector2i) -> Vector2:
	return ORIGIN + (Vector2(c) + Vector2(0.5, 0.5)) * CELL


func refresh_all() -> void:
	if tc == null or level == null:
		return
	var t := tc.current_t
	_env.set_timepoint(level.get_timepoint(t))
	# ★ 时刻调色（色温 × 亮度）与光照方向由环境层统一算出，再**下发给每个道具**：
	#   这样"环境变暗/偏色"时道具跟着同一束光变，而不会出现"只有地板变色、
	#   道具像贴纸一样亮着"的割裂感。乘法调色不会压低对比度（见 EnvironmentLayer）。
	var light: Color = _env.light_color()
	var ldir: Vector2 = _env.light_dir()
	var pressed := tc.plate_pressed(t)
	var grate_open := tc.grate_open(t)
	for e in level.entities:
		var node: TimeEntity = _nodes.get(String(e.id), null)
		if node == null:
			continue
		var s := tc.resolve_state(e, t)
		node.apply_resolved(s, e.id == &"PLATE" and pressed or e.id == &"GRATE" and grate_open)
		node.modulate = light
		node.light_dir = ldir
		if _ghost:
			var forms: Array[StringName] = []
			for tt in level.timepoint_count():
				var fs := tc.resolve_state(e, tt)
				if fs.removed or fs.pos == StateFrame.POS_VOID:
					continue
				if not forms.has(fs.form):
					forms.append(fs.form)
			node.set_ghost(forms)
		else:
			node.set_ghost([])
	_sync_player_transform()
	_player.modulate = light
	_goal.modulate = light
	_goal.queue_redraw()
	# 面向高亮框 / 朝向箭头依赖 _facing 与格子占用状态，状态一变就重绘
	_player.queue_redraw()
	# 路径预览也要刷：时刻/状态一变，可达性就变了
	_redraw_preview()
	refreshed.emit()


## 把精灵吸附到逻辑坐标的格心。
## ⚠ 只在**没有在途移动**时吸附：移动中逻辑坐标天然滞后于精灵，
## 强行吸附会让画面每帧回弹（旧实现里 refresh_all 无条件吸附，逐格推进后就会抖）。
func _sync_player_transform() -> void:
	if _player == null or tc == null:
		return
	if _route.is_empty():
		_player.position = _cell_center(tc.player_pos)


## 足迹层 + 光标层一起重绘。两层的可见性条件不同（光标只在"静止 + 有悬停格"时出现），
## 任何一处状态变了都统一走这个入口，避免漏刷出"光标还停在上一次的格上"。
func _redraw_preview() -> void:
	if _preview != null:
		_preview.queue_redraw()
	if _cursor != null:
		_cursor.queue_redraw()


## 时刻变化回调：**只有真的换了一个时刻**才进入 0.35 s 切换冷却。
## （tc.moment_changed 每次状态变化都会发；不设这道闸，持取/使用/走路都会误锁切换。）
func _on_moment_changed(t: int) -> void:
	if t != _last_moment:
		_last_moment = t
		_transition = TRANSITION
	refresh_all()


# ------------------------------------------------------------------ 输入 ---

## ★ 键盘**移动**刻意不在这里处理：方向键要支持长按连续步进，而 _input 只给
##   按下/抬起两个瞬间。真正的步进在 _process → _poll_keyboard() 里轮询。
##   这里只处理"一次性动词"（切时刻/持取/放置/使用/观察/撤销/提示/重置）。
func _input(event: InputEvent) -> void:
	if tc == null or event is InputEventMouseButton or event is InputEventMouseMotion:
		return
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("shift_prev"):
		_try_shift(-1)
	elif event.is_action_pressed("shift_next"):
		_try_shift(1)
	elif event.is_action_pressed("take"):
		_do_take()
	elif event.is_action_pressed("place"):
		_do_place()
	elif event.is_action_pressed("use"):
		_do_use()
	elif event.is_action_pressed("observe"):
		_do_observe()
	elif event.is_action_pressed("undo"):
		_cancel_move()
		tc.undo_step(); refresh_all()
	elif event.is_action_pressed("hint"):
		_do_hint()
	elif event.is_action_pressed("reset"):
		_cancel_move()
		tc.reset(); refresh_all()


## 鼠标：左键按下 = 出发；按住拖动 = 实时改目的地（RTS 式"长按持续走"）；
## 移动指针（不按）= 更新路径预览。
func _unhandled_input(event: InputEvent) -> void:
	if tc == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var cell := _pos_to_cell(event.position)
			_mouse_hold = true
			_hover_cell = cell
			if cell != NO_CELL:
				move_to(cell)
			_redraw_preview()
		else:
			_mouse_hold = false
		return
	if event is InputEventMouseMotion:
		var c := _pos_to_cell(event.position)
		if c == _hover_cell:
			return
		_hover_cell = c
		# 按住拖动：指针进到新格就改目的地（静默，避免拖过一格刷一条"过不去"）
		if _mouse_hold and c != NO_CELL:
			move_to(c, true)
		_redraw_preview()


func _pos_to_cell(p: Vector2) -> Vector2i:
	var local := p - ORIGIN
	var c := Vector2i(int(floor(local.x / CELL)), int(floor(local.y / CELL)))
	if tc == null or not tc.grid.is_inside(c):
		return NO_CELL
	return c


func _try_shift(delta: int) -> void:
	if _transition > 0.0:
		return
	_cancel_move()      # ★ 切时刻会改可通行性：先把精灵收回逻辑格，避免悬在半路
	tc.shift(delta)


## 供外部（HUD/测试）发起移动；返回是否成功规划出一条路。
## 语义：**逐格推进** —— 精灵每真正走到一格，逻辑坐标才跟着前进。
## silent = true 时不发"过不去"提示（长按拖动会高频调用）。
func move_to(cell: Vector2i, silent: bool = false) -> bool:
	if tc == null or not tc.grid.is_inside(cell):
		return false
	if cell == tc.player_pos and _route.is_empty():
		return false
	# 起点：默认用逻辑坐标；已在移动途中则看精灵是否已越过半格 ——
	# 越过 → 从"正在前往的那一格"续算（直行/拐弯都不白跑）；未越过 → 退回本格格心。
	var from := tc.player_pos
	if not _route.is_empty():
		var step: Vector2i = _route[0]
		if step != from and (_player.position - _cell_center(from)).length() > CELL * 0.5:
			from = step
	var path := tc.find_path(from, cell)
	if path.is_empty():
		if not silent:
			level_message.emit("过不去。")
		return false
	# ★ 整段连续移动只占**一条**撤销记录：只在"从静止出发"时入栈。
	if _route.is_empty():
		tc.mark_move_start()
	_route.clear()
	for c in path:
		_route.append(c)
	# 精灵恰好就在 from 的格心 → 该格无需作为航点
	if _player.position.distance_to(_cell_center(from)) < 0.5:
		_route.remove_at(0)
	_redraw_preview()
	return true


## 原子瞬移（供测试/调试用）：一次入栈、立即落点、精灵吸附、清空移动状态。
## 等价于旧 `_walk_to()` 的"走到即立即改坐标"语义 —— 旧测试靠它保持轻量。
func _teleport_to(cell: Vector2i) -> bool:
	_cancel_move()
	if cell == tc.player_pos:
		refresh_all()
		return true
	var path := tc.walk_to(cell)
	if path.is_empty():
		return false       # tc.walk_to 已 emit "过不去。"
	if path.size() >= 2:
		_facing = path[path.size() - 1] - path[path.size() - 2]
	refresh_all()
	return true


## 取消在途移动，并把精灵收回 tc.player_pos 的格心。
## ⚠ 不能用 _player.position = _cell_center(tc.player_pos) 之外的做法：
##   _resolve_player_if_blocked() 在切时刻时可能把玩家挤到别的格，必须重新对齐。
func _cancel_move() -> void:
	_route.clear()
	if _player != null and tc != null:
		_player.position = _cell_center(tc.player_pos)
		_player.queue_redraw()
	_redraw_preview()


# ------------------------------------------------------------------ 动词 ---

func _interactive_at(cell: Vector2i) -> TimeEntityData:
	for e in level.entities:
		var s := tc.resolve_state(e, tc.current_t)
		if s.removed or s.pos != cell:
			continue
		return e
	return null


func _facing_cell() -> Vector2i:
	return tc.player_pos + _facing


## 持取：优先面向格，其次任意相邻可取物
func _do_take() -> void:
	_cancel_move()      # ★ 人未到不结算：先收回逻辑格再判定相邻
	var e := _interactive_at(_facing_cell())
	if e == null or e.anchored:
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var cand := _interactive_at(tc.player_pos + d)
			if cand != null and not cand.anchored:
				e = cand
				_facing = d
				break
	if e == null:
		level_message.emit("面前没有可拿的东西。")
		return
	tc.take(e.id)
	refresh_all()


## 放置（GDD §6.2.2 优先级）：① 容器格 → ② 面向格 → ③ 四邻空地兜底
##
## 顺序是**硬要求**：容器格（本关为压力板）承载解谜意图，必须先于面向格尝试。
## 玩家从南面踩上压力板再退回时朝向是北 → 面向格是空地 (9,1)，若先试面向格，
## 砝码就会落在 (9,1)，plate_pressed 永远为 false，闸门不开，关卡不可解。
##
## ⚠️ 不要在外部用 is_blocked() 预筛容器格：① 那会把可放置的压力板自己筛掉
## （压力板本身不阻挡）；② 容器格若已被占用，tc.place() 内部校验会返回 false，
## 自然回退到下一级候选 —— 这正是期望行为，无需在调用方重复判定。
func _do_place() -> void:
	_cancel_move()      # ★ 人未到不结算：先收回逻辑格再判定相邻
	# ★ 空手时直接返回：否则下面的三级候选会各失败一次，`tc.place()` 逐次
	#   emit 出 5 条一模一样的「手上没有东西可放。」，把只留 5 行的提示条整个冲掉。
	if tc.inventory.is_empty():
		level_message.emit("手上没有东西可放。")
		return
	# ① 容器格优先（is_receptacle 且未被占用；非相邻者由 tc.place() 自行拒绝）
	if tc.level != null:
		for p in tc.level.receptacle_positions():
			if tc.place(p):
				_facing = p - tc.player_pos
				refresh_all()
				return
	# ② 面向格
	if tc.place(_facing_cell()):
		refresh_all()
		return
	# ③ 四邻兜底
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var c: Vector2i = tc.player_pos + d
		if c == _facing_cell():
			continue
		if tc.place(c):
			_facing = c - tc.player_pos
			refresh_all()
			return
	# ④ 全部失败：手上确实拿着东西却无处可放，补一句（「离太远 / 已占用」tc.place 已各自提示过）
	refresh_all()
	level_message.emit("周围没有能放下它的地方。")


## 使用：开锁 / 拔藤
func _do_use() -> void:
	_cancel_move()      # ★ 人未到不结算：先收回逻辑格再判定相邻
	var e := _interactive_at(_facing_cell())
	if e == null:
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var cand := _interactive_at(tc.player_pos + d)
			if cand != null and (cand.is_lock or cand.anchored):
				e = cand
				_facing = d
				break
	if e == null:
		level_message.emit("面前没有可以使用的东西。")
		return
	tc.use(e.id)
	refresh_all()


## 观察：长按 Tab 开残影叠加（不可交互，GDD §5 L7）
func _do_observe() -> void:
	_ghost = not _ghost
	if _ghost:
		level_message.emit(tc.observe_text())
	else:
		level_message.emit("残影已收起。")
	refresh_all()


func _do_hint() -> void:
	if level.hints.is_empty():
		return
	_hint_level = mini(_hint_level + 1, level.hints.size())
	var d: Dictionary = level.hints[_hint_level - 1]
	level_message.emit("[提示 L%d] %s" % [int(d["level"]), String(d["text"])])


# ------------------------------------------------------------------ 帧 ----

func _process(delta: float) -> void:
	if _transition > 0.0:
		_transition = maxf(0.0, _transition - delta)
	_poll_keyboard(delta)
	_advance(delta)


## 方向键长按连续步进：**按下即走一格**，之后每 STEP_REPEAT 再走一格。
## 换方向立刻响应并重置计时（否则从"上"换到"右"要愣 0.13 s，手感发滞）。
func _poll_keyboard(delta: float) -> void:
	if tc == null or tc.won:
		_reset_hold()
		return
	var dir := Vector2i.ZERO
	if Input.is_action_pressed("move_up"):
		dir = Vector2i(0, -1)
	elif Input.is_action_pressed("move_down"):
		dir = Vector2i(0, 1)
	elif Input.is_action_pressed("move_left"):
		dir = Vector2i(-1, 0)
	elif Input.is_action_pressed("move_right"):
		dir = Vector2i(1, 0)
	if dir == Vector2i.ZERO:
		_reset_hold()
		return
	if dir != _hold_dir:
		_hold_dir = dir
		_hold_t = 0.0
		_step_dir(dir)
		return
	_hold_t += delta
	if _hold_t >= STEP_REPEAT:
		_hold_t -= STEP_REPEAT
		_step_dir(dir)


func _reset_hold() -> void:
	_hold_dir = Vector2i.ZERO
	_hold_t = 0.0


## 沿 dir 再走一格（键盘长按/连按用）。
## ⚠ 刻意**不走 move_to**：move_to 会按"是否越过半格"重算起点，
##   而键盘重复触发时精灵往往才走了 15% —— 那会被判成"退回本格格心"，
##   把刚走出去的进度原地抹掉（表现为按着方向键却一顿一顿）。
##   这里只在**路线末端续一格**，进度永不丢失。
func _step_dir(dir: Vector2i) -> void:
	var frontier: Vector2i = _route[_route.size() - 1] if not _route.is_empty() else tc.player_pos
	extend_move(dir, frontier)


## 从 from_cell 朝 dir 延长一格。_route 为空时退化为一次普通 move_to（含入栈）。
func extend_move(dir: Vector2i, from_cell: Vector2i) -> bool:
	var nxt := from_cell + dir
	if tc == null or not tc.grid.is_inside(nxt) or tc.is_blocked(nxt, tc.current_t):
		return false
	if _route.is_empty():
		return move_to(nxt, true)
	_route.append(nxt)
	_redraw_preview()
	return true


## 逐格推进：精灵朝 _route[0] 的格心走，**真正抵达那一刻**才提交逻辑坐标。
## 于是：① 精灵永远沿相邻格前进，不会斜穿墙角；② 通关/相邻判定都发生在"人到之后"。
func _advance(delta: float) -> void:
	if _player == null or _route.is_empty():
		return
	var wp := _cell_center(_route[0])
	var d := wp - _player.position
	var step := WALK_SPEED * CELL * delta
	if d.length() > step:
		_player.position += d.normalized() * step
		return
	_player.position = wp
	var cell: Vector2i = _route[0]
	_route.remove_at(0)
	var prev := tc.player_pos
	tc.commit_cell(cell)              # ★ 逻辑落点（cell == player_pos 时内部直接返回）
	if cell != prev:
		_facing = cell - prev         # U1：每走一格更新朝向
	_player.queue_redraw()            # 面向格变了，四角标要跟着换
	_redraw_preview()                 # 剩余路线少了一格


## 路径足迹（地板之上、道具之下）：把"我接下来会怎么走"画成一串渐亮渐大的黄铜圆点 +
## 一条细连线。移动中画**真实剩余路线**（_route），静止时按光标悬停格用 find_path 现场算。
func _draw_path_trail() -> void:
	var cells := preview_path()
	if cells.is_empty():
		return
	var pts := PackedVector2Array()
	for c in cells:
		pts.append(_cell_center(c))
	if pts.size() >= 2:
		_preview.draw_polyline(pts, Color(COL_PATH.r, COL_PATH.g, COL_PATH.b, 0.45), 7.0, true)
	var n := cells.size()
	for i in n:
		# 越接近终点越亮越大：给出"这条路往哪去"的方向感
		var k := float(i + 1) / float(n)
		_preview.draw_circle(_cell_center(cells[i]), 7.0 + 5.0 * k,
			Color(COL_PATH.r, COL_PATH.g, COL_PATH.b, 0.25 + 0.55 * k))


## 悬停光标（道具**之上**，与目标格标记同层）：
##   可达 → 黄铜圆环，明确"松手就去这里"；
##   不可达 → 暗红叉角，明确"这里过不去"（而不是"点了没反应"）。
## 只在静止且指针停在格上时出现；移动中不画（此时足迹本身就是反馈）。
func _draw_hover_cursor() -> void:
	if _cursor == null or tc == null or not _route.is_empty() or _hover_cell == NO_CELL:
		return
	var off := _cell_center(_hover_cell)
	if preview_reachable():
		_cursor.draw_arc(off, 40.0, 0.0, TAU, 28, Color(COL_PATH.r, COL_PATH.g, COL_PATH.b, 0.6), 3.0, true)
	else:
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				_cursor.draw_line(off + Vector2(sx * 26.0, sy * 26.0),
					off + Vector2(-sx * 26.0, -sy * 26.0), COL_PATH_BAD, 3.5)


## 当前要预览的格子序列（供 HUD / 测试查询，也是 _draw_path_preview 的唯一数据源）。
## 移动中 → 真实剩余路线；静止且光标在格上 → 现场 find_path；否则空数组。
func preview_path() -> Array[Vector2i]:
	if tc == null:
		return []
	if not _route.is_empty():
		return _route.duplicate()
	if _hover_cell == NO_CELL:
		return []
	return tc.find_path(tc.player_pos, _hover_cell)


## 悬停格是否可达（静止时才有意义；移动中恒为 true —— 在途路线必然可达）。
func preview_reachable() -> bool:
	if tc == null:
		return false
	if not _route.is_empty():
		return true
	if _hover_cell == NO_CELL:
		return false
	return not tc.find_path(tc.player_pos, _hover_cell).is_empty()


## 正在移动中？（HUD 与测试用；也用于判定"人是否已到位"）
func is_moving() -> bool:
	return not _route.is_empty()


## 玩家：画面上唯一的「自己」。可读性要求 —— 在任何时刻色调下都能一眼找到它。
## 层次：暖色柔光晕 → 接地影 → 高对比本体（亮米色 + 近黑粗描边）→ 黄铜轴心。
## 亮米色 vs 冷色地板是全场最强的一处图底对比，保证玩家位置永远不丢。
func _draw_player() -> void:
	_player.draw_circle(Vector2.ZERO, 36.0, Color("#E8C56A", 0.05))
	_player.draw_circle(Vector2.ZERO, 27.0, Color("#E8C56A", 0.09))
	_player.draw_circle(Vector2(2.0, 4.0), 21.0, Color(0.0, 0.0, 0.0, 0.35))
	_player.draw_circle(Vector2.ZERO, 19.0, Color("#F2E9D6"))
	_player.draw_circle(Vector2.ZERO, 19.0, Color("#12161C"), false, 4.0)
	_player.draw_circle(Vector2.ZERO, 9.0, Color("#C8863C"))
	_player.draw_circle(Vector2.ZERO, 9.0, Color("#7A5A22"), false, 2.0)
	_draw_facing_arrow()
	_draw_target_glow()


## 朝向箭头（实心三角 + 深色描边）：比一条线更明确地指出「我正对着哪一格」
func _draw_facing_arrow() -> void:
	var d: Vector2 = Vector2(_facing)
	if d == Vector2.ZERO:
		return
	var tip: Vector2 = d * 30.0
	var side: Vector2 = Vector2(-d.y, d.x)
	var pts := PackedVector2Array([tip, side * 8.0 - d * 8.0, -side * 8.0 - d * 8.0])
	_player.draw_colored_polygon(pts, Color("#F2E9D6"))
	var closed := PackedVector2Array(pts)
	closed.append(pts[0])
	_player.draw_polyline(closed, Color("#12161C"), 2.5, true)


## 面向格上有可交互物时，那一格亮起**黄铜四角折线标** —— 回答「我现在能操作什么」。
## （v1 用的是两圈粗白框，读起来像选中框、噪声大；四角标更干净且指向更明确。）
func _draw_target_glow() -> void:
	var t := _interactive_at(_facing_cell())
	if t == null:
		return
	var off: Vector2 = _cell_center(_facing_cell()) - _player.position
	var half := 44.0
	var seg := 17.0
	var col := Color("#F0CE78")
	_player.draw_rect(Rect2(off - Vector2(half, half), Vector2(half * 2.0, half * 2.0)),
		Color(0.94, 0.81, 0.47, 0.10))
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner: Vector2 = off + Vector2(sx * half, sy * half)
			_player.draw_line(corner, corner + Vector2(-sx * seg, 0.0), col, 3.0)
			_player.draw_line(corner, corner + Vector2(0.0, -sy * seg), col, 3.0)


## 目标格标记：黄铜四角折线 + 极淡底色。
## ★ 画在 GoalMarker 层（Entities 之上）—— 出口门会占满整格，画在道具下层就被
##   完全盖住了（v2 第一版踩过这个坑：标记"写了但看不见"）。
## 它回答玩家最基础的一个问题：「我该往哪走？」
func _draw_goal_marker() -> void:
	var half := 45.0
	var seg := 18.0
	var col := Color("#E8C56A")
	_goal.draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0),
		Color(col.r, col.g, col.b, 0.10))
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner: Vector2 = Vector2(sx * half, sy * half)
			_goal.draw_line(corner, corner + Vector2(-sx * seg, 0.0), col, 3.5)
			_goal.draw_line(corner, corner + Vector2(0.0, -sy * seg), col, 3.5)


# ------------------------------------------------------- 供 UI / 测试用 ----

func status_text() -> String:
	return tc.status_text()


func target_label() -> String:
	var e := _interactive_at(_facing_cell())
	if e == null:
		return "—"
	var s := tc.resolve_state(e, tc.current_t)
	return "%s · %s" % [e.display_name, String(s.form)]
