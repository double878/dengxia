# 第二幕开发前整理计划

**目标：**从最新主干创建 `feat-act2`，统一现有代码格式，清理确认无用的临时文件，交付可继续开发第二幕的已验证基线。

**实现边界：**沿用 Godot 4.7.2 Standard 和现有 A/B/C 模块；本次不实现第二幕，不迁移历史关卡，不改变输入、时钟、判定或回放契约。不使用子智能体或另建工作树，按项目要求在新分支顺序执行。

**工具：**GDScript、Godot `4.7.2.stable.official.ed1daf0bf`、Python 3.10+、gdtoolkit 4.5.0（仅开发工具）。

## 切片 1：审查与分支

- 输入：`git status`、`origin/main`、PRD、技术设计、现有源码与资源引用。
- 输出：分支名、基线结果、删除候选与保留理由。
- 约束：已有未跟踪文件先备份；不删正式测试、素材原稿或来源证据。
- 验收：分支从最新 `origin/main` 创建；精确引擎和模板版本确认；A/C 基线与三项门禁通过。
- [x] 检查工作区并备份临时测试入口及 UID。
- [x] `git fetch origin` 后执行 `git switch -c feat-act2 origin/main`。
- [x] 验证引擎版本、模板、资源导入、启动、Windows 导出与 A/C 套件。

## 切片 2：规范化与清理

- 输入：切片 1 的代码基线和引用审查结果。
- 输出：格式/静态检查配置、统一后的代码、开发入口说明、清理清单。
- 约束：保留变量初始化顺序、UID、场景路径、历史原型；不修改 `.godot` 导入缓存。
- 验收：全部 GDScript 可重复通过格式检查；基础静态检查通过；格式变化通过语法树和注释保留检查；正式包排除测试文件。
- [x] 添加 `.editorconfig`、`.gdformatrc`、`.gdlintrc`、固定版本的开发依赖与 README。
- [x] 用 gdformat 安全模式整理 `scripts/` 与 `tests/`；修正局部变量命名及未使用形参标记。
- [x] 删除已备份的临时测试入口、失败导出残留和 Python 字节码缓存。
- [x] 在导出预设中排除 `tests/`、`tools/` 和 `docs/`，保留运行时实际依赖的 `scripts/a_test/`。

## 切片 3：验证与交付

- 输入：切片 2 的最终 diff、现有测试入口和导出包。
- 输出：命令/退出码、断言汇总、审查结果、提交与远端分支。
- 约束：先解析检查，再跑行为套件；失败只定向排查，最多 3 轮；不把无头验证说成人工试玩。
- 验收：格式和静态检查、Godot 解析、A/B/C 行为回归、三项门禁及导出包启动通过；无临时入口遗留；分支推送后工作区干净。
- [x] 对修改脚本执行 `--headless --path . --check-only --script <文件>`。
- [x] 运行 A/C 总入口、B 视觉/音频、布景、步态、正式录放和旧教学关回归。
- [x] 重新执行三项门禁；核查 PCK 文件清单与 release 启动。
- [x] 审查 diff、记录既有日志提示与第二幕接入差异，确认仅包含本次整理的提交范围。

## 第二幕入口与差异

PRD 第 6.2 节的第二幕为 105 秒《端阳惊变（酒变）》，目标包括全场影子缩放、换头和倾灯显露。现有 `StageDef.make_level2()` 为历史 45 秒双人教程，不能当作正式第二幕。正式第一幕在 `level1_a_scene.gd` 中使用 `Act1OperaStage` 与真实音源配置；第二幕需另行确定内容和接入，继续复用唯一 `MusicClock`、`Level1Harness`、`CLiveCapture` 与 `GameFlow` 的录放链路。

PRD 的三幕时长与技术设计历史五关口径有差异；正式第一幕又已按实际音源编排。本次仅记录这些差异，不能宣称三幕总时长预算或第二幕已完成。

## 实际整理结果

- 102 份 GDScript 中 90 份统一格式；另有 3 个局部变量和 2 个未使用形参的命名修正。保留模块、初始化顺序、UID、场景路径和素材。
- gdformat 4.5.0 展开嵌套多行 lambda 后，两处测试的闭括号缩进不被 Godot 接受。秒级解析检查定位后，将这两处原有回调绑定到命名 `Callable`；两份脚本复查通过，相关完整录放回归通过。没有关闭格式检查或修改断言。
- 删除 `tests/a/_xiaoqing_slice_tmp.gd` 及 UID（先备份到 `$env:TEMP/dengxia-cleanup-20261011-131015/`）、3 个 `builds/dengxia.exe~*.TMP`、3 个 Python 字节码文件及空缓存目录，释放约 312 MiB。
- 删除无人引用的一次性交接消息 `docs/handoff/C-to-B-message.txt`：其中旧手角范围、尚无素材等描述已过时，详细历史交接仍保留在 `C-to-B-replay.md`，当前契约由 README 指向正式录放补充。
- 开发环境、字节码、临时测试入口及失败导出残留加入忽略规则。研究缓存、音频制作工程和正式素材保留，以免丢失来源与可编辑数据。

## 实际验证

执行引擎统一为 `D:\Godot\4.7.2\godot.exe`。修改脚本先做解析检查；通过后执行行为套件。格式与基础静态检查使用固定的 gdtoolkit 4.5.0 和仓库配置：

```powershell
gdformat --check scripts tests
gdlint scripts tests
godot.exe --headless --path . --check-only --script res://<修改的脚本>
godot.exe --headless --path . --import
godot.exe --headless --path . --quit-after 60
godot.exe --headless --path . --export-release "Windows Desktop" "builds/dengxia.exe"
```

以上最终检查均 exit 0。全部 102 份脚本通过语法树、注释保留与格式稳定性比较；比较时明确允许上述 5 个名称变化和 2 个测试回调绑定。90 份修改脚本最终均通过 Godot 解析。另检查文本 LF 与 `git diff --check`。

以下逻辑套件使用 `--headless --path . --script res://<入口>`；Windows 套件不加 `--headless`。

| 入口 | 最终结果 |
| --- | --- |
| `tests/a/run_tests.gd` | 1284 + 22 条通过，0 失败 |
| `tests/c/run_tests_c.gd` | 459 条通过，0 失败 |
| `tests/c/run_scenery_tests.gd` | 94 条通过 |
| `tests/b/run_stage_visuals.gd` | 379 条通过 |
| `tests/b/run_performance_audio.gd` | 53 条通过 |
| `tests/b/run_act1_game_audio.gd` | 26 条通过 |
| `tests/c/run_game_replay_success.gd` | 12 项通过，实际演出/回放记录 117617 ms |
| `tests/c/run_tutorial_replay.gd -- stage=2` | 11 项通过 |
| `tests/b/run_stage_walk.gd`，Windows 图形 | 24 项通过 |
| `tests/c/run_game_replay.gd`，Windows 图形 | 43 项通过，记录 44283 ms；已查看幕前截图 |
| `tests/b/run_replay_audio.gd`，Windows 音频 | 12 项通过，stderr 为空 |

合计 2419 条断言/检查通过。PCK 目录核查共 191 个打包条目，没有 `tests/`、`tools/`、`docs/` 文件；真实音源配置、正式场景和宿主引用存在。在 `builds/` 工作目录执行 `dengxia.exe --headless --quit-after 60`，独立 release 启动 exit 0。

日志位于忽略目录 `builds/stage-realism/logs/`，前缀为 `normalize-`；截图在 `builds/stage-walk/`。A/C 非法输入用例的预期 ERROR 与既有 ObjectDB/resource 退出提示仍然存在；启动和 release 短时退出也出现释放提示，不能描述为无警告。未重做整幕真实时间 Windows 演出、人工键鼠手感、主观听感或比赛机性能验收。
