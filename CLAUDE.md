# 技术偏好 / 引擎版本（建议补）

> 本文件供工程级真相源使用。

## 引擎与版本

| 项 | 决策 |
|---|---|
| 引擎 | Godot **4.7.2 stable**（实测 `4.7.2.stable.official.ed1daf0bf`；`config/features` 钉定 `4.7`）—— 版本假设风险已消除 |
| 语言 | **GDScript** |
| 视角 | **2D 俯视网格**（10×5 含边界墙，level_01）。理由见 §11、concept_doc §8 |
| 关卡数据 | **自定义 Resource**（`LevelResource` / `TimeEntityResource` / `TimepointDef`），inspector 填表，类型安全、便于策划改数值（GDD §2.1、design-strategist 建议） |
| 物理 | 不用实时物理；移动/阻挡用**离散网格占用判定**（确定性、可 headless） |
| 过渡表现 | 切时刻 0.35 s 过渡：**Tween + 全局 shader 参数**（色调/光照角度），非每物体各自播动画 |
| 测试 | headless 断言（`--headless --script`）；逻辑层零 `Node` 依赖即可测 |

**版本假设风险已消除**：本机实测 Godot 4.7.2。Phase 4 期间遇到的 4.7 API 差异与实测结论全部记录在 `docs/architecture/architecture.md` §12.4（共 9 条），未臆造任何 API。

### 核心机制回顾（对齐 GDD）
```
KEY:  T0 金属锭(HOT) → T1 崭新钥匙(UNLOCKS:GATE) → T2 生锈钥匙(FRAGILE) → T3 锈块(JUNK)
```
- **世界会变，手上的不变**：背包道具免疫时刻变化（冻结拾取瞬间形态）。
- **只读历史 + 玩家覆盖层**：`chain` 是策划写在真值表里的常量；玩家操作写入 `Override`；世界呈现 = `resolve_state(实体, 当前时刻)`。
- **只影响未来**：在过去动一下，未来继承；过去不受影响。

---

## 硬约束（不可违背）

1. **逻辑与渲染解耦**：所有时间/道具/求解/通关判定逻辑必须能在**无图形环境（headless）**下被断言测试。渲染层只"读状态、画出来"，绝不反向写入游戏状态。
2. **`resolve_state` 是纯函数**：给定 `(实体, 时刻, Override 日志)`，输出永远唯一确定 → 这是系统**悖论免疫力**的来源（GDD §3.3、§4.1）。不做因果物理模拟、不做推导。
3. **只向未来传播**：`t_index > t` 的 Override 一律不生效。写入代码断言，这是祖父悖论的唯一防线（GDD §4.2）。
4. **切换可逆、无副作用**：撤销按 `parent_seq` 级联删除 forward 派生记录，全额返还时砂，零代价、不限次数。
5. **本轮不写代码**：`src/` 保持空，本文档只给类签名（方法名 + 属性 + 信号），Phase 4 再实现。

---

## 目录结构（Godot 工程）

```
D:/New test/
├─ project.godot                     # config/features=PackedStringArray("4.7")；[input] 映射
├─ CLAUDE.md                         # 技术偏好/引擎版本（建议补）
├─ src/
│  ├─ core/                          # 零渲染依赖的逻辑层（可 headless 单测）
│  │  ├─ time_controller.gd          # TimeController
│  │  ├─ state_frame.gd              # StateFrame（RefCounted）
│  │  ├─ override.gd                 # Override（RefCounted）
│  │  ├─ backpack.gd                 # BackpackItem
│  │  ├─ world_snapshot.gd
│  │  ├─ resolve.gd                  # resolve_state 纯函数（可独立单测）
│  │  ├─ puzzle_goal.gd              # 通关 + 死锁谓词
│  │  ├─ grid.gd                     # 离散网格占用/通行判定
│  │  └─ save_data.gd
│  ├─ data/                          # 关卡数据 Resource
│  │  ├─ level_resource.gd
│  │  ├─ timepoint_def.gd
│  │  └─ time_entity_resource.gd
│  ├─ entities/                      # 道具（含渲染，Node2D）
│  │  ├─ time_entity.gd              # 基类
│  │  └─ props/                      # key.gd / weight.gd / vine.gd / gate.gd ...
│  ├─ level/
│  │  └─ level_manager.gd
│  ├─ ui/                            # UI 层（Control）
│  │  ├─ time_ruler.gd
│  │  ├─ hourglass_hud.gd
│  │  ├─ backpack_hud.gd
│  │  ├─ hint_layer.gd
│  │  └─ undo_control.gd
│  └─ main.gd
├─ levels/
│  ├─ level_01.tscn
│  └─ level_01_data.tres             # LevelResource 实例
├─ tests/                           # headless 断言测试
│  ├─ test_resolve_pure.gd           # §9 验收1：纯函数
│  ├─ test_override_no_past.gd       # §9 验收2：绝不影响过去
│  ├─ test_undo_restore.gd           # §9 验收3/4：撤销复原+时砂
│  ├─ test_immovable_pressure.gd     # §9 验收8：形态锁不影响压感
│  └─ test_level_01_solvable.gd      # §9 验收7：按 §7 步骤表可通关
├─ docs/
│  ├─ architecture/architecture.md
│  ├─ architecture/adr/ADR-001~005
│  └─ architecture/tech_checklist.md
└─ design/                           # DS-101 产出（真相源）
```

**关键分层：** `src/core/` + `src/data/` **禁止**引用 `Node2D`/渲染类型，确保 headless 可测；`src/entities/` 才含绘制。这是硬约束 §0.1 的落地（ADR-004）。

---

## 与 GDD 的对齐状态（原"待确认"已解决）

| # | 事项 | 结论 | 来源 |
|---|---|---|---|
| 1 | 时间模型 | 离散时刻切换、全局单一时刻 | GDD §2 ✅ |
| 2 | 状态模型 | 只读链 + Override 覆盖层 + resolve 纯函数 | GDD §3/§4 ✅ |
| 3 | 形态链 | StateFrame 四元组，按 t 索引 | GDD §3.2 ✅ |
| 4 | 携带穿越 | **背包是"时间之外"存储**，冻结形态，切时刻不变 | GDD §4.3/§5 L2 ✅ |
| 5 | 通关判定 | 纯谓词 + 通用死锁谓词 | GDD §7.1 ✅ |
| 6 | 因果检测 | **不做因果物理模拟**；悖论免疫靠 resolve 确定性 | GDD §4.1 ✅ |
| 7 | 派生状态 | 压力板/闸门实时重算，不进 Override 层 | GDD §6.2 ✅ |

> **无遗留待确认项。** 架构已完全对齐 GDD。若 GDD 后续修订，本文档跟进。
