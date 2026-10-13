# 第二幕补救交付

2026-10-13。用户要求“把第一关的补救操作加上”，本次接入第二关第二场厅堂。

当前动作目标出现后保留 8 秒准备时间，仍未完成则开启第一关同源的 8 秒补救窗口。师父手沿真实手腕、嘴点、杯或目标方向示范；幕台显示琥珀框，字幕区域保留剧情，下方显示“补救中 · 演出已暂停”。复用第一关 `remedy.wav` 慢锣鼓，未制作唱腔或新音频。

实际补做成功即收起示范和慢锣鼓，原失误记录保留。超时结束提示，未完成的递杯、饮酒和换蛇继续等待真实动作；同一步不反复开窗。取杯和递杯是不同目标，后续漏做可独立补救。菜单暂停冻结歌曲与真实时间、补救窗口和音频，恢复后继续。误退场提示按原编号恢复影人，保留走位与杯归属。

第二场暂无正式唱腔/拍点和整关评分，因此按动作停滞触发，不宣称完成节拍或整关评分接入。普通对白、临时对唱、自由身段和自动惊倒不额外判错；本轮要求的饮后弯腰是独立实际动作，也按原窗口补救，完成才触发不适对白。第一关原补救规则、节拍判定与回放继续使用原通路。最新验证见 [剧情修订记录](act2-plot-order-delivery.md)。

## 修改范围

- `scripts/a/remedy_system.gd`：新增 `update_actions`，真实完成/超时/收场使用原窗口结算与事件；原 `update(PerformanceSystem)` 不变。
- `scripts/act2/act2_remedy.gd`：仅读阶段、在场名单、杯归属和显露，调度补救及一次去重；不写人形、蛇、道具或剧情状态。
- `scripts/act2/act2_hall.gd`：补救展示、原慢锣鼓、灯反馈、暂停与退出；维持真实输入。
- `scripts/b/teacher_hand.gd`：抽取第一关原手形，`level1_a_scene.gd` 和第二场共同调用。
- `scripts/act2/remedy_guide.gd`：按真实几何绘制师父手、目标与方向；文字位置限制在画布内。
- `tests/c/run_act2_remedy.gd`、`tests/b/run_act2_actions_graphics.gd`：正式宿主补救、成功/超时、暂停、误退恢复，以及图形和实际混音回归。

## 验证

修改脚本逐个先执行：

```powershell
& .\tools\run_godot.ps1 -LogName remedy-parse -GodotArgs @('--headless','--path','.','--check-only','--script','res://<文件>.gd')
```

所有行为入口同样经 `tools/run_godot.ps1`，替换脚本与 LogName；图形和声音检查去掉 `--headless`：

```powershell
& .\tools\run_godot.ps1 -LogName remedy-windows -GodotArgs @('--path','.','--script','res://tests/c/run_act2_remedy.gd')
& .\tools\run_godot.ps1 -LogName remedy-graphics -GodotArgs @('--path','.','--script','res://tests/b/run_act2_actions_graphics.gd')
```

| 验证 | 结果 |
| --- | --- |
| 第二场补救正式宿主 | Windows 18 项通过，退出 0 |
| 既有第二场动作 | 70 项通过，退出 0 |
| Windows 第二场图形输入 | 完整流程通过；取杯、递杯、饮酒、压灯、显形与返回恢复的补救已截图并目视检查 |
| 慢锣鼓实际混音 | AudioEffectCapture 捕获峰值 0.105447，大于 0.001；未以播放器状态代替声音输出 |
| 第一关 A 套件 | 1284 + 22 项通过，包含原补救、时钟、灯与第一幕编排 |
| 第一幕完整接还伞与回放 | 12 项通过 |
| 厅堂衔接 | 39 项通过 |
| Windows 上半身图形回归 | 22 项通过 |
| gdformat / gdlint | 通过 |

既有慢鼓有击间静音，混音检查覆盖 1.4 秒以包含完整 1.25 秒间隔。初始 0.25 秒采样只读到击间静音，调整的是采样依据，未改音源或降低通过阈值。

日志在 `builds/stage-realism/logs/remedy-*.out.log` / `.err.log`；画面在 `builds/act2-actions/remedy-*.png`。无头补救测试断言通过，但人工快速推进音源时引擎退出报告 2 个音频 ObjectDB 释放提示；Windows 同一测试与完整图形验收无此提示。A 套件保留既有 4 个 ObjectDB / 1 个 resource 退出提示，非法输入案例 ERROR 为预期。

验收沿用 Godot `4.7.2.stable.official.ed1daf0bf` 与 `4.7.2.stable` 模板。独立工作区与原工程均执行 `--headless --path . --import`、`--headless --path . --quit-after 60`、`--headless --path . --export-release "Windows Desktop" builds/dengxia.exe`，三项退出 0；原工程导出 EXE 在 Windows 图形环境启动，退出 0。试玩继续用 `builds/第二幕试玩.cmd`。

更新已接回 `D:\Cursor_program\灯下`，52 个其他已有文件经 SHA256 核对未改动。原工程再次通过补救 18 项、动作 70 项和 Windows 全流程/混音验证；当前工程、试玩和导出均含补救。工作分支继续使用 `feat-act2-actions`，只提交本次切片，保留原工程原有未提交修改。
