extends SceneTree
## 正式入口：第四自动演员、原声时轴、玩家自由身段、固定山脚站位及真实收场回放。
const Helper := preload("res://tests/c/run_act2_actions.gd")
const Story := preload("res://tests/c/run_act3_story.gd")
const GAME := preload("res://scenes/game_flow.tscn")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ACT3_FINALE: " + label)


static func until(host: Node, song_ms: int) -> void:
	Story.advance(host, maxf(0, (song_ms - host.clock.get_song_time_ms()) / 1000.0))


func _run() -> void:
	var game: Node = GAME.instantiate()
	game.initial_stage = 3
	root.add_child(game)
	var host: Node = game._level
	host.set_process(false)
	check(host.actions.phase != "error", "完整原声与仙翁清单合法")
	check(host.audio.config.complete, "最后一段完成整关")
	check(host._finale_view.puppet.figure_height <= host._views[1].figure_height, "仙翁显示尺寸不再大于双童")
	host.start_scene()
	host.audio.player.stop()
	host.clock.set_player(null)
	Helper.key(host, KEY_1)
	Story.move_to(host, 0, .56)
	var finale_config: Dictionary = host.audio.config.finale
	until(host, int(finale_config.start_ms) - 300)
	check(not host.finale.active and host.fight.active_actor == 2, "仙翁到点前仍由鹤童接战")
	var white: PuppetState = host.controller.get_puppet(0)
	white.hand_angle = Vector2(.6, 1.1)
	white.elbow_angle = Vector2(.3, .5)
	white.torso_lean = .2
	var pose: Dictionary = white.to_dict()
	until(host, int(finale_config.stop_ms) + 140)
	check(host.finale.active and host._finale_view.visible, "喝止时仙翁从山后出场")
	check(host._finale_view.puppet.entrance_mask != null, "仙翁出场使用现有山景遮挡")
	check(host.fight.phase == "stopped" and host.fight.active_actor == -1, "徒儿住手后立即停止进攻")
	check(host.fight.flash_strength(host.clock.get_song_time_ms()) == 0, "停战不残留交锋闪光")
	until(host, int(finale_config.gift_ms) - 100)
	check(host.on_stage == [0, 1, 2] and host.finale.elder != null, "仙翁与双童、白素贞四人同场")
	check(host.controller.puppets.size() == 3, "第四演员不改变三槽控制契约")
	check(host.fight.sword_progress() == [0.0, 0.0, 0.0], "停战后白素贞收剑，双童藏剑")
	check(white.to_dict() == pose, "仙翁出场不接管白素贞姿态或走位")
	check(host._finale_view.puppet.entrance_mask == null, "仙翁走出山景后解除遮挡")
	Helper.key(host, KEY_SPACE)
	check(host.controller.controlled_id == 0, "结尾仍只接手白素贞")
	var before: Dictionary = host.finale.recorded_view()
	var song: int = host.clock.get_song_time_ms()
	var count: int = host.capture.record.snapshots.size()
	Helper.key(host, KEY_ESCAPE)
	Story.advance(host, 2)
	check(host.finale.recorded_view() == before, "暂停冻结仙翁与双童")
	check(
		host.clock.get_song_time_ms() == song and host.capture.record.snapshots.size() == count,
		"暂停冻结时轴与采集"
	)
	Helper.key(host, KEY_ESCAPE)
	until(host, int(finale_config.gift_ms) + 500)
	check(
		(
			host.finale.herb_owner == -1
			and host.finale.gift_progress == 0
			and host.finale.phase == "advice"
		),
		"仙翁直接说话，不演递草"
	)
	until(host, int(finale_config.gift_ms) + 1300)
	check(host.finale.herb_owner == -1, "白素贞不持灵芝道具")
	check(
		(
			host._views[0]._held_prop_hand == ""
			and host._surface.projection_views[0]._held_prop_hand == ""
		),
		"实体和幕影均为空手"
	)
	Story.move_to(host, 0, .40)
	check(absf(white.stage_pos.x - .40) < .01, "赠草后仍可自由走位")
	Helper.drag(host, host._views[0].torso_screen_position(), Vector2(45 * white.facing, 0), true)
	check(white.torso_lean > .2, "谢礼仍可由玩家拖动完成")
	Helper.key(host, KEY_W)
	Story.advance(host, .2)
	check(white.air_height > 0, "收剑后 W 仍可短跳")
	Story.advance(host, .4)
	var dodge_x: float = white.stage_pos.x
	var dodge_facing: float = white.facing
	Helper.key(host, KEY_S)
	Story.advance(host, .5)
	check((white.stage_pos.x - dodge_x) * dodge_facing < -.04, "结尾 S 仍可后撤")
	host._exit(0)
	host.lamp_controller.lamp.exposure = .1
	song = host.clock.get_song_time_ms()
	Story.advance(host, 2)
	check(
		host.clock.get_song_time_ms() >= song + 1990 and not host.actions.waiting,
		"缺场、暗灯与漏谢礼不停止原声时轴"
	)
	host._enter(0)
	host.lamp_controller.lamp.exposure = .7
	until(host, 153000)
	check(host.finale.elder.stage_pos.x < host.controller.get_puppet(2).stage_pos.x, "仙翁位于鹤童左边")
	check(
		host.controller.get_puppet(2).stage_pos.x < host.controller.get_puppet(1).stage_pos.x,
		"鹤童位于鹿童左边"
	)
	check(host.finale.elder.stage_pos.x > .48, "三人固定在山脚前景，左侧留给玩家")
	until(host, int(finale_config.farewell_ms) + 1000)
	check(host.finale.phase == "farewell" and host.actions.subtitle().contains("多谢仙翁"), "谢别按原声时标发生")
	var record: CPerformanceRecord = host.capture.record
	until(host, int(host.audio.config.duration_ms) + 1400)
	check(host.actions.phase == "awaiting_exit" and game._flow == null, "原声结束等待玩家离场，不自动收场")
	var waiting_real: int = host.clock.get_real_time_ms()
	Story.advance(host, 2)
	check(
		(
			host.clock.get_real_time_ms() >= waiting_real + 1990
			and host.actions.phase == "awaiting_exit"
		),
		"待离场时仍保留实际等待与操控"
	)
	Helper.take(host, 0)
	Helper.key(host, KEY_W)
	Story.advance(host, .2)
	check(white.air_height > 0, "片尾等待时仍可 W 跳起")
	var exit_event := InputEventMouseButton.new()
	exit_event.button_index = MOUSE_BUTTON_RIGHT
	exit_event.pressed = true
	exit_event.position = host._views[0].head_screen_position()
	host._input(exit_event)
	check(not host.on_stage.has(0) and not host._views[0].visible, "空中右键实际头部即可退场消失")
	check(host.actions.departure_requested, "谢别后的右键离场触发结尾")
	Story.advance(host, .05)
	check(game._flow != null, "原声已结束时右键退场直接收场，不额外等待")
	await process_frame
	check(game._level == null and game._flow != null, "玩家离场后进入官方观看选择")
	check(record.validate_invariants().is_empty(), "四人演出记录完整")
	var verifier := CReplayVerifier.new()
	var report: Dictionary = verifier.verify(record)
	check(report.ok, "独立回放验收器逐帧核对四人和灵芝：" + str(report.problems))
	game._choose_replay(true)
	var replay: Node = game._replay
	replay.set_process(false)
	var player: CReplayPlayer = game._flow.get_player()
	var giving: CSnapshot
	var farewell: CSnapshot
	var exact: bool = true
	for i in range(record.snapshots.size()):
		var snapshot: CSnapshot = record.snapshots[i]
		var f: Dictionary = snapshot.performance.finale
		exact = exact and player.sample(snapshot.time_ms).performance.finale == f
		if f.phase == "advice":
			giving = snapshot
		if f.phase == "farewell":
			farewell = snapshot
		if i > 0:
			var previous: CSnapshot = record.snapshots[i - 1]
			var pf: Dictionary = previous.performance.finale
			if pf.active != f.active or pf.herb_owner != f.herb_owner:
				var mid: int = (snapshot.time_ms + previous.time_ms) / 2
				var mf: Dictionary = player.sample(mid).performance.finale
				check(mf.active == pf.active and mf.herb_owner == pf.herb_owner, "出现与灵芝归属不提前切换")
	check(exact, "同次记录所有采样点的第四演员完整还原")
	for snapshot: CSnapshot in [giving, farewell]:
		check(snapshot != null, "记录包含仙翁说话与谢别")
		if snapshot == null:
			continue
		var frame: Dictionary = player.sample(snapshot.time_ms)
		frame.state = &"paused"
		replay.apply_frame(frame)
		check(replay._act3_view.finale_view.visible, "实际回放显示仙翁")
		check(
			replay._act3_view.finale_view.elder.to_dict() == snapshot.performance.finale.elder,
			"显示器只读第四演员原姿态"
		)
	# 同一可见阶段的连续姿态应插值，不能只沿用前帧。
	var a: Dictionary = giving.performance.duplicate(true)
	var b: Dictionary = a.duplicate(true)
	b.finale.elder.stage_pos.x += .1
	b.finale.gift_progress += .1
	var mid: Dictionary = player._lerp_performance(a, b, .5, 34)
	check(
		absf(mid.finale.elder.stage_pos.x - a.finale.elder.stage_pos.x - .05) < .00001, "第四演员连续位置插值"
	)
	check(absf(mid.finale.gift_progress - a.finale.gift_progress - .05) < .00001, "同归属赠草进度连续插值")
	replay._act3_view.sync({"on_stage": [], "audio": {}}, true)
	check(not replay._act3_view.finale_view.visible, "缺少仙翁字段的旧记录正常隐藏第四人")
	game._skip_replay()
	check(game._flow == null and game._page.name == "OutroVideo", "观看后释放记录并播放片尾")
	game.queue_free()
	await process_frame
	check_early_departure()
	print("ACT3_FINALE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func check_early_departure() -> void:
	var actions: RefCounted = load("res://scripts/act3/act3_actions.gd").new()
	var clock := MusicClock.new()
	var controller := PuppetController.new()
	controller.setup(3)
	var score: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/audio/act3-mountain/score.json")
	)
	actions.setup(clock, controller, score)
	actions.start()
	actions.free_performance = true
	clock.set_free_time_ms(160000)
	actions.actor_exited(0)
	check(not actions.departure_requested, "谢别前误退场不提前完成结尾")
	clock.set_free_time_ms(int(score.finale.farewell_ms) + 1000)
	actions.actor_exited(0)
	var on_stage: Array[int] = [1, 2]
	actions.update(on_stage, .7, true)
	check(
		actions.departure_requested and actions.phase != "finished" and not clock.is_song_frozen(),
		"谢别时先退场，原声仍继续播完"
	)
	on_stage.append(0)
	actions.update(on_stage, .7, true)
	check(not actions.departure_requested, "原声收尾时重新上场会取消离场完成状态")
	on_stage.erase(0)
	actions.actor_exited(0)
	clock.set_free_time_ms(int(score.duration_ms))
	actions.update(on_stage, .7, true)
	check(actions.phase == "finished", "已经离场时等到原声片尾才收场")
	for x: float in [.12, .30, .56, .87]:
		var finale: RefCounted = load("res://scripts/act3/finale_choreography.gd").new()
		finale.setup(score)
		controller.get_puppet(0).stage_pos.x = x
		var original: Vector2 = controller.get_puppet(0).stage_pos
		on_stage.assign([0, 2])
		for tick in range(900):
			finale.update(
				1.0 / 60.0,
				int(score.finale.start_ms) + roundi(tick * 1000.0 / 60.0),
				controller,
				on_stage
			)
		var positions: Array[float] = [
			finale.elder.stage_pos.x,
			controller.get_puppet(1).stage_pos.x,
			controller.get_puppet(2).stage_pos.x
		]
		check(
			positions[0] < positions[2] and positions[2] < positions[1],
			"不同玩家位置不改变仙翁、鹤童、鹿童顺序：%s" % x
		)
		# Vector2 用单精度存储；与写入后的向量精确比较，避免将 float64 常量当成位移。
		check(controller.get_puppet(0).stage_pos == original, "排位不挪动玩家：%s" % x)
