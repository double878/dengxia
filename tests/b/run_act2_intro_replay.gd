extends SceneTree
## 实际空台静音录制，再按真实时长回放；不注入完成事件或自由时钟。
const Capture := preload("res://scripts/c/c_act2_capture.gd")
const ReplayAudio := preload("res://scripts/b/act2_replay_audio.gd")
var checks: int = 0
var failures: int = 0
var capture: AudioEffectCapture
var peaks := {"live": 0.0, "replay": 0.0}


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ACT2_INTRO_REPLAY: " + message)


func mix_peak(tag: String) -> void:
	for sample: Vector2 in capture.get_buffer(capture.get_frames_available()):
		peaks[tag] = maxf(peaks[tag], maxf(absf(sample.x), absf(sample.y)))


func _run() -> void:
	check(DisplayServer.get_name() == "Windows" and AudioServer.get_driver_name() == "WASAPI", "需要真实 Windows/WASAPI")
	if failures:
		quit(1)
		return
	capture = AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(0, capture)
	var opening: Node = load("res://scenes/act2/opening.tscn").instantiate()
	opening.capture = Capture.new()
	root.add_child(opening)
	var recording: RefCounted = opening.capture
	var record: CPerformanceRecord = recording.record
	var expected_ms: int = int(opening.dialogue.config.intro_duration_ms)
	check(expected_ms == 100 and opening.dialogue.config.get("background_music", true) == false, "开场仅保留100ms静音控制片段")
	var deadline: int = Time.get_ticks_msec() + expected_ms + 3000
	while opening.clock.get_real_time_ms() < expected_ms + 400 and Time.get_ticks_msec() < deadline:
		await create_timer(.02).timeout
		mix_peak("live")
	check(recording.finish(), "实际音乐记录不完整")
	check(peaks.live < .001, "空台实际录制不得有背景音乐")
	check(record.snapshots[0].time_ms == 0 and record.snapshots[0].performance.audio.entry.playing, "零点未记录音乐")
	var ended_ms: int = -1
	var final_playing_ms: int = 0
	for snapshot: CSnapshot in record.snapshots:
		check(snapshot.performance.song_ms == 0, "空台音乐期间消耗了对白")
		if snapshot.performance.audio.entry.playing:
			final_playing_ms = snapshot.time_ms
		elif ended_ms < 0:
			ended_ms = snapshot.time_ms
	check(absi(ended_ms - expected_ms) < 200, "实际音乐未完整记录到结束：%d/%d" % [ended_ms, expected_ms])
	check(final_playing_ms > expected_ms - 200, "音乐记录提前截断")
	opening.queue_free()
	await process_frame
	await create_timer(.2).timeout
	capture.clear_buffer()
	var audio: Node = ReplayAudio.new()
	root.add_child(audio)
	audio.setup()
	var player := CReplayPlayer.new(record)
	player.play()
	var begun: int = Time.get_ticks_msec()
	deadline = begun + record.duration_ms + 3000
	while player.get_now_ms() < record.duration_ms and Time.get_ticks_msec() < deadline:
		var frame: Dictionary = player.advance(.02)
		var view: Dictionary = frame.get("performance", {})
		audio.apply_recorded(int(view.get("scene_id", 2)), view.get("audio", {}), false)
		await create_timer(.02).timeout
		mix_peak("replay")
	check(player.get_now_ms() == record.duration_ms, "完整音乐回放未走到终点")
	check(absi(Time.get_ticks_msec() - begun - record.duration_ms) < 200, "开场回放未按1:1实际时长")
	check(peaks.replay < .001, "空台实际回放不得有背景音乐")
	check(not audio.players.entry.playing and not audio.players.opening.playing, "音乐结束后等待仍响声")
	var report := {"checks": checks, "failures": failures, "intro_ms": expected_ms,
		"recorded_end_ms": ended_ms, "record_duration_ms": record.duration_ms, "peaks": peaks,
		"audio": AudioServer.get_driver_name(), "display": DisplayServer.get_name()}
	DirAccess.make_dir_recursive_absolute("res://builds/no-background-audio-20261022")
	FileAccess.open("res://builds/no-background-audio-20261022/intro-replay.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	audio.queue_free()
	await process_frame
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	print("ACT2_INTRO_REPLAY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
