extends RefCounted
class_name UmbrellaController
## 第一关「借伞还伞」流程。依用户 2026-10-04 定案的第一关流程表实现。
##
## 这条流程是**状态机 + 两个判定落点**，与操控控制器（PuppetController）分开：
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
## 对照流程表（用户 2026-10-04 修订版）：
##   开场      许仙固定站位、右手举到 90°（打伞位）持伞；玩家控制白素贞。
##   接伞      白素贞走到许仙面前（**不必贴住他、更不必穿过他**）、把左手抬到 90°，
##             两只手碰到一起（手距与手高都在容差内）→ 伞自动转到白素贞左手。
##   向右走    接到伞后立即向右走；许仙右手一直举着；白素贞可自行放下左手，伞跟随她的手。
##   走到折返点 白素贞持伞走到**小青身旁**（舞台右侧的折返点），系统记下「已到过折返点」。
##             用户 2026-10-05 修订：原先要求走到舞台最右端（x≥0.95），实测太远、也没必要——
##             小青就站在右侧，走到她身旁即可。
##   转身返回  玩家反向拖动白素贞，她自动翻面（皮影只有正反两面）向左走回许仙身旁。
##   还伞      已经到过折返点、并走回交接位置（手距进入容差）→ 伞自动交回许仙右手。
##             不要求她重新抬手；手位较低时用短暂递伞过渡衔接。
##   收势      放下左手。
##
## 「交接位置」是**两只手相接**的那一段：两人都把手抬到 90° 时各朝对方伸出
## `HAND_REACH_X`，因此接地点相距 `2 × HAND_REACH_X` 时两只手正好碰上；
## 容差 `HAND_JOIN_TOLERANCE` 给出一个位置带（见 `join_window_x()`）。
## 用户 2026-10-04 修订的原因：原先按「两人接地点距离」判，白素贞必须几乎站到许仙身上
## 才换手（画面上两具影身叠成一团），而两只手真正相遇的位置在那条判据之外。

const PuppetStateScript := preload("res://scripts/a/puppet_state.gd")

## 交接事件类型。object_id 为**接手的那个人**：接伞记白素贞、还伞记许仙。
const KIND_TAKE: String = "umbrella_take"
const KIND_RETURN: String = "umbrella_return"

## 伞只有这一把，全局编号固定。
const UMBRELLA_ID: int = 0
const UMBRELLA_NAME: String = "umbrella_main"

## 角色分工（PuppetState.puppet_id）。与 StageDef.make_level1 的 initial 一致。
const XUXIAN_ID: int = 1     ## 许仙：固定站位、右手举伞
const BAISUZHEN_ID: int = 0  ## 白素贞：玩家控制
const XUXIAN_HAND: String = "right"
const BAISUZHEN_HAND: String = "left"

## —— 「两只手相接」判据（本流程的核心，用户 2026-10-04 定案）——
## 影人手臂抬到 90°（水平前伸）时，手在水平方向上伸出的长度 = 半身宽 + 整条手臂。
## 占位影人的几何（见 placeholder_puppet.gd）：半身宽 0.105 身高、整臂 0.31 身高，
## 站立身高 ≈ 230 px × 灯距倍率 1.07 ≈ 246 px，于是 0.415 × 246 ≈ 102 px ≈ 0.053 幕布宽。
## 两人各朝对方伸出一只手，所以**两人接地点相距 0.106 时两只手正好碰上**。
##
## ⚠️ 这个数跟着影人素材的几何走（也随灯距缩缩放而坐 ±25%）。正式素材到位后必须重新对一次，
## 并由 tests/a/test_umbrella.gd 的「判据与画面对表」断言兜住——否则会出现
## 「判据说手碰到了、画面上手还差半个身位」这种看不见的错。
const HAND_REACH_X: float = 0.053
## 手与手之间的距离容差：0.06 ≈ 一掌宽。窗口因此是「接地点相距 0.046~0.166」，
## 也就是白素贞站在许仙右侧 0.05~0.17 个幕布宽处都能交接——**不必贴住他、更不必穿过他**。
## 接伞与还伞共用同一条判据（用户定案：还伞遵循同样的逻辑）。
const HAND_JOIN_TOLERANCE: float = 0.06
## 手高容差（幕布归一化高度）。换算到手臂角度约 ±0.13 rad（≈7.6°），
## 也就是说「两只手大致齐平」才算相接，随手乱举不会被判成相接。
## 只有**接伞**要这一条：还伞不要求她重新抬手（手位低时用递伞过渡衔接）。
const HAND_HEIGHT_TOLERANCE: float = 0.04
## 折返点的左边界：玩家把白素贞拖到 x ≥ 此值即记下「已到过折返点」，之后走回来才可能还伞。
##
## 折返点取**小青身旁**（用户 2026-10-05 定案，此前要求走到舞台最右端 0.95）：小青站在
## `StageDef` 开演布景里的 x=0.86 且整关不动，0.74 让白素贞停在她左侧、留约 0.12 个身位
## （两具影身各宽约 0.026，再近画面上就会叠在一起）。
## 它与交接窗口（许仙 x=0.13 → 0.176~0.296）不重叠，因此「已经到过折返点」
## 一定意味着真的离开过交接位置往右走过。
##
## ⚠️ 落点的目标带下界**必须取这个值**，不要另写一个数：控制器置起标记的条件就是这个不等式；
## 落点带若写得比它低，会出现「拍点判命中、却没记下到过折返点」→ 走回去时还伞永远不触发。
const TURN_POINT_X: float = 0.74
## 还伞要求「从右侧向左返回」：横向变化小于这个值视为站定，不当作返回动作。
const DIRECTION_EPSILON: float = 0.0005

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
## 实际接伞时的位置（供显示端/录制参考；**还伞的判据是走回交接窗口，不是精确回到这一点**）。
var _borrow_x: float = 0.0
## 本次持伞期间是否已经走到过折返点（小青身旁）。
var _reached_turn_point: bool = false
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

## 两个落点的「本轮是否已经上报过」。它们的意义是**同一次交接只报一次**：
## 白素贞一直站在对齐位置上时，若不设这个门，每帧都会再报一次接伞；
## 还伞同理。回到许仙手上后 `_take_reported` 复位，于是第二轮的接伞仍能如实上报
## （流程允许玩家来回多走几趟，判定不该被第一次的动作永久锁死）。
var _take_reported: bool = false
var _return_reported: bool = false
## 还伞之后置起：白素贞必须先离开接伞区，才能再接一次伞。
## 防止「还伞」与「接伞」的条件在同一帧同时成立、伞每帧来回弹。
var _must_leave_zone: bool = false

## 鸭子类型时钟，只用来推进递伞过渡的时长（固定步长 = 1 / 物理帧率）。
var clock: Object = null
## 正式第一幕由剧情许可控制；旧关卡/测试默认保持原行为。
var take_allowed: bool = true
var return_allowed: bool = true

var _events: Array[Dictionary] = []
var _previous_x: float = 0.0


## 建立第一关的伞流程。其它关卡不启用：返回 false 并保持禁用状态。
## p_puppets 是 PuppetController 的影人数组，按 puppet_id 取用（不假设顺序）。
func setup(p_stage_def: StageDef, p_puppets: Array) -> bool:
	_events.clear()
	_take_reported = false
	_return_reported = false
	_must_leave_zone = false
	_reached_turn_point = false
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
	_previous_x = _puppet_x(BAISUZHEN_ID)
	position = hand_position(XUXIAN_ID, XUXIAN_HAND)
	return true


## 本关是否启用借伞还伞流程（只有第一关）。
func is_enabled() -> bool:
	return stage_id == StageDef.LEVEL1_ID and _puppet(BAISUZHEN_ID) != null \
		and _puppet(XUXIAN_ID) != null


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
		# 顺序要紧：先按此刻的位置更新「已到过左端」，再判还伞。
		# 反过来的话，白素贞一帧内从左端挪回接伞位置时，还伞会读到上一帧的
		# 「到过左端」，而她此刻明明还在接伞区右侧之外——还伞因此会提前在左端触发。
		_note_turn_point()
		if return_allowed:
			_try_return(song_time_ms)
	_follow_hand()
	_previous_x = _puppet_x(BAISUZHEN_ID)


## 鸭子类型时钟，用于递伞过渡的推进；只需 get_physics_ticks_per_second()。
func set_clock(p_clock: Object) -> void:
	clock = p_clock


## —— 交接窗口 ——
## 白素贞的接地点 x 落在 [min, max] 之内即「两只手相接」。
## 由「两人都把手抬到 90°」推出：各伸出 `HAND_REACH_X`，相距两倍时两只手正好碰上，
## 容差 `HAND_JOIN_TOLERANCE` 给出一段带。`xuxian_x` 是许仙的接地点 x。
##
## 刻意**按固定姿势**算一次，不按白素贞当下的手臂角度实时重算：她持伞往回走时可以自行
## 放下左手（伞跟着手落），若窗口随手臂高低移动，还伞的落点就会跟着漂，玩家没法瞄准。
##
## 落点数据（StageDef）与运行时判定（本控制器）共用这一个函数，免得拍点与判定漂开。
static func join_window_x(xuxian_x: float) -> Vector2:
	var contact_x: float = xuxian_x + 2.0 * HAND_REACH_X
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
	var angle: float = clampf(hand_angle,
		PuppetStateScript.HAND_ANGLE_MIN, PuppetStateScript.HAND_ANGLE_MAX)
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


func holder_hand_of() -> String:
	return _holder_hand


func borrow_position() -> float:
	return _borrow_x


func has_reached_turn_point() -> bool:
	return _reached_turn_point


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
## 白素贞走到交接窗口里（两只手相接的那一段）、把左手抬到打伞位（90°）→ 伞自动转到她左手。
## 她**不需要**贴到许仙身上、更不需要穿过他：判据是两只手之间的距离，不是两人的接地点距离。
func _try_take(song_time_ms: int) -> void:
	# 还伞之后必须先离开交接窗口，才能再接一次。
	# 否则「还伞」与「接伞」的条件在她站着不动的同一帧里同时成立，伞会每帧在两人之间来回弹
	# （还伞 → 仍然相接 → 又接走 → 又还 → …）。这与「走到折返点」用同一套纪律：
	# 一个动作要真的做过一次位移才算发生过，不能靠在原地反复满足条件刷出来。
	if _must_leave_zone:
		if in_join_window():
			return
		_must_leave_zone = false
	if not _hands_meet():
		return
	var previous_id: int = _holder_id
	var previous_hand: String = _holder_hand
	_borrow_x = _puppet_x(BAISUZHEN_ID)
	_holder_id = BAISUZHEN_ID
	_holder_hand = BAISUZHEN_HAND
	_reached_turn_point = false
	_begin_handoff(position, hand_position(BAISUZHEN_ID, BAISUZHEN_HAND),
		previous_id, previous_hand)
	if not _take_reported:
		_emit(song_time_ms, KIND_TAKE, BAISUZHEN_ID, _baisuzhen_x())
		_take_reported = true
	_return_reported = false


## —— 走到折返点（小青身旁）——
## 白素贞**持伞走到小青身旁**（x ≥ TURN_POINT_X）时，系统记下「已到过折返点」。
## 这是还伞的前置条件：没有真的往右走到过折返点，走回许仙身旁不会自动交伞
## （否则她接到伞站在原地不动就会被判成「已经回来」，伞来回弹个不停）。
##
## 标记「置起」与「清掉」都不能只看位置，必须同时看**方向**（规则与原先成镜像）：
##   置起：x ≥ TURN_POINT_X（真的走到了小青身旁）
##   清掉：**又往更右边走在交接窗口之外**（x 在增大，且此刻不在窗口里）
##
## 「又往更右边走」正是重新走一趟「走到折返点 → 返回」的开头；向左走回、站着不动都不作废。
func _note_turn_point() -> void:
	var x: float = _puppet_x(BAISUZHEN_ID)
	if x >= TURN_POINT_X:
		_reached_turn_point = true
		return
	if not in_join_window() and x > _previous_x:
		_reached_turn_point = false


## —— 还伞 ——
## 三个条件同时成立才自动交回：①本次持伞期间到过折返点；②此刻走回交接窗口（两只手相接的位置带）；
## ③正在从右侧向左返回（白素贞在向左走）。**不要求她重新抬手**，也不要求单独做一次转身——
## 影人只有正反两面，拖动方向一变就自动翻面（`facing_turn`）。
func _try_return(song_time_ms: int) -> void:
	if not _reached_turn_point:
		return
	if not in_join_window():
		return
	var x: float = _puppet_x(BAISUZHEN_ID)
	if _previous_x - x <= DIRECTION_EPSILON:
		return
	var previous_id: int = _holder_id
	var previous_hand: String = _holder_hand
	_holder_id = XUXIAN_ID
	_holder_hand = XUXIAN_HAND
	_reached_turn_point = false
	_begin_handoff(position, hand_position(XUXIAN_ID, XUXIAN_HAND),
		previous_id, previous_hand)
	_must_leave_zone = true
	if not _return_reported:
		_emit(song_time_ms, KIND_RETURN, XUXIAN_ID, x)
		_return_reported = true
	_take_reported = false


## —— 判据 ——
## 白素贞此刻是否站在交接窗口里（两只手相接的那一段）。只按两人的**接地点**算，
## 因此与她的手臂高低无关——还伞因此不要求她重新抬手（见 `join_window_x` 的说明）。
func in_join_window() -> bool:
	var window: Vector2 = join_window_x(_puppet_x(XUXIAN_ID))
	var x: float = _puppet_x(BAISUZHEN_ID)
	return x >= window.x and x <= window.y


## 接伞的相接条件：位置（在交接窗口里）与手高（两只手齐平）两条都要。
## 手高按幕布上的实际高度算——它已经把站蹲与手臂角度都折进去了，
## 因此「蹲着随手一伸」不会与站着的手齐平，而「抬到打伞位 90°」正好齐平。
func _hands_meet() -> bool:
	if not in_join_window():
		return false
	var baisuzhen: PuppetState = _puppet(BAISUZHEN_ID)
	var xuxian: PuppetState = _puppet(XUXIAN_ID)
	if baisuzhen == null or xuxian == null:
		return false
	var left: float = hand_height(baisuzhen.hand_angle.x, baisuzhen.stance)
	var right: float = hand_height(xuxian.hand_angle.y, xuxian.stance)
	return absf(left - right) <= HAND_HEIGHT_TOLERANCE


## 位置与手高的读数，供显示端/测试读取（不参与判定）。
## `dx` 是**接地点**间距、`window` 是交手窗口、`aligned` 是接伞条件是否成立——
## 「两只手之间的实际距离」由显示端按画出来的手腕算（A→B 交接文档 6.2 节）。
func alignment() -> Dictionary:
	var window: Vector2 = join_window_x(_puppet_x(XUXIAN_ID))
	var baisuzhen: PuppetState = _puppet(BAISUZHEN_ID)
	var xuxian: PuppetState = _puppet(XUXIAN_ID)
	var dy: float = 0.0
	if baisuzhen != null and xuxian != null:
		dy = absf(hand_height(baisuzhen.hand_angle.x, baisuzhen.stance)
			- hand_height(xuxian.hand_angle.y, xuxian.stance))
	return {
		"dx": absf(_puppet_x(BAISUZHEN_ID) - _puppet_x(XUXIAN_ID)),
		"dy": dy,
		"window_min": window.x,
		"window_max": window.y,
		"in_window": in_join_window(),
		"aligned": _hands_meet(),
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
func _begin_handoff(start: Vector2, live: Vector2, previous_id: int,
		previous_hand: String) -> void:
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
	_handoff_progress = minf(_handoff_progress
		+ maxf(delta_s, 0.0) / maxf(HANDOFF_DURATION_S, 0.001), 1.0)
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
		"handed_from": XUXIAN_ID if kind == KIND_TAKE else BAISUZHEN_ID,
		"borrow_x": _borrow_x,
		"metric": metric,
	}
	_events.append({
		"time_ms": song_time_ms,
		"kind": kind,
		"object_id": object_id,
		"cue_id": "",
		"payload": payload,
	})


## 接伞与还伞的判定读数都用白素贞的接地点 x——
## 交接发生的条件本来就是「她的位置对不对」，用她的位置比用伞的位置更直接。
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
