extends SceneTree
## Windows 实时片段探针：在片段衔接前定位，然后真实播放到新片末尾。
const Helper := preload("res://tests/c/run_act2_actions.gd")
const Story := preload("res://tests/c/run_act3_story.gd")
const Capture := preload("res://scripts/c/c_act3_capture.gd")
const OUTPUT := "res://builds/act3-fight"
var checks: int = 0
var failures: int = 0
var levels: Dictionary = {}
var capture: AudioEffectCapture
var screenshots: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ACT3_FIGHT_WINDOWS: " + label)


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
	screenshots.append(label)


func _run() -> void:
	check(
		DisplayServer.get_name() != "headless" and AudioServer.get_driver_name() != "Dummy",
		"真实窗口与音频设备"
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
	await shot("01-playbill")
	host.start_scene()
	check(await pump(.6, "empty_stage") > .001, "空山开演已有原声")
	# 前段时长与等待另由正式剧情回归覆盖；本探针真实听验后续约 42 秒。
	host.set_process(false)
	host.audio.player.stop()
	host.clock.set_player(null)
	Helper.key(host, KEY_1)
	Story.move_to(host, 0, .56)
	Story.advance(host, int(host.audio.config.gates[1].at_ms) / 1000.0 + 1.2)
	check(host.guard_entrance.triggered and not host.guard_entrance.active, "先完成真实出山再检查打戏")
	if not host.guard_entrance.triggered:
		host.queue_free()
		quit(1)
		return
	Story.advance(host, 98.8 - host.clock.get_song_time_s())
	host.capture = Capture.new()
	host.clock.set_player(host.audio.player)
	host.clock.start(98800)
	host.set_process(true)
	check(await pump(.45, "before_splice") > .001, "接续前原声有真实混音")
	check(host.fight.draw_progress == 0.0, "唱词前剑仍在鞘中")
	await shot("02-sheathed")
	check(await pump(3.5, "splice_and_draw") > .001, "连续播放跨越片段接续和拔剑唱词")
	check(host.fight.draw_progress == 1.0, "真实播放到唱词后自动出鞘")
	Story.raise_hand(host, 0, Vector2(180, -240))
	var white: PuppetState = host.controller.get_puppet(0)
	var hand: Vector2 = white.hand_angle
	var elbow: Vector2 = white.elbow_angle
	await shot("03-deer-duel")
	Helper.key(host, KEY_ESCAPE)
	var position: Vector2 = host.controller.get_puppet(1).stage_pos
	await pump(.2, "pause_drain")
	capture.clear_buffer()
	check(await pump(.35, "paused") < .001, "菜单暂停后真实混音静音")
	check(host.controller.get_puppet(1).stage_pos == position, "暂停保持双童动作")
	Helper.key(host, KEY_ESCAPE)
	check(await pump(.5, "resumed") > .001, "恢复后继续同一条原声")
	await pump(15.5, "deer_to_crane")
	check(not host.on_stage.has(1), "鹿童按唱词退场")
	await pump(3, "crane_entrance")
	check(host.on_stage.has(2), "鹤童自动接战")
	await shot("04-crane-entrance")
	Story.move_to(host, 0, .3)
	var old_x: float = host.controller.get_puppet(2).stage_pos.x
	check(await pump(5, "crane_duel") > .001, "鹤童交手期间原声持续")
	check(host.controller.get_puppet(2).stage_pos.x < old_x, "鹤童跟随玩家调整距离")
	await shot("05-crane-duel")
	check(await pump(10.5, "no_fall_lyric") > .001, "保留视频后半段唱腔")
	check(white.hand_angle == hand and white.elbow_angle == elbow, "唱词不接管白素贞手势")
	check(
		absf(white.stage_pos.y * 1080.0 - 642.0) < .01 and host._views[0].fall_angle == 0.0,
		"整段没有强制跌倒"
	)
	await shot("06-no-fall")
	await pump(4, "source_end")
	check(host.actions.phase == "free_performance" and host.finale.active and not host._emitted, "打戏接仙翁，保持同一场")
	check(host.capture.finish(), "实际窗口三人演出记录合法")
	var record: CPerformanceRecord = host.capture.record
	host.queue_free()
	await process_frame
	var flow := CResultFlow.new()
	check(flow.offer_replay(record, 3), "同次记录可供幕前回放")
	flow.choose_replay(true)
	var replay: Node = load("res://scripts/b/performance_replay.gd").new()
	replay.flow = flow
	replay.stage_id = 3
	root.add_child(replay)
	replay.set_process(false)
	var player: CReplayPlayer = flow.get_player()
	for snapshot: CSnapshot in record.snapshots:
		if snapshot.performance.get("fight_phase") == "crane_duel":
			var frame: Dictionary = player.sample(snapshot.time_ms)
			frame.state = &"playing"
			replay.apply_frame(frame)
			check(await pump(.5, "replay_crane") > .001, "幕前鹤童段读取原声位置")
			check(replay._act3_view.swords[0].draw_progress == 1.0, "幕前保留白素贞持剑")
			await shot("07-replay")
			break
	replay.stop()
	replay.queue_free()
	await process_frame
	AudioServer.remove_bus_effect(0, 0)
	var output := FileAccess.open(OUTPUT + "/verification.json", FileAccess.WRITE)
	(
		output
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
						"Real-time playback from 98.8s through supplied material end; opening covered separately."
					},
					"\t"
				)
			)
		)
	)
	print("ACT3_FIGHT_WINDOWS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
