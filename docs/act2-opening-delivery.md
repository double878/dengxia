# 法海与两关衔接交付

## 实际改动

- 法海按用户参考原图制作 14 件透明 atlas：身体 12 件、饰带、锡杖。毗卢帽、卷须、红色田相袈裟、花袖与法器保留源图颜色和纹样；手工轮廓与原稿可追溯。
- 显示端用独立 skin_override，不占用第一关的六个头映射。锡杖跟随右腕，实体与投影共用骨架和翻面。
- 第二关独立开场：`1/2` 仅上场，空格按编号循环接手，右键退场。重复上场不重置姿势；接手清空旧拖动和翻面目标；ESC 与按钮暂停。
- 第一关仍先询问是否观看回放。不看、跳过、看完三条路径都进入无重演/重看按钮的收场页；左/中/右键点任意位置进入第二关，排除滚轮和释放、阻止重复加载与输入穿透、释放旧记录和旧场景。
- 同步 PRD、TECH_DESIGN、README 与用户已确认的第二关设计。

## 当前边界

本次只有第二关开场操演。两场对白音源、交杯与饮酒、完整白蛇、惊倒、整关计分与第二关录放尚未接入；不能把开场称为完整第二关。原图 JPEG 的 alpha 是白底估算，背面是同一分件镜像。

## 验证结果

使用 `D:\Godot\4.7.2\godot.exe`，版本 `4.7.2.stable.official.ed1daf0bf`。

| 检查 | 结果 |
| --- | --- |
| gdformat 全部 scripts/tests | 104 文件无需改动 |
| gdlint 全部 scripts/tests | 无问题 |
| 五个变动 GDScript 的 --check-only | 全部退出 0 |
| tests/a/run_tests.gd | 1284 + 22 条断言通过 |
| tests/b/run_stage_visuals.gd | 379 条断言通过 |
| tests/c/run_game_replay.gd | 37 项通过 |
| tests/c/run_game_replay_success.gd | 12 项通过 |
| tests/c/run_act2_opening.gd，无头 | 57 项通过 |
| 同一开场回归，实际 Windows OpenGL 窗口 | 60 项通过，含 3 张截图 |
| atlas/source | 14 件、RGBA、2048×2048、透明边角/水印区域、原稿 SHA256 一致 |
| 既有三角色 manifest | 去掉新法海条目后与原提交完全一致 |
| 资源导入、60 帧无头启动、Windows Release 导出 | 全部退出 0 |
| 导出 PCK 中第二关独立开场启动 | 退出 0 |
| 实际导出 dengxia.exe 默认入口启动 | 退出 0 |

定向回归先观察到旧版本缺少第二关、收场仍有两个按钮；另一个定向测试先复现了切换影人时翻面目标泄漏，修复后均通过。测试通过 viewport 输入管线验证键鼠事件和 GUI 消费，并非人工完整试玩或对白听感验收。

A 套件的非法输入用例会故意输出 ERROR。完整第一关无头启动/套件退出仍有基线已有的 ObjectDB/resource 释放提示；不将退出码 0 描述成无警告通过。第二关独立开场启动没有该提示。

## 复核命令

```powershell
& 'C:\Temp\dengxia-normalize-py313\Scripts\gdformat.exe' --check scripts tests
& 'C:\Temp\dengxia-normalize-py313\Scripts\gdlint.exe' scripts tests
& .\tools\run_godot.ps1 -LogName act2-release-headless -GodotArgs @('--headless','--path','.','--script','res://tests/c/run_act2_opening.gd')
& .\tools\run_godot.ps1 -LogName act2-release-graphics -GodotArgs @('--path','.','--script','res://tests/c/run_act2_opening.gd')
& .\tools\run_godot.ps1 -LogName act2-gate-import -GodotArgs @('--headless','--path','.','--import')
& .\tools\run_godot.ps1 -LogName act2-gate-startup -GodotArgs @('--headless','--path','.','--quit-after','60')
& .\tools\run_godot.ps1 -LogName act2-gate-export-fixed -GodotArgs @('--headless','--path','.','--export-release','"Windows Desktop"','builds/dengxia.exe')
& .\tools\run_godot.ps1 -LogName act2-packed-opening -GodotArgs @('--headless','--path','builds','--main-pack','dengxia.pck','res://scenes/act2/opening.tscn','--quit-after','60')
```

工具包装器使用 Start-Process，含空格的导出预设需要保留双引号；第一次未加引号得到 `Invalid export preset name: Windows`，修正命令后导出成功。发布模板禁止命令行替换 scene path，故直接给导出 exe 传第二关场景的探针被模板拒绝；改用同版本编辑器读取实际 PCK 验证第二关资源，并单独验证导出 exe 默认入口。

日志：忽略的 `builds/stage-realism/logs/act2-*`；图形证据：`builds/act2-opening/fahai-onstage.png`、`fahai-turn-raised.png`、`fahai-close-lamp.png`。源素材预览：`docs/art/fahai-cutout.png`。

本轮按用户要求由同一代理实施并自查，没有调用子智能体；未执行独立代理代码审查。自查覆盖第一关头架映射、上下场/接手不变量、旧状态泄漏、三条收场路径与发布资源加载。

## 2026-10-11 操作手修复

第二关开场遗漏了操作手绘制及手边抓签的输入换算。现将第一关原有手与短签绘制提取到 `scripts/b/operator_hand.gd`，两关共用；第二关用前景层显示，未接手时也保留操作手。空格接手后，左键拖操作手或短签可移动当前影人；移动、换人后仍映射到当前胸签，松开或暂停会结束拖动。底部提示同步说明手边竹签可拖动。

定向测试先在旧实现复现 5 项手边拖动失败；修复后无头回归 70 项、Windows OpenGL 窗口回归 77 项通过，覆盖未接手不拖动、手掌/短签落点、移动后重抓、换人后的拖动对象、松开结束及手掌像素可见性。第一关 `tests/b/run_stage_walk.gd` 图形回归 24 项通过，已检查两关截图；未执行人工试玩或重跑其他完整套件。四个改动脚本解析、格式与 lint 通过；导入、60 帧启动、Windows Release 导出和 PCK 第二关启动均退出 0。默认第一关启动仍有前述 ObjectDB/resource 基线退出提示。

本次命令沿用上方包装器：开场回归使用 `hand-headless-final` / `hand-graphics-final` 日志名，第一关图形回归使用 `hand-level1-graphics`；门禁使用 `hand-import` / `hand-startup` / `hand-export` / `hand-packed-opening`。日志保存在 `builds/stage-realism/logs/hand-*`，新增截图为 `builds/act2-opening/operator-hand-idle.png` 与 `operator-hand-dragged.png`。自查确认只涉及操作手绘制、输入映射和相应回归；没有调用子智能体。

## 2026-10-11 队友布景接入与主干合并

队友 [PR #9](https://github.com/double878/dengxia/pull/9) 已合入 `main@955d72a`，交付的是门楼、菊石与柳树布景资源及数据。先将最新主干合入 `feat-act2`，自动合并无冲突；再在正式第二关开场挂载 `CStageBinding(stage_id=2, enable_rain=false)`，人物脚点取第二关门楼基线（约 661 px）。布景构图、贴图与裁剪沿用队友实现，三份新增 C 脚本统一格式；第一关衔接、操作手和空格接手保持可用。完整第二关剧情的交付边界沿用上文。

新增回归先在未接入版本复现三条收场路径均缺少布景绑定，接入后的验证如下：

| 检查 | 本轮实际结果 |
| --- | --- |
| 五个变动脚本解析 | 全部退出 0 |
| gdformat / gdlint scripts tests | 106 文件格式通过，lint 无问题 |
| 第二关切关与操演，无头 / Windows 窗口 | 109 / 117 项通过；检查三件实际贴图、幕布裁剪、层级、地面与键鼠 |
| 布景数据套件 | 116 项通过 |
| A 行为套件 | 1284 + 22 项通过，0 失败 |
| B 视觉套件 | 379 项通过 |
| C 录放套件 | 459 项通过，0 失败 |
| 正式第一关回放 / 成功演出回放 | 37 / 12 项通过 |
| 第一关 Windows 画面与步态 | 24 项通过 |
| 导入、60 帧启动、Windows Release 导出 | 全部退出 0 |
| 导出 PCK 中第二关开场启动 | 退出 0 |

命令仍为上方 `tools/run_godot.ps1` 包装器，测试入口见表中套件；本轮日志前缀为 `scenery-integration-*`。实际窗口截图见 `builds/act2-opening/act2-scenery-onstage.png` 与 `operator-hand-idle.png`。已检查窗口画面；键鼠通过 viewport 输入管线自动验证，未执行人工完整试玩。非法输入测试按预期输出 ERROR；默认第一关启动与 A 套件仍有已知 ObjectDB/resource 退出提示。未调用子智能体，已直接审查集成差异、双方布景数据与状态边界。

## 2026-10-11 人物缩小至房门高度

按用户要求，许仙与法海的站立身高参数从 300 调为 200，缩小约三分之一；两者实体与幕布投影共用 `FIGURE_HEIGHT`，实际冠帽轮廓高度接近门楼的房门上沿。脚点沿用 661 px 地面，锡杖和竹签连接跟随现有视图缩放。

本次只调整显示尺寸并记录交付。脚本解析、gdformat、gdlint 通过；`tests/c/run_act2_opening.gd` 在 Windows 窗口中 117 项通过，已检查 `act2-scenery-onstage.png`。导入、60 帧无头启动、Windows Release 导出均退出 0，默认第一关启动仍有原有 ObjectDB/resource 退出提示；未重跑其他完整套件、未新增尺寸常量的镜像测试。命令沿用上方包装器，日志为 `act2-scale-parse` / `act2-scale-graphics` / `act2-scale-import` / `act2-scale-startup` / `act2-scale-export`。
