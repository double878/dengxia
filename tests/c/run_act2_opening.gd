extends SceneTree
## 第一关实际页面输入与第二关开场操演回归；图形运行另保存舞台截图。

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ACT2_OPENING: " + label)


func _run() -> void:
	check(ResourceLoader.exists("res://scenes/act2/opening.tscn"), "缺少独立第二关开场")
	check(PlaceholderPuppet.SKIN_TEXTURES.size() == 3, "法海污染了第一关头架映射")
	for route: String in ["decline", "skip", "complete"]:
		await test_transition(route)
	print("ACT2_OPENING checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func test_transition(route: String) -> void:
	var game: Node = load("res://scenes/game_flow.tscn").instantiate()
	root.add_child(game)
	var old_level: Node = game.get("_level")
	old_level.set_process(false)
	old_level.get("_harness").shutdown()
	var record: CPerformanceRecord = preload("res://scripts/c/c_mock_performer.gd").new().build()
	game._performance_finished(record, 1, "许仙借伞")
	var flow: CResultFlow = game.get("_flow")
	check(flow.get_flow_state() == &"choice", route + " 保留初次回放选择")
	check(game.get("_page").find_children("*", "Button", true, false).size() == 2, "选择页两项")
	click(Vector2(30, 30))
	await process_frame
	check(game.get("_stage_id") == 1, "点击选择页背景不能切关")
	game._choose_replay(route != "decline")
	if route == "skip":
		game._skip_replay()
	elif route == "complete":
		game.get("_replay").set_process(false)
		flow.get_player().set_clock_source(CReplayPlayer.CLOCK_SOURCE_DELTA)
		game.get("_replay")._process(float(record.duration_ms) / 1000.0 + 1.0)
	check(flow.get_flow_state() == &"result", route + " 到达收场")
	check(game.get("_page").find_children("*", "Button", true, false).is_empty(), "收场无重看/重演按钮")
	click(Vector2(1800, 980), MOUSE_BUTTON_WHEEL_UP)
	click(Vector2(1800, 980), MOUSE_BUTTON_LEFT, false)
	await process_frame
	check(game.get("_stage_id") == 1, "滚轮和释放不切关")
	if not ResourceLoader.exists("res://scenes/act2/opening.tscn"):
		game.queue_free()
		await process_frame
		return
	# 覆盖背景、标题、说明文字三个落点，以及左右中三种点击。
	var locations := {
		"decline": Vector2(10, 10), "skip": Vector2(960, 320), "complete": Vector2(960, 430)
	}
	var buttons := {
		"decline": MOUSE_BUTTON_LEFT, "skip": MOUSE_BUTTON_RIGHT, "complete": MOUSE_BUTTON_MIDDLE
	}
	click(locations[route], buttons[route])
	click(locations[route], buttons[route])
	await process_frame
	await process_frame
	check(flow.is_released, "切关释放旧录像")
	check(not is_instance_valid(old_level), "第一关宿主没有释放")
	check(game.get("_stage_id") == 2, route + " 进入第二关")
	check(game.get("_page") == null and game.get("_replay") == null, "旧页面/回放残留")
	var opening: Node = game.get("_level")
	if opening == null or opening.scene_file_path != "res://scenes/act2/opening.tscn":
		check(false, "误入旧第二关教学场景")
	else:
		check(opening.get("on_stage").is_empty(), "切关点击穿透使影人提前上场")
		check(game.get_child_count() == 1, "重复点击加载了多个场景")
		if route == "decline":
			await test_controls(opening)
	game.queue_free()
	await process_frame


func test_controls(opening: Node) -> void:
	opening.set_process(false)
	var controller: PuppetController = opening.get("controller")
	await capture("operator-hand-idle")
	key(KEY_1)
	key(KEY_1)
	key(KEY_2)
	key(KEY_3)
	check(opening.get("on_stage") == [0, 1], "数字键上场/重复上场/空槽")
	check(controller.controlled_id == -1, "数字键不应自动接手")
	press(Vector2(960, 856))
	check(not controller.is_dragging() and controller.controlled_id == -1, "点操作手不应代替空格接手")
	click(Vector2(960, 856), MOUSE_BUTTON_LEFT, false)
	key(KEY_SPACE)
	check(controller.controlled_id == 0, "空格先接手法海")
	var fahai: PuppetState = controller.get_puppet(0)
	var view: PlaceholderPuppet = opening.get("_views")[0]
	check(view.get("skin_override") == 3, "法海没有独立身体")
	check(opening.get("_surface").projection_views[0].get("skin_override") == 3, "投影没用法海")
	check(not opening.get("_surface").front_view, "开场误显示幕前")
	fahai.hand_angle = Vector2(0.4, 1.2)
	var pose: Vector2 = fahai.hand_angle
	await test_hand_drag(opening)
	press(Vector2(960, 856))
	check(controller.is_dragging(), "移动后仍应能从操作手抓签")
	key(KEY_SPACE)
	check(not controller.is_dragging(), "接手没有结束旧胸签拖动")
	check(controller.controlled_id == 1 and fahai.hand_angle == pose, "切换没保持原姿势")
	var xu_position: Vector2 = controller.get_puppet(1).stage_pos
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(80, 0)
	root.push_input(motion, true)
	controller.tick(1.0 / 60.0)
	check(controller.get_puppet(1).stage_pos == xu_position, "旧拖动泄漏到许仙")
	check(
		controller.get_puppet(1).turn_progress == 1.0 and controller.get_puppet(1).facing == -1.0,
		"法海的翻面目标泄漏到许仙"
	)
	press(Vector2(960, 856))
	check(controller.is_dragging(), "换人后手边竹签没有接到许仙")
	var fahai_position: Vector2 = fahai.stage_pos
	motion.relative = Vector2(-40, 0)
	root.push_input(motion, true)
	controller.tick(1.0 / 60.0)
	click(Vector2(920, 856), MOUSE_BUTTON_LEFT, false)
	check(
		controller.get_puppet(1).stage_pos.x < xu_position.x and fahai.stage_pos == fahai_position,
		"换人后手边拖动仍作用于旧影人"
	)
	key(KEY_SPACE)
	check(controller.controlled_id == 0, "空格没有循环回法海")
	await capture("fahai-onstage")
	fahai.facing = -1.0
	fahai.hand_angle.y = 2.2
	opening._refresh_views()
	await capture("fahai-turn-raised")
	fahai.facing = 1.0
	key(KEY_ESCAPE)
	var frozen: int = opening.get("clock").get_real_time_ms()
	key(KEY_SPACE)
	click(view.hand_screen_position("right"), MOUSE_BUTTON_RIGHT)
	opening._process(1.0)
	check(controller.controlled_id == 0 and opening.get("on_stage").size() == 2, "暂停仍接手/退场")
	check(opening.get("clock").get_real_time_ms() == frozen, "暂停仍走时钟")
	key(KEY_ESCAPE)
	var place: Vector2 = fahai.stage_pos
	click(view.hand_screen_position("right"), MOUSE_BUTTON_RIGHT)
	check(opening.get("on_stage") == [1] and controller.controlled_id == -1, "右键没有收走法海")
	key(KEY_SPACE)
	key(KEY_SPACE)
	check(controller.controlled_id == 1, "空格未跳过缺席影人")
	key(KEY_1)
	check(fahai.stage_pos == place and is_equal_approx(fahai.hand_angle.y, 2.2), "再次上场重置位置或姿势")
	key(KEY_SPACE)
	check(controller.controlled_id == 0, "接手未按编号循环")
	var lamp: LampState = opening.get("lamp_controller").lamp
	lamp.distance = 0.85
	opening._refresh_views()
	check(view.shadow_scale() == opening.get("_views")[1].shadow_scale(), "灯距未作用于全部影人")
	var ground: Vector2 = view.stage_to_screen(fahai.stage_pos)
	var projected: PlaceholderPuppet = opening.get("_surface").projection_views[0]
	var expected_wrist: Vector2 = (
		ground + (view.hand_screen_position("right") - ground) * projected.shadow_scale()
	)
	check(projected.hand_screen_position("right").is_equal_approx(expected_wrist), "法海腕点没有遵循全场灯距投影")
	await capture("fahai-close-lamp")


func test_hand_drag(opening: Node) -> void:
	var controller: PuppetController = opening.get("controller")
	var state: PuppetState = controller.get_controlled()
	var other: Vector2 = controller.get_puppet(1).stage_pos
	var pose: Vector2 = state.hand_angle
	for at: Vector2 in [Vector2(960, 856), Vector2(960, 750)]:
		var before: Vector2 = state.stage_pos
		press(at)
		check(controller.is_dragging(), "操作手/手边竹签没有抓住胸签")
		var motion := InputEventMouseMotion.new()
		motion.position = at + Vector2(80, 0)
		motion.relative = Vector2(80, 0)
		root.push_input(motion, true)
		controller.tick(1.0 / 60.0)
		check(state.stage_pos.x > before.x, "从操作手拖动没有移动当前影人")
		check(
			state.hand_angle == pose and controller.get_puppet(1).stage_pos == other,
			"拖动改变了姿势或未接手影人"
		)
		click(motion.position, MOUSE_BUTTON_LEFT, false)
		check(not controller.is_dragging(), "松开操作手没有结束拖动")
	press(Vector2(1250, 900))
	check(not controller.is_dragging(), "操作手外的桌面也能抓住胸签")
	click(Vector2(1250, 900), MOUSE_BUTTON_LEFT, false)
	opening._refresh_views()
	await capture("operator-hand-dragged")


func press(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func click(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, pressed: bool = true) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = button
	event.pressed = pressed
	root.push_input(event, true)
	if pressed and button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		var release := event.duplicate() as InputEventMouseButton
		release.pressed = false
		root.push_input(release, true)


func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for _i in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/act2-opening")
	var screen := root.get_texture().get_image()
	if label in ["operator-hand-idle", "fahai-onstage"]:
		var scale: Vector2 = Vector2(screen.get_size()) / Vector2(1920, 1080)
		var at: Vector2 = Vector2(960, 856) * scale
		var palm: Color = screen.get_pixel(int(at.x), int(at.y))
		check(palm.r > 0.5 and palm.g > 0.35 and palm.b > 0.2, "操作手缺失或被长签遮挡：" + label)
	check(screen.save_png("res://builds/act2-opening/%s.png" % label) == OK, "保存舞台截图")
