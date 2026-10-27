# 《孤岛求生》纵向切片 · 验收报告

生成时间：2026-10-26
工程路径：`island-survival/`
引擎：**Godot 4.3.stable.official.77dcf97d8**（GL Compatibility）

---

## 1. 结论摘要

| 验收项（GDD 15.1） | 状态 | 证据 |
|---|---|---|
| 新游戏可理解基本操作与目标 | ✅ | 主菜单 + HUD 主线 5 步 + 采集/建造提示 |
| 三区域自由探索，完成采集/建造/战斗/升级闭环 | ✅ | 冒烟测试全链路；11 张截图 |
| 至少经历一次死亡并继续同一存档 | ✅ | 死亡掉落、复活、二次死亡清尸 均断言通过 |
| 保存退出并继续，世界状态一致 | ✅ | 原子存档 + 读档后建筑/主线一致性断言 |
| 击败守卫、点燃火台、出现胜利结算 | ✅ | 点火→胜利流程断言；胜利面板截图 |
| 无脚本解析错误、无悬空引用、追踪可机检 | ✅ | 自检 0 问题 0 警告；`@trace` 覆盖 27/27 |
| Windows 包已导出 | ✅ | `export/windows/`（exe 81 MB + pck 7.4 MB） |
| Windows 实机性能/兼容 | ⚠️ **待验证** | 容器内无法运行 exe；仅用 Linux + llvmpipe 加载同一 pck 验证 |

**一句话**：功能与工程完整性已验证；Windows 实机未验证，`NUM-006` 平衡试玩未完成，设计冻结仍需人工签字。

---

## 2. 测试结果

### 2.1 冒烟测试（`-- --smoke`）
```
ok: true    checks: 64    failures: 0    exit: 0
```
覆盖：采集工具门槛、制作扣料、满级拒绝不扣料、非法建造不扣料、拆除返还 50%、
伤害公式、守卫击杀与徽记、死亡掉落与任务物品保留、读档恢复建筑与主线、点火胜利、
背包不暂停 / Esc 暂停。

### 2.2 战斗与平衡模拟（`-- --combat`）
```
ok: true    checks: 16    failures: 0    exit: 0
```
覆盖：伤害公式原值直通、连击倍率、守卫 25% 减伤、野猪 FSM 前摇/攻击/追击、狼接近玩家、
守卫命中、脱战回血 25%、满级矛击杀与击杀计数、**TTK 表与 GDD 8.4 逐行核对（3 敌人 × 2 等级）**。

平衡观察（**非通过条件**）：

| 场景 | 命中 | 耗时 | 玩家受伤 | 结果 |
|---|---:|---:|---:|---|
| 徒手 vs 野猪（不闪避） | 11 | 16 s | 96 | **阵亡** |
| 矛 Lv2 vs 野猪 | 3 | 2.0 s | 16 | 击杀 |

### 2.3 工程规格自检（`tools/spec_check.py`）
```
ok: true    problems: 0    warnings: 0    traceCoverage: true
```
校验项：必需/推荐目录、4 个必需文件、`.import` 元文件、绝对路径扫描、`res://` 悬空引用、
`@trace` 需求覆盖。

### 2.4 渲染验证
11 张截图，1600×900 实际窗口（viewport 1920×1080）：
菜单、海滩出生、森林、岩地守卫、湿地、背包、建造栏、海滩营地、暂停、死亡、胜利。
中文渲染、区域色板、7 个界面布局均已肉眼确认。

### 2.5 导出包验证
- `IslandSurvival.pck` 解析：**59 个条目**，仅含 `scripts/ assets/ resources/ scenes/ .godot/ project.binary`。
- 不含 `tests/`、`tools/`、`docs/`、`reports/`、截图（已逐项核对）。
- 用 Linux 版 Godot 加载同一 pck 启动 300 帧：**exit 0，无脚本错误**。

---

## 3. 本轮修复的缺陷

| 缺陷 | 根因 | 修复 |
|---|---|---|
| 背包面板偏移到屏幕左上、被 HUD 遮挡 | 挂在 `CanvasLayer` 下的 `Control` 没有父 Control，`set_anchors_preset(FULL_RECT)` 不会撑开自身 `size`，导致锚点百分比按 0 尺寸计算 | 全部 7 个 UI 面板改为显式设置 `anchor_*` + `offset_*`；子控件统一走 `_fill_parent()` |
| 建造面板完全不可见 | 同上，且 `PanelContainer` + `custom_minimum_size` 与 offset 冲突 | 改 `Panel` + `MarginContainer`，尺寸由 offset 决定 |
| 发行包混入 8 张测试截图 | `export_filter="all_resources"` 下 `exclude_filter` 对已导入资源不生效 | 截图移出 `res://`；清理 `.godot/imported/` 中的 ctex 缓存 |
| 战斗测试误判徒手能击杀 | 测试复位函数未清空装备槽（复活按设计不清装备） | 复位时显式重置 `equipped`，并在报告里输出 `fist_weapon` 以便复查 |

---

## 4. 已知限制（如实标注）

1. **Windows 实机未验证**：exe 由官方模板导出，但当前环境为 Linux 容器，无法运行 `.exe`。
2. **平衡未完成**：GDD 13.3 要求 3 条路线的真人试玩记录，尚未进行，`NUM-006 = partial`。
3. **设计未冻结**：`docs/design-freeze.json` 的 27 条 `confirmed` 全为 `false`，需需求方对 GDD 附录 B 的 6 项表态。
4. **音频未实现**：GDD 9.5 范围，本轮切片未做。
5. **美术为程序化占位**：非最终资产。
6. **720p 可读性未单独截图**（最小窗口 1600×900；截图分辨率与此一致）。
7. **rcedit 缺失**：exe 的图标/版本信息未写入（导出警告，不影响运行）。
8. **无头环境噪音**：`--headless` 下 dummy 渲染器报 `Parameter "m" is null`，不影响结果。

---

## 5. 产物清单

```
island-survival/
├── project.godot                     # 含 PLAT-001 平台声明
├── export_presets.cfg                # Windows Desktop 预设
├── export/windows/
│   ├── IslandSurvival.exe            # 81 MB（Godot 4.3 官方模板）
│   └── IslandSurvival.pck            # 7.4 MB（59 条目，纯游戏资源）
├── scenes/main/main.tscn
├── scripts/                          # 24 个 .gd（autoload / player / world / buildings / enemy / ui / main）
├── resources/ui_theme.tres
├── assets/ui/font_cjk.otf            # Noto Sans SC
├── tests/                            # smoke_runner / combat_runner / screenshot_runner
├── tools/spec_check.py               # 工程规格自检
├── docs/
│   ├── gdd.md                        # 实现说明书 + 差异 + 待确认项
│   └── design-freeze.json            # 27 条需求实现与验证状态
└── reports/
    ├── smoke-report.json             # 64 项断言
    ├── combat-report.json            # 16 项断言 + 平衡观察
    ├── spec-check.json               # 0 问题 0 警告
    └── smoke_final.log
```

截图单独存放于 `/workspace/__shots/`（工程外，避免被导出打包）。

---

## 6. 复现命令

```bash
cd island-survival

# 冒烟测试
godot --headless --path . -- --smoke

# 战斗与平衡模拟
godot --headless --path . -- --combat

# 工程规格自检
python3 tools/spec_check.py .

# 截图（需要 X 环境）
xvfb-run -a godot --path . -- --shot=/tmp/shots/island

# 重新导出 Windows 包
godot --headless --path . --export-release "Windows Desktop" export/windows/IslandSurvival.exe
```

导出模板需先安装到 `~/.local/share/godot/export_templates/4.3.stable/`
（来源：`Godot_v4.3-stable_export_templates.tpz` 中的 `windows_*` 与 `version.txt`）。
