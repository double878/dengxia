extends RefCounted
class_name UmbrellaController
## 第一关「借伞 → 回到小青身旁」流程。
##
## 🔴 2026-10-16 用户定案简化：**取消还伞**，流程收在「接到伞后走回小青身旁」。
##   原「走到折返点再转身走回许仙还伞」两段随之退役（还伞通路已从本控制器删除，
##   理由见 `TURN_POINT_X` 注：新站位下连它的方向判据都反了，留着即是隐患）。
##
## 这条流程是**状态机 + 两个判定点**（接伞、归位），与操控控制器（PuppetController）分开：
##   - PuppetController 只负责「胸签、站蹲、翻面、双手」，不知道伞的存在；
##   - 本控制器只读 PuppetState，不写任何影人字段，只维护伞自己的归属与位置；
##   - 交接发生时产出 `umbrella_take` / `umbrella_return` 事件，交给
##     PerformanceSystem 按拍点判定（与抬手/挂起/换头走同一条判定路径）。
##
## 伞**画在哪**不归本控制器管：本控制器只说「伞现在归谁、握在哪只手、有没有正在递」。
## 位置读数（`position` / `hand_position`）是 A 内部的相对口径，与影人显示端画出来的
## 手臂比例不是同一套坐标系，显示端不要拿它换算像素——要把伞画在手上，请用显示端自己
## 画出的手腕（`PlaceholderPuppet.hand_screen_position()`）。理由与实测见 A→B 交接文档 6.2 节。
##
## 对照流程表（2026-10-16 第四轮用户定案版：借伞 → 接到伞即收场对话）：
##   开场      许仙立在**桥上**（0.58，桥面高 588px）、右手举到 140° 把伞托在头顶；玩家控制白素贞。
##             白素贞与小青立在柳树一带（0.32 / 0.26）——白素贞在小青靠许仙的那一侧。
##   接伞      白素贞向右走到许仙面前（**不必贴住他、更不必穿过他**）、把一只手抬到
##             打伞位（90°）或更高（🔴 2026-10-16 用户定案：**左手右手都可以**，手臂最大
##             可以举到**竖直**）→ 手一到打伞位以上，伞自动转到那只手。
##   收场      🔴 2026-10-16 第四轮用户定案：**借到伞后不用返回**——接伞判据本就要求她
##             处在许仙旁的交接窗口里，接到伞即收关（`Act1OperaFlow.after_update`），
##             收场段将接入借伞后的对话（内容待用户提供）。「走回小青身旁」环节退役。
##   收势      更早已下线（「最后不用放下手」），不再要求任何落手动作。
##
## ⚠️ 本控制器只说「伞归谁」，**关卡何时收尾由 `Act1OperaFlow` 在接伞事件处决定**；
## `is_at_home()`/`TURN_POINT_X` 只作历史口径保留（见下注）。
##
## 「交接位置」是**两只手相接**的那一段：两人各朝对方伸出一只手，
## 接地点相距「两人伸出量之和」（`CONTACT_REACH_X`）时两只手正好碰上；
## 容差 `HAND_JOIN_TOLERANCE` 给出一个位置带（见 `join_window_x()`）。
## ⚠️ 两人的伸出量**不相等**——许仙把伞托在头顶（手角 140°，水平投影缩短），
##   白素贞抬到打伞位（90°，水平投影满值）；且两人的半身宽各按自己的素材比例。
## 用户 2026-10-04 修订的原因：原先按「两人接地点距离」判，白素贞必须几乎站到许仙身上
## 才换手（画面上两具影身叠成一团），而两只手真正相遇的位置在那条判据之外。

const PuppetStateScript := preload("res://scripts/a/puppet_state.gd")

## 交接事件类型。object_id 为**接手的那个人**：接伞记白素贞。
## ⚠️ `umbrella_return`（还伞）自 2026-10-16 流程简化起**本关不再产生**；事件 kind 仍留在
## 记录契约里（C 侧 `c_timed_event.gd` 照旧接收、`PerformanceSystem` 照旧能翻译），只是没有发出者。
const KIND_TAKE: String = "umbrella_take"

## 伞只有这一把，全局编号固定。
const UMBRELLA_ID: int = 0
const UMBRELLA_NAME: String = "umbrella_main"

## 角色分工（PuppetState.puppet_id）。与 StageDef.make_level1 的 initial 一致。
const XUXIAN_ID: int = 1  ## 许仙：固定站位、右手举伞
const BAISUZHEN_ID: int = 0  ## 白素贞：玩家控制
const XUXIAN_HAND: String = "right"
## 🔴 历史名：许仙固定用右手，白素贞**左右手都可以接伞**（2026-10-16 用户定案）——
## 实际接在哪儿由 `_meeting_hand()` 现场判断并写进 `_holder_hand`，本常量只作
## 测试与旧数据引用的「默认接伞手」保留，不再参与判定。**不要改名**（测试在用）。
const BAISUZHEN_HAND: String = "left"

## —— 「两只手相接」判据（本流程的核心，用户 2026-10-04 定案）——
## 影人把手伸到某个角度时，手在**水平方向**上伸出的长度 = 半身宽 + 整条手臂的水平投影。
## 手臂的水平投影随「手举得多高」收缩：手角 90°（水平前伸）时是满值，越过 90° 之后
## 按 cos(手角 − 90°) 缩减——许仙把伞托到头顶（140°）时，投影只剩 cos 50° ≈ 0.643。
##
## 按占位影人的几何（见 `placeholder_puppet.gd`）算一遍。身高 = 230 px × 灯距倍率 1.07 ≈ 246 px，
## 整条手臂 0.31 个身高（上臂 0.16 + 下臂 0.15）：
##   许仙   = (0.105 + 0.31 × 0.643) × 246 ≈ 74.9 px ≈ **0.0390** 幕布宽（举伞 140°，手臂已过头顶）
##   白素贞 = (0.074 + 0.31 × 1.000) × 246 ≈ 94.5 px ≈ **0.0492** 幕布宽（打伞位 90°，手臂水平）
## 半身宽各按素材清单的 `shoulder_half_width_ratio`（许仙没配 → 兜底 `HALF_W_RATIO` 0.105；白素贞 0.074）。
## 两人相对而立、各朝对方伸出一只手 ⇒ 接地点相距**两者之和**（≈0.0882）时两只手正好碰上。
##
## ⚠️ 这两个数跟着影人素材的几何走（也随灯距缩放坐 ±25%）。正式素材到位后必须重新对一次，
## 并由 `tests/a/test_umbrella.gd` 的「判据与画面对表」断言兜住——否则会出现
## 「判据说手碰到了、画面上手还差半个身位」这种看不见的错。
##
## 🔴 2026-10-16（用户参考图定案：许仙把伞托在头顶）把这个投影改了：他由「举 90°」改成 140°，
## 伸出量从 0.0531 掉到 0.0390，交接位置随之向**右**移 0.018 个幕宽。
## 三方对表断言当场抓到这条（改之前两只手腕横向差 34.1 px），按新姿势重算后归零。
## **他（或她）的姿势一改，这里就必须重算**——窗口、落点带都由它派生。
const XUXIAN_REACH_X: float = 0.039
const BAISUZHEN_REACH_X: float = 0.04922
## 两只手正好碰上时的**接地点间距**（= 两人伸出量之和）。
## `join_window_x()` 与 `StageDef.LEVEL1_APPROACH_*` 都从它派生，别再在别处写一个小数。
const CONTACT_REACH_X: float = XUXIAN_REACH_X + BAISUZHEN_REACH_X
## 手与手之间的距离容差：0.06 ≈ 一掌宽。窗口因此是「接地点相距
## `CONTACT_REACH_X` − 0.06 ~ `CONTACT_REACH_X` + 0.06」= **0.028~0.148**，
## 也就是白素贞站在许仙左侧 0.03~0.15 个幕布宽处都能交接——**不必贴住他、更不必穿过他**。
## 接伞与还伞曾被设计为共用同一条判据；还伞退役后本判据只服务接伞（换手）。
const HAND_JOIN_TOLERANCE: float = 0.06
## 手高容差（幕布归一化高度）。换算到手臂角度约 ±0.13 rad（≈7.6°），
## 也就是说「两只手大致齐平」才算相接，随手乱举不会被判成相接。
## 只有换手那一下要这一条：接住伞之后她可以自行放下左手，伞跟着手落。
const HAND_HEIGHT_TOLERANCE: float = 0.04
## 🔴 **历史口径**（2026-10-16 第四轮定案后已退役）：`TURN_POINT_X` 原是「走回小青身旁」
## 归位阈值——接到伞后走回 x ≤ 此值即收关。第四轮定案「借到伞后不用返回，站在许仙旁
## 对话」后归位环节下线，本常量与 `is_at_home()` 只作历史口径保留（测试与旧数据引用），
## **不再有任何流程消费者**；不要拿它做新判据。
const TURN_POINT_X: float = 0.32

## 交接窗口的**参考手角**：判定用「她的手抬到**不低于**这个角度」。
##
## 理由（2026-10-16 用户参考图定案：许仙把伞举在头顶）：伞是**竖持**的，许仙握在伞杆上段、
## 白素贞握下段，两人的手本来就不在同一高度上，因此「两手齐平」不再是正确的判据。
## 这里取**打伞位 90°**（= `StageDef.LEVEL1_HAND_MAX_RAD`）作为**下界参考**：
## 手高到达打伞位（减去容差）即算到位。
## 🔴 2026-10-16 用户定案两条放宽：**左手右手都可以接**；且她的手角上限放宽到竖直（π），
## 「举得比打伞位更高」同样算到位（见 `_meeting_hand()`）。
## ⚠️ 它必须与 `StageDef.LEVEL1_UMBRELLA_RAISE_*` 的到位区间自洽，否则会出现
## 「拍点算抬手到位、伞却不换手」——见 `tests/a/test_level1_cues.gd` 的数值扫描断言。
const CONTACT_HAND_ANGLE_RAD: float = PI * 0.5

## 手部锚点在幕布上的归一化高度（肩/胸位置）。
const HAND_ANCHOR_Y: float = 0.68
## 整条手臂的长度（归一化）。0.30 与占位影人的「肩到手」比例一致。
const ARM_LENGTH: float = 0.30
## 蹲下时肩部整体降低多少（乘 stance）。接伞时两人都站着，这一项不参与；
## 它只在有人蹲着伸手时起作用，避免「蹲着也能与站着手齐平」。
const STANCE_DROP: float = 0.12

## 递伞过渡时长（真实秒）。流程表：手位较低时用短暂递伞过渡衔接。
const HANDOFF_DURATION_S: float = 0.18

var stage_id: int = -1
var puppets: Array = []
## 当前持伞的影人编号；-1 表示无人持伞（只在 setup 之前出现）。
var _holder_id: int = -1
## 当前持伞的那只手（"left" / "right"）。
var _holder_hand: String = XUXIAN_HAND
## 实际接伞时的位置（供显示端/录制参考）。
var _borrow_x: float = 0.0
## 🔴 历史口径：是否已回到小青身旁（x ≤ `TURN_POINT_X`）。曾是本关的完成条件，
## 第四轮定案「接到伞即收关」后**流程不再读它**；按当前位置直接赋值（不走锁存）。
var _at_home: bool = false
## 伞在幕布上的归一化位置（A 内部口径；**显示端不要拿它换算像素**，见 `hand_position()`）。
var position: Vector2 = Vector2.ZERO
## 正在做递伞过渡。
var handing_off: bool = false
## 交接发生那一帧伞的位置。过渡期间伞从这里、以递减的偏移趋向当前手位。
var _handoff_from: Vector2 = Vector2.ZERO
var _handoff_progress: float = 1.0
## 递伞过渡的**起点是哪只手**（交出去的那一方）。显示端按它把伞从那只手的手腕
## 送到新手的手腕上；不在过渡中时这两个字段没有意义（`handing_off` 为 false）。
var _handoff_from_id: int = -1
var _handoff_from_hand: String = ""

## 接伞「本轮是否已经上报过」：白素贞一直站在对齐位置上时，若不设这个门，每帧都会再报一次接伞。
var _take_reported: bool = false

## 鸭子类型时钟，只用来推进递伞过渡的时长（固定步长 = 1 / 物理帧率）。
var clock: Object = null
## 正式第一幕由剧情许可控制（唱段结束前不许接伞）；旧关卡/测试默认保持原行为。
var take_allowed: bool = true

var _events: Array[Dictionary] = []


## 建立第一关的伞流程。其它关卡不启用：返回 false 并保持禁用状态。
## p_puppets 是 PuppetController 的影人数组，按 puppet_id 取用（不假设顺序）。
func setup(p_stage_def: StageDef, p_puppets: Array) -> bool:
	_events.clear()
	_take_reported = false
	_at_home = false
	handing_off = false
	_handoff_progress = 1.0
	_handoff_from_id = -1
	_handoff_from_hand = ""
	stage_id = p_stage_def.id if p_stage_def != null else -1
	puppets = p_puppets
	if not is_enabled():
		_holder_id = -1
		return false
	_holder_id = XUXIAN_ID
	_holder_hand = XUXIAN_HAND
	_borrow_x = 0.0
	position = hand_position(XUXIAN_ID, XUXIAN_HAND)
	return true


## 本关是否启用借伞流程（只有第一关）。
func is_enabled() -> bool:
	return (
		stage_id == StageDef.LEVEL1_ID
		and _puppet(BAISUZHEN_ID) != null
		and _puppet(XUXIAN_ID) != null
	)


## 每帧一次。必须在 PuppetController.tick() 之后、StageDirector.update() 之前调用：
## 状态先定稿，交接事件与它们的时间戳再进同一条判定路径。
##
## `_frame_events` 是上一帧的判定结果（`cue_hit` / `cue_miss`）。本控制器目前不消费它，
## 保留这个入口是为了让「状态机读判定」与「判定读状态机」两条线都留在同一个签名里，
## 后续若要按判定结果调整交接表现（例如错拍时的迟疑）不必再改调用方。
func update(song_time_ms: int, _frame_events: Array) -> void:
	if not is_enabled():
		return
	# 递伞过渡按固定步长推进。刻意读 `Engine.physics_ticks_per_second` 而不是时钟上的方法：
	# 这里的时钟是鸭子类型（MusicClock / 测试用自由时钟），只保证有歌曲时间与真实时间两个读数，
	# 往它上面要物理帧率会让没实现该方法的时钟在演出中途报错（补救倒计时会因此卡住不走）。
	var delta_s: float = 1.0 / maxf(float(Engine.physics_ticks_per_second), 1.0)
	_advance_handoff(delta_s)
	if _holder_id == XUXIAN_ID and take_allowed:
		_try_take(song_time_ms)
	elif _holder_id == BAISUZHEN_ID:
		# 持伞期间每帧按当前位置刷新「有没有回到小青身旁」（本关的完成条件）。
		_note_at_home()
	_follow_hand()


## 鸭子类型时钟，用于递伞过渡的推进；只需 get_physics_ticks_per_second()。
func set_clock(p_clock: Object) -> void:
	clock = p_clock


## —— 交接窗口 ——
## 白素贞的接地点 x 落在 [min, max] 之内即「两只手相接」。
## 由「两人各把手伸到自己的持伞/打伞姿势」推出：伸出量之和为 `CONTACT_REACH_X`
## （见其注：许仙 0.0390 + 白素贞 0.0492），相距这个值时两只手正好碰上，
## 容差 `HAND_JOIN_TOLERANCE` 给出一段带。`xuxian_x` 是许仙的接地点 x。
##
## 🔴 那个**符号就是方向**：白素贞是从许仙的**左侧**过来的（她 0.32 → 许仙 0.5285），
## 手相接的位置在许仙**左方** `CONTACT_REACH_X` 处，所以这里是**减号**。
## 2026-10-16 定案（许仙回桥头）时**必须连同这个符号一起改**：只改站位不改它，窗口会落到许仙
## 右边——她得绕过他走到他右后方才接得到伞。
## 减号后窗口 = 0.58 − 0.0882 ± 0.06 = **0.4318~0.5518**（829~1059px，空地到桥面左段；
## 窗口右半落在桥跨上——白素贞站在那段时脚点随桥拱升起，见 `StageWalkPath`）。
##
## 沿革：最初是加号（许仙在台左 0.13、白素贞在台右 0.80）；2026-10-15 站位镜像（许仙换到
## 桥头 0.5285、白素贞换到台左 0.32）时改成减号；2026-10-16 一度改回加号（许仙在岸边 0.28），
## 同日定案再把许仙放回桥头，于是又回到**减号**；同日第三轮他再上桥面（0.58），窗口右移。
## **每次左右关系一变，这个符号都要跟着翻一次**——它和站位是同一条数据的两面。
## `StageDef.LEVEL1_APPROACH_*` 也照抄同一个符号，`test_level1_cues` 用等式把两者钉住。
##
## 刻意**按固定姿势**算一次，不按白素贞当下的手臂角度实时重算：她持伞往回走时可以自行
## 放下左手（伞跟着手落），若窗口随手臂高低移动，落点就会跟着漂，玩家没法瞄准。
##
## 落点数据（StageDef）与运行时判定（本控制器）共用这一个函数，免得拍点与判定漂开。
static func join_window_x(xuxian_x: float) -> Vector2:
	var contact_x: float = xuxian_x - CONTACT_REACH_X
	return Vector2(contact_x - HAND_JOIN_TOLERANCE, contact_x + HAND_JOIN_TOLERANCE)


## 手举到某个角度时，手在幕布上的归一化高度。
##
## 手角口径（PuppetState.hand_angle）：0 = 手臂自然垂下、π = 举过头顶。
## 高度 = 肩高 − 手臂在竖直方向上的投影，投影是 `ARM_LENGTH · cos(角度)`：
##   垂下（0）    → cos = +1 → 0.68 − 0.30 = 0.38（最低）
##   平伸（π/2）  → cos =  0 → 0.68        （齐肩）
##   举顶（π）    → cos = −1 → 0.68 + 0.30 = 0.98（最高）
## 用 `sin` 会得到「垂下手最高、举起手最低」的反向结果——两只手角度相同时
## 两处符号错误会互相抵消，于是「对齐」看起来还能成立，但单看一只手的高度就是错的。
##
## 这套肩高/臂长是 A 内部的**相对口径**，只用来比较「两只手是否齐平」（两边同一口径，
## 比例不影响结论）；它不等于画面上的实际像素位置——那张图由显示端按手腕画
## （A→B 交接文档 6.2 节）。
static func hand_height(hand_angle: float, stance: float) -> float:
	var angle: float = clampf(
		hand_angle, PuppetStateScript.HAND_ANGLE_MIN, PuppetStateScript.HAND_ANGLE_MAX
	)
	var drop: float = ARM_LENGTH * cos(angle)
	return HAND_ANCHOR_Y - drop - STANCE_DROP * clampf(stance, 0.0, 1.0)


## 某个影人某只手的相对位置（A 内部口径：判定「两只手是否齐平」与递伞过渡用它）。
##
## ⚠️ 它**不是**显示端的坐标系。手高按 A 自己的肩高/臂长口径算，与影人显示端画出来的
## 手臂比例不是同一套，也没有灯距缩放。显示端要把道具画在手上，请用显示端自己的
## `PlaceholderPuppet.hand_screen_position()`；拿这个值去换算像素会错位
## ——2026-10-04 实测把伞画到了幕布底部（A→B 交接文档 6.2 节）。
func hand_position(puppet_id: int, hand: String) -> Vector2:
	var state: PuppetState = _puppet(puppet_id)
	if state == null:
		return Vector2(0.5, HAND_ANCHOR_Y)
	var angle: float = state.hand_angle.x if hand == "left" else state.hand_angle.y
	return Vector2(state.stage_pos.x, hand_height(angle, state.stance))


## 伞此刻挂在哪只手上（A 内部口径，同 `hand_position`）。
## 递伞过渡中仍指向目标手：伞是「正往那只手去」。
func holder_hand_position() -> Vector2:
	return hand_position(_holder_id, _holder_hand)


## —— 只读别名（给显示端与测试用）——
## 与 `_holder_id` / `_borrow_x` 是同一个值，另开这两个入口是因为显示端读的是
## 「伞现在归谁、当初在哪儿接的」这两件事，直接读字段会让「谁该改它」变得模糊。


func holder_id_of() -> int:
	return _holder_id


func recorded_view() -> Dictionary:
	return {
		"holder_id": _holder_id,
		"holder_hand": _holder_hand,
		"handing_off": handing_off,
		"from_id": _handoff_from_id,
		"from_hand": _handoff_from_hand,
		"progress": _handoff_progress
	}


## 只供回放表现端使用；不调用 update，不触发新交接或评分。
func apply_recorded_view(view: Dictionary) -> void:
	_holder_id = int(view.get("holder_id", -1))
	_holder_hand = str(view.get("holder_hand", "right"))
	handing_off = bool(view.get("handing_off", false))
	_handoff_from_id = int(view.get("from_id", -1))
	_handoff_from_hand = str(view.get("from_hand", ""))
	_handoff_progress = clampf(float(view.get("progress", 1.0)), 0.0, 1.0)


func holder_hand_of() -> String:
	return _holder_hand


func borrow_position() -> float:
	return _borrow_x


## 🔴 历史口径（已退役）：白素贞**此刻**是否已回到小青身旁（x ≤ `TURN_POINT_X`）。
## 曾是本关完成条件，现流程不读；只在持伞期间可能为 true（见 `update()`：
## 只有 `_holder_id == BAISUZHEN_ID` 时才刷新），接伞之前恒为 false。
func is_at_home() -> bool:
	return _at_home


## —— 递伞过渡的只读读数（给显示端画「一只手把伞递给另一只手」）——
## 过渡中：伞从 `handoff_from_id/handoff_from_hand` 那只手，移到当前 `holder_id_of()/
## holder_hand_of()` 那只手；走到哪一段取 `handoff_blend()`。
## 不在过渡中（`handing_off` 为 false）时显示端只需按当前持伞人的手位画，不必读这三个。
func handoff_from_id() -> int:
	return _handoff_from_id


func handoff_from_hand() -> String:
	return _handoff_from_hand


## 过渡进度（0 = 还在原来那只手上，1 = 已到新手上），已做缓入缓出。
## 显示端在两手腕之间按这个比例插值即可，不必自己再缓动一次。
func handoff_blend() -> float:
	return _ease(_handoff_progress)


func has_event(kind: String) -> bool:
	return _count(kind) > 0


func _count(kind: String) -> int:
	var n: int = 0
	for event in _events:
		if str(event.get("kind", "")) == kind:
			n += 1
	return n


func take_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_events)
	_events.clear()
	return out


## —— 接伞 ——
## 白素贞走到交接窗口里（两只手相接的那一段）、把**一只手**抬到打伞位（90°）或更高
## （🔴 2026-10-16 用户定案：左手右手都可以，最大可以举到竖直）→ 伞自动转到那只手。
## 她**不需要**贴到许仙身上、更不需要穿过他：判据是两只手之间的距离，不是两人的接地点距离。
func _try_take(song_time_ms: int) -> void:
	var hand: String = _meeting_hand()
	if hand.is_empty():
		return
	var previous_id: int = _holder_id
	var previous_hand: String = _holder_hand
	_borrow_x = _puppet_x(BAISUZHEN_ID)
	_holder_id = BAISUZHEN_ID
	_holder_hand = hand
	# 换手当帧她必然在交接窗口里（远在历史归位阈值 0.32 之右），显式清一次保持语义自洽。
	_at_home = false
	_begin_handoff(position, hand_position(BAISUZHEN_ID, hand), previous_id, previous_hand)
	if not _take_reported:
		_emit(song_time_ms, KIND_TAKE, BAISUZHEN_ID, _baisuzhen_x())
		_take_reported = true


## —— 回到小青身旁（归位，🔴 历史口径已退役） ——
## 白素贞**持伞走到小青身旁**（x ≤ `TURN_POINT_X`）时置起。曾是本关的完成条件，
## 第四轮定案「接到伞即收关」后流程不再读它，仅按原逻辑保留（测试仍在验证）。
##
## 按当前位置直接赋值，而不是锁存：它回答的是「此刻在不在小青身旁」。
## ⚠️ 只有 `_holder_id == BAISUZHEN_ID`（她持伞）时才会被调用（见 `update()`），
## 所以接伞之前本标记恒为 false（她的开局站位 0.32 恰在阈值上，没有这层门会误置起）。
func _note_at_home() -> void:
	_at_home = _puppet_x(BAISUZHEN_ID) <= TURN_POINT_X


## —— 判据 ——
## 白素贞此刻是否站在交接窗口里（两只手相接的那一段）。只按两人的**接地点**算，
## 因此与她的手臂高低无关——换手只看位置对不对，不要求她保持抬手姿势。
func in_join_window() -> bool:
	var window: Vector2 = join_window_x(_puppet_x(XUXIAN_ID))
	var x: float = _puppet_x(BAISUZHEN_ID)
	return x >= window.x and x <= window.y


## 接伞的相接条件：位置（在交接窗口里）与手（**一只手**抬到**打伞位或更高**）两条都要。
##
## 🔴 2026-10-16 起这里不再拿许仙的**实时手高**做参考（他改成把伞举在头顶 140°）：
## 伞是**竖持**的，他握上段、她握下段，两人的手本来就不在同一高度。
## 🔴 同日用户定案放宽为两条：
##   ① **左手右手都可以**——两只手任一只到位即可换手（伞转到实际到位的那只）；
##   ② **到位 = 手高不低于打伞位**（下界仍是原来的容差带，约 82.4°），上界放开到竖直——
##      因为她的手角上限本日也放宽到 π（竖直），「举得比打伞位更高」同样握得住伞杆下段。
## 手高按幕布上的实际高度算，已把站蹲与手臂角度折进去，因此「蹲着随手一伸」仍不算入位。
func _hands_meet() -> bool:
	return not _meeting_hand().is_empty()


## 哪只手已经到位（"left" / "right"；都没到位返回 ""）。两只都到位时**优先左手**（原判据的手感）。
func _meeting_hand() -> String:
	if not in_join_window():
		return ""
	var baisuzhen: PuppetState = _puppet(BAISUZHEN_ID)
	if baisuzhen == null:
		return ""
	var contact: float = hand_height(CONTACT_HAND_ANGLE_RAD, 0.0)
	var floor: float = contact - HAND_HEIGHT_TOLERANCE
	if hand_height(baisuzhen.hand_angle.x, baisuzhen.stance) >= floor:
		return "left"
	if hand_height(baisuzhen.hand_angle.y, baisuzhen.stance) >= floor:
		return "right"
	return ""


## 位置与手高的读数，供显示端/测试读取（不参与判定）。
## `dx` 是**接地点**间距、`window` 是交手窗口、`aligned` 是接伞条件是否成立——
## 「两只手之间的实际距离」由显示端按画出来的手腕算（A→B 交接文档 6.2 节）。
## `dy` 是她**更接近打伞位的那只手**与打伞位的高度差（🔴 2026-10-16 起两只手都可接，
## 不再只看左手）；`hand` 是已经到位的那只手（"" = 都没到位）。
func alignment() -> Dictionary:
	var window: Vector2 = join_window_x(_puppet_x(XUXIAN_ID))
	var baisuzhen: PuppetState = _puppet(BAISUZHEN_ID)
	var dy: float = 0.0
	if baisuzhen != null:
		var contact: float = hand_height(CONTACT_HAND_ANGLE_RAD, 0.0)
		var left: float = absf(hand_height(baisuzhen.hand_angle.x, baisuzhen.stance) - contact)
		var right: float = absf(hand_height(baisuzhen.hand_angle.y, baisuzhen.stance) - contact)
		dy = minf(left, right)
	return {
		"dx": absf(_puppet_x(BAISUZHEN_ID) - _puppet_x(XUXIAN_ID)),
		"dy": dy,
		"window_min": window.x,
		"window_max": window.y,
		"in_window": in_join_window(),
		"aligned": _hands_meet(),
		"hand": _meeting_hand(),
	}


## —— 持伞跟随 ——
## 伞跟着持伞人的那只手走。白素贞持伞时可以自行放下左手，伞随手下落（流程表「向左走」）。
##
## 递伞过渡期间不是「沿着两个固定点插值」，而是「跟当前手位 + 一个递减的偏移」。
## 理由：交接要花 0.18 秒，这 0.18 秒里玩家还在拖动、手还在移动。若把目标点冻结在
## 交接开始那一帧的手位上，伞就会在这段时间里脱离手上的位置、悬在半路（实测过：
## 白素贞从 0.16 走到 0.10 时，伞停在 0.1307 不动）。
func _follow_hand() -> void:
	var live: Vector2 = holder_hand_position()
	if handing_off:
		position = _handoff_from + (live - _handoff_from) * _ease(_handoff_progress)
		return
	position = live


## 递伞过渡：手位不同时用短暂过渡衔接，不是瞬间跳过去。
## `start` 是交接发生那一帧伞的位置（A 内部口径，只用来判断两只手差得远不远）；
## `previous_id` / `previous_hand` 是伞**原来**在哪只手上——显示端靠它把手腕上的伞
## 从那只手送到新的那只手（A 不给绝对坐标，见 A→B 交接文档 6.2 节）。
## 两只手本来就重合时不做过渡，`handing_off` 保持 false，显示端按新持伞人直接落位。
func _begin_handoff(start: Vector2, live: Vector2, previous_id: int, previous_hand: String) -> void:
	_handoff_from_id = previous_id
	_handoff_from_hand = previous_hand
	if start.distance_to(live) < 0.0005:
		position = live
		handing_off = false
		_handoff_progress = 1.0
		return
	_handoff_from = start
	handing_off = true
	_handoff_progress = 0.0


func _advance_handoff(delta_s: float) -> void:
	if not handing_off:
		return
	_handoff_progress = minf(
		_handoff_progress + maxf(delta_s, 0.0) / maxf(HANDOFF_DURATION_S, 0.001), 1.0
	)
	if _handoff_progress >= 1.0:
		handing_off = false


## 平滑但不带弹性的收尾：交接是一只手把伞递出去，不是抛过去。
func _ease(t: float) -> float:
	var p: float = clampf(t, 0.0, 1.0)
	return p * p * (3.0 - 2.0 * p)


## 已经上报过的同一轮交接不再重复上报（补救期间反复开窗就是从这里漏出去的）。
func _emit(song_time_ms: int, kind: String, object_id: int, metric: float) -> void:
	var payload := {
		"kind": kind,
		"umbrella_id": UMBRELLA_ID,
		"umbrella": UMBRELLA_NAME,
		"holder_id": object_id,
		"holder_hand": _holder_hand,
		"handed_from": XUXIAN_ID,
		"borrow_x": _borrow_x,
		"metric": metric,
	}
	(
		_events
		. append(
			{
				"time_ms": song_time_ms,
				"kind": kind,
				"object_id": object_id,
				"cue_id": "",
				"payload": payload,
			}
		)
	)


## 接伞的判定读数用白素贞的接地点 x——交接发生的条件本来就是「她的位置对不对」，
## 用她的位置比用伞的位置更直接。
func _baisuzhen_x() -> float:
	return _puppet_x(BAISUZHEN_ID)


func _puppet_x(puppet_id: int) -> float:
	var state: PuppetState = _puppet(puppet_id)
	return state.stage_pos.x if state != null else 0.0


func _puppet(puppet_id: int) -> PuppetState:
	for state in puppets:
		if state != null and state.puppet_id == puppet_id:
			return state
	return null
