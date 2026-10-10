class_name Resolve
extends RefCounted
##
## resolve_state —— 系统的心脏（GDD §3.3，architecture §3.7）。
##
## 纯函数：给定 (实体, 时刻, Override 日志)，输出永远唯一确定。
## 这是「悖论免疫力」的来源：不存在算不出来的状态。
##
## ★★ 硬断言（祖父悖论的唯一防线）★★
##   `o.t_index > t` 的 Override **绝不**参与求值 —— 只向未来传播，绝不向过去传播。
##   本文件不写 assert 之外的副作用，可在 headless 下逐字段断言。
##


## 主入口
static func resolve_state(entity: TimeEntityData, t: int, overrides: Array) -> StateFrame:
	assert(entity != null, "resolve_state: entity 为空")
	assert(t >= 0 and t < entity.chain.size(),
		"resolve_state: t=%d 越界 (chain=%d)" % [t, entity.chain.size()])

	# 1) 取只读历史链在该时刻的帧
	var s := entity.chain[t].duplicate_frame()

	# 2) 叠加覆盖层：按 seq 升序遍历，后写覆盖先写
	var latest: Dictionary = {}
	for raw in overrides:
		var o := raw as Override
		if o == null:
			continue
		if o.entity_id != entity.id:
			continue
		# ★ 核心断言：未来写入不影响过去
		if o.t_index > t:
			continue
		# 字段白名单（锚定物只接受被显式许可的字段）
		if not entity.can_override(o.field):
			continue
		latest[String(o.field)] = o.value

	# 3) 应用到副本（不触碰 chain 原值）
	for f in latest.keys():
		s.set_field(StringName(f), latest[f])

	return s


## 显式断言「绝不向过去传播」：返回所有在 t 生效的 override（供测试与调试用）
static func applicable_overrides(
	entity: TimeEntityData,
	t: int,
	overrides: Array
) -> Array[Override]:
	var out: Array[Override] = []
	for raw in overrides:
		var o := raw as Override
		if o == null: continue
		if o.entity_id != entity.id: continue
		if o.t_index > t: continue
		if not entity.can_override(o.field): continue
		out.append(o)
	out.sort_custom(func(a: Override, b: Override) -> bool: return a.seq < b.seq)
	return out


## 判定某时刻某实体是否「存在于世界上」（用于占位 / 压感 / 阻挡）
static func exists(s: StateFrame) -> bool:
	return s != null and (not s.removed) and s.pos != StateFrame.POS_VOID
