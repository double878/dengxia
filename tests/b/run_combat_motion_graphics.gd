extends SceneTree
## Windows 实际渲染/混音探针；输入走正式宿主，录放读取同次状态。
const Helper := preload("res://tests/c/run_act2_actions.gd")
const Story := preload("res://tests/c/run_act3_story.gd")
const OUTPUT := "res://builds/combat-motion"
const THIRD_SCENE := preload("res://scenes/act3/opening.tscn")
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
		push_error("COMBAT_WINDOWS: " + label)


func shot(label: String) -> void:
	for _i in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	check(
		root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png") == OK, "保存 " + label
	)
	screenshots.append(label)


func fixed(host: Node, seconds: float) -> void:
	for _i in range(roundi(seconds * 60)):
		host._process(1.0 / 60.0)


func pump(seconds: float, label: String) -> float:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	var peak: float = 0.0
	while Time.get_ticks_msec() < deadline:
		await create_timer(.015).timeout
		for sample: Vector2 in capture.get_buffer(capture.get_frames_available()):
			peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	levels[label] = peak
	return peak


func dispose(host: Node) -> void:
	root.remove_child(host)
	host.queue_free()
	await process_frame


func _run() -> void:
	check(
		DisplayServer.get_name() != "headless" and AudioServer.get_driver_name() != "Dummy",
		"Windows 渲染与实际音频设备"
	)
	if failures:
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2
	AudioServer.add_bus_effect(0, capture)
	if not OS.get_cmdline_user_args().has("only-act3"):
		await first_act()
		await second_act()
	await third_act()
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
						"Scripted keyboard/mouse in Windows; live source audio around draw/jump/dodge; six deterministic NPC pose previews and actual-record replay."
					},
					"\t"
				)
			)
		)
	)
	print("COMBAT_WINDOWS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func first_act() -> void:
	var host: Node = load("res://scenes/a_test/level1_a.tscn").instantiate()
	root.add_child(host)
	host.set_process(false)
	var harness: Level1Harness = host._harness
	harness.opera_audio.stop()
	harness.clock.set_player(null)
	var controller: PuppetController = harness.runtime.puppet_controller
	var white: PuppetState = controller.get_puppet(0)
	Helper.key(host, KEY_W)
	harness.advance_steps(12)
	host._refresh_ui()
	check(white.air_height > .015 and white.leg_spread > .9, "第一关正式入口 W 张腿跳")
	await shot("act1-jump")
	harness.advance_steps(20)
	check(white.air_height == 0, "第一关短跳落地")
	var facing: float = white.facing
	var before: float = white.stage_pos.x
	Helper.key(host, KEY_S)
	harness.advance_steps(12)
	host._refresh_ui()
	check(white.stance > .7 and white.facing == facing, "第一关正式入口 S 压身且不转背")
	await shot("act1-dodge")
	harness.advance_steps(18)
	check((white.stage_pos.x - before) * facing < -.04, "第一关实际后撤")
	check(
		is_equal_approx(white.stage_pos.y, controller.walk_path.height_at(white.stage_pos.x)),
		"后撤保持桥面脚点"
	)
	await dispose(host)


func second_act() -> void:
	var host: Node = load("res://scenes/act2/opening.tscn").instantiate()
	root.add_child(host)
	host.set_process(false)
	host.dialogue.player.stop()
	host.clock.set_player(null)
	host._enter(0)
	host._entrance_complete[0] = true
	host.controller.set_controlled_puppet(0)
	host.controller.get_puppet(0).stage_pos.x = .5
	Helper.key(host, KEY_W)
	fixed(host, .2)
	check(host.controller.get_puppet(0).air_height > .1, "第二关门楼 W 到达共用控制器")
	await shot("act2-gate-jump")
	fixed(host, .3)
	Helper.key(host, KEY_S)
	fixed(host, .2)
	check(host.controller.get_puppet(0).stance > .7, "第二关门楼 S 躲闪")
	await dispose(host)
	host = load("res://scenes/act2/hall.tscn").instantiate()
	root.add_child(host)
	host.set_process(false)
	host.audio.player.stop()
	host.clock.set_player(null)
	host.controller.set_controlled_puppet(0)
	Helper.key(host, KEY_W)
	fixed(host, .2)
	check(not host.seated[0] and host.controller.get_puppet(0).air_height > .1, "厅堂 W 先离座再跳")
	await shot("act2-hall-jump")
	fixed(host, .3)
	host._snake_controlled = true
	host.controller.set_controlled_puppet(-1)
	var before: Dictionary = host.snake.recorded_view()
	Helper.key(host, KEY_W)
	Helper.key(host, KEY_S)
	check(
		host.snake.recorded_view() == before and not host.controller.motion.active(),
		"完整白蛇不套用人形 W/S"
	)
	await dispose(host)


func third_act() -> void:
	var host: Node = THIRD_SCENE.instantiate()
	root.add_child(host)
	host.start_scene()
	host.set_process(false)
	host.audio.player.stop()
	host.clock.set_player(null)
	Helper.key(host, KEY_1)
	Story.move_to(host, 0, .56)
	fixed(host, 30)
	check(host.guard_entrance.triggered and not host.guard_entrance.active, "鹿童沿用重音出山")
	if not host.guard_entrance.triggered:
		await dispose(host)
		return
	Story.advance(host, 98.8 - host.clock.get_song_time_s())
	host.capture = preload("res://scripts/c/c_act3_capture.gd").new()
	host.clock.set_player(host.audio.player)
	host.clock.start(98800)
	host.set_process(true)
	check(await pump(.3, "before_draw") > .001, "拔剑前原声正在混音")
	await shot("act3-sheath-right")
	check(await pump(3.0, "draw") > .001, "换手自动拔剑时原声连续")
	check(host.fight.draw_progress == 1.0, "到唱词自动出鞘完成")
	check(
		(
			host._swords[0].geometry().wrist.distance_to(
				host._views[0].hand_screen_position("left")
			)
			< .01
		),
		"实际画面剑柄位于换手后的腕点"
	)
	await shot("act3-sword-hand")
	Helper.key(host, KEY_W)
	var position: Vector2 = host.controller.get_puppet(0).stage_pos
	var deadline: int = Time.get_ticks_msec() + 600
	while host.controller.get_puppet(0).air_height < .08 and Time.get_ticks_msec() < deadline:
		await process_frame
	# 渲染帧可能晚于墙钟定时器，观察真实腾空状态再截图；声音继续在真实设备播放。
	host.set_process(false)
	check(await pump(.06, "jump") > .001, "第三关起跳原声持续")
	check(host.controller.get_puppet(0).air_height > .08, "第三关 W 原地短跳")
	Helper.drag(host, host._views[0].torso_screen_position(), Vector2(100, 30))
	check(host.controller.get_puppet(0).stage_pos == position, "Windows 鼠标拖动不能移动空中身形")
	await shot("act3-player-jump")
	Helper.key(host, KEY_ESCAPE)
	var state: Dictionary = host.controller.get_puppet(0).to_dict()
	await pump(.2, "pause_drain")
	capture.clear_buffer()
	check(await pump(.15, "paused") < .001, "菜单暂停实际混音静音")
	check(host.controller.get_puppet(0).to_dict() == state, "暂停保持空中姿态")
	Helper.key(host, KEY_ESCAPE)
	host.set_process(true)
	await pump(.4, "resume")
	check(host.controller.get_puppet(0).air_height == 0, "恢复后完成短跳")
	# 用正式 W 再跳一次，以固定步长抓取实际提剑和下劈姿态，混音设备继续播放原声。
	host.set_process(false)
	var hands: Vector2 = host.controller.get_puppet(0).hand_angle
	Helper.key(host, KEY_W)
	fixed(host, .14)
	check(host._swords[0].geometry().direction.y < -.7, "Windows W 提剑起跳")
	await shot("act3-jump-cut-raised")
	fixed(host, .17)
	check(host._swords[0].geometry().direction.y > .4, "Windows W 自动向下劈剑")
	check(await pump(.06, "jump_cut") > .001, "下劈时原声持续")
	await shot("act3-jump-cut-down")
	fixed(host, .20)
	check(host.controller.get_puppet(0).hand_angle == hands, "Windows 落地恢复原手姿")
	var facing: float = host.controller.get_puppet(0).facing
	Helper.key(host, KEY_S)
	# 短动作的中点按实际固定步长取样；墙钟等待会受截图期间的渲染帧影响。
	fixed(host, .21)
	check(await pump(.06, "dodge") > .001, "第三关躲闪原声持续")
	check(
		(
			host.controller.get_puppet(0).stance > .7
			and host.controller.get_puppet(0).facing == facing
		),
		"第三关 S 压身后撤保持朝向"
	)
	await shot("act3-player-dodge")
	fixed(host, .3)
	await pump(.06, "dodge_end")
	host.set_process(false)
	host.audio.player.stop()
	check(host.capture.finish(), "真实操作记录可收尾")
	var record: CPerformanceRecord = host.capture.record
	await dispose(host)
	await replay_jump(record)
	await pose_previews()


func replay_jump(record: CPerformanceRecord) -> void:
	var flow := CResultFlow.new()
	check(flow.offer_replay(record, 3), "同次演出记录可回放")
	flow.choose_replay(true)
	var replay: Node = load("res://scripts/b/performance_replay.gd").new()
	replay.flow = flow
	replay.stage_id = 3
	root.add_child(replay)
	replay.set_process(false)
	for snapshot: CSnapshot in record.snapshots:
		if snapshot.puppets[0].air_height > .1:
			var frame: Dictionary = flow.get_player().sample(snapshot.time_ms)
			frame.state = &"paused"
			replay.apply_frame(frame)
			check(replay._states[0].leg_spread == snapshot.puppets[0].leg_spread, "幕前显示原记录张腿")
			check(replay._states[0].air_height == snapshot.puppets[0].air_height, "幕前显示原记录离地高度")
			check(replay._surface.projection_views[0]._held_prop_hand == "left", "幕前保留换手后的持剑绑定")
			await shot("replay-player-jump")
			break
	var saw_cut: bool = false
	for snapshot: CSnapshot in record.snapshots:
		var white: Dictionary = snapshot.puppets[0]
		if (
			white.air_height > .04
			and white.hand_angle.left > .5
			and white.hand_angle.left < .8
			and white.elbow_angle.left < .2
		):
			var frame: Dictionary = flow.get_player().sample(snapshot.time_ms)
			frame.state = &"paused"
			replay.apply_frame(frame)
			check(replay._act3_view.swords[0].geometry().direction.y > .4, "同次回放显示实际下劈剑路")
			await shot("replay-jump-cut-down")
			saw_cut = true
			break
	check(saw_cut, "录制包含真实 W 下劈姿态")
	replay.stop()
	await dispose(replay)


func pose_previews() -> void:
	var host: Node = THIRD_SCENE.instantiate()
	root.add_child(host)
	host.start_scene()
	host.set_process(false)
	host.audio.player.stop()
	host._card.hide()
	var white: PuppetState = host.controller.get_puppet(0)
	white.stage_pos = Vector2(.45, 642.0 / 1080.0)
	white.hand_angle = Vector2(2.10, .4)
	white.elbow_angle = Vector2(.3, .3)
	host.controller.set_controlled_puppet(0)
	host.fight.draw_progress = 1
	var Moves := preload("res://scripts/act3/fight_moves.gd")
	for id in [1, 2]:
		host.on_stage.assign([0, id])
		var offset: float = 0.0
		var moves: Array = Moves.DEER if id == 1 else Moves.CRANE
		for i in moves.size():
			var actor: PuppetState = host.controller.get_puppet(id)
			actor.stage_pos = Vector2(.67, 642.0 / 1080.0)
			actor.facing = -1
			host.fight._cycle = -1
			var duration: float = moves[i].duration
			var peak: float = [.42, .57, .40][i] if id == 1 else [.62, .38, .42][i]
			for tick in range(roundi(duration * peak * 60) + 1):
				host.fight._duel(
					actor, white, roundi(offset * 1000 + tick * 1000.0 / 60), 1.0 / 60, true
				)
			host._refresh_views()
			if id == 2:
				var gap: float = absf(actor.stage_pos.x - white.stage_pos.x) * 1920
				check(gap >= 199.9 and gap <= 340.1, "Windows 鹤童腾挪留出操作空间 " + str(i))
			check(
				actor.leg_spread > .7 and actor.air_height > .03, "招式分件张腿 " + str(id) + "-" + str(i)
			)
			await shot("npc-" + str(id) + "-" + str(i))
			offset += duration
	await dispose(host)
