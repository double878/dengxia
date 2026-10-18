# 录放契约（REPLAY_CONTRACT）

> 2026-10-15 人形腾空身段：三槽 PuppetState 新增 air_height（归一化离地高度）、leg_spread（0..1 张腿）、body_angle（世界弧度）。stage_pos 继续表示脚下地面点。三字段按原演出采样、补采样、插值和显示，缺失为零，拒绝非有限/越界值；回放不重新调用跳跃、躲闪或双童编排。puppet_motion 事件记录动作开始，后续逐帧状态保留实际动作、取消和暂停。

> 2026-10-15 第三关单场连续打戏：stage_id=3、scene_id=31 的同一份记录保存白素贞/鹿童/鹤童三槽真实 PuppetState；新增 performance.sword_progress（对应三人出鞘比例）、fight_phase、clash_point{x,y}、clash_strength。剑从实际腕点与前臂方向重建，幕前只读记录的出鞘和交锋，不重做 NPC 编排或碰撞。上山等待原样保留，自动出山后自由操演，原声不受动作、退场或暗灯影响；菜单暂停不采样。score.complete=false 的现有素材尾不发 performance_finished，不提前回放；测试可显式收尾记录验证已有段落，正式流程等待完整剧情素材。源轨为 performance.wav，记录同一条连续原声的位置与音源版本。

> 2026-10-14 第二关正式录放（优先于下方历史范围）：`scripts/c/c_act2_capture.gd` 在 Act2Opening/Act2Hall 固定步末接宿主已收集的事件，仅读取控制器与 MusicClock。两场同一份 stage_id=2 的记录；场次编号 2/22 存在 performance.scene_id，第二场真实时间叠加第一场终点加 1 ms。首帧零点；离场/等待/补救/收势均包含在 duration_ms，菜单暂停不采样。第三具记录槽在第一场不可见，不虚构第三名演员。performance 追加场内真实时间、阶段、字幕、音源版本、入口遮挡/暗场章节卡、坐姿/倒地角、杯 owner/hand、白蛇六节/位置/翻面/复位计数，以及 main/entry/hit/slow 的 playing/paused/position_ms/volume_db。字幕与阶段变化使用现有 dialogue_line_changed/opera_phase_changed；补救原事件保留，白蛇对象命名空间 white_snake 仅允许漏做与补救事件。漏做 cue_miss 标记 missed_outright，不要求不存在的 cue_fire。回放只消费快照与事件，不重新执行动作许可、输入解算或补救判定；跨场、杯归属、坐姿、入口遮挡在原落点切换，姿态/灯/蛇节与倒地角连续插值，蛇 R 复位前保持原蛇颈，歌曲前向跳段离散应用。幕前复用原影件/杯/蛇与布景并整体镜像；无雨幕、操作手或操控提示。声音按记录播放，冻结/暂停保留原位置，恢复或跳段从记录位置 play，避免在暂停 WAV 上 seek 后恢复静音。整关结束先 choice；不看、跳过、自然结束都 result，下一次鼠标点击进入第三关并释放记录。

> 2026-10-13 上半身补充：PuppetState.to_dict() 新增双肘 `elbow_angle{left,right}`、`head_tilt`、`torso_lean`，旧记录缺字段按零读取。快照保留、校验与变化检测覆盖这三个字段，任一实际变化触发补采样；回放直接插值实际角度，不重新执行鼠标解算。事件白名单新增 `upper_body_pose`、`upper_body_reset`。R 复位在记录落点瞬时应用，上一个样本至复位样本之间保持原上身姿态，位置与下半身继续正常插值；回放显示不提供操控提示。本补充不代表第二关完整录放已经接入。

> 2026-10-11 正式入口补充（以下优先于后文历史原型口径）：`Level1Harness.start_recording()` 在应用开场站位之后写入 t=0 帧；固定步末 `CLiveCapture.capture()` 读取状态和宿主统一事件，不调用 Runtime.tick、不自行取 Runtime 事件。正式记录的 time_ms 使用唯一 MusicClock 的真实演出时间，payload 保留 song_time_ms、real_time_ms、sequence；duration_ms 为实际终点，包括全部等待和补救，菜单暂停除外。CSnapshot.performance 保存 song_ms、on_stage、umbrella（归属、交接起点及进度）、audio（各轨播放位置/暂停、等待增益）。PuppetState 增加 walk_phase/walk_amount，回放保留步态。新增合法类别为 puppet_hook、puppet_take_back、head_swap、opera_wait_begin/end、opera_take_close、opera_score_skipped、opera_phase_changed、dialogue_line_changed；音频事件的 object_id 为 performance_audio。CResultFlow.offer_replay 只进入 choice，choose_replay 才播放或进入 result；显式 begin_replay 保留为旧测试/探针兼容 API。GameFlow 使用选择 API，不自动回放。后文 CRecorder/CStageRecorder 的固定歌曲长度及歌曲时间口径只适用于旧原型，不用于正式游戏。

> 本文件是 C 侧录放行为的**唯一契约**，由 C 负责维护。
> 生成：2026-10-04 · 基准分支 `feat-replay-from-a`（从 `origin/feat-level1-controls` @ `e791acd` 切出）

## 0. 本文件的范围与引用原则

**本文件管什么**：C 侧 Recorder 与 Replay 的**行为契约** —— 采什么、何时采、怎么存、怎么放、允许与禁止做什么。

**本文件不管什么**：A 侧字段的**事实定义**。

> A 侧字段事实源以 A 端代码与 `docs/handoff/A-to-B-level1.md` 为准。
> 本文件**不复制**字段表，只引用。字段一改，以 A 侧为准，本文件不重复维护第二份，
> 避免双份漂移。A 端 review 请以「引用是否正确」为准，不要以「字段表是否齐全」为准。

**已核实的引用目标**：`docs/handoff/A-to-B-level1.md` 在 `origin/feat-level1-controls@e791acd` 上**尚不存在**（该分支 `docs/` 下只有 `superpowers/plans/` 两份计划）。A 端说明系「本次新建」。本文件在 A 侧文档 push 前，字段事实暂以 **A 端代码实读**为准，并在下节标注实测口径。

---

## 1. A 侧数据源（引用 + 实测，不复制字段表）

### 1.1 唯一的接入入口

`scripts/a/level1_runtime.gd` 的 `Level1Runtime`，是 C 侧接触 A 的唯一门面。调用序列：

```
runtime.setup(clock) -> bool     # 装配 puppet_controller / director / lamp_controller
runtime.start()                  # 产出 stage_start
runtime.tick(delta)              # A 侧帧推进（内含 puppet.tick / director.update / lamp.update）
runtime.set_paused(value)        # 暂停：clock.pause() + 清空两侧 input_map
runtime.is_over() -> bool
runtime.take_events() -> Array[Dictionary]   # 取走即清空
```

### 1.2 C 侧读取点（状态）

| 要读的 | 路径 | 形状 |
| --- | --- | --- |
| 三个影人状态 | `runtime.puppet_controller.puppets` | `Array`，定长 3，每项有 `to_dict()` |
| 灯态 | `runtime.lamp_controller.lamp` | 有 `to_dict()` |
| 歌曲时间 | `runtime.clock.get_song_time_ms()` | `int` 毫秒，**唯一时钟** |

**字段名与不变量以 A 端 `PuppetState.to_dict()` / `LampState.to_dict()` 为准**，本文件不复制。
实测形状（仅供核对，不作契约）：

- `PuppetState.to_dict()` → `puppet_id`, `stage_pos{x,y}`, `stance`, `facing`, `turn_progress`, `hand_angle{left,right}`, `head_id`, `hook_slot`, `is_controlled`
- `LampState.to_dict()` → `distance`, `exposure`, `oil`, `flame_feedback`

### 1.3 帧内调用顺序（契约核心）

A 端 `Level1Runtime.tick(delta)` 内部顺序（实测 `level1_runtime.gd:53-65`）：

```
puppet_controller.tick(delta)
  → puppet_controller.take_events()          # 影人事件
  → director.update(controller_events)       # 判定
  → director.take_events()                   # 判定/补救事件
  → lamp_controller.update(delta, director_events)   # 灯：状态 + 灯事件
  → （关末）lamp_controller.finish_show() → take_events()
```

因此 **C 侧的调用序列固定为**：

```
runtime.tick(delta)              # ① A 侧推进
recorder.capture_states(runtime) # ② 采连续状态（读 tick 之后的最终值）
recorder.capture_events(runtime) # ③ 取本帧离散事件
```

**为什么第 ② 步在 tick 之后仍然正确**：A 端把「采快照」与「采事件」两个逻辑位置都收进了 `tick()` 内部顺序，`lamp_controller.update()` 是 `tick()` 的最后一步。所以 `tick()` 返回时读到的一定是本帧最终值 —— 这满足 TECH_DESIGN「状态先变化，再供表现与录制读取」。

**⚠ 与早期认知的差异**：C 侧**不再**需要在自己的 `_process` 里插到 `performance.update()` 与 `remedy.update()` 之间 —— 那是 A 端 `tick()` 内部的事。C 侧只在 `tick()` 之后读一次。这是接真数据后最重要的修正。

### 1.4 事件

`take_events()` 返回 `Array[Dictionary]`（**字典，不是对象**），**取走即清空**。
每条含 `time_ms` / `kind` / `object_id` / `cue_id` / `payload`。
`time_ms` 已被 `Level1Runtime._queue_events()` 钳制到 `stage_def.duration_ms`。

**kind 全集：21 个**（实测自 A 端代码，非推算）：

| 来源 | kind | 数 |
| --- | --- | --- |
| `puppet_controller.gd` | `drag_begin` `drag_end` `pose_stance` `facing_turn` `hand_motion` | 5 |
| `performance_system.gd` | `cue_hint` `cue_fire` `cue_hit` `cue_miss` | 4 |
| `remedy_system.gd` | `remedy_open` `remedy_success` `remedy_timeout` `remedy_show` `remedy_hide` | 5 |
| `stage_director.gd` | `stage_start` `stage_end` | 2 |
| `lamp_controller.gd` | `lamp_state_changed` `lamp_input_changed` `lamp_oil_changed` `lamp_feedback_changed` `lamp_finished` | 5 |
| **合计** | | **21** |

> 注：`cue_hint.gd` 的 `stance`/`hand`/`move`/`reach` 是**线索动作名**，不是事件 kind，不计入。
> 早期文档曾写「17 个」，**已作废**，以本表 21 为准。

### 1.5 ⚠ object_id 类型分歧（C 侧定案）

**事实**：`object_id` 存在**两个命名空间，且是类型分歧而非取值范围差异**。

| 事件来源 | 类型 | 值 |
| --- | --- | --- |
| 影人（`puppet_controller`） | `int` | `0`–`2`（下标即 `puppet_id`） |
| 油灯（`lamp_controller`） | `String` | `"lamp_main"`（`lamp_controller.gd:23`） |
| 关卡/补救（`stage_director` / `remedy_system`） | `int` | 无对象时为 `0` |

**C 侧定案**：`CTimedEvent.object_id` 声明为 **`Variant`**，`validate()` **按类型分支校验**：

- `TYPE_INT` → 影人命名空间，须落在 `[0, PUPPET_COUNT-1]`（即 0–2）
- `TYPE_STRING` / `TYPE_STRING_NAME` → 灯命名空间，须等于 `"lamp_main"`
- 其他类型 → 直接拒绝

下游**一律不要**对 `object_id` 做数值比较或 `int()` 强转（会把 `"lamp_main"` 毁成 0）。

**A 端确认**：此分歧由 C 侧定案后统一，A 端不单方面改动。**本文件即为定案。**

---

## 2. C 侧录制契约（Recorder）

### 2.1 采样规则

| 项 | 规则 |
| --- | --- |
| 定频 | **30 Hz**，按**微秒相位 33333μs 累进**，不用整数 33ms 步进 |
| 为什么 | 整数 33ms 在 35 秒累计 20ms 误差且永远采不到 35000 整点；微秒相位实测 35s→1051 帧、110s→3301 帧，末帧误差 0–1ms |
| 补采样 | 字段跳变（含离散量 `head_id`/`hook_slot`/`is_controlled`）**当帧追加**，优先级高于定频 |
| 同刻去重 | 同一 `time_ms` 只保留一条；跳变与定频同帧相遇时不追加第二条 |
| 暂停 | 时钟冻结时**不追加、不推进相位**；恢复后按同一网格继续 |

### 2.2 变化检测阈值

`CHANGE_EPSILON = 1.0e-9`，用**绝对误差** `absf(a-b) > eps`。

**不得**用 `is_equal_approx`：它按相对误差工作（约 1e-5），会把单帧的小幅变化判成「没变」，补采样不触发，30 Hz 会漏掉瞬时动作。

### 2.3 事件记录

- `take_events()` 取走即清空 → 每帧取一次不会重复。
- **不做任何节流**。`lamp_oil_changed` 在演出期间基本每帧一条，**原样全量记录**。节流会让回放与真实演出不一致，违反 1:1 忠实。
- `object_id` **原样透传**，不做 `int()` 强转。

### 2.4 字段语义注意事项（易错）

1. **`lamp.distance` 越大表示灯离影人越近**（反直觉）。Recorder **原样记录数值**，不做方向换算；若表现层需要反向，是回放表现层的事。
2. **`lamp_oil_changed` 每帧一条**，见 2.3。
3. **`flame_feedback` 是连续量**，变化检测按 2.2 的绝对误差。

### 2.5 记录容器

`CPerformanceRecord`：按 `(time_ms, seq)` 有序插入；`seq` 从 1 连续、**仅成功写入时递增**（被拒事件不消耗，号段无空洞）。
`duration_ms` 用**关卡固定时长**，不用末帧 `time_ms`。

---

## 3. 忠实性约束（PRD 5.2.3，回放端不得违反）

1. **`cue_fire` 与 `cue_hit`/`cue_miss` 分开两条**。错拍时动作照常发生，所以既有 `cue_fire` 也有 `cue_miss`。回放要能看到「动作做了」这个事实。
2. **`remedy_success` 不删除此前的 `cue_miss`**。原失误仍计入该幕表现。`replay()` 返回**原事件流，不做任何过滤**。
3. **`cue_miss` 必须有对应的 `cue_fire`**（同 `cue_id`）。只有 `cue_miss` 而无 `cue_fire`，说明「动作做了」这个事实丢了，回放将无法呈现。

以上三条已内建为 `CPerformanceRecord.validate_invariants()` 的自检，录制结束时执行。

---

## 4. 单向数据流（TECH_DESIGN 2.3）

```
输入 → PuppetState / LampState（逻辑层唯一可变状态）
     → 画面表现（只读状态）
     → Recorder（同帧读状态与事件，写时间戳）
     → PerformanceRecord（只存不改）
     → Replay（只读记录）
```

- **Recorder 只读 A 的状态与事件，不写回任何状态。**
- **Replay 只读记录，不回调输入与评分模块。**
- 这是「幕后与幕前画面一致」的边界。

---

## 5. 待确认（待 A 侧或后续切片补齐）

| # | 待确认项 | 影响 |
| --- | --- | --- |
| 1 | `docs/handoff/A-to-B-level1.md` 何时 push | 本文件 1 节引用目标缺位 |
| 2 | `lamp_finished` 是否仅在关末发出；中途是否会重复 | 回放关末表现 |
| 3 | `payload` 各 kind 的字段明细 | 回放还原动作细节 |
| 4 | 第 5 关 `acts` 掌声结构与触发归属 | 切片 3/4 |
| 5 | 回放音频总线命名与播放器持有方 | 切片 3 音频 |

---

*本文件由 C 侧维护。A 侧章节请以「引用是否正确」review。*
