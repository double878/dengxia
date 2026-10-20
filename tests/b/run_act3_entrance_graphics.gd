extends SceneTree
## Windows 实时原声混音、跳跃、暂停、恢复和落地证据。
const Helper := preload("res://tests/c/run_act2_actions.gd")
const Story := preload("res://tests/c/run_act3_story.gd")
const OUTPUT := "res://builds/act3-entrance"
var checks: int = 0
var failures: int = 0
var capture: AudioEffectCapture
var levels: Dictionary = {}
var jump_song_ms: int = -1


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ACT3_ENTRANCE_WINDOWS: " + label)


func pump(seconds: float, label: String) -> float:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	var peak: float = 0.0
	while Time.get_ticks_msec() < deadline:
		await create_timer(.04).timeout
		for sample: Vector2 in capture.get_buffer(capture.get_frames_available()):
			peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	levels[label] = peak
	return peak


func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	check(
		root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png") == OK, "截图 " + label
	)


func _run() -> void:
	check(
		DisplayServer.get_name() != "headless" and AudioServer.get_driver_name() != "Dummy",
		"使用真实 Windows 图形和音频设备"
	)
	if failures:
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(0, capture)
	var host: Node = load("res://scenes/act3/opening.tscn").instantiate()
	root.add_child(host)
	check(await pump(.3, "playbill") < .001, "戏单等待没有提前播放")
	host.start_scene()
	check(await pump(1.0, "empty_stage_start") > .001, "白素贞未上场时已有原声混音")
	await shot("empty-stage-music")
	await pump(13.0, "empty_stage_prelude")
	check(
		host.clock.get_song_time_ms() > 13000 and not host.clock.is_song_frozen(), "空山原声持续越过旧入场等待点"
	)
	Helper.key(host, KEY_1)
	Story.move_to(host, 0, .56)
	check(not host.on_stage.has(1), "提前靠山不提前出山")
	var cue_ms: int = int(host.audio.config.gates[1].at_ms)
	await pump((cue_ms - host.clock.get_song_time_ms()) / 1000.0 - .20, "wait_final_accent")
	check(not host.on_stage.has(1), "真实音频重音之前仍隐藏鹿童")
	await pump(.28, "jump")
	check(host.on_stage.has(1) and host.controller.get_puppet(1).stage_pos.y < .57, "真实窗口中鹿童已跳起")
	for frame: CSnapshot in host.capture.record.snapshots:
		if frame.performance.on_stage.has(1) and frame.puppets[1].stage_pos.y * 1080.0 < 641.0:
			jump_song_ms = int(frame.performance.song_ms)
			break
	check(jump_song_ms >= cue_ms and jump_song_ms <= cue_ms + 70, "实际起跳与末尾重音对齐")
	await shot("jump")
	Helper.key(host, KEY_ESCAPE)
	var position: Vector2 = host.controller.get_puppet(1).stage_pos
	var song: int = host.clock.get_song_time_ms()
	await pump(.25, "pause_drain")
	capture.clear_buffer()
	check(await pump(.45, "paused") < .001, "暂停后真实混音静音")
	check(
		(
			host.controller.get_puppet(1).stage_pos == position
			and host.clock.get_song_time_ms() == song
		),
		"暂停保持跳跃位置与歌曲时间"
	)
	Helper.key(host, KEY_ESCAPE)
	check(await pump(.95, "resumed") > .001, "继续后恢复原声混音")
	check(
		(
			not host.guard_entrance.active
			and absf(host.controller.get_puppet(1).stage_pos.y * 1080 - 642) < .01
		),
		"继续后完整落地"
	)
	check(
		host.controller.get_puppet(1).stage_pos.x * 1920 < host.guard_entrance._edge_x - 100,
		"实际落点在山缘外保留身体宽度"
	)
	await shot("landed")
	var singing_from: int = host.clock.get_song_time_ms()
	check(await pump(24, "free_singing") > .001, "跳出后不做关键动作也持续输出真实唱腔")
	check(
		(
			host.clock.get_song_time_ms() > singing_from + 23000
			and not host.actions.waiting
			and not host.actions.remedy.has_open_windows()
		),
		"原退步抬掌时点不能停唱或开启补救"
	)
	Helper.right(host, 1)
	host.lamp_controller.lamp.exposure = .1
	singing_from = host.clock.get_song_time_ms()
	check(await pump(1.2, "free_exit_dark") > .001, "鹿童退场和压暗时仍有真实唱腔")
	check(host.clock.get_song_time_ms() > singing_from + 1000, "自由退场压暗不冻结歌曲时间")
	Helper.key(host, KEY_2)
	host.lamp_controller.lamp.exposure = .7
	await shot("free-performance")
	var record: CPerformanceRecord = host.capture.record
	check(host.capture.finish(), "实时时间记录收尾通过")
	host.queue_free()
	await process_frame
	await pump(.2, "exit_drain")
	capture.clear_buffer()
	check(await pump(.3, "exited") < .001, "退出场次停止原声")
	var flow := CResultFlow.new()
	check(flow.offer_replay(record, 3), "幕前装载同一次演出")
	flow.choose_replay(true)
	var replay: Node = load("res://scripts/b/performance_replay.gd").new()
	replay.flow = flow
	replay.stage_id = 3
	root.add_child(replay)
	check(await pump(.8, "replay_start") > .001, "幕前从空山开头播放实际原声")
	replay.toggle_pause()
	await pump(.2, "replay_pause_drain")
	capture.clear_buffer()
	check(await pump(.4, "replay_paused") < .001, "幕前暂停实际静音")
	replay.toggle_pause()
	check(await pump(.5, "replay_resumed") > .001, "幕前继续恢复原声")
	replay.stop()
	replay.queue_free()
	await process_frame
	AudioServer.remove_bus_effect(0, 0)
	var output := FileAccess.open(OUTPUT + "/verification.json", FileAccess.WRITE)
	output.store_string(
		JSON.stringify(
			{
				"checks": checks,
				"failures": failures,
				"levels": levels,
				"jump_song_ms": jump_song_ms,
				"jump_cue_ms": cue_ms,
				"audio_driver": AudioServer.get_driver_name()
			},
			"\t"
		)
	)
	print("ACT3_ENTRANCE_WINDOWS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
