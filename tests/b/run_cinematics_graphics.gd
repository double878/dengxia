extends SceneTree
## 正式入口的实际 Windows 视频/混音回归；第三关录放用真实短演出记录连接。

const GAME := preload("res://scenes/game_flow.tscn")
const OUTPUT := "res://builds/cinematics"
var checks: int = 0
var failures: int = 0
var capture: AudioEffectCapture
var peaks: Dictionary = {}
var game: Node
var output_dir: String


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CINEMATICS: " + label)


func pump(seconds: float, tag: String = "") -> float:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	var peak: float = 0.0
	while Time.get_ticks_msec() < deadline:
		await create_timer(.02).timeout
		for sample: Vector2 in capture.get_buffer(capture.get_frames_available()):
			peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	if not tag.is_empty():
		peaks[tag] = peak
	return peak


func key(code: Key, echo: bool = false, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)


func click(button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = Vector2(300, 250)
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)


func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output_dir + "/" + name + ".png") == OK, name)


func finish_third() -> CPerformanceRecord:
	game._advance_to_act3()
	var host: Node = game._level
	check(host.actions.phase == "ready", "第三关保留原有开场页")
	host.start_scene()
	await pump(.2)
	check(host.capture.finish(), "实际短演出记录合法")
	var record: CPerformanceRecord = host.capture.record
	game._performance_finished(record, 3, "盗仙草")
	await process_frame
	check(game._page.name != "OutroVideo" and game._flow != null, "第三关先选择真实回放")
	return record


func _run() -> void:
	check(
		DisplayServer.get_name() == "Windows" and AudioServer.get_driver_name() == "WASAPI",
		"需要实际 Windows 图形和 WASAPI 混音"
	)
	if failures:
		quit(1)
		return
	output_dir = ProjectSettings.globalize_path(OUTPUT)
	check(DirAccess.make_dir_recursive_absolute(output_dir) == OK, "创建外部验证输出目录")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(0, capture)
	game = GAME.instantiate()
	root.add_child(game)
	await pump(.15)
	check(game._page.name == "HomeScreen" and game._level == null, "启动显示首页，不提前开演")
	check(game._page.size == Vector2(1920, 1080), "首页覆盖完整设计画布")
	await shot("01-home")
	click(MOUSE_BUTTON_WHEEL_UP)
	key(KEY_ENTER, true)
	key(KEY_ENTER, false, false)
	await process_frame
	check(game._page.name == "HomeScreen", "滚轮、连发和松开不启动")
	key(KEY_ENTER)
	await pump(.8, "intro-start")
	check(game._page.name == "IntroVideo" and game._level == null, "任意键启动片头且不提前开演")
	var intro: Node = game._page
	check(intro._player.is_playing(), "Godot 实际播放 Theora")
	await shot("02-intro")
	click()
	key(KEY_A)
	await pump(.15)
	check(game._page == intro, "普通按键与点击不跳过视频")
	key(KEY_SPACE)
	await pump(.2)
	capture.clear_buffer()
	var paused_position: float = intro._player.stream_position
	check(await pump(.25, "intro-paused") < .0001, "视频暂停后实际混音静音")
	check(absf(intro._player.stream_position - paused_position) < .04, "暂停冻结视频位置")
	key(KEY_SPACE, true)
	check(intro._player.paused, "空格连发不反复暂停")
	await shot("03-paused")
	key(KEY_SPACE)
	var deadline: int = Time.get_ticks_msec() + 38000
	var natural_peak: float = 0.0
	while game._page == intro and Time.get_ticks_msec() < deadline:
		natural_peak = maxf(natural_peak, await pump(.08))
	peaks["intro-complete"] = natural_peak
	check(natural_peak > .001, "片头实际混音有原声")
	check(game._level == null and game._page.name == "StageBriefing", "片头自然结束进入第一关简介")
	game._briefing_finished()
	if game._level == null:
		quit(1)
		return
	await shot("04-first-level")
	# 短演出记录只验证第三关接线，完整结尾另由 run_act3_finale 覆盖。
	var record: CPerformanceRecord = await finish_third()
	game._choose_replay(false)
	await pump(.3)
	check(game._page.name == "OutroVideo" and game._flow == null, "不看回放播放片尾并释放记录")
	check(game._page.find_children("*", "Button", true, false).is_empty(), "片尾没有旧收场按钮")
	var outro: Node = game._page
	await shot("05-outro")
	deadline = Time.get_ticks_msec() + 15000
	var outro_peak: float = 0.0
	while not outro._waiting and Time.get_ticks_msec() < deadline:
		outro_peak = maxf(outro_peak, await pump(.08))
	peaks["outro-complete"] = outro_peak
	check(outro_peak > .001 and outro._waiting, "片尾完整自然结束，有实际原声")
	check(outro._image.texture == game.OUTRO_LAST_IMAGE, "片尾保留源视频最后一帧")
	await shot("06-ended")
	key(KEY_ENTER)
	click(MOUSE_BUTTON_WHEEL_DOWN)
	await pump(.1)
	check(game._page == outro, "片尾结束等待鼠标点击，不被按键和滚轮带走")
	click(MOUSE_BUTTON_RIGHT)
	await pump(.1)
	check(game._page.name == "HomeScreen" and game._stage_id == 1, "点击返回首页并重置第一关")
	check(game._level == null and game._flow == null, "返回首页无旧演出或记录")
	await shot("07-home-again")
	click()
	await pump(.15)
	check(game._page.name == "IntroVideo", "鼠标开启新一轮片头，不连跳到第一关")
	key(KEY_ESCAPE)
	await pump(.15)
	check(game._level == null and game._page.name == "StageBriefing", "Esc 跳过片头进入第一关简介")
	game._briefing_finished()
	for route: String in ["skip", "natural"]:
		record = await finish_third()
		game._choose_replay(true)
		check(game._replay != null, route + " 实际加载真实记录的幕前回放")
		if route == "skip":
			game._replay._skip()
		deadline = Time.get_ticks_msec() + 2000
		while game._replay != null and Time.get_ticks_msec() < deadline:
			await pump(.05)
		check(game._replay == null and game._page.name == "OutroVideo", route + " 回放后进入片尾")
		await pump(.1)
		key(KEY_SPACE)
		await process_frame
		check(game._page._player.paused, "片尾也支持暂停")
		key(KEY_ESCAPE)
		await pump(.1)
		check(game._page._waiting and not game._page._player.is_playing(), "暂停时 Esc 也能结束片尾")
		click()
		await pump(.1)
		check(game._page.name == "HomeScreen", route + " 片尾后点击返回且不穿透首页")
	game.queue_free()
	await process_frame
	var rehearsal: Node = GAME.instantiate()
	rehearsal.initial_stage = 3
	root.add_child(rehearsal)
	check(rehearsal._level != null and rehearsal._page == null, "第三关排练入口绕过首页与片头")
	rehearsal.queue_free()
	await process_frame
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	var report := {
		"checks": checks, "failures": failures, "peaks": peaks,
		"display": DisplayServer.get_name(), "audio": AudioServer.get_driver_name(),
		"scope": "Actual complete video playback and mixer; real short act3 records for routing."
	}
	FileAccess.open(output_dir + "/verification.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("CINEMATICS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
