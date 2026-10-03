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

## 本关允许的 kind 全集。出现集合外的 kind 时 push_error 并拒绝插入，
## 防止 A 端拼错字符串后静默写进记录。
const KNOWN_KINDS: Array = [
	KIND_DRAG_BEGIN, KIND_DRAG_END, KIND_POSE_STANCE, KIND_FACING_TURN,
	KIND_HAND_MOTION, KIND_CUE_HINT, KIND_CUE_FIRE, KIND_CUE_HIT, KIND_CUE_MISS,
	KIND_REMEDY_OPEN, KIND_REMEDY_SUCCESS, KIND_REMEDY_TIMEOUT,
	KIND_REMEDY_SHOW, KIND_REMEDY_HIDE, KIND_STAGE_START, KIND_STAGE_END,
]

## seq 的起始值。本场 PerformanceRecord 内从 1 开始、每成功写入一条 +1。
const SEQ_FIRST: int = 1

## 没有影人对象的事件（关卡开始/结束、补救）填 0，不填 -1，
## 免得下游多一个判空分支。
const OBJECT_ID_NONE: int = 0

## 与关键动作无关的事件填空字符串，而不是 null。
const CUE_ID_NONE: String = ""


var time_ms: int = 0
var kind: StringName = &""
var object_id: int = OBJECT_ID_NONE
var cue_id: String = CUE_ID_NONE
var payload: Dictionary = {}
## 本场记录内的单调序号，由 PerformanceRecord 分配，不由 A 端提供。
## 放在事件顶层而不是由写入方旁路维护，是为了让排序依据自解释：
## 单看一条记录就能验证它的先后，不必回溯写入时的外部状态。
var seq: int = -1


func _init(p_time_ms: int = 0, p_kind: StringName = &"", p_object_id: int = OBJECT_ID_NONE,
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
func validate() -> Array:
	var problems: Array = []
	if time_ms < 0:
		problems.append("time_ms 为负：%d" % time_ms)
	if not KNOWN_KINDS.has(kind):
		problems.append("未知 kind：%s" % kind)
	if object_id < 0 or object_id > CSnapshot.PUPPET_COUNT - 1:
		problems.append("object_id 越界：%d" % object_id)
	return problems


## 分配 seq。仅由 PerformanceRecord 在校验通过后调用。
func assign_seq(p_seq: int) -> void:
	seq = p_seq


## 按 (time_ms, seq) 排序时的比较结果。seq 为 -1 视为未分配，排在最前。
## 因为同 time_ms 时必须靠 seq 定序，所以 seq 必须是顶层字段。
func compare_order(other: CTimedEvent) -> int:
	if time_ms != other.time_ms:
		return time_ms - other.time_ms
	var a := seq if seq >= 0 else 0
	var b := other.seq if other.seq >= 0 else 0
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
func describe() -> String:
	return "CTimedEvent(seq=%d, t=%dms, kind=%s, obj=%d, cue=%s)" \
		% [seq, time_ms, kind, object_id, cue_id]
