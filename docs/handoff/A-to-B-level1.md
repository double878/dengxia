# A → B 交接：第一关显示契约

> 版本：2026-10-03 · 负责人 A（操控、节拍与关卡规则）
> 范围：**只覆盖第一关**，只覆盖 B 需要的「读什么、什么时候读、别做什么」。
> 依据：[PRD.md](../../PRD.md) 第 4、5、6 节；[TECH_DESIGN.md](../../TECH_DESIGN.md) 第 1.1、2.1、2.3 节；`docs/superpowers/plans/2026-10-03-level1-a.md` 第 1 节。
> 本文件由 A 维护。B 若要改字段含义，先告诉 A，不各自改契约。

## 0. 一句话边界

**B 只读 A 的状态与事件，不写。** 拍点、判定窗、命中/错拍、补救时机、关卡结束时刻全部由 A 提供；B 不自己算拍点、不自己判对错、不自己决定「该显示到什么时候」。这与岗位表里「节拍与得分规则由 A 统一提供」一致。

## 1. A 的代码在哪（重要）

| 项 | 事实 |
| --- | --- |
| `origin/main` | **没有 A 的代码**。HEAD `285b8db`，只有工程初始化与文档，共 6 个提交。 |
| A 的代码 | 在 `feat-level1-controls`。本地 HEAD `f71e0ce`，相对 `origin/main` 领先 13 个提交；远端 `origin/feat-level1-controls` 仍停在 `e791acd`，本地比它领先 3 个提交。 |
| 原先「未提交的一批」（重要） | 那批改动（手部幅度扩到可抬 180°、翻面改成 0.1 秒的正/反两面、**补救期间冻结歌曲时间轴（+ 0.5 倍速慢鼓、8 秒按真实时间计）**，以及同步过的测试和文档）已作为**基线提交 `f71e0ce`** 落库，工作区不再有这批未提交内容。要这批代码取 `feat-level1-controls` 即可（推送后）；按下面的命令拿到的仍是 `e791acd` 旧版。 |
| PR | 尚未创建，`origin/main` 上没有任何合并记录。 |
| 工作区 | 除本文件所述基线之外无别的未提交内容。 |

取代码（远端未更新前，这样拿到的仍是 `e791acd`）：

```powershell
git fetch origin
git switch -c feat-<你的模块> origin/feat-level1-controls
```

B 要看的文件都在 `scripts/a/`、`scenes/a_test/`、`tests/a/` 下。

**游戏入口：** `scripts/game_flow.gd` 现在会把 `scenes/a_test/level1_a.tscn` 作为第一关实例化进来，所以双击运行游戏即进第一关。选关菜单做出后这里改成进选关，第一关场景本身不受影响。

**第一关的输入集（只有 PRD 第 4.1 节这一套，没有测试专用键）：** 鼠标左键点影人 / 手边的签 = 接手并拖胸签，滚轮 = 推拉灯，`Q`/`E` = 倾灯，`A`/`D`/`Shift+A`/`Shift+D`/`W`/`S` = 双手，`1`/`2`/`3` 或点备用头架 = 换头，空格 = 挂起/取回影人，`ESC` 或右上角按钮 = 暂停。**空格不再是暂停键。**（空格在第一关按不动——两个挂钩槽被布景占满，原因与影响见第 7 节末。）

## 2. 每帧的调用顺序（这是接口，不是建议）

```gdscript
# 1) 唯一时钟先走
clock.update(delta)                       # scripts/a/music_clock.gd

# 2) A 推进一帧：PuppetController → StageDirector → LampController
runtime.tick(delta)                       # scripts/a/level1_runtime.gd

# 3) 此时读状态，读到的一定是本帧最终值
runtime.puppet_controller.puppets         # Array[PuppetState]，下标即 puppet_id
runtime.lamp_controller.lamp              # LampState

# 4) 事件取走即清空，每帧只取一次
var events := runtime.take_events()       # Array[Dictionary]
```

**不变量：**`tick()` 返回时，本帧的 `PuppetState` / `LampState` 已经是最终值；同一帧的事件与状态一致。请**不要**在自己的 `_process` 里抢在 `runtime.tick()` 之前读，也不要缓存上一帧的状态当作本帧。

现成的完整入口在 `scenes/a_test/level1_a.tscn` + `scripts/a_test/level1_a_scene.gd`，可以照它的接线方式接。

## 3. `PuppetState`（A 产出 → B 显示）

来源：`scripts/a/puppet_state.gd`。读法：`runtime.puppet_controller.puppets[i]`，或 `get_puppet(id)`。

| 字段 | 类型 | 范围 | 含义 |
| --- | --- | --- | --- |
| `puppet_id` | `int` | `0`–`2` | 影人编号 |
| `stage_pos` | `Vector2` | 各分量 `0.0`–`1.0` | **接地点（脚底）**的幕布归一化位置；`x` 向右为正，`y=0` 最深处、`y=1` 最靠幕布 |
| `stance` | `float` | `0.0`–`1.0` | `0.0` 完全站立，`1.0` 完全蹲下 |
| `facing` | `float` | **恰为 `-1.0` 或 `+1.0`** | **二值**：`+1.0` = 正面朝外，`-1.0` = 反面朝外。影人只有正反两面，没有中间朝向 |
| `turn_progress` | `float` | `0.0`–`1.0` | 本次翻面的过渡进度：`1.0` = 已停稳在 `facing` 那一面。翻面中从 0 升到 1，**换面发生在 0.5**（画面上最窄、侧对观众的一瞬）；整段 0.1 秒 |
| `hand_angle` | `Vector2` | 各分量 `-1.5708`–`+3.1416` | `.x` = 左手、`.y` = 右手，**弧度**；`0` = 手臂自然垂下，`+π/2` = 水平前伸，`+π` = 举过头顶（抬手能到 180°），负值为收手 |
| `head_id` | `int` | `-1`、`0`–`5` | `-1` = 未分配；六个头（三个初始头 + 三个备用头）全局共享 |
| `hook_slot` | `int` | `-1`、`0`、`1` | `-1` = 未挂起，否则为挂钩槽位 |
| `is_controlled` | `bool` | — | 是否当前直接受控 |

JSON 化请用 `state.to_dict()`（`Vector2` 已展开成具名标量：`stage_pos.x/y`、`hand_angle.left/right`），不要自己序列化 `Vector2`。

**B 可以直接依赖的不变量**（A 侧测试逐条断言）：

1. 全场恰好一个或零个 `is_controlled == true`。
2. `head_id` 与头架槽位合起来，`0`–`5` 各出现恰好一次——换头不会复制头部道具。头架本身不在 `PuppetState` 里：读 `controller.rack_heads`（长度 3）或 `controller.head_on_rack(slot)`；换头走 `controller.swap_head(slot, puppet_id = -1)`，默认作用于当前受控影人。
3. 同一 `hook_slot` 最多一个影人；挂起者保持姿势、不自行运动。
4. 连续量永不出界（上表范围即硬边界）。`facing` 恒为 ±1：传入 0 之类的非法值会被吸附到最近的一面，不会停在「没有面」的状态上。
5. 到限后继续按住不产生额外变化，不抖动。
6. 翻面**不是**逐帧插值的连续朝向：`facing` 只在翻面中点跳一次，`turn_progress` 才是连续量。B 显示翻面请用 `turn_progress` 做「压到最窄再展开」，只认 `facing` 决定画哪一面。

## 4. `LampState`（A 产出 → B 显示）

来源：`scripts/a/lamp_state.gd`。读法：`runtime.lamp_controller.lamp`。**四个字段全部由 A 产出**（`LampController` 是 A 的模块，在 `Level1Runtime.tick()` 内每帧更新），B 只读。

| 字段 | 类型 | 范围 | 含义 | 谁会改它 |
| --- | --- | --- | --- | --- |
| `distance` | `float` | `0.0`–`1.0` | 灯距控制量，**越大表示灯离影人越近**（影子越大） | 鼠标滚轮（B 不参与） |
| `exposure` | `float` | `0.0`–`1.0` | 幕布上影子的显露程度 | `Q`/`E`（B 不参与） |
| `oil` | `float` | `0.0`–`1.0` | 剩余灯油 | **只**由歌曲时间推进消耗，输入改不了，**不可回升** |
| `flame_feedback` | `float` | `0.0`–`1.0` | 火苗反馈强度，由 A 的判定结果驱动 | A 的命中/错拍/补救结果 |

B 用 `flame_feedback` 画灯芯火苗的**稳定程度与亮度波动**；用 `oil` 画台面整体环境亮度。这两条正是 PRD 第 4.3、5.1 节要求玩家「读火苗判断操演状态」的唯一数值来源。

**火苗的采样时机不需要 B 决定，也不需要占位值**——`flame_feedback` 与其他三个字段一样，在 `tick()` 返回时已定稿。B 只要每帧读一次即可，不存在「B 采样频率」这个参数。火苗的**视觉**抖动频率（美术表现）由 B 自己定，但它只是显示，不得写回 `LampState`。

现成的数值规则（B 可以据此预期，但不要自己重算）：

- 灯油消耗 `0.015`/秒，第一关 35 秒约消耗 52%；最暗时仍留有可辨认余量。
- `flame_feedback` 每次表现结果步进：`cue_hit` / `remedy_success` **+0.25**；`cue_miss` / `remedy_timeout` **−0.18**；结果始终 clamp 在 `0.0`–`1.0`。
- 暂停时歌曲时间、灯油、火苗反馈、判定一起冻结；恢复后沿同一时间轴继续，不会跳变。

## 5. `TimedEvent`（A 产出 → B 表现 / C 录制）

每条事件固定五个字段：`time_ms`(int)、`kind`(String)、`object_id`、`cue_id`(String，非判定事件为 `""`)、`payload`(Dictionary，至少含 `"kind"`)。

> **已知的类型分歧（不是笔误）：**影人事件的 `object_id` 是 `int`（`0`–`2`），油灯事件的 `object_id` 是 `String` `"lamp_main"`。B/C 的消费端要按 `kind` 分支处理，不能假设 `object_id` 一定是 `int`。统一方案等 C 的录制契约定案后再改，A 不会单方面改。

| `kind` | 触发时机 | `payload` 关键内容 |
| --- | --- | --- |
| `drag_begin` / `drag_end` | 胸签拖动开始 / 结束 | `{"dragging": bool}` |
| `puppet_hook` / `puppet_take_back` | 空格挂起 / 取回影人 | `{"hook_slot": int}`；取回时是**被释放**的槽位 |
| `head_swap` | 按 `1`/`2`/`3` 或点备用头架，与头架对应位置换头 | `{"slot": int, "head_from": int, "head_to": int}` |
| `pose_stance` | `stance` **开始变化**与**停止变化**时各一次，不每帧发 | `{"stance": float}` |
| `facing_turn` | 转身方向切换（左/停/右） | `{"from": float, "to": float}` |
| `hand_motion` | 某只手的运动方向改变 | `{"hand": "left"｜"right", "dir": -1｜0｜1, "angle": float}` |
| `cue_fire` | 玩家**做出了**这个动作（物理动作确实发生） | 见 `cue_hit` 同结构 |
| `cue_hit` / `cue_miss` | 合拍结果：命中 / 未命中 | `{"cue_id", "action", "offset_ms", "tolerance_ms", "reason"?}` |
| `remedy_open` | 补救窗口开启（**同时冻结歌曲时间轴**） | `{"action", "demo_action", "reason", "duration_ms", "remaining_ms", "target_range", "real_time_ms"}`，`reason` 为 `missed_cue` 或 `low_sync` |
| `remedy_freeze_begin` | 补救窗口开启、歌曲时间轴冻结 | `{"reason": "remedy", "open_windows": int, "real_time_ms": int}` |
| `remedy_freeze_end` | 所有窗口关闭、时间轴恢复 1 倍速 | `{"reason": "remedy", "frozen_ms": int, "real_time_ms": int}` |
| `remedy_show` / `remedy_hide` | 当前示范手切换（**同屏唯一**，B 只需按这个显示/隐藏） | 当前示范的 `cue_id` |
| `remedy_success` | 窗口内补做成功 | `{"action", "elapsed_ms", "still_missed"}` |
| `remedy_timeout` | 8 秒到期未完成 | `{"action", "elapsed_ms"}`；随关卡结束时额外带 `"reason": "stage_end"` |
| `stage_start` | 演出开始 | `{"duration_ms": 35000}` |
| `stage_end` | 演出结束 | `{"reason", "song_time_ms", "remedy_open_count", "duration_ms"}`，`reason` 为 `duration_reached` 或 `forced` |
| `lamp_input_changed` | `distance` 或 `exposure` 变化 | 四个字段全量 + `changed_fields` |
| `lamp_oil_changed` | `oil` 变化（**演出期间每帧都会发**） | 同上 |
| `lamp_feedback_changed` | `flame_feedback` 变化 | 同上 |
| `lamp_state_changed` | 上面任一情况都会附带发一次 | 同上 |
| `lamp_finished` | 演出结束、油灯停摆 | 四个字段全量 |

**给 B 的四条要点：**

1. `cue_fire` 与 `cue_hit`/`cue_miss` 是分开的。`cue_fire` 只说明「玩家做出了这个动作」，错拍时它照样发——所以**物理动作永远照常发生**，B 不要在收到 `cue_miss` 时把动作撤掉。
2. 示范手请只认 `remedy_show` / `remedy_hide`，不要自己按 `remedy_open` 去挑一个显示。同屏唯一展示的优先级由 A 决定（最早到期的那条）。
3. `lamp_oil_changed` 在演出期间基本上每帧一条，不要用它当「一帧只处理一条」的假设去做性能敏感的分配。
4. **补救期间歌曲时间是冻结的**：窗口一开，A 就冻结歌曲时间（拍点、灯油、关卡结束判定随之停住），鼓点由一路 0.5 倍速慢鼓接管；窗口全部关闭才解冻，并从冻结处继续。因此：
   - 补救期间 `clock.get_song_time_ms()` 不变，B 的节拍指示、目标边界、线索淡出都会自然停住——这是**对的**，不要用墙钟去补，也不要用 `delta` 自己推。
   - 判断「现在是不是补救时间」请用 `clock.is_song_frozen()`（或认 `remedy_freeze_begin` / `remedy_freeze_end`），**不要**用 `clock.is_paused()`：后者只表示玩家按了 ESC 暂停。
   - 8 秒窗口按**真实时间**计（`clock.get_real_time_ms()`），事件里的 `remaining_ms` / `elapsed_ms` 也都是真实时间。B 可以据此做定性提示，但不能写倒计时秒数（PRD 第 3、5.1 节禁止泄露数值）。

## 6. 线索数据 `CueHint`（B 画图标用）

来源：`scripts/a/cue_hint.gd`。A 只产出数据，不负责画出来。

```gdscript
var hint := CueHint.make(cue)                 # cue 来自 StageDef.cues
if CueHint.is_visible(hint, clock.get_song_time_ms()):
    # 该显示图标了
```

`hint` 字段：`cue_id`、`kind`、`action`、`target_object`、`demo_action`、`target_range`（原样带出，**供 B 画目标边界**）、`hint_time_ms`、`beat_time_ms`。

`kind` 四种，与动作一一对应：

| `kind` | 对应动作 |
| --- | --- |
| `stance` | `stand_up`、`crouch` |
| `hand` | `hand_raise`、`hand_lower` |
| `move` | `move_left`、`move_right` |
| `reach` | `reach` |

**线索不得泄露精确拍号、数值评分或观众心理**（PRD 第 5.1、8 节）。B 拿到的 `beat_time_ms` 是为了算图标淡出时机，不是给玩家看的数字；请勿在画面上显示拍号或倒计时秒数。

## 7. 第一关的具体数据

时长 **35000 ms**（绝不延长），BPM **96**（一拍 625 ms），共 56 拍。

第一关数据**在代码里**：`scripts/a/stage_def.gd` 的 `StageDef.make_level1()`。**没有 `data/level1.tres` 或 `.json`**——B 不要另抄一份 cue 表，直接调这个静态方法取，避免两处数据漂移。

段落（6 段，连续覆盖整关）：

| 段落 | 起 | 止 |
| --- | ---: | ---: |
| 起势 | 0 | 1875 |
| 起身 | 1875 | 4375 |
| 移步 | 4375 | 8125 |
| 抬手 | 8125 | 10625 |
| 回行 | 10625 | 14375 |
| 收势 | 14375 | 35000 |

关键动作（6 条，容差均为 ±250 ms，线索均提前 1000 ms 可见，重音每 4 拍一次）：

| `cue_id` | 落点 | 重音 | 动作 | 目标范围 | 线索可见于 |
| --- | ---: | :---: | --- | --- | ---: |
| `l1_c0_crouch` | 1250 ms（第 2 拍） | | 蹲下 | `stance ∈ [0.85, 1.0]` | 250 ms |
| `l1_c1_stand` | 2500 ms（第 4 拍） | ✓ | 站起 | `stance ∈ [0.0, 0.05]` | 1500 ms |
| `l1_c2_move_left` | 5000 ms（第 8 拍） | | 向左移动 | `x ∈ [0.0, 0.35]` | 4000 ms |
| `l1_c3_hand_raise` | 8750 ms（第 14 拍） | | 抬手 | `angle ∈ [2.356, 3.142]` rad（135°–180°） | 7750 ms |
| `l1_c4_move_right` | 12500 ms（第 20 拍） | ✓ | 向右移动 | `x ∈ [0.65, 1.0]` | 11500 ms |
| `l1_c5_reach_center` | 15000 ms（第 24 拍） | ✓ | 移动到中位 | `x ∈ [0.47, 0.53]` | 14000 ms |

注意：**判定的是「姿势到位或状态切换」的那一瞬间，不是平移的每一帧**。「到位」（`reach`）要求本次拖动中先离开过目标范围再进入——原地起拖不算到位。

**手角口径（本次变更）**：`hand_angle` 以**手臂自然垂下为 0**、`+π/2` 为水平前伸、`+π` 为举过头顶；抬手速度 4.5 rad/s，从垂直到 180° 约 0.7 秒。因此「抬手」落点的到位区间是 135°–180°，玩家要在落点前约 0.5 秒开始按住。

**翻面口径（本次变更）**：`facing` 只在 ±1 之间取，一次翻面约 0.1 秒（60 fps 下 6–7 帧）。B 画翻面请按 `turn_progress` 把宽度压到 `|2p−1|`（先窄后展开），换面（切换正/反面贴图）发生在 `turn_progress = 0.5` 那一帧；不要再按 `facing` 做连续插值，那样会退化成缓慢旋转。

**补救冻结（本次变更）**：补救窗口一开，歌曲时间轴就冻结（B 会收到 `remedy_freeze_begin`，鼓点变成 0.5 倍速），8 秒按**真实时间**计；窗口全部关闭才解冻（`remedy_freeze_end`）。第一关 6 条落点若全部漏做，真实耗时约 83 秒，而歌曲时间仍然正好 35 秒。

**空格（挂起/取回）在第一关不会发生：**第一关开局三个影人同时在场，其中两个分别挂在两个挂钩上（PRD 第 4.2 节），
所以两个挂钩槽从第一帧起就是满的，`hook_current()` 找不到空位、必然失败。因此**本关不会产生
`puppet_hook` / `puppet_take_back` 事件**，也不会出现「无人受控」的帧——B 不必为这两种情况准备兜底画面。
挂起/取回属第 2 关（双人）的机制（PRD 第 6 节）。A 侧 HUD 因此不再显示「空格 = 挂起这个影人」那行提示，
避免说了做不到。若日后改第一关布景让出空槽，A 会同步这行提示并告知 B。

## 8. 请 B 不要做的事

| 不要 | 原因 |
| --- | --- |
| 写 `PuppetState` / `LampState` 的任何字段 | 单向数据流是双面画面一致的边界；B 写会造成幕后/幕前不一致，且污染 C 的录制 |
| 自己算拍点或自己判「这一下算不算准」 | 拍点与判定规则由 A 统一提供；两套算法必然漂移 |
| 用 `delta` 自己推灯油或火苗 | 灯油只随歌曲时间消耗，用墙钟推会在暂停后错位 |
| 在 `remedy_open` 时自己挑示范手 | 同屏唯一展示由 A 决定，认 `remedy_show`/`remedy_hide` |
| 抄一份第一关 cue 表 | 数据在 `StageDef.make_level1()`，抄一份必然与 A 的改动脱节 |
| 在画面上显示拍号、分数、百分比、倒计时秒数 | PRD 第 3、5.1 节明确禁止 |

## 9. 还没有、也还没定的东西（如实说明）

| 项 | 现状 |
| --- | --- |
| 正式锣鼓主音轨 | **未交付**。`StageDef.track_path` 目前是空串。A 的时钟在无音轨时会明确降级，并且**没有**在无正式音轨的情况下验证过拍点对齐。B 交付音轨后必须复测。 |
| 第一关的临时音轨 | `scripts/a_test/metronome.gd`：**现场合成**的旋律 + 低鼓 + 每 4 拍重音，`AudioStreamGenerator` 实时输出。第一关现在**靠它出声**（否则会得到一个没有音乐的关卡），但它仍是**临时素材，不是正式音轨**，不引用任何外部文件、不登记使用权。B 的正式锣鼓到位后整体替换即可，`MusicClock` 与判定逻辑不受影响。 |
| 影人/灯/幕布贴图 | 全无。A 用的是 `scripts/a_test/placeholder_puppet.gd`、`placeholder_lamp.gd` 占位图形（含关节点、三根竹签、幕布洗光）。 |
| 低合拍补救路径 | 机制可用并已单独验证，但在**标准第一关数据**下不会开窗（每段只有一条落点，「段内已判定 >= 2」与「还剩一条未判定」无法同时成立）。阈值需游玩实测校准。 |
| 补救冻结的记录与回放 | A 已产出 `remedy_freeze_begin` / `remedy_freeze_end` 与 `real_time_ms`，但 **C 的录制契约尚未定案**。回放必须靠这两个事件还原「这段真实时间不计入歌曲时间」，否则 1:1 回放会比重看的实际演出短。C 定契约时请把这两个 `kind` 纳入。 |
| 慢鼓音色 | 补救期间的 0.5 倍速鼓是**现场合成的占位声音**（同一套临时节拍音按 0.5 倍速播放）。正式锣鼓到位后，慢鼓应由正式素材提供；时钟与事件契约不受影响。 |
| 音频延迟补偿 | 时钟按音频播放位置增量累计；实际听感（是否真的对上鼓点）**只能人工听**，无头模式用虚拟音频驱动，证明不了。 |
| 音频停摆的降级 | `MusicClock` 有停摆看门狗：播放器自称在播但播放位置连续 0.6 秒不前进（声卡缺失/被独占/缓冲停摆）时，会降级为自由计时并 `push_warning`，此时 `is_audio_driven()` 变 `false`。**B 的 HUD 可以据此提示玩家**，A 的第一关已经这么做了。降级只换时间来源，判定规则一条不变。 |
| 诊断开关 | 第一关支持 `场景文件 -- diag` 启动（`level1_a.tscn -- diag`），每 30 帧打印 `fps / song / audio_driven / playing / pos / advance / ui`。排查「看到卡住」时先跑这个，别靠肉眼猜。 |

## 10. B 怎么自证接对了

1. 先只画一个只读 HUD，把 `puppets[0]` 的九个字段和 `lamp` 的四个字段逐帧打出来，跑 `scenes/a_test/level1_a.tscn`，确认数值与 A 的测试场景 HUD 一致。
2. 再把 `take_events()` 逐条打印，走一遍完整 35 秒，确认能收到 `stage_start` → 6 条 `cue_fire`（做成/做错都会有）→ 至少一条 `cue_miss` → `remedy_open`/`remedy_show` → `stage_end`。
3. 图形环境实测必须做：无头模式证明不了火苗听感、贴图可读性和节拍观感。

---

**待 A 与 B 双方确认后本文件即为第一关显示契约。** 有异议请在 B 实现之前提，不要在已经接好之后改字段含义。
