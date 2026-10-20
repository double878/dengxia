# 三关人形动作与第三关打戏 Implementation Plan

> **Execution:** Implement authorized tasks in the current chat, respecting dependency order and the user's stage boundaries. Use subagents only when the user explicitly requests or approves them. Track steps with checkbox (`- [x]`) syntax.

**Goal:** 三关统一 W 短跳、S 压身后撤，修正白素贞出鞘，丰富双童自动搭戏。

**Architecture:** 继续由 PuppetController 写人形状态，共用一个短动作辅助类。离地高度、张腿和整身倾角进入原状态/录放链，地面坐标仍保留桥面路径。第三关的剑和自动演员只读同一几何和原声音时标。

**Tech Stack:** Godot 4.7.2 Standard / GDScript / 现有透明分件。

## Global Constraints

- 用户已确认六项定案；W 腾空时锁定身形，完整白蛇保持分节操作。
- Godot 固定 `D:\Godot\4.7.2\godot.exe`；不改工程、场景、音源或引擎缓存。
- 保留现有未提交工作；只修改此目标需要的代码和说明，不混合暂存历史工作。
- 第三关只有一场，原声不断、不强制跌倒；鹿童 27.560 秒重音出山沿用原实现。
- 无子代理；修改后先解析，再定向测试，最后 import/startup/export 与 Windows 图形验证。

### Task 1: 共用 W/S 与真实录放

**Files:** 新建 `scripts/a/puppet_motion.gd`、`tests/a/run_puppet_motion.gd`；修改 `puppet_controller.gd`、`puppet_state.gd`、`input_reader.gd`、三关输入宿主、`placeholder_puppet.gd`、C snapshot/player/verifier 和 B replay。

**Interfaces:** `PuppetController.start_motion(kind: String) -> bool`；`motion.active() -> bool`；状态增加 `air_height`（归一化高度）、`leg_spread`（0..1）、`body_angle`（世界弧度）。`PuppetMotion.tick(state, delta, path)` 仅由 controller 调用。

- [x] 用真实 InputEventKey 复现 W 尚未触发短跳，保存失败证据。
  ```gdscript
  check(reader.handle_event(key(KEY_W)), "W 触发一次短跳")
  check(not reader.handle_event(key(KEY_W, true)), "重复键不触发")
  ```
- [x] 实现约 0.46 秒原地跳（短蓄势、0.32 秒腾空、落地），腾空锁胸签/手签/快捷抬手；约 0.40 秒 S 后撤，维持面朝对手，边缘夹紧。
- [x] 复用原有腿分件；跳跃显示张腿。渲染、几何查询、道具共享离地/倾角矩阵。
- [x] 三关宿主把 W/S 传给共用读取器；厅堂动作开始时离座；切人/挂起清理瞬态；暂停保持。
- [x] snapshot 缺省、校验、变化、插值、应用及 verifier 覆盖新字段；旧记录为零。
- [x] 解析并运行 `tests/a/run_puppet_motion.gd`、`tests/a/run_upper_body.gd`。验证桥面落地、锁姿、切换、边缘、旧记录与回放。

### Task 2: 剑鞘和右手出鞘

**Files:** `scripts/act3/sword_view.gd`、`fight_choreography.gd`、`tests/c/run_act3_fight.gd`。

**Interfaces:** `SwordView.geometry()` 返回右腕、剑尖、剑轴；`sheath_geometry()` 返回鞘口和鞘尾。原有 `draw_progress` 继续录制。

- [x] 按素材 reference_facing 计算鞘口/尾，面朝右时满足 `mouth.x > tail.x`、`mouth.y < tail.y`，翻面时同样随身。
- [x] 出鞘轨迹从鞘口到实际右手；唱词后剑柄固定右腕。自动出鞘不改玩家手臂姿态。
- [x] 解析并运行 fight 定向回归，增加两个朝向和持剑腕点断言。

### Task 3: 双童的多招搭戏

**Files:** `scripts/act3/fight_choreography.gd`、`tests/c/run_act3_fight.gd`；新建 `tests/b/run_combat_motion_graphics.gd`。

**Interfaces:** 保留 `update(delta, song_ms, on_stage)`；NPC 动作写同一 PuppetState，新招式以有限编排交替出现。

- [x] 鹿童组合跃身进刺、上下连斩、转身横扫；鹤童组合架剑反挑、侧身腾挪、回身进剑。每招有蓄势/出招/收势，出招锁方向和目的地；蓄势/收势随玩家调整距离。
- [x] 原声的败退、鹤童接战、结束等待时标沿用；各段结束归零离地/张腿/倾角，不留悬空。
- [x] 定向验证招式差异、离地/张腿/剑角范围、避让后不追踪、暂停、玩家状态与唱腔持续。
- [x] Windows 图形探针模拟三关键鼠输入，截图短跳、躲闪、双童招式、右手出鞘和真实记录回放；查看截图。
- [x] 更新 PRD/TECH/README/操作提示与交付说明。运行音频逐采样校验。
- [x] 最终执行同版本 `--headless --path . --import`、`--headless --path . --quit-after 60`、`--headless --path . --export-release "Windows Desktop" "builds/dengxia.exe"`，复核 diff 与临时产物。
