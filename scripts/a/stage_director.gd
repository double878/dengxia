extends RefCounted
class_name StageDirector
## A 范围的第一关推进与结束判定。
##
## 职责边界：只管「演出时间轴」这一件事——把判定系统、补救系统与关卡时长串起来，
## 并保证 PRD 第 5.2.4、5.2.5 节的两条硬约束：
## - 8 秒到期仍未完成时**演出继续**，不暂停、不重播、不失败；
## - 到 35 秒**按时结束**，绝不延长、绝不重播；未到期的补救窗口随演出结束。
##
## 输出事件：stage_start {duration_ms}、stage_end {reason, song_time_ms, remedy_open_count}。
## 编排顺序固定为：先 detect_misses（判定落点是否已过）→ 再 remedy.update（开窗/结算）
## → 最后判断关卡是否到时。这样「落点刚过」与「窗口刚开」在同一帧内一次完成。

const PerformanceSystemScript := preload("res://scripts/a/performance_system.gd")
const RemedySystemScript := preload("res://scripts/a/remedy_system.gd")

const END_REASON_DURATION: String = "duration_reached"   ## 正常到时结束
const END_REASON_FORCED: String = "forced"               ## 外部要求立即结束（如跳过）

var stage_def: StageDef = null
var clock: Object = null                ## 鸭子类型：get_song_time_ms() -> int
var performance: PerformanceSystem = null
var remedy: RemedySystem = null

var started: bool = false
var ended: bool = false
var end_reason: String = ""

var _events: Array[Dictionary] = []
var _end_ms: int = -1


## 建立第一关的演出：判定系统与补救系统共用同一个时钟与同一批 Cue。
func setup(p_stage_def: StageDef, p_clock: Object, p_puppets: Array) -> void:
	stage_def = p_stage_def
	clock = p_clock
	performance = PerformanceSystemScript.new()
	performance.setup(stage_def.cues, clock, p_puppets)
	remedy = RemedySystemScript.new()
	remedy.setup(stage_def.cues, clock)
	started = false
	ended = false
	end_reason = ""
	_events.clear()
	_end_ms = -1


func start() -> void:
	if started:
		return
	started = true
	_events.append({
		"time_ms": song_time_ms(),
		"kind": "stage_start",
		"object_id": 0,
		"cue_id": "",
		"payload": {"kind": "stage_start", "duration_ms": duration_ms()},
	})


## 每帧一次。必须在 PuppetController.tick() 之后调用。
## 事件按「判定 → 补救 → 结束」的顺序并进同一个队列，调用方只读一次。
func update(controller_events: Array) -> void:
	if not started or ended:
		return
	var now_ms: int = song_time_ms()
	performance.update(now_ms, controller_events)
	_events.append_array(performance.take_events())
	performance.detect_misses(now_ms)
	_events.append_array(performance.take_events())
	remedy.update(now_ms, performance, false)
	_events.append_array(remedy.take_events())
	if now_ms >= duration_ms():
		_finish(END_REASON_DURATION, now_ms)


## 立即结束（例如玩家选择跳过）。仍走同一套收尾，不重播。
func force_end() -> void:
	if ended:
		return
	_finish(END_REASON_FORCED, song_time_ms())


func is_over() -> bool:
	return ended


func duration_ms() -> int:
	return stage_def.duration_ms if stage_def != null else 0


## 本关剩余时间（毫秒），到点后为 0。
func remaining_ms() -> int:
	if ended:
		return 0
	return maxi(duration_ms() - song_time_ms(), 0)


func progress() -> float:
	if duration_ms() <= 0:
		return 0.0
	return clampf(float(song_time_ms()) / float(duration_ms()), 0.0, 1.0)


func take_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_events)
	_events.clear()
	return out


func song_time_ms() -> int:
	return int(clock.get_song_time_ms()) if clock != null else 0


func _finish(reason: String, now_ms: int) -> void:
	ended = true
	end_reason = reason
	_end_ms = now_ms
	# 窗口随演出结束关闭：不延长关卡固定时间
	var open_before: int = remedy.open_count()
	remedy.update(now_ms, performance, true)
	_events.append_array(remedy.take_events())
	var still_open: int = remedy.open_count()
	if still_open > 0:
		push_error("关卡结束时仍有 %d 个补救窗口未关闭，演出时长被延长了" % still_open)
	_events.append({
		"time_ms": now_ms,
		"kind": "stage_end",
		"object_id": 0,
		"cue_id": "",
		"payload": {
			"kind": "stage_end",
			"reason": reason,
			"song_time_ms": now_ms,
			"remedy_open_count": open_before,
			"duration_ms": duration_ms(),
		},
	})
