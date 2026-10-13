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

## 2026-10-11 树后与门内手动出场

用户确认 1B / 2A / 3A / 4B / 5A：首次按 1 时法海在树右后方、按 2 时许仙在门洞内，各先露出部分身体；空格接手后手动分别向左／向右拖出。保留 200 身高、原地面、操作手和原输入。树的逐行外轮廓与右门框提供固定舞台遮罩，实体和投影同步隐藏被遮挡部分；幕布外竹签继续可见。实体及当前灯距投影走出入口后永久解除该人的遮罩。部分出场或完全出场后退场再上场均恢复原处和姿势，重复数字键不重置；遮挡区不响应影人的胸签抓取和右键退场。

新增 `scripts/act2/act2_entrance.gd`、共享 shader include 和 `tests/c/run_act2_entrances.gd`，显示端只增加默认关闭的可选遮罩。未修改布景原图、场景或工程配置。PRD、技术设计、第二关定案及 README 已同步；本轮直接实现并自查，未使用子智能体或独立代理审查。

回归先在旧实现复现 6 项入口／遮挡失败；遮挡区输入检查又复现左右键误命中，修复后结果如下：

| 实际命令（`tools/run_godot.ps1 -GodotArgs`） | 结果 |
| --- | --- |
| `--headless --path . --check-only --script <五个变动脚本>` | 全部退出 0 |
| `gdformat --check` / `gdlint` 五个变动脚本 | 全部通过 |
| `--headless --path . --script res://tests/c/run_act2_entrances.gd` | 30 项，0 失败 |
| `--path . --script res://tests/c/run_act2_entrances.gd` | Windows OpenGL，43 项，0 失败 |
| `--path . --script res://tests/c/run_act2_opening.gd` | Windows OpenGL，117 项，0 失败 |
| `--headless --path . --script res://tests/b/run_stage_visuals.gd` | 379 项，0 失败 |
| `--path . --script res://tests/b/run_stage_walk.gd` | Windows OpenGL，24 项，0 失败 |
| `--headless --path . --import` | 退出 0 |
| `--headless --path . --quit-after 60` | 退出 0，原有 ObjectDB/resource 退出提示仍在 |
| `--headless --path . --export-release "Windows Desktop" builds/dengxia.exe` | 退出 0 |
| `--path builds --main-pack dengxia.pck res://scenes/act2/opening.tscn --quit-after 60` | Windows 图形启动退出 0 |

使用同一 `D:\Godot\4.7.2\godot.exe`，精确版本 `4.7.2.stable.official.ed1daf0bf`，同版本导出模板存在。窗口测试经真实 viewport 输入管线执行，比较遮挡、无遮挡和缺席三种画面的像素：法海初始可见面积约为无遮挡的 36%，许仙约为 17%，投影亦为部分可见；已检查实际截图。未执行人工完整试玩或重跑 A/C 其他完整套件，未验证尚未接入的第二关整关录放。

日志在忽略的 `builds/stage-realism/logs/entrance-*`；截图在 `builds/act2-opening/entrance-fahai-start.png`、`entrance-xuxian-start.png`、`entrance-fahai-out.png`、`entrance-xuxian-partial.png` 和 `entrance-both-out.png`。导出产物为 `builds/dengxia.exe` 与同目录 `dengxia.pck`；正式回归测试及引擎生成的 UID 保留，无临时入口需要清理。

## 2026-10-11 许仙改为门洞中央直接上场

用户要求许仙直接在门的中间出场，覆盖上一版许仙从右门框逐渐露出的定案。现在按 2 时，许仙实体和投影在门洞中央（约 x=434.4 px）完整显示；仍需空格接手，退场再上场恢复原处。删除许仙专用门洞遮罩和右侧出场判据；法海沿用树后首次遮挡与手动走出。同步 PRD、技术设计、README 和第二关定案，原计划注明后续调整。

更新既有出场回归后，旧实现先复现 6 项位置／完整显露／胸签抓取失败；修正后 Windows OpenGL 出场测试 40 项、两关衔接与操演 117 项全部通过。实体和投影的许仙初始可见像素与无遮挡画面完全一致，已检查 `builds/act2-opening/entrance-xuxian-start.png`，人物落在门洞中间。三个变动脚本解析、gdformat 和 gdlint 通过；资源导入、60 帧无头启动和 Windows Release 导出均退出 0，本次启动日志没有退出资源提示。不表示此前间歇出现的第一关退出资源提示已被修复。

实际命令继续使用 `tools/run_godot.ps1`：`--headless --path . --check-only --script <三个变动脚本>`、`--path . --script res://tests/c/run_act2_entrances.gd`、`--path . --script res://tests/c/run_act2_opening.gd`、`--headless --path . --import`、`--headless --path . --quit-after 60`、`--headless --path . --export-release "Windows Desktop" builds/dengxia.exe`。本轮日志前缀 `door-center-*`，版本仍为 `4.7.2.stable.official.ed1daf0bf`。未重跑其他完整套件或人工完整试玩；没有新建临时测试入口，沿用现有分支和 PR #12。

## 2026-10-13 第二幕厅堂布景接入（编号 22）

用户要求「游戏里要能看到第二幕的景」。此前编号 22 的室内厅堂布景（队友 PR #14 交付）**只有数据，游戏里没有任何地方取用它**——第一场末句应允后的暗场只是停在全黑加「端阳」标题，没有下一场。本轮把它接进正式入口。

改了什么：

- 新增 `scenes/act2/hall.tscn` 与 `scripts/act2/act2_hall.gd`：复用 `StageBackdrop`、`StageSurface`、`MusicClock`、`LampController`，挂 `CStageBinding(stage_id=22, enable_rain=false)`，与第一场同一套层级（背幕 -2 → 幕布 -1 → 布景 0）和同一块幕布 `Rect2(66, 92, 1788, 588)`。本幕**没有主音轨**，时钟只提供真实时间给火光与幕面闪烁，歌曲时间保持冻结。
- `scripts/act2/act2_opening.gd`：新增 `scene_finished` 信号与 `DARK_HOLD_S = 1.5`。末句应允后暗场、清场，幕面全黑（`duration_ms`）之际「端阳」章节卡停留 1.5 秒，再发信号；不留这段时间标题一帧都不会显示。暂停时倒计时随之停住。
- `scripts/game_flow.gd`：新增编号常量与 `HALL_SCENE`。`_start_performance()` 把 22 当一幕加载；第一场的 `scene_finished` 经 `call_deferred` 换景到 22（信号来自正在运行的场景自身，不在发送过程中释放发送方）。两场之间不结算、不回放。
- 新增 `tests/c/run_act2_hall.gd`（38 项）：厅堂场景取到 22、13 件贴图实际加载、酒具绘制顺序在桌子之后、裁入幕布、层级正确、不放影人；主流程能把 22 当一幕加载；第一场收场后在章节卡走完前不换景、推迟到帧末执行、换景后旧宿主释放且只加载一个场景。

**本轮交付边界（用户 2026-10-13 定案「只把厅堂景摆进游戏」）**：第二场只显示布景，**不放影人、不接受操控输入**；递杯、抬杯饮酒、人身退场换完整白蛇、调灯显形与许仙惊倒仍属后续切片。整关录放、计分与时长预算同样未接入。

验证（`D:\Godot\4.7.2\godot.exe`，`4.7.2.stable.official.ed1daf0bf`）：

| 检查 | 本轮实际结果 |
| --- | --- |
| 三个变动/新增脚本解析（`--check-only`） | 全部退出 0 |
| `tests/c/run_act2_hall.gd`，无头 | 38 项，0 失败 |
| `tests/c/run_act2_opening.gd` | 133 项，0 失败 |
| `tests/c/run_act2_dialogue.gd` / `run_act2_entrances.gd` | 40 / 28 项，0 失败 |
| `tests/a/run_tests.gd` | 1284 + 22 项，0 失败 |
| `tests/b/run_stage_visuals.gd` | 379 项，0 失败 |
| `tests/c/run_tests_c.gd` / `run_scenery_tests.gd` | 459 / 480 项，0 失败 |
| 正式第一关回放 / 成功演出回放 / 旧教学关回放 | 37 / 12 / 11 项，0 失败 |
| 导入、60 帧无头启动、Windows Release 导出 | 全部退出 0 |
| 真实窗口抓帧（1920×1080） | 厅堂 13 件全部可见，见下 |

真实图形环境证据（`builds/act2-hall/`，`builds/` 已忽略）：

- `hall-onstage.png`：直接启动 `scenes/act2/hall.tscn` 的一帧——两柱围合、四根横梁、花架花盆、圆桌与桌上酒具、两凳，台口标题「第二关 · 端阳惊变　第二幕 · 端阳饮酒」。
- `chapter-card.png`：第一场收场瞬间，幕面全黑（alpha 1.00）加「端阳」章节卡。
- `after-switch.png`：同一趟运行 3 秒后，`_stage_id` 已为 22、宿主场景已换成 `res://scenes/act2/hall.tscn`。

抓帧用一次性 `SceneTree` 钩子（`root.get_texture().get_image().save_png`）在带窗口的引擎里取真实 GL 帧，用完已删；钩子里同时打印了 `stage_id` 与 13 件 id 作为逻辑读数。无头模式拿不到画面，故画面结论以这三张为准。

顺带修掉一个既有缺陷：`tests/c/run_tutorial_replay.gd` 缺少 `-- stage=2` 时只在第 24 行记一条失败就继续跑，随后在 `Nil` 上脚本错误、`quit()` 永不执行，**进程会一直挂着**（本轮实际挂满 20 分钟）。现在缺参数时提前干净退出并返回 1（实测 2 秒），带参数仍 11 项全过。该文件与本次功能无关，单独一个提交便于回退。

