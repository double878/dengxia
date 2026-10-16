extends SceneTree
## Windows 图形/混音：连续播放 135s 至整轨结束，并显示同次结尾的真实幕前回放。
const Helper := preload("res://tests/c/run_act2_actions.gd")
const Story := preload("res://tests/c/run_act3_story.gd")
const Capture := preload("res://scripts/c/c_act3_capture.gd")
const OUTPUT := "res://builds/act3-finale"
var checks: int = 0
var failures: int = 0
var screenshots: Array[String] = []
var levels: Dictionary = {}
var capture: AudioEffectCapture


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ACT3_FINALE_WINDOWS: " + label)


func shot(label: String) -> void:
	for _i in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	check(
		root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png") == OK, "保存 " + label
	)
	screenshots.append(label)


func pump(seconds: float, label: String) -> float:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	var peak: float = 0.0
	while Time.get_ticks_msec() < deadline:
		await create_timer(.015).timeout
		for sample: Vector2 in capture.get_buffer(capture.get_frames_available()):
			peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	levels[label] = peak
	return peak


func to_song(host: Node, target: int, label: String, silent: bool = false) -> void:
	var deadline: int = (
		Time.get_ticks_msec() + maxi(0, target - host.clock.get_song_time_ms()) + 5000
	)
	var peak: float = 0.0
	var audio_driven: bool = true
	while host.clock.get_song_time_ms() < target and Time.get_ticks_msec() < deadline:
		await create_timer(.015).timeout
		audio_driven = audio_driven and host.clock.is_audio_driven()
		for sample: Vector2 in capture.get_buffer(capture.get_frames_available()):
			peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	levels[label] = peak
	check(host.clock.get_song_time_ms() >= target, label + " 原声时钟持续推进")
	check(audio_driven, label + " 时钟由实际声音播放驱动，无设备停摆降级")
	if silent:
		check(peak < .001, label + " 无对白停顿中没有背景音乐")
	else:
		check(peak > .001, label + " 真实混音非静音")


func _run() -> void:
	check(
		DisplayServer.get_name() != "headless" and AudioServer.get_driver_name() != "Dummy",
		"Windows 实际渲染与声音设备"
	)
	if failures:
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2
	AudioServer.add_bus_effect(0, capture)
	var game: Node = load("res://scenes/game_flow.tscn").instantiate()
	game.initial_stage = 3
	root.add_child(game)
	var host: Node = game._level
	host.set_process(false)
	host.start_scene()
	host.audio.player.stop()
	host.clock.set_player(null)
	Helper.key(host, KEY_1)
	Story.move_to(host, 0, .56)
	Story.advance(host, 135.0 - host.clock.get_song_time_s())
	# 只在探针中把录制起点重置到 135s；随后整段通过声卡实时连续播放。
	host.capture = Capture.new()
	host.clock.set_player(host.audio.player)
	host.clock.start(135000)
	host.capture.capture(host)
	host.set_process(true)
	await to_song(host, 136200, "before-arrival-splice")
	await shot("01-crane-duel")
	var finale_config: Dictionary = host.audio.config.finale
	await to_song(host, int(finale_config.stop_ms) + 340, "across-arrival-splice")
	check(host.finale.active and host.fight.active_actor == -1, "仙翁喝止自动停战")
	await shot("02-elder-arrival")
	Helper.key(host, KEY_ESCAPE)
	var frozen: Dictionary = host.finale.recorded_view()
	await pump(.2, "pause-drain")
	capture.clear_buffer()
	check(await pump(.4, "paused") < .001, "暂停使真实混音静音")
	check(host.finale.recorded_view() == frozen, "暂停冻结仙翁真实画面")
	Helper.key(host, KEY_ESCAPE)
	await to_song(host, int(finale_config.gift_ms) - 1100, "gathering")
	check(host.on_stage == [0, 1, 2], "仙翁与三人同时在场")
	await shot("03-four-actors")
	await to_song(host, int(finale_config.gift_ms) + 500, "across-blessing-splice", true)
	check(host.finale.herb_owner == -1 and host.finale.gift_progress == 0, "第二段原声直接说话，不递草")
	await shot("04-elder-speaking")
	Story.move_to(host, 0, .30)
	Story.move_to(host, 0, .31)
	await to_song(host, int(finale_config.gift_ms) + 3200, "no-herb")
	check(host.finale.herb_owner == -1 and host.fight.draw_progress == 0, "白素贞空手且剑已归鞘")
	await shot("05-foreground-lineup")
	await to_song(host, int(finale_config.advice_ms) + 400, "elder-advice")
	check(host.controller.get_puppet(0).stage_pos.x < host.finale.elder.stage_pos.x, "玩家把白素贞移到最左边")
	check(host.finale.elder.stage_pos.x < host.controller.get_puppet(2).stage_pos.x, "仙翁位于鹤童左边")
	check(
		host.controller.get_puppet(2).stage_pos.x < host.controller.get_puppet(1).stage_pos.x,
		"鹤童位于鹿童左边"
	)
	check(host._finale_view.puppet.figure_height < host._views[1].figure_height, "仙翁按可见轮廓缩小至双童相近身高")
	await shot("06-return-to-zhenjiang")
	await to_song(host, int(finale_config.farewell_ms) + 100, "farewell-start")
	# 测试玩家自己的谢礼输入，演出逻辑不代演。
	Helper.take(host, 0)
	var white: PuppetState = host.controller.get_puppet(0)
	Helper.drag(host, host._views[0].torso_screen_position(), Vector2(55 * white.facing, 0), true)
	await to_song(host, int(finale_config.farewell_ms) + 1100, "farewell")
	check(white.torso_lean > .25, "谢礼输入在结尾仍可操作")
	await shot("07-player-farewell")
	var record: CPerformanceRecord = host.capture.record
	await pump(
		(int(host.audio.config.duration_ms) - host.clock.get_song_time_ms()) / 1000.0 + 1.0,
		"complete-original-tail"
	)
	check(
		game._level != null and game._flow == null and host.actions.phase == "awaiting_exit",
		"原声结束保持舞台，等待玩家离场"
	)
	Helper.key(host, KEY_W)
	host.set_process(false)
	Story.advance(host, .2)
	check(white.air_height > 0, "片尾 W 实际跳起")
	await shot("07-jump-exit")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.position = host._views[0].head_screen_position()
	host._input(event)
	check(not host.on_stage.has(0), "空中右键白素贞实际退场")
	host.capture.capture(host)
	await shot("07-departed")
	host.set_process(true)
	await pump(.15, "departure-close")
	check(game._level == null and game._flow != null, "玩家离场后显示观看选择")
	check(record.validate_invariants().is_empty(), "实际 Windows 记录合法")
	await shot("08-official-replay-choice")
	game._choose_replay(true)
	var replay: Node = game._replay
	replay.set_process(false)
	var player: CReplayPlayer = game._flow.get_player()
	for label: String in ["advice", "farewell"]:
		for snapshot: CSnapshot in record.snapshots:
			var f: Dictionary = snapshot.performance.finale
			if f.phase != label:
				continue
			if (
				label == "advice"
				and snapshot.performance.song_ms < int(finale_config.gift_ms) + 3000
			):
				continue
			var frame: Dictionary = player.sample(snapshot.time_ms)
			frame.state = &"playing"
			replay.apply_frame(frame)
			check(replay._act3_view.finale_view.data == f, "幕前读取同次仙翁和灵芝数据")
			check(await pump(.35, "replay-" + label) > .001, "幕前读取原声位置 " + label)
			await shot("09-replay-" + label)
			break
	game._skip_replay()
	await shot("10-result")
	game.queue_free()
	await process_frame
	AudioServer.remove_bus_effect(0, 0)
	var out := FileAccess.open(OUTPUT + "/verification.json", FileAccess.WRITE)
	(
		out
		. store_string(
			(
				JSON
				. stringify(
					{
						"checks": checks,
						"failures": failures,
						"levels": levels,
						"screenshots": screenshots,
						"audio_driver": AudioServer.get_driver_name(),
						"scope":
						"Continuous playback from 135s through the new 175.288s ending, except menu pause; elder selections use extracted original voice without backing; real Windows rendering and mixer; same-session recorded finale replay. Not a human listening assessment."
					},
					"\t"
				)
			)
		)
	)
	print("ACT3_FINALE_WINDOWS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
