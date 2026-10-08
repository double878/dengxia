extends Node
class_name PerformanceAudio
## 表现层读取 MusicClock；主播放器的暂停/续播只由 MusicClock 控制。

var clock: MusicClock
var score: AudioScore
var problems: Array[String] = []
var _main: AudioStreamPlayer
var _slow: AudioStreamPlayer
var _sync: AudioStreamSynchronized
var _ready_audio: bool = false
var _started: bool = false
var _state: String = "stopped"
var _line: Dictionary = {}
var _events: Array[Dictionary] = []
var _sequence: int = 0
var _vocal_db: float = 0.0
var _vocal_target: float = 0.0
var _last_feedback: float = 0.5
var _was_frozen: bool = false
var _slow_gain: float = 0.0
var _main_gain: float = 1.0


func setup(p_score: AudioScore, p_clock: MusicClock, streams: Dictionary = {}) -> bool:
	if _main != null or p_score == null or p_clock == null:
		push_error("PerformanceAudio.setup 缺少配置/时钟或重复建立")
		return false
	score = p_score
	clock = p_clock
	problems = score.validate()
	if streams.is_empty():
		var bundle: Dictionary = score.load_bundle()
		streams = bundle["streams"]
		problems = bundle["problems"]
	else:
		problems.append_array(score.validate_streams(streams))
	if not problems.is_empty():
		return false
	_sync = AudioStreamSynchronized.new()
	_sync.stream_count = score.tracks.size()
	for i in score.tracks.size():
		_sync.set_sync_stream(i, streams[score.tracks[i]["asset_id"]])
	_main = AudioStreamPlayer.new()
	_main.name = "PerformanceMain"
	_main.stream = _sync
	add_child(_main)
	_slow = AudioStreamPlayer.new()
	_slow.name = "PerformanceRemedy"
	var loop: AudioStreamWAV = streams["remedy_slow"].duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = int(round(loop.get_length() * float(loop.mix_rate)))
	_slow.stream = loop
	add_child(_slow)
	_ready_audio = true
	return true


## MusicClock.start() 先启动宿主；此处只初始化本轮表现，不能建立第二时钟。
func start() -> void:
	_started = true
	_sequence = 0
	_events.clear()
	_line = {}
	_vocal_db = 0.0
	_vocal_target = 0.0
	_last_feedback = 0.5
	_was_frozen = false
	_slow_gain = 0.0
	_main_gain = 1.0
	if _slow != null:
		_slow.stop()
		_slow.stream_paused = false
	if _main != null:
		_main.volume_db = 0.0
	_set_state("running")


func get_player() -> AudioStreamPlayer:
	return _main


func get_slow_player() -> AudioStreamPlayer:
	return _slow


func has_recordings() -> bool:
	return _ready_audio


func current_line() -> Dictionary:
	return _line.duplicate(true)


func vocal_gain_db() -> float:
	return _vocal_db


func update(delta: float, feedback: float = 0.5) -> void:
	if not _started or clock == null or score == null:
		return
	if clock.is_paused():
		if _slow != null:
			_slow.stream_paused = true
		_set_state("paused")
		return
	var frozen: bool = clock.is_song_frozen()
	if _slow != null:
		_slow.stream_paused = false
		if frozen and not _slow.playing:
			_slow.volume_db = -60.0
			_slow.play()
	if _was_frozen and not frozen:
		_main_gain = 0.0
		_set_vocal_target(0.0)
	elif is_finite(feedback) and not is_equal_approx(feedback, _last_feedback):
		_set_vocal_target(-6.0 * clampf((0.5 - feedback) / 0.5, 0.0, 1.0))
	_last_feedback = feedback if is_finite(feedback) else _last_feedback
	_was_frozen = frozen
	_set_state("remedy" if frozen else "running")
	var step: float = maxf(delta, 0.0)
	_slow_gain = move_toward(_slow_gain, 1.0 if frozen else 0.0, step / 0.18)
	_main_gain = move_toward(_main_gain, 1.0, step / 0.12)
	_vocal_db = move_toward(_vocal_db, _vocal_target, step * 20.0)
	if _slow != null:
		_slow.volume_db = linear_to_db(maxf(_slow_gain, 0.001))
		if not frozen and _slow_gain <= 0.0:
			_slow.stop()
	if _main != null:
		_main.volume_db = linear_to_db(maxf(_main_gain, 0.001))
		for i in score.tracks.size():
			var track: Dictionary = score.tracks[i]
			var gain: float = _vocal_db if not str(track["role_id"]).is_empty() else 0.0
			if str(track["asset_id"]) == "instrumental":
				gain = _instrumental_db(clock.get_song_time_ms())
			_sync.set_sync_stream_volume(i, gain)
	var next: Dictionary = score.line_at(clock.get_song_time_ms())
	if str(next.get("line_id", "")) != str(_line.get("line_id", "")):
		_line = next
		_emit("dialogue_line_changed", _line.duplicate(true))


## 前 500 ms 器乐让位，句尾后 600 ms 恢复；锣鼓轨保持独立增益。
func _instrumental_db(song_ms: int) -> float:
	var amount: float = 0.0
	for line in score.lines:
		var begin: int = int(line["start_ms"])
		var end: int = int(line["end_ms"])
		var enter: float = clampf(float(song_ms - begin + 500) / 500.0, 0.0, 1.0)
		var leave: float = clampf(float(end + 600 - song_ms) / 600.0, 0.0, 1.0)
		var weight: float = minf(enter, leave)
		amount = maxf(amount, weight * weight * (3.0 - 2.0 * weight))
	return -9.0 * amount


func _set_vocal_target(value: float) -> void:
	if is_equal_approx(_vocal_target, value):
		return
	var transition_ms: int = int(round(absf(value - _vocal_db) / 20.0 * 1000.0))
	_vocal_target = value
	_emit("vocal_gain_changed", {"target_db": value, "transition_ms": transition_ms})


func _set_state(value: String) -> void:
	if _state == value:
		return
	_state = value
	_emit("audio_state_changed", {"state": value, "recordings_ready": _ready_audio,
		"slow_transition_ms": 180, "main_transition_ms": 120})


func _emit(kind: String, extra: Dictionary) -> void:
	var payload: Dictionary = extra.duplicate(true)
	payload.merge({"real_time_ms": clock.get_real_time_ms(), "sequence": _sequence,
		"audio_version": score.audio_version, "stage_id": score.stage_id}, true)
	_sequence += 1
	_events.append({"time_ms": mini(clock.get_song_time_ms(), score.duration_ms),
		"kind": kind, "object_id": "performance_audio", "cue_id": str(extra.get("cue_id", "")),
		"payload": payload})


func take_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_events)
	_events.clear()
	return out


func stop() -> void:
	if _main != null:
		_main.stream_paused = false
		_main.stop()
	if _slow != null:
		_slow.stream_paused = false
		_slow.stop()
	if not _line.is_empty():
		_line = {}
		_emit("dialogue_line_changed", {})
	if clock != null and score != null:
		_set_state("stopped")
	_started = false


func _exit_tree() -> void:
	stop()
	# 退出时解除流引用；普通收场仍保留素材，以便从零重开。
	if _main != null:
		_main.stream = null
	if _slow != null:
		_slow.stream = null
	_sync = null
