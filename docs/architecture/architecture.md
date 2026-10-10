# 主架构文档 — 《物候》（Godot 4 / GDScript）

> 代号：物候 / Seasons of Things ｜ 引擎：Godot 4.x（GDScript）｜ 评审强度：lean
> 维护：程基岩（engineering-lead）
> **真相源对齐**：本文档以 `design/gdd/core_mechanic_gdd.md`（机制）、`design/level/level_01_design.md`（关卡真值表）、`design/concept/concept_doc.md`（范围）为准。与 GDD 冲突处一律以 GDD 为准，本文档修订跟进。

---

## 0. 文档定位与硬约束

本文档是**技术方向唯一真相源**，定义引擎、场景树、核心类签名、时刻切换管线、`resolve_state` 求值模型、Override 传播、数据流、撤销/重置、存档与目录结构。

**硬约束（不可违背）：**
1. **逻辑与渲染解耦**：所有时间/道具/求解/通关判定逻辑必须能在**无图形环境（headless）**下被断言测试。渲染层只"读状态、画出来"，绝不反向写入游戏状态。
2. **`resolve_state` 是纯函数**：给定 `(实体, 时刻, Override 日志)`，输出永远唯一确定 → 这是系统**悖论免疫力**的来源（GDD §3.3、§4.1）。不做因果物理模拟、不做推导。
3. **只向未来传播**：`t_index > t` 的 Override 一律不生效。写入代码断言，这是祖父悖论的唯一防线（GDD §4.2）。
4. **切换可逆、无副作用**：撤销 = **回滚一步完整操作的快照**（时刻 + 时砂 + Override 及其 forward 派生 + 背包 + 坐标），撤销/重置永远免费、零代价、不限次数。实现取舍见 ADR-005（快照回滚 vs `parent_seq` 级联删除）。
5. **Phase 4 已实现**：`src/` 已落地，本文档的类签名即为实际签名；`tests/` 183 条 headless 断言全绿。验证命令与结果见 §13。

---

## 1. 技术栈确认与引擎版本假设

| 项 | 决策 |
|---|---|
| 引擎 | Godot **4.7.2 stable**（实测 `4.7.2.stable.official.ed1daf0bf`；`config/features` 钉定 `4.7`）—— **版本假设风险已消除** |
| 语言 | **GDScript** |
| 视角 | **2D 俯视网格**（10×5 含边界墙，level_01）。理由见 §11、concept_doc §8 |
| 关卡数据 | **自定义 Resource**（`LevelData` / `TimeEntityData` / `TimepointDef` / `StateFrame`），由 `tools/gen_level_res.gd` 从代码化真值表 `Level01Def` 序列化为 `levels/level_01_data.tres`；类型安全、可 inspector 填表 |
| 物理 | 不用实时物理；移动/阻挡用**离散网格占用判定**（确定性、可 headless） |
| 过渡表现 | 切时刻 0.35 s 冷却 + 全局色调 `ColorRect` + 光照角度重绘 + 粒子替换 |
| 测试 | headless 断言（`--headless --script res://tests/test_main.gd`）；逻辑层零 `Node` 依赖即可测 |

**Godot 4.7 实测结论（不臆造 API，全部跑过）：** 见 §12.4。

### 核心机制回顾（对齐 GDD）
```
KEY:  T0 金属锭(HOT) → T1 崭新钥匙(UNLOCKS:GATE) → T2 生锈钥匙(FRAGILE) → T3 锈块(JUNK)
```
- **世界会变，手上的不变**：背包道具免疫时刻变化（冻结拾取瞬间形态）。
- **只读历史 + 玩家覆盖层**：`chain` 是策划写在真值表里的常量；玩家操作写入 `Override`；世界呈现 = `resolve_state(实体, 当前时刻)`。
- **只影响未来**：在过去动一下，未来继承；过去不受影响。

---

## 2. 场景树结构

### 2.1 主场景（`main.tscn`，根 `Node`）
```
Main (Node)
├─ TimeController (Node)            # 全局时刻/时砂/Override 栈（autoload 亦可）
├─ LevelLoader (Node)               # 加载当前 LevelResource
├─ UILayer (CanvasLayer)            # 与关卡解耦的 HUD
│  ├─ TimeRuler (Control)           # 黄铜刻度尺 + 游标 + 罗马数字 Ⅰ–Ⅳ
│  ├─ HourglassHUD (Control)        # 时砂容量/剩余（常驻）
│  ├─ BackpackHUD (Control)         # 背包 2 格（常驻）
│  ├─ HintLayer (Control)           # 3 级提示
│  └─ UndoControl (Control)         # 撤销/重置/操作时间轴
└─ HeadlessHarness (Node)           # 仅测试构建启用：跑逻辑断言
```

### 2.2 关卡场景（`levels/level_01.tscn`，根 `Node2D`）
```
Level01 (Node2D)                    # LevelManager 挂载
├─ GridLayer (Node2D)               # 网格地板/墙（程序化）
├─ Environment (Node2D)             # 静态背景（程序化绘制，全时刻共用）
├─ Entities (Node2D)                # 所有 TimeEntity 容器
│  ├─ KEY / WEIGHT / VINE ...       # TimeEntity 派生
├─ DerivedLayer (Node2D)            # 派生状态：PLATE / GRATE（不进 Override 层）
└─ LevelManager (Node)              # 关卡逻辑：build / snapshot / deadlock
```

### 2.3 道具节点（`TimeEntity` 派生，挂 `Entities/`）
```
TimeEntity (Node2D)
├─ _draw() 程序化渲染当前 StateFrame（读 resolve 结果，剪影守恒）
└─ 具体道具（key.gd / weight.gd / vine.gd ...）
```

### 2.4 UI 层（`Control` 系）
UI **只订阅信号、只读状态**，不持有游戏真相；用户操作经 UI → 调 `TimeController` 公开方法。

---

## 3. 核心类与职责（GDScript 风格签名，可照抄）

> 逻辑类**不继承 Node 也可测**（`RefCounted` 或纯数据）；渲染部分才继承 `Node2D`。签名对齐 GDD §3.2。

### 3.1 `StateFrame`（状态四元组，纯数据，`RefCounted`）
```gdscript
class_name StateFrame
extends RefCounted

const POS_VOID := Vector2i(-1, -1)

var form: StringName = &""          # 形态 ID：INGOT / KEY_NEW / KEY_RUSTY / RUST_LUMP ...
var pos: Vector2i = POS_VOID        # 网格坐标；POS_VOID = 该时刻不存在于世界
var available: bool = false         # 是否可被玩家持取
var tags: PackedStringArray = []    # 交互标签（见 §3.6 标签表）
var note: String = ""               # 可选叙事条目 ID

func duplicate_frame() -> StateFrame
func to_dict() -> Dictionary
static func from_dict(d: Dictionary) -> StateFrame
```

### 3.2 `TimeEntity`（带只读状态链的道具，GDD §3.2）
```gdscript
class_name TimeEntity
extends Node2D   # 渲染需要；可测性靠"状态与绘制分离"（状态存于 chain，见下）

@export var id: StringName                 # &"KEY"
@export var display_name: String           # "钥匙"
@export var anchored: bool = false         # 锚定：不可被玩家移动/取走，且不受 Override 影响
@export var silhouette: StringName         # 剪影资源 ID（跨时刻恒定，硬约束 P1/视觉锚点2）
@export var chain: Array[StateFrame]       # 长度 == TIMEPOINTS.size()，索引即 t（只读常量）

var _applied: StateFrame = null            # 运行时：当前已 resolve 的帧（渲染读它）

func base_frame(t: int) -> StateFrame      # 只读链取值（不叠加 Override）
func get_resolved(t: int) -> StateFrame    # = resolve_state(self, t)（纯函数，§3.7）
func apply_resolved(s: StateFrame) -> void # 渲染+占用唯一入口（幂等）
func _draw() -> void                       # 读 _applied，剪影守恒绘制
```

### 3.3 `Override`（玩家写入的覆盖记录，GDD §3.2）
```gdscript
class_name Override
extends RefCounted

var t_index: int                 # 写入发生在哪个时刻
var entity_id: StringName
var field: StringName            # &"pos" | &"form" | &"available" | &"removed"
var value: Variant
var propagate: StringName        # &"forward"（默认）| &"none"
var seq: int                     # 全局递增序号：撤销 + "后写覆盖先写"
var parent_seq: int = -1         # 派生自哪条 forward 记录；撤销父记录时级联删除子记录
```

### 3.3b `ActionRecord`（操作日志项，时砂/撤销的真相源，GDD §5.1）
```gdscript
class_name ActionRecord
extends RefCounted

enum Type { SHIFT, TAKE, USE, PLACE }   # 记入 action_log 的动词（观察/回溯不入账）
var type: Type
var from_t: int = -1             # 仅 SHIFT 用（算 |Δt|）
var to_t: int = -1               # 仅 SHIFT 用
var seq: int                     # 与 Override 共享的全局序号（可关联派生 Override）
# action_log = 未被撤销的操作序列；时砂 = cap - Σ|from_t-to_t|(SHIFT)
# 撤销 = 从 action_log 弹记录（含其派生 Override），时砂自动回来，无"退还"逻辑
```

### 3.4 `TimeController`（全局时刻/时砂/Override 栈，唯一写者）
```gdscript
class_name TimeController
extends Node   # autoload；逻辑部分可脱离 Node 单测

# --- 信号 ---
signal moment_changed(t: int)                # 当前时刻切换
signal hourglass_changed(left: int, cap: int)
signal backpack_changed()                    # 背包内容变化
signal override_added(o: Override)
signal deadlock_detected()                   # 死局（非 Game Over，见 §3.8/§7）
signal goal_reached()                        # 通关
signal history_changed(can_undo: bool)

# --- 状态 ---
var current_t: int = 0                       # 当前时刻索引
var hourglass_cap: int = 12                  # 时砂容量（level_01=12）
var action_log: Array[ActionRecord] = []     # 未被撤销的操作序列（时砂/撤销的唯一真相源）
var overrides: Array[Override] = []          # 覆盖日志（按 seq 升序）
var backpack: Array[BackpackItem] = []       # 背包（时间之外，见 §3.5）
var _seq: int = 0                            # 全局序号分配器
var _transitioning: bool = false             # 0.35s 冷却中，吞输入
# ⚠️ 时砂不是可变计数器，而是 action_log 的派生量（GDD §5.1）；无 hourglass:int 字段

# --- 时刻/关卡 ---
func set_level(level: LevelResource) -> void
func get_timepoints() -> Array                # TimepointDef 列表
func is_t_unlocked(t: int) -> bool

# --- 时砂（派生量，GDD §5.1）---
func sand_remaining() -> int                  # = cap - Σ|from_t-to_t|（遍历 action_log 中 SHIFT）
func sand_spent() -> int                      # 已消耗（派生）
# 无 spend_sand/refund_sand：撤销=从 action_log 弹记录，时砂自动回来

# --- 切换（走完整管线 §5）---
func shift(delta: int) -> void                # 上一刻/下一刻（A/D）；spent>cap 时输入层拒绝
func goto_t(t: int) -> void                   # 跳到指定时刻（刻度尺点击）
func can_shift(delta: int) -> bool            # sand_remaining>=|Δt| & 未锁 & 非冷却

# --- 动词（5 个，GDD concept §5）---
func verb_take(entity: TimeEntity) -> bool    # 持取（含放置/推移）
func verb_use(target: Node) -> bool           # 使用（开锁/拔藤/扳闸/压板）
func verb_observe() -> void                   # 观察/残影叠加（Tab 长按）
func verb_undo() -> void                      # 单步撤销（Z）/时间轴/重置

# --- Override 与求解 ---
func add_override(o: Override) -> void        # seq++、登记、forward 传播（§3.7）
func resolve_state(entity: TimeEntity, t: int) -> StateFrame   # ★纯函数心脏（§3.7）
func recompute_derived(t: int) -> void        # 重算压力板/闸门等派生状态

# --- 撤销/重置 ---
func undo_step() -> void                      # 弹最大 seq + 级联删 forward 子记录
func undo_to(seq: int) -> void                # 时间轴撤销到某历史节点
func reset() -> void                          # 清空 action_log + overrides（时砂派生自动归满）
```
**职责：** 唯一持有 `current_t` / `action_log` / `overrides` / 背包；切换与动词驱动管线；维护 `seq`/`parent_seq`；广播信号。**不直接操作节点**——通过信号通知订阅者。时砂不落字段，由 `sand_remaining()` 派生。

### 3.5 `BackpackItem`（背包项，时间之外，GDD §4.3/§5 L2）
```gdscript
class_name BackpackItem
extends RefCounted
var entity_id: StringName        # 逻辑身份
var form: StringName             # 拾取瞬间冻结的形态（切时刻不变）
var tags: PackedStringArray      # 冻结形态的标签（用于 UNLOCKS: 等判定）
# 背包不参与 resolve；持有 = {entity_id, form}
```

### 3.6 标签表（MVP 全量，GDD §3.4）—— 硬规则
| 标签 | 作用 | 消费者 |
|---|---|---|
| `UNLOCKS:<door_id>` | 可对指定门 USE 开锁 | 门 |
| `PRESSER` | 放压力板上触发 | 压力板→闸门 |
| `BLOCKING` | 占格不可通行 | 寻路 |
| `HOT` / `IMMOVABLE` / `OCCLUDED` | 不可取，反馈原因 | 持取（+渲染） |
| `TOO_THICK` | 不可 USE 清除 | 使用 |
| `PULLABLE` | 可 USE 拔除 | 使用 |
| `FRAGILE` | USE 于门时折断（一次性负反馈） | 门 |
| `JUNK` | 无用途，仅供叙事 | — |

> **硬规则（GDD §3.4 / level §5.2）**：`IMMOVABLE` / `OCCLUDED` / `HOT` **只影响「玩家能否持取」，绝不影响「占位/压感/阻挡」**。砝码在压力板上锈死，机关照样开着。**必须在代码注释与 GDD 同时写明**，否则 level_01 直接不可解。

### 3.7 `resolve_state` —— 纯函数心脏（GDD §3.3，直接照抄）
```gdscript
func resolve_state(entity: TimeEntity, t: int) -> StateFrame:
    var s: StateFrame = entity.chain[t].duplicate_frame()
    if entity.anchored:
        return s                                  # 锚定物只读，玩家无法改写
    var latest: Dictionary = {}
    for o in overrides:                            # overrides 按 seq 升序
        if o.entity_id != entity.id: continue
        if o.t_index > t: continue                 # 未来写入不影响过去（核心断言点！）
        latest[o.field] = o.value                  # 后写覆盖先写
    for f in latest.keys():
        s.set(f, latest[f])
    return s
```
**forward 传播实现**：`add_override(o)` 时，若 `propagate == "forward"`，则为所有 `t > o.t_index` 且该时刻 `chain[t].form ≠ VOID` 的时刻**各生成一条派生 Override**（`parent_seq = o.seq`）。撤销父记录时按 `parent_seq` 级联删除。

### 3.8 派生状态（压力板/闸门，GDD §6.2，**不进 Override 层**）
```gdscript
# 派生：实时判定，每次重算，不落 Override
func plate_pressed(t: int) -> bool:
    for e in level.entities:
        var s := resolve_state(e, t)
        if s.pos == Vector2i(6, 3) and s.tags.has(&"PRESSER"):
            return true
    return false
func grate_open(t: int) -> bool:
    return plate_pressed(t)
```

### 3.9 `PuzzleGoal` / 死锁判定（GDD §7.1）
```gdscript
class_name PuzzleGoal
extends Node
@export var requirements: Array[Dictionary]   # 例：[{tag:"UNLOCKS:GATE", target:"GATE"}]
func check(world: WorldSnapshot) -> bool      # 通关判定（纯谓词）

# 通用死锁谓词（非 Game Over，仅"死局"提示）
func is_deadlock() -> bool:
    for req in level.requirements:
        var satisfiable := false
        for t in unlocked_timepoints:
            var tags := 背包内全部 form 的 tags
            for e in level.entities:
                tags += resolve_state(e, t).tags
            if req.tag in tags: satisfiable = true
        if not satisfiable: return true
    return false
```
**职责：** 通关与死局判定完全由**纯谓词**构成，输入快照输出布尔，天然可单测。level_01 经设计**无真死局**。

### 3.10 `LevelResource` / `TimepointDef`（关卡数据，Resource）
```gdscript
class_name TimepointDef
extends Resource
@export var id: StringName       # &"T2_RUST"
@export var index: int           # 2
@export var label: String        # "锈时·昏"
@export var roman: String        # "Ⅲ"（色盲安全主标识）
@export var tint: Color
@export var light_angle: float   # 光照角度（度）
@export var ambient_sfx: String
@export var particle: String     # SPARK / DUST / RUST / ASH

class_name LevelResource
extends Resource
@export var level_id: StringName              # &"L01_FORGE_HALL"
@export var timepoints: Array[TimepointDef]   # 长度 N，索引即 t
@export var start_t: int = 2
@export var unlocked: Array[int] = [0,1,2,3]
@export var hourglass_cap: int = 12
@export var backpack_cap: int = 2
@export var entities: Array[TimeEntityResource]  # 道具状态链
@export var grid_size: Vector2i               # (10, 5)
@export var player_start: Vector2i            # (2, 3)
@export var win: Dictionary                   # {t:2, pos:(8,1)} 出口胜利点
```

### 3.10b `TimeEntityResource`（实体能力定义，与 StateFrame 分离）
```gdscript
class_name TimeEntityResource
extends Resource
@export var id: StringName                    # &"PLATE"
@export var display_name: String
@export var anchored: bool = false            # 锚定：不受 Override 影响
@export var solid: bool = false               # 是否阻挡（砝码/台/炉 true；钥匙 false 可跨过）
@export var is_lock: bool = false             # 是否锁具（可被 USE 开锁）
@export var is_receptacle: bool = false       # ★ 容器格：PLACE 的吸附目标（GDD §6.2.1）
@export var silhouette: StringName            # 剪影资源 ID（跨时刻恒定）
@export var writable_fields: PackedStringArray  # 可被 Override 写入的字段
@export var chain: Array[StateFrame]          # 只读状态链（长度 == 时刻数）
```
> **`is_receptacle` 是实体能力，不是时刻状态** → 与 `anchored/solid/is_lock` 同级，**不进 `StateFrame.tags`**（tags 逐时刻变化，容器性不随时间变，放进 tags 要在 N 帧重复写易漏）。关卡 1 仅 `PLATE=true`。放置目标选择算法见 GDD §6.2.2，验收 P1–P6。

### 3.11 `LevelManager`（关卡管理器）
```gdscript
class_name LevelManager
extends Node
func build_world(level: LevelResource) -> void     # 读 Resource → 生成 TimeEntity 节点 → 登记
func get_snapshot(t: int) -> WorldSnapshot          # 收集所有 entity 的 resolve 结果 + 派生
func check_win(t: int, player_pos: Vector2i) -> bool
func is_deadlock() -> bool                          # 转调 §3.9
```

### 3.12 `WorldSnapshot`（某时刻全量态，`RefCounted`）
```gdscript
class_name WorldSnapshot
extends RefCounted
var t: int
var entities: Dictionary        # {entity_id: StateFrame}
var derived: Dictionary         # {plate_pressed, grate_open, ...}
func to_dict() -> Dictionary
static func from_dict(d: Dictionary) -> WorldSnapshot
```

---

## 4. 时刻切换管线（GDD §6.1 判定顺序 + §2.3 反馈）

`TimeController.shift(delta)` / `goto_t(t)` 触发，**严格有序**：

1. **输入接收 + 冷却校验**：`_transitioning` 为真则吞输入；`can_shift` 检查 `sand_remaining() >= |Δt|` & 时刻锁。
2. **时砂预检（派生量，GDD §5.1）**：`sand_spent() + |Δt| > cap` → **输入层直接拒绝**（"沙漏空了"反馈，到头撞刻度 + 卡住音效，非静默失败）。**不手动扣砂**——切换成功后向 `action_log` 追加一条 `SHIFT(from_t,current_t)`，时砂由 `sand_remaining()` 派生。
3. **记撤销点**：本次切换作为一条 `ActionRecord`（含 `from_t/to_t`，关联后续 Override 的 seq）。
4. **推进当前时刻**：`current_t = target`。
5. **全量 resolve（纯函数）**：对每个 `TimeEntity` 调 `resolve_state(e, target)` 组装 `WorldSnapshot`。**此步不触碰节点**。
6. **重算派生状态**：`recompute_derived(target)` → 压力板/闸门。
7. **应用（幂等）**：每个 `TimeEntity.apply_resolved(snapshot.entities[id])` → 更新 `_applied`、`queue_redraw()`、更新网格占用表。
8. **玩家格校验**：若目标时刻玩家脚下格被阻挡，推到最近可通行格并提示（GDD §2.4）。
9. **死锁重算**：`is_deadlock()`；命中则 `deadlock_detected`（沙漏变灰 + 轻提示，**非失败画面**）。
10. **通关判定**：`check_win(target, player_pos)`；命中则 `goal_reached`。
11. **过渡表现（0.35 s）**：Tween 驱动全局 shader 参数（色调插值 + 光照角度旋转）+ 粒子替换 + 环境音交叉淡入 + 刻度尺游标滑动；各实体 0.25 s 变形动画（非瞬移）。**期间 `_transitioning = true`。**
12. **UI 刷新**：UI 订阅 `moment_changed` / `hourglass_changed(sand_remaining,cap)` / `backpack_changed` / `history_changed` 更新。**UI 是被通知方。**

> **残影叠加（Observe 长按）** 是渲染层功能，不进本管线：渲染层对视野内每个实体 `resolve_state(e, t)`（**含 Override**）渲染 `t ∈ 已解锁时刻`（当前时刻层不画），跳过 `POS_VOID`/`removed`，背包物品不画残影。仅在 Override 写入/切时刻时置脏重算，不每帧 resolve（GDD §2.5）。

**管线要点：** 步骤 5-7 是"resolve → 派生 → 应用"三段，resolve 与应用分离是**可逆性**的关键。切换**不改变玩家坐标**（共用一套网格）。

---

## 5. 状态求值模型：只读链 + Override 覆盖层 + `resolve_state` 纯函数

**选择（对齐 GDD §4.1）：只读历史链 + 玩家 Override 覆盖层，`resolve_state` 纯函数求值。**

- `chain` 是**预设只读常量**（策划写真值表），**不做物理模拟、不做推导**。
- 玩家操作写入 `Override`（`add_override`），默认 `propagate = "forward"`。
- 世界呈现 = `resolve_state(实体, 当前时刻)`：取 `chain[t]`，叠加所有 `t_index <= t` 的 Override（按 `seq` 后写覆盖先写）。

**为什么这是"悖论免疫力"而非缺陷：** 因为历史是常量、Override 是有限日志、resolve 是确定性纯函数 → **任何时刻状态都可计算，系统绝不崩溃**。不存在"算不出来的悖论"；悖论只表现为**关卡死局**（由 `is_deadlock` 检测），不表现为系统错误。

**对比我早期草案（已废弃）：** 我曾设想"per-entity 静态表 + 全量重算 + 因果/悖论检测阶段"。GDD 的模型更优且更简单——**用覆盖层表达玩家能动性，用 resolve 确定性取代复杂的因果检测**。本架构据此重写。

**为什么是纯函数：** 可逆（撤销 = 弹 Override 再 resolve）、无副作用（resolve 阶段不碰节点）、可测试（`resolve_state` 输入 (实体,时刻,日志) 输出帧，headless 直接断言，GDD §9 验收 1/2）。

---

## 6. 数据流与信号总线（单向，避免循环依赖）

```
玩家输入 ──► UI 层 ──► TimeController（唯一写者：current_t / 时砂 / overrides / 背包）
                          │
     ┌────────────┬───────┼────────┬─────────────┬────────────┐
     ▼            ▼       ▼        ▼             ▼            ▼
 moment_changed  hourglass  backpack  override_added  deadlock  goal_reached
     │            │        │           │            │           │
     ▼            ▼        ▼           ▼            ▼           ▼
 TimeEntity   HourglassHUD  Backpack  (调试/残影)  HintLayer   LevelManager
 重绘+占用    HUD         HUD                     (死局提示)  (过关)
 TimeRuler
```

- **唯一写者原则**：只有 `TimeController` 改 `current_t`/时砂/`overrides`/背包；`TimeEntity` 只读 resolve + 幂等应用；派生状态每次重算不落层；UI 只发请求 + 订阅信号。
- **信号订阅（谁发 → 谁订）**：
  - `moment_changed` → `TimeEntity`（重绘）、`TimeRuler`（游标/罗马数字）、环境层（shader/粒子/音）。
  - `hourglass_changed` → `HourglassHUD`。
  - `backpack_changed` → `BackpackHUD`。
  - `override_added` → 残影/调试视图（可选）。
  - `deadlock_detected` → `HintLayer`（沙漏变灰 + 轻提示）。
  - `goal_reached` → `LevelManager`（过关）、`HintLayer`。
  - `history_changed` → `UndoControl`（可用态）。
- **不用全局 EventBus 字符串派发**：直接用类型化信号，编译期可查，lean 下更简单。

---

## 7. 撤销/重置系统（GDD §7.2 + §5.1）

- **真相源**：`action_log`（未撤销的操作序列）+ `overrides`（覆盖层，每条带 `seq` + `parent_seq`）。
- **时砂是派生量（GDD §5.1，硬规则）**：`sand_remaining() = cap - Σ|from_t-to_t|(action_log 中 SHIFT)`。**不存可变计数器、无 spend/refund 逻辑**。撤销 = 从 `action_log` 弹记录 → 时砂**自动**回来（切换消耗与操作消耗同源同算，无"分开结算"）。
- **单步撤销 `Z`**：弹出 `seq` 最大的一条 `ActionRecord`，并**按 `parent_seq` 级联删除其派生的 forward Override 子记录**（否则未来态残留）。
- **时间轴撤销**：长按 `Z` 打开操作时间轴，拖到任意历史节点（含时刻与位置一并回滚）。
- **重置时刻**：清空全部 `action_log` + `overrides`，回初始时间线（免费、不限次数）。
- **硬保证（防软锁死，GDD §5.1）**：**撤销与「重置时刻」永远免费、永远可用，不受时砂约束**。时砂耗尽只拒绝"新的切换"，绝不阻止撤销/重置。
- **时砂永不负数**：`spent > cap` 时 SHIFT 在输入层被拒（构造上不可能超限，无需 clamp）。
- **幂等保证**：撤销后 `resolve_state` 重新求值即复原，无累积漂移；GDD §9 验收 3/4：撤销 10 次后与初始态逐字段一致、时砂无负数。

---

## 8. 存档（lean 最小化）

- **本关持久化仅存**：`level_id` + `current_t` + `action_log`（操作序列，含 SHIFT 的 from/to）+ `overrides`（覆盖日志，含 seq/parent_seq）+ 背包 + 少量 flags。
- **不存**：道具链（Resource 常量）、时砂（由 action_log 派生）、派生状态（可重算）、渲染状态。
- **格式**：`ConfigFile` / `JSON`（Resource 可 `ResourceSaver`/`ResourceLoader`），单文件 `user://save.cfg`。
- **策略**：仅过关/手动存档点写入；切换不自动存档。lean 下甚至可只做"记住上次关卡 + 时刻"。

---

## 9. 目录结构（Godot 工程）

```
D:/New test/
├─ project.godot                     # config/features=PackedStringArray("4.7")；[input] 映射（由 tools/setup_input.gd 生成）
├─ README.md                         # 怎么打开 / 怎么操作 / 怎么跑测试 / 已知限制
├─ src/
│  ├─ core/                          # ★ 零渲染依赖的逻辑层（可 headless 单测）
│  │  ├─ state_frame.gd              # StateFrame（extends Resource，便于存 .tres）
│  │  ├─ override.gd                 # Override（RefCounted）
│  │  ├─ time_entity_data.gd         # TimeEntityData（只读链 + 字段白名单）
│  │  ├─ timepoint_def.gd            # TimepointDef（表现层：roman/tint/light_angle/particle）
│  │  ├─ level_data.gd               # LevelData（关卡静态数据）
│  │  ├─ resolve.gd                  # ★ resolve_state 纯函数心脏
│  │  ├─ time_controller.gd          # ★ 唯一写者（RefCounted，无 Node 依赖）
│  │  ├─ inventory_item.gd           # InventoryItem（冻结形态 = 时间之外）
│  │  ├─ inventory.gd                # Inventory（容量 2）
│  │  ├─ hourglass.gd                # Hourglass（容量 12，耗 |Δt|，撤销返还）
│  │  ├─ grid.gd                     # Grid（离散网格 / 四邻域）
│  │  ├─ world_snapshot.gd           # WorldSnapshot（全量态 + 逐字段 diff）
│  │  └─ puzzle_condition.gd         # 通关谓词 + 通用死锁谓词
│  ├─ data/
│  │  ├─ level_01_def.gd             # ★ 代码化真值表（权威，照抄关卡文档 §5）
│  │  └─ level_loader.gd             # 优先 .tres，失败回退 Level01Def
│  ├─ entities/                      # 道具（含渲染，Node2D）
│  │  ├─ time_entity.gd              # 基类（只读状态 + 幂等 apply + 残影）
│  │  ├─ prop_art.gd                 # ★ 全程序化绘制，剪影守恒
│  │  └─ props/                      # key/weight/vine/gate/grate/plate/exit/stand/forge .gd
│  ├─ level/
│  │  ├─ level_manager.gd            # 建世界 + 5 动词接线 + 派发渲染
│  │  └─ environment_layer.gd        # 地板/墙/粒子/光照角度
│  ├─ ui/
│  │  ├─ hud.gd                      # CanvasLayer 根（撤销/重置/提示按钮）
│  │  ├─ time_ruler.gd               # 黄铜刻度尺 + 罗马 Ⅰ–Ⅳ + 游标（可点击跳转）
│  │  ├─ hourglass_hud.gd            # 时砂（常驻）
│  │  ├─ backpack_hud.gd             # 背包 2 格（常驻，显示冻结形态）
│  │  ├─ hint_layer.gd               # 三级提示 + 反馈文案
│  │  └─ ui_font.gd                  # SystemFont（中文 CJK，零字体文件依赖）
│  └─ main/
│     ├─ main.gd / main.tscn         # 入口
├─ levels/
│  └─ level_01_data.tres             # LevelData 实例（由 tools/gen_level_res.gd 生成）
├─ tools/
│  ├─ gen_level_res.gd               # 真值表 → .tres
│  └─ setup_input.gd                 # 键位 → project.godot [input]
├─ tests/                            # headless 断言（183 条，全绿）
│  ├─ test_main.gd                   # 入口（extends SceneTree）
│  ├─ harness.gd                     # 断言器
│  ├─ test_resolve_pure.gd           # 验收 1 / 8：纯函数 + 绝不向过去传播
│  ├─ test_undo_restore.gd           # 验收 7：撤销复原 + 时砂账本
│  ├─ test_immovable_pressure.gd     # 验收 6：形态锁不影响占位/压感
│  ├─ test_level_01_solvable.gd      # 验收 1/2/3/4 + A5 携带冻结
│  ├─ test_deadlock_and_win.gd       # 验收 5：仅 T2 通关 + 死锁谓词
│  ├─ test_scene_wiring.gd           # 场景装配冒烟
│  └─ README.md
├─ docs/
│  ├─ architecture/architecture.md
│  ├─ architecture/adr/ADR-001~006
│  └─ architecture/tech_checklist.md
└─ design/                           # DS-101 产出（真相源）
```

**关键分层：** `src/core/` + `src/data/` **禁止**引用 `Node2D`/渲染类型，确保 headless 可测；`src/entities/` 才含绘制。这是硬约束 §0.1 的落地（ADR-004）。

---

## 10. 与 GDD 的对齐状态（主理人裁决已全部落地）

| # | 事项 | 结论 | 来源 | 落地位置 |
|---|---|---|---|---|
| 1 | 时刻标识 | **整数索引 `t ∈ [0, N-1]` 是权威**；`id`/`label`/`roman`/`tint`/`light_angle`/`particle` 只是表现层 | GDD §2.1 | `TimepointDef` + `TimeController.current_t: int` |
| 2 | 时间模型 | 离散时刻切换、全局单一时刻 | GDD §2 ✅ | `TimeController.shift/goto_t` |
| 3 | 状态模型 | **只读链 + Override 覆盖层 + resolve 纯函数**（"per-entity 状态表"已废弃） | GDD §3/§4 ✅ | `Resolve.resolve_state` |
| 4 | 形态链 | `StateFrame`（form/pos/available/tags/note + removed/open），按 t 索引 | GDD §3.2 ✅ | `TimeEntityData.chain` |
| 5 | 携带穿越 | **允许，且是核心（A5）**：手持物免疫时刻变化。背包用 `InventoryItem`（entity_id + 冻结 form + 冻结 tags）表示，**与 resolve 无关**，容量 2 | GDD §4.3/§5 L2 ✅ | `inventory.gd` / `inventory_item.gd` |
| 6 | 只向未来传播 | `o.t_index > t` 的 Override 绝不参与求值（显式 `continue` + 断言 + 专项测试） | GDD §4.2 ✅ | `resolve.gd` |
| 7 | 时砂 Hourglass | 容量 12，切换消耗 `|Δt|`，耗尽不可切换，撤销全额返还，HUD 常驻 | GDD §5 L1 ✅ | `hourglass.gd` + `hourglass_hud.gd` |
| 8 | 派生状态 | `PLATE.pressed(t)` / `GRATE.open(t)` 是**实时派生的纯谓词**，**不写入 Override 层** | 关卡 §5.2 ✅ | `TimeController.plate_pressed/grate_open` |
| 9 | 形态锁语义 | `IMMOVABLE`/`OCCLUDED`/`HOT`/`TOO_THICK` **只**影响能否持取/使用，**绝不影响占位与压感**（代码注释已写） | GDD §3.4 ✅ | `time_controller.gd` + `test_immovable_pressure.gd` |
| 10 | 死锁谓词 | GDD §7.1 伪代码已实现；本关经设计永不为真（用伪造需求反向验证谓词非空实现） | GDD §7.1 ✅ | `puzzle_condition.gd` |
| 11 | 通关判定 | 纯谓词：在 `win_t` 站上 `win_pos` 且该格未阻挡 | GDD §7.1 ✅ | `PuzzleCondition.check_win` |
| 12 | 因果检测 | **不做因果物理模拟**；悖论免疫靠 resolve 确定性 | GDD §4.1 ✅ | — |

> **无遗留待确认项。** 与 GDD 的 2 处实现取舍、4 项补齐与 Godot 4.7 实测坑见 §12。

---

## 11. 2D / 3D 与美术资源建议（结论）

**结论：2D 俯视网格。** 理由（与 concept_doc §8 一致）：
1. **解密游戏**：真值表 + 网格最好实现，最易验证可解性；视角固定无纵深需求。
2. **零外部美术资源**：`ColorRect`/`Polygon2D`/`_draw()` 程序化绘制即可全覆盖；**剪影守恒**（同一道具各形态共用剪影，只变材质/侵蚀层级）是硬约束，程序化绘制反而更易保证跨时刻一致。
3. **可 headless 验证**：逻辑层（`src/core/`+`src/data/`）与 `Node2D` 渲染天然分层，headless 断言无阻力。3D 引入光照/相机/深度，收益为零。

**美术策略：全程序化绘制**（详见 `tech_checklist.md`）——网格地板 `_draw()`、道具 `_draw()` 剪影 + 侵蚀细节、罗马刻度用**线段绘制**（规避内置字体缺 U+2160 字形）、中文 `Label` 用 `SystemFont`（OS 自带，零字体文件）、全局 `ColorRect` 做时刻色调。**零外部美术依赖。**

---

## 13. 验证与测试（Phase 4 实际跑通）

```bash
GD="C:/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

# 1) 资源导入 + 全量脚本编译检查（输出无 ERROR = 通过）
"$GD" --headless --path "D:/New test" --import

# 2) 主场景能否真正启动（输出空 + 有 [game] ready 行 = 通过）
"$GD" --headless --path "D:/New test" --quit-after 300

# 3) headless 断言测试（退出码 0 = 全绿）
"$GD" --headless --path "D:/New test" --script res://tests/test_main.gd
```

**实际结果（本机实测，非推演）：**
- `--import`：**0 ERROR**；17 个 `class_name` 全部注册
- 主场景启动：**0 ERROR / 0 WARNING**，打印 `[game] ready: 时刻 Ⅲ 锈时·昏 ｜ 时砂 12/12 ｜ 背包 0/2 ｜ 坐标 (2,3)`
- 断言测试：**183 PASS / 0 FAIL / 0 ERROR，退出码 0**

**门禁看两个数**：PASS/FAIL **且** 日志 `ERROR` 计数 = 0。只数 PASS 会在「属性被改名/删除」这类断裂面前假通过（技能文档 Pitfall 15）。

---

## 12. 与 GDD 对齐说明（Phase 4 主理人裁决落地）

> 本节记录 Phase 4 实现期间，主理人一致性裁决的执行结果、补齐的缺口、以及**必须让主理人知悉的两处与 GDD 的实现取舍**。

### 12.1 主理人裁决 → 执行对照

| 裁决 | 执行情况 |
|---|---|
| **裁决 1 · 时刻标识** | ✅ `TimeController.current_moment` → `current_t: int`（权威）；`TimepointDef` 保留 `roman`/`tint`/`light_angle`/`particle` 作表现层 |
| **裁决 2 · 只读链 + Override 层** | ✅ `chain: Array[StateFrame]` 只读；玩家操作只写 `overrides`；`Resolve.resolve_state()` 纯函数；`o.t_index > t` 的 `continue` 是"向过去不传播"的唯一防线，已写成显式分支并配 `test_resolve_pure` 逐字段比对 |
| **裁决 3 · 携带穿越** | ✅ 背包 = `Inventory`（容量 2）+ `InventoryItem`（冻结 `form`/`tags`），**完全不参与** `resolve_state`。测试 A5 专项：T1 取 `KEY_NEW` → 切 T2/T3 → 形态仍是 `KEY_NEW` |
| **裁决 4.1 · 时砂** | ✅ `Hourglass`（cap 12，派生量：`remaining = cap - Σ 未撤销 SHIFT 的 \|Δt\|`）+ `HourglassHUD` 常驻；耗尽后 `shift()` 在输入层拒绝并给反馈。**无 `spend`/`refund` 增量账本** —— 撤销 = 整步快照恢复，时砂随快照回滚（`refund()` 死函数已删，见 `hourglass.gd:29` 禁用注释） |
| **裁决 4.2 · 派生状态** | ✅ `plate_pressed(t)` / `grate_open(t)` 每次实时求值，**不落 Override 层** |
| **裁决 4.3 · 形态锁语义** | ✅ 已在 `time_controller.gd` 的 `TAKE_BLOCK_REASON` 上方、`is_blocked()`、`plate_pressed()` 三处写死注释；`test_immovable_pressure` 5 条断言锁死 |
| **裁决 4.4 · 死锁谓词** | ✅ `PuzzleCondition.is_deadlock()`；本关永不为真；用伪造的 `IMPOSSIBLE_TAG` 反向验证谓词**不是空实现** |

### 12.2 补齐的四个缺口（原架构缺失）

1. **时砂 Hourglass**（`src/core/hourglass.gd`）—— 原来只有 `TimeController.hourglass: int` 字段，没有资源对象与耗尽/返还语义。
2. **派生状态**（`plate_pressed` / `grate_open`）—— 原架构 §3.8 只有伪代码，现已落地且带 `removed` / `PRESSER` 判定。
3. **形态锁语义的代码级固化** —— 原架构只在§3.6 表格里提了一句，现已在三处关键函数写进注释。
4. **死锁谓词** —— 原架构 §3.9 只有伪代码，现已落地可测。

### 12.3 两处与 GDD 的实现取舍（**需主理人裁决确认**）

#### D1 · 锚定物（`anchored`）的可写字段
GDD §4.3 说"锚定物不进覆盖层，玩家永远改不动（门…）"，但 GDD §6 与关卡文档真值表又说"门（GATE）✅ 锚定，开启状态是**覆盖写入** forward"、"藤蔓（VINE）✅ 锚定，`PULLABLE` 可被 USE 清除（写入 `removed = true`）"。**两条直接冲突。**

**实现取舍**：`anchored` 的语义收窄为"**玩家无法持取/搬运**"，另加 `writable_fields: PackedStringArray` 白名单字段：
- 自由道具（KEY/WEIGHT）→ `["pos","form","available","removed"]`
- `GATE` → `["open"]`
- `VINE` → `["removed"]`
- 其余锚定物 → `[]`

`Resolve.resolve_state` 在叠加 Override 前先查白名单。**关卡可解性依赖这个取舍**（否则门永远开不了）。

#### D2 · 放置（Place）**不**冻结形态
GDD §4.3 C3 说"放回世界 = C1（pos）+ C3（form = 携带形态）"。但关卡文档 §9.1 与 §5.2 明确要求"**砝码放上压力板后，T2 形态仍为 `WEIGHT_SEIZED`（锈死）**"，且验收清单第 8 条的用例前提正是"砝码在压力板上且 T2 形态为 `IMMOVABLE`"。若按 GDD C3 冻结形态，该验收用例的前提**无法成立**。

**实现取舍**：`place()` **只写 `pos`**，物件放回世界后继续走它自己的时间线；**冻结只发生在背包里**（A5 的核心就是"手上的不变"，由 `InventoryItem` 承担，不依赖放置）。
- 副作用：本关走标准解法时，压力板上的砝码在 T2 是 `WEIGHT_SEIZED`、T3 是 `WEIGHT_BURIED` —— 与关卡文档完全吻合。
- 开锁路径（`use` 于锁具）仍按"钥匙留在锁孔"写入 `pos` + `form`（携带形态），避免"断钥匙卡在锁孔里"的怪异画面。
- `place()` 预留 `carry_form` 语义开关，若主理人裁定要严格遵循 GDD C3，改一处即可。

#### D3 · 撤销机制：快照回滚 而非 `parent_seq` 级联删除
架构 §7 与 GDD §7.2 要求"撤销父记录时按 `parent_seq` 级联删除子记录"。实现改为**每步操作前压一整份状态快照**（`current_t`/`hourglass`/`player_pos`/`won`/`overrides`/`inventory`），撤销 = 弹栈还原。

**理由**：级联删除只能还原 Override，还原不了**时刻、时砂、背包、坐标**这四项；而这四项恰恰是验收第 7 条「撤销后与初始态逐字段一致」的检查项。快照回滚 100% 覆盖且无漂移风险；`parent_seq` 字段仍然保留在 `Override` 上，供调试与时间轴 UI 追溯父子关系。→ 见 **ADR-005**。

### 12.4 Godot 4.7.2 实测结论（不臆造 API，全部跑过）

| # | 现象 | 处理 |
|---|---|---|
| 1 | `InputMap.add_action()` **不会**写入 `ProjectSettings`（`has_setting("input/x") == false`），`ProjectSettings.save()` 持久化不到 | 必须显式 `ProjectSettings.set("input/<action>", {"deadzone":0.5,"events":[InputEvent]})` 再 `save()` → `tools/setup_input.gd` |
| 2 | `ProjectSettings.save()` 在 4.7 **不接受路径参数**（0 参）；`get()` **不接受默认值参数**（1 参） | 按实测签名调用 |
| 3 | `const ARR := [1.0, 2.0]` 推导为**未类型化** `Array`，`var x := ARR[i]` 报 `Cannot infer the type` | 显式写 `const ARR: Array[float]` 或 `var x: float` |
| 4 | 对 untyped 变量（`tc` 传参）调用方法返回 Variant，`var s := tc.resolve_state(...)` 报同样错误 | 显式 `var s: StateFrame = ...` |
| 5 | `ResourceSaver.save()` 目标**目录必须存在**（`levels/` 不存在时报 `Cannot save file`） | 先 `mkdir levels/`；`StateFrame`/`TimeEntityData` 继承 `Resource` 才能被完整序列化（含嵌套 `Array[StateFrame]`） |
| 6 | 新增 `class_name` 文件后，必须先跑一次 `--import`，否则其它脚本报 `Identifier "X" not declared` | 写进 `tests/README.md` 的跑测前置步骤 |
| 7 | GDScript **lambda 捕获是按值**的：`var won := false; f.connect(func(): won = true)` **不生效** | 标志位放进 `Dictionary`/`Array` 等引用类型 |
| 8 | GUI 版 exe 在 headless 下不输出 stdout | 一律用 `*_console.exe` |
| 9 | 内置字体无 CJK 字形；U+2160 罗马数字也可能缺字 | `SystemFont` 渲染中文；罗马刻度 Ⅰ–Ⅳ 改用 `draw_rect` 线段绘制 |

### 12.5 关卡数据一致性（照抄真值表，零改动）

`Level01Def.build()` 逐格照抄 `design/level/level_01_design.md`：
- §3 ASCII 图 → 37 格墙（外圈 + (7,1)(4,2)(5,2)(4,3)(5,3)(7,3)(8,3)）
- §4 时刻表 → 4 个 `TimepointDef`（罗马 Ⅰ–Ⅳ / 色调 / 光照角 / 粒子）
- §5.1 真值表 → 9 个实体 × 4 时刻，形态/位置/可取/标签**一字未改**
- §7 胜利条件 → `win_t = 2`，`win_pos = (8,1)`
- 唯一的数据层调整：`KEY.solid = false`（钥匙很小可跨过）。**不改这一项关卡直接不可解** —— 因为 `use` 开锁后钥匙留在门格 (4,1)，若钥匙实心会把刚打开的通路重新堵死（已由 `test_level_01_solvable` 步 5 → 步 7 的连通性锁住）。
