# 皮影舞台实物质感升级实施清单

依据已批准的 `docs/stage-realism-plan.md`，本会话直接顺序实施。用户禁止默认子智能体；用户已确认现有小青未提交改动完成，可作为本轮基线继续编辑。已保存原文件、哈希及 staged/working 差异，备份位于系统临时目录 `dengxia-stage-realism-20261008/baseline`。

目标：完成棉布与绷紧结构、木台与框架、油灯、实体/透射投影分层、全场道具一致性、独立幕前开发验收场景，并交付可核对的图形证据。

约束：Godot `4.7.2.stable.official.ed1daf0bf`，同版本模板，统一 `D:\Godot\4.7.2\godot.exe`，Compatibility、GDScript、原有控制/判定及状态字段。固定 1920×1080 设计坐标及现有交互区域；图形窗口尺寸仍由 `project.godot` 在建窗前设置。

## 0. 基线

- [x] 运行原工程 import、startup、export 三项门禁，并记录真实进程退出码。
- [x] 运行现有回归，保存固定状态原画面。
- [x] 核对原有小青资源与伞挂点测试，单独保存已完成素材基线，后续提交只纳入相应切片。

## 1. 幕布与舞台结构

文件：`tools/generate_stage_textures.py`，`assets/stage/`，`scripts/b/stage_backdrop.gd`，`scripts/b/stage_surface.gd`，`shaders/stage_cloth.gdshader`，现有舞台显示接线。

输入：现有 `CLOTH`、`SCREEN_FRAME`、`TABLE`、lamp；输出：自制可重建纹理、绷布/木框/台面，以及在既有幕面显示的材质。

接口：`StageBackdrop.draw_stage(canvas: Node2D, cloth: Rect2, frame: Rect2, table: Rect2, oil: float)`；`StageSurface.configure(cloth: Rect2)`；`StageSurface.update_light(lamp: LampState, real_ms: int, song_ms: int, bpm: float)`。

- [x] 生成 tileable 棉布细纹与木纹，保存生成源和素材说明。
- [x] 替换舞台大网格、平面边框与台面；补包边、绳结、接合与厚度。
- [x] 材质使用连续照度与细织纹，不透视后台。
- [x] 脚本先解析，真实图形窗口检查亮/暗两档和缩窗纹理；截图保存。

## 2. 油灯与视觉时间

文件：`scripts/b/stage_light.gd`，现有 `placeholder_lamp.gd`，正式 `tests/b/test_stage_visuals.gd`。

输入：只读 LampState 与现有真实/歌曲时间；输出：确定性的火焰、有限幕面波动、局部光晕和最低环境亮度。

接口：`StageLight.sample(lamp: LampState, real_ms: int, song_ms: int, bpm: float = 96.0) -> Dictionary`；油灯暴露 `set_visual_time(real_ms: int, song_ms: int, bpm: float)`。

- [x] 先用真实灯显示验证“同时间同结果、反馈高更稳定、低显露仍能操作”的契约。
- [x] 使用小碗、油面、灯芯和曲线火焰替换占位图，表现局部反光。
- [x] 显式时间取代墙钟；暂停与补救采用已批准的双时钟约定。
- [x] 定向行为检查与图形检查通过后再扩展投影。

## 3. 实体/投影及道具

文件：现有 `placeholder_puppet.gd`，`scripts/b/stage_surface.gd`，`scripts/b/umbrella_visual.gd`，`shaders/puppet_transmission.gdshader`，`shaders/puppet_back.gdshader`，现有舞台接线。

输入：同一组 PuppetState、LampState、UmbrellaController；输出：固定尺寸的实体及签杆、受灯距控制的透色幕影、两套明确的道具挂点。

接口：影人显示 `render_mode` 区分旧测试视图、实体、投影；原手腕/翻面几何复用。幕面提供 `projected_hand_position(id: int, hand: String) -> Vector2`，实体使用实体视图的 `hand_screen_position(hand: String)`；禁止将投影坐标用于输入判定。

- [x] 先写测试，验证实体尺寸/腕点不随灯距或显露度改变，投影则改变；同姿态不能修改 A 状态。
- [x] 复用原分件及枢轴，消除幕面脚下椭圆；投影中不绘实体签杆/命中圈。
- [x] 所有影人与伞共用一个幕面透射 SubViewport，有限柔边，独立裁切。
- [x] 替换原父节点内伞绘制的接线，使实体伞和幕影各跟对应腕点；交接、翻面和换头留正式回归。
- [x] 检查三影人、挂起者、极端灯距、显露度、头部交换、双手异步及伞交接。

## 4. 幕前开发验收与收尾

文件：`scenes/b/stage_visual_lab.tscn`，`scripts/b/stage_visual_lab.gd`，`tests/b/run_stage_visuals.gd`，`tests/b/stage_graphics_probe.gd`，TECH_DESIGN 与实施记录。

输入：确定性样例状态，包含举伞、转身、换头、挂起和离幕样例；输出：独立幕后/幕前开发场景、固定状态截图、实际 GPU 图形检查与帧时统计。正常游戏流程始终只进入幕后。

- [x] 同一套样例状态分别驱动开发幕后/幕前，幕前镜像整体投影，无操作者或实体杆。
- [x] 保存原图、升级后幕后、幕前、最低灯况和交叠样例；屏幕颜色检查独立验证镂空/重叠。
- [x] 图形探针验证 shader 无编译错误、暂停画面冻结、样例可重现和输入挂点。
- [x] 全部正式回归、规定三项门禁及 PCK 图形检查通过。导出 exe 普通入口图形启动与 480 帧运行通过；发布模板不支持 `--script` 的探针限制与早期失败证据已记录。
- [x] 已按可验证切片提交并 push；沿用当前分支已有 PR #4，并更新说明，不合并。
- [x] 清理本轮临时入口，保留正式契约测试；实际记录回放尚未接入的限制如实列出。

命令通过 `tools/run_godot.ps1` 调用同一 godot.exe 并等待真实退出码；原始参数仍为 TECH_DESIGN 的 import/startup/export 和 tests/a/run_tests.gd。每次编辑后先 `--check-only --script <文件>`，排查时只跑对应切片，不用整套定位语法错误。

最终验收与原始证据说明：`docs/stage-realism-delivery.md`。源码及 PCK 图形检查已完成，独立 exe 普通图形入口也已通过短样本运行；人工手感/听音、五关长流程和实际记录回放尚未验收。
