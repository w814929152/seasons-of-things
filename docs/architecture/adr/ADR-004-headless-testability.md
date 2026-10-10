# ADR-004：逻辑/渲染分离与 headless 可测试性

- **状态**：已采纳（硬约束）
- **决策者**：engineering-lead
- **关联**：architecture.md §0.1 / §3 / §9

## 上下文
硬约束：游戏逻辑层必须可在**无图形环境（headless）**下被断言测试。用户机器不保证有图形界面。这决定了分层与依赖方向。GDD §9 已给出 8 条可转成单元测试的验收标准。

## 决策：分层 + 依赖单向

1. **`src/core/` + `src/data/` 零渲染依赖**：`TimeController` / `StateFrame` / `Override` / `BackpackItem` / `WorldSnapshot` / `resolve_state` / `PuzzleGoal` / `Grid` / `LevelResource` 全部为 `RefCounted` 或纯数据，**禁止** `extends Node2D`、禁止引用 `draw`/`queue_redraw`/纹理。
2. **渲染层只读状态**：`TimeEntity._draw()` 只读 `_applied`；`apply_resolved` 是"状态 → 节点"的唯一通道，单向。
3. **求解纯谓词**：`resolve_state(e,t)` 与 `PuzzleGoal.check(world)` 输入快照、输出确定值/布尔，无副作用。
4. **测试入口**：`tests/` 用 `--headless --script` 运行，断言信号与状态，不起窗口。

## 依赖方向（不可逆）
```
core + data（纯逻辑）  ◄──  entities（渲染+交互）  ◄──  ui / level
   无依赖                 依赖 core                 依赖 entities
```
**core 不得反向依赖任何渲染类型。** 用 `Input` 抽象：逻辑层暴露方法（`shift`/`verb_take`），输入适配层（UI/测试脚本）调用之。

## GDD §9 验收标准 → 测试映射
| GDD §9 # | 标准 | 测试文件 |
|---|---|---|
| 1 | resolve 纯函数，同输入同输出 | `test_resolve_pure.gd`（随机 Override 序列 × 全时刻） |
| 2 | Override 绝不 影响 t < t_index | `test_override_no_past.gd`（写入后重算更小 t，逐字段比对基线） |
| 3 | 撤销回到任意历史节点，逐字段一致 | `test_undo_restore.gd`（快照比对） |
| 4 | 撤销全额返还时砂，无负数无泄漏 | `test_undo_restore.gd`（资源账本） |
| 5 | 5 动词覆盖全部操作，无第六动词 | 操作日志审计 |
| 7 | 关卡 1 按标准解法可通关，最少步数 | `test_level_01_solvable.gd`（按 §7 步骤表自动化） |
| 8 | IMMOVABLE/OCCLUDED 不影响占位压感 | `test_immovable_pressure.gd`（砝码锈死在压力板上机关仍开） |

## 后果
- **正向**：核心逻辑可在 CI/无显示器环境验证；关卡可解性可被断言；重构渲染不影响逻辑。
- **负向**：分层带来少量样板（状态在 core 与 Node 间传递）；作者需遵守依赖方向。lean 下用目录约定 + 清单约束即可，不引入 DI 框架。
- **验证手段**：Phase 4 用 `godot-headless-verify` 技能做全量脚本编译检查 + headless 逻辑断言。
