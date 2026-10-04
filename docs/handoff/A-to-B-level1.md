# A → B 交接：演出显示契约（前四关）

> 版本：2026-10-04 · 负责人 A（操控、节拍与关卡规则）
> 范围：**前四关（教学关）**，只覆盖 B 需要的「读什么、什么时候读、别做什么」。
> 依据：[PRD.md](../../PRD.md) 第 3、4、5、6 节；[TECH_DESIGN.md](../../TECH_DESIGN.md) 第 1.1、2.1、2.3 节；`docs/superpowers/plans/2026-10-03-level1-a.md` 第 1 节。
> 本文件由 A 维护。B 若要改字段含义，先告诉 A，不各自改契约。
> **文件名仍是 `A-to-B-level1.md`（避免打断已有引用），但内容已覆盖到第 4 关。**

## 0. 一句话边界

**B 只读 A 的状态与事件，不写。** 拍点、判定窗、命中/错拍、补救时机、关卡结束时刻全部由 A 提供；B 不自己算拍点、不自己判对错、不自己决定「该显示到什么时候」。这与岗位表里「节拍与得分规则由 A 统一提供」一致。

## 1. A 的代码在哪（重要）

| 项 | 事实 |
| --- | --- |
| `origin/main` | **没有 A 的代码**。HEAD `285b8db`，只有工程初始化与文档，共 6 个提交。 |
| A 的代码 | 在 `feat-level1-controls`。本地 HEAD `66a241a`，相对 `origin/main` 领先 14 个提交；远端 `origin/feat-level1-controls` 仍停在 `e791acd`，本地比它领先 4 个提交。 |
| 已落库的基线 | 原先那批在建改动（手部可抬 180°、翻面 0.1 秒正/反两面、补救冻结 + 慢鼓 + 8 秒按真实时间计）已作为基线提交 `f71e0ce` 入库；其后的 `66a241a` 把慢放倍率由 0.1 改为 **0.5 倍速**。要这些代码取 `feat-level1-controls` 即可（推送后）；按下面的命令拿到的仍是 `e791acd` 旧版。 |
| PR | 尚未创建，`origin/main` 上没有任何合并记录。 |
| 工作区 | 干净。 |

取代码（远端未更新前，这样拿到的仍是 `e791acd`）：

```powershell
git fetch origin
git switch -c feat-<你的模块> origin/feat-level1-controls
```

B 要看的文件都在 `scripts/a/`、`scenes/a_test/`、`tests/a/` 下。

**游戏入口：** `scripts/game_flow.gd` 现在会把 `scenes/a_test/level1_a.tscn` 作为第一关实例化进来，所以双击运行游戏即进第一关。选关菜单做出后这里改成进选关，第一关场景本身不受影响。

**演出场景（前四关共用一个）：** `scenes/a_test/level1_a.tscn` + `scripts/a_test/level1_a_scene.gd`。
关卡由命令行参数切换：`godot.exe --path . res://scenes/a_test/level1_a.tscn -- stage=2`（1–4，缺省第 1 关）。
**这是开发用开关，刻意不做成按键**——PRD 第 4.1 节只定义了一套键位，往演出场景里加测试键会让玩家按到没有文档依据的键。

**输入集（只有 PRD 第 4.1 节这一套，没有测试专用键）：** 鼠标左键点影人 / 手边的签 = 接手并拖胸签，滚轮 = 推拉灯，`Q`/`E` = 倾灯，`A`/`D`/`Shift+A`/`Shift+D`/`W`/`S` = 双手，`1`/`2`/`3` 或点备用头架 = 换头，空格 = 挂起/取回影人，`ESC` 或右上角按钮 = 暂停。**空格不再是暂停键。**
第 1 关的空格按不动（两个挂钩槽被布景占满），第 2 关开局**留有一个空挂钩**，空格在第 2 关是必须用的键——原因与影响见第 7 节末。

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
| `hand_angle` | `Vector2` | 各分量 `-1.5708`–**本关上界** | `.x` = 左手、`.y` = 右手，**弧度**；`0` = 手臂自然垂下，`+π/2` = 水平前伸，`+π` = 举过头顶，负值为收手。**上界按关不同**：第 1 关是 `+π/2`（90° 打伞位，理由见 §7.1），第 2–4 关是 `+π`；下界一律 `-1.5708` |
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
| `umbrella_take` | **第一关借伞**：白素贞走进交接窗口（两只手相接的位置带）且左手与许仙右手齐平 → 伞转到白素贞左手。她**不必贴到许仙身上、更不必穿过他** | `{"umbrella_id", "umbrella", "holder_id", "holder_hand", "handed_from", "borrow_x", "metric"}`，`metric` = 白素贞当时的接地点 x |
| `umbrella_return` | **第一关还伞**：已经到过最右端、并走回交接窗口（向左返回） → 伞自动交回许仙右手 | 同上；`metric` 为还伞时的 x |
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

**2026-10-04 新增的动作取值（事件种类没有新增，只是 `action` 多了五个）：** `cue_hint` / `cue_fire` / `cue_hit` / `cue_miss` 的 `action` 字段现在可能是 `hook`、`take_back`、`head_swap`、`lamp_distance`、`lamp_exposure`（此前只有 7 种姿势/移动动作）。B 若在 `match action` 里穷举，需要补这五个；未匹配到已知动作时请按「未知动作」安静跳过，不要报错。

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

`kind` 八种，与动作一一对应。带 ✱ 的是 2026-10-04 新增（第 2–4 关的教学内容）：

| `kind` | 对应动作 | 出现在 |
| --- | --- | --- |
| `stance` | `stand_up`、`crouch` | 第 1 关 |
| `hand` | `hand_raise`、`hand_lower` | 第 1、2、3、4 关 |
| `move` | `move_left`、`move_right` | 第 1、2、3、4 关 |
| `reach` | `reach` | 第 1、2、3、4 关 |
| ✱ `hook` | `hook`（挂起）、`take_back`（取回） | 第 2 关 |
| ✱ `head` | `head_swap`（换头） | 第 4 关 |
| ✱ `lamp_distance` | `lamp_distance`（滚轮推拉灯） | 第 3、4 关 |
| ✱ `lamp_exposure` | `lamp_exposure`（Q/E 倾灯显露） | 第 4 关 |

**线索不得泄露精确拍号、数值评分或观众心理**（PRD 第 5.1、8 节）。B 拿到的 `beat_time_ms` 是为了算图标淡出时机，不是给玩家看的数字；请勿在画面上显示拍号或倒计时秒数。

**新增落点的目标范围**：`target_range.key` 除原有的 `stance`/`hand`/`angle`/`facing`/`x`/`y` 外，新增 `distance`、`exposure`（灯的连续量，取自 `LampState`）与 `slot`（换头/挂起的架位）。`hook`/`take_back`/`head_swap` 三类**不带目标范围**（任意一次挂起/取回/换头都算做到）；它们的 `cue_hint` 里 `target_object` 是**解析后的具体影人编号**，不会是 `-1`。

## 6.2 第一关的伞：B 怎么画（**2026-10-04 新增，同日改为「显示端按手腕画」**）

伞的运行状态由 `UmbrellaController`（`scripts/a/umbrella_controller.gd`）持有，**B 只读**。
取法：`runtime.director.umbrella` —— **其它关卡这里是 `null`**，
所以「本关有没有伞」只需判一个 null，不必各自去查 `stage_id`。

| 读什么 | 单位 | 含义 |
| --- | --- | --- |
| `umbrella.holder_id_of()` | `int` | 当前持伞的影人编号（`0` 白素贞 / `1` 许仙） |
| `umbrella.holder_hand_of()` | `String` | 持伞的手：`"left"` / `"right"` |
| `umbrella.handing_off` | `bool` | 是否正在做递伞过渡（一只手把伞递给另一只手） |
| `umbrella.handoff_from_id()` | `int` | 过渡的**起点**是哪只手的主人；`handing_off` 为 false 时无意义 |
| `umbrella.handoff_from_hand()` | `String` | 过渡起点的那只手 |
| `umbrella.handoff_blend()` | `float` 0–1 | 过渡进度（**已缓入缓出**）：`0` = 还在原来那只手上、`1` = 已到新手上 |
| `umbrella.borrow_position()` | `float` | 本次实际接伞时的接地点 x（供显示端/录制参考；**还伞的判据是走回交接窗口，不是精确回到这一点**） |
| `umbrella.has_reached_right_edge()` | `bool` | 本次持伞期间是否已到过舞台最右侧（还伞的前置条件） |
| `umbrella.position` | `Vector2`，各分量 0–1 | **A 内部口径，不要用它换算像素**（见下） |

**伞画在哪，由显示端决定：画在你（显示端）画出的那只手腕上。**

```gdscript
# 每帧（在你画完影人之后，位置取你自己画手时用的那个腕点）
var holder := puppets[umbrella.holder_id_of()]        # 或你自己的影人视图节点
var at: Vector2 = 该影人 hand=umbrella.holder_hand_of() 那只手的腕点像素位置
if umbrella.handing_off:
    var from: Vector2 = puppets[umbrella.handoff_from_id()] 的
        hand=umbrella.handoff_from_hand() 那只手的腕点
    at = from.lerp(at, umbrella.handoff_blend())      # 画面上就是「一只手把伞递出去」
```

**为什么 A 不给像素位置（2026-10-04 修）。** 原先 `umbrella.position` 号称「已经算好是
持伞那只手的位置」，但那是 A 自己的一套归一化口径（肩高 0.68、臂长 0.30，且没有灯距缩放），
与影人显示端画出来的手臂比例（肩在接地点上方 0.80 身高、整条手臂 0.31 身高）**不是同一套数**；
显示端还要把它按幕布矩形换算，而影人是按整块画布换算，于是坐标系也不一致。实测结果：
许仙开局举伞时伞被画在幕布底部 `y≈668`，而他自己的右手在 `267` 高处——**「开局伞不在许仙手上」**。
现在 A 只回答「归谁、哪只手、有没有正在递」，落点由画手的那一方给，天然对齐；
灯距推拉让影子变大变小时，手和伞也一起缩放。参考实现：
`level1_a_scene._draw_umbrella()` + `placeholder_puppet.hand_screen_position()`。

**先落地（推荐）**：正式影人素材的手臂比例与占位不同，因此**不要**照抄占位的那几个比例常数，
照抄会把这次的坑换个地方再踩一遍——你只要「伞画在我画的那只手上」这一条。

**三件事 B 不要做：**

1. **不要自己判「接伞/还伞的条件成不成立」。** 交接窗口（两只手相接的位置带）、
   手高容差（±0.04）、「已到过最右端」、以及「还伞之后必须先离开交接窗口才能再接一次」
   全在 A 侧；A 会在成条件的那一刻给出 `handing_off` 与归属变化，你照它画就行。
   （`UmbrellaController.hand_height()` / `hand_position()` 是 A 判「两只手是否齐平」用的
   内部口径，**别拿去换算像素**。）
2. **不要把伞画在幕布前那一层。** 幕后看到的是影人背面，伞在背面那一侧；
   参考实现（`level1_a_scene._draw_umbrella`）把它画在挂钩与签手**之前**，免得压住持伞的人。
3. **不要按 `cue_id` 认伞事件。** `umbrella_take` / `umbrella_return` 的 `cue_id` 是
   **空串**（它们由状态机产生，不是输入事件）；要认就认 `kind`。
   判定结果仍照常走 `cue_hit` / `cue_miss`，其 `action` 为 `umbrella_take` / `umbrella_return`。
   顺带记一条 A 侧踩过的坑（B 侧读 `cue_hint` 时会看到同一个字段）：
   **这两条落点的 `target_object` 必须等于事件上报的 `object_id`**——事件上报的是
   **接手的那个人**（接伞记白素贞 `0`、还伞记许仙 `1`），判定里拿 `target_object != object_id`
   直接跳过这条 cue。还伞这条曾被写成 `0`，结果**玩家把伞还回去也判不到**，
   窗一过就被判「完全没做」并开出补救窗口。

**伞的提示图标**：`cue_hint` 的 `hint_kind` 新增 `umbrella`；
`l1_c4_take_umbrella` 与 `l1_c6_return_umbrella` 的目标范围 `key` 都是 `x`，值就是**交接窗口**
（约 `[0.176, 0.296]`，由「两人都抬手到 90° 时两只手在中间相接」推出），
B 按已有的「目标边界」画法处理即可。另注意 `l1_c5_move_to_edge` 的 `x` 目标带是 `[0.95, 1.0]`——
它**必须与交接窗口完全不重叠**，否则「走到最右端」这一步会先经过交接窗口、被还伞抢走伞。
`l1_c5_move_to_edge` 的动作因此是 `move_right`（此前是 `move_left`）。

## 6.1 两类提示手：教学手与补救手（**新增，B 必须区分**）

PRD 第 5.1 节要求「目标动作必须在落点之前有可感知的线索」，第 5.2 节又要求失误后出现师父示范手。这两件事在画面上都表现为一只手，但**触发时机与条件必须互相区分、互不重叠**：

| | 教学提示手（前四关） | 补救提示手 |
| --- | --- | --- |
| 何时出现 | 某条落点进入 `hint_time_ms`（= 落点 − `hint_lead_ms`，默认提前 1 s）且**尚无判定结果** | 补救窗口开着（收到 `remedy_show`、`current_demo_cue_id` 非空） |
| 何时消失 | 该落点被判定（`cue_hit` / `cue_miss`）或过了判定窗 | 窗口关闭（`remedy_hide`、补做成功 / 超时 / 收场） |
| 计时依据 | **歌曲时间**（`get_song_time_ms()`，演出正常推进） | **真实时间**（`get_real_time_ms()`，歌曲时间此时已冻结） |
| 建议样式 | 半透明描边（预告，视觉上轻） | 实色填充 + 外圈光晕（纠正，视觉上重） |

**互斥规则（只有一条，请照此实现）：补救冻结期间一律不画教学手，同一时刻只画一只；补救手优先。**
理由有二：① 补救冻结时演出时间停住、**新的落点不会到来**，此时预告「即将到来的动作」是误导，而玩家正在补做上一个动作；② 漏做型补救的窗口开在落点之后，该落点的线索时段本就已过，天然不重叠；只有「低合拍型补救挂在段内更靠前、还没到落点的 cue 上」时才可能重叠，必须显式压制。

A 侧把这条规则做成了静态纯函数 `level1_a_scene.hint_hand_choice(paused, over, is_tutorial, frozen, remedy_demo_cue_id, active_cue_id)`，返回 `HAND_NONE` / `HAND_TEACHING` / `HAND_REMEDY` 三者之一。B 可以直接照它的取值表实现，A 侧测试已穷举全部输入组合断言「结果只可能是三者之一」。

**第 5 关没有常驻教学手**（PRD 第 3、6 节：第 5 关撤掉教学图标，只在失误时出现示范手）。判定教学关用 `StageDef.is_tutorial()`（前四关为 true）。

同样受互斥规则约束的还有**目标边界与方向箭头**：补救冻结期间也不画（A 的显示端已如此实现）。

## 7. 前四关的具体数据

四关数据**都在代码里**：`scripts/a/stage_def.gd` 的 `StageDef.make_stage(id)`（`id` 取 1–4）。
**没有 `data/levelN.tres` 或 `.json`**——B 不要另抄一份 cue 表，直接调这个静态方法取，避免两处数据漂移。
未知编号返回 `null`（不静默给一关默认数据）。

四关统一 BPM **96**（一拍 625 ms，PRD 第 10 节的原型区间 90–100），时长与 PRD 第 6 节一致：

| 关 | 关名 | 折（《白蛇传》） | 时长（歌曲时间） | 拍数 | 关键动作 | 本折教的动作 |
| ---: | --- | --- | ---: | ---: | ---: | --- |
| 1 | 入手 | 游湖借伞 | 35000 ms | 56 | 6 | 胸签、双手、鼓点 |
| 2 | 双人 | 游湖同舟 | 45000 ms | 72 | 7 | 挂起 / 取回、一人挂起保持姿势一人运动组同框 |
| 3 | 灯位 | 盗仙草 | 50000 ms | 80 | 7 | 滚轮推拉灯，全场影子同步缩放 |
| 4 | 显隐 | 端阳现身 | 55000 ms | 88 | 9 | 换头 + 倾灯控制影子显露 |

四关歌曲时间合计 185000 ms；加上第 5 关 110 秒共 295 秒，满足 PRD A02 的「不超过 300 秒」。
**情节只决定谁出场、怎么出场、动作的动机，不改动各关要教的操作与判定范围。**

**开演布景（新增契约）：** `StageDef.initial` 描述每关开局怎么摆，**B 只读**：

| 键 | 类型 | 含义 |
| --- | --- | --- |
| `controlled` | `int` | 起始受控影人编号 |
| `on_stage` | `[int]` | 在场的影人编号；**不在列表里的未登场，B 不要画**（第 2、4 关只有两人登场） |
| `hung` | `{int: int}` | 影人编号 → 挂钩槽位（0/1） |
| `positions` | `{int: [float, float]}` | 接地点归一化 x/y |
| `hand_angles` | `{int: [float, float]}` | 左右手角（弧度） |
| `distance` / `exposure` / `oil` | `float` | 灯的初值（第 4 关 `exposure` 从 0.15 低显露起步） |

**第 2 关开局必须留一个空挂钩**，这是它和第 1 关布景的唯一关键差别：两钩都满时 `hook_current()` 找不到空位必然失败，而 `take_back` 又要求「当前无人受控」，玩家会卡死在原地、整关无法完成。因此第 2 关只让白素贞与小青登场（`on_stage = [0, 1]`）。

### 7.1 第一关明细

时长 **35000 ms**（绝不延长），共 56 拍。

段落（6 段，连续覆盖整关）：

| 段落 | 起 | 止 |
| --- | ---: | ---: |
| 出峨眉 | 0 | 1875 |
| 化人形 | 1875 | 4375 |
| 游湖 | 4375 | 7500 |
| 借伞 | 7500 | 13750 |
| 还伞 | 13750 | 20000 |
| 同舟 | 20000 | 35000 |

关键动作（8 条，容差均为 ±250 ms，重音每 4 拍一次）。
**线索提前量按动作类型分两档**（2026-10-04 修订）：
**原地动作**（蹲下 / 站起 / 抬手 / 接伞 / 放手）提前 **1000 ms**；
**长距离移动**（向左走 / 走到最右端 / 走回还伞）提前 **3000 ms**——理由见下面的「长距离移动的时间预算」。

**2026-10-04 修订：第一关按用户给定的「借伞还伞」流程重排**——许仙固定站位、右手举到 90°（打伞位）持伞；
白素贞走到他面前、把左手抬到 90°，**两只手碰到一起**就自动接伞（不必贴住他、更不必穿过他）；
接到伞后向右走到舞台最右边；再转身（拖动方向一变自动翻面）走回，走回交接窗口就把伞还回许仙右手，然后放手。
原来的「蹲/站/左右横移/中位到位」六条已被这条流程取代：

| `cue_id` | 落点 | 重音 | 动作 | 目标范围 | 线索可见于 |
| --- | ---: | :---: | --- | --- | ---: |
| `l1_c0_crouch` | 1250 ms（第 2 拍） | | 蹲下 | `stance ∈ [0.85, 1.0]` | 250 ms |
| `l1_c1_stand` | 2500 ms（第 4 拍） | ✓ | 站起 | `stance ∈ [0.0, 0.05]` | 1500 ms |
| `l1_c2_move_left` | 5000 ms（第 8 拍） | | 向左走（走向许仙） | `x ∈ [0.0, 0.35]` | 2000 ms |
| `l1_c3_hand_raise` | 8750 ms（第 14 拍） | | 抬起左手到打伞位 | `angle ∈ [1.309, 1.571]` rad（75°–90°） | 7750 ms |
| `l1_c4_take_umbrella` | 10000 ms（第 16 拍） | ✓ | **接伞** | `x ∈ [0.176, 0.296]`（交接窗口） | 9000 ms |
| `l1_c5_move_to_edge` | 13750 ms（第 22 拍） | ✓ | 持伞**向右**走到最右边 | `x ∈ [0.95, 1.0]` | 10750 ms |
| `l1_c6_return_umbrella` | 17500 ms（第 28 拍） | ✓ | **还伞**（走回交接窗口） | `x ∈ [0.176, 0.296]`（同一窗口） | 14500 ms |
| `l1_c7_hand_lower` | 18750 ms（第 30 拍） | | 放下左手收势 | `angle ∈ [0.0, 0.35]` rad | 17750 ms |

### 7.2 长距离移动的时间预算（**B 需要注意的手感约束**）

这一折里有两次「走到一端」：接伞后走到最右端（第 22 拍），再从最右端走回交接窗口（第 28 拍）。
每次要走约 **0.65 个舞台宽 ≈ 1250 画布像素**。拖动是 1:1 映射（`dpx.x / STAGE_PIXEL_SIZE.x`，
`STAGE_PIXEL_SIZE.x = 1920`），正常拖速 450~600 px/s 下需要 **2~2.8 秒**，再加 0.3~0.5 秒反应时间。

所以这两条落点各留 **6 拍 = 3.75 秒**（接伞在 10000 → 走到最右端 13750 → 还伞 17500），
线索也提前 **3 秒**出现。**这不是随手定的拍号**：早先版本把它们按第 20/24 拍排（拍间 2.5 秒）
且线索只提前 1 秒，等于「看到提示就只剩 1 秒去拖 1250 像素」——实测玩家根本走不到
（用户 2026-10-04 报的「一接到伞就立刻要向右走、根本来不及」）。

`tests/a/test_level1_cues.gd` 的 `_test_01` 会把这两条约束钉住：**长距离移动落点的拍间间隔
与线索提前量都必须 ≥ `StageDef.MOVE_BUDGET_MS`（3000 ms）**，同时原地动作的线索提前量
必须保持默认 1 秒。改拍号或改提前量时若把它们改小，这条断言会失败。


`cue_id` 有两条注意：

- `l1_c2_move_left` 与 `l1_c5_move_to_edge` **id 必须不同**（动作也相反：前者 `move_left`、
  后者 `move_right`）：它们是两次独立的漏做机会。补救系统按 `cue_id` 去重，共用一个 id
  会让同一条漏做开出两个窗口（这个坑实测踩到过）。
- 许仙的举伞角是 **90°（水平前伸，打伞位）**：打伞不需要举过头顶——伞杆从手向上撑起、
  伞面正好罩在头顶（用户 2026-10-04 定案，此前是举满 180°）。这一折的**手角上界也收到 90°**
  （`StageDef.hand_angle_max_rad`），于是「抬到 90°」变成一个**能停住的位置**：按住 A 到顶
  就是 90°，玩家不必掐角度、也不会扫过头（90° 是行程中间点，若靠松手去停在它上面，
  窗口只有约 30 ms）。
- 白素贞的抬手到位区间是 **`[75°, 90°]`**，它**完整包住接伞的对齐窗口**：对齐要求两手手高差
  ≤ 0.04，换算成角度约 ±7.6°，叠加本关 90° 上界后窗口就是 82.4°~90° ⊂ `[75°, 90°]`。
  这条包含关系由 `tests/a/test_level1_cues.gd` 的 `_test_15` 用数值扫描钉住——否则会出现
  「拍点算抬手到位、伞却不换手」。

注意：**判定的是「姿势到位或状态切换」的那一瞬间，不是平移的每一帧**。「到位」（`reach`）要求本次拖动中先离开过目标范围再进入——原地起拖不算到位。

**手角口径（本次变更）**：`hand_angle` 以**手臂自然垂下为 0**、`+π/2` 为水平前伸、`+π` 为举过头顶；抬手速度 4.5 rad/s，从垂直到 180° 约 0.7 秒。**上界按关不同**：第 2–4 关的「抬手」落点到位区间是 135°–180°（举桨 / 采仙草 / 举杯），玩家在落点前约 0.5 秒开始按住；**第 1 关不同**——本折上界收到 90°，抬手到位区间是 75°–90°，按住 A 到顶即到位（见 §7.1）。

**翻面口径（本次变更）**：`facing` 只在 ±1 之间取，一次翻面约 0.1 秒（60 fps 下 6–7 帧）。B 画翻面请按 `turn_progress` 把宽度压到 `|2p−1|`（先窄后展开），换面（切换正/反面贴图）发生在 `turn_progress = 0.5` 那一帧；不要再按 `facing` 做连续插值，那样会退化成缓慢旋转。

**补救冻结（本次变更）**：补救窗口一开，歌曲时间轴就冻结（B 会收到 `remedy_freeze_begin`，鼓点变成 0.5 倍速），8 秒按**真实时间**计；窗口全部关闭才解冻（`remedy_freeze_end`）。第一关 8 条落点若全部漏做，真实耗时约 99 秒，而歌曲时间仍然正好 35 秒。

**空格（挂起/取回）在第 1 关不会发生：**第一关开局三个影人同时在场，其中两个分别挂在两个挂钩上（PRD 第 4.2 节），
所以两个挂钩槽从第一帧起就是满的，`hook_current()` 找不到空位、必然失败。因此**第 1 关不会产生
`puppet_hook` / `puppet_take_back` 事件**，也不会出现「无人受控」的帧——B 不必为第 1 关准备这两种情况的兜底画面。
A 侧 HUD 会按**实际可用性**自动决定是否显示那行提示（挂钩满的时候不显示，避免说了做不到），这个规则是纯函数 `level1_a_scene.hook_hint_text`。

**第 2 关相反，这两种事件都会出现，B 必须准备兜底画面：**
- 挂起后 `controlled_id = -1`，会有一段时间**无人受控**（`get_controlled()` 返回 `null`）。B 的取胸签、画竹签连线、取「当前影人」的地方都要容忍无人受控，不要直接取 `puppets[0]` 顶替。
- 第 2 关的关键动作大多以「当前受控影人」为目标（`target_object = -1` 在 A 侧内部表示该含义，**对外事件里的 `object_id` 已经解析成具体编号**）。
- 第 2 关开局挂着一个影人（`hung`），取回之前它保持姿势、不运动；这与第 1 关「两人挂在钩上」是同一套状态，B 的挂起表现可以直接复用。

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
| 低合拍补救路径 | 机制可用并已单独验证。**2026-10-04 起在标准第一关数据下也能真的开窗了**：改版后的「借伞」段含三条落点，满足「段内已判定 >= 2 且还剩未判定」的前提。阈值仍需游玩实测校准。 |
| 还伞落点的拍点容差 | **已澄清（2026-10-04）**：此前记的「还伞在无头测试里稳定偏 +260 ms、疑似测试台拖动模型问题」是**误诊**。真因是关卡数据 `l1_c6_return_umbrella` 的 `target_object` 写成 `0`（白素贞），而交接事件上报的 `object_id` 是「接手的人」=许仙 `1`，判定里 `target_object != object_id` 直接把这条 cue 跳过——**它从来没被判过**，每次都是窗过之后由 `detect_misses` 判死，offset 正好是窗上界之后的 +260 ms。改成许仙后这条落点恢复判定，`tests/a/test_remedy.gd` 的 01c 现已覆盖「还伞按拍命中 + 零补救窗口」。 |
| 补救冻结的记录与回放 | A 已产出 `remedy_freeze_begin` / `remedy_freeze_end` 与 `real_time_ms`，但 **C 的录制契约尚未定案**。回放必须靠这两个事件还原「这段真实时间不计入歌曲时间」，否则 1:1 回放会比重看的实际演出短。C 定契约时请把这两个 `kind` 纳入。 |
| 慢鼓音色 | 补救期间的 0.5 倍速鼓是**现场合成的占位声音**（同一套临时节拍音按 0.5 倍速播放）。正式锣鼓到位后，慢鼓应由正式素材提供；时钟与事件契约不受影响。 |
| 音频延迟补偿 | 时钟按音频播放位置增量累计；实际听感（是否真的对上鼓点）**只能人工听**，无头模式用虚拟音频驱动，证明不了。 |
| 音频停摆的降级 | `MusicClock` 有停摆看门狗：播放器自称在播但播放位置连续 0.6 秒不前进（声卡缺失/被独占/缓冲停摆）时，会降级为自由计时并 `push_warning`，此时 `is_audio_driven()` 变 `false`。**B 的 HUD 可以据此提示玩家**，A 的第一关已经这么做了。降级只换时间来源，判定规则一条不变。 |
| 诊断开关 | 第一关支持 `场景文件 -- diag` 启动（`level1_a.tscn -- diag`），每 30 帧打印 `fps / song / audio_driven / playing / pos / advance / ui`。排查「看到卡住」时先跑这个，别靠肉眼猜。 |

**2026-10-04 修掉的一处补救重复开窗（B 只需知道结论）：** 两条触发路径（漏做 / 低合拍）
各自都有去重，但**跨路径**没有。低合拍路径按段挑「本段第一条还没判定的 cue」，
而那条 cue 如果一直没人做，稍后必然也被漏做路径选中——实测同一个 `l1_c5_move_to_edge`
先吃一个低合拍窗口、超时关闭后再吃一个漏做窗口，补救窗口总数比落点数还多一个。
现在 `_already_recorded()` 认「已有记录」的落点（低合拍与漏做都算），
**一个落点在一次演出里最多补救一次**，符合 PRD 第 5.2.6 节「同一错误不能反复触发自己的窗口」。
B 侧不需要改任何东西，只是不会再看到同一 `cue_id` 的两条 `remedy_open`。

## 10. B 怎么自证接对了

1. 先只画一个只读 HUD，把 `puppets[0]` 的九个字段和 `lamp` 的四个字段逐帧打出来，跑 `scenes/a_test/level1_a.tscn`，确认数值与 A 的测试场景 HUD 一致。
2. 再把 `take_events()` 逐条打印，走一遍完整 35 秒，确认能收到 `stage_start` → 8 条 `cue_fire`（做成/做错都会有）→ 至少一条 `cue_miss` → `remedy_open`/`remedy_show` → `stage_end`。
3. 图形环境实测必须做：无头模式证明不了火苗听感、贴图可读性和节拍观感。

---

**待 A 与 B 双方确认后本文件即为第一关显示契约。** 有异议请在 B 实现之前提，不要在已经接好之后改字段含义。
