extends Node
class_name Act1OperaAudio
## 表现层消费剧情与唯一 MusicClock，主轨包含自然对白及已通过的唱段。

const MANIFEST_PATH := "res://assets/audio/act1-natural/score.json"
var config: Dictionary = {}
var problems: Array[String] = []
var clock: MusicClock
var flow: Act1OperaFlow
var _main: AudioStreamPlayer
var _wait: AudioStreamPlayer
var _gong: AudioStreamPlayer
var _slow: AudioStreamPlayer
var _line: Dictionary = {}
var _events: Array[Dictionary] = []
var _wait_gain: float = 0.0


static func read_config() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_error("缺少第一幕正式音源清单：%s" % MANIFEST_PATH)
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not (value is Dictionary):
		push_error("第一幕音源清单必须为 JSON 对象")
		return {}
	for key in ["main_path", "wait_loop_path", "take_close_path", "remedy_path", "audio_version"]:
		if str(value.get(key, "")).is_empty():
			push_error("第一幕音源清单缺少：%s" % key)
			return {}
	if not (value.get("lines") is Array) or int(value.get("duration_ms", 0)) <= 0:
		push_error("第一幕音源清单缺少台词或时长")
		return {}
	var previous_end := 0
	var ids := {}
	for item: Variant in value.lines:
		if not (item is Dictionary):
			push_error("第一幕台词格式错误")
			return {}
		var id := str(item.get("line_id", ""))
		var begin := int(item.get("start_ms", -1))
		var end := int(item.get("end_ms", -1))
		if id.is_empty() or ids.has(id) or str(item.get("text", "")).is_empty() \
				or begin < previous_end or end <= begin or end > int(value.duration_ms) \
				or str(item.get("delivery", "")) not in ["speech", "singing"]:
			push_error("第一幕台词缺失、重叠或时间越界：%s" % id)
			return {}
		ids[id] = true
		previous_end = end
	return value


func setup(value: Dictionary, p_clock: MusicClock, p_flow: Act1OperaFlow) -> bool:
	config = value
	clock = p_clock
	flow = p_flow
	for key in ["main", "wait_loop", "take_close", "remedy"]:
		var path: String = str(config.get(key + "_path", ""))
		if not ResourceLoader.exists(path):
			problems.append("缺少正式音源：%s" % path)
			continue
		var stream: Variant = load(path)
		if not (stream is AudioStreamWAV):
			problems.append("须为 PCM WAV：%s" % path)
			continue
		var wav: AudioStreamWAV = stream
		if wav.mix_rate != 48000 or wav.format != AudioStreamWAV.FORMAT_16_BITS \
				or wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			problems.append("须为无循环 48k/16-bit WAV：%s" % path)
		if key == "main" and absf(wav.get_length() * 1000.0 - float(config.duration_ms)) > 1.0:
			problems.append("主轨长度与时间表不一致")
		var player := AudioStreamPlayer.new()
		player.name = "Act1_" + key
		player.stream = wav
		if key in ["wait_loop", "remedy"]:
			var loop: AudioStreamWAV = wav.duplicate()
			loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
			loop.loop_end = int(round(loop.get_length() * 48000.0))
			player.stream = loop
		add_child(player)
		match key:
			"main": _main = player
			"wait_loop": _wait = player
			"take_close": _gong = player
			"remedy": _slow = player
	return problems.is_empty()


func get_player() -> AudioStreamPlayer:
	return _main


func update(events: Array = [], delta: float = 1.0 / 60.0) -> void:
	for event in events:
		if str(event.get("kind", "")) == "opera_take_close":
			_gong.play()
	var paused := clock.is_paused()
	_wait.stream_paused = paused
	_gong.stream_paused = paused
	_slow.stream_paused = paused
	if paused:
		return
	if flow.is_waiting():
		if not _wait.playing:
			_wait.volume_db = -60.0
			_wait.play()
	_wait_gain = move_toward(_wait_gain, 1.0 if flow.is_waiting() else 0.0, maxf(delta, 0.0) / 0.08)
	_wait.volume_db = linear_to_db(maxf(_wait_gain, 0.001))
	if not flow.is_waiting() and _wait_gain <= 0.0:
		_wait.stop()
	if clock.is_song_frozen() and not flow.is_waiting():
		if not _slow.playing:
			_slow.play()
	else:
		_slow.stop()
	var next: Dictionary = {}
	var now := clock.get_song_time_ms()
	for line: Dictionary in config.lines:
		if now >= int(line.start_ms) and now < int(line.end_ms):
			next = line
			break
	if str(next.get("line_id", "")) != str(_line.get("line_id", "")):
		_line = next.duplicate(true)
		_events.append({"time_ms": now, "kind": "dialogue_line_changed",
			"object_id": "performance_audio", "cue_id": "", "payload":
			_line.merged({"real_time_ms": clock.get_real_time_ms(),
			"audio_version": config.audio_version, "stage_id": 1})})


func current_line() -> Dictionary:
	return _line.duplicate(true)


func take_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


func stop() -> void:
	for player in [_main, _wait, _gong, _slow]:
		if player != null:
			player.stream_paused = false
			player.stop()
	_line = {}
	_wait_gain = 0.0


func _exit_tree() -> void:
	stop()
	for player in [_main, _wait, _gong, _slow]:
		if player != null:
			player.stream = null
