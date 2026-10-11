extends SceneTree
## 同一正式入口的完整接还伞演出；带窗口时按实际音频时间跑完整幕及回放。

var game: Node
var harness: Level1Harness
var checks: int = 0
var failures: int = 0
var visited_qing: bool = false
var arrival_wait_start: int = -1
var take_wait_start: int = -1
var return_wait_start: int = -1
var phase: String = "live"
var record: CPerformanceRecord
var replay_pause_wall: int = -1
var paused_once: bool = false
var graphics: bool = false
var sample_wall: int = 0
var frame_times: Array[float] = []
var last_opera_phase: String = ""
var observed_gongs: int = 0
var handoff_x: float = 0.0


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SUCCESS_REPLAY: " + label)


func _run() -> void:
	graphics = DisplayServer.get_name() != "headless"
	game = load("res://scenes/game_flow.tscn").instantiate()
	root.add_child(game)
	harness = game._level._harness
	var xuxian: PuppetState = harness.runtime.puppet_controller.get_puppet(UmbrellaController.XUXIAN_ID)
	var join: Vector2 = UmbrellaController.join_window_x(xuxian.stage_pos.x)
	handoff_x = (join.x + join.y) * 0.5
	game._level.set_process(false)
	if not graphics:
		harness.opera_audio.stop()
		harness.clock.set_player(null)
		for _i in range(18000):
			if phase == "done": break
			_step(1.0 / 60.0)
		await _finish()
	else:
		root.show()
		sample_wall = Time.get_ticks_msec()
		await capture("success-opening")


func _process(delta: float) -> bool:
	if graphics and game != null and phase != "done":
		frame_times.append(delta)
		_step(delta)
		if phase == "done":
			call_deferred("_finish")
	return false


func _step(delta: float) -> void:
	if phase == "live":
		_automate(delta)
		harness.advance(delta)
		harness.take_events()
		game._level._refresh_ui()
		game._level.queue_redraw()
		if harness.runtime.is_over():
			_key(KEY_A, false)
			_key(KEY_S, false)
			record = harness.capture.record
			game._level._process(0)
			check(game._flow.get_flow_state() == &"choice", "接还伞后没有选择页")
			check(record.validate_invariants().is_empty(), "接还伞记录无效")
			for kind: String in ["umbrella_take", "umbrella_return", "opera_take_close"]:
				check(record.events.any(func(e: Variant) -> bool: return str(e.kind) == kind), "缺少 " + kind)
			check(record.duration_ms > 111811, "实际等待没有增加时长")
			check(record.snapshots.any(func(s: Variant) -> bool: return bool(s.performance.umbrella.get("handing_off", false))), "未记录递伞过渡")
			phase = "choice"
			if graphics: call_deferred("_start_replay")
			else: _start_replay()
	elif phase == "replay":
		var flow: CResultFlow = game._flow
		if game._replay != null:
			observed_gongs = game._replay._audio.replay_gong_count
		if flow.is_replaying():
			if not paused_once and flow.get_player().get_now_ms() > 2000:
				game._replay.toggle_pause()
				paused_once = true
				replay_pause_wall = Time.get_ticks_msec()
			elif replay_pause_wall >= 0 and (not graphics or Time.get_ticks_msec() - replay_pause_wall >= 700):
				game._replay.toggle_pause()
				replay_pause_wall = -1
			if not graphics:
				game._replay._process(delta)
		else:
			check(flow.get_flow_state() == &"result", "完整回放没有回收场")
			check(flow.get_player().get_dispatched_event_count() == record.events.size(), "回放漏事件")
			check(flow.get_player().get_now_ms() == record.duration_ms, "回放时长不一致")
			check(observed_gongs == 1, "回放收锣没有且仅有一次")
			phase = "done"


func _automate(delta: float) -> void:
	var opera: Act1OperaFlow = harness.opera_flow
	var real: int = harness.clock.get_real_time_ms()
	var bai: PuppetState = harness.runtime.puppet_controller.get_puppet(0)
	if opera.phase != last_opera_phase:
		print("AUTOMATION phase=%s real=%d song=%d x=%.3f hand=%.3f A=%s" % [opera.phase, real, harness.clock.get_song_time_ms(), bai.stage_pos.x, bai.hand_angle.x, Input.is_key_pressed(KEY_A)])
		last_opera_phase = opera.phase
	var goal: float = bai.stage_pos.x
	if opera.phase == "wait_arrival":
		if arrival_wait_start < 0: arrival_wait_start = real
		if real - arrival_wait_start > 800: goal = handoff_x
	elif opera.phase == "wait_take":
		if take_wait_start < 0: take_wait_start = real
		_key(KEY_A, real - take_wait_start > 700)
	elif opera.taken and not opera.returned:
		_key(KEY_A, false)
		if not visited_qing:
			goal = 0.80
			visited_qing = bai.stage_pos.x >= 0.79
		elif opera.phase == "wait_return":
			if return_wait_start < 0: return_wait_start = real
			if real - return_wait_start > 700:
				goal = handoff_x
				_key(KEY_S, true)
	elif opera.returned:
		_key(KEY_S, true)
	var controller: PuppetController = harness.runtime.puppet_controller
	if absf(goal - bai.stage_pos.x) > 0.0001:
		if not controller.is_dragging():
			controller.begin_drag(0, Vector2(bai.stage_pos.x * 1920, bai.stage_pos.y * 1080 - 45))
		var target: float = move_toward(bai.stage_pos.x, goal, 0.22 * delta)
		controller.drag_to(Vector2((target - bai.stage_pos.x) * 1920, 0))
	elif controller.is_dragging():
		controller.end_drag()


func _key(code: Key, pressed: bool) -> void:
	if Input.is_key_pressed(code) == pressed: return
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _start_replay() -> void:
	await capture("success-choice")
	game._choose_replay(true)
	if not graphics:
		game._replay.set_process(false)
		game._flow.get_player().set_clock_source(CReplayPlayer.CLOCK_SOURCE_DELTA)
	phase = "replay"
	if graphics:
		await capture("success-front")


func capture(label: String) -> void:
	if not graphics: return
	for _i in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/stage-walk")
	check(root.get_texture().get_image().save_png("res://builds/stage-walk/%s.png" % label) == OK, "保存截图")


func _finish() -> void:
	check(phase == "done", "验证未完成完整演出/回放")
	if graphics and not frame_times.is_empty():
		frame_times.sort()
		print("FRAME p50=%.2fms p95=%.2fms samples=%d" % [frame_times[frame_times.size() / 2] * 1000,
			frame_times[int(frame_times.size() * 0.95)] * 1000, frame_times.size()])
	game.queue_free()
	await process_frame
	print("SUCCESS_REPLAY checks=%d failures=%d duration=%d" % [checks, failures, record.duration_ms if record != null else 0])
	quit(1 if failures else 0)
