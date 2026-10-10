class_name Hourglass
extends RefCounted
##
## 时砂（GDD §5 L1）：切换时刻消耗 |Δt| 点；耗尽不可切换；撤销全额返还。
## 容量 12，关卡 1 最优解仅耗 2 —— 纯防穷举，不做压力。
##

var cap: int = 12
var left: int = 12


func setup(p_cap: int) -> void:
	cap = maxi(1, p_cap)
	left = cap


func can_spend(n: int) -> bool:
	return n >= 0 and left >= n


func spend(n: int) -> bool:
	if not can_spend(n):
		return false
	left -= n
	assert(left >= 0, "时砂出现负数")
	return true


# ★ 此处**故意没有** refund(n)：撤销 = 整步快照恢复（TimeController._push_history /
#   undo_step），时砂随快照一并回滚。若再叠加一次 refund，left 会被「快照 + 增量」
#   双重加算而超过 cap，破坏「时砂是派生量」（architecture §时砂）这一硬规则。
#   如需改回增量式返还，必须先撤销 undo_step 的快照语义，二者不可共存。


func refill() -> void:
	left = cap


func is_empty() -> bool:
	return left <= 0


func ratio() -> float:
	return float(left) / float(cap)
