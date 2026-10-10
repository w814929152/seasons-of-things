extends SceneTree
##
## 输入映射安装器（离线工具，不参与游戏运行）。
##
## 用法：
##   godot_console --headless --path "D:/New test" --script res://tools/setup_input.gd
##
## ★ Godot 4.7 实测坑：InputMap.add_action() **不会**写进 ProjectSettings
##   （has_setting("input/xxx") 仍为 false），所以 ProjectSettings.save() 持久化不到。
##   必须显式 ProjectSettings.set("input/<action>", {deadzone, events}) 再 save()。
##
## 键位表来自 design/level/level_01_design.md §10：
##   A/D 切时刻 · ↑↓←→ 移动（长按连续走） · 空格 持取 · Q 放置 · E 使用 ·
##   Tab 观察 · Z 撤销 · H 提示 · R 重置
##   ⚠ E **只**绑定 Use，不复用为切时刻（概念文档 §5 已修正的键位冲突）。
##   ⚠ 方向键**只**做移动：原先 ←/→ 兼做切时刻，但它与"格子移动"的心智模型冲突
##     （玩家按方向键期待"走一步"，而不是"跳一个时刻"），故收敛为 A/D 切时刻。
##

const BINDINGS := {
	"shift_prev": [KEY_A],
	"shift_next": [KEY_D],
	"move_up": [KEY_UP],
	"move_down": [KEY_DOWN],
	"move_left": [KEY_LEFT],
	"move_right": [KEY_RIGHT],
	"take": [KEY_SPACE],
	"place": [KEY_Q],
	"use": [KEY_E],
	"observe": [KEY_TAB],
	"undo": [KEY_Z],
	"hint": [KEY_H],
	"reset": [KEY_R],
	# ── 陀螺对战（tops/）：与《物候》不同时运行，键位复用不冲突 ──
	"tops_up": [KEY_W, KEY_UP],
	"tops_down": [KEY_S, KEY_DOWN],
	"tops_left": [KEY_A, KEY_LEFT],
	"tops_right": [KEY_D, KEY_RIGHT],
	"tops_boost": [KEY_SHIFT],
	"tops_restart": [KEY_R],
}


func _initialize() -> void:
	for action in BINDINGS.keys():
		var events: Array[InputEvent] = []
		for kc in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.device = -1
			ev.keycode = kc
			ev.physical_keycode = kc
			events.append(ev)
		ProjectSettings.set("input/" + action, {"deadzone": 0.5, "events": events})

	# 清理历史遗留的探测用 action
	if ProjectSettings.has_setting("input/probe_act"):
		ProjectSettings.set("input/probe_act", null)

	var err := ProjectSettings.save()
	if err != OK:
		print("[setup_input] FAILED err=", err)
		quit(1)
		return

	print("[setup_input] OK — 已写入 project.godot [input]")
	quit(0)
