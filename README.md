# 灯下

Godot 4.7.2 Standard 的 Windows 皮影戏 Demo。正式入口为 `scenes/game_flow.tscn`，包含第一幕幕后演出、观众选择、幕前回放，以及点击收场页进入第二关开场。

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

先导入资源；修改脚本后先用 `--check-only --script res://<文件>` 做解析检查。行为测试统一使用：

```powershell
& .\tools\run_godot.ps1 -LogName local-a -GodotArgs @('--headless','--path','.','--script','res://tests/a/run_tests.gd')
```

其他套件替换 `LogName` 和脚本路径：

| 入口 | 覆盖 |
| --- | --- |
| `tests/a/run_tests.gd` | 操控、双时钟、判定、补救、灯、道具与第一幕编排 |
| `tests/c/run_tests_c.gd` | 录制、回放、记录校验与结果流程 |
| `tests/c/run_scenery_tests.gd` | 布景与状态绑定 |
| `tests/b/run_stage_visuals.gd` | 实体/投影几何、灯和道具附件 |
| `tests/b/run_performance_audio.gd` | 音频时间轴与状态 |
| `tests/b/run_act1_game_audio.gd` | 正式第一幕音源、等待与暂停 |
| `tests/b/run_stage_walk.gd` | 桥面、距离驱动步态与正式入口 |
| `tests/c/run_act2_opening.gd` | 三条第一关收场路径、点击切关、法海外观绑定、第二关开场键鼠与暂停 |
| `tests/c/run_game_replay.gd` | 实际记录与选择/重看/跳过/再演 |
| `tests/c/run_game_replay_success.gd` | 完整接还伞与回放 |
| `tests/c/run_tutorial_replay.gd`（追加 `-- stage=2`） | 旧教学关挂起、取回、换头与节拍回放 |

非法输入测试会刻意产生 `ERROR` 日志；A 套件存在既有的退出时 ObjectDB/resource 释放提示。检查断言、退出码和具体日志来源，不把这些提示隐瞒为无警告通过。无头测试不能代替 Windows 下的听感、输入手感、画面与性能验收；音频混音专项使用 `tests/b/run_replay_audio.gd` 并去掉 `--headless`。

## 第二幕开发基线

开发分支：`feat-act2`。用户已确认 [第二关两场设计](docs/superpowers/specs/2026-10-10-act2-design.md)：法海劝酒、端阳惊变；改用数字键上场、空格循环接手、右键退场，完整白蛇替身与灯光显形。时长按实际对白和音乐编排决定，取消固定 105 秒。

当前切片提供法海独立分件、持杖操演，以及第一关收场点击进入第二关开场。直接查看开场：

```powershell
& 'D:\Godot\4.7.2\godot.exe' --path . 'res://scenes/act2/opening.tscn'
```

按 `1` 法海上场、`2` 许仙上场，空格循环接手；左键拖胸签，`A/D` 抬手，`Shift+A/D` 落手，`W/S` 双手抬落，右键点影人下场，滚轮与 `Q/E` 调灯，`ESC` 暂停。当前开场没有对白、递酒、变蛇、惊倒、整关计分与第二关录放，不会按旧教学时长自动结束。

`tools/build_fahai_assets.py` 用 Pillow 和 NumPy 重建 atlas；原图保留在 `assets/puppets/source/`，该目录由 `.gdignore` 排除导入和导出。透明整身预览在 `docs/art/fahai-cutout.png`。不需要图像生成 API，也不增加游戏运行依赖。

现有 `StageDef.make_level2()` / `-- stage=2` 是 **45 秒的旧双人教学关**，并非正式第二幕。第一幕由 `level1_a_scene.gd` 选择 `Act1OperaStage` 与真实音源配置；新幕接入应继续复用唯一 `MusicClock`、`Level1Harness`、`CLiveCapture` 和 `GameFlow`，画面只读状态，回放不重新判定。

PRD 已采用三幕，技术设计仍有五关旧条款，第一幕实际时长又由音源决定；第二幕制作前需要对齐关卡数据、选幕入口、音源长度与总时长预算。本次整理保留当前可验证行为，具体范围和验收见 [第二幕准备计划](docs/superpowers/plans/2026-10-11-act2-preparation.md)。
