class_name TimeController
extends RefCounted
##
## 全局时刻控制器 —— **唯一写者**（architecture §3.4）。
##
## 持有：current_t / 时砂 / overrides / 背包 / 玩家坐标。
## 不引用任何 Node2D 与渲染类型 —— 可在 headless 下直接 new 出来断言。
## 渲染层通过信号订阅，绝不反向写入。
##
## 五个动词：观察 / 切换 / 持取 / 放置 / 使用（+ 回溯 = 撤销）
##

signal moment_changed(t: int)
signal hourglass_changed(left: int, cap: int)
signal inventory_changed()
signal override_added(o: Override)
signal deadlock_detected()
signal goal_reached()
signal history_changed(can_undo: bool)
signal message(text: String)
signal player_moved(pos: Vector2i, path: Array)

const POS_VOID := Vector2i(-1, -1)

## 形态锁文案（GDD §3.4：这些标签**只**影响能否持取，绝不影响占位/压感）
const TAKE_BLOCK_REASON := {
	"HOT": "太烫了，现在还拿不起来。",
	"IMMOVABLE": "它与地面锈成了一体，这一刻搬不动。",
	"OCCLUDED": "它被落灰掩埋了，看不见也拿不到。",
	"NO_TAKE": "它重得推不动。",
}

var level: LevelData = null
var current_t: int = 0
var hourglass: int = 0
var hourglass_cap: int = 12
var overrides: Array[Override] = []
var inventory: Inventory = null
var player_pos: Vector2i = Vector2i.ZERO
var won: bool = false

var grid: Grid = null
var _glass := Hourglass.new()
var _seq: int = 0
var _undo_stack: Array[Dictionary] = []
var _initial_snapshot: Dictionary = {}


# ---------------------------------------------------------------- setup ---

func setup(lv: LevelData) -> void:
	assert(lv != null, "TimeController.setup: level 为空")
	level = lv
	grid = Grid.new()
	grid.setup(lv.grid_size, lv.walls)
	current_t = lv.start_t
	hourglass_cap = lv.hourglass_cap
	_glass.setup(lv.hourglass_cap)
	hourglass = _glass.left
	overrides.clear()
	inventory = Inventory.new()
	inventory.cap = lv.backpack_cap
	player_pos = lv.player_start
	_seq = 0
	_undo_stack.clear()
	won = false
	_initial_snapshot = _snapshot_state()


# ------------------------------------------------------------- 历史/撤销 ---

func _snapshot_state() -> Dictionary:
	var ov: Array[Override] = []
	for o in overrides:
		ov.append((o as Override).clone())
	return {
		"current_t": current_t,
		"hourglass": hourglass,
		"player_pos": player_pos,
		"won": won,
		"overrides": ov,
		"inventory": inventory.clone_items(),
		"seq": _seq,
	}


func _restore_state(d: Dictionary) -> void:
	current_t = int(d["current_t"])
	hourglass = int(d["hourglass"])
	_glass.left = hourglass
	player_pos = d["player_pos"]
	won = bool(d["won"])
	overrides = d["overrides"]
	_seq = int(d.get("seq", _seq))
	inventory.items = d["inventory"]


func _push_history() -> void:
	_undo_stack.append(_snapshot_state())


func can_undo() -> bool:
	return not _undo_stack.is_empty()


## 单步撤销（Z）：回滚一步完整操作（含时刻、时砂、Override 及其 forward 派生、背包、坐标）
func undo_step() -> bool:
	if not can_undo():
		message.emit("没有可撤销的操作了。")
		return false
	_restore_state(_undo_stack.pop_back())
	_after_change(true)
	message.emit("已撤销一步（时砂全额返还）。")
	return true


## 重置时刻：清空全部 Override，回到关卡初始时间线；返还全部时砂；免费
func reset() -> void:
	if _undo_stack.is_empty() and overrides.is_empty():
		return
	_push_history()
	_restore_state(_initial_snapshot)
	_after_change(true)
	message.emit("时间线已重置（免费，时砂全额）。")


# ----------------------------------------------------------- 覆盖层写入 ---

## 写入一条 Override，并按 propagate 生成 forward 派生记录。
## 返回本次写入的全部 seq（父记录在前，派生记录在后）。
func add_override(
	field: StringName,
	entity_id: StringName,
	value: Variant,
	t_index: int,
	propagate: StringName = Override.PROP_FORWARD,
	label: String = ""
) -> Array[int]:
	var parent := Override.create(t_index, entity_id, field, value, _next_seq(), propagate, -1, label)
	overrides.append(parent)
	var seqs: Array[int] = [parent.seq]
	override_added.emit(parent)

	if propagate == Override.PROP_FORWARD:
		# ★ 只向未来传播：t > t_index 的时刻各生成一条派生记录
		for t in range(t_index + 1, level.timepoint_count()):
			var child := Override.create(t, entity_id, field, value, _next_seq(),
				Override.PROP_NONE, parent.seq, label + " (传播)")
			overrides.append(child)
			seqs.append(child.seq)
	return seqs


func _next_seq() -> int:
	_seq += 1
	return _seq


# ------------------------------------------------------------- 时刻切换 ---

func can_shift(delta: int) -> bool:
	return _shift_failure(delta) == ""


func _shift_failure(delta: int) -> String:
	if level == null:
		return "关卡未加载。"
	var target := current_t + delta
	if target < 0 or target >= level.timepoint_count():
		return "刻度尺已经到头了。"
	if not level.is_unlocked(target):
		return "那个时刻还锁着。"
	if not _glass.can_spend(absi(delta)):
		return "时砂不够了 —— 按 Z 撤销可全额返还。"
	return ""


func shift(delta: int) -> bool:
	var fail := _shift_failure(delta)
	if fail != "":
		message.emit(fail)
		return false
	_push_history()
	_glass.spend(absi(delta))
	hourglass = _glass.left
	current_t += delta
	assert(hourglass >= 0, "时砂出现负数")
	_after_change(false)
	return true


func goto_t(t: int) -> bool:
	return shift(t - current_t)


# ---------------------------------------------------------------- 动词 ----

## 观察：返回当前时刻的观察文本（残影对比由渲染层处理）
func observe_text() -> String:
	if level == null:
		return ""
	var tp := level.get_timepoint(current_t)
	var head := "[%s %s] " % [tp.roman if tp != null else "?", tp.label if tp != null else ""]
	var lines: Array[String] = []
	for e in level.entities:
		var s := resolve_state(e, current_t)
		if s.removed or s.pos == POS_VOID:
			continue
		lines.append("· %s：%s" % [e.display_name, _entry_text(e.id, s)])
	if inventory != null and not inventory.is_empty():
		lines.append("· 手上：%s" % ", ".join(inventory.labels()))
	return head + "\n" + "\n".join(lines)


## 观察面板单行描述。
## ⚠ 门 / 闸门 / 压力板的"开·关·被压住"是**派生状态**（open / plate_pressed），
##   不在 form 里。若只读 form，会把"已经打开的铁栅门"写成「锁着的铁栅门」——
##   所以这几类必须先判派生状态，再退回 form 文案。
func _entry_text(id: StringName, s: StateFrame) -> String:
	if id == &"GATE":
		return "敞开的铁栅门" if s.open else _form_text(id, s.form)
	if id == &"GRATE":
		return "开启的闸门" if grate_open(current_t) else "放下的闸门，堵着去路"
	if id == &"PLATE":
		return "被压住的压力板" if plate_pressed(current_t) else "空着的压力板"
	return _form_text(id, s.form)


func _form_text(id: StringName, form: StringName) -> String:
	var key := String(id) + "/" + String(form)
	match key:
		"KEY/INGOT": return "一块还发红的金属锭（烫手）"
		"KEY/KEY_NEW": return "崭新的黄铜钥匙"
		"KEY/KEY_RUSTY": return "生锈的钥匙，齿口已经发脆"
		"KEY/RUST_LUMP": return "一坨锈块，什么都开不了"
		"KEY/KEY_BROKEN": return "断成两截的钥匙"
		"WEIGHT/MOLTEN": return "一汪熔融的铜液"
		"WEIGHT/WEIGHT_OK": return "完好的黄铜砝码"
		"WEIGHT/WEIGHT_SEIZED": return "锈死在地上的砝码"
		"WEIGHT/WEIGHT_BURIED": return "被落灰掩埋的砝码"
		"VINE/SPROUT": return "刚冒头的幼苗 —— 纤细，却已爬满整个门洞，过不去"
		"VINE/YOUNG": return "柔弱的幼藤，一把就能拔掉，但它确实堵着路"
		"VINE/THICK": return "茂密的藤墙，堵死了通路"
		"VINE/WITHERED": return "枯死的藤，硬得像铁网"
		"GATE/BARRED", "GATE/BARRED_RUSTY", "GATE/BARRED_ROTTEN": return "锁着的铁栅门"
		"EXIT/NOT_BUILT": return "这里只有一个门框，门还没有建起来"
		"EXIT/NO_HANDLE": return "门扇还没有装把手，推不开"
		"EXIT/INTACT": return "完好的出口门"
		"EXIT/COLLAPSED": return "坍塌封死的出口"
		"STAND/STAND": return "工匠的钥匙台"
		"FORGE/FORGE": return "熄灭的熔炉，壁上刻着一行小字"
	return String(form)


## 持取（空格）
func take(entity_id: StringName) -> bool:
	if level == null: return false
	var e := level.get_entity(entity_id)
	if e == null:
		return false
	var s := resolve_state(e, current_t)
	if s.removed or s.pos == POS_VOID:
		message.emit("那里没有可拿的东西。")
		return false
	if not Grid.is_adjacent(player_pos, s.pos) and player_pos != s.pos:
		message.emit("离得太远了。")
		return false
	if e.anchored:
		message.emit("%s 是钉死在这里的。" % e.display_name)
		return false
	for tag in TAKE_BLOCK_REASON.keys():
		if s.tags.has(tag):
			message.emit(TAKE_BLOCK_REASON[tag])
			return false
	if not s.available:
		message.emit("这一刻拿不了它。")
		return false
	if inventory.is_full():
		message.emit("背包满了（上限 %d）。" % inventory.cap)
		return false

	_push_history()
	inventory.add(InventoryItem.from_frame(e, s, current_t))
	# C2 取离世界：pos = POS_VOID，向未来传播
	add_override(&"pos", e.id, POS_VOID, current_t, Override.PROP_FORWARD, "持取")
	message.emit("拿到 %s —— 它会保持此刻的样子。" % e.display_name)
	_after_change(false)
	return true


## 放置（Q）—— 把背包顶部的物品放到相邻格（压力板 / 空地）
## ★ 关卡 1 语义（与 GDD §4.3 C3 的差异，见 architecture §12 决策 D3）：
##   放置只写 pos，**不冻结 form**。理由：关卡文档 §9.1 / §5.2 明确要求
##   「砝码放上压力板后，T2 形态仍为 WEIGHT_SEIZED（锈死）」——
##   物件放回世界后继续走它自己的时间线，冻结只发生在**背包里**。
func place(target_pos: Vector2i) -> bool:
	if inventory.is_empty():
		message.emit("手上没有东西可放。")
		return false
	if target_pos == player_pos:
		message.emit("就放在脚边吧 —— 需要放到相邻的格子里。")
		return false
	if not Grid.is_adjacent(player_pos, target_pos):
		message.emit("离得太远了。")
		return false
	if not grid.is_inside(target_pos) or grid.is_wall(target_pos):
		message.emit("那里放不下。")
		return false
	if is_blocked(target_pos, current_t):
		message.emit("那里已经有东西了。")
		return false

	var item := inventory.top()
	_push_history()
	inventory.remove_top()
	add_override(&"pos", item.entity_id, target_pos, current_t, Override.PROP_FORWARD, "放置")
	if _is_removed_now(item.entity_id):
		add_override(&"removed", item.entity_id, false, current_t, Override.PROP_FORWARD, "放置")
	message.emit("你把 %s 放下了 —— 它将从此时开始存在。" % item.display_name)
	_after_change(false)
	return true


## 使用（E）：开锁 / 拔藤
func use(entity_id: StringName) -> bool:
	if level == null: return false
	var e := level.get_entity(entity_id)
	if e == null:
		return false
	var s := resolve_state(e, current_t)
	if s.removed or s.pos == POS_VOID:
		message.emit("那里没有可以使用的东西。")
		return false
	if not Grid.is_adjacent(player_pos, s.pos) and player_pos != s.pos:
		message.emit("离得太远了。")
		return false

	# --- 锁具 ---
	if e.is_lock:
		if s.open:
			message.emit("它已经开着了。")
			return false
		if inventory.is_empty():
			message.emit("需要一件能开锁的东西。")
			return false
		var item := inventory.top()
		_push_history()
		inventory.remove_top()
		if item.has_tag("FRAGILE"):
			# 设计好的教学负反馈：锈钥匙一拧就断
			add_override(&"form", item.entity_id, &"KEY_BROKEN", current_t,
				Override.PROP_FORWARD, "钥匙折断")
			add_override(&"pos", item.entity_id, player_pos, current_t,
				Override.PROP_FORWARD, "钥匙残骸落地")
			message.emit("锈死的钥匙断成了两截。它曾经不是这样的。")
		elif item.has_tag("UNLOCKS:" + String(e.id)):
			# 开锁：门开（forward），钥匙留在锁孔里（携带形态）
			add_override(&"open", e.id, true, current_t, Override.PROP_FORWARD, "开锁")
			add_override(&"pos", item.entity_id, s.pos, current_t, Override.PROP_FORWARD, "钥匙留锁孔")
			add_override(&"form", item.entity_id, item.form, current_t, Override.PROP_FORWARD, "携带形态")
			message.emit("%s 开了。" % e.display_name)
		else:
			inventory.add(item)  # 没用上，放回
			_undo_stack.pop_back()
			message.emit("这东西开不了这把锁。")
			return false
		_after_change(false)
		return true

	# --- 可拔除障碍 ---
	if s.tags.has("PULLABLE"):
		_push_history()
		add_override(&"removed", e.id, true, current_t, Override.PROP_FORWARD, "拔除")
		message.emit("你把它连根拔掉了。")
		_after_change(false)
		return true
	if s.tags.has("TOO_THICK"):
		message.emit("藤蔓太粗了，这一刻拔不动。")
		return false

	message.emit("这里没什么可做的。")
	return false


## 移动：逻辑上直接落点，返回路径供渲染层做动画。
## ⚠ 原子式：一次入栈 + 立即把 player_pos 设为目标格。
## 渲染层若要「人到了才结算」，请改用 mark_move_start() + commit_cell()。
func walk_to(target: Vector2i) -> Array[Vector2i]:
	if target == player_pos:
		return []
	var path := find_path(player_pos, target)
	if path.is_empty():
		message.emit("过不去。")
		return []
	_push_history()
	player_pos = target
	_after_change(false)
	return path


## 开始一段「逐格推进」的移动：显式入栈**一条**撤销点。
## 之后每次 commit_cell() 都不再写历史 → 整段连续移动只占一步撤销。
## 渲染层负责保证「同一次连续移动只调用一次」，重复调用会多插撤销点。
func mark_move_start() -> void:
	_push_history()


## 把玩家真正挪到 target（由渲染层在**精灵到达该格**时调用）。
## ⚠ 故意不写历史：撤销点已由 mark_move_start() 统一入栈。
## 若未先调用 mark_move_start()，本次落点将不可撤销。
func commit_cell(target: Vector2i) -> void:
	if target == player_pos:
		return
	player_pos = target
	_after_change(false)


func _is_removed_now(entity_id: StringName) -> bool:
	var e := level.get_entity(entity_id)
	if e == null:
		return false
	return resolve_state(e, current_t).removed


# ------------------------------------------------------------- 求解/派生 ---

func resolve_state(e: TimeEntityData, t: int) -> StateFrame:
	return Resolve.resolve_state(e, t, overrides)


func resolve_now(e: TimeEntityData) -> StateFrame:
	return resolve_state(e, current_t)


## 派生状态：压力板（GDD §6.2 / 关卡文档 §5.2）—— **实时判定，不写入 Override 层**
func plate_pressed(t: int) -> bool:
	if level == null:
		return false
	for e in level.entities:
		var s := resolve_state(e, t)
		if s.removed or s.pos != level.plate_pos:
			continue
		if s.tags.has("PRESSER"):
			return true
	return false


## 派生状态：闸门 open(t) = plate.pressed(t)
func grate_open(t: int) -> bool:
	return plate_pressed(t)


## 特殊语义实体：它们的阻挡由形态/派生决定，先于普通实心物判定。
## （保证「钥匙留在锁孔里」不会把开着的门格又堵上）
const SPECIAL_IDS := ["PLATE", "GATE", "GRATE", "VINE", "EXIT"]

## 某格在某时刻是否阻挡（墙 + 实体占位 + 锁/闸/藤/出口的形态）
func is_blocked(cell: Vector2i, t: int) -> bool:
	if level == null:
		return true
	if not grid.is_inside(cell) or grid.is_wall(cell):
		return true
	# 第一遍：特殊语义实体
	for e in level.entities:
		if not SPECIAL_IDS.has(String(e.id)):
			continue
		var s := resolve_state(e, t)
		if s.removed or s.pos != cell:
			continue
		if e.id == &"PLATE":
			continue                       # 压力板本身可踩
		if e.id == &"GATE":
			return not s.open             # 开了就不挡
		if e.id == &"GRATE":
			return not grate_open(t)      # 派生：open(t) = plate.pressed(t)
		if e.id == &"VINE":
			# 四形态一律阻挡（硬性咽喉）：拔掉才通。
			# T0/T1 额外带 PULLABLE —— 「拔得动」与「过得去」是两件事，别混。
			return s.tags.has("BLOCKING")
		if e.id == &"EXIT":
			return s.tags.has("BLOCKING") # 仅 T2 INTACT 可通行
	# 第二遍：普通实心实体（钥匙很小，可跨过；砝码/台/炉挡路）
	for e in level.entities:
		if SPECIAL_IDS.has(String(e.id)):
			continue
		var s := resolve_state(e, t)
		if s.removed or s.pos != cell:
			continue
		if e.solid:
			return true
	return false


## 显式通关判定（供测试/UI 直接问「此刻站这里算不算通关」）
func evaluate_win() -> bool:
	return PuzzleCondition.check_win(self)


## 死锁谓词（GDD §7.1）—— 本关经设计永不为真
func is_deadlock() -> bool:
	return PuzzleCondition.is_deadlock(self)


## 导出可回滚状态快照（供测试逐字段比对）
func export_state() -> Dictionary:
	return _snapshot_state()


## 两个状态快照的逐字段差异（空数组 = 完全一致）
static func state_diff(a: Dictionary, b: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if int(a.get("current_t", -1)) != int(b.get("current_t", -1)):
		out.append("current_t: %s != %s" % [a.get("current_t"), b.get("current_t")])
	if int(a.get("hourglass", -1)) != int(b.get("hourglass", -1)):
		out.append("hourglass: %s != %s" % [a.get("hourglass"), b.get("hourglass")])
	if Vector2i(a.get("player_pos", Vector2i.ZERO)) != Vector2i(b.get("player_pos", Vector2i.ZERO)):
		out.append("player_pos: %s != %s" % [a.get("player_pos"), b.get("player_pos")])
	if bool(a.get("won", false)) != bool(b.get("won", false)):
		out.append("won: %s != %s" % [a.get("won"), b.get("won")])
	var oa: Array = a.get("overrides", [])
	var ob: Array = b.get("overrides", [])
	if oa.size() != ob.size():
		out.append("overrides.size: %d != %d" % [oa.size(), ob.size()])
	else:
		for i in oa.size():
			var x := oa[i] as Override
			var y := ob[i] as Override
			if x == null or y == null:
				out.append("overrides[%d]: null" % i)
				continue
			if x.to_dict() != y.to_dict():
				out.append("overrides[%d]: %s != %s" % [i, x.to_text(), y.to_text()])
	var ia: Array = a.get("inventory", [])
	var ib: Array = b.get("inventory", [])
	if ia.size() != ib.size():
		out.append("inventory.size: %d != %d" % [ia.size(), ib.size()])
	else:
		for i in ia.size():
			if (ia[i] as InventoryItem).to_dict() != (ib[i] as InventoryItem).to_dict():
				out.append("inventory[%d] differs" % i)
	return out


func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not grid.is_inside(to) or is_blocked(to, current_t):
		return []
	if from == to:
		return [from]
	var prev: Dictionary = {}
	var seen: Dictionary = {from: true}
	var q: Array[Vector2i] = [from]
	var head := 0
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		if cur == to:
			break
		for n in grid.neighbors4(cur):
			if seen.has(n):
				continue
			if is_blocked(n, current_t):
				continue
			seen[n] = true
			prev[n] = cur
			q.append(n)
	if not seen.has(to):
		return []
	var path: Array[Vector2i] = [to]
	var c: Vector2i = to
	while c != from:
		c = prev[c]
		path.append(c)
	path.reverse()
	return path


func snapshot(t: int = -1) -> WorldSnapshot:
	if t < 0:
		t = current_t
	var ws := WorldSnapshot.new()
	ws.t = t
	for e in level.entities:
		ws.entities[String(e.id)] = resolve_state(e, t)
	ws.derived["plate_pressed"] = plate_pressed(t)
	ws.derived["grate_open"] = grate_open(t)
	return ws


## 全部时刻的快照（用于「绝不向过去传播」逐字段比对）
func snapshot_all() -> Array[WorldSnapshot]:
	var out: Array[WorldSnapshot] = []
	for t in level.timepoint_count():
		out.append(snapshot(t))
	return out


# --------------------------------------------------------------- 内部 ----

func _after_change(is_undo: bool) -> void:
	_resolve_player_if_blocked()
	moment_changed.emit(current_t)
	hourglass_changed.emit(hourglass, hourglass_cap)
	inventory_changed.emit()
	history_changed.emit(can_undo())
	if not won and PuzzleCondition.check_win(self):
		won = true
		goal_reached.emit()
	elif PuzzleCondition.is_deadlock(self):
		deadlock_detected.emit()
	if is_undo:
		pass


## GDD §2.4：切换后若玩家脚下格被阻挡，推到最近的可通行格并提示
func _resolve_player_if_blocked() -> void:
	if level == null:
		return
	if not is_blocked(player_pos, current_t):
		return
	var q: Array[Vector2i] = [player_pos]
	var seen: Dictionary = {player_pos: true}
	var head := 0
	var found := player_pos
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		if not is_blocked(cur, current_t):
			found = cur
			break
		for n in grid.neighbors4(cur):
			if not seen.has(n):
				seen[n] = true
				q.append(n)
	if found != player_pos:
		player_pos = found
		message.emit("脚下被挡住了，被挤到了 (%d,%d)。" % [found.x, found.y])


func status_text() -> String:
	var tp := level.get_timepoint(current_t)
	return "时刻 %s %s ｜ 时砂 %d/%d ｜ 背包 %d/%d ｜ 坐标 (%d,%d)" % [
		tp.roman if tp != null else "?", tp.label if tp != null else "",
		hourglass, hourglass_cap, inventory.size(), inventory.cap,
		player_pos.x, player_pos.y
	]
