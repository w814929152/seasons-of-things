class_name WeightEntity
extends TimeEntity
## 黄铜砝码（具体道具）—— 四形态共用同一剪影，只改材质与侵蚀层级。
## 剪影守恒是硬约束：玩家必须能一眼认出「是同一个东西」。

func _draw_form(form: StringName, _is_current: bool) -> void:
	var pressed := false
	PropArt.draw_weight(self, form)
