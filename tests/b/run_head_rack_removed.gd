extends SceneTree
## 第一关真实 GUI 输入与画面回归；共享控制器的旧记录能力不受此入口删除影响。
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("HEAD_RACK_REMOVED: " + label)


func _run() -> void:
	var game: Node = load("res://scenes/game_flow.tscn").instantiate()
	root.add_child(game)
	game._intro_finished()
	game._briefing_finished()
	await process_frame
	var host: Node = game._level
	var actors: PuppetController = host._harness.runtime.puppet_controller
	var before: Array = actors.puppets.map(func(p: PuppetState) -> int: return p.head_id)
	check(host.get_node_or_null("Hud/RackLabel") == null, "无备用头文字标签")
	for code: Key in [KEY_1, KEY_2, KEY_3]:
		for pressed: bool in [true, false]:
			var key := InputEventKey.new()
			key.keycode = code
			key.pressed = pressed
			root.push_input(key, true)
	for x: float in [1512, 1590, 1668]:
		for pressed: bool in [true, false]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.position = Vector2(x, 838)
			click.pressed = pressed
			root.push_input(click, true)
	await process_frame
	check(actors.puppets.map(func(p: PuppetState) -> int: return p.head_id) == before, "1/2/3 和原头架热区不会换头")
	check(not host.has_method("_draw_head_rack"), "已移除头架绘制")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path: String = ProjectSettings.globalize_path("res://builds/playtest-polish-20261017/no-head-rack.png")
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		check(root.get_texture().get_image().save_png(path) == OK, "保存实际画面")
	game.queue_free()
	await process_frame
	await create_timer(.1).timeout
	print("HEAD_RACK_REMOVED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
