# 灯下

Godot 4.7.2 Standard 的 Windows 皮影戏 Demo。正式入口为 `scenes/game_flow.tscn`。第一关收场进入第二关「法海劝酒 / 端阳惊变」，第二关整关真实回放后进入第三关《盗仙草》。第三关是一场连续演出：开演即播放视频原声，白素贞近山后，鹿童随前奏末尾重音跳出；求情后自动拔剑，玩家自由操演白素贞，鹿童、鹤童按唱词接战并随玩家位置配合，不做跌倒。已有原声约 140.1 秒，播完保留同一舞台，后续素材待补，整关完成后才开放幕前回放。详见 [第二关回放交付](docs/act2-replay-delivery.md) 和 [第三关连续打戏交付](docs/act3-fight-delivery.md)。

可在 Godot 打开 `scenes/act3/rehearsal.tscn` 按 F6 直接排练第三关，也可执行 `& 'D:\Godot\4.7.2\godot.exe' --path . res://scenes/act3/rehearsal.tscn`。

导出后运行 `& .\tools\play_act3.ps1`，直接打开第三关排练。导出模板禁止场景路径覆盖，因此脚本使用 `builds/dengxia.exe -- --act3-rehearsal` 启动参数。

开始修改前阅读 [AGENTS.md](AGENTS.md)、[PRD.md](PRD.md) 与 [TECH_DESIGN.md](TECH_DESIGN.md)。当前录放行为以 [录放契约顶部的正式入口补充](docs/REPLAY_CONTRACT.md) 和当前代码为准；`docs/handoff/`、早期计划中的参数属于历史交接记录。

## 运行与门禁

统一使用 Godot `4.7.2.stable.official.ed1daf0bf` 和 `4.7.2.stable` Windows 导出模板。下面使用本机安装路径；其他机器只替换同版本可执行文件路径。

```powershell
& 'D:\Godot\4.7.2\godot.exe' --headless --path . --import
& 'D:\Godot\4.7.2\godot.exe' --path .
```

每轮三项门禁：

```powershell
New-Item -ItemType Directory -Path builds -Force | Out-Null
& 'D:\Godot\4.7.2\godot.exe' --headless --path . --import
& 'D:\Godot\4.7.2\godot.exe' --headless --path . --quit-after 60
& 'D:\Godot\4.7.2\godot.exe' --headless --path . --export-release 'Windows Desktop' 'builds/dengxia.exe'
```

自动检查可复用 `tools/run_godot.ps1`，它等待进程结束、返回真实退出码，并保存 stdout/stderr 到 `builds/stage-realism/logs/`。导出包排除 `tests/`、`tools/`、`docs/`；`scripts/a_test/` 内含正式入口仍在使用的宿主、输入和画面实现，不能按目录名删除。

## 代码格式与静态检查

开发工具需要 Python 3.10+；本机可使用 `py -3.13`。工具只装入虚拟环境，不成为游戏依赖：

```powershell
py -3.13 -m venv .venv
& .\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
& .\.venv\Scripts\gdformat.exe scripts tests
& .\.venv\Scripts\gdformat.exe --check scripts tests
& .\.venv\Scripts\gdlint.exe scripts tests
```

- 文本使用 UTF-8、LF 和末尾换行；GDScript 与 shader 使用 Tab 缩进。
- GDScript 由 gdformat 统一，目标行宽 100；长字符串、资源路径和注释允许超过目标行宽。
- 保留格式器安全检查，验证语法树、注释保留与重复格式化稳定性；不要使用 `--fast`。
- 多行回调先绑定命名 `Callable`，避免 gdformat 4.5.0 在嵌套调用中生成 Godot 不接受的 lambda 闭括号缩进；格式检查后仍需做 Godot 解析检查。
- 基础静态检查保留命名、未使用形参、重复加载、无效表达式和空白等规则。声明顺序保留现有初始化语义；分派函数提前返回和公开方法数量由代码审查判断，不使用全局数量限制。单文件上限为 1500 行，新增功能优先沿模块边界拆分。
- 形参因接口兼容而保留但未使用时加 `_` 前缀；普通局部变量用 `snake_case`，常量用 `UPPER_SNAKE_CASE`。
- 不格式化引擎生成的导入数据；不要删除 `.gd.uid`、素材原稿、来源说明或正式回归测试。

## 测试入口

人形操作：左键拖手自动弯肘，拖头俯仰，Alt+左键拖躯干前倾，R 恢复上身。A/D 抬手、Shift+A/D 落手。W 按一次原地张腿短跳，空中锁定身形、落地恢复，按住不连跳；S 压身后撤一步，保持朝向。三关人形统一，完整白蛇保持原分节操作。普通胸签/手边竹签拖动继续移动和蹲站。

先导入资源；修改脚本后先用 `--check-only --script res://<文件>` 做解析检查。行为测试统一使用：

```powershell
& .\tools\run_godot.ps1 -LogName local-a -GodotArgs @('--headless','--path','.','--script','res://tests/a/run_tests.gd')
```

其他套件替换 `LogName` 和脚本路径：

| 入口 | 覆盖 |
| --- | --- |
| `tests/c/run_act3_fight.gd` | 连续打戏、自动出鞘、双童配合、真实接剑、没有强制跌倒与三人回放 |
| `tests/b/run_act3_fight_graphics.gd` | Windows 实时原声衔接、出鞘、双童接战、暂停/恢复与幕前音画 |
| `tests/a/run_tests.gd` | 操控、双时钟、判定、补救、灯、道具与第一幕编排 |
| `tests/a/run_upper_body.gd` | 双臂、头腰、正式输入、复位、旧数据与新姿态录放、实际腕点判定 |
| `tests/b/run_upper_body_graphics.gd` | Windows 图形环境中的正式输入、提示、持杖/持伞及幕前姿态回放（不加 `--headless`） |
| `tests/c/run_tests_c.gd` | 录制、回放、记录校验与结果流程 |
| `tests/c/run_scenery_tests.gd` | 布景与状态绑定 |
| `tests/b/run_stage_visuals.gd` | 实体/投影几何、灯和道具附件 |
| `tests/b/run_performance_audio.gd` | 音频时间轴与状态 |
| `tests/b/run_act1_game_audio.gd` | 正式第一幕音源、等待与暂停 |
| `tests/b/run_stage_walk.gd` | 桥面、距离驱动步态与正式入口 |
| `tests/c/run_act2_opening.gd` | 三条第一关收场路径、点击切关、法海外观绑定、第二关开场键鼠与暂停 |
| `tests/c/run_act2_entrances.gd` | 法海树后手动出场、许仙门中直接上场、恢复进度、遮挡区命中与 Windows 像素验收 |
| `tests/c/run_act2_hall.gd` | 第二幕厅堂布景接入（编号 22）、主流程加载 22 号、第一场收场自动换景 |
| `tests/c/run_act2_actions.gd` | 第二幕实际递杯饮酒、左右正式离场、误退场恢复、换蛇、分节长度与惊倒门槛 |
| `tests/c/run_act2_remedy.gd` | 第二幕 8 秒补救、成功/超时、暂停、误退恢复与独立目标；音频检查推荐 Windows 图形环境 |
| `tests/c/run_act2_hall_audio.gd` | 七句对白、连续唱腔、真实动作许可、主轨冻结与前向跳段 |
| `tests/c/run_act2_music_cues.gd` | 法海出场音乐、开口停乐与真实落地一次重音 |
| `tests/c/run_act2_replay.gd` | 正式两场整关录放、观看/不看/暂停/跳过/自然结束、收场点击和第三关入口；Windows 模式另检查实际混音与暂停像素，追加 `-- realtime` 跑完整实时 1:1 回放，追加 `-- live` 连实际音轨录制也实时执行 |
| `tests/b/run_act2_voice_graphics.gd` | Windows 实时主轨、暂停/缺场静音、完整演唱、饮后对白与倒地混音（不加 `--headless`） |
| `tests/b/run_act2_actions_graphics.gd` | Windows 图形输入完整走第二幕，Q/E 压灯显形、蛇头/躯干拖动和惊倒截图（不加 `--headless`） |
| `tests/c/run_game_replay.gd` | 实际记录与选择/重看/跳过/再演 |
| `tests/c/run_game_replay_success.gd` | 完整接还伞与回放 |
| `tests/c/run_tutorial_replay.gd`（追加 `-- stage=2`） | 旧教学关挂起、取回、换头与节拍回放 |

非法输入测试会刻意产生 `ERROR` 日志；A 套件存在既有的退出时 ObjectDB/resource 释放提示。检查断言、退出码和具体日志来源，不把这些提示隐瞒为无警告通过。无头测试不能代替 Windows 下的听感、输入手感、画面与性能验收；音频混音专项使用 `tests/b/run_replay_audio.gd` 并去掉 `--headless`。

## 第二幕开发基线

第二场沿用第一关补救：当前动作提示出现后准备 8 秒，仍未完成则开启 8 秒补救窗口，显示师父手、目标方向、琥珀框并播放已有慢锣鼓。完成后结束提示，菜单暂停冻结补救计时；超时仍等待真实动作，同一步不反复开窗。第二场现已接入唱腔，节拍评分仍属后续切片，此处按动作停滞触发，详细验收见 [补救交付](docs/act2-remedy-delivery.md)。

用户已确认 [第二关两场设计](docs/superpowers/specs/2026-10-10-act2-design.md)：法海劝酒、端阳惊变；改用数字键上场、空格循环接手、右键退场，完整白蛇替身与灯光显形。时长按实际对白和音乐编排决定，取消固定 105 秒。

当前提供法海独立分件、自然对白与持杖操演，第一关收场点击进入第二关第一场「法海劝酒」，第一场收场后自动换景进第二场「端阳饮酒」。第二场完成 [人物动作](docs/superpowers/specs/2026-10-13-act2-actions-design.md) 与 [七句对白、连续饮前对唱](docs/audio/2026-10-14-act2-wine-dialogue-integration.md)。法海出场配用户视频音乐、开口前停，许仙落地响一次视频重音。第一场使用队友提交的门楼、菊石和柳树布景，第二场使用室内厅堂布景（编号 22）。直接查看两场：

```powershell
& 'D:\Godot\4.7.2\godot.exe' --path . 'res://scenes/act2/opening.tscn'
& 'D:\Godot\4.7.2\godot.exe' --path . 'res://scenes/act2/hall.tscn'
```

按 `1` 法海上场、`2` 许仙上场，空格循环接手；左键拖胸签或手边竹签，`A/D` 抬手，`Shift+A/D` 落手，`W` 张腿短跳，`S` 压身后撤，右键点影人下场，滚轮与 `Q/E` 调灯，`ESC` 暂停。两场之间暗场换景，完整演出后的真实回放与收场沿用现有流程。

第一场末句应允后自动暗场、清场，「端阳」章节卡停留 1.5 秒后换到第二场。第二场开场白素贞与许仙对坐，小青站在白素贞后侧。`1/2/3/4` 对应白素贞/许仙/小青/白蛇，空格循环接手，拖离凳子自动起身。白素贞应允后小青先答「好吧」，再走到左台边右键退场；许仙与白素贞先唱完约 41 秒的连续劝酒对唱，才开放拖手取杯、双手交接、送杯到嘴边饮酒。饮后接手白素贞，按住 Alt 向前拖躯干弯腰，才触发不适普通对白；饮前已经弯腰时先按 R 扶正再弯。弯腰也有原补救示范。许仙走到右台边取药退场后，按住 Q 压灯、右键收白素贞、按 4 上白蛇、按住 E 显形；拖蛇头弯颈身，拖躯干整移。按 2 返回许仙，接手走近白蛇后自动惊退仰倒。普通身段自由，关键动作一直等待实际输入。第二关整关评分与录放尚未接入；最新声音证据见 [声音交付](docs/audio/2026-10-14-act2-wine-dialogue-integration.md)。

首次上场时，法海在树右后方露出一点；空格接手后，从手边抓签向左拖出，出场过程受树遮挡，完全走出后在布景前自由表演。许仙直接在门洞中央完整上场，空格接手后可以自由移动。右键退场后再上场恢复原位置、姿势和出场进度。点树的遮挡区域不会误抓取或退场，手边竹签始终可拖动。

`tools/build_fahai_assets.py` 用 Pillow 和 NumPy 重建 atlas；原图保留在 `assets/puppets/source/`，该目录由 `.gdignore` 排除导入和导出。透明整身预览在 `docs/art/fahai-cutout.png`。不需要图像生成 API，也不增加游戏运行依赖。

现有 `StageDef.make_level2()` / `-- stage=2` 是 **45 秒的旧双人教学关**，并非正式第二幕。第一幕由 `level1_a_scene.gd` 选择 `Act1OperaStage` 与真实音源配置；新幕接入应继续复用唯一 `MusicClock`、`Level1Harness`、`CLiveCapture` 和 `GameFlow`，画面只读状态，回放不重新判定。

PRD 已采用三幕，技术设计仍有五关旧条款，第一幕实际时长又由音源决定；第二幕制作前需要对齐关卡数据、选幕入口、音源长度与总时长预算。本次整理保留当前可验证行为，具体范围和验收见 [第二幕准备计划](docs/superpowers/plans/2026-10-11-act2-preparation.md)。
