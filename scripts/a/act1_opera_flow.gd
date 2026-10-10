extends RefCounted
class_name Act1OperaFlow
## 只读唯一双时钟和真实道具交接；不播放声音、不代演。

const WAIT_LIMIT_MS := 8000
var config: Dictionary = {}
var clock: MusicClock
var umbrella: UmbrellaController
var phase: String = "opening"
var taken: bool = false
var returned: bool = false
var _arrived: bool = false
var _deadline_ms: int = -1
var _events: Array[Dictionary] = []


func setup(value: Dictionary, p_clock: MusicClock, p_umbrella: UmbrellaController) -> bool:
	var previous := -1
	for key in ["opening_end_ms", "arrival_ms", "singing_start_ms", "singing_end_ms",
			"take_ms", "return_gate_ms", "return_start_ms", "closing_ms", "duration_ms"]:
		var point := int(value.get(key, -1))
		if point <= previous:
			push_error("第一幕音频时间表非法：%s=%d" % [key, point])
			return false
		previous = point
	if p_clock == null or p_umbrella == null or str(value.get("audio_version", "")).is_empty():
		return false
	config = value.duplicate(true)
	clock = p_clock
	umbrella = p_umbrella
	return true


func start() -> void:
	phase = ""
	taken = false
	returned = false
	_arrived = false
	_deadline_ms = -1
	_events.clear()
	umbrella.take_allowed = false
	umbrella.return_allowed = false
	_set_phase("opening", "start")


func before_update() -> void:
	if clock.is_paused():
		return
	if is_waiting():
		if clock.get_real_time_ms() >= _deadline_ms:
			_timeout()
		elif phase == "wait_arrival" and umbrella.in_join_window():
			_arrived = true
			_end_wait("arrived", "borrow_dialogue")
		return
	var now := clock.get_song_time_ms()
	if now >= int(config.closing_ms):
		_set_phase("closing", "timeline")
	elif phase == "closing":
		return
	elif now < int(config.opening_end_ms):
		_set_phase("opening", "timeline")
	elif now < int(config.arrival_ms):
		_set_phase("approach", "timeline")
	elif not _arrived:
		if umbrella.in_join_window():
			_arrived = true
			_set_phase("borrow_dialogue", "arrived")
		else:
			_begin_wait("wait_arrival")
	if is_waiting() or phase == "closing":
		return
	if not taken:
		if now >= int(config.take_ms):
			umbrella.take_allowed = true
			_begin_wait("wait_take")
		elif _arrived:
			_set_phase("borrow_dialogue", "timeline")
	elif now < int(config.return_gate_ms):
		_set_phase("tour", "timeline")
	elif not returned:
		_begin_wait("wait_return")
	elif now >= int(config.return_start_ms):
		_set_phase("return_dialogue", "returned")


func after_update(events: Array) -> void:
	if clock.is_paused():
		return
	for event in events:
		match str(event.get("kind", "")):
			"umbrella_take":
				if taken:
					continue
				taken = true
				umbrella.take_allowed = false
				umbrella.return_allowed = true
				_emit("opera_take_close", {"asset_id": "take_close", "phase_id": "tour"})
				_end_wait("taken", "tour")
			"umbrella_return":
				returned = true
				umbrella.return_allowed = false
				if phase == "wait_return":
					_end_wait("returned", "return_dialogue")


func is_waiting() -> bool:
	return phase.begins_with("wait_")


func take_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


func _begin_wait(value: String) -> void:
	_deadline_ms = clock.get_real_time_ms() + WAIT_LIMIT_MS
	_set_phase(value, "condition_pending")
	clock.set_song_frozen(true)
	_emit("opera_wait_begin", {"phase_id": value, "deadline_real_ms": _deadline_ms,
		"asset_id": "wait_loop"})


func _end_wait(reason: String, next: String) -> void:
	if is_waiting():
		_emit("opera_wait_end", {"phase_id": phase, "reason": reason,
			"wait_ms": WAIT_LIMIT_MS - maxi(_deadline_ms - clock.get_real_time_ms(), 0)})
	_deadline_ms = -1
	_set_phase(next, reason)
	clock.set_song_frozen(false)


func _timeout() -> void:
	var from := clock.get_song_time_ms()
	_end_wait("timeout", "closing")
	umbrella.take_allowed = false
	umbrella.return_allowed = false
	clock.advance_to_ms(int(config.closing_ms))
	_emit("opera_score_skipped", {"from_ms": from, "to_ms": int(config.closing_ms),
		"reason": "timeout", "phase_id": "closing", "asset_id": "main"})


func _set_phase(value: String, reason: String) -> void:
	if phase == value:
		return
	phase = value
	_emit("opera_phase_changed", {"phase_id": value, "reason": reason, "asset_id": "main"})


func _emit(kind: String, data: Dictionary) -> void:
	data.merge({"real_time_ms": clock.get_real_time_ms(), "audio_version": config.audio_version,
		"stage_id": 1}, true)
	_events.append({"time_ms": clock.get_song_time_ms(), "kind": kind,
		"object_id": "performance_audio", "cue_id": "", "payload": data})
