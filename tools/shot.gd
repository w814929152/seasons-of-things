extends SceneTree
##
## 一次性截图工具：把主场景真实渲染出来存成 PNG，用于视觉检查（关卡辨识度等）。
##
## ⚠ 必须**非 headless** 运行（headless 用 Dummy display server，截出来是纯黑）。
##
## 用法：
##   "Godot_..._console.exe" --path "D:/New test" --script res://tools/shot.gd
##
## 产物：res://_preview.png
##

## 可选参数（跟在 `--` 后面，空格分隔）：
##   scene=res://…   要截的场景（默认《物候》主场景）
##   out=res://….png 输出路径
##   frames=180      等待帧数（动态场景要多等几帧才有东西可看）
##   launch=0.8      场景根节点是 TopsMain 时，替玩家发射（力度 0.15–1.0），
##                   否则会一直停在发射阶段截不到战斗画面
##   scale=1.0       《物候》主场景：强制窗口缩放倍率（1.0 = 1248×908 设计分辨率，
##                   便于逐像素核对；不传则用启动时的自动放大）
##   t=0..3          《物候》主场景：切到指定时刻后再截图（默认停在关卡起始时刻）
##   hints=3         《物候》主场景：连按 3 次 H（= 提示条共 4 行），
##                   用于复核「多行提示条是否被画布底边 / 边框切掉」
##   hover=x,y       《物候》主场景：把鼠标指针移到格 (x,y) 中心（真实鼠标事件），
##                   用于截「静止时的路径预览」
##   walk=x,y        《物候》主场景：左键点一下格 (x,y) 而后抬起，
##                   用于截「移动中的剩余路线预览」
##   walkframes=12   walk 之后再等几帧才截（默认 6）——给几帧让精灵走出半格，
##                   不然看起来和静止没区别
const ORIGIN := Vector2(0.0, 140.0)
const CELL := 96.0

func _initialize() -> void:
	var scene_path := "res://src/main/main.tscn"
	var out_path := "res://_preview.png"
	var frames := 8
	var launch := -1.0
	var force_scale := 0.0
	var want_t := -1
	var want_hints := 0
	var hover_cell := Vector2i(-1, -1)
	var walk_cell := Vector2i(-1, -1)
	var walk_frames := 6
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("scene="):
			scene_path = s.substr(6)
		elif s.begins_with("out="):
			out_path = s.substr(4)
		elif s.begins_with("frames="):
			frames = int(s.substr(7))
		elif s.begins_with("launch="):
			launch = float(s.substr(7))
		elif s.begins_with("scale="):
			force_scale = float(s.substr(6))
		elif s.begins_with("t="):
			want_t = int(s.substr(2))
		elif s.begins_with("hints="):
			want_hints = int(s.substr(6))
		elif s.begins_with("hover="):
			hover_cell = _parse_cell(s.substr(6))
		elif s.begins_with("walk="):
			walk_cell = _parse_cell(s.substr(5))
		elif s.begins_with("walkframes="):
			walk_frames = int(s.substr(11))

	await process_frame
	var scene := load(scene_path)
	if scene == null:
		print("[shot] FAIL: 无法加载 ", scene_path)
		quit(1)
		return
	var main: Node = scene.instantiate()
	root.add_child(main)
	if main is TopsMain and launch > 0.0:
		await process_frame
		(main as TopsMain)._launch(clampf(launch, 0.15, 1.0))
	if force_scale > 0.0:
		await process_frame
		WindowScaler.apply(force_scale)
	# 《物候》：切到指定时刻（每次切换前清掉 0.35 s 冷却，否则会被静默吞掉）
	if want_t >= 0 and main.get("level") != null:
		await process_frame
		var lm = main.get("level")
		var guard := 0
		while lm.tc.current_t != want_t and guard < 8:
			lm._transition = 0.0
			lm._try_shift(1 if want_t > lm.tc.current_t else -1)
			guard += 1
	# 《物候》：连按若干次 H，把提示条撑到多行（复核"文字提示被边框 / 底边切"）
	if want_hints > 0 and main.get("level") != null:
		await process_frame
		var lm_h = main.get("level")
		for _i in want_hints:
			lm_h._do_hint()
			await process_frame
	# 《物候》：先"点一下"某格（截移动中的路径预览），再把指针悬停到某格
	if main.get("level") != null and walk_cell.x >= 0:
		await process_frame
		var lm_w = main.get("level")
		lm_w.move_to(walk_cell)
		for _i in walk_frames:
			await process_frame
	if main.get("level") != null and hover_cell.x >= 0:
		await process_frame
		var lm_h = main.get("level")
		_push_motion(_cell_center(hover_cell))
		await process_frame
	# 多等几帧：等 HUD bind、环境层粒子、道具 redraw 全部就位
	for _i in frames:
		await process_frame
	# 诊断行：截图前把"逻辑坐标 / 精灵像素 / 距离本格格心多远 / 剩余路线"一并打出来。
	# 逐格推进之后这三者不再恒等（逻辑坐标滞后于精灵），看图时容易误判成 bug，
	# 所以直接把数摆出来 —— 看图和读数互为交叉验证。
	if main.get("level") != null:
		var lm_d = main.get("level")
		var pp: Vector2 = lm_d.get("_player").position
		var pc: Vector2i = lm_d.tc.player_pos
		print("[shot] 逻辑坐标=", pc,
			" 精灵像素=", pp,
			" 本格格心=", lm_d._cell_center(pc),
			" 距格心=%.1f px" % pp.distance_to(lm_d._cell_center(pc)),
			" 剩余路线=", lm_d.get("_route"))
	var vp := root.get_viewport()
	var img: Image = vp.get_texture().get_image()
	# ★ 偶发坑（实测踩到）：窗口刚按 scale= 调整完的头几帧里，HUD 所在的 CanvasLayer
	#   可能还没画进视口纹理 —— 截出来顶部 140 px 一片纯黑，看图的人会以为"HUD 没了"。
	#   这里按 HUD 刻度尺上的采样点自检，全黑就再等几帧重截（最多 12 次）。
	var tries := 0
	while tries < 12 and _hud_blank(img):
		await process_frame
		img = vp.get_texture().get_image()
		tries += 1
	if tries > 0:
		print("[shot] 首帧 HUD 未入纹理，重截了 %d 次" % tries)
	var err: int = img.save_png(out_path)
	print("[shot] err=", err, " size=", img.get_size(), " -> ", out_path)
	quit(0)


## HUD 是否整片空白（采样刻度尺 / 沙漏 / 状态行三处，全黑即判定未入纹理）
func _hud_blank(img: Image) -> bool:
	if img.get_height() < 140 or img.get_width() < 400:
		return false
	for p in [Vector2i(60, 30), Vector2i(300, 40), Vector2i(120, 84), Vector2i(700, 88)]:
		var c := img.get_pixelv(p)
		if c.r > 0.07 or c.g > 0.07 or c.b > 0.07:
			return false
	return true


func _parse_cell(s: String) -> Vector2i:
	var parts := s.split(",")
	if parts.size() != 2:
		printerr("[shot] 无法解析格坐标：", s)
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


func _cell_center(c: Vector2i) -> Vector2:
	return ORIGIN + (Vector2(c) + Vector2(0.5, 0.5)) * CELL


## 注入真实鼠标移动事件（视口局部坐标）—— 和玩家动手移指针走同一条 _unhandled_input 路径
func _push_motion(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	root.push_input(ev, true)
