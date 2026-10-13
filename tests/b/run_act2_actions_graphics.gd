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
	ActionsInput.drag(hall, hall._views[1].hand_screen_position("right"), Vector2(1035, 415) - hall._views[1].hand_screen_position("right"))
	await capture("cup-held")
	ActionsInput.drag(hall, hall._views[1].torso_screen_position(), Vector2(-152, 0))
	ActionsInput.advance(hall, 0.2)
	ActionsInput.take(hall, 0)
	var offered: Vector2 = hall._views[1].hand_screen_position(hall.actions.cup_hand)
	ActionsInput.drag(hall, hall._views[0].hand_screen_position("left"), offered - hall._views[0].hand_screen_position("left"))
	await capture("cup-passed")
	ActionsInput.drag(hall, hall._views[0].hand_screen_position("left"), hall._views[0].mouth_screen_position() - hall._views[0].hand_screen_position("left"))
	await capture("drink")
	ActionsInput.advance(hall, 0.8)
	if not hall.actions.drunk:
		push_error("图形真实输入未完成饮酒")
		quit(1)
		return
	hall.queue_free()
	await process_frame
	print("ACT2_GRAPHICS opening / cup-held / cup-passed / drink captured")
	quit(0)
