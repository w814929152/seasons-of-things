# ADR-002：切换时刻的求值策略（resolve 纯函数 + 派生状态重算）

- **状态**：已采纳（对齐 GDD §3.3、§6.1、§6.2）
- **决策者**：engineering-lead
- **关联**：architecture.md §4 / §5 / §3.8

## 上下文
玩家切换"当前时刻"时，世界需呈现新时刻的完整状态。GDD 已定义求值方式：`resolve_state` 纯函数 + 派生状态实时重算。

## 求值分两层

### 层 1：实体状态 —— `resolve_state` 纯函数（全量、确定性）
```
resolve_state(entity, t):
    s = chain[t].duplicate()
    if anchored: return s          # 锚定物只读
    for o in overrides (seq 升序):
        if o.entity_id != id: continue
        if o.t_index > t: continue  # 未来写入不影响过去（核心断言点）
        latest[o.field] = o.value   # 后写覆盖先写
    apply(latest) → return s
```
- **全量重算**：每次切换对每个实体独立 resolve，不维护增量 diff。
- **理由**：时刻数有限（4~6）、实体数 ≤ 9，全量成本可忽略；确定性 + 可逆 + 可测优先于省 CPU（见原 ADR-002 分析，结论不变）。

### 层 2：派生状态 —— 实时重算，不进 Override 层
- 压力板：`pressed(t) = ∃ e，resolve(e,t).pos == 板坐标 且 tags 含 PRESSER`
- 闸门：`open(t) = plate.pressed(t)`
- **每次切换/操作后重算**，不落 Override（否则与实体 Override 耦合、破坏确定性）。

## 判定优先顺序（GDD §6.1，实现必读）
```
1. resolve_state(entity, current_t)
2. 检查 tags 是否允许动作（形态锁）→ 不允许则拒绝 + 原因反馈
3. 执行动作 → 追加 Override（seq++）
4. 重算所有派生状态（压力板 → 闸门）
5. 重算死锁谓词
6. 播放反馈（动画 + 音效 + 图标，三通道冗余）
```

## 关键硬规则（防实现反了导致关卡不可解）
- **`IMMOVABLE` / `OCCLUDED` / `HOT` 只影响"玩家能否持取"，绝不影响"占位/压感/阻挡"**。
- 反例：T2 砝码 `WEIGHT_SEIZED`（锈死）在压力板上时，机关**必须开着**。若实现成"锈死就不压板"，关卡 1 直接不可解（GDD §5.2、§9 验收 8 专项用例）。

## 后果
- **正向**：可逆、无副作用、易测（`resolve_state` 纯函数 headless 直接断言）。
- **负向**：若未来关卡规模暴增（数百实体 + 高频切换）需重评增量；当前明确不做。
- **前置约束**：派生状态公式依赖 GDD 真值表，已在 level_01 固定，无待确认项。
