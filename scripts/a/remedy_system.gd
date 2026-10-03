extends RefCounted
class_name RemedySystem
## 8 秒补救（PRD 第 5.2 节）。
##
## 规则（逐条对应 PRD，写在这里便于对照）：
## 1. 错过关键动作落点，或合拍度跌破警戒线 → 出现示范手与警告；
## 2. 从触发时起给 8 秒；
## 3. 窗口内补做对应动作即算补救成功，示范与警告结束；
## 4. 8 秒到期仍未完成 → 记录这次未完成，提示结束，**演出继续，不暂停、不重播、不失败**；
## 5. 同一 cue_id 不能反复触发或重置自己的窗口；不同错误可各自触发；
##    同屏一次只展示一个当前示范，所有失误各自保留记录；
##    窗口永远不延长关卡固定时间，关卡结束时未到期的窗口随演出结束（close_reason = "stage_end"）。
##
## 输出事件（登记在 docs/superpowers/plans/2026-10-03-level1-a.md 第 1.3 节）：
##   remedy_open    {action, demo_action, reason, duration_ms, remaining_ms, target_range}
##   remedy_success {action, elapsed_ms, still_missed}
##   remedy_timeout {action, elapsed_ms, reason?}
##   remedy_show    {action, demo_action, remaining_ms}   当前示范（同屏唯一）
##   remedy_hide    {}                                    当前示范结束
##
## 关键不变量：补救成功**不抹去**原来的失误记录（PRD 第 5.2.3 节）。
## records 保存全部记录；窗口上的 missed 标记本系统从不自动清除。

const DEFAULT_WINDOW_MS: int = 8000     ## PRD 第 5.2.2 节：固定 8 秒
const DEFAULT_SYNC_THRESHOLD: float = 0.5
const DEFAULT_MIN_GRADED: int = 2       ## 段内至少已判定这么多落点，才套用合拍度阈值

## 开窗原因
const REASON_MISSED: String = "missed_cue"
const REASON_LOW_SYNC: String = "low_sync"

## 关窗原因
const CLOSE_SUCCESS: String = "success"
const CLOSE_TIMEOUT: String = "timeout"
const CLOSE_STAGE_END: String = "stage_end"

var cues: Array = []                    ## 由 StageDef 提供，用于查目标范围与示范动作
var clock: Object = null                ## 鸭子类型：get_song_time_ms() -> int
var window_ms: int = DEFAULT_WINDOW_MS
var sync_threshold: float = DEFAULT_SYNC_THRESHOLD
var min_graded: int = DEFAULT_MIN_GRADED

var windows: Dictionary = {}            ## cue_id -> 补救窗口，同 cue_id 唯一
var records: Array = []                 ## 全部失误/补救记录（含已结束的窗口）
var current_demo_cue_id: String = ""    ## 同屏只展示一个当前示范

var _events: Array[Dictionary] = []
var _low_sync_segments: Dictionary = {} ## 已因低合拍度过一次补救的段，避免同段反复开窗


func setup(p_cues: Array, p_clock: Object) -> void:
	cues = p_cues
	clock = p_clock
	windows.clear()
	records.clear()
	current_demo_cue_id = ""
	_events.clear()
	_low_sync_segments.clear()


func get_cue(cue_id: String) -> Dictionary:
	for cue in cues:
		if str(cue.get("cue_id", "")) == cue_id:
			return cue
	return {}


## 触发补救。同一 cue_id 已有窗口时**拒绝重复触发**，原窗口与剩余时间不受影响。
func open(cue_id: String, reason: String, song_time_ms: int) -> bool:
	if windows.has(cue_id):
		return false
	var cue: Dictionary = get_cue(cue_id)
	if cue.is_empty():
		push_error("RemedySystem.open 收到未知 cue_id：%s" % cue_id)
		return false
	var window: Dictionary = {
		"cue_id": cue_id,
		"reason": reason,
		"action": str(cue.get("action", "")),
		"demo_action": str(cue.get("demo_action", cue.get("action", ""))),
		"target_object": int(cue.get("target_object", 0)),
		"started_ms": song_time_ms,
		"deadline_ms": song_time_ms + window_ms,
		"target_range": cue.get("target_range", {}).duplicate(true),
		"missed": true,                  ## 原失误保留；成功也不清除
		"closed": false,
		"close_reason": "",
	}
	windows[cue_id] = window
	records.append(window)
	_emit(song_time_ms, "remedy_open", window["target_object"], cue_id, {
		"action": window["action"],
		"demo_action": window["demo_action"],
		"reason": reason,
		"duration_ms": window_ms,
		"remaining_ms": window_ms,
		"target_range": window["target_range"],
	})
	_select_demo(song_time_ms)
	return true


## 每帧一次，在判定系统 detect_misses() 之后调用。
## 负责：为新的漏做/低合拍开窗、结算窗口内的补做、处理超时与关卡结束。
func update(song_time_ms: int, performance: PerformanceSystem, stage_end: bool) -> void:
	_open_for_new_errors(song_time_ms, performance)
	_resolve_windows(song_time_ms, performance, stage_end)


func is_open(cue_id: String) -> bool:
	return windows.has(cue_id)


func get_window(cue_id: String) -> Dictionary:
	return windows.get(cue_id, {})


func open_count() -> int:
	return windows.size()


func get_records() -> Array:
	return records


func take_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_events)
	_events.clear()
	return out


## 剩余时间（毫秒）。窗口不存在时返回 0。
func remaining_ms(cue_id: String, song_time_ms: int) -> int:
	var window: Dictionary = windows.get(cue_id, {})
	if window.is_empty():
		return 0
	return maxi(int(window["deadline_ms"]) - song_time_ms, 0)


## 为「新出现的错误」开窗：漏做的关键动作，以及跌破警戒线的段。
func _open_for_new_errors(song_time_ms: int, performance: PerformanceSystem) -> void:
	for cue_id in performance.missed_outright_cue_ids():
		if windows.has(cue_id):
			continue                      ## 同一错误不能反复触发
		if _already_recorded(cue_id):
			continue
		open(cue_id, REASON_MISSED, song_time_ms)

	# 合拍度跌破警戒线：每段只触发一次，避免同一段反复刷窗口
	for segment_name in _segments_with_graded_cues(performance):
		if _low_sync_segments.has(segment_name):
			continue
		if performance.segment_graded_count(segment_name) < min_graded:
			continue
		var score: float = performance.segment_score(segment_name)
		if score < 0.0 or score >= sync_threshold:
			continue
		_low_sync_segments[segment_name] = true
		var cue_id: String = _first_open_cue_in_segment(segment_name, performance)
		if cue_id.is_empty():
			continue                      ## 本段没有既未判定、也未开窗的落点
		open(cue_id, REASON_LOW_SYNC, song_time_ms)


## 结算所有窗口：补做成功、超时、随关卡结束。
func _resolve_windows(song_time_ms: int, performance: PerformanceSystem, stage_end: bool) -> void:
	for cue_id in windows.keys():
		var window: Dictionary = windows[cue_id]
		if bool(window["closed"]):
			continue
		if _remedy_completed(window, performance):
			_close(cue_id, CLOSE_SUCCESS, song_time_ms)
			continue
		if stage_end:
			# 关卡结束：未到期的窗口随演出结束，不延长关卡（PRD 第 5.2.5 节）
			_close(cue_id, CLOSE_STAGE_END, song_time_ms)
			continue
		if song_time_ms >= int(window["deadline_ms"]):
			_close(cue_id, CLOSE_TIMEOUT, song_time_ms)


## 补救是否已完成：窗口开启之后，玩家**真的做出了**这条 cue 要求的动作。
##
## 判定系统在漏做时写入的 `missed_outright` 结果带着落点时刻的时间戳，
## 而「补做」是一次新的判定、时间戳必然晚于窗口开启时刻；两者因此可区分，
## 不会把开窗前的旧成绩当成补救成功。`hit` 是否转正与本函数无关：
## 补救成功补的是「把动作做出来」，原失误仍留在结果与记录里。
func _remedy_completed(window: Dictionary, performance: PerformanceSystem) -> bool:
	var cue_id: String = str(window["cue_id"])
	var outcome: Dictionary = performance.get_outcome(cue_id)
	if outcome.is_empty():
		return false
	if bool(outcome.get("missed_outright", false)):
		return false                  ## 还停留在「完全没做」的漏做结果上
	return int(outcome.get("time_ms", 0)) >= int(window["started_ms"])


func _close(cue_id: String, reason: String, song_time_ms: int) -> void:
	var window: Dictionary = windows[cue_id]
	window["closed"] = true
	window["close_reason"] = reason
	window["closed_ms"] = song_time_ms
	var elapsed: int = song_time_ms - int(window["started_ms"])
	match reason:
		CLOSE_SUCCESS:
			_emit(song_time_ms, "remedy_success", int(window["target_object"]), cue_id, {
				"action": str(window["action"]),
				"elapsed_ms": elapsed,
				"still_missed": bool(window["missed"]),   ## 原失误保留
			})
		CLOSE_TIMEOUT:
			_emit(song_time_ms, "remedy_timeout", int(window["target_object"]), cue_id, {
				"action": str(window["action"]),
				"elapsed_ms": elapsed,
			})
		CLOSE_STAGE_END:
			_emit(song_time_ms, "remedy_timeout", int(window["target_object"]), cue_id, {
				"action": str(window["action"]),
				"elapsed_ms": elapsed,
				"reason": CLOSE_STAGE_END,
			})
	windows.erase(cue_id)
	if current_demo_cue_id == cue_id:
		current_demo_cue_id = ""
		_emit(song_time_ms, "remedy_hide", int(window["target_object"]), cue_id, {})
	_select_demo(song_time_ms)


## 同屏只展示一个当前示范：选剩余时间最短的窗口（最紧急的先提示）。
func _select_demo(song_time_ms: int) -> void:
	var best_id: String = ""
	var best_deadline: int = 1 << 62
	for cue_id in windows.keys():
		var window: Dictionary = windows[cue_id]
		if bool(window["closed"]):
			continue
		var deadline: int = int(window["deadline_ms"])
		if deadline < best_deadline:
			best_deadline = deadline
			best_id = str(cue_id)
	if best_id == current_demo_cue_id:
		return
	if not current_demo_cue_id.is_empty():
		_emit(song_time_ms, "remedy_hide", 0, current_demo_cue_id, {})
	current_demo_cue_id = best_id
	if not best_id.is_empty():
		var chosen: Dictionary = windows[best_id]
		_emit(song_time_ms, "remedy_show", int(chosen["target_object"]), best_id, {
			"action": str(chosen["action"]),
			"demo_action": str(chosen["demo_action"]),
			"remaining_ms": maxi(int(chosen["deadline_ms"]) - song_time_ms, 0),
		})


func _already_recorded(cue_id: String) -> bool:
	for record in records:
		if str(record.get("cue_id", "")) == cue_id and str(record.get("reason", "")) != REASON_LOW_SYNC:
			return true
	return false


func _segments_with_graded_cues(performance: PerformanceSystem) -> Array[String]:
	var out: Array[String] = []
	for cue in cues:
		var segment_name: String = str(cue.get("segment", ""))
		if segment_name.is_empty() or out.has(segment_name):
			continue
		if performance.segment_graded_count(segment_name) > 0:
			out.append(segment_name)
	return out


## 低合拍度补救挂在本段第一条**还没判定、也还没开着窗口**的 cue 上。
##
## 跳过已开着窗口的 cue 是必须的：漏做路径会为每条漏做的 cue 开窗，段内第一条
## 漏做的 cue 因此几乎总是已经有窗口。若不跳过，`_open_for_new_errors` 会在这里
## 静默 continue，使「跌破警戒线触发补救」在本关数据下永远不生效。
func _first_open_cue_in_segment(segment_name: String, performance: PerformanceSystem) -> String:
	for cue in cues:
		if str(cue.get("segment", "")) != segment_name:
			continue
		var cue_id: String = str(cue.get("cue_id", ""))
		if performance.has_outcome(cue_id):
			continue
		if windows.has(cue_id):
			continue
		return cue_id
	return ""


func _emit(song_time_ms: int, kind: String, object_id: int, cue_id: String,
		payload_extra: Dictionary) -> void:
	var payload := {"kind": kind}
	payload.merge(payload_extra, true)
	_events.append({
		"time_ms": song_time_ms,
		"kind": kind,
		"object_id": object_id,
		"cue_id": cue_id,
		"payload": payload,
	})
