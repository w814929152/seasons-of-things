extends Node2D
##
## 游戏入口：把关卡层与 UI 层拼起来（architecture §2.1）。
## 逻辑真相在 TimeController（src/core，零渲染依赖），这里只做组装。
##

const LEVEL_MANAGER := preload("res://src/level/level_manager.gd")
const HUD_SCRIPT := preload("res://src/ui/hud.gd")
const WINDOW_SCALER := preload("res://src/ui/window_scaler.gd")

var level: LevelManager = null
var hud: HUD = null


func _ready() -> void:
	# 先把 1248×908 的设计画布等比放大到「屏幕放得下的最大尺寸」并居中 ——
	# 场景与道具随之整体变大变清晰（canvas_items 模式为清晰缩放，不会糊）。
	WINDOW_SCALER.apply()

	level = LEVEL_MANAGER.new()
	level.name = "Level01"
	add_child(level)

	hud = HUD_SCRIPT.new()
	hud.name = "HUD"
	add_child(hud)

	level.start_level()
	hud.bind_level(level)

	level.level_message.connect(func(text: String) -> void: print("[game] ", text))
	level.level_goal.connect(func() -> void: print("[game] GOAL REACHED"))
	print("[game] ready: ", level.status_text())
