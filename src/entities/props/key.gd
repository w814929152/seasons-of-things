class_name KeyEntity
extends TimeEntity
## 钥匙（具体道具）—— 四形态共用同一剪影，只改材质与侵蚀层级。
## 剪影守恒是硬约束：玩家必须能一眼认出「是同一个东西」。

func _draw_form(form: StringName, _is_current: bool) -> void:
	# KEY 与 STAND 同处 (3,2)。竖直绘制会和台面糊成一根「图腾柱」，
	# 斜搁 + 上移 + 略缩，让钥匙看起来是**躺在台面上**的一把钥匙。
	draw_set_transform(Vector2(0.0, -22.0), deg_to_rad(-62.0), Vector2(0.72, 0.72))
	PropArt.draw_key(self, form)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
