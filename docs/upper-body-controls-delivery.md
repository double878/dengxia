# 上半身操控交付记录

2026-10-13。设计经用户确认，功能分支 `feat-upper-body-controls`，基于 `origin/main@b068661`。隔离工程为 `builds/worktrees/feat-upper-body-controls`，无子智能体。

## 已实现

- 左键拖手自动配合固定长度肩肘；左键拖头调整俯仰，Alt+左键拖躯干前倾。无独立手腕旋转。
- 松手、换人保留姿态；R 恢复当前人的双臂、头腰，保留下半身与身份。悬停/拖动提示只出现在受控实体。
- 第一、第二关正式宿主复用同一输入。保留键盘快捷抬落手、第一幕直臂打伞停靠位和原下半身路径。
- 伞、锡杖、竹签读取新腕点，伞朝上、杖竖直。第一幕接伞手高与抬手指标读取共享姿态几何，交接窗口及归属流程保持原规则。
- 新姿态快照、变化补采样、插值、幕前应用和独立核对齐全；旧记录缺字段为零。R 在原事件落点跳变，不提前插值复位。

## 验证命令与结果

全部使用 `D:\Godot\4.7.2\godot.exe`（`4.7.2.stable.official.ed1daf0bf`），通过 `tools/run_godot.ps1` 等待真实退出码，日志在 `builds/stage-realism/logs/upper-*.log`。修改脚本先用 `--headless --path . --check-only --script res://<文件>` 解析，再执行行为测试。

| Godot 参数 / 入口 | 实际结果 |
| --- | --- |
| `--headless --path . --script res://tests/a/run_upper_body.gd` | 100 条通过，0 失败；含输入、边界、R、记录和腕点判定 |
| `--headless --path . --script res://tests/a/run_tests.gd` | 1284 条通过，0 失败；另 22 条正式第一幕断言通过 |
| `--headless --path . --script res://tests/c/run_tests_c.gd` | 461 条通过，0 失败；负例测试有预期错误输出 |
| `--headless --path . --script res://tests/b/run_stage_visuals.gd` | 379 条通过，0 失败 |
| `--headless --path . --script res://tests/c/run_game_replay_success.gd` | 12 项通过；实际演出记录 117617 ms，接还伞、等待与回放完整 |
| `--headless --path . --script res://tests/c/run_act2_opening.gd` | 133 项通过，0 失败 |
| `--headless --path . --script res://tests/c/run_act2_dialogue.gd` | 40 项通过，0 失败 |
| `--headless --path . --script res://tests/c/run_act2_entrances.gd` | 28 项通过，0 失败 |
| `--path . --script res://tests/b/run_upper_body_graphics.gd` | Windows Intel Arc / OpenGL 3.3：22 项通过，0 失败 |
| `--headless --path . --import` | 退出 0 |
| `--headless --path . --quit-after 60` | 退出 0 |
| `--headless --path . --export-release "Windows Desktop" builds/dengxia.exe` | 退出 0 |

图形探针调用正式宿主 `_input`，捕获实际操作后的状态，进入正式幕前表现端；截图在 `builds/upper-body/` 的 `pose.png`、`act1-pose-hint.png`、`act1-replay-pose.png`。已目视检查新姿态、提示、竖直持杖与朝上伞面。

## 限制

Windows 自动输入与截图证明程序路径和画面，不能替代用户对手感与音频的试玩。第二关整关录放尚未接入，本功能只扩展共用姿态契约。

第二关测试退出仍报告 2 个 ObjectDB 实例和 1 个资源未释放；同命令在修改前的原工程也复现，未归因于本功能。A 全套测试也有既存退出资源提示。启动门禁退出 0，保留这些提示，未宣称无日志问题。
