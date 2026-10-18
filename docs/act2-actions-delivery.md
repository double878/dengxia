# 第二关第二幕人物动作交付

2026-10-13。按用户确认的“AA流程同意”执行，范围以 `superpowers/specs/2026-10-13-act2-actions-design.md` 为准。本轮不制作唱腔或新对白音频，不接入第二关整关评分、录放或第三幕。

## 已交付行为

厅堂开场白素贞与许仙对坐，小青站在白素贞后侧服侍。拖手、头、前倾与 R 复位沿用现有上身控制；拖离凳子自动起身。普通对白以短字幕自动推进；白素贞应允后小青答「好吧」再离场。饮前两人对唱先用临时字幕排练，结束后才开放取杯、递杯和饮酒。饮后必须由玩家让白素贞实际弯腰，才开始不适与取药的普通对白；弯腰接入原补救。最新顺序及验证见 [剧情修订记录](act2-plot-order-delivery.md)。

小青必须走到左台边再退场。许仙取桌上红杯，让白素贞的手靠近杯完成真实交接，持杯手送到嘴边保持片刻才饮下；未做动作一直等待。许仙从右台边退场取药后，玩家压暗灯、收白素贞、上白蛇、调亮显形；白素贞和白蛇互斥。许仙从右侧返回，真正走近并面向显形白蛇后自动惊退、仰倒、静止。误退场保留姿态、走位与杯归属，正式离场的角色不会提前串场。暂停冻结双时钟，暂停、失焦、换人和离开场景结束拖动。

白蛇具有固定长度的颈身分节和铜色关节；拖蛇头带动相邻节弯曲，拖躯干整条移动，R 恢复颈身。实体与透射读同一蛇状态。

## 操作和启动

| 操作 | 行为 |
| --- | --- |
| 空格 | 按在场编号循环接手 |
| 1 / 2 / 3 / 4 | 白素贞 / 许仙 / 小青 / 白蛇上场；剧情未许可时不响应 |
| 左键拖手 / 头 / Alt 拖躯干 | 人形弯肘 / 俯仰 / 前倾 |
| 左键拖胸签或手边竹签 | 人形走位、蹲站；拖离座位自动起身 |
| 左键拖蛇头 / 躯干 | 蛇颈身弯曲 / 整条平移 |
| 右键点影人 | 退场；小青买酒菜需左边，许仙取药需右边 |
| Q / E（按住） | 压暗 / 调亮显露度 |
| 滚轮 | 调整灯距 |
| R | 当前影人上身或白蛇颈身复位 |
| ESC / 暂停按钮 | 暂停 / 继续 |

在项目根目录直接验收第二场：

```powershell
& 'D:\Godot\4.7.2\godot.exe' --path . 'res://scenes/act2/hall.tscn'
```

正式流程仍由第一场收场自动切入 22 号厅堂。导出包为 `builds/dengxia.exe` 和同目录 `dengxia.pck`，应一起保留。正式导出模板禁用了命令行场景路径覆盖；给 EXE 追加第二场路径会退出 1，因此直接打开第二场使用本机同版本 Godot 和当前源码。

本机 `builds/第二幕试玩.cmd` 调用 `D:\Godot\4.7.2\godot.exe` 打开当前工程第二场，不必先演第一关；正式 EXE 从游戏入口开始。

## 资源和实现

- `scripts/act2/act2_hall.gd`：宿主、三人控制、灯、蛇输入、同源显示及一次惊倒。
- `scripts/act2/act2_hall_actions.gd`：字幕、实际动作门槛、唯一酒杯与正式离返。
- `scripts/act2/wine_cup_view.gd`：杯跟随真实腕点；`scripts/c/c_scenery_view.gd` 按需隐藏桌面同一杯。
- `scripts/act2/snake_pose.gd` / `snake_view.gd`：有限分节求解与实体/透射绘制。
- `scripts/a_test/placeholder_puppet.gd`：默认关闭的坐姿与倒地参数，腕/头查询和显示共用变换。
- `tools/build_snake_assets.py` / `assets/puppets/snake/`：开发期素材整理、透明分件、来源和轮廓清单。

用户原始参考保留为 `assets/puppets/snake/snake-reference.jpg`，SHA256 为 `03c849985140842647d6e82cb810d4afb76a4bd8282ff081e0e01960e3588c90`。图像是含花枝、背景和手机界面的参考，头部按轮廓取出，颈身、盘曲和尾部按操演需要重建，白色纹理取样；这不是逐像素复刻。清单中的 922×2048 是处理坐标画布，原始文件未改写。三个 PNG 均含完整透明区。Pillow/NumPy 只用于开发脚本，游戏无新增运行依赖。

## 验证证据

使用 `D:\Godot\4.7.2\godot.exe`（`4.7.2.stable.official.ed1daf0bf`）与 `4.7.2.stable` 导出模板。所有修改脚本先逐个执行 `--headless --path . --check-only --script res://<文件>`；gdformat 4.5.0 与 gdlint 检查通过。

自动测试命令统一经 `tools/run_godot.ps1`：

```powershell
& .\tools\run_godot.ps1 -LogName final-act2-actions -GodotArgs @('--headless','--path','.','--script','res://tests/c/run_act2_actions.gd')
& .\tools\run_godot.ps1 -LogName final-act2-graphics -GodotArgs @('--path','.','--script','res://tests/b/run_act2_actions_graphics.gd')
```

其他回归替换脚本路径与 LogName，结果如下（退出码均为 0）：

| 入口 | 结果 |
| --- | --- |
| `tests/c/run_act2_actions.gd` | 70 项通过；包括误退场恢复、等待、单杯、暂停、分节有限值与惊倒门槛 |
| `tests/b/run_act2_actions_graphics.gd` | Windows OpenGL / Intel Arc 实际输入流程通过，Q/E、蛇头/躯干拖动、饮酒、惊倒已截图目视检查 |
| `tests/c/run_act2_hall.gd` | 39 项通过 |
| `tests/c/run_act2_opening.gd` | 133 项通过 |
| `tests/c/run_act2_dialogue.gd` | 40 项通过 |
| `tests/c/run_act2_entrances.gd` | Windows 图形环境 40 项通过 |
| `tests/a/run_upper_body.gd` | 100 项通过 |
| `tests/a/run_tests.gd` | 1284 项 + 第一幕编排 22 项通过 |
| `tests/c/run_tests_c.gd` | 461 项通过 |
| `tests/b/run_stage_visuals.gd` | 379 项通过 |
| `tests/c/run_game_replay_success.gd` | 第一幕完整接还伞与回放，12 项通过 |

三项门禁为 `--headless --path . --import`、`--headless --path . --quit-after 60`、`--headless --path . --export-release "Windows Desktop" builds/dengxia.exe`。三项通过；导出 EXE 在 Windows 图形环境以 `--quit-after 60` 启动退出码为 0。

日志：`builds/stage-realism/logs/final-*.out.log` / `.err.log`。截图：`builds/act2-actions/` 下的 `opening`、`cup-held`、`cup-passed`、`drink`、`snake-dark`、`snake-revealed`、`snake-bend`、`snake-moved`、`startled`、`ending`。

独立分支验证后已接回 `D:\Cursor_program\灯下`。全部运行脚本、场景、着色器和测试源码与验证工作区一致；核对 24 个其他已有文件未改动。在原工程重跑资源导入、逐文件解析、动作 70 项、厅堂 39 项、Windows 完整图形输入、无头启动与导出，均退出 0；原工程导出包的正式入口在 Windows 图形环境退出 0。原工程已有上半身修改仍保留在原分支，不将其混入动作提交。

A/C 套件的非法输入案例会刻意输出 ERROR，但断言和退出码通过。启动门禁仍有基线的 2 个 ObjectDB / 1 个 resource 退出释放提示，A 套件记录 4 个 ObjectDB / 1 个 resource 提示；此项未在动作切片内修复。第二幕动作及图形验收无该提示。

自动化确认动作与画面；操作手感、自由身段的演出质量和白蛇美术仍需用户实际试玩评价。终场保留惊死定格，当前没有第二关整关收场、回放或第三幕衔接。正式回归保留，临时诊断不进入提交；构建和截图不进版本库。
