extends RefCounted
class_name PuppetController
## A 范围唯一操控实现：胸签拖动、站蹲、渐进转身、双手控制。
## 单向数据流（TECH_DESIGN.md 2.3）：本控制器先改 PuppetState，再把 TimedEvent 写入队列；
## B 的显示与 C 的录制在同一帧读状态，因此一定读到改动后的值。
## 事件契约见 docs/superpowers/plans/2026-10-03-level1-a.md 第 1.3 节。

const PuppetStateScript := preload("res://scripts/a/puppet_state.gd")

## 虚拟舞台像素尺寸。固定为 1920x1080，不使用 viewport 尺寸，
## 这样窗口缩放不会改变操控手感。
const STAGE_PIXEL_SIZE: Vector2 = Vector2(1920.0, 1080.0)

const STANCE_SPEED_PER_S: float = 1.5    ## 站蹲速度（stance/s），站→蹲约 0.67 s
const TURN_DURATION_S: float = 0.25      ## 转身过渡时长；满足「不能瞬间翻面」
const TURN_SPEED_PER_S: float = 1.0 / TURN_DURATION_S
const HAND_SPEED_RAD_PER_S: float = 2.0  ## 抬手/落手速度
const HAND_ANGLE_INITIAL: float = 0.3    ## 双手初始角（弧度），抬落两向都留余量
const CHEST_TAG_RADIUS_PX: float = 90.0  ## 胸签拖动热区（以虚拟舞台像素计）
const FACING_DEADZONE_PX: float = 2.0    ## 横向位移小于此值不改变转身目标
const STANCE_EPSILON: float = 0.000001   ## 站蹲「是否仍在变化」的比较阈值

## 事件类型。cue_id 非判定事件一律为空字符串。
const KIND_POSE_STANCE: String = "pose_stance"
const KIND_FACING_TURN: String = "facing_turn"
const KIND_HAND_MOTION: String = "hand_motion"
const KIND_DRAG_BEGIN: String = "drag_begin"
const KIND_DRAG_END: String = "drag_end"
const KIND_HOOK: String = "puppet_hook"
const KIND_TAKE_BACK: String = "puppet_take_back"
const KIND_HEAD_SWAP: String = "head_swap"

## 头架上的备用头槽位数。按键 1/2/3 与 0/1/2 一一对应（PRD 第 4.1、4.2 节）。
const HEAD_RACK_SLOTS: int = 3

## 挂钩槽位数（PRD 第 4.2 节：两个可见挂钩）。
const HOOK_SLOTS: int = 2

## 鸭子类型时钟：只需提供 get_song_time_ms() -> int。
## 切片 1 用 FrameClock / TestClock，切片 2 起换成 MusicClock，本控制器不改。
var clock: Object = null

var puppets: Array = []                  ## Array[PuppetState]，下标即 puppet_id
var controlled_id: int = -1              ## 当前唯一受控影人；-1 表示无人受控
## 头架上每个槽位当前放着哪个头。与 puppets 的 head_id 合起来，
## 六个头各出现恰好一次（不变量 2），换头因此只是「交换」而不是复制。
var rack_heads: Array = []

var _events: Array[Dictionary] = []      ## 待取走的事件队列
var _input_map: Dictionary = {}          ## 本帧生效的输入快照
var _drag_active: bool = false
var _drag_puppet_id: int = -1
var _drag_accum_px: Vector2 = Vector2.ZERO
var _facing_target: float = 0.0          ## 0.0 表示保持当前朝向，+/-1.0 表示转身目标
## 只在运动方向变化与停稳时发事件，避免每帧噪声撑大 C 的录制
var _stance_moving: bool = false
var _stance_last_emitted: float = 0.0
var _turn_dir: int = 0
var _hand_dir: Vector2i = Vector2i.ZERO


func _init() -> void:
	set_input_map({})


## 建立 puppet_count 个影人，默认 0 号受控。头 0-2 分配给三个影人，3-5 留给头架。
func setup(puppet_count: int = 3) -> void:
	if puppet_count < 1:
		push_error("PuppetController.setup 收到非法 puppet_count：%d" % puppet_count)
		puppet_count = 1
	puppets.clear()
	_events.clear()
	_drag_active = false
	_drag_puppet_id = -1
	_drag_accum_px = Vector2.ZERO
	_facing_target = 0.0
	_stance_moving = false
	_stance_last_emitted = 0.0
	_turn_dir = 0
	_hand_dir = Vector2i.ZERO
	for i in puppet_count:
		var state: PuppetState = PuppetStateScript.new(i)
		state.stage_pos = Vector2(0.5, 0.5)
		state.stance = 0.0
		state.facing = 0.0
		state.turn_progress = 0.0
		state.hand_angle = Vector2(HAND_ANGLE_INITIAL, HAND_ANGLE_INITIAL)
		state.head_id = i                      ## 前三个头分配给三个影人
		state.hook_slot = PuppetStateScript.HOOK_SLOT_NONE
		state.is_controlled = false
		puppets.append(state)
	controlled_id = 0
	puppets[0].is_controlled = true
	# 头架三个槽位放余下的三个头，保证「六个头各出现恰好一次」从开局就成立
	rack_heads.clear()
	for slot in HEAD_RACK_SLOTS:
		rack_heads.append(puppet_count + slot)


func get_puppet(puppet_id: int) -> PuppetState:
	if puppet_id < 0 or puppet_id >= puppets.size():
		push_error("PuppetController.get_puppet 收到越界 puppet_id：%d" % puppet_id)
		return null
	return puppets[puppet_id]


func get_controlled() -> PuppetState:
	if controlled_id == -1:
		return null
	return get_puppet(controlled_id)


## 找一个空闲的挂钩槽位；返回 -1 表示两个槽都被占着。
##
## 之所以做成公开方法，是为了让 HUD 能按**实际可用性**提示玩家：挂钩满的时候
## 仍然写着「空格 = 挂起这个影人」，就是说了做不到（第一关开局两个影人分别挂在
## 两个钩上，正是这种情况）。提示与挂起判定共用这一处查找，不会各自漂移。
func find_free_hook_slot() -> int:
	for candidate in HOOK_SLOTS:
		var occupied: bool = false
		for puppet in puppets:
			if puppet.hook_slot == candidate:
				occupied = true
				break
		if not occupied:
			return candidate
	return -1


func hook_current() -> bool:
	var state: PuppetState = get_controlled()
	if state == null:
		return false
	var slot: int = find_free_hook_slot()
	if slot == -1:
		return false
	end_drag()
	state.hook_slot = slot
	state.is_controlled = false
	controlled_id = -1
	set_input_map({})
	_emit(KIND_HOOK, state.puppet_id, {"hook_slot": slot})
	return true


func take_back(puppet_id: int) -> bool:
	if controlled_id != -1 or puppet_id < 0 or puppet_id >= puppets.size():
		return false
	var state: PuppetState = puppets[puppet_id]
	if state.hook_slot == PuppetStateScript.HOOK_SLOT_NONE:
		return false
	var old_slot: int = state.hook_slot
	state.hook_slot = PuppetStateScript.HOOK_SLOT_NONE
	state.is_controlled = true
	controlled_id = puppet_id
	_emit(KIND_TAKE_BACK, puppet_id, {"hook_slot": old_slot})
	return true


## 与备用头架第 slot 个位置交换头部（slot 0/1/2 对应按键 1/2/3）。
## PRD 第 4.2 节：换头只作用于当前受控影人；换下的头留在原位置，
## 因此这里做的是**交换**——六个头合起来仍然各出现恰好一次，不会复制头部道具。
func swap_head(slot: int, puppet_id: int = -1) -> bool:
	if rack_heads.is_empty() or slot < 0 or slot >= rack_heads.size():
		return false
	var target: PuppetState = get_controlled() if puppet_id == -1 else get_puppet(puppet_id)
	if target == null:
		return false
	var incoming: int = rack_heads[slot]
	if incoming == PuppetStateScript.HEAD_ID_NONE:
		return false
	var outgoing: int = target.head_id
	target.head_id = incoming
	rack_heads[slot] = outgoing
	_emit(KIND_HEAD_SWAP, target.puppet_id,
		{"slot": slot, "head_from": outgoing, "head_to": incoming})
	return true


## 头架槽位当前放着的头，供显示端画备用头架。
func head_on_rack(slot: int) -> int:
	if slot < 0 or slot >= rack_heads.size():
		return PuppetStateScript.HEAD_ID_NONE
	return int(rack_heads[slot])


## 每帧一次的唯一步进入口。
## 顺序固定：应用拖动 → 应用双手 → 应用转身 → clamp → 事件早已在各自步骤内入队。
## 保证同一帧内状态先变、事件后到。
func tick(delta: float) -> void:
	var controlled: PuppetState = get_controlled()
	if controlled == null:
		return
	_apply_drag(controlled)
	_settle_stance(controlled)
	_apply_hands(controlled, delta)
	_apply_facing(controlled, delta)
	controlled.clamp_continuous()


## 鼠标左键按下：命中当前受控影人的胸签才进入拖动。
func begin_drag(puppet_id: int, mouse_pos: Vector2) -> bool:
	var target: PuppetState = get_puppet(puppet_id)
	if target == null:
		return false
	if not target.is_controlled:
		return false
	var chest_tag_px := Vector2(
		target.stage_pos.x * STAGE_PIXEL_SIZE.x,
		target.stage_pos.y * STAGE_PIXEL_SIZE.y - CHEST_TAG_RADIUS_PX * 0.5)
	if mouse_pos.distance_to(chest_tag_px) > CHEST_TAG_RADIUS_PX:
		return false
	_drag_active = true
	_drag_puppet_id = puppet_id
	_drag_accum_px = Vector2.ZERO
	_emit(KIND_DRAG_BEGIN, puppet_id, {"dragging": true})
	return true


## 拖动中：只累积位移，真正的状态改变留到 tick()，
## 保证「拖动时维持双手已有姿势」且时序可预测。
func drag_to(mouse_pos: Vector2) -> void:
	if not _drag_active:
		return
	_drag_accum_px += mouse_pos


func end_drag() -> void:
	if not _drag_active:
		return
	var who: int = _drag_puppet_id
	var target: PuppetState = get_puppet(who)
	if target != null:
		_apply_drag(target)
		_settle_stance(target)
	_drag_active = false
	_drag_puppet_id = -1
	_drag_accum_px = Vector2.ZERO
	_emit(KIND_DRAG_END, who, {"dragging": false})


func is_dragging() -> bool:
	return _drag_active


## 设置本帧的输入快照。整体替换而非逐键累加，避免漏掉「松开」。
func set_input_map(input_map: Dictionary) -> void:
	_input_map = {
		"left_raise": bool(input_map.get("left_raise", false)),
		"left_lower": bool(input_map.get("left_lower", false)),
		"right_raise": bool(input_map.get("right_raise", false)),
		"right_lower": bool(input_map.get("right_lower", false)),
		"both_raise": bool(input_map.get("both_raise", false)),
		"both_lower": bool(input_map.get("both_lower", false)),
	}


func get_input_map() -> Dictionary:
	return _input_map.duplicate()


## C 的 Recorder 每帧调用一次；取走即清空，不会重复记录。
func take_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_events)
	_events.clear()
	return out


## 胸签拖动：横向改 stage_pos.x，纵向改 stance（向下拖 = 蹲下）。
## 横向位移超过死区时设定转身目标，转身在 _apply_facing 中平滑推进。
func _apply_drag(controlled: PuppetState) -> void:
	if _drag_accum_px == Vector2.ZERO:
		return
	if not _drag_active or _drag_puppet_id != controlled.puppet_id:
		_drag_accum_px = Vector2.ZERO
		return
	var dpx: Vector2 = _drag_accum_px
	_drag_accum_px = Vector2.ZERO

	controlled.stage_pos.x = clampf(
		controlled.stage_pos.x + dpx.x / STAGE_PIXEL_SIZE.x,
		PuppetStateScript.STAGE_POS_MIN, PuppetStateScript.STAGE_POS_MAX)

	var before_stance: float = controlled.stance
	controlled.stance = clampf(
		controlled.stance + dpx.y / STAGE_PIXEL_SIZE.y,
		PuppetStateScript.STANCE_MIN, PuppetStateScript.STANCE_MAX)
	if not is_equal_approx(before_stance, controlled.stance):
		if not _stance_moving:
			_stance_moving = true
			_emit(KIND_POSE_STANCE, controlled.puppet_id, {"stance": controlled.stance})
		# 记下本帧已上报的值，停稳时才不会把同一帧的值重复发一次
		_stance_last_emitted = controlled.stance

	if absf(dpx.x) > FACING_DEADZONE_PX:
		_facing_target = 1.0 if dpx.x > 0.0 else -1.0


func _apply_hands(controlled: PuppetState, delta: float) -> void:
	var step: float = HAND_SPEED_RAD_PER_S * maxf(delta, 0.0)
	var left_dir: int = _net_dir(_input_map["left_raise"], _input_map["left_lower"],
		_input_map["both_raise"], _input_map["both_lower"])
	var right_dir: int = _net_dir(_input_map["right_raise"], _input_map["right_lower"],
		_input_map["both_raise"], _input_map["both_lower"])
	if left_dir != 0:
		controlled.hand_angle.x += float(left_dir) * step
	if right_dir != 0:
		controlled.hand_angle.y += float(right_dir) * step
	controlled.hand_angle.x = clampf(controlled.hand_angle.x,
		PuppetStateScript.HAND_ANGLE_MIN, PuppetStateScript.HAND_ANGLE_MAX)
	controlled.hand_angle.y = clampf(controlled.hand_angle.y,
		PuppetStateScript.HAND_ANGLE_MIN, PuppetStateScript.HAND_ANGLE_MAX)
	_emit_hand_if_changed(controlled, left_dir, right_dir)


## 转身平滑推进；_facing_target 为 0.0 时保持当前朝向。
func _apply_facing(controlled: PuppetState, delta: float) -> void:
	if _facing_target == 0.0:
		return
	var next: float = move_toward(controlled.facing, _facing_target,
		TURN_SPEED_PER_S * maxf(delta, 0.0))
	controlled.facing = clampf(next,
		PuppetStateScript.FACING_MIN, PuppetStateScript.FACING_MAX)
	controlled.turn_progress = absf(controlled.facing)
	var dir: int = 0
	if not is_equal_approx(controlled.facing, _facing_target):
		dir = 1 if _facing_target > 0.0 else -1
	if dir != _turn_dir:
		_turn_dir = dir
		_emit(KIND_FACING_TURN, controlled.puppet_id,
			{"from": controlled.facing, "to": _facing_target})


## 单只手的净方向：抬为 +1、落为 -1、冲突或松开为 0（保持当前姿势）。
func _net_dir(hand_raise: bool, hand_lower: bool, both_raise: bool, both_lower: bool) -> int:
	var dir: int = int(hand_raise) - int(hand_lower) + int(both_raise) - int(both_lower)
	return clampi(dir, -1, 1)


func _emit_hand_if_changed(controlled: PuppetState, left_dir: int, right_dir: int) -> void:
	var dir := Vector2i(left_dir, right_dir)
	if dir == _hand_dir:
		return
	if dir.x != _hand_dir.x:
		_emit(KIND_HAND_MOTION, controlled.puppet_id,
			{"hand": "left", "dir": left_dir, "angle": controlled.hand_angle.x})
	if dir.y != _hand_dir.y:
		_emit(KIND_HAND_MOTION, controlled.puppet_id,
			{"hand": "right", "dir": right_dir, "angle": controlled.hand_angle.y})
	_hand_dir = dir


## 站蹲停稳时补发一次最终值，保证 C 录到的 stance 变化有明确收尾。
func _settle_stance(controlled: PuppetState) -> void:
	if not _stance_moving:
		return
	if not is_equal_approx(controlled.stance, _stance_last_emitted):
		_emit(KIND_POSE_STANCE, controlled.puppet_id, {"stance": controlled.stance})
	_stance_moving = false
	_stance_last_emitted = controlled.stance


func _emit(kind: String, object_id: int, payload_extra: Dictionary) -> void:
	var payload := {"kind": kind}
	payload.merge(payload_extra, true)
	var stamp: int = 0
	if clock != null:
		stamp = int(clock.call("get_song_time_ms"))
	_events.append({
		"time_ms": stamp,
		"kind": kind,
		"object_id": object_id,
		"cue_id": "",
		"payload": payload,
	})
