# 《孤岛求生》· 生存纵向切片

Godot 4.3 实现的纵向切片（Milestone B/C/D 初版）。4 区域连续岛、生存状态、采集门槛、12 格背包、10 配方、4 建筑、敌人 FSM 与掉落、死亡回收、主线 5 步、原子存档、暂停规则、胜利结算。

策划依据：GDD v0.9（设计冻结见 `docs/design-freeze.json`，实现说明见 `docs/gdd.md`）。

## 运行环境

| 项目 | 值 |
| --- | --- |
| 引擎 | Godot **4.3.stable.official.77dcf97d8** |
| 渲染 | GL Compatibility |
| 窗口 | 设计 1920×1080，覆盖 1600×900，`canvas_items` 拉伸 |
| 主场景 | `res://scenes/main/main.tscn` |
| Autoload | `Game`、`GameConfig`、`InputSetup` |
| 输入 | 运行时注册 InputMap，用 `physical_keycode` 规避中文输入法吞键 |

## 快速开始

```bash
git clone https://github.com/Honuanin/IslandSurvival.git
cd IslandSurvival
```

用 Godot 4.3 的 Project Manager「导入」本目录的 `project.godot` 即可。首次打开会生成 `.godot/` 缓存（已被 git 忽略）。

> **命令行/CI 场景请先跑一次导入**：`godot --headless --path . --import`（约 4 秒）。
> 跳过这一步直接运行，字体资源尚未导入，主题会报 `referenced non-existent resource`，UI 相关断言可能失败。
> 首次导入时 `ui_theme.tres` 报一条字体 `Parse Error` 属正常现象，资源导入完成后即消失。

## 全局类与 preload 约定

工程里 18 个脚本带 `class_name`，但**不要在新脚本里依赖裸全局类名**（如 `Player.new()`）。全局类名靠 `.godot/global_script_class_cache.cfg` 注册，该缓存不进版本库，新 clone 首次导入前引用会直接 `Parse Error`，导致整个工程启动失败（`game_session.gd` 曾因此完全无法解析）。

需要引用其他类时，用显式 preload：

```gdscript
const PlayerScript := preload("res://scripts/player/player.gd")

var player: PlayerScript = null
```

`game_session.gd` 已按此改造，可作为范例。声明 `class_name` 本身没有问题，`Enemy`、`Inventory` 等被其他脚本按需 preload。


## 回归测试

改动后请至少跑冒烟测试与规格自检两项：

```bash
# 冒烟测试：64 项断言，覆盖 22 条验收项
godot --headless --path . -- --smoke

# 战斗与平衡测试：16 项断言 + TTK 表核对
godot --headless --path . -- --combat

# 工程规格自检：目录、必需文件、.import、绝对路径、悬空引用、@trace 覆盖
python3 tools/spec_check.py

# 截图（需要显示环境，CI 中可用 xvfb-run）
xvfb-run -a godot --path . -- --shots
```

三条命令均以 **exit 0** 为通过。`--shots` 输出到工程外的 `__shots/`，避免测试截图被打进发行包。

实测基线（Godot 4.3.stable.official.77dcf97d8，清空 `.godot/` 后全新导入）：

| 检查 | 结果 |
| --- | --- |
| `godot --headless --path . --import` | exit 0，约 4 秒 |
| `--smoke` | **64/64**，failures 0，exit 0 |
| `--combat` | **16/16**，failures 0，exit 0；TTK 全表匹配 |
| `tools/spec_check.py` | `problemCount 0` / `warningCount 0` / `traceCoverage true` |

> 无头模式下会刷出大量 `Parameter "m" is null`（dummy 渲染器遍历 3D 网格的正常现象）与退出时的 RID 泄漏告警，**不影响断言结果**，可忽略。

## 目录职责

| 路径 | 职责 |
| --- | --- |
| `scenes/` | 场景。当前只有 `main/main.tscn`，其余节点由 `game_session.gd` 程序化构建 |
| `scripts/autoload/` | 单例：`game.gd`（全局状态/信号）、`game_config.gd`（**全部数值表**）、`input_setup.gd` |
| `scripts/player/` | 玩家、`inventory.gd`（事务式背包）、`survival_stats.gd` |
| `scripts/world/` | 岛屿生成、地形、低多边形网格、资源节点、掉落物 |
| `scripts/enemy/` | 敌人 FSM（PATROL→ALERT→CHASE→WINDUP→ATTACK→RECOVER→DEAD） |
| `scripts/buildings/` | 建造控制器与建筑实例 |
| `scripts/ui/` | HUD、背包、建造、暂停、死亡、胜利、主菜单 |
| `assets/` `resources/` | 字体（含 CJK）、UI 主题 |
| `tests/` | 冒烟/战斗/截图三个 runner |
| `tools/spec_check.py` | 规格自检脚本 |
| `docs/` | 实现说明与设计冻结 |
| `reports/` | 各项测试的产出报告 |
| `export/` | **不进版本库**，导出产物走 Release |

## 数值改动约定

所有平衡数值集中在 `scripts/autoload/game_config.gd`，包括敌人、工具、伤害公式、配方、建筑、生存消耗。**不要在业务脚本里散落魔法数字**，改动后跑 `--combat` 观察 TTK 是否仍符合 GDD 8.4：

| 目标 | 玩家 | 命中数 | 击杀耗时 |
| --- | --- | --- | --- |
| 野猪 60HP | 石斧 Lv1 | 4 | — |
| 狼 80HP | 石斧 Lv1 | 5 | — |
| 守卫 280HP | 长矛 Lv2 | 20 | — |

## 提交约定

- 提交信息用中文，首行不超过 50 字，说明「改了什么 + 为什么」。
- 涉及玩法或数值的改动，请在 MR 描述里附上 `--smoke`、`--combat` 的实际输出。
- 新增机制请在对应代码处补 `@trace <需求ID>` 注释，`spec_check.py` 会校验 27 条需求的覆盖情况。
- 设计冻结中 `confirmed` 为 `false` 的条目仍在等人签字，不要单方面改动其行为。

## 已知限制

- 音频未实现（GDD 9.5 范围外）。
- `NUM-006` 平衡只做了脚本化模拟，缺真人试玩。
- Windows 包在 Linux 容器内无法实机验证运行表现；导出缺 `rcedit`，exe 无图标与版本信息。
- 设计冻结 27 条需求的 `confirmed` 全为 `false`。

详见 `reports/acceptance-report.md`。
