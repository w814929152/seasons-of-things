class_name TimeEntityData
extends Resource
##
## 一个「实体」的只读历史链（GDD §3.2）。
##
## chain       : 长度 == 时刻数，索引即 t。**只读**，策划写真值表，永不运行时改写。
## anchored    : 锚定物 —— 玩家无法持取/搬运（但可按 writable_fields 被写入特定字段）
## writable_fields: 该实体允许被 Override 覆盖的字段白名单。
##                  自由道具 = pos/form/available/removed
##                  锚定锁具 GATE = open（门的开启状态是覆盖写入，GDD §6）
##                  锚定障碍 VINE = removed（PULLABLE 可被 USE 清除，GDD §6）
##

@export var id: StringName = &""
@export var display_name: String = ""
@export var anchored: bool = false
@export var silhouette: StringName = &""     # 剪影 ID（跨时刻恒定，硬约束 P1）
@export var solid: bool = true               # 是否占据并阻挡所在格
@export var is_lock: bool = false            # 是否为锁具（可被 UNLOCKS:<id> 开启）
@export var is_receptacle: bool = false      # 是否为容器格（可被放置；关卡无关，取代原 plate_pos 硬编码）
@export var writable_fields: PackedStringArray = []
@export var chain: Array[StateFrame] = []


func can_override(field: StringName) -> bool:
	return writable_fields.has(String(field))


func base_frame(t: int) -> StateFrame:
	if t < 0 or t >= chain.size():
		push_error("TimeEntityData.base_frame: t=%d 越界 (chain=%d)" % [t, chain.size()])
		return StateFrame.new()
	return chain[t]


func chain_size() -> int:
	return chain.size()
