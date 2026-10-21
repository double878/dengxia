extends SceneTree
## 两场真实操演记录 → 观看选择 → 幕前回放 → 收场 → 盗仙草入口。
const Helper := preload("res://tests/c/run_act2_actions.gd")
const GAME := preload("res://scenes/game_flow.tscn")
var checks: int = 0
var failures: int = 0
var game: Node
var record: CPerformanceRecord
var frames: Dictionary = {}
var live: bool = false


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ACT2_REPLAY: " + label)


func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/act2-replay")
	check(
		root.get_texture().get_image().save_png("res://builds/act2-replay/" + name + ".png") == OK,
		"截图 " + name
	)


func _run() -> void:
	live = DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("live")
	game = GAME.instantiate()
	game.set("_stage_id", 2)
	root.add_child(game)
	game._briefing_finished()  # 两场演出测试从确认简介后开始。
	var opening: Node = game.get("_level")
	opening.set_process(live)
	check(opening.get("capture") != null, "正式第二关第一场没有整关录制")
	if opening.get("capture") == null:
		game.queue_free()
		await process_frame
		quit(1)
		return
	if not live:
		opening.dialogue.player.stop()
		opening.clock.set_player(null)
	record = opening.capture.record
	check(record.snapshots[0].time_ms == 0, "第二关首帧不在零点")
	check(record.snapshots[0].performance.audio.entry.playing, "零点快照须包含空台开场音乐")
	Helper.key(opening, KEY_1)
	Helper.key(opening, KEY_SPACE)
	opening._process(1.0 / 60.0)
	frames.entry = record.snapshots[-1].time_ms
	if live:
		await create_timer(1.5).timeout
	else:
		for _i in range(90):
			opening._process(1.0 / 60.0)
	Helper.drag(opening, opening.HAND_ANCHOR, Vector2(-400, 0))
	check(opening.dialogue.phase == "wait_greeting", "真实走出树后才允许许仙迎接")
	var guard: int = 0
	while opening.dialogue.phase != "wait_greeting" and guard < 1200:
		await tick(opening)
		guard += 1
	check(guard < 1200, "第一场首句结束无法进入迎接等待")
	Helper.key(opening, KEY_2)
	Helper.key(opening, KEY_SPACE)
	if not live:
		# 快速录制用自由时钟；真实完整开场音乐另由 Windows 实播覆盖。
		opening.music_cues.entry.stop()
		opening.music_cues.entry.finished.emit()
	var greeting_x: float = opening.controller.get_puppet(0).stage_pos.x * 1920.0 - 300.0
	var xu_x: float = opening.controller.get_puppet(1).stage_pos.x * 1920.0
	Helper.drag(opening, opening.HAND_ANCHOR, Vector2(greeting_x - xu_x, 0))
	guard = 0
	var opening_limit: int = ceili(float(opening.dialogue.config.duration_ms + 5000) / 1000 * 60)
	while opening.dialogue.phase != "finished" and guard < opening_limit:
		await tick(opening)
		guard += 1
	check(guard < opening_limit, "第一场不能正常走完")
	if live:
		await create_timer(1.7).timeout
	else:
		for _i in range(100):
			opening._process(1.0 / 60.0)
	check(game.get("_flow") == null, "两场之间不能出现观看选择")
	await process_frame
	var hall: Node = game.get("_level")
	check(hall != opening and hall.scene_file_path.ends_with("hall.tscn"), "第一场收尾未进厅堂")
	if hall == opening:
		game.queue_free()
		await process_frame
		quit(1)
		return
	hall.set_process(live)
	if not live:
		Helper.deterministic_clock(hall)
	check(hall.capture.record == record, "换场丢失第一場记录")
	check(record.snapshots[-1].performance.scene_id == 22, "厅堂首帧未录制")
	frames.seated = record.snapshots[-1].time_ms
	check(hall.actions.phase == "duet" and hall.on_stage == [0, 1], "厅堂首帧直接双人对唱")
	var before: int = record.snapshots.size()
	var time_before: int = hall.clock.get_real_time_ms()
	Helper.key(hall, KEY_ESCAPE)
	await advance(hall, 3)
	check(
		record.snapshots.size() == before and hall.clock.get_real_time_ms() == time_before,
		"菜单暂停不得延长记录"
	)
	Helper.key(hall, KEY_ESCAPE)
	await advance(hall, 1.2)
	frames.duet = record.snapshots[-1].time_ms
	check(await until_phase(hall, "cup", 50), "完整对唱后才开放取杯")
	await advance(hall, 8.2)
	check(hall.remedy.active(), "真实等待触发补救")
	frames.remedy = record.snapshots[-1].time_ms
	Helper.take(hall, 1)
	Helper.drag(
		hall,
		hall._views[1].hand_screen_position("right"),
		Vector2(1035, 415) - hall._views[1].hand_screen_position("right")
	)
	Helper.drag(hall, hall._views[1].torso_screen_position(), Vector2(-152, 0))
	await advance(hall, .2)
	Helper.take(hall, 0)
	var offered: Vector2 = hall._views[1].hand_screen_position(hall.actions.cup_hand)
	Helper.drag(
		hall,
		hall._views[0].hand_screen_position("left"),
		offered - hall._views[0].hand_screen_position("left")
	)
	check(hall.actions.cup_owner == 0, "真实递杯给白素贞")
	frames.cup = record.snapshots[-1].time_ms
	Helper.drag(
		hall,
		hall._views[0].hand_screen_position("left"),
		hall._views[0].mouth_screen_position() - hall._views[0].hand_screen_position("left")
	)
	await advance(hall, .8)
	Helper.drag(hall, hall._views[0].torso_screen_position(), Vector2(75, 0), true)
	check(hall.actions.bent, "饮后真实弯腰")
	check(await until_phase(hall, "medicine_exit", 15), "弯腰后两句对白")
	Helper.take(hall, 1)
	Helper.drag(hall, hall._views[1].torso_screen_position(), Vector2(740, 0))
	Helper.right(hall, 1)
	hall.lamp_controller.lamp.exposure = .1
	await advance(hall, .1)
	Helper.right(hall, 0)
	Helper.key(hall, KEY_4)
	Helper.key(hall, KEY_SPACE)
	# 白蛇真实分节姿态也必须进入记录。
	hall.snake.drag_head(hall.snake.head_position() + Vector2(-35, 25))
	hall.snake.move(Vector2(20, 0))
	hall.lamp_controller.lamp.exposure = .8
	await advance(hall, .2)
	frames.snake = record.snapshots[-1].time_ms
	var before_reset: CSnapshot = record.snapshots[-1]
	var reset_index: int = record.snapshots.size()
	Helper.key(hall, KEY_R)
	await advance(hall, .05)
	var snake_reset_ms: int = record.snapshots[reset_index].time_ms
	Helper.key(hall, KEY_2)
	Helper.take(hall, 1)
	Helper.drag(hall, hall._views[1].torso_screen_position(), Vector2(-690, 0))
	await advance(hall, float(hall.audio.config.fright_duration_ms) / 1000.0 + 1.8)
	check(hall.actions.phase == "finished" and game.get("_flow") == null, "倒地后保留收势再显示选择")
	frames.fallen = record.snapshots[-1].time_ms
	await advance(hall, 3)
	await process_frame
	var flow: CResultFlow = game.get("_flow")
	check(flow != null and flow.get_flow_state() == &"choice", "第二幕结束没有观看选择")
	if flow == null:
		game.queue_free()
		await process_frame
		quit(1)
		return
	check(game.get("_stage_id") == 2, "结果应属于第二关而非场次22")
	check(not flow.is_replaying(), "回放不能自动开始")
	check(record.validate_invariants().is_empty(), "第二关记录不变量")
	check(record.snapshots[-1].time_ms == record.duration_ms, "收势末帧和时长不一致")
	check(
		record.snapshots.any(func(s: Variant) -> bool: return s.performance.scene_id == 2),
		"整关回放不能漏法海劝酒"
	)
	var waits: Array = record.snapshots.filter(
		func(s: Variant) -> bool:
			return s.performance.scene_id == 22 and s.performance.phase == "cup"
	)
	check(waits[-1].time_ms - waits[0].time_ms >= 8100, "等待与补救被压缩")
	check(
		record.events.any(func(e: Variant) -> bool: return str(e.kind) == "remedy_open"), "补救事件丢失"
	)
	await shot("choice")
	game._choose_replay(true)
	var replay: Node = game.get("_replay")
	replay.set_process(false)
	var player: CReplayPlayer = flow.get_player()
	player.set_clock_source(CReplayPlayer.CLOCK_SOURCE_DELTA)
	var matches: Callable = func(s: Variant) -> bool:
		var sampled: Dictionary = player.sample(s.time_ms)
		return sampled.performance == s.performance and sampled.puppets == s.puppets
	check(record.snapshots.all(matches), "逐采样点录放字段不一致")
	check(
		(
			player.sample(snake_reset_ms - 1).performance.snake.points
			== before_reset.performance.snake.points
		),
		"白蛇复位前不能预插值改变蛇颈"
	)
	if DisplayServer.get_name() != "headless":
		await audio_probe(replay, player)
		if live or OS.get_cmdline_user_args().has("realtime"):
			await wall_playback(replay, flow)
			game._watch_replay()
			replay = game.get("_replay")
			replay.set_process(false)
			player = flow.get_player()
			player.set_clock_source(CReplayPlayer.CLOCK_SOURCE_DELTA)
	for name: String in frames:
		replay.apply_frame(player.sample(frames[name]))
		check(replay.get("_surface").front_view, "必须使用幕前镜像")
		var view: Node = replay.get("_act2_view")
		var performance: Dictionary = player.sample(frames[name]).performance
		check(view.scene_id == performance.scene_id, "回放布景场次 " + name)
		if name == "entry":
			check(replay.get("_surface").projection_views[0].skin_override == 3, "法海不能被显示成白素贞")
			check(not view.binding.enable_rain, "第二关回放不能添加雨幕")
		elif name == "seated":
			check(
				(
					replay.get("_surface").projection_views[0].seated
					and replay.get("_surface").projection_views[1].seated
				),
				"回放两人对坐"
			)
		elif name == "cup":
			check(view.cup_data.cup_owner == 0 and view.cup.visible, "动态杯归属")
		elif name == "snake":
			check(
				view.snake_view.visible and view.snake.recorded_view() == performance.snake,
				"完整白蛇分节录放"
			)
		elif name == "fallen":
			check(replay.get("_surface").projection_views[1].fall_angle > 1.4, "回放不能让许仙重新站立")
		await shot("front-" + name)
	var boundary: CSnapshot = record.snapshots.filter(func(s: Variant) -> bool: return s.performance.scene_id == 22)[0]
	check(player.sample(boundary.time_ms - 1).performance.scene_id == 2, "不能提前换景")
	game._unhandled_input(_click())
	check(game.get("_stage_id") == 2, "回放中点击不能跳关")
	replay._process(.2)
	replay.toggle_pause()
	var frozen: int = player.get_now_ms()
	replay._process(2)
	check(player.get_now_ms() == frozen, "回放暂停仍推进")
	replay.toggle_pause()
	replay._process(.2)
	check(player.get_now_ms() > frozen, "回放无法继续")
	game._skip_replay()
	check(flow.get_flow_state() == &"result", "跳过后应回收场")
	await shot("result")
	game._watch_replay()
	game.get("_replay").set_process(false)
	game.get("_replay")._process(float(record.duration_ms) / 1000.0 + 1)
	check(flow.get_flow_state() == &"result", "自然结束应回收场")
	# 按钮事件已处理，不应立即跳关；收场后新的任意点击才前进。
	await process_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.position = Vector2(4, 4)
	click.pressed = true
	game._unhandled_input(click)
	game._unhandled_input(click)
	await process_frame
	check(
		(
			game.get("_stage_id") == 3
			and game.get("_level").scene_file_path == "res://scenes/act3/opening.tscn"
		),
		"收场点击没有进入盗仙草入口或重复跳关"
	)
	check(flow.is_released, "进入下一关没有释放第二关记录")
	await shot("act3-opening")
	game.queue_free()
	await process_frame
	# 独立覆盖不看回放：真实记录提供给同一宿主，不能自动前进。
	game = GAME.instantiate()
	game.set("_stage_id", 22)
	root.add_child(game)
	game._briefing_finished()  # 两场演出测试从确认简介后开始。
	game._performance_finished(record, 2, "端阳惊变")
	game._choose_replay(false)
	check(
		game.get("_flow").get_flow_state() == &"result" and game.get("_stage_id") == 2, "不看回放应停在收场"
	)
	game._unhandled_input(_click())
	check(not game.get("_advancing"), "选择按钮同帧的点击不能透传跳关")
	await process_frame
	click.button_index = MOUSE_BUTTON_MIDDLE
	game._unhandled_input(click)
	await process_frame
	check(game.get("_stage_id") == 3, "不看回放后点击不能进入下一关")
	game.queue_free()
	await process_frame
	print(
		(
			"ACT2_REPLAY checks=%d failures=%d duration=%d snapshots=%d events=%d"
			% [checks, failures, record.duration_ms, record.snapshots.size(), record.events.size()]
		)
	)
	quit(1 if failures else 0)


func _click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func audio_probe(replay: Node, player: CReplayPlayer) -> void:
	check(AudioServer.get_driver_name() != "Dummy", "Windows 回放需要真实音频设备")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2
	AudioServer.add_bus_effect(0, capture)
	var speech: CSnapshot = record.snapshots.filter(_opening_speech)[0]
	var sound_frames := frames.duplicate()
	sound_frames.speech = speech.time_ms
	sound_frames.fallen = record.snapshots.filter(_hit_start)[0].time_ms
	sound_frames.remedy = record.snapshots.filter(_remedy_start)[0].time_ms
	var report := {
		"display": DisplayServer.get_name(), "audio": AudioServer.get_driver_name(), "peaks": {}
	}
	for key: String in ["entry", "speech", "remedy", "duet", "fallen", "cup"]:
		replay.get("_act2_audio").stop()
		await create_timer(.15).timeout
		capture.clear_buffer()
		replay.apply_frame(player.sample(int(sound_frames[key])))
		# 重音与补救第一拍很短，采集起音，不能先丢掉前250毫秒。
		# 视频开头原有约600ms静音，entry采到首个重音；其他短音效仍采集起音。
		await create_timer(1.1 if key == "entry" else .6).timeout
		var peak: float = buffer_peak(capture)
		report.peaks[key] = peak
		check(peak < .001 if key == "cup" else peak > .001, "实际回放混音/等待静音 " + key)
		if key == "speech":
			check(not replay.get("_act2_audio").players.entry.playing, "回放法海开口必须停止视频音乐")
		if key == "duet":
			var waiting: CSnapshot = record.snapshots.filter(_hall_wait)[0]
			replay.apply_frame(player.sample(waiting.time_ms))
			replay.apply_frame(player.sample(int(frames.duet)))
			check(await mix_peak(capture) > .001, "动作等待后恢复对唱实际有声")
	player.play()
	var flow: CResultFlow = game.get("_flow")
	replay.apply_frame(flow.advance(float(frames.duet) / 1000))
	replay.toggle_pause()
	check(await mix_peak(capture) < .001, "暂停回放必须实际静音")
	var paused_at: int = player.get_now_ms()
	await RenderingServer.frame_post_draw
	var frozen: PackedByteArray = root.get_texture().get_image().get_data()
	await create_timer(.2).timeout
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().get_data() == frozen, "暂停幕前画面逐像素冻结")
	replay.toggle_pause()
	check(await mix_peak(capture) > .001 and player.get_now_ms() == paused_at, "恢复回放从原处响起")
	replay.stop()
	check(await mix_peak(capture) < .001, "离开回放停止全部声音")
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	DirAccess.make_dir_recursive_absolute("res://builds/act2-replay")
	FileAccess.open("res://builds/act2-replay/windows-audio.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)


func _opening_speech(s: CSnapshot) -> bool:
	return (
		s.performance.scene_id == 2
		and s.performance.phase == "dialogue"
		and s.performance.song_ms > 1000
	)


func mix_peak(capture: AudioEffectCapture) -> float:
	await create_timer(.25).timeout
	capture.clear_buffer()
	await create_timer(.35).timeout
	return buffer_peak(capture)


func buffer_peak(capture: AudioEffectCapture) -> float:
	var peak: float = 0.0
	for sample: Vector2 in capture.get_buffer(capture.get_frames_available()):
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	return peak


func _hall_wait(s: CSnapshot) -> bool:
	return s.performance.scene_id == 22 and s.performance.phase == "cup"


func _hit_start(s: CSnapshot) -> bool:
	return s.performance.scene_id == 22 and bool(s.performance.audio.hit.playing)


func _remedy_start(s: CSnapshot) -> bool:
	return s.performance.scene_id == 22 and bool(s.performance.audio.slow.playing)


func wall_playback(replay: Node, flow: CResultFlow) -> void:
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2
	AudioServer.add_bus_effect(0, capture)
	var player: CReplayPlayer = flow.get_player()
	player.set_clock_source(CReplayPlayer.CLOCK_SOURCE_WALL)
	player.play()
	replay.set_process(true)
	var begin_ms: int = Time.get_ticks_msec()
	var scenes_seen: Dictionary = {}
	var line_peaks: Dictionary = {}
	var hit_starts: int = 0
	var hit_playing: bool = false
	while flow.is_replaying() and Time.get_ticks_msec() - begin_ms < record.duration_ms + 5000:
		await create_timer(.03).timeout
		if not is_instance_valid(replay):
			break
		var frame: Dictionary = replay.get("_last_frame")
		var view: Dictionary = frame.get("performance", {})
		scenes_seen[str(view.get("scene_id", 0))] = true
		var audio: Node = replay.get("_act2_audio")
		var playing: bool = audio.players.hit.playing
		if playing and not hit_playing:
			hit_starts += 1
		hit_playing = playing
		var line: String = str(view.get("subtitle", ""))
		line_peaks[line] = maxf(float(line_peaks.get(line, 0)), buffer_peak(capture))
	var elapsed: int = Time.get_ticks_msec() - begin_ms
	check(flow.get_flow_state() == &"result", "实时完整回放自然进入收场")
	check(absi(elapsed - record.duration_ms) < 1000, "完整回放按1:1实际时长播放")
	check(scenes_seen.has("2") and scenes_seen.has("22"), "实时回放完整播放两场")
	check(hit_starts == 1, "实时许仙惊叫实际只播放一次")
	for manifest: String in [
		"res://assets/audio/act2-opening/score.json", "res://assets/audio/act2-hall/score.json"
	]:
		var score: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest))
		var lines: Array = score.lines.duplicate()
		lines.append_array(score.get("duet", []))
		for line: Dictionary in lines:
			var text: String = "%s：%s" % [line.role_name, line.text]
			# 厅堂直接从对唱开始；清单前五句仅保留为历史音源。
			if int(line.start_ms) < int(score.get("duet_start_ms", 0)):
				check(not line_peaks.has(text), "已删除的厅堂前置对白不得回放 " + str(line.line_id))
			else:
				check(float(line_peaks.get(text, 0)) > .001, "实时录放台词有声 " + str(line.line_id))
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	FileAccess.open("res://builds/act2-replay/realtime.json", FileAccess.WRITE).store_string(
		JSON.stringify(
			{
				"duration_ms": record.duration_ms,
				"elapsed_ms": elapsed,
				"scenes": scenes_seen,
				"hit_starts": hit_starts,
				"line_peaks": line_peaks
			},
			"  "
		)
	)
	print(
		(
			"ACT2_REPLAY_WALL duration=%d elapsed=%d hit_starts=%d"
			% [record.duration_ms, elapsed, hit_starts]
		)
	)


func tick(host: Node) -> void:
	if live:
		await create_timer(1.0 / 60.0).timeout
	else:
		host._process(1.0 / 60.0)


func advance(host: Node, seconds: float) -> void:
	if live:
		await create_timer(seconds).timeout
	else:
		Helper.advance(host, seconds)


func until_phase(host: Node, expected: String, limit: float) -> bool:
	if not live:
		return Helper.until_phase(host, expected, limit)
	var deadline: int = Time.get_ticks_msec() + int(limit * 1000)
	while host.actions.phase != expected and Time.get_ticks_msec() < deadline:
		await create_timer(.04).timeout
	return host.actions.phase == expected
