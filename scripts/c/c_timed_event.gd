extends RefCounted
class_name CTimedEvent
## 一次演出中的离散事件。字段由 A 端冻结（A 侧 StageDirector 已把
## 控制器、判定、补救三条队列并成一条流，Recorder 每帧取一次）。
##
## 本类只做三件事：校验字段、按 (time_ms, seq) 有序插入、供回放端原样取用。
## 明确不做：不解释 payload 含义、不推导后果、不合并同刻事件。
##
## 忠实性约束（PRD 5.2.3，回放端不得违反）：
## - cue_fire 与 cue_hit/cue_miss 是分开的两条。错拍时动作照常发生，
##   所以既有 cue_fire 也有 cue_miss。回放要能看到「动作做了」这个事实。
## - remedy_success 不删除此前的 cue_miss。原失误仍计入该幕表现。
##   replay() 返回的是原事件流，不做任何过滤。
##
## 用 preload 常量而不是 class_name 引用 CSnapshot：godot --headless --script
## 不读全局类名缓存，直接写 CSnapshot.PUPPET_COUNT 会报 "Could not find type"。
const CSnapshotScript := preload("res://scripts/c/c_snapshot.gd")

## 事件类型。与 A 端产出的 kind 字符串逐一对应，改动需同步 A 端。
const KIND_DRAG_BEGIN: StringName = &"drag_begin"
const KIND_DRAG_END: StringName = &"drag_end"
const KIND_POSE_STANCE: StringName = &"pose_stance"
const KIND_FACING_TURN: StringName = &"facing_turn"
const KIND_HAND_MOTION: StringName = &"hand_motion"
const KIND_CUE_HINT: StringName = &"cue_hint"
const KIND_CUE_FIRE: StringName = &"cue_fire"
const KIND_CUE_HIT: StringName = &"cue_hit"
const KIND_CUE_MISS: StringName = &"cue_miss"
const KIND_REMEDY_OPEN: StringName = &"remedy_open"
const KIND_REMEDY_SUCCESS: StringName = &"remedy_success"
const KIND_REMEDY_TIMEOUT: StringName = &"remedy_timeout"
const KIND_REMEDY_SHOW: StringName = &"remedy_show"
const KIND_REMEDY_HIDE: StringName = &"remedy_hide"
const KIND_STAGE_START: StringName = &"stage_start"
const KIND_STAGE_END: StringName = &"stage_end"
## 补救冻结区间起止（A 侧 stage_director.gd:13 明确「供 B 提示、C 记录回放节奏」）。
## payload：begin = {reason, open_windows, real_time_ms}
##          end   = {reason, frozen_ms, real_time_ms}
## 冻结期间歌曲时间停住、真实时间照走，所以这两个事件是回放里
## 「哪一段节奏在等玩家」的唯一依据——丢了就只能靠快照反推，等于凭空补节奏。
const KIND_REMEDY_FREEZE_BEGIN: StringName = &"remedy_freeze_begin"
const KIND_REMEDY_FREEZE_END: StringName = &"remedy_freeze_end"
## 第一关借伞 / 还伞（A 侧 umbrella_controller.gd:38-39，交接文档 §5 已列）。
## payload：{umbrella_id, umbrella, holder_id, holder_hand, handed_from, borrow_x, metric}
## 这两个是伞的**归属变更**事件：回放端据此把伞从一只手交到另一只手。
## 伞的位置由显示端按「持伞那只手的手腕」算（A-to-B 交接文档 §6.2），
## 因此记录里只要有这两个事件，回放就能复现伞的移动，不必另存伞的坐标。
const KIND_UMBRELLA_TAKE: StringName = &"umbrella_take"
const KIND_UMBRELLA_RETURN: StringName = &"umbrella_return"
## 油灯五个自主事件（scripts/a/lamp_controller.gd）。
## 注意：cue_hint.gd 里的 stance/hand/move/reach 是线索「动作名」，不是事件 kind。
const KIND_LAMP_STATE_CHANGED: StringName = &"lamp_state_changed"
const KIND_LAMP_INPUT_CHANGED: StringName = &"lamp_input_changed"
const KIND_LAMP_OIL_CHANGED: StringName = &"lamp_oil_changed"
const KIND_LAMP_FEEDBACK_CHANGED: StringName = &"lamp_feedback_changed"
const KIND_LAMP_FINISHED: StringName = &"lamp_finished"

## 本关允许的 kind 全集。出现集合外的 kind 时 push_error 并拒绝插入，
## 防止 A 端拼错字符串后静默写进记录。
## 实测自 A 端代码的权威口径，共 25 个：
##   puppet_controller 5 / performance_system 4 / remedy_system 5 /
##   stage_director 4（stage_start/stage_end + 冻结区间起止）/
##   umbrella_controller 2 / lamp_controller 5
##
## 2026-10-05 补 4 个：remedy_freeze_begin/end 与 umbrella_take/return。
## 前一版白名单停在 21 个，这 4 类事件在 append_event 里被**静默拒写**
## （只 push_error，记录照常收尾），后果是回放里补救冻结那几段节奏凭空消失、
## 伞永远停在开场那只手上——实测真 runtime 录制时暴露。补法有据：
##   - 冻结起止：stage_director.gd:13 写明「供 B 提示、C 记录回放节奏」；
##   - 借伞/还伞：umbrella_controller.gd:38-39 定义，A-to-B 交接文档 §5 已列。
const KNOWN_KINDS: Array = [
	KIND_DRAG_BEGIN, KIND_DRAG_END, KIND_POSE_STANCE, KIND_FACING_TURN,
	KIND_HAND_MOTION, KIND_CUE_HINT, KIND_CUE_FIRE, KIND_CUE_HIT, KIND_CUE_MISS,
	KIND_REMEDY_OPEN, KIND_REMEDY_SUCCESS, KIND_REMEDY_TIMEOUT,
	KIND_REMEDY_SHOW, KIND_REMEDY_HIDE, KIND_STAGE_START, KIND_STAGE_END,
	KIND_REMEDY_FREEZE_BEGIN, KIND_REMEDY_FREEZE_END,
	KIND_UMBRELLA_TAKE, KIND_UMBRELLA_RETURN,
	KIND_LAMP_STATE_CHANGED, KIND_LAMP_INPUT_CHANGED, KIND_LAMP_OIL_CHANGED,
	KIND_LAMP_FEEDBACK_CHANGED, KIND_LAMP_FINISHED,
]

## 灯事件的 object_id 命名空间。A 端 lamp_controller.gd:23 的常量值，
## 与影人事件的 int 0-2 是不同命名空间，靠类型区分而不是靠取值区分。
const LAMP_OBJECT_ID: String = "lamp_main"

## seq 的起始值。本场 PerformanceRecord 内从 1 开始、每成功写入一条 +1。
const SEQ_FIRST: int = 1

## 没有影人对象的事件（关卡开始/结束、补救）填 0，不填 -1，
## 免得下游多一个判空分支。
const OBJECT_ID_NONE: int = 0

## 与关键动作无关的事件填空字符串，而不是 null。
const CUE_ID_NONE: String = ""


var time_ms: int = 0
var kind: StringName = &""
## 事件作用对象。**类型是 Variant，因为 A 端存在两个命名空间**：
##   - 影人事件：int 0-2（下标即 puppet_id）
##   - 油灯事件：String "lamp_main"（lamp_controller.gd:23 的常量）
##   - 关卡/补救等无对象事件：int OBJECT_ID_NONE（0）
## 这三个是类型分歧而非取值范围差异，所以不能用 int 声明。
## 下游按 typeof() 分支处理，不要做数值比较。
var object_id: Variant = OBJECT_ID_NONE
var cue_id: String = CUE_ID_NONE
var payload: Dictionary = {}
## 本场记录内的单调序号，由 PerformanceRecord 分配，不由 A 端提供。
## 放在事件顶层而不是由写入方旁路维护，是为了让排序依据自解释：
## 单看一条记录就能验证它的先后，不必回溯写入时的外部状态。
var seq: int = -1


func _init(p_time_ms: int = 0, p_kind: StringName = &"", p_object_id: Variant = OBJECT_ID_NONE,
		p_cue_id: String = CUE_ID_NONE, p_payload: Dictionary = {}) -> void:
	time_ms = p_time_ms
	kind = p_kind
	object_id = p_object_id
	cue_id = p_cue_id
	payload = p_payload.duplicate(true)
	# payload 至少含 kind，与顶层同值，便于 JSON 化后自解释。
	payload["kind"] = String(p_kind)


## 字段校验。返回空数组表示通过，否则返回问题描述列表。
## 校验失败的事件不写入记录，也不消耗 seq——否则号段会出现空洞，
## 而「seq 连续」是回放端可校验的属性。
##
## object_id 按类型分支校验，不做跨类型数值比较：
##   - int    → 影人/无对象命名空间，须落在 [OBJECT_ID_NONE, PUPPET_COUNT-1]
##   - String → 油灯命名空间，须等于 LAMP_OBJECT_ID
##   - 其他   → 直接拒绝，避免下游拿到无法解释的类型
func validate() -> Array:
	var problems: Array = []
	if time_ms < 0:
		problems.append("time_ms 为负：%d" % time_ms)
	if not KNOWN_KINDS.has(kind):
		problems.append("未知 kind：%s" % kind)
	var id_problem: String = _validate_object_id()
	if not id_problem.is_empty():
		problems.append(id_problem)
	return problems


## object_id 的类型分支校验，返回空串表示通过。
func _validate_object_id() -> String:
	var t: int = typeof(object_id)
	if t == TYPE_INT:
		var v: int = object_id
		if v < OBJECT_ID_NONE or v > CSnapshotScript.PUPPET_COUNT - 1:
			return "object_id 越界（int）：%d" % v
		return ""
	if t == TYPE_STRING or t == TYPE_STRING_NAME:
		var s: String = String(object_id)
		if s != LAMP_OBJECT_ID:
			return "object_id 未知灯对象（String）：%s" % s
		return ""
	return "object_id 类型不支持：%s（值 %s）" % [type_string(t), str(object_id)]


## 分配 seq。仅由 PerformanceRecord 在校验通过后调用。
func assign_seq(p_seq: int) -> void:
	seq = p_seq


## 按 (time_ms, seq) 排序时的比较结果。seq 为 -1 视为未分配，排在最前。
## 因为同 time_ms 时必须靠 seq 定序，所以 seq 必须是顶层字段。
func compare_order(other: Variant) -> int:
	if time_ms != other.time_ms:
		return time_ms - other.time_ms
	# other 是 Variant，成员取值无法用 := 推断，须显式 int。
	var a: int = seq if seq >= 0 else 0
	var b: int = other.seq if other.seq >= 0 else 0
	return a - b


func to_dict() -> Dictionary:
	return {
		"time_ms": time_ms,
		"kind": String(kind),
		"object_id": object_id,
		"cue_id": cue_id,
		"payload": payload.duplicate(true),
		"seq": seq,
	}


## 供测试与诊断使用的紧凑描述。
## object_id 用 %s 而非 %d：它是 Variant，String 命名空间下 %d 会报错。
func describe() -> String:
	return "CTimedEvent(seq=%d, t=%dms, kind=%s, obj=%s, cue=%s)" \
		% [seq, time_ms, kind, str(object_id), cue_id]
