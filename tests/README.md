# 《物候》headless 断言测试

零图形环境下验证游戏逻辑。**不需要显示器、不需要打开编辑器。**

---

## 怎么跑

### 前置：装好 Godot 4.7.2 console 版

```bash
GD="C:/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
"$GD" --version        # 应输出 4.7.2.stable.official.ed1daf0bf
```

> ⚠️ 必须用 **`_console.exe`**。GUI 版 exe 在 Windows headless 下不输出 stdout，你会看到一片空白。

### 步骤 1（新增/改名 `class_name` 文件后**必做**）：资源导入 + 全量编译检查

```bash
"$GD" --headless --path "D:/New test" --import
```

- 输出里**没有** `SCRIPT ERROR` / `ERROR` 即通过。
- 这一步会把新脚本注册进全局类缓存。**跳过它会报 `Identifier "X" not declared`**（Godot 4.7 实测坑）。

### 步骤 2：跑断言

```bash
"$GD" --headless --path "D:/New test" --script res://tests/test_main.gd
```

- 退出码 **0** = 全绿；**1** = 有失败。
- 结尾会打印 `[SELFTEST] pass = N   fails = M`。

### 步骤 3（可选）：主场景能否真正启动

```bash
"$GD" --headless --path "D:/New test" --quit-after 300
```

- 应看到 `[game] ready: 时刻 Ⅲ 锈时·昏 ｜ 时砂 12/12 ｜ 背包 0/2 ｜ 坐标 (3,5)`，且无 ERROR。

### 一次性命令（推荐直接复制）

```bash
GD="C:/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" && \
"$GD" --headless --path "D:/New test" --import && \
"$GD" --headless --path "D:/New test" --script res://tests/test_main.gd
```

---

## 门禁看两个数

1. **PASS/FAIL**：`fails = 0`
2. **ERROR 计数 = 0**：`grep -cE "^ERROR|SCRIPT ERROR" <日志>`

只数 PASS 会漏掉一类断裂：属性被改名/删除时，Godot 是**跳过赋值**而不是落入坏值，相关用例照样 PASS，只有 ERROR 计数会暴露它。

---

## 与「端到端流程走查」的分工

| | `tests/test_main.gd` | `tools/e2e_flow.gd` |
|---|---|---|
| 入口 | 直接调 `TimeController` / `LevelManager` 的方法 | **真 `main.tscn` + 真实输入事件**（`InputEventAction` 走动作名、鼠标左键走 `_unhandled_input`） |
| 覆盖 | 逻辑数值：真值表 / 传播 / 撤销 / 放置算法 | **接线**：InputMap 动作 / 动作→动词 / 切时刻冷却 / HUD 刷新 / 通关信号 |
| 跑法 | `--script res://tests/test_main.gd` | `--script res://tools/e2e_flow.gd` |

两者互补：逻辑改动跑前者，输入层 / 场景装配改动跑后者（或都跑）。

---

## 用例文件对照（关卡文档 §11 验收清单）

| 文件 | 覆盖的验收项 |
|---|---|
| `test_resolve_pure.gd` | 验收 1（纯函数）+ 验收 8（override 绝不向过去传播，逐字段比对基线）；后写覆盖先写；锚定物字段白名单 |
| `test_undo_restore.gd` | 验收 7（撤销 10 次后逐字段一致、时砂无负数且全额返还）；重置；时砂耗尽后仍可撤销 |
| `test_immovable_pressure.gd` | 验收 6（`IMMOVABLE`/`OCCLUDED`/`HOT` 不影响占位与压感） |
| `test_level_01_solvable.gd` | 验收 1/2/3/4：§7 标准解法十步重放；T2 折断且 T1 钥匙仍在；砝码正向传播；藤蔓正向传播；A5 携带冻结专项；**藤蔓硬性咽喉回归**（拔除前四时刻皆阻挡 / 拔前寻路到不了东区 / T0 因铁栅未开而够不到藤蔓，故拔藤唯一只能在 T1） |
| `test_deadlock_and_win.gd` | 验收 5（仅 T2 站上 (11,1) 通关）；死锁谓词永不为真 + 伪造需求反向验证；背包容量 2 |
| `test_acceptance_11.gd` | 关卡文档 §11 验收清单第 2–9 条的集中断言 |
| `test_place_target_p1_p6.gd` | §11.1 放置目标专项 P1–P6（U1/U2/U3 修复回归，压力板 (9,3)） |
| `test_hud_refresh.gd` | HUD 刷新：刻度 / 时砂 / 背包 / 状态栏随状态变化重绘 |
| `test_hud_layout.gd` | HUD 版式：各面板不重叠 / 不越出画布 / 分界线与铭文位置 |
| `test_movement.gd` | 移动输入专项：逐格推进（人未到不结算）/ 中途改目标不穿墙 / 键盘长按 / 拖拽改目的地 / 路径预览 / 整段移动只占 1 条撤销 / 切时刻取消移动 |
| `test_hint_layout.gd` | 提示条布局：多行不再越出画布底边 / 边框不压字 / 单行只压最下一行墙（回归「文字提示被边框遮挡」） |
| `test_hud_layout.gd` | HUD 版式：三组面板 + 按钮互不重叠 / 不越界 / `BAND_H=140` 不漂移 / 时刻名铭牌可点 / 状态行不重复 / 按钮自绘四态 / 死锁脉冲自行收回 |
| `test_scene_wiring.gd` | 场景装配冒烟：9 个道具节点生成、5 个动词接线、残影开关、通关信号 |
| `test_main.gd` | 入口 + 输入映射断言（`E` 只绑 Use、`A/D` 只绑切时刻、方向键只绑 `move_*`、空格只绑持取） |
| `harness.gd` | 极简断言器（`ck` / `eq` / `diff_snapshots`） |

---

## 新增用例怎么写

1. 在 `tests/` 下建 `class_name TestXxx extends RefCounted`，暴露 `static func run(h: TestHarness) -> void`。
2. 在 `test_main.gd` 的 `_initialize()` 里加一行 `TestXxx.run(h)`。
3. **跑一次 `--import`**（注册新 `class_name`），再跑测试。

约定：
- 一局新游戏用 `TestHarness.new_game()`（T2 / (3,5) / 时砂 12）。
- 断言一律走 `h.ck(cond, 说明)` / `h.eq(实际, 期望, 说明)`。
- ⚠️ **GDScript 的 lambda 捕获是按值的**：想在回调里改外部标志位，请把标志位放进 `Dictionary`/`Array`（`test_scene_wiring.gd` 里有注释示例）。

---

## 实测基线（本机，Godot 4.7.2）

```
--import            → 0 ERROR
主场景 --quit-after → 0 ERROR / 0 WARNING
断言测试            → fails = 0, ERROR = 0, 退出码 0（最近一次实测 534 PASS / 14 个用例组）
端到端走查          → fails = 0, ERROR = 0, 退出码 0（当前 114 PASS，约 4 s）
```

### 两个"写测试时才会遇到"的坑（都实际踩过）

1. **别依赖帧数做时序断言**。headless 下帧间隔抖动很大，"点一下 → `await process_frame` →
   断言坐标没变"这种写法会偶发失败（那一帧恰好够走完一格）。
   * 要断"按下瞬间还没生效"：用 `root.push_input(ev, true)`（**同步**派发到 `_unhandled_input`），
     **不要 await**，直接读状态。
   * 要精确驱动逐格推进：直接调 `lm._process(dt)` 喂固定步长，完全确定性
     （`test_movement.gd` 就是这么写的）。
2. **键盘移动要按"状态"驱动，不是"事件"驱动**。方向键移动是 `_process` 轮询
   `Input.is_action_pressed` 实现的，因此测试里要用 `Input.action_press/release`，
   用 `InputEventAction` 是驱动不起来的。
