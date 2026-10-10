class_name Inventory
extends RefCounted
##
## 背包：容量 2（GDD §5 L2）。手持物冻结，免疫时刻变化。
##

var cap: int = 2
var items: Array[InventoryItem] = []


func is_empty() -> bool:
	return items.is_empty()


func is_full() -> bool:
	return items.size() >= cap


func size() -> int:
	return items.size()


func add(it: InventoryItem) -> bool:
	if is_full():
		return false
	items.append(it)
	return true


func top() -> InventoryItem:
	if items.is_empty():
		return null
	return items[items.size() - 1]


func remove_top() -> InventoryItem:
	if items.is_empty():
		return null
	return items.pop_back()


func has_tag(tag: String) -> bool:
	for it in items:
		if it.has_tag(tag):
			return true
	return false


func all_tags() -> PackedStringArray:
	var out: PackedStringArray = []
	for it in items:
		for t in it.tags:
			out.append(String(t))
	return out


func clone_items() -> Array[InventoryItem]:
	var out: Array[InventoryItem] = []
	for it in items:
		var c := InventoryItem.new()
		c.entity_id = it.entity_id
		c.form = it.form
		c.tags = it.tags.duplicate()
		c.display_name = it.display_name
		c.silhouette = it.silhouette
		c.picked_at_t = it.picked_at_t
		out.append(c)
	return out


func labels() -> Array[String]:
	var out: Array[String] = []
	for it in items:
		out.append(it.label())
	return out
