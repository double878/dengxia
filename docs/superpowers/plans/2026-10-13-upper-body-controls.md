# 上半身操控实现计划

**Goal:** 全游戏人形影人支持拖手弯肘、拖头俯仰、Alt 拖躯干前倾，保留下半身行为并同步道具判定与回放。

**Architecture:** PuppetState 保存实际关节角；共享 UpperBodyPose 计算两段手臂及上身变换。输入通过实体视图换算到局部姿态，PuppetController 唯一写状态，显示和录放只读。

**Tech Stack:** Godot 4.7.2 Standard、GDScript、既有 A/B/C 测试及 Windows 图形探针。

## 全局约束

- 用户已确认 `docs/superpowers/specs/2026-10-13-upper-body-controls-design.md`，本计划在本会话顺序执行，不使用子智能体。
- 隔离目录为 `builds/worktrees/feat-upper-body-controls`，分支为 `feat-upper-body-controls`，基于 origin/main 的 b068661。
- 保留原工作区厅堂改动；切片提交只包含此功能。最终将已验证差异应用回原工作区，重新验证包含厅堂改动的正式入口。
- 所有 Godot 命令使用 `D:\Godot\4.7.2\godot.exe`；先解析再定向测试，失败先定位事实，三轮无实质进展即报告。
- 双臂长度固定、手腕无独立输入、头腰有限幅；角色下半身、灯和剧情规则沿用现有逻辑。

## 切片 1：关节姿态与共用显示

文件：新增 `scripts/a/upper_body_pose.gd` 和 `tests/a/run_upper_body.gd`；修改 `scripts/a/puppet_state.gd`、`scripts/a_test/placeholder_puppet.gd`。

接口：`UpperBodyPose.arm_points(shoulder, angle, bend, right_side, height)` 返回肩、肘、腕、前臂方向；`solve_arm(offset, right_side, height)` 返回合法肩肘角；`torso_transform(hip, lean)` 绕髋转动。PuppetState 新增 `elbow_angle: Vector2`、`head_tilt: float`、`torso_lean: float`。

- [ ] 写行为测试，通过运行时加载新增几何脚本，在脚本缺失时产生明确失败；断言原直臂腕点兼容、弯肘两段长度、目标可达性、越界与肩点有限值、头腰不改下半身状态。
- [ ] 导入基线后，解析并运行新增测试，确认失败原因是缺少功能。
- [ ] 实现共用几何和状态字段；显示腕点、头、躯干、饰带、锡杖、竹签共用新姿态。
- [ ] 解析修改脚本，运行新增几何测试和 `tests/b/run_stage_visuals.gd`。
- [ ] 检查并提交本切片。

## 切片 2：正式输入与提示

文件：修改 `scripts/a/puppet_controller.gd`、`scripts/a_test/input_reader.gd`、`scripts/a_test/level1_a_scene.gd`、`scripts/act2/act2_opening.gd`；扩展 `tests/a/run_upper_body.gd`。

接口：`set_hand_target(hand, local_offset, height)` 应用固定两段求解；`set_upper_angle(part, angle)` 应用头腰范围；`reset_upper_body()` 复位当前人的上身并发事件。InputReader 注入实体视图数组，用 `hit_upper_body(point, alt)` 判定目标，用视图逆变换换算手目标；现有胸签接口保留。

- [ ] 测试真实鼠标事件拖手、头、腰，松手保持、R 复位、换人不串输入和暂停禁用；测试鼠标控制一手而键盘仍能操作另一手。
- [ ] 确认测试在当前版本因输入未实现而失败。
- [ ] 增加输入路由、抓取偏移、拖动锁定、失焦释放及快捷抬落手；修改两个正式宿主接入相同视图和输入。
- [ ] 加入悬停/拖动标记，回放与未受控人物不显示；更新正式操控说明。
- [ ] 解析、定向操控回归及第二关出场回归，检查提交。

## 切片 3：接伞判定与完整姿态回放

文件：修改 `scripts/a/umbrella_controller.gd`、`scripts/a/performance_system.gd`、`scripts/c/c_snapshot.gd`、`scripts/c/c_replay_player.gd`、`scripts/c/c_replay_verifier.gd`、`scripts/b/performance_replay.gd`、正式回归入口及需求/技术文档。

接口：新增字段在 `PuppetState.to_dict()`、CSnapshot 缺省/校验/变化检测、回放插值及显示应用中完整保留。缺失字段以零读取。接伞手高及抬手指标读取实际姿态几何。

- [ ] 写弯肘或弯腰时接伞高度变化、旧记录缺省、新字段采样/插值/瞬时复位录放回归，并确认当前实现失败。
- [ ] 迁移手高判定和新字段的录放链路；保持原剧情窗口和道具归属。
- [ ] 解析，运行上半身、A、B 显示、C 录放及第一关完整接还伞回归。
- [ ] Windows 图形探针注入实际输入并截图，检查新姿态、下半身、实体与幕影、持伞/持杖及回放一致性。
- [ ] 执行资源导入、无头启动、Windows 导出；自查整体 diff 与设计覆盖，修复实质缺陷后提交推送。
- [ ] 将功能差异应用回原工作区，执行正式入口和厅堂衔接定向回归，交付操作与证据。

## 命令与证据

脚本解析示例：

```powershell
& .\tools\run_godot.ps1 -LogName upper-parse -GodotArgs @('--headless','--path','.','--check-only','--script','res://scripts/a/upper_body_pose.gd')
```

新增回归：

```powershell
& .\tools\run_godot.ps1 -LogName upper-test -GodotArgs @('--headless','--path','.','--script','res://tests/a/run_upper_body.gd')
```

完成判据：所有相关断言实际执行且无失败；三项门禁退出码为零；图形证据展示可见姿态与挂点。人工操作手感与音频体验若未进行用户试玩，交付中明确保留这一限制。
