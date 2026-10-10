extends SceneTree
##
## 关卡数据 Resource 生成器（离线工具，不参与游戏运行）。
##
## 用法：
##   godot_console --headless --path "D:/New test" --script res://tools/gen_level_res.gd
##
## 把 Level01Def（代码化真值表）序列化为 levels/level_01_data.tres。
## 用 .tres 而非 JSON 的原因：Godot 原生 Resource 有静态类型（Array[StateFrame] 等），
## 策划在 inspector 里改数值时引擎会做类型校验，比 JSON 更安全。
##

func _initialize() -> void:
	var lv := Level01Def.build()
	var path := "res://levels/level_01_data.tres"
	var err := ResourceSaver.save(lv, path)
	if err != OK:
		print("[gen_level_res] FAILED err=", err)
		quit(1)
		return

	var back := ResourceLoader.load(path, "LevelData") as LevelData
	if back == null:
		print("[gen_level_res] RELOAD FAILED")
		quit(1)
		return

	print("[gen_level_res] OK -> ", path)
	print("  level_id      = ", String(back.level_id))
	print("  timepoints    = ", back.timepoints.size())
	print("  entities      = ", back.entities.size())
	print("  start_t       = ", back.start_t)
	print("  hourglass_cap = ", back.hourglass_cap)
	print("  walls         = ", back.walls.size())
	print("  win           = t", back.win_t, " @ (", back.win_pos.x, ",", back.win_pos.y, ")")
	for e in back.entities:
		var forms: Array[String] = []
		for f in e.chain:
			forms.append(String(f.form) + "@" + str(f.pos))
		print("   - ", String(e.id), " anchored=", e.anchored, " chain=", forms)
	quit(0)
