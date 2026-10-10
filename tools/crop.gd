extends SceneTree
##
## 看图诊断工具（Image 操作不需要渲染，headless 可跑）：
##   ① 按**设计坐标**裁剪并放大指定区域（自动识别截图缩放倍率）；
##   ② 在若干**关键格中心**采样像素色并打印（量化"墙地对比"这类主观判断）。
##
## 用法：
##   "Godot_..._console.exe" --headless --path "D:/New test" --script res://tools/crop.gd \
##     -- img=res://_shot_t2.png
##

const DESIGN_W := 1248.0
const ORIGIN := Vector2(0.0, 140.0)   # 网格原点（与 level_manager / environment_layer 一致）
const CELL := 96.0

## 设计坐标下的诊断区域（x, y, w, h）—— 坐标随 13×8 新布局更新
const REGIONS := {
	"wall_corner":  [0, 140, 192, 192],       # 左上角：外墙拐角 → 墙/地分离
	"floor_plain":  [384, 524, 192, 192],     # 西厅纯空地 (4,4)(5,4)(4,5)(5,5) → 地板是否一整片
	"grate_plate":  [864, 332, 192, 192],     # 闸门 (10,2) + 压力板 (9,3)
	"key_stand":    [288, 332, 96, 96],       # 钥匙台 (3,2)
	"player":       [192, 620, 192, 192],     # 玩家起点 (3,5)
	"exit_goal":    [1056, 236, 96, 96],      # 出口门 (11,1) —— 目标格标记
	"hud_band":     [0, 0, 1248, 140],        # HUD 仪表带整条（三组面板 + 按钮 + 状态行）
}

## 采样点：格子中心（格坐标，必须是"无实体"的格子才反映纯地板）
const SAMPLES := {
	"floor_west(2,1)": Vector2i(2, 1),
	"floor_west(5,4)": Vector2i(5, 4),
	"floor_east(9,5)": Vector2i(9, 5),
	"wall_(0,1)":      Vector2i(0, 1),
	"wall_(7,3)":      Vector2i(7, 3),
	"void_(?)":        Vector2i(-1, -1),
}


func _initialize() -> void:
	var src := "res://_preview.png"
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("img="):
			src = s.substr(4)
	var img := Image.load_from_file(src)
	if img == null:
		print("[crop] FAIL: 找不到 ", src)
		quit(1)
		return
	var s: float = float(img.get_width()) / DESIGN_W
	print("[crop] src=%s size=%s scale=%.2f" % [src, str(img.get_size()), s])

	for k in REGIONS.keys():
		var a: Array = REGIONS[k]
		var r := Rect2i(int(a[0] * s), int(a[1] * s), int(a[2] * s), int(a[3] * s))
		r = r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
		var c := img.get_region(r)
		var mag := 3 if r.size.x <= 400 else 2
		c.resize(r.size.x * mag, r.size.y * mag, Image.INTERPOLATE_NEAREST)
		var err := c.save_png("res://_crop_%s.png" % k)
		print("[crop] %-12s err=%d" % [k, err])

	print("[sample] ── 关键格中心取色（十六进制 / 亮度）──")
	for k in SAMPLES.keys():
		var cell: Vector2i = SAMPLES[k]
		var p: Vector2
		if cell.x < 0:
			p = Vector2(20.0, 20.0)          # 左上角即 HUD 背板 / 房间外
		else:
			p = ORIGIN + (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
		# 格中心可能压着道具：再往格角挪一点取"纯地面"
		var q: Vector2 = p + Vector2(-CELL * 0.30, -CELL * 0.30)
		var c1 := img.get_pixel(int(p.x * s), int(p.y * s))
		var c2 := img.get_pixel(int(q.x * s), int(q.y * s))
		print("[sample] %-18s 中心=%s (lum %.3f)  偏角=%s (lum %.3f)" % [
			k, c1.to_html(false), c1.get_luminance(), c2.to_html(false), c2.get_luminance()])
	quit(0)
