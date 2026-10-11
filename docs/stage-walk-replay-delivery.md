# 正式入口的桥面、小步走与观众选择回放

对应用户确认的 1A / 2A / 3A；分支 `feat-stage-walk-replay`。从 `scenes/game_flow.tscn` 进入实际演出，布景绑定复用队友 `1739111`，没有合并其整个分支。

白素贞和小青开场脚点沿桥贴图的桥面轮廓放置；白素贞横向拖动时上下桥，岸边接还许仙的伞。迈步随实际位移交替，停下收脚，身体轻微起伏且伞跟随实际腕点，玩家的手角不被步态修改。

正式 Harness 每个固定步末把已更新状态与统一事件交给 CLiveCapture。真实时间是录放时间轴，歌曲时间另存，因此等待与补救完整保留，前向跳段不会播放被跳过的对白。录制包含开场 t=0、步态、换头、挂起、灯、在场名单、伞归属与交接进度、音源位置/暂停/等待增益及收锣事件。回放只读记录，不重新操控、推进剧情或评分。

演出结束先显示“观看幕前回放 / 不看回放”。不看、自然结束、跳过都进入本幕收场，可观看同一条记录或再演；再演释放旧记录。幕前只显示镜像后的幕布、布景、影人及伞，没有幕后手和签。雨幕与灯光使用记录时间，暂停音画均冻结。旧教学关继续复用既有合成节拍。

## 已执行验证

统一引擎：`D:\Godot\4.7.2\godot.exe`，版本 `4.7.2.stable.official.ed1daf0bf`。

以下脚本均使用 `--path . --script res://<路径>`；逻辑套件加 `--headless`，图形/音频套件使用实际 Windows 窗口。

| 验证 | 结果 |
| --- | --- |
| 本切片 21 个新增/修改脚本 `--check-only --script` | 全部解析成功；第一切片另有 7 个脚本解析成功 |
| tests/a/run_tests.gd | 1284 + 22 条通过，0 失败 |
| tests/c/run_tests_c.gd | 459 条通过，0 失败 |
| tests/c/run_scenery_tests.gd | 94 条通过 |
| tests/b/run_stage_visuals.gd | 379 条通过 |
| tests/b/run_performance_audio.gd | 53 条通过 |
| tests/b/run_act1_game_audio.gd | 26 条通过 |
| tests/b/run_stage_walk.gd，Windows 图形 | 24 项通过；正式入口截图与步态 |
| tests/c/run_game_replay.gd，Windows 图形 | 43 项通过；8 秒等待、跳段、换头、采样点逐字段还原、选择/收场/重看/跳过/再演；暂停截图逐像素一致 |
| tests/c/run_game_replay_success.gd，Windows 图形 | 15 项通过；完整接还伞演出 118833 ms，再完整回放同一时长，全部事件派发、收锣仅一次；14277 个帧间隔样本 p50/p95 均为 16.67 ms |
| tests/c/run_game_replay_success.gd，最新无头定向回归 | 12 项通过，实际逻辑演出 118983 ms；允许与音频驱动样本有混音时钟差异 |
| tests/b/run_replay_audio.gd，Windows 音频 | 12 项通过；AudioEffectCapture 检测对白/等待器乐的非零混音输出、音轨暂停/继续、跳段、收锣去重及释放 |
| tests/c/run_tutorial_replay.gd -- stage=2 | 11 项通过；挂起/取回/换头、补救事件、旧节拍回放和暂停 |

最终门禁均 exit 0：

```powershell
godot.exe --headless --path . --import
godot.exe --headless --path . --quit-after 60
godot.exe --headless --path . --export-release "Windows Desktop" "builds/dengxia.exe"
```

实际调用由 `tools/run_godot.ps1` 或 Python subprocess 等待进程结束并读取真实退出码，避免 PowerShell 直接调用 GUI 引擎提早返回。日志在忽略目录 `builds/stage-realism/logs/`，截图在 `builds/stage-walk/`。最终门禁日志前缀 `replay-final-*`。

## 检查与限制

直接审查了宿主唯一推进边界、事件不重复消费、桥面位置、步态与腕点、回放离散朝向、双时钟、音频暂停、收锣去重、观众选择及记录释放。为遵守用户要求，没有启动子智能体。

回归发现并修正了旧白名单拒绝 `performance_audio` 和真实 `-1` 判定/补救目标的问题；`-1` 只对这些明确类别开放，具体影人操作仍严格校验。第一幕满钩状态无法再挂起是现有规则，因此挂起/取回验收使用已有第二教学关。布景在幕前透射画布内部先于人物合成，避免柳树覆盖人物。

已有测试中的非法输入案例会刻意输出 ERROR，部分 headless 退出仍有既有 ObjectDB/resource 释放提示；不能将这些日志描述为完全无警告。Windows 全循环及音频专项没有脚本错误。音频已验证实际混音输出和控制行为，主观听感仍由用户试玩确认；本轮不宣称完成全部幕次的人工体验验收。

没有删除或提交用户原有的 `tests/a/_xiaoqing_slice_tmp.gd` 及 UID。自建回归脚本覆盖稳定契约，保留在 tests 目录；截图和日志均不提交。
