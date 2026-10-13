extends SceneTree
## Windows 实际图形环境：正式厅堂输入和动作截图，禁止用 headless 代替。

var hall: Node
const OUTPUT: String = "res://builds/act2-actions"


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
	hall.queue_free()
	await process_frame
	print("ACT2_GRAPHICS opening captured")
	quit(0)
