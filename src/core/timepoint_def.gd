class_name TimepointDef
extends Resource
##
## 一个离散时刻的表现层定义（GDD §2.1）。
## 权威标识是**整数索引 t**；roman / tint / light_angle / particle 只是表现层。
##

@export var id: StringName = &""        # &"T2_RUST"
@export var index: int = 0              # 2
@export var label: String = ""          # "锈时·昏"
@export var roman: String = ""          # "Ⅲ" —— 色盲安全的主标识
@export var tint: Color = Color.WHITE   # 环境色调
@export var light_angle: float = 90.0   # 光照角度（度）—— 非色彩区分通道
@export var ambient_sfx: String = ""    # 环境音
@export var particle: String = ""       # SPARK / DUST / RUST / ASH
@export var brightness: float = 1.0     # 亮度层级（非色彩通道）
