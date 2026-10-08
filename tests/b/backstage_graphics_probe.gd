extends SceneTree
## 正常入口与显示接线回归：在真实图形窗口注入原输入事件，检查状态和实际画面。

const Entry := preload("res://scenes/game_flow.tscn")
var checks: int = 0
var failures: int = 0
var output_dir: String = "res://builds/stage-realism"
var entry: Node
var stage: Node2D


func _initialize() -> void:
	print("BACKSTAGE_INIT: display=%s window_visible=%s" % [DisplayServer.get_name(), root.visible])
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for arg: String in args:
		if arg.begins_with("output="):
			output_dir = arg.trim_prefix("output=")
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.show()
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("BACKSTAGE FAIL: " + label)


func _settle() -> void:
	for i in range(6):
		await process_frame
		await RenderingServer.frame_post_draw


func _save(name: String) -> Image:
	await _settle()
	var image: Image = root.get_texture().get_image()
	_check(image.save_png(output_dir + "/" + name + ".png") == OK, "保存 " + name)
	return image


func _run() -> void:
	print("BACKSTAGE_OPEN: ", output_dir)
	DirAccess.make_dir_recursive_absolute(output_dir)
	entry = Entry.instantiate()
	root.add_child(entry)
	stage = entry._level
	await _settle()
	_check(not stage._stage_surface.front_view, "正常入口始终为幕后，不泄露幕前")
	_check(stage._puppet_views[0].render_mode == PlaceholderPuppet.RenderMode.ENTITY, "游戏使用实体层")
	var view: PlaceholderPuppet = stage._puppet_views[0]
	var height: float = view.figure_px_height()
	var wrist: Vector2 = view.hand_screen_position("left")
	var initial: float = stage._lamp.lamp.distance
	var scroll := InputEventMouseButton.new()
	scroll.button_index = MOUSE_BUTTON_WHEEL_UP
	scroll.pressed = true
	stage._input(scroll)
	# 滚轮由原 LampInputReader 缓存，下一固定步才消费。
	await _settle()
	stage._refresh_ui()
	_check(stage._lamp.lamp.distance > initial, "原滚轮事件仍推近灯")
	_check(is_equal_approx(height, view.figure_px_height()), "滚轮保持实体尺寸")
	_check(wrist.is_equal_approx(view.hand_screen_position("left")), "滚轮保持实体腕点")
	var controller: PuppetController = stage._harness.runtime.puppet_controller
	var state: PuppetState = controller.get_controlled()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = view.chest_tag_screen()
	stage._input(press)
	var before: float = state.stage_pos.x
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + Vector2(70, 0)
	motion.relative = Vector2(70, 0)
	stage._input(motion)
	press.pressed = false
	stage._input(press)
	_check(state.stage_pos.x > before, "原胸签命中与拖动坐标仍一致")
	stage._harness.set_paused(true)
	stage._refresh_ui()
	await _save("backstage")
	var lamp: LampState = stage._lamp.lamp
	lamp.distance = 0.0
	stage._refresh_ui()
	await _save("backstage-far")
	lamp.distance = 1.0
	stage._refresh_ui()
	await _save("backstage-near")
	lamp.oil = 0.0
	lamp.exposure = 0.0
	stage._refresh_ui()
	await _save("backstage-low-game")
	_check(view.exposure_alpha() == 1.0, "低油低显露实体仍不透明可操作")
	stage._paused = true
	stage._refresh_ui()
	var paused: Image = await _save("backstage-paused")
	await _settle()
	_check(paused.get_data() == root.get_texture().get_image().get_data(), "游戏暂停后画面与火光逐像素冻结")
	stage._paused = false
	lamp.oil = 1.0
	lamp.exposure = 1.0
	stage._harness.set_paused(false)
	await _settle()
	var intervals: Array[float] = []
	var previous: int = Time.get_ticks_usec()
	for i in range(240):
		await process_frame
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		intervals.append(float(now - previous) / 1000.0)
		previous = now
	intervals.sort()
	var sum: float = 0.0
	for value: float in intervals:
		sum += value
	var metrics := {"resolution": str(paused.get_size()), "frames": 240, "mean_ms": sum / 240.0, "p95_ms": intervals[228], "max_ms": intervals.back(), "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name()}
	var file := FileAccess.open(output_dir + "/backstage-metrics.json", FileAccess.WRITE)
	_check(file != null, "后台性能证据可写入")
	metrics["checks"] = checks
	metrics["failures"] = failures
	if file != null:
		file.store_string(JSON.stringify(metrics, "\t"))
	print("BACKSTAGE: ", JSON.stringify(metrics))
	stage._harness.shutdown()
	entry.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures > 0 else 0)
