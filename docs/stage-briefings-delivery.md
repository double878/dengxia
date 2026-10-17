# 三关演前简介交付

2026-10-17，按用户提供的第三关简介截图，将三关统一为同一套演前说明。

## 实际行为

- 第一关《许仙借伞》：片头结束或跳过后显示简介，说明走近许仙、接伞、游湖和还伞的顺序。
- 第二关《端阳惊变》：第一关收场或跳过后显示简介，说明迎接法海、取杯递酒、饮酒与暗灯换蛇；本关转入厅堂时不再显示。
- 第三关《盗仙草》：保留原简介内容与现有开演流程，改用共享组件，不额外叠一张页面。
- 三关均使用深绿底、金色标题、剧情目标、操作说明、声音说明与“开演”按钮。简介等待期间静音、不消耗演出时间、不产生演出记录；背景点击和普通操演按键不越过简介。

`scripts/ui/stage_briefing.gd` 集中文案和版式，按钮只发出一次 `start_requested`。第一、二关由 `GameFlow` 延后处理信号，然后才创建宿主、时钟和录制；第三关连接原有 `start_scene()`，沿用候场与声音资源检查。没有新增依赖、修改记录格式或改动玩法判定。

## 已执行验证

所有命令通过 `tools/run_godot.ps1` 调用同一 `D:\Godot\4.7.2\godot.exe`，版本为 `4.7.2.stable.official.ed1daf0bf`。所有改动的 GDScript 在运行测试前均执行 `--check-only` 解析检查。

| 检查 | 实际结果 |
| --- | --- |
| 源工程 Windows/WASAPI 三关简介 | 71 项，0 失败；真实鼠标事件点击开演，等待混音峰值三关均为 0；验证零时钟、零点快照、不重复宿主、厅堂不重复简介和第三关复用 |
| Windows/WASAPI 媒体流程 | 49 项，0 失败；完整播放片头片尾，验证片头自然结束与 Esc 跳过均到简介，三条回放结束路径与返回首页 |
| 第一关实际录放 | 38 项，0 失败；44,283ms、2,181 快照、2,981 事件；重新演出先回简介 |
| 第二关入口与切关 | 174 项，0 失败；包含第一关三条收场路径、暂停跳关、第二关简介后开演 |
| 第二关厅堂换景 | 39 项，0 失败 |
| 第二关整关录放 | 59 项，0 失败；113,084ms、6,787 快照、64 事件 |
| 第三关完整结尾与回放 | 61 项，0 失败 |
| 资源导入 | 退出码 0；引擎补建旧测试 `run_act2_intro_replay.gd.uid`，该非任务产物已在验证后清理 |
| 无头启动 60 帧 | 退出码 0 |
| Windows Desktop release 导出 | 退出码 0，生成 `builds/dengxia.exe` 和 `builds/dengxia.pck` |
| 实际 PCK 的 Windows/WASAPI 三关简介 | 71 项，0 失败，三关等待混音均为 0 |
| 导出 exe 普通图形入口 120 帧 | 退出码 0，实际 Intel Arc OpenGL Compatibility，日志无错误 |
| A 范围整套行为测试 | 1,284 项及正式第一幕另 22 项断言通过，0 失败；退出告警见下方边界 |
| C 范围整套行为测试 | 464 项，0 失败；无退出资源告警 |

复跑命令如下；`-LogName` 对应日志前缀，日志位于 `builds/stage-realism/logs/`。

```powershell
& .\tools\run_godot.ps1 -LogName briefings-windows --path . --script res://tests/b/run_stage_briefings.gd
& .\tools\run_godot.ps1 -LogName briefings-cinematics --path . --script res://tests/b/run_cinematics_graphics.gd
& .\tools\run_godot.ps1 -LogName briefings-act1-replay --headless --path . --script res://tests/c/run_game_replay.gd
& .\tools\run_godot.ps1 -LogName briefings-act2-entry-final --headless --path . --script res://tests/c/run_act2_opening.gd
& .\tools\run_godot.ps1 -LogName briefings-act2-hall-final --headless --path . --script res://tests/c/run_act2_hall.gd
& .\tools\run_godot.ps1 -LogName briefings-act2-replay --headless --path . --script res://tests/c/run_act2_replay.gd
& .\tools\run_godot.ps1 -LogName briefings-act3-finale --headless --path . --script res://tests/c/run_act3_finale.gd
& .\tools\run_godot.ps1 -LogName briefings-import --headless --path . --import
& .\tools\run_godot.ps1 -LogName briefings-smoke --headless --path . --quit-after 60
& .\tools\run_godot.ps1 -LogName briefings-export --headless --path . --export-release '"Windows Desktop"' builds/dengxia.exe
& .\tools\run_godot.ps1 -LogName briefings-packed-windows --path . --main-pack builds/dengxia.pck --script res://tests/b/run_stage_briefings.gd
& .\tools\run_godot.ps1 -LogName briefings-suite-a --headless --path . --script res://tests/a/run_tests.gd
& .\tools\run_godot.ps1 -LogName briefings-suite-c --headless --path . --script res://tests/c/run_tests_c.gd
```

源工程三关实际截图与报告保存在 `builds/stage-briefings-source/`，PCK 复验在 `builds/stage-briefings/`。已逐张查看，确认剧情、操作、声音说明与按钮均可读，文字无越界或重叠。第二关旧入口测试退出前增加 100ms 混音回收时间；最终两项测试均无退出资源告警，未修改运行时音频实现。

## 验证边界

本轮实际图形验证覆盖三张简介及开演点击，声音验证读取 Windows/WASAPI 混音，媒体验证按真实时长播放两段视频；没有重新人工演完三关，也没有进行首次玩家可理解性的试玩。游戏启动需保留同目录 `dengxia.pck`。

A、C 整套测试中的未知动作、空记录及倒退时钟等错误日志来自刻意输入非法数据的防御性用例，相关断言均通过。A 范围测试退出另外报告 4 个 ObjectDB 实例与 1 个资源未释放，本轮没有修复或重新建立该告警的旧版本基线，不将其描述为无告警通过。简介、媒体、三关定向回归、导出包简介及发布程序启动的最终日志均没有该资源告警。
