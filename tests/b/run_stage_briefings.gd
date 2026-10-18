extends SceneTree
## Windows 实际画面/混音与真实入口检查；无头也可跑流程与边界。

const GAME := preload("res://scenes/game_flow.tscn")
const Briefing := preload("res://scripts/ui/stage_briefing.gd")
var checks: int = 0
var failures: int = 0
var capture: AudioEffectCapture
var output_dir: String
var peaks: Dictionary = {}
var graphics: bool
var game: Node


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("STAGE_BRIEFINGS: " + label)


func pump(seconds: float) -> float:
	var peak: float = 0.0
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		await create_timer(.02).timeout
		if capture != null:
			for sample: Vector2 in capture.get_buffer(capture.get_frames_available()):
				peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	return peak


func click(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.pressed = pressed
		# position 来自 1920×1080 的逻辑画布，不是缩放后窗口的屏幕坐标。
		root.push_input(event, true)


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)


func check_card(card: Control, stage_id: int) -> void:
	check(card is Briefing and card.stage_id == stage_id, "第 %d 关使用统一简介" % stage_id)
	check(card.get_node("Title").text == Briefing.BRIEFINGS[stage_id].title, "标题与关卡对应")
	check(not card.get_node("Story").text.is_empty(), "简介包含剧情和行动目标")
	for node_name: String in ["Title", "Story", "Controls", "AudioNote", "StartScene"]:
		var item := card.get_node(node_name) as Control
		check(Rect2(Vector2.ZERO, card.size).encloses(item.get_rect()), node_name + " 位于画布内")
		check(item.position.y + item.size.y <= 1000, node_name + " 未越出底部")
	check(card.get_node("Story").get_rect().end.y <= card.get_node("Controls").position.y, "剧情与操作不重叠")
	check(card.get_node("Controls").get_rect().end.y <= card.audio_note.position.y, "操作与声音不重叠")
	if graphics:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output_dir + "/stage-%d.png" % stage_id) == OK, "保存实际简介截图")
	if capture != null:
		await pump(.15)
		capture.clear_buffer()
	peaks[str(stage_id)] = await pump(.3)
	check(float(peaks[str(stage_id)]) < .0001, "简介等待期间静音")
	click(Vector2(20, 20))
	for code: Key in [KEY_1, KEY_A, KEY_SPACE, KEY_ESCAPE]:
		key(code)
	await process_frame
	check(card.is_visible_in_tree(), "背景点击和操演按键不越过简介")


func start_card(card: Control) -> void:
	var button := card.get_node("StartScene") as Button
	click(button.get_global_rect().get_center())
	await process_frame
	await process_frame
	await pump(.08)


func _run() -> void:
	graphics = DisplayServer.get_name() != "headless"
	output_dir = ProjectSettings.globalize_path("res://builds/stage-briefings")
	DirAccess.make_dir_recursive_absolute(output_dir)
	if graphics:
		check(DisplayServer.get_name() == "Windows" and AudioServer.get_driver_name() == "WASAPI", "实际 Windows / WASAPI")
		capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(0, capture)
	game = GAME.instantiate()
	root.add_child(game)
	check(game._page.name == "HomeScreen", "首页保留")
	game._intro_finished()
	var card: Control = game._page
	await check_card(card, 1)
	check(game._level == null, "第一关简介期间未建立演出宿主、时钟和记录")
	await start_card(card)
	check(game._page == null and game._level != null, "第一关点击开演才建立演出")
	if game._level == null:
		quit(1)
		return
	var first: Node = game._level
	game._briefing_finished()
	check(game._level == first, "重复开演不会创建第二个宿主")
	check(first._harness.clock.get_real_time_ms() < 500, "第一关从零起步，不计简介阅读时间")
	check(first._harness.capture.record.snapshots[0].time_ms == 0, "第一关记录从零开始")
	game._skip_act1()
	await process_frame
	await process_frame
	card = game._page
	await check_card(card, 2)
	check(game._level == null and game._act2_capture == null, "第二关简介期间未播放音乐或采集记录")
	await start_card(card)
	var opening: Node = game._level
	check(opening != null and game._page == null, "第二关点击开演才进入法海劝酒")
	if opening == null:
		quit(1)
		return
	check(opening.on_stage.is_empty(), "开演点击不使人物误上场")
	check(opening.clock.get_real_time_ms() < 500, "第二关时钟从开演起步")
	check(game._act2_capture.record.snapshots[0].time_ms == 0, "第二关记录从零开始")
	game._advance_to_act2_hall()
	check(game._page == null and game._stage_id == 22, "厅堂场间换景不重复简介")
	game._skip_act2()
	await process_frame
	await process_frame
	var third: Node = game._level
	card = third._card
	await check_card(card, 3)
	check(third.clock.get_real_time_ms() == 0 and third.capture.record.snapshots.is_empty(), "第三关简介保持零时钟、无演出记录")
	check(game._page == null, "第三关没有额外叠一张简介")
	await start_card(card)
	check(third._started and not card.visible, "第三关同一开演按钮启动现有演出")
	check(third.capture.record.snapshots[0].time_ms == 0, "第三关记录仍从零开始")
	game.queue_free()
	await process_frame
	if capture != null:
		AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	var report := {"checks": checks, "failures": failures, "peaks": peaks, "display": DisplayServer.get_name(), "audio": AudioServer.get_driver_name()}
	FileAccess.open(output_dir + "/verification.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("STAGE_BRIEFINGS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
