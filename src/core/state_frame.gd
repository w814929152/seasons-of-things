class_name StateFrame
extends Resource
##
## 某实体在某一个离散时刻的完整状态（GDD §3.1 四元组 + 两个运行时字段）。
##
## 纯数据：不引用任何 Node / Node2D / 渲染类型 —— 保证 headless 下可逐字段断言。
## 继承 Resource 而非 RefCounted，是为了能被 ResourceSaver 写进 .tres（关卡数据）。
##

## 该时刻「不存在于世界」
const POS_VOID := Vector2i(-1, -1)

@export var form: StringName = &""          # 形态 ID：INGOT / KEY_NEW / KEY_RUSTY ...
@export var pos: Vector2i = POS_VOID        # 网格坐标；POS_VOID = 缺席
@export var available: bool = false         # 是否可被玩家持取
@export var tags: PackedStringArray = []    # 交互标签（见 architecture §3.6 标签表）
@export var note: String = ""               # 可选叙事条目
@export var removed: bool = false           # 自某时刻起被清除（藤蔓被拔除）
@export var open: bool = false              # 仅锁具（GATE）使用：true = 已开启


func duplicate_frame() -> StateFrame:
	var f := StateFrame.new()
	f.form = form
	f.pos = pos
	f.available = available
	f.tags = tags.duplicate()
	f.note = note
	f.removed = removed
	f.open = open
	return f


func set_field(field: StringName, value: Variant) -> void:
	match field:
		&"form": form = value
		&"pos": pos = value
		&"available": available = value
		&"tags": tags = value
		&"note": note = value
		&"removed": removed = value
		&"open": open = value
		_:
			push_warning("StateFrame.set_field: unknown field '%s'" % String(field))


func get_field(field: StringName) -> Variant:
	match field:
		&"form": return form
		&"pos": return pos
		&"available": return available
		&"tags": return tags
		&"note": return note
		&"removed": return removed
		&"open": return open
	return null


## 逐字段相等（用于撤销复原与「绝不向过去传播」的断言）
func equals(other: StateFrame) -> bool:
	if other == null:
		return false
	if form != other.form: return false
	if pos != other.pos: return false
	if available != other.available: return false
	if removed != other.removed: return false
	if open != other.open: return false
	if note != other.note: return false
	if tags.size() != other.tags.size(): return false
	for i in tags.size():
		if tags[i] != other.tags[i]: return false
	return true


func to_dict() -> Dictionary:
	return {
		"form": String(form),
		"pos": [pos.x, pos.y],
		"available": available,
		"tags": Array(tags),
		"note": note,
		"removed": removed,
		"open": open,
	}


static func from_dict(d: Dictionary) -> StateFrame:
	var f := StateFrame.new()
	f.form = StringName(String(d.get("form", "")))
	var p: Array = d.get("pos", [-1, -1])
	f.pos = Vector2i(int(p[0]), int(p[1]))
	f.available = bool(d.get("available", false))
	f.tags = PackedStringArray(Array(d.get("tags", [])))
	f.note = String(d.get("note", ""))
	f.removed = bool(d.get("removed", false))
	f.open = bool(d.get("open", false))
	return f


func to_text() -> String:
	return "%s@(%d,%d)%s%s" % [
		String(form), pos.x, pos.y,
		" 可取" if available else " 不可取",
		" removed" if removed else ""
	]
