extends SceneTree
## Windows 图形环境：正式第二关输入、姿态、持杖与复位截图。

var scene: Node2D
var failures: int = 0
var checks: int = 0
const OUTPUT: String = "res://builds/upper-body"


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("上身图形探针需要 Windows 图形环境")
		quit(1)
		return
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("UPPER_GRAPHICS: " + label)


func _capture(name: String) -> void:
	for _i in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	_check(
		root.get_texture().get_image().save_png(OUTPUT + "/" + name + ".png") == OK, "保存 " + name
	)


func _drag(point: Vector2, delta: Vector2, alt: bool = false) -> void:
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.position = point
	button.pressed = true
	button.alt_pressed = alt
	scene._input(button)
	var motion := InputEventMouseMotion.new()
	motion.position = point + delta
	motion.relative = delta
	motion.alt_pressed = alt
	scene._input(motion)
	button.position = point + delta
	button.pressed = false
	scene._input(button)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	scene = load("res://scenes/act2/opening.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.dialogue.player.stop()
	scene._enter(0)
	scene._enter(1)
	scene._entrance_complete[0] = true
	scene.controller.set_controlled_puppet(0)
	var state: PuppetState = scene.controller.get_puppet(0)
	state.stage_pos.x = 0.60
	state.facing = 1.0
	scene._refresh_views()
	var view: PlaceholderPuppet = scene._views[0]
	var baseline: Vector2 = state.stage_pos
	await _capture("before")
	_drag(view.hand_screen_position("right"), Vector2(-25, -25))
	_check(state.elbow_angle.y > 0.1, "正式入口自动弯肘")
	_drag(view.head_screen_position(), Vector2(25, 0))
	_check(absf(state.head_tilt) > 0.01, "正式入口头部俯仰")
	_drag(view.torso_screen_position(), Vector2(35, 0), true)
	_check(state.torso_lean > 0.1, "正式入口前倾")
	_check(state.stage_pos == baseline and state.stance == 0.0, "上身操作保留位置及站姿")
	await _capture("pose")
	var projection: PlaceholderPuppet = scene._surface.projection_views[0]
	_check(projection.puppet_state == state, "实体与投影读取同一姿态")
	var reset := InputEventKey.new()
	reset.keycode = KEY_R
	reset.pressed = true
	scene._input(reset)
	_check(
		state.elbow_angle == Vector2.ZERO and state.head_tilt == 0 and state.torso_lean == 0,
		"正式入口 R 复位"
	)
	await _capture("reset")
	root.remove_child(scene)
	scene.queue_free()
	await process_frame
	await _first_act_replay()
	print("UPPER_GRAPHICS checks=%d failures=%d output=%s" % [checks, failures, OUTPUT])
	quit(1 if failures > 0 else 0)


func _first_act_replay() -> void:
	scene = load("res://scenes/a_test/level1_a.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var harness: Level1Harness = scene._harness
	harness.opera_audio.stop()
	harness.clock.set_player(null)
	var controller: PuppetController = harness.runtime.puppet_controller
	controller.get_puppet(1).hook_slot = PuppetState.HOOK_SLOT_NONE
	controller.set_controlled_puppet(1)
	var state: PuppetState = controller.get_puppet(1)
	state.stage_pos.x = 0.5
	scene._refresh_ui()
	harness.start_recording(1, scene._on_stage)
	var view: PlaceholderPuppet = scene._puppet_views[1]
	var baseline: Vector2 = state.stage_pos
	_drag(view.hand_screen_position("right"), Vector2(-25, -25))
	_drag(view.head_screen_position(), Vector2(25, 0))
	_drag(view.torso_screen_position(), Vector2(35 * state.facing, 0), true)
	harness.advance_steps(6)
	scene._refresh_ui()
	var pose_time: int = harness.clock.get_real_time_ms()
	var posed: Dictionary = state.to_dict()
	_check(state.elbow_angle.y > 0.1 and state.torso_lean > 0.1, "第一幕正式输入弯肘前倾")
	_check(state.stage_pos == baseline, "第一幕上身操作不移动脚点")
	harness.puppet_input.update_hover(view.hand_screen_position("right"))
	_check(view.upper_hover_part == "right", "正式实体显示悬停提示")
	await _capture("act1-pose-hint")
	var reset := InputEventKey.new()
	reset.keycode = KEY_R
	reset.pressed = true
	scene._input(reset)
	harness.advance_steps(6)
	_check(harness.runtime.director.umbrella.holder_id_of() == 1, "R 不改变伞的归属")
	var record: CPerformanceRecord = harness.capture.record
	_check(record.snapshots.size() >= 3, "正式捕获保留姿态和复位样本")
	_check(preload("res://scripts/c/c_replay_verifier.gd").new().verify(record).ok, "真实输入记录经独立核对")
	root.remove_child(scene)
	scene.queue_free()
	await process_frame
	var flow := CResultFlow.new()
	_check(flow.offer_replay(record, 1), "装载第一幕真实记录")
	flow.choose_replay(true)
	var replay := preload("res://scripts/b/performance_replay.gd").new()
	replay.flow = flow
	root.add_child(replay)
	replay.stop()
	replay.apply_frame(flow.get_player().sample(pose_time))
	var replay_state: PuppetState = replay._states[1]
	_check(
		replay_state.elbow_angle == Vector2(posed.elbow_angle.left, posed.elbow_angle.right),
		"幕前显示实际双肘"
	)
	_check(
		replay_state.head_tilt == posed.head_tilt and replay_state.torso_lean == posed.torso_lean,
		"幕前显示实际头腰"
	)
	_check(not replay._surface.projection_views[1].show_upper_controls, "回放不显示操控提示")
	await _capture("act1-replay-pose")
	replay.apply_frame(flow.get_player().sample(record.duration_ms))
	_check(
		(
			replay_state.elbow_angle == Vector2.ZERO
			and replay_state.head_tilt == 0
			and replay_state.torso_lean == 0
		),
		"回放保留 R 复位"
	)
	root.remove_child(replay)
	replay.queue_free()
	await process_frame
