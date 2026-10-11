# 正式游戏布景、步态与回放实施计划

> 使用 executing-plans 在当前会话顺序执行；用户规定不使用子智能体。

**Goal:** 将队友的布景及真实幕前回放接入游戏，满足已批准的 1A / 2A / 3A。

**Architecture:** Harness 保持唯一状态推进者。C 数据模块记录并重放状态，GameFlow 管理演出、回放选择、幕前回放与收场。

**Tech Stack:** Godot 4.7.2.stable.official.ed1daf0bf，GDScript，现有音源及布景，无新增依赖。

## 全局约束

- 分支 feat-stage-walk-replay；每个通过验证的切片提交、推送。
- 先解析修改脚本，再运行定向测试；调试最多三轮无进展后报告卡点。
- 三项门禁始终使用 D:\Godot\4.7.2\godot.exe；Windows 图形验证不能由 headless 代替。
- 不清理或提交用户的 tests/a/_xiaoqing_slice_tmp.gd 及 UID。

## 切片一：布景与小步走

输入：CSceneryDef 的桥锚点/比例、PuppetController 横向拖动及 PuppetState。
输出：CStageBinding 正式挂载、第一幕 bridge_height(x)、walk_phase/walk_amount 连续状态及显示端步态。
文件：scripts/c/c_stage_binding.gd、scripts/a/stage_walk_path.gd、puppet_state.gd、puppet_controller.gd、scripts/a_test/placeholder_puppet.gd、level1_a_scene.gd；tests/b/run_stage_walk.gd。

- [x] 写并运行失败测试：开场两人位于桥面；左岸与桥端连续；往返高度一致；拖动产生步态；停止收脚；手角不变。
- [x] 按现有布景变换映射桥面，Controller 在横向移动后更新接地点及距离驱动步态，显示端用相同步态位移腿与上身/腕点。
- [x] 解析相关脚本，运行定向测试及已有 A/B/C 回归，Windows 正式入口截图核对。
- [x] 审查 diff、明确暂存、提交并 push。

## 切片二：实际记录及可选幕前回放

输入：切片一的状态、Harness 统一事件和真实/歌曲时钟、现有正式音源。
输出：从 t=0 到实际终点的 CPerformanceRecord；GameFlow 的 choice/result/replay；只读幕前画面与音频。
文件：C Snapshot/Replay/ResultFlow/TimedEvent、scripts/c/c_live_capture.gd、scripts/b/performance_replay.gd、scripts/b/act1_opera_audio.gd（复用音源与播放节点）、Harness、level1_a_scene、game_flow；tests/c/run_game_replay.gd。

- [x] 写并运行失败测试：首帧站位、超歌曲时长的等待、前向跳段、步态及伞进度保留；结束停在选择页；不看后仍能观看；暂停/跳过/自然结束/重看/再演释放。
- [x] 在固定步边界捕获 CSnapshot，并保留统一事件顺序；扩充实际发出的合法事件类别。真实时间写入 time_ms，歌曲位置保留在 performance 数据。
- [x] CResultFlow 加入等待选择状态。GameFlow 接结束信号并提供“观看幕前回放 / 不看回放”、收场及再演按钮；PerformanceReplay 从 CReplayPlayer 状态驱动 StageSurface，布景用同一幕布中心镜像。
- [x] Act1OperaAudio 的回放接口读取记录的音频状态及歌曲位置，按原等待/补救/跳段复用正式音源，暂停全输出；收锣只由记录事件触发。
- [x] 解析、定向测试、全部相关回归；运行 import/start/export 门禁及 Windows 实际入口完整循环验证。
- [x] 更新 PRD/TECH 的自动回放与过时时间轴描述，记录证据，清理自建临时脚本；审查 diff 后提交、push、创建功能 PR。
