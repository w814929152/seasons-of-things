class_name PuzzleCondition
extends RefCounted
##
## 通关判定 + 通用死锁谓词（GDD §7.1，architecture §3.9）。
## 全部由**纯谓词**构成，输入快照输出布尔，天然可 headless 单测。
##
## 本关（L01_FORGE_HALL）经设计核查：死锁谓词**永不为真**（唯一破坏性操作
## 「钥匙折断」不影响 T1，天然自愈）。谓词仍然实现并测试，供后续关卡复用。
##

## 通关判定：在 win_t 时刻站上 win_pos，且该格此刻未被阻挡
static func check_win(tc) -> bool:
	if tc == null or tc.level == null:
		return false
	if tc.current_t != tc.level.win_t:
		return false
	if tc.player_pos != tc.level.win_pos:
		return false
	if tc.is_blocked(tc.level.win_pos, tc.current_t):
		return false
	return true


## 通用死锁谓词：任何已解锁时刻都凑不出某个必需标签 → 死局
## （死局是「提示」，不是 Game Over）
static func is_deadlock(tc) -> bool:
	if tc == null or tc.level == null:
		return false
	for req in tc.level.requirements:
		var tag := String(req.get("tag", ""))
		var target_name := StringName(String(req.get("target", "")))
		if tag == "":
			continue
		if not _is_tag_satisfiable(tc, tag, target_name):
			return true
	return false


static func _is_tag_satisfiable(tc, tag: String, target_name: StringName) -> bool:
	# 1) 手上冻结的物品自带该标签
	for it in tc.inventory.items:
		if (it as InventoryItem).has_tag(tag):
			return true
	for t in tc.level.unlocked:
		# 2) 世界上某个实体在该时刻带该标签
		for e in tc.level.entities:
			var s: StateFrame = tc.resolve_state(e as TimeEntityData, t)
			if s.tags.has(tag):
				return true
		# 3) 所需目标已经处于满足态（例如门已开）
		var target: TimeEntityData = tc.level.get_entity(target_name)
		if target != null and tc.resolve_state(target, t).open:
			return true
	return false
