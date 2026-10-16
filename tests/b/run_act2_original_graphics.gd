extends SceneTree
## 完整原声实时播放回归：真实 Windows/WASAPI，不改歌曲时间和播放速度。
const Helper := preload("res://tests/c/run_act2_actions.gd")
const OUTPUT := "res://builds/act2-xuxian-voice-20261016"
var opening: Node
var capture: AudioEffectCapture
var checks: int = 0
var failures: int = 0
var levels: Dictionary = {}
var subtitles: Dictionary = {}
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ACT2_ORIGINAL_WINDOWS: " + message)


func pump(seconds: float, tag: String = "") -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		await create_timer(.03).timeout
		var key: String = tag
		if key.is_empty():
			var line: Dictionary = opening.dialogue.get_line()
			key = str(line.get("line_id", opening.dialogue.phase))
			if not line.is_empty():
				subtitles[key] = line.text
		var row: Dictionary = levels.get(key, {"frames": 0, "peak": 0.0})
		for sample: Vector2 in capture.get_buffer(capture.get_frames_available()):
			row.frames += 1
			row.peak = maxf(row.peak, maxf(absf(sample.x), absf(sample.y)))
		levels[key] = row


func silence() -> float:
	await create_timer(.25).timeout
	capture.clear_buffer()
	await create_timer(.35).timeout
	var peak: float = 0
	for sample: Vector2 in capture.get_buffer(capture.get_frames_available()):
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	return peak


func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT + "/" + name + ".png") == OK, "截图 " + name)


func _run() -> void:
	check(DisplayServer.get_name() == "Windows", "需要真实 Windows 图形设备")
	check(AudioServer.get_driver_name() == "WASAPI", "需要真实 WASAPI 音频输出")
	if failures:
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2
	AudioServer.add_bus_effect(0, capture)
	opening = load("res://scenes/act2/opening.tscn").instantiate()
	root.add_child(opening)
	opening.scene_finished.connect(func(): completed = true)
	Helper.key(opening, KEY_1)
	await pump(.8, "entry")
	check(levels.entry.peak < .001 and not opening.music_cues.entry.playing, "法海入场应保持静音")
	Helper.key(opening, KEY_SPACE)
	Helper.drag(opening, opening.HAND_ANCHOR, Vector2(-400, 0))
	await pump(.1, "arrival")
	check(opening.dialogue.phase == "wait_greeting", "出树后未等待迎接")
	check(await silence() < .001, "迎接前原声漏播")
	check(opening.clock.get_song_time_ms() == 0, "迎接等待消耗了首句")
	Helper.key(opening, KEY_2)
	Helper.key(opening, KEY_SPACE)
	var gap: float = opening.controller.get_puppet(0).stage_pos.x * 1920 - 300
	var xu: float = opening.controller.get_puppet(1).stage_pos.x * 1920
	Helper.drag(opening, opening.HAND_ANCHOR, Vector2(gap - xu, 0))
	check(opening.dialogue.phase == "dialogue", "实际迎接未启动原声")
	check(opening.clock.is_audio_driven(), "原声没有使用真实播放器时钟")
	var paused: bool = false
	var splice_shot: bool = false
	var deadline: int = Time.get_ticks_msec() + 110000
	while not completed and Time.get_ticks_msec() < deadline:
		await pump(.08)
		var now: int = opening.clock.get_song_time_ms()
		if not paused and now >= int(opening.dialogue.config.splice_ms) - 500:
			paused = true
			Helper.key(opening, KEY_ESCAPE)
			var song: int = opening.clock.get_song_time_ms()
			var real_ms: int = opening.clock.get_real_time_ms()
			check(await silence() < .001, "接头前暂停实际输出未静音")
			check(opening.clock.get_song_time_ms() == song, "接头暂停仍推进歌曲")
			check(opening.clock.get_real_time_ms() == real_ms, "接头暂停仍推进真实时间")
			await shot("pause-before-splice")
			Helper.key(opening, KEY_ESCAPE)
		if not splice_shot and now >= int(opening.dialogue.config.splice_ms) + 1500:
			splice_shot = true
			await shot("second-original")
	check(completed and opening.dialogue.phase == "finished", "原声尾音和暗场未完整结束")
	check(paused and splice_shot, "没有覆盖实际接头")
	check(subtitles.size() == opening.dialogue.config.lines.size(), "未经过全部原片字幕")
	for row: Dictionary in opening.dialogue.config.lines:
		check(float(levels.get(row.line_id, {}).get("peak", 0)) > .001, "原片台词无混音：" + row.line_id)
	check(opening.on_stage.is_empty(), "原片结束没有清场")
	var report := {
		"checks": checks, "failures": failures, "display": DisplayServer.get_name(),
		"audio": AudioServer.get_driver_name(), "levels": levels, "subtitles": subtitles,
		"complete_original_playback": completed, "human_listening_verified": false
	}
	var output := FileAccess.open(OUTPUT + "/windows-playback.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	opening.queue_free()
	await process_frame
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	print("ACT2_ORIGINAL_WINDOWS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
