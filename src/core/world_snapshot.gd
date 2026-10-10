class_name WorldSnapshot
extends RefCounted
##
## 某一时刻的全量世界态（architecture §3.12）：所有实体的 resolve 结果 + 派生状态。
## 用于撤销比对、「绝不向过去传播」断言、以及渲染层的一次性读取。
##

var t: int = 0
var entities: Dictionary = {}    # { String(entity_id) : StateFrame }
var derived: Dictionary = {}     # { "plate_pressed": bool, "grate_open": bool }


func get_frame(entity_id: StringName) -> StateFrame:
	return entities.get(String(entity_id), null) as StateFrame


func to_dict() -> Dictionary:
	var ents: Dictionary = {}
	for k in entities.keys():
		ents[k] = (entities[k] as StateFrame).to_dict()
	return {"t": t, "entities": ents, "derived": derived.duplicate()}


static func from_dict(d: Dictionary) -> WorldSnapshot:
	var ws := WorldSnapshot.new()
	ws.t = int(d.get("t", 0))
	var ents: Dictionary = d.get("entities", {})
	for k in ents.keys():
		ws.entities[k] = StateFrame.from_dict(ents[k])
	ws.derived = Dictionary(d.get("derived", {})).duplicate()
	return ws


## 与另一快照逐字段比对，返回差异描述数组（空 = 完全一致）
func diff(other: WorldSnapshot) -> Array[String]:
	var out: Array[String] = []
	if other == null:
		out.append("other 为空")
		return out
	if t != other.t:
		out.append("t: %d != %d" % [t, other.t])
	for k in entities.keys():
		var a := entities[k] as StateFrame
		var b := other.entities.get(k, null) as StateFrame
		if b == null:
			out.append("%s: 缺失" % k)
			continue
		if not a.equals(b):
			out.append("%s: %s != %s" % [k, a.to_text(), b.to_text()])
	for k in derived.keys():
		if derived.get(k, null) != other.derived.get(k, null):
			out.append("derived.%s: %s != %s" % [
				k, str(derived.get(k, null)), str(other.derived.get(k, null))])
	return out
