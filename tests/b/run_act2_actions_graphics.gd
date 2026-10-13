extends SceneTree
## Windows 实际图形环境：正式厅堂输入和动作截图，禁止用 headless 代替。

var hall: Node
const OUTPUT: String = "res://builds/act2-actions"
const ActionsInput := preload("res://tests/c/run_act2_actions.gd")


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("第二幕图形验收需要 Windows 图形环境")
		quit(1)
		return
	call_deferred("_run")


func capture(name: String) -> void:
	for _i in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(OUTPUT + "/" + name + ".png")
	if result != OK:
		push_error("第二幕截图保存失败：" + name)
		quit(1)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	hall = load("res://scenes/act2/hall.tscn").instantiate()
	root.add_child(hall)
	hall.set_process(false)
	await capture("opening")
	ActionsInput.advance(hall, 20.0)
	ActionsInput.take(hall, 2)
	ActionsInput.drag(hall, hall._views[2].torso_screen_position(), Vector2(-430, 0))
	ActionsInput.right(hall, 2)
	ActionsInput.advance(hall, 4.0)
	ActionsInput.take(hall, 1)
	ActionsInput.drag(
		hall,
		hall._views[1].hand_screen_position("right"),
		Vector2(1035, 415) - hall._views[1].hand_screen_position("right")
	)
	await capture("cup-held")
	ActionsInput.drag(hall, hall._views[1].torso_screen_position(), Vector2(-152, 0))
	ActionsInput.advance(hall, 0.2)
	ActionsInput.take(hall, 0)
	var offered: Vector2 = hall._views[1].hand_screen_position(hall.actions.cup_hand)
	ActionsInput.drag(
		hall,
		hall._views[0].hand_screen_position("left"),
		offered - hall._views[0].hand_screen_position("left")
	)
	await capture("cup-passed")
	ActionsInput.drag(
		hall,
		hall._views[0].hand_screen_position("left"),
		hall._views[0].mouth_screen_position() - hall._views[0].hand_screen_position("left")
	)
	await capture("drink")
	ActionsInput.advance(hall, 0.8)
	if not hall.actions.drunk:
		push_error("图形真实输入未完成饮酒")
		quit(1)
		return
	ActionsInput.advance(hall, 8.0)
	ActionsInput.take(hall, 1)
	ActionsInput.drag(hall, hall._views[1].torso_screen_position(), Vector2(740, 0))
	ActionsInput.right(hall, 1)
	ActionsInput.hold(hall, KEY_Q, 5.0)
	if hall.actions.phase != "replace":
		push_error(
			(
				"真实 Q 输入未压暗换身，phase=%s exposure=%f"
				% [hall.actions.phase, hall.lamp_controller.lamp.exposure]
			)
		)
		quit(1)
		return
	ActionsInput.right(hall, 0)
	ActionsInput.key(hall, KEY_4)
	ActionsInput.key(hall, KEY_SPACE)
	await capture("snake-dark")
	ActionsInput.hold(hall, KEY_E, 5.0)
	if hall.actions.phase != "return":
		push_error("真实 E 输入未显形")
		quit(1)
		return
	await capture("snake-revealed")
	var before: PackedVector2Array = hall.snake.points.duplicate()
	ActionsInput.drag(hall, hall.snake.head_position(), Vector2(35, -20))
	if hall.snake.points == before:
		push_error("正式拖头没有带动蛇身")
		quit(1)
		return
	await capture("snake-bend")
	var bent: PackedVector2Array = hall.snake.points.duplicate()
	var body_before: Vector2 = hall.snake.position
	ActionsInput.drag(hall, hall.snake.body_position(), Vector2(60, 0))
	ActionsInput.advance(hall, 0.2)
	if hall.snake.points != bent or hall.snake.position.x <= body_before.x + 50:
		push_error("正式拖躯干未保持弯曲姿态整移")
		quit(1)
		return
	await capture("snake-moved")
	ActionsInput.key(hall, KEY_2)
	ActionsInput.take(hall, 1)
	ActionsInput.drag(hall, hall._views[1].torso_screen_position(), Vector2(-690, 0))
	ActionsInput.advance(hall, 0.2)
	await capture("startled")
	ActionsInput.advance(hall, 2.0)
	if hall.actions.phase != "finished":
		push_error("实际返回未完成惊倒")
		quit(1)
		return
	await capture("ending")
	hall.queue_free()
	await process_frame
	print(
		"ACT2_GRAPHICS full actual-input sequence captured, Q/E, snake head/body dragging and ending passed"
	)
	quit(0)
