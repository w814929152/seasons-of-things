class_name Grid
extends RefCounted
##
## 离散网格（关卡 01 为 13×8，含边界墙；尺寸由 `LevelData.grid_size` 注入）。MVP 中**地形无时间链**（全时刻相同），
## 以减少真值表爆炸（GDD §6 表格末行）。
##

var size: Vector2i = Vector2i(13, 8)
var walls: Array[Vector2i] = []
var _wall_set: Dictionary = {}


func setup(sz: Vector2i, wall_list: Array) -> void:
	size = sz
	walls.clear()
	_wall_set.clear()
	for c in wall_list:
		var v := c as Vector2i
		walls.append(v)
		_wall_set[v] = true


func is_inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


func is_wall(c: Vector2i) -> bool:
	return _wall_set.has(c)


## 四邻域（无对角）
func neighbors4(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var deltas: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in deltas:
		var n := c + d
		if is_inside(n) and not is_wall(n):
			out.append(n)
	return out


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return manhattan(a, b) == 1
