class_name Override
extends RefCounted
##
## 玩家写入时间线的一条覆盖记录（GDD §3.2）。
##
## t_index : 写入发生在哪个时刻
## field   : &"pos" | &"form" | &"available" | &"removed" | &"open"
## propagate: &"forward"（默认，向未来传播）| &"none"
## seq     : 全局递增序号 —— 撤销顺序 + 「后写覆盖先写」
## parent_seq: forward 派生记录的父记录；-1 表示玩家直接写入
##

const PROP_FORWARD := &"forward"
const PROP_NONE := &"none"

var t_index: int = 0
var entity_id: StringName = &""
var field: StringName = &""
var value: Variant = null
var propagate: StringName = PROP_FORWARD
var seq: int = 0
var parent_seq: int = -1
var label: String = ""


static func create(
	p_t: int,
	p_entity: StringName,
	p_field: StringName,
	p_value: Variant,
	p_seq: int,
	p_propagate: StringName = PROP_FORWARD,
	p_parent: int = -1,
	p_label: String = ""
) -> Override:
	var o := Override.new()
	o.t_index = p_t
	o.entity_id = p_entity
	o.field = p_field
	o.value = p_value
	o.seq = p_seq
	o.propagate = p_propagate
	o.parent_seq = p_parent
	o.label = p_label
	return o


func clone() -> Override:
	var o := Override.new()
	o.t_index = t_index
	o.entity_id = entity_id
	o.field = field
	o.value = value
	o.propagate = propagate
	o.seq = seq
	o.parent_seq = parent_seq
	o.label = label
	return o


func to_dict() -> Dictionary:
	return {
		"t_index": t_index,
		"entity_id": String(entity_id),
		"field": String(field),
		"value": value,
		"propagate": String(propagate),
		"seq": seq,
		"parent_seq": parent_seq,
		"label": label,
	}


func to_text() -> String:
	return "#%d [t%d] %s.%s = %s (%s)%s" % [
		seq, t_index, String(entity_id), String(field), str(value),
		String(propagate), "" if parent_seq < 0 else " <-#%d" % parent_seq
	]
