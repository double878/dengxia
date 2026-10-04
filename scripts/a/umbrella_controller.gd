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
## 对照流程表：
##   开场      许仙固定站位、右手举起持伞；玩家控制白素贞。
##   接伞      白素贞走到许仙身旁、左手与许仙右手等高且在容差内 → 伞自动转到白素贞左手。
##   向左走    白素贞持伞向左移动；许仙右手一直举着；白素贞可自行放下左手，伞跟随她的手。
##   到达最左边 白素贞进入舞台最左侧的可达区域，系统记下「已到过左端」。
##   向右返回  玩家反向拖动白素贞，向右走回许仙身旁。
##   还伞      已经到过左端、并从左侧返回实际接伞位置 → 伞自动交回许仙右手。
##             不要求再转身，也不要求白素贞重新抬手；手位较低时用短暂递伞过渡衔接。

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

## 接伞位置容差：白素贞的接地点要走到许仙身旁多近才算「身旁」。
## 0.06 = 幕布宽度的 6%，约半个影人身宽；再宽会让人在明显错位处凭空拿到伞。
const POSITION_TOLERANCE: float = 0.06
## 还伞位置容差：要回到**实际接伞位置**多近才算「返回接伞的位置」。
##
## 刻意比 POSITION_TOLERANCE 紧一倍。流程表两个动作的措辞是不同的：
## 接伞是「走到许仙身旁」（一个区域），还伞是「返回实际接伞时的位置」（那个点）。
## 共用一个 0.06 会实测出问题：实测接伞点是 0.16，白素贞走到 0.10 时
## |0.10 − 0.16| 恰好等于 0.06、被判成「回到了接伞位置」而提前还伞。
const RETURN_TOLERANCE: float = 0.03
## 手高容差（幕布归一化高度）。换算到手臂角度约 ±0.13 rad（≈7.6°），
## 也就是说「两只手大致齐平」才算对齐，随手乱举不会被判成对齐。
const HAND_HEIGHT_TOLERANCE: float = 0.04
## 「舞台最左侧的可达区域」的右边界。玩家把白素贞拖到 x ≤ 此值即记下「已到过左端」。
## 0.05 与接伞区（许仙 x=0.13 ± 0.06 → 0.07~0.19）不重叠，因此「已经到过左端」
## 一定意味着真的离开过接伞位置往左走过。
const LEFT_EDGE_X: float = 0.05
## 还伞要求「从左侧返回」：横向变化小于这个值视为站定，不当作返回动作。
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
## 实际接伞时的位置，还伞要求回到这里。
var _borrow_x: float = 0.0
## 本次持伞期间是否已经到达过舞台最左侧的可达区域。
var _reached_left_edge: bool = false
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

var _events: Array[Dictionary] = []
var _previous_x: float = 0.0


## 建立第一关的伞流程。其它关卡不启用：返回 false 并保持禁用状态。
## p_puppets 是 PuppetController 的影人数组，按 puppet_id 取用（不假设顺序）。
func setup(p_stage_def: StageDef, p_puppets: Array) -> bool:
	_events.clear()
	_take_reported = false
	_return_reported = false
	_must_leave_zone = false
	_reached_left_edge = false
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
	if _holder_id == XUXIAN_ID:
		_try_take(song_time_ms)
	elif _holder_id == BAISUZHEN_ID:
		# 顺序要紧：先按此刻的位置更新「已到过左端」，再判还伞。
		# 反过来的话，白素贞一帧内从左端挪回接伞位置时，还伞会读到上一帧的
		# 「到过左端」，而她此刻明明还在接伞区右侧之外——还伞因此会提前在左端触发。
		_note_left_edge()
		_try_return(song_time_ms)
	_follow_hand()
	_previous_x = _puppet_x(BAISUZHEN_ID)


## 鸭子类型时钟，用于递伞过渡的推进；只需 get_physics_ticks_per_second()。
func set_clock(p_clock: Object) -> void:
	clock = p_clock


## 手举到某个角度时，手在幕布上的归一化高度。
##
## 手角口径（PuppetState.hand_angle）：0 = 手臂自然垂下、π = 举过头顶。
## 高度 = 肩高 − 手臂在竖直方向上的投影，投影是 `ARM_LENGTH · cos(角度)`：
##   垂下（0）    → cos = +1 → 0.68 − 0.30 = 0.38（最低）
##   平伸（π/2）  → cos =  0 → 0.68        （齐肩）
##   举顶（π）    → cos = −1 → 0.68 + 0.30 = 0.98（最高）
## 用 `sin` 会得到「垂下手最高、举起手最低」的反向结果——两只手角度相同时
## 两处符号错误会互相抵消，于是「对齐」看起来还能成立，但单看一只手的高度就是错的。
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


func has_reached_left_edge() -> bool:
	return _reached_left_edge


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
## 白素贞走到许仙身旁，且左手与许仙右手等高 → 伞自动转到白素贞左手。
## 接伞位置被记下，还伞要求回到这里（而不是「回到许仙身旁的任意一点」）。
func _try_take(song_time_ms: int) -> void:
	# 还伞之后必须先离开接伞区，才能再接一次。
	# 否则「还伞」与「接伞」的条件在她站着不动的同一帧里同时成立，伞会每帧在两人之间来回弹
	# （还伞 → 仍然对齐 → 又接走 → 又还 → …）。这与「到达最左边」用同一套纪律：
	# 一个动作要真的做过一次位移才算发生过，不能靠在原地反复满足条件刷出来。
	if _must_leave_zone:
		if absf(_puppet_x(BAISUZHEN_ID) - _borrow_x) <= POSITION_TOLERANCE:
			return
		_must_leave_zone = false
	if not _hands_aligned():
		return
	var previous_id: int = _holder_id
	var previous_hand: String = _holder_hand
	_borrow_x = _puppet_x(BAISUZHEN_ID)
	_holder_id = BAISUZHEN_ID
	_holder_hand = BAISUZHEN_HAND
	_reached_left_edge = false
	_begin_handoff(position, hand_position(BAISUZHEN_ID, BAISUZHEN_HAND),
		previous_id, previous_hand)
	if not _take_reported:
		_emit(song_time_ms, KIND_TAKE, BAISUZHEN_ID, _baisuzhen_x())
		_take_reported = true
	_return_reported = false


## —— 到达最左边 ——
## 白素贞**持伞走进舞台最左侧的可达区域**时，系统记下「已到过左端」。
## 这是还伞的前置条件：没有真的往左走到过左端，回到许仙身旁不会自动交伞。
##
## 标记「置起」与「清掉」都不能只看位置，必须同时看**方向**：
##   置起：x ≤ LEFT_EDGE_X（真的走到了最左边）
##   清掉：**往左走在接伞位置左侧**（x < borrow − 容差 且 x 在减小）
##
## 两个方向条件都是实测逼出来的，缺一个就会出问题：
## 1. 清空若「只看位置在接伞位置左侧」（第一版），会把她**持伞向右回程**时
##    经过的那段左侧区间也算成「重新往左走」，标记在半路被清掉——她这一趟再也
##    走不到最左端，于是标记永远回不来，还伞永远触发不了（实测就卡在这里）。
## 2. 清空若「只看走到接伞位置右侧」（更早的一版），会让她从最左端向右返回时
##    必然先经过的右侧区间把标记清掉，同样是还伞永远触发不了。
##
## 于是正确的语义是：只有「又往更左边走」才作废上一趟——那正是重新走一趟
## 「到最左端 → 返回」的开头；向右返回、站着不动都不作废。
func _note_left_edge() -> void:
	var x: float = _puppet_x(BAISUZHEN_ID)
	if x <= LEFT_EDGE_X:
		_reached_left_edge = true
		return
	if x < _borrow_x - RETURN_TOLERANCE and x < _previous_x:
		_reached_left_edge = false


## —— 还伞 ——
## 三个条件同时成立才自动交回：①本次持伞期间到过左端；②此刻回到接伞位置；
## ③正在从左侧向右返回（反向拖动）。不要求转身，也不要求重新抬手。
func _try_return(song_time_ms: int) -> void:
	if not _reached_left_edge:
		return
	var x: float = _puppet_x(BAISUZHEN_ID)
	if absf(x - _borrow_x) > RETURN_TOLERANCE:
		return
	if x - _previous_x <= DIRECTION_EPSILON:
		return
	var previous_id: int = _holder_id
	var previous_hand: String = _holder_hand
	_holder_id = XUXIAN_ID
	_holder_hand = XUXIAN_HAND
	_reached_left_edge = false
	_begin_handoff(position, hand_position(XUXIAN_ID, XUXIAN_HAND),
		previous_id, previous_hand)
	_must_leave_zone = true
	if not _return_reported:
		_emit(song_time_ms, KIND_RETURN, XUXIAN_ID, x)
		_return_reported = true
	_take_reported = false


## 接伞的对齐条件：两条都要。位置按接地点算，手高按幕布上的实际高度算——
## 手高已经把站蹲与手臂角度都折进去了，因此「蹲着随手一伸」不会与站着手齐平。
func _hands_aligned() -> bool:
	var baisuzhen: PuppetState = _puppet(BAISUZHEN_ID)
	var xuxian: PuppetState = _puppet(XUXIAN_ID)
	if absf(baisuzhen.stage_pos.x - xuxian.stage_pos.x) > POSITION_TOLERANCE:
		return false
	var left: float = hand_height(baisuzhen.hand_angle.x, baisuzhen.stance)
	var right: float = hand_height(xuxian.hand_angle.y, xuxian.stance)
	return absf(left - right) <= HAND_HEIGHT_TOLERANCE


## 位置与手高的对齐读数，供显示端/测试读取（不参与判定）。
func alignment() -> Dictionary:
	var baisuzhen: PuppetState = _puppet(BAISUZHEN_ID)
	var xuxian: PuppetState = _puppet(XUXIAN_ID)
	return {
		"dx": absf(baisuzhen.stage_pos.x - xuxian.stage_pos.x),
		"dy": absf(hand_height(baisuzhen.hand_angle.x, baisuzhen.stance)
			- hand_height(xuxian.hand_angle.y, xuxian.stance)),
		"aligned": _hands_aligned(),
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
