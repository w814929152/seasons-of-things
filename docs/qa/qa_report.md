# 关卡 01 质量门报告 · QA-501

> 关卡：《物候 / Seasons of Things》· 关卡 01《钟械工坊 · 前厅》（`L01_FORGE_HALL`）
> 范围：烟雾测试 + 可解性验证 + §11.1 放置目标选择专项（P1–P6）+ §11 九条验收清单
> 执行人：严守真（QA / 测试） ｜ 引擎：Godot 4.7.2 console（headless）
> 被测基线：`design/level/level_01_design.md` §7 / §11 / §11.1、`design/gdd/core_mechanic_gdd.md`

---

## 0. 结论速览

# 🔴 判定：FAIL

| 项 | 结果 |
|---|---|
| 自动化断言 | **291 PASS / 4 FAIL / 0 ERROR** |
| 退出码 | **1**（非 0） |
| 稳定性 | 连续 3 次运行结果**完全一致**（291/4/0），无 flaky |
| §11 九条验收清单 | 8 条通过 · **1 条未实现**（三级提示的被动阈值触发）|
| §11.1 专项 P1–P6 | 4 条通过（P1 / P4 / P5 / P6）· **2 条失败（P2 / P3）** |
| 硬规则「IMMOVABLE 不影响占位与压感」 | ✅ 通过 |
| HUD 滞后争议 | ✅ **工程侧的解释不成立**（结论见 §4），但**其背后确有另一处真实陷阱**（已定位，见 §4.3）|

**判定依据（硬门）**：关卡文档 §11.1 原文 —— *「本组不通过 = 质量门不通过，无论上面 9 条是否全绿」*。
P2 / P3 未通过 ⇒ 质量门 **FAIL**。

**但同时给出放行建议**：本缺陷**不导致硬卡死**（可撤销自救，见 §3.2 诊断），且**默认动线（从北面进入 (6,2)）是通的**（P1 / P4 / P5 全绿，端到端可通关）。修复只需改 `src/level/level_manager.gd` 的 `_do_place()` 一处。详见 §6。

---

## 1. 执行命令与真实输出

### 1.1 基线条带（我进场时先复跑一次既有套件）

```bash
GD="C:/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
"$GD" --headless --path "D:/New test" --script res://tests/test_main.gd
```

```
[SELFTEST] pass = 183   fails = 0
[SELFTEST] ALL PASS
EXIT=0
```

### 1.2 补完用例后的最终门控运行

```bash
"$GD" --headless --path "D:/New test" --import          # 新 .gd 需先导入以注册 class_name
"$GD" --headless --path "D:/New test" --script res://tests/test_main.gd
```

```
[SELFTEST] pass = 291   fails = 4
  FAIL  [§11.1 放置目标选择专项 P1–P6] P2：★ 仍落在 (6,3)（U3 容器格吸附优先于空地）  (实际=(6, 1) / 期望=(6, 3))
  FAIL  [§11.1 放置目标选择专项 P1–P6] P2：plate_pressed(T1) == true
  FAIL  [§11.1 放置目标选择专项 P1–P6] P3：★ 落在 (6,3) 而非 (6,1)（隔离走路，定位 U1 还是 U3）  (实际=(6, 1) / 期望=(6, 3))
  FAIL  [§11.1 放置目标选择专项 P1–P6] P3：plate_pressed(T1) == true
[SELFTEST] HAS FAILURES
EXIT=1
```

日志中 `SCRIPT ERROR` 计数 = **0**（`tests/test_main.gd` 头部声明的门禁要求：PASS 全绿 **且** ERROR = 0）。

稳定性复核（连续 3 次）：

```
run1 EXIT=1  pass = 291  fails = 4  ERR=0
run2 EXIT=1  pass = 291  fails = 4  ERR=0
run3 EXIT=1  pass = 291  fails = 4  ERR=0
```

### 1.3 我新增 / 修改的文件（未触碰 `src/`）

| 文件 | 动作 | 说明 |
|---|---|---|
| `tests/test_place_target_p1_p6.gd` | **新增** | §11.1 的 P1–P6 专项（走 `lm._do_place()` 真实入口，不直接喂目标格） |
| `tests/test_hud_refresh.gd` | **新增** | HUD 刷新专项 A/B/C 三组，用于裁决 HUD 滞后争议 |
| `tests/test_acceptance_11.gd` | **新增** | §11 三条未被直接断言的验收项补证（最短解 / 非色彩通道 / 提示分级） |
| `tests/test_main.gd` | **修改 2 行** | 注册上面三个套件；并新增 `await process_frame`（原因见 §5.1） |

`src/` 下**零改动**（已用 `grep`/`Read` 复核，未做任何 Edit/Write）。

---

## 2. §11 九条验收清单逐条结果

| # | 验收项 | 判定 | 证据（真实输出 / 代码依据） |
|---|---|---|---|
| 1 | 按 §7 步骤表逐步执行可通关，最少 7 步 / 2 次切换 | ✅ PASS | `test_level_01_solvable` 十步重放全绿；我另补最短解计数：`★ §11-1：主动操作数 = 7（切换 T2→T1 → 持取 KEY → 开锁 GATE → 持取 WEIGHT → 拔除 VINE → 放置 WEIGHT → 切换 T1→T2）(实际=7 / 期望=7)`、`★ §11-1：切换次数 = 2`、`★ §11-1：时砂 12 → 10（耗 2）`、`★ §11-1：7 步 / 2 切换后通关` |
| 2 | 4 个时刻关掉色彩后仍可分辨 | ⚠️ 条件通过 | 4 条**非色彩**通道已实现并断言通过：罗马刻度 `["Ⅰ","Ⅱ","Ⅲ","Ⅳ"]`、光照角度 `[15.0,90.0,300.0,350.0]`、粒子 `["SPARK","DUST","RUST","ASH"]`、亮度 `[0.78,1.0,0.66,0.5]`（T1>T0>T2>T3）。**第 5 条通道（环境音）数据已就绪但无音频实现**（README 已知限制 #1）。设计要 ≥3 条 ⇒ 满足。**待人工盲测确认观感** |
| 3 | T2 用锈钥匙 → 折断，且 T1 钥匙仍存在 | ✅ PASS | `★ 验收2：T1 钥匙仍为 KEY_NEW` / `T1 钥匙仍在 (3,2)` / `T1 钥匙仍可取` / `T1 钥匙仍带 UNLOCKS:GATE` / `★ T0 仍是金属锭` |
| 4 | 砝码 T1 上板 → 切 T2 闸门保持开启 | ✅ PASS | `P4：★ resolve_state(WEIGHT,T2).pos == (6,3)`、`P4：★ plate_pressed(T2) == true`、`P4：★ grate_open(T2) == true`、`P4：闸门格 (7,2) 在 T2 可通行` |
| 5 | 藤蔓 T1 拔除 → T2 的 (5,1) 可通行 | ✅ PASS | `★ 验收4：T2 藤蔓已清除（正向传播）`、`★ 验收4：T2 的 (5,1) 可通行` |
| 6 | T1 站 (8,1) 不通关；T2 可通关 | ✅ PASS | `验收5：站在 (8,1) 于 T0/T1/T2/T3 不通关/不通关/通关/不通关`；`T1 出口 NO_HANDLE → 阻挡`、`T3 出口 COLLAPSED → 阻挡`、`T0 出口 NOT_BUILT → 阻挡`、`T2 出口 INTACT → 可通行` |
| 7 | 砝码在板上且 T2 为 `IMMOVABLE` → 板仍 pressed | ✅ PASS | `★ 验收6：T2 形态仍是锈死 SEIZED`、`T2 带 IMMOVABLE`、`★ 验收6：压力板仍 pressed（形态锁不影响压感）`；另 `T3 带 OCCLUDED` → `★ T3 压力板仍为 pressed（OCCLUDED 不影响压感）`；`T0 带 HOT` → `T0 也带 PRESSER` |
| 8 | 撤销 10 次与初始态逐字段一致；时砂无负数 | ✅ PASS | `已执行操作数 = 10`、`连续撤销 10 次全部成功`、`撤销后与初始态逐字段一致`（`diff=` 为空）、`撤销全额返还时砂 → 12`、`时砂最终耗尽为 0`、`时砂耗尽后仍可撤销` |
| 9 | 三级提示按阈值触发，冷却生效 | ❌ **未实现** | **代码审查结论**：`src/` 全量 grep 无任何 90/180/360 s 计时器或 45 s 冷却实现；`LevelManager._do_hint()`（`src/level/level_manager.gd:274-279`）只做「按 H 逐级 +1」，无计时、无冷却、无被动触发。已自动化的部分是：3 级文案与设计稿 §9.3 **完全一致**、级别 1/2/3 齐备。与 README 已知限制 #4 一致 |

### 2.1 硬规则专项复核（主理人指定重点）

> `IMMOVABLE` / `OCCLUDED` **只影响能否持取，不影响占位与压感**

| 时刻 | 形态 | 形态锁标签 | 是否可取 | 板是否 pressed | 结果 |
|---|---|---|---|---|---|
| T0 | `MOLTEN` | `HOT` | 否 | — | `T0 也带 PRESSER` ✅ |
| T1 | `WEIGHT_OK` | — | 是 | true | `P1：plate_pressed(T1) == true` ✅ |
| T2 | `WEIGHT_SEIZED` | `IMMOVABLE` | **否** | **true** ✅ | `★ 压力板仍为 pressed —— 形态锁不影响压感` |
| T3 | `WEIGHT_BURIED` | `OCCLUDED` | **否** | **true** ✅ | `★ T3 压力板仍为 pressed（OCCLUDED 不影响压感）` |

**结论：硬规则成立。** `plate_pressed()`（`src/core/time_controller.gd:403-413`）只看 `pos == plate_pos && tags.has("PRESSER")`，**完全不读 `available` 或形态锁标签** —— 实现与设计一致，无「砝码锈死了机关就不开」的 bug。
反向面也成立：`T2 锈死：持取被拒绝`（形态锁确实只作用于持取）。

---

## 3. §11.1 放置目标选择专项 P1–P6

| # | 用例 | 判定 | 实际输出 |
|---|---|---|---|
| **P1** | 从 (6,1) 走向 (6,2) 后按 Q | ✅ PASS | `P1：朝向 = 末步方向 (0,1)` → `P1：砝码落在压力板 (6,3) (实际=(6, 3))` → `plate_pressed(T1) == true` |
| **P2** | 从**南面** (6,3) 进入 (6,2) 后按 Q | ❌ **FAIL** | 朝向 `(0,-1)`、面向格是空地 `(6,1)` → **`实际=(6, 1)`，期望 `(6, 3)`**；`plate_pressed(T1)` 为 false |
| **P3** | 纯朝向构造 `_facing=(0,-1)`（隔离走路） | ❌ **FAIL** | **`实际=(6, 1)`，期望 `(6, 3)`**；`plate_pressed(T1)` 为 false |
| **P4** | 放置结果跨时刻正向传播 | ✅ PASS | `resolve_state(WEIGHT,T2).pos == (6,3)`、`plate_pressed(T2) == true`、`grate_open(T2) == true` |
| **P5** | 端到端通关，时砂 10 | ✅ PASS | `P5：★ check_win == true`、`P5：★ 时砂剩余 10（12 − 2 次相邻切换）` |
| **P6** | 朝向随走路更新 | ✅ PASS | 路径 8 格、末步方向 `(0,1)`、`到达时 _facing == (0,1)`、`面向格 = (6,3)`、`面向格上的实体 = PLATE` |

### 3.1 失败项：P2 / P3（**阻断门控的一条**）

- **等级**：Blocker（依 §11.1 硬门）；实际玩家体验影响 = Major
- **文件行号**：`src/level/level_manager.gd:228-244`，根因在第 **229** 行
- **复现步骤**：
  1. T1，铁栅已开、藤蔓已拔、手持 `WEIGHT_OK`
  2. 站上压力板 (6,3)，再走到 (6,2)（`_walk_to` 把朝向设为末步方向 `(0,-1)`）
  3. 按 `Q`
- **预期**：砝码落在压力板 (6,3)，`plate_pressed(T1) == true`
- **实际**：砝码落在空地 (6,1)，`plate_pressed(T1) == false`
- **P3 隔离结论**：不走步、直接置 `_facing=(0,-1)` 结果相同 ⇒ **不是 U1（走路更新朝向）的问题，是 U3（容器格吸附优先级）没有实现**
- **根因**：

  ```gdscript
  # src/level/level_manager.gd:228-244
  func _do_place() -> void:
      if tc.place(_facing_cell()):      # ← 第 229 行：先试面向格，成功就返回
          refresh_all()
          return
      var candidates: Array[Vector2i] = []
      candidates.append_array(tc.level.receptacle_positions())   # 容器格只当兜底
      ...
  ```

  而 GDD §6.2.2 规定的顺序是：

  ```
  1. 候选中 is_receptacle == true 且 not is_blocked  → 取第一个   ← 容器格必须最优
  2. 否则：面向格 若合法                                → 取面向格
  3. 否则：四邻中第一个合法格
  4. 否则：失败
  ```

  当前实现把第 1 步和第 2 步**颠倒了**：面向格只要恰好是合法空地，就会抢在容器格前面命中。
  GDD §6.2 原文对此早有预警：*「只做 U2 的话，若面向格恰好是一块合法空地，仍会放到空地而不是压力板」* —— 这正是本次实测命中的情形。
  数据层是对的：`PLATE.is_receptacle = true`（`src/data/level_01_def.gd:156-161`）、`LevelData.receptacle_positions()` 已字段化 —— **缺的是选择算法里的优先级**。

### 3.2 严重度补充诊断（已自动化，用于判断会不会硬卡死）

```
[ck] PASS  P2-诊断：砝码落到 (6,1) 后该格被占（砝码 solid=true）→ 咽喉被自己堵住
[ck] PASS  P2-诊断：仍可从 (6,2) 把砝码取回（可自救，非硬死局）
```

即：放错后砝码占住 (6,1)，玩家被挤在 {(6,2),(6,3)} 口袋里，但**仍可从 (6,2) 取回砝码重放**（T1 形态 `WEIGHT_OK` 可取），**不构成硬死局**，也**不会触发死锁谓词**（`P4`/`test_deadlock_and_win` 全程非死局）。
但玩家当刻看到的是「机关没反应 + 路被自己堵了」，属于**高困惑度体验缺陷**。

### 3.3 触发概率评估（为什么现有 183 条断言没抓到）

- 首次抵达 (6,2) **只能从北面** ((5,2) 是墙、(7,2) 需闸门先开、(6,3) 必经 (6,2)) ⇒ 首次放置**侥幸正确**（P1 绿）
- 但「先踩上压力板看看、再退回 (6,2) 放置」是**极自然**的玩家行为 ⇒ P2 场景真实可现
- 既有用例（`test_level_01_solvable:85`、`test_scene_wiring:61-63`）都是**直接调 `tc.place(Vector2i(6,3))` 或手工把 `_facing` 设成 `(0,1)`** —— 等于「假设玩家已经选对了格子」，**绕过了真正出问题的目标格选择算法**。所以 183/187 条断言全绿，但缺陷仍在。

---

## 4. HUD 滞后争议的独立裁决

> 争议：工程侧报告「场景层断言全绿」，但日志里出现「时砂 12/12（期望 10/12）」「背包 1/2（期望 0/2）」这类滞后数字，工程侧判定是「测试直接调 `tc.shift()` 而非走输入事件所致，不是真缺陷」。

我先说明一点：`_test.log` **在项目树内不存在**（`find . -name "_test.log"` 无结果，`/tmp` 下的历史日志也无该字符串），所以我**没有采信该日志**，而是自己重建了实验。

### 4.1 结论一：HUD 在真实玩家流程中**不滞后** —— 工程侧的「不是真缺陷」这个**结论**成立

我全程走 `LevelManager` 的玩家入口（`_try_shift` / `_do_take` / `_do_use` / `_do_place` / `_walk_to` —— 即 `_input()` 里真正调用的那些函数），每一步同时核对 **HUD 显示值** 与 **tc 真相值**：

```
[ck] PASS  A0 绑定后：HUD 时砂 = 12 / 12          (实际=12 / 12 / 期望=12 / 12)
[ck] PASS  A1 切时刻后：HUD 时砂 = 11 / 12        (实际=11 / 12 / 期望=11 / 12)
[ck] PASS  A2 持取钥匙后：HUD 状态行含「背包 1/2」
[ck] PASS  A3 开锁后（钥匙留锁孔）：HUD 状态行含「背包 0/2」
[ck] PASS  A4 持取砝码后：HUD 状态行含「背包 1/2」
[ck] PASS  A6 放置砝码后：HUD 状态行含「背包 0/2」
[ck] PASS  A7 切回 T2 后：HUD 时砂 = 10 / 12      (实际=10 / 12 / 期望=10 / 12)
[ck] PASS  A8 通关时：HUD 时砂 = 10 / 12          (实际=10 / 12 / 期望=10 / 12)
[ck] PASS  A9：HUD 时砂随撤销刷新为 10 / 12
[ck] PASS  A10 重置后：HUD 时砂 = 12 / 12
```

刷新链路代码审查：`LevelManager` 在 `start_level()` 里订阅了 `tc.moment_changed` / `tc.inventory_changed` / `tc.override_added` → `refresh_all()` → `refreshed` → `HUD._on_refresh()`（`src/ui/hud.gd:83`）；每个动词函数末尾也显式 `refresh_all()`。**链路完整，无遗漏分支。**

### 4.2 结论二：工程侧给出的**理由**不成立 —— 直接调 `tc.shift()` 并不会让 HUD 滞后

我做了反向验证（若"测试直接调 tc 导致 HUD 不刷新"成立，下面两条必然失败）：

```
[ck] PASS  B1：★ 直接调 tc.shift() 后 HUD 仍刷新为 11 / 12  (实际=11 / 12 / 期望=11 / 12)
[ck] PASS  B2：★ 直接调 tc.take() 后 HUD 仍刷新为 背包 1/2
```

原因很直接：`tc.shift()` → `_after_change()` → `moment_changed` 信号 → `LevelManager._on_moment_changed()` → `refresh_all()` → HUD 刷新。**逻辑层与输入层共用同一条信号链，不存在"绕过输入层就漏刷新"的分支。**

### 4.3 结论三：滞后数字的**真正**成因（我定位到的真陷阱）—— 0.35 s 切换冷却在 headless 下永不递减

```
[ck] PASS  C1：第一次 _try_shift 生效 → T1          (实际=1 / 期望=1)
[ck] PASS  C1：HUD 时砂 11 / 12（HUD 并未滞后）
[ck] PASS  C2：★ 第二次 _try_shift 被冷却吞掉（仍停在 T1）   (实际=1 / 期望=1)
[ck] PASS  C2：★ 于是 HUD 停在 11/12 —— 表现为『滞后』
[ck] PASS  C3：模拟 _process(0.4) 冷却清零后再切 → T0（真实游戏有帧循环）
[ck] PASS  C3：HUD 时砂 10 / 12（真实游戏路径下 HUD 不滞后）
```

- `LevelManager._try_shift()`（`src/level/level_manager.gd:169-173`）开头有 `if _transition > 0.0: return`
- `_transition` 由 `_on_moment_changed()` 置为 `0.35`，只在 `_process(delta)` 里递减
- **headless `--script` 模式下没有帧循环**，`_process` 从不被调用 ⇒ 第一次切换之后 `_transition` 永远停在 0.35 ⇒ **后续所有 `_try_shift()` 被静默吞掉**（既不报错也不切换）
- 结果就是：用例以为自己切了 2 次（期望时砂 10），实际只切了 0–1 次，读到的 HUD 是 12/12 或 11/12 —— **与争议里描述的数字完全吻合**

这正是既有用例 `test_scene_wiring.gd:38,84` 里那两行 `lm._transition = 0.0` 存在的原因（作者当时是手工绕过，但没有注释说明）。

**所以：滞后数字是「场景层用例忘了清冷却」造成的测试假象，不是 HUD 缺陷。** 工程侧「不是真缺陷」的判断正确，但归因（"测试直接调 tc.shift()"）错了；正确的归应是 **"场景层用例连续调 `_try_shift()` 时没模拟帧循环"**。

### 4.4 由此暴露的一个**真实测试基建缺陷**（已被我修掉，需工程侧知晓）

headless `--script` 模式下，`SceneTree.root` 在 `_initialize()` 阶段 `is_inside_tree() == false`（实测）：

```
before frame: root.is_node_ready = false  root.is_inside_tree = false
after  frame: root.is_node_ready = true   root.is_inside_tree = true
```

⇒ 此时 `add_child()` **不会触发子节点的 `_ready()`**。任何依赖 `_ready` 建控件的用例（HUD 的刻度尺 / 沙漏 / 背包 / 提示层）都会拿到 `null`，`bind_level()` 直接崩并刷出 10 条 `SCRIPT ERROR`。
**这意味着：此前根本没有任何一条自动化用例真正验证过 HUD** —— 187 条断言里不含 HUD，原因就在这里。

我在 `tests/test_main.gd` 里加了 `await process_frame`（一行），此后 root 就绪、`add_child` 正常触发 `_ready`，HUD 用例才跑得起来，且全套件 `SCRIPT ERROR = 0`。

---

## 5. 我改动了什么（及为什么必须改）

### 5.1 `tests/test_main.gd`（+1 行逻辑，+3 行注册）

```gdscript
func _initialize() -> void:
	var h := TestHarness.new()
	await process_frame          # ← 新增：等 root 就绪，否则 add_child 不触发 _ready
	print("════════ 《物候》headless 断言测试 ════════")
	...
	TestPlaceTargetP1P6.run(h, root)
	TestHudRefresh.run(h, root)
	TestAcceptance11.run(h)
```

不改这行，HUD 相关断言无法运行（会刷 10 条 ERROR，违反门禁的"ERROR = 0"）。

### 5.2 三个新增套件

见 §1.3 表格。设计原则：**被测动作一律走玩家入口**，只有 arrange（布置前置）才直接写 `tc`。

---

## 6. 已知风险与缓解建议

| # | 风险 / 缺陷 | 等级 | 位置 | 建议 |
|---|---|---|---|---|
| R1 | **U3 容器格吸附优先级未实现**：面向格是合法空地时，砝码放到空地而非压力板 | **Blocker**（§11.1 硬门） | `src/level/level_manager.gd:229` | 把 `_do_place()` 改成 GDD §6.2.2 的顺序：先在候选集 `[面向格] + 四邻` 里找 `is_receptacle && !is_blocked` 的格子 → 再面向格 → 再四邻空地。改完 P2/P3 即转绿。**这是唯一阻断项** |
| R2 | 三级提示的**被动**阈值（90/180/360 s）与 45 s 冷却**未实现** | Major（验收清单 §11-9 未达标） | `src/level/level_manager.gd:274-279` | 加一个"自上次有效进展以来的累计秒数"计时器，达标后调 `_do_hint()`；或正式把它降级为"MVP 只做主动提示"并同步修订 §11-9。**需主理人裁决** |
| R3 | 无音效，环境音通道只是数据 | Minor（README 已知限制 #1） | `src/level/environment_layer.gd` | 非色彩通道仍有 4 条（≥3 达标），可延后 |
| R4 | `walk_to()` 会入撤销栈 ⇒ 通关后按 Z 只把玩家挪回去，Override 不动，玩家可能以为"撤销没反应" | Minor | `src/core/time_controller.gd:379` | 要么移动不入撤销栈（GDD §7 说移动不计步），要么撤销时跳过纯移动记录 |
| R5 | `plate_pressed()` 仍硬编码 `level.plate_pos` | Minor（可维护性） | `src/core/time_controller.gd:403-413`（README 已知限制 #8） | 后续加第二个容器时改为遍历 `receptacle_positions()` |
| R6 | headless 下 `_try_shift()` 会被 0.35 s 冷却静默吞掉，易产生"假失败 / 假滞后" | Minor（测试基建） | `src/level/level_manager.gd:169-173` | 用例里统一 `lm._transition = 0.0`（我已在自己的用例里这么做），或给 `_try_shift` 加个 `force` 参数供测试调用 |
| R7 | §11-2 的"关掉色彩后仍可分辨"仅做了数据层断言，未做人工盲测 | Minor | — | 建议出包后做一次 5 人灰度盲测（关色彩、只凭刻度+光照+粒子辨识时刻） |
| R8 | 切时刻过渡无 Tween 插值、无操作时间轴、无存档 | Minor（README 已知限制 #2/#5/#3） | — | 已在 README 披露，垂直切片范围内可接受 |

---

## 7. 放行建议

**我的判定：FAIL（不放行）。**

理由只有一条，但它是硬门：关卡文档 §11.1 明写「本组不通过 = 质量门不通过」，而 P2 / P3 未通过。

**但请主理人注意配套的放行弹性**：

1. 本缺陷**不锁死关卡** —— 默认动线（从北面进入 (6,2)）可正常通关（P1 / P4 / P5 全绿、端到端 `check_win == true`、时砂 10），且放错后**可撤销自救**（已自动化验证）。
2. 修复面极窄 —— 只需在 `src/level/level_manager.gd:229` 把「容器格优先」提到「面向格」之前，**一个函数、约 10 行**。
3. HUD 争议已查清：**HUD 无缺陷**（真实流程逐帧核对全绿），滞后数字是测试基建（0.35 s 冷却 + headless 无帧循环）造成的假象，我已顺手修好基建。

**建议路径**：
- **路径 A（推荐）**：让工程侧改 `_do_place()` 一处 → 我复跑门控（预计 P2/P3 转绿，291+ PASS / 0 FAIL / 退出码 0）→ 转 **PASS** 放行。
- **路径 B（需人工裁决）**：若本次只是内部垂直切片、可接受"从南面进入时放错、玩家撤销重来"，可由主理人签字降级为 **CONCERNS** 放行，但必须在发布说明里写明这条已知缺陷，并在 §11.1 的裁定上留痕（属于偏离预设门规）。

按工作室规矩，质量门是**建议性**门控：**我给判定，最终放行由用户（主理人）决定。**
