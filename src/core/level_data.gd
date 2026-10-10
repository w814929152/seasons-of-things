class_name LevelData
extends Resource
##
## 关卡静态数据（对应 architecture §3.10 LevelResource）。
## 全部为策划真值表的常量；运行时状态（current_t / overrides / 背包 / 时砂）
## 一律由 TimeController 持有，绝不写回本对象。
##

@export var level_id: StringName = &""
@export var display_name: String = ""
@export var timepoints: Array[TimepointDef] = []
@export var start_t: int = 0
@export var unlocked: Array[int] = []
@export var hourglass_cap: int = 12
@export var backpack_cap: int = 2
@export var entities: Array[TimeEntityData] = []
@export var grid_size: Vector2i = Vector2i(13, 8)   # 默认值对齐关卡 01（真实值由 LevelData 注入）
@export var walls: Array[Vector2i] = []
@export var player_start: Vector2i = Vector2i.ZERO
@export var plate_pos: Vector2i = Vector2i(9, 3)   # 压力板坐标（派生状态判定用）
@export var win_t: int = 0
@export var win_pos: Vector2i = Vector2i.ZERO
@export var requirements: Array[Dictionary] = []   # [{tag:"UNLOCKS:GATE", target:"GATE"}]
@export var hints: Array[Dictionary] = []          # 三级提示文案


func timepoint_count() -> int:
	return timepoints.size()


func is_unlocked(t: int) -> bool:
	return unlocked.has(t)


func get_entity(id: StringName) -> TimeEntityData:
	for e in entities:
		if e.id == id:
			return e
	return null


func get_timepoint(t: int) -> TimepointDef:
	if t < 0 or t >= timepoints.size():
		return null
	return timepoints[t]


## 本关所有「容器格」坐标（放置兜底用）。
## 容器性写在实体上（is_receptacle），不写在关卡上 —— 后续加箱子 / 插槽 / 祭坛
## 只需在真值表里标 is_receptacle，无需回头改 level_manager._do_place()。
## 注意：容器格**不要求可通行**，不要用 is_blocked() 去筛它。
func receptacle_positions() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for e in entities:
		if e.is_receptacle and not e.chain.is_empty():
			out.append(e.chain[0].pos)      # 容器是锚定物，位置全时刻一致
	return out


func entity_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for e in entities:
		out.append(e.id)
	return out
