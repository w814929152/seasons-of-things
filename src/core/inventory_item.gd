class_name InventoryItem
extends RefCounted
##
## 背包内的物品 —— **时间之外的存储**（GDD §4.3 / §5 L2）。
## 拾取瞬间冻结 form 与 tags：切时刻时它**不变**，世界上的那个东西才变。
## 背包**不参与** resolve_state —— 这是「手持物免疫时刻变化」的实现方式。
##

var entity_id: StringName = &""
var form: StringName = &""
var tags: PackedStringArray = []
var display_name: String = ""
var silhouette: StringName = &""
var picked_at_t: int = -1


static func from_frame(e: TimeEntityData, s: StateFrame, at_t: int) -> InventoryItem:
	var it := InventoryItem.new()
	it.entity_id = e.id
	it.form = s.form
	it.tags = s.tags.duplicate()
	it.display_name = e.display_name
	it.silhouette = e.silhouette
	it.picked_at_t = at_t
	return it


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func label() -> String:
	return "%s·%s" % [display_name, String(form)]


func to_dict() -> Dictionary:
	return {
		"entity_id": String(entity_id),
		"form": String(form),
		"tags": Array(tags),
		"display_name": display_name,
		"silhouette": String(silhouette),
		"picked_at_t": picked_at_t,
	}
