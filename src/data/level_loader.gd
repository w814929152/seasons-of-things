class_name LevelLoader
extends RefCounted
##
## 关卡加载器：优先加载 Godot 原生 Resource（levels/level_01_data.tres，类型安全），
## 加载失败时回退到代码化真值表 Level01Def.build()，保证永远有数据可用。
##

const LEVEL_01_RES := "res://levels/level_01_data.tres"


static func load_level_01() -> LevelData:
	if ResourceLoader.exists(LEVEL_01_RES):
		var res := ResourceLoader.load(LEVEL_01_RES, "LevelData") as LevelData
		if res != null and res.entities.size() > 0 and res.timepoints.size() > 0:
			return res
		push_warning("LevelLoader: %s 损坏，回退到代码化真值表。" % LEVEL_01_RES)
	else:
		push_warning("LevelLoader: 未找到 %s，回退到代码化真值表。" % LEVEL_01_RES)
	return Level01Def.build()
