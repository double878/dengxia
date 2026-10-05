extends RefCounted
class_name LampController
## A 范围的油灯控制：灯距、显露度、灯油消耗与火焰反馈。
## 依 TECH_DESIGN.md 第 2.3 节（LampState / TimedEvent 契约）与 PRD 第 4.3 节。
##
## 单向数据流：本控制器先改 LampState，再把 TimedEvent 写入队列；
## B 的显示与 C 的录制在同一帧读状态，因此一定读到改动后的值。
##
## 时间来源：**唯一**使用 MusicClock 的歌曲时间。绝不引入第二套墙钟计时，
## 因此暂停时歌曲时间、灯油、火焰反馈与输入判定一起冻结，恢复后沿同一时间轴继续。
## `delta` 只用于把「按住输入」换算成连续位移，不参与灯油计算。
##
## 灯油规则：以 (oil_start, song_time_start) 为基准，用**歌曲时间差**乘消耗速率。
## 同一歌曲时间重复更新不会重复扣油；歌曲时间倒退按 0 计，油量不回升。

const LampStateScript := preload("res://scripts/a/lamp_state.gd")

## 油灯在 TimedEvent 里的对象标识。
##
## 注意：这是本切片按任务书要求采用的 **String** 标识，而切片 1-4 的影人事件
## 用的是 int（影人 0-2）。两种类型并存是已知的契约分歧，已在汇报中提出，
## 待 C 的录制契约定案后统一；此处不改动切片 1-4 的任何实现。
const LAMP_OBJECT_ID: String = "lamp_main"

## 事件类型
const KIND_STATE_CHANGED: String = "lamp_state_changed"
const KIND_INPUT_CHANGED: String = "lamp_input_changed"
const KIND_OIL_CHANGED: String = "lamp_oil_changed"
const KIND_FEEDBACK_CHANGED: String = "lamp_feedback_changed"
const KIND_FINISHED: String = "lamp_finished"

## 灯油消耗速率：每秒消耗占满油的多少。仅此一处定义，不散落在多处硬编码。
## 取 0.015/s 的意图：35 秒的第一关大约消耗 52%，最暗时仍留有可辨认余量
## （PRD 第 8 节要求最暗时关键对象仍可辨认）。这是原型起点值，待游玩实测校准。
const OIL_CONSUME_PER_S: float = 0.015

## 连续输入速度（单位/秒）
const DISTANCE_SPEED_PER_S: float = 0.6
const EXPOSURE_SPEED_PER_S: float = 0.6

## 火焰反馈每次表现结果的增量
const FEEDBACK_HIT_DELTA: float = 0.25
const FEEDBACK_MISS_DELTA: float = -0.18

## 输入快照的键。同一控制轴的两个方向同时按住时净方向为 0（保持原值）。
const INPUT_KEYS: Array[String] = [
	"distance_increase", "distance_decrease", "exposure_increase", "exposure_decrease",
]

## 提高火焰反馈的事件类型
const FEEDBACK_UP_KINDS: Array[String] = ["cue_hit", "remedy_success"]
## 降低火焰反馈的事件类型
const FEEDBACK_DOWN_KINDS: Array[String] = ["cue_miss", "remedy_timeout", "remedy_failed"]

## 鸭子类型时钟：只需提供 get_song_time_ms() -> int 与 is_paused() -> bool。
var clock: Object = null

var lamp: LampState = null

var _events: Array[Dictionary] = []
var _input_map: Dictionary = {}
var _oil_song_ms: int = 0            ## 上次结算灯油时的歌曲时间
var _oil_start: float = 1.0          ## 初始化时的灯油基准
var _finished: bool = false
var _was_paused: bool = false
var _seen_feedback_keys: Dictionary = {}   ## 已处理过的表现事件，避免重复叠加


## 建立油灯。必须在 clock 赋值之后调用。
func setup() -> void:
	lamp = LampStateScript.new()
	_events.clear()
	_input_map = {}
	for key in INPUT_KEYS:
		_input_map[key] = false
	_seen_feedback_keys.clear()
	_finished = false
	_was_paused = false
	_oil_start = lamp.oil
	# 初始化时记录 oil_start 与 song_time_start，之后一律用歌曲时间差结算消耗。
	_oil_song_ms = _clock_song_ms()


## 设置本帧的输入快照。整体替换而非逐键累加，避免漏掉「松开」。
func set_input_map(input_map: Dictionary) -> void:
	_input_map = {}
	for key in INPUT_KEYS:
		_input_map[key] = bool(input_map.get(key, false))


func get_input_map() -> Dictionary:
	return _input_map.duplicate()


## 每帧一次。顺序固定：更新歌曲时间基准 → 应用灯距/显露度输入 → 消耗灯油
## → 处理表现事件驱动火焰反馈 → clamp → 事件早已在各自步骤内入队。
## 保证同一帧内状态先变、事件后到。
##
## performance_events 是判定/补救系统产出的 TimedEvent 数组，用来驱动 flame_feedback。
## 传空数组即表示本帧没有表现事件。
func update(delta: float, performance_events: Array = []) -> Array[Dictionary]:
	if lamp == null or _finished:
		return []
	# 暂停冻结：歌曲时间、灯油、火焰反馈与输入判定一起停住。
	if is_paused():
		_was_paused = true
		return []
	if _was_paused:
		# 恢复的第一帧：把灯油基准对齐到当前歌曲时间，使暂停时长不被计入消耗；
		# 但**不能**跳过本帧，否则恢复当场那一帧的推进会被吞掉。
		_was_paused = false
		_oil_song_ms = _clock_song_ms()

	var now_ms: int = _clock_song_ms()
	var before: Dictionary = lamp.to_dict()

	_apply_input(maxf(delta, 0.0))
	_consume_oil(now_ms)
	_apply_feedback(now_ms, performance_events)
	lamp.clamp_continuous()

	_emit_changes(now_ms, before)
	return _drain_events()


## 结束演出：之后不再消耗灯油、也不再产生任何事件。
func finish_show() -> void:
	if _finished:
		return
	_finished = true
	_emit(KIND_FINISHED, _clock_song_ms(), "", lamp.to_dict())


func is_finished() -> bool:
	return _finished


func is_paused() -> bool:
	if clock == null:
		return false
	return bool(clock.call("is_paused"))


## C 的 Recorder 每帧调用一次；取走即清空，不会重复记录。
func take_events() -> Array[Dictionary]:
	return _drain_events()


## 模拟接收端：逐条读入事件并解析成可核对的记录，只读不写。
## 用于在不依赖 B/C 的前提下证明事件内容可被下游消费。
## 静态方法：接收端不持有任何运行状态，构造后无需 setup() 即可使用。
static func receive_events(events: Array) -> Array:
	var received: Array = []
	for raw in events:
		if not (raw is Dictionary):
			continue
		var event: Dictionary = raw
		var complete: bool = event.has("time_ms") and event.has("kind") \
			and event.has("object_id") and event.has("cue_id") and event.has("payload")
		if not complete:
			push_error("LampController.receive_events 收到字段不全的事件：%s" % str(event))
			continue
		if not (event["payload"] is Dictionary):
			push_error("LampController.receive_events 收到 payload 不是字典的事件：%s" % str(event))
			continue
		received.append({
			"time_ms": int(event["time_ms"]),
			"kind": str(event["kind"]),
			"object_id": str(event["object_id"]),
			"cue_id": str(event["cue_id"]),
			"payload": (event["payload"] as Dictionary).duplicate(true),
		})
	return received


## 单轴净方向：+1 增加、-1 减少、0 保持（含同轴相反输入同时按住）。
static func net_dir(increase: bool, decrease: bool) -> int:
	if increase == decrease:
		return 0                       ## 都按或都没按 → 保持当前值
	return 1 if increase else -1


static func clamp_unit(value: float) -> float:
	return clampf(value, LampStateScript.UNIT_MIN, LampStateScript.UNIT_MAX)


func _apply_input(delta: float) -> void:
	if delta <= 0.0:
		return
	var dist_dir: int = net_dir(_input_map["distance_increase"], _input_map["distance_decrease"])
	var expo_dir: int = net_dir(_input_map["exposure_increase"], _input_map["exposure_decrease"])
	if dist_dir != 0:
		lamp.distance = clamp_unit(
			lamp.distance + float(dist_dir) * DISTANCE_SPEED_PER_S * delta)
	if expo_dir != 0:
		lamp.exposure = clamp_unit(
			lamp.exposure + float(expo_dir) * EXPOSURE_SPEED_PER_S * delta)


## 灯油只随歌曲时间推进消耗。同一歌曲时间重复更新差值为 0，因此天然幂等；
## 歌曲时间倒退（delta < 0）按 0 计，油量不回升。
func _consume_oil(now_ms: int) -> void:
	var elapsed_ms: int = now_ms - _oil_song_ms
	if elapsed_ms < 0:
		# 丢弃倒退区间，但把基准移到新的歌曲时间，保证后续前进仍能扣油。
		_oil_song_ms = now_ms
		return
	if elapsed_ms <= 0:
		return
	_oil_song_ms = now_ms
	var elapsed_s: float = float(elapsed_ms) / 1000.0
	lamp.oil = clamp_unit(lamp.oil - OIL_CONSUME_PER_S * elapsed_s)


## 火焰反馈只由表现结果驱动。同一事件重复输入不重复叠加。
##
## 事件来自判定/补救系统，但也可能来自录制回放或测试注入，因此逐字段判类型，
## 不假设 kind / payload / cue_id / time_ms 的形状；畸形事件一律跳过而不是抛错。
func _apply_feedback(now_ms: int, performance_events: Array) -> void:
	for raw in performance_events:
		if not (raw is Dictionary):
			continue
		var event: Dictionary = raw
		var kind: String = str(event.get("kind", ""))
		var up: bool = FEEDBACK_UP_KINDS.has(kind)
		var down: bool = FEEDBACK_DOWN_KINDS.has(kind)
		if not up and not down:
			continue
		# 表现结果必须是完整的 TimedEvent。缺字段的事件不能伪造一次命中/错拍。
		if not event.has("cue_id") or typeof(event["cue_id"]) != TYPE_STRING:
			continue
		if not event.has("time_ms") or typeof(event["time_ms"]) != TYPE_INT:
			continue
		if not event.has("payload") or not (event["payload"] is Dictionary):
			continue
		var cue_id: String = event["cue_id"]
		if cue_id.is_empty():
			continue
		var stamp_ms: int = event["time_ms"]
		# 去重键含 cue_id 与事件时间：同一事件被重复喂入时只生效一次，
		# 但不同时刻的合法事件仍各自生效。
		var key: String = "%s|%s|%d" % [kind, cue_id, stamp_ms]
		if _seen_feedback_keys.has(key):
			continue
		_seen_feedback_keys[key] = true
		var delta: float = FEEDBACK_HIT_DELTA if up else FEEDBACK_MISS_DELTA
		lamp.flame_feedback = clamp_unit(lamp.flame_feedback + delta)


## 状态先变化，再按变化字段发事件。
func _emit_changes(now_ms: int, before: Dictionary) -> void:
	var changed: Array = lamp.changed_fields(before)
	if changed.is_empty():
		return
	var payload: Dictionary = lamp.to_dict()
	payload["changed_fields"] = changed
	if changed.has("oil"):
		_emit(KIND_OIL_CHANGED, now_ms, "", payload)
	if changed.has("flame_feedback"):
		_emit(KIND_FEEDBACK_CHANGED, now_ms, "", payload)
	if changed.has("distance") or changed.has("exposure"):
		_emit(KIND_INPUT_CHANGED, now_ms, "", payload)
	_emit(KIND_STATE_CHANGED, now_ms, "", payload)


func _clock_song_ms() -> int:
	if clock == null:
		return 0
	return int(clock.call("get_song_time_ms"))


func _drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_events)
	_events.clear()
	return out


## cue_id 为空串表示这是油灯自身的自主事件，不代表任何关键动作。
func _emit(kind: String, time_ms: int, cue_id: String, payload_extra: Dictionary) -> void:
	var payload := {"kind": kind}
	payload.merge(payload_extra, true)
	_events.append({
		"time_ms": time_ms,
		"kind": kind,
		"object_id": LAMP_OBJECT_ID,
		"cue_id": cue_id,
		"payload": payload,
	})
