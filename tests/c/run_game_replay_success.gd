extends SceneTree
## 同一正式入口的完整借伞演出（2026-10-16 流程：唱完 → 借伞 → 回到小青身旁 → 结束）；
## 带窗口时按实际音频时间跑完整幕及回放。

var game: Node
var harness: Level1Harness
var checks: int = 0
var failures: int = 0
var visited_qing: bool = false
var phase: String = "live"
var record: CPerformanceRecord
var config: Dictionary = {}
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
	config = Act1OperaAudio.read_config()
	game = load("res://scenes/game_flow.tscn").instantiate()
	root.add_child(game)
	harness = game._level._harness
	var xuxian: PuppetState = harness.runtime.puppet_controller.get_puppet(
		UmbrellaController.XUXIAN_ID
	)
	var join: Vector2 = UmbrellaController.join_window_x(xuxian.stage_pos.x)
	handoff_x = (join.x + join.y) * 0.5
	game._level.set_process(false)
	if not graphics:
		harness.opera_audio.stop()
		harness.clock.set_player(null)
		for _i in range(18000):
			if phase == "done":
				break
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
			check(game._flow.get_flow_state() == &"choice", "借伞收关后没有选择页")
			check(record.validate_invariants().is_empty(), "借伞记录无效")
			for kind: String in ["umbrella_take", "opera_take_close"]:
				check(
					record.events.any(func(e: Variant) -> bool: return str(e.kind) == kind),
					"缺少 " + kind
				)
			# 2026-10-16 流程简化后本关**不再还伞**：多出一条还伞事件就是流程回退了。
			check(
				not record.events.any(func(e: Variant) -> bool: return str(e.kind) == "umbrella_return"),
				"本关不应再产生 umbrella_return"
			)
			# 记录时长取**真实耗时**（CLiveCapture 口径）。⚠️「回到小青身旁」会把歌曲时钟
			# 直接跳到 closing_ms，本轨因此跳掉约 8.3 s 的过场，真实耗时**必然短于整轨**；
			# 这条同时防住两种回归：跳过头把尾奏整段吞掉、或根本没跳让玩家干等过场。
			check(
				(
					record.duration_ms > int(config.opening_end_ms)
					and record.duration_ms < int(config.duration_ms)
				),
				(
					"实际耗时 %d 应落在 (唱段结束 %d, 整轨 %d) 内"
					% [record.duration_ms, int(config.opening_end_ms), int(config.duration_ms)]
				)
			)
			var is_handoff: Callable = func(s: Variant) -> bool:
				return bool(s.performance.umbrella.get("handing_off", false))
			check(record.snapshots.any(is_handoff), "未记录递伞过渡")
			phase = "choice"
			if graphics:
				call_deferred("_start_replay")
			else:
				_start_replay()
	elif phase == "replay":
		var flow: CResultFlow = game._flow
		if game._replay != null:
			observed_gongs = game._replay._audio.replay_gong_count
		if flow.is_replaying():
			if not paused_once and flow.get_player().get_now_ms() > 2000:
				game._replay.toggle_pause()
				paused_once = true
				replay_pause_wall = Time.get_ticks_msec()
			elif (
				replay_pause_wall >= 0
				and (not graphics or Time.get_ticks_msec() - replay_pause_wall >= 700)
			):
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
		print(
			(
				"AUTOMATION phase=%s real=%d song=%d x=%.3f hand=%.3f A=%s"
				% [
					opera.phase,
					real,
					harness.clock.get_song_time_ms(),
					bai.stage_pos.x,
					bai.hand_angle.x,
					Input.is_key_pressed(KEY_A)
				]
			)
		)
		last_opera_phase = opera.phase
	var goal: float = bai.stage_pos.x
	if opera.taken:
		# 接到伞：立刻**向左**走回小青身旁（x ≤ TURN_POINT_X 即本关完成条件）。
		_key(KEY_A, false)
		if not visited_qing:
			# 目标刻意**越过**阈值 0.04：`move_toward` 若把目标设成恰好 0.32，
			# 位置会停在阈值右侧、`is_at_home()` 永远不成立（实测就是她卡在窗口中心、
			# 由时间轴到 closing_ms 才收场，真实耗时等于整轨）。
			# 🔴 符号随站位翻面：2026-10-16 定案后「回到小青身旁」是**向左**走，
			#    旧写法 `TURN_POINT_X + 0.04` 是「向右走」时代的（那时阈值 0.74 在右侧），
			#    照抄会让自动化永远不往回走——这一条就是被实际耗时对不上抓出来的。
			goal = UmbrellaController.TURN_POINT_X - 0.04
			visited_qing = bai.stage_pos.x <= goal
		# 归位收关后时钟跳到 closing_ms，再等 0.7 s 放下双手收势（对 l1_opera_lower_hand）。
		_key(KEY_S, harness.clock.get_song_time_ms() >= int(config.closing_ms) + 700)
	elif opera.phase == "opening":
		# 唱段（带字幕）期间玩家不操作，跟着听即可。
		_key(KEY_A, false)
	else:
		# 唱完了：**向右**走进交接窗口（她在柳树下 0.32，许仙在桥头），并把左手抬到打伞位。
		goal = handoff_x
		_key(KEY_A, absf(bai.stage_pos.x - handoff_x) < 0.03)
	var controller: PuppetController = harness.runtime.puppet_controller
	if absf(goal - bai.stage_pos.x) > 0.0001:
		if not controller.is_dragging():
			controller.begin_drag(0, Vector2(bai.stage_pos.x * 1920, bai.stage_pos.y * 1080 - 45))
		var target: float = move_toward(bai.stage_pos.x, goal, 0.22 * delta)
		controller.drag_to(Vector2((target - bai.stage_pos.x) * 1920, 0))
	elif controller.is_dragging():
		controller.end_drag()


func _key(code: Key, pressed: bool) -> void:
	if Input.is_key_pressed(code) == pressed:
		return
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
	if not graphics:
		return
	for _i in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/stage-walk")
	check(
		root.get_texture().get_image().save_png("res://builds/stage-walk/%s.png" % label) == OK,
		"保存截图"
	)


func _finish() -> void:
	check(phase == "done", "验证未完成完整演出/回放")
	if graphics and not frame_times.is_empty():
		frame_times.sort()
		print(
			(
				"FRAME p50=%.2fms p95=%.2fms samples=%d"
				% [
					frame_times[frame_times.size() / 2] * 1000,
					frame_times[int(frame_times.size() * 0.95)] * 1000,
					frame_times.size()
				]
			)
		)
	game.queue_free()
	await process_frame
	print(
		(
			"SUCCESS_REPLAY checks=%d failures=%d duration=%d"
			% [checks, failures, record.duration_ms if record != null else 0]
		)
	)
	quit(1 if failures else 0)
