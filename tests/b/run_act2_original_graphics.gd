extends SceneTree
## 自然对白完整实播（保留旧测试入口）：Windows/WASAPI，早到/晚到和暂停。
const Helper := preload("res://tests/c/run_act2_actions.gd")
const OUTPUT := "res://builds/act2-natural-opening-20261017"
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
		push_error("ACT2_NATURAL_WINDOWS: " + message)


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
	await pump(.8, "entry")
	check(opening.on_stage.is_empty(), "空台开场场景错误")
	check(levels.entry.peak > .001 and opening.music_cues.entry.playing, "进入第二关空台即播放视频音乐")
	Helper.key(opening, KEY_ESCAPE)
	var intro_position: float = opening.music_cues.entry.get_playback_position()
	check(await silence() < .001, "出场器乐在菜单暂停时必须实际静音")
	check(absf(opening.music_cues.entry.get_playback_position() - intro_position) < .04, "暂停消耗开场音乐")
	Helper.key(opening, KEY_ESCAPE)
	Helper.key(opening, KEY_1)
	Helper.key(opening, KEY_SPACE)
	Helper.drag(opening, opening.HAND_ANCHOR, Vector2(-400, 0))
	await pump(.1, "arrival")
	check(opening.dialogue.phase == "wait_greeting", "出树后未等待迎接")
	check(await silence() > .001 and opening.dialogue.player.stream_paused, "音乐期间不提前播放对白")
	check(opening.clock.get_song_time_ms() == 0, "迎接等待消耗了首句")
	Helper.key(opening, KEY_2)
	Helper.key(opening, KEY_SPACE)
	var gap: float = opening.controller.get_puppet(0).stage_pos.x * 1920 - 300
	var xu: float = opening.controller.get_puppet(1).stage_pos.x * 1920
	Helper.drag(opening, opening.HAND_ANCHOR, Vector2(gap - xu, 0))
	check(opening.dialogue.phase == "wait_greeting" and opening.clock.is_song_frozen(), "提前迎接不得打断音乐")
	var entry_deadline: int = Time.get_ticks_msec() + 10000
	while opening.dialogue.phase != "dialogue" and Time.get_ticks_msec() < entry_deadline:
		await pump(.03)
	check(opening.dialogue.phase == "dialogue" and opening.music_cues.can_start_main(), "完整音乐结束且实际迎接后才对白")
	check(not opening.music_cues.entry.playing, "开场音乐与对白叠声")
	check(opening.clock.is_audio_driven(), "对白没有使用真实播放器时钟")
	var paused: bool = false
	var missing_tested: bool = false
	var splice_shot: bool = false
	var deadline: int = Time.get_ticks_msec() + int(opening.dialogue.config.duration_ms) + 10000
	while not completed and Time.get_ticks_msec() < deadline:
		await pump(.08)
		var now: int = opening.clock.get_song_time_ms()
		if not missing_tested and now >= int(opening.dialogue.config.lines[1].start_ms) + 500:
			missing_tested = true
			Helper.right(opening, 1)
			await pump(.1, "missing_actor")
			var missing_at: int = opening.clock.get_song_time_ms()
			check(await silence() < .001 and opening.clock.is_song_frozen(), "误退场后对白须实际静音")
			check(opening.clock.get_song_time_ms() == missing_at, "缺场消耗对白")
			Helper.key(opening, KEY_2)
			await pump(.1)
			check(not opening.clock.is_song_frozen(), "回来后未原位续播")
		if not paused and now >= int(opening.dialogue.config.lines[2].start_ms) + 500:
			paused = true
			Helper.key(opening, KEY_ESCAPE)
			var song: int = opening.clock.get_song_time_ms()
			var real_ms: int = opening.clock.get_real_time_ms()
			check(await silence() < .001, "接头前暂停实际输出未静音")
			check(opening.clock.get_song_time_ms() == song, "接头暂停仍推进歌曲")
			check(opening.clock.get_real_time_ms() == real_ms, "接头暂停仍推进真实时间")
			await shot("pause-before-splice")
			Helper.key(opening, KEY_ESCAPE)
		if not splice_shot and now >= int(opening.dialogue.config.lines[4].start_ms) + 1500:
			splice_shot = true
			await shot("second-original")
	check(completed and opening.dialogue.phase == "finished", "对白尾音和暗场未完整结束")
	check(paused and missing_tested and splice_shot, "未覆盖对白暂停、缺场和后续台词")
	check(subtitles.size() == opening.dialogue.config.lines.size(), "未经过全部原片字幕")
	for row: Dictionary in opening.dialogue.config.lines:
		check(float(levels.get(row.line_id, {}).get("peak", 0)) > .001, "原片台词无混音：" + row.line_id)
	check(opening.on_stage.is_empty(), "原片结束没有清场")
	var report := {
		"checks": checks, "failures": failures, "display": DisplayServer.get_name(),
		"audio": AudioServer.get_driver_name(), "levels": levels, "subtitles": subtitles,
		"complete_natural_dialogue_playback": completed, "human_listening_verified": false
	}
	var output := FileAccess.open(OUTPUT + "/windows-playback.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	opening.queue_free()
	await process_frame
	# 晚出场：完整音乐在空台结束，等待及人物重新上下场都不重播。
	opening = load("res://scenes/act2/opening.tscn").instantiate()
	root.add_child(opening)
	await pump(8.5, "late_empty_intro")
	check(opening.music_cues.can_start_main() and not opening.music_cues.entry.playing, "空台开场音乐未完整结束")
	check(opening.clock.get_song_time_ms() == 0 and opening.dialogue.get_line().is_empty(), "晚出场提前消耗对白")
	check(await silence() < .001, "音乐结束后等待不得循环器乐或偷播对白")
	Helper.key(opening, KEY_1)
	Helper.key(opening, KEY_SPACE)
	Helper.drag(opening, opening.HAND_ANCHOR, Vector2(-400, 0))
	await pump(.1, "late_arrival")
	check(opening.dialogue.phase == "wait_greeting" and not opening.music_cues.entry.playing, "晚出场重新播放音乐")
	Helper.key(opening, KEY_2)
	Helper.key(opening, KEY_SPACE)
	gap = opening.controller.get_puppet(0).stage_pos.x * 1920 - 300
	xu = opening.controller.get_puppet(1).stage_pos.x * 1920
	Helper.drag(opening, opening.HAND_ANCHOR, Vector2(gap - xu, 0))
	await pump(1.5, "late_first_line")
	check(opening.dialogue.phase == "dialogue" and levels.late_first_line.peak > .001, "晚迎接后未从首句开始说话")
	check(not opening.music_cues.entry.playing, "晚迎接对白与器乐重叠")
	report.checks = checks
	report.failures = failures
	report.levels = levels
	FileAccess.open(OUTPUT + "/windows-playback.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	opening.queue_free()
	await process_frame
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	print("ACT2_NATURAL_WINDOWS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
