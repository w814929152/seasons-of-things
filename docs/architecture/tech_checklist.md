# 实现控制清单（Phase 4 开工前 / 交付时的"一页规则"）

> 用途：动手写代码前逐项确认；交付时逐项回看。
> 状态图例：⬜ 待确认 / ✅ 已确认且已实现 / ⚠️ 有风险待处理 / ❌ 已废弃（被新决策取代）
> 真相源：`design/gdd/core_mechanic_gdd.md`、`design/level/level_01_design.md`、`design/concept/concept_doc.md`。

---

## 1. 环境与版本

| # | 确认项 | 状态 | 备注 |
|---|---|---|---|
| 1 | Godot 版本钉定 **4.7**（`config/features`） | ✅ | **已实测**：`4.7.2.stable.official.ed1daf0bf`。原"假定 4.2"的风险项已消除 |
| 1b | 验证一律走 **headless + console 版 exe** | ✅ | GUI 版在 Windows headless 下不输出 stdout；用 `Godot_v4.7.2-stable_win64_console.exe` |
| 1c | 新增 `class_name` 文件后先跑一次 `--import` | ✅ | 否则其它脚本报 `Identifier "X" not declared`（坑 #6，见 architecture §12.4） |

## 2. 渲染与美术

| # | 确认项 | 状态 | 备注 |
|---|---|---|---|
| 2 | 2D 俯视网格（10×5 含边界墙） | ✅ | level_01；解密 + 零美术 + headless 三者折中的最优解 |
| 3 | 全程序化绘制，**零外部美术资源** | ✅ | `src/entities/prop_art.gd` 全 `_draw()`；9 种道具剪影守恒 |
| 3b | **剪影守恒**（同道具各形态共用剪影） | ✅ | 每种道具只有一个 `draw_xxx()`，形态差异只改颜色/侵蚀层/细节 |
| 3c | 罗马刻度 Ⅰ–Ⅳ 用**线段**绘制，不用字体 | ✅ | 规避内置字体缺 U+2160 字形；也是色盲安全主通道 |
| 3d | 中文 Label 用 `SystemFont` | ✅ | 内置字体无 CJK 字形；OS 自带字体，零文件依赖 |
| 3e | 时刻区分 ≥3 条非色彩通道 | ✅ | 罗马刻度 + 光照角度 + 粒子 + 亮度层级 + 色调（5 条） |

## 3. 时间与状态模型

| # | 确认项 | 状态 | 备注 |
|---|---|---|---|
| 4 | 时刻标识：**整数 `t ∈ [0,N-1]` 是权威** | ✅ | `id`/`roman`/`tint`/`light_angle`/`particle` 只是表现层（GDD §2.1） |
| 5 | 只读链 + Override 覆盖层 + resolve 纯函数 | ✅ | `Resolve.resolve_state()`；"per-entity 静态表 + 因果检测"草案已废弃 |
| 6 | `t_index > t` 的 Override **绝不生效** | ✅ | `resolve.gd` 显式 `continue` + `test_resolve_pure` 逐字段比对 |
| 7 | forward 传播：父记录 + 派生记录（`parent_seq`） | ✅ | `TimeController.add_override()` |
| 8 | 携带穿越：**背包 = 时间之外**，冻结 form/tags | ✅ | `InventoryItem` 不参与 resolve；容量 2 |
| 9 | **时砂 Hourglass**：cap 12，耗 `\|Δt\|`，耗尽拒绝，撤销返还 | ✅ | `src/core/hourglass.gd` + HUD 常驻（GDD §5 L1） |
| 9b | 时砂实现为**计数器**而非 action_log 派生量 | ✅ | GDD §5 L1 明确"容量 12、耗尽不可切换"；计数器语义直白且 `assert(left >= 0)` 可证无负数 |
| 10 | 派生状态：压力板/闸门**实时求值，不落 Override** | ✅ | `plate_pressed(t)` / `grate_open(t)` |
| 11 | 形态锁只影响持取，**绝不影响占位/压感** | ✅ | 三处代码注释 + `test_immovable_pressure` 5 条断言 |
| 12 | **残影唯一真值源 = resolve_state(e,t) 含 Override** | ✅ | `TimeEntity.set_ghost()`；残影不可交互（GDD §5 L7） |

## 4. 判定与撤销

| # | 确认项 | 状态 | 备注 |
|---|---|---|---|
| 13 | 通关判定：纯谓词 | ✅ | `PuzzleCondition.check_win()`：t==2 且 pos==(8,1) 且未阻挡 |
| 14 | 通用死锁谓词（GDD §7.1） | ✅ | 本关永不为真；用伪造需求反向验证谓词非空实现 |
| 15 | 撤销：**整步快照回滚** | ✅ | **取代** `parent_seq` 级联删除 → ADR-005；`parent_seq` 仅保留作追溯 |
| 15b | 撤销/重置永远免费、不限次数、全额返还 | ✅ | 关卡文档 §9.1「时砂耗尽 → 撤销自救」依赖此条 |
| 16 | 重置时刻：回出厂态，免费 | ✅ | `TimeController.reset()` |

## 5. 输入与交互

| # | 确认项 | 状态 | 备注 |
|---|---|---|---|
| 17 | 输入映射写入 `project.godot [input]` | ✅ | 由 `tools/setup_input.gd` 生成（坑 #1：必须显式 `ProjectSettings.set("input/...")`） |
| 17b | 键位：`↑↓←→`移动 · `A/D`切时刻 · `空格`持取 · `Q`放置 · `E`使用 · `Tab`观察 · `Z`撤销 · `H`提示 · `R`重置 | ✅ | 关卡文档 §10（第八轮把方向键让给移动，切时刻收敛到 `A/D`） |
| 17c | **`E` 只绑定 Use，不复用为切时刻** | ✅ | 已由测试断言（扫描所有游戏 action 的按键归属） |
| 17d | 动词总数锁死 5（观察/切换/持取/放置/使用） | ✅ | 放置用独立键 `Q`，不新增动词 |
| 18 | 移动：点击格子 → BFS 寻路（不计步） | ✅ | 关卡文档 §7「移动由寻路完成，不计步」 |
| 18b | 走路更新朝向 + 放置/使用按面向格取目标 | ✅ | `LevelManager._facing`；无朝向则兜底扫四邻 |
| 18c | 移动是**逐格推进**：逻辑坐标只在精灵抵达该格时才提交 | ✅ | `TimeController.mark_move_start()` + `commit_cell()`；`LevelManager._route`。断言见 `tests/test_movement.gd` |
| 18d | 键盘移动（`↑↓←→`，按住连续走）+ 鼠标长按拖拽改目的地 | ✅ | 键盘在 `_process` 轮询 `Input.is_action_pressed`（天然支持按住）；拖拽走 `InputEventMouseMotion` |
| 18e | 路径预览：悬停/移动中在地上画可达路线，不可达画暗红叉角 | ✅ | `LevelManager.preview_path()`；足迹层在地板上、悬停光标层在道具之上 |
| 18f | 整段连续移动只占 **1 条**撤销记录 | ✅ | 只在"从静止出发"时 `mark_move_start()` 入栈一次 |
| 18g | **藤蔓四形态一律 `BLOCKING`**（硬性咽喉）：`PULLABLE`＝拔得动，`BLOCKING`＝挡着路，两者正交 | ✅ | 回归 `tests/test_level_01_solvable.gd::_vine_chokepoint()`；对照探针 `tools/probe_vine_bypass.gd`。**曾漏**：T0/T1 只带 `PULLABLE` ⇒ 幼苗/幼藤不阻挡 ⇒ 切到 T1 直接穿过 (8,1)、切回 T2 即可通关，P3 谜题被架空、§7「步 7 拔藤」沦为多余 |
| 18h | 改了 `src/data/level_01_def.gd` **必须重新生成** `levels/level_01_data.tres` | ✅ | `LevelLoader` 优先加载 .tres，仅失败才回退 def。只改 def 不重生成 = 改了毫无效果（本轮实际踩到） |

## 6. 分层与可测性

| # | 确认项 | 状态 | 备注 |
|---|---|---|---|
| 19 | `src/core/` + `src/data/` **零渲染依赖** | ✅ | 硬约束；`TimeController` 是 `RefCounted`，headless 可直接 new |
| 20 | 网格占用：离散网格，不用物理引擎 | ✅ | `Grid` + `is_blocked()` 四邻域 BFS |
| 21 | 关卡数据：**自定义 Resource（.tres）** | ✅ | `levels/level_01_data.tres`，由 `tools/gen_level_res.gd` 从 `Level01Def` 生成 |
| 22 | 关卡数值**照抄真值表，零改动** | ✅ | 唯一数据层调整 `KEY.solid=false`（不改则关卡不可解，见 architecture §12.5） |
| 23 | headless 断言测试 | ✅ | 183 条，全绿，0 ERROR；见 `tests/README.md` |
| 24 | 存档 | ⬜ | **本轮未做**（垂直切片范围外）。规划：`level_id` + `current_t` + `overrides` + 背包；不存 chain/派生/渲染 |

---

## 已知风险与缓解

| # | 风险 | 缓解 |
|---|---|---|
| R1 | **"取走→放下"时序语义被误"修"**：T1 取走 → T2 仍空着是**正确行为**（GDD §4.4） | 代码注释复述规则 + `test_level_01_solvable` 步 4/5 锁死 + 已在 UI 给「它将从此时开始存在」提示语 |
| R2 | **形态锁误影响占位/压感** → 关卡不可解 | `test_immovable_pressure` 专项；`is_blocked()` 与 `plate_pressed()` 均**不读**形态锁标签 |
| R3 | **锚定物语义冲突**（GDD §4.3 vs §6） | 已用 `writable_fields` 白名单化解 → architecture §12.3-D1；需主理人确认 |
| R4 | **放置是否冻结形态**（GDD §4.3 C3 vs 关卡 §9.1/§11-8） | 已选"只写 pos" → ADR-006；需主理人确认 |
| R5 | Godot 4.7 与训练数据（≤4.2）的 API 差异 | 全部用 headless 实测确认后才落地，坑位已记录在 architecture §12.4 |

## 本轮已知限制（垂直切片）

- 无音效（GDD §2.3 的听觉通道缺失 → 时刻区分当前只有 4 条非色彩通道）
- 切时刻过渡是 0.35 s 冷却 + 瞬时重绘，**未做 Tween 插值动画**（ADR/架构 §4 步骤 11 的视觉规格未完全实现）
- 无存档 / 无关卡选择 / 无评星
- 提示系统只有 L1→L2→L3 的**主动**按 `H` 递进；**被动**计时触发（90s/180s/360s 阈值）未实现
- 操作时间轴（长按 Z 拖动到任意历史节点）未实现，只做了单步撤销 + 重置
