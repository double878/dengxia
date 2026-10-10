extends SceneTree
## Windows 真 GPU 验收：固定样例、实际透射像素、暂停、镜像、幕面裁切、帧间隔。

const Lab := preload("res://scenes/b/stage_visual_lab.tscn")
const Optics := preload("res://tests/b/optics_fixture.gd")
var lab: Node2D
var failures: int = 0
var checks: int = 0
var output_dir: String = "res://builds/stage-realism"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for arg: String in args:
		if arg.begins_with("output="):
			output_dir = arg.trim_prefix("output=")
	if DisplayServer.get_name() == "headless":
		push_error("图形验收必须使用实际图形窗口，不可 --headless")
		quit(1)
		return
	root.show()
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("GRAPHICS FAIL: " + label)


func _settle() -> void:
	for i in range(5):
		await process_frame
		await RenderingServer.frame_post_draw


func _capture(name: String) -> Image:
	await _settle()
	var result: Image = root.get_texture().get_image()
	_check(result.save_png(output_dir + "/" + name + ".png") == OK, "保存 " + name)
	return result


func _luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


func _pixel(image: Image, design: Vector2) -> Color:
	var point: Vector2 = design * Vector2(image.get_size()) / Vector2(1920, 1080)
	return image.get_pixelv(Vector2i(point))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	lab = Lab.instantiate()
	root.add_child(lab)
	var normal: Image = await _capture("front")
	var cloth_region := Rect2i(Vector2i(Vector2(66, 92) * Vector2(normal.get_size()) / Vector2(1920, 1080)), Vector2i(Vector2(1788, 588) * Vector2(normal.get_size()) / Vector2(1920, 1080)))
	var normal_cloth: PackedByteArray = normal.get_region(cloth_region).get_data()
	var state_before: Array = lab.states.map(func(state: PuppetState) -> Dictionary: return state.to_dict())
	var paused_image: Image = await _capture("front-paused")
	_check(normal.get_data() == paused_image.get_data(), "同一暂停时间画面逐像素冻结")
	_check(state_before == lab.states.map(func(state: PuppetState) -> Dictionary: return state.to_dict()), "渲染不改写姿态")
	lab.paused = false
	await _settle()
	var resumed: Image = root.get_texture().get_image()
	_check(resumed.get_data() != paused_image.get_data(), "恢复后动作与自然火光继续变化")
	lab.paused = true
	lab.visual_ms = 1250.0
	for sample: String in ["near", "far", "low", "overlap", "head", "turn", "offscreen", "lifted"]:
		lab.set_case(sample)
		var changed: Image = await _capture("front-" + sample)
		_check(changed.get_region(cloth_region).get_data() != normal_cloth, "状态样例在真实幕面产生变化：" + sample)
	lab.front = false
	lab.set_case("low")
	await _capture("backstage-low")
	lab.set_case("normal")
	await _capture("backstage-lab")
	# 单独用已知几何验证实际 shader；实体关闭，检查幕面透光与全幕镜像。
	lab.front = false
	lab.surface.front_view = false
	lab.surface.sync_puppets(lab.states, [], null)
	lab.set_process(false)
	for view: PlaceholderPuppet in lab.entities:
		view.hide()
	lab.prop.hide()
	lab.lamp_view.hide()
	lab.surface.update_light(lab.lamp, 1250, 1250, 96.0)
	var fixture: Node2D = Optics.new()
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/puppet_transmission.gdshader")
	fixture.material = material
	lab.surface.projection_viewport.add_child(fixture)
	var back: Image = await _capture("optics-back")
	var raw: Image = lab.surface.projection_viewport.get_texture().get_image()
	var hole: Color = raw.get_pixel(360, 220)
	var red: Color = raw.get_pixel(320, 180)
	var single: Color = raw.get_pixel(555, 220)
	var overlap: Color = raw.get_pixel(610, 220)
	_check(hole.r > 0.98 and hole.g > 0.98 and hole.b > 0.98, "镂空完整透光")
	_check(red.r > red.g + 0.25 and red.r > red.b + 0.25, "染色皮片保留红色透射")
	_check(_luminance(overlap) < _luminance(single) - 0.08, "实际相乘的重叠皮片更暗")
	var tile: Color = raw.get_pixel(840, 200)
	var flat: Color = raw.get_pixel(1000, 200)
	_check(absf(tile.r - flat.r) < 0.012 and absf(tile.g - flat.g) < 0.012 and absf(tile.b - flat.b) < 0.012, "相同贴图色与顶点色不重复乘色或 alpha")
	var entity_fixture: Node2D = Optics.new()
	var entity_material := ShaderMaterial.new()
	entity_material.shader = preload("res://shaders/puppet_back.gdshader")
	entity_fixture.material = entity_material
	entity_fixture.position.y = 230
	lab.surface.projection_viewport.add_child(entity_fixture)
	await _settle()
	var entity_raw: Image = lab.surface.projection_viewport.get_texture().get_image()
	var entity_tile: Color = entity_raw.get_pixel(840, 430)
	var entity_flat: Color = entity_raw.get_pixel(1000, 430)
	_check(absf(entity_tile.r - entity_flat.r) < 0.012 and absf(entity_tile.g - entity_flat.g) < 0.012 and absf(entity_tile.b - entity_flat.b) < 0.012, "实体贴图也不能重复乘色或 alpha")
	entity_fixture.queue_free()
	_check(_luminance(_pixel(back, Vector2(360, 220))) > _luminance(_pixel(back, Vector2(320, 180))) + 0.20, "孔与皮片在布面仍有层次")
	lab.surface.front_view = true
	lab.surface.update_light(lab.lamp, 1250, 1250, 96.0)
	var front: Image = await _capture("optics-front")
	var mirror_red: Color = _pixel(front, Vector2(1920 - 320, 180))
	_check(absf(_luminance(mirror_red) - _luminance(_pixel(back, Vector2(320, 180)))) < 0.015, "幕前透射左右镜像且保持颜色")
	fixture.hide()
	var empty: Image = await _capture("optics-empty")
	_check(_pixel(front, Vector2(18, 34)).is_equal_approx(_pixel(empty, Vector2(18, 34))), "幕外色片不污染框架或后台")
	fixture.queue_free()
	lab.set_process(true)
	lab.front = true
	lab.set_case("normal")
	lab.paused = false
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
	var metrics := {"resolution": str(normal.get_size()), "frames": intervals.size(), "mean_ms": sum / intervals.size(), "p95_ms": intervals[int(intervals.size() * 0.95)], "max_ms": intervals.back(), "gpu": RenderingServer.get_video_adapter_name(), "checks": checks, "failures": failures}
	var file := FileAccess.open(output_dir + "/graphics-metrics.json", FileAccess.WRITE)
	_check(file != null, "性能证据可写入")
	metrics["checks"] = checks
	metrics["failures"] = failures
	if file != null:
		file.store_string(JSON.stringify(metrics, "\t"))
	print("GRAPHICS: ", JSON.stringify(metrics))
	lab.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures > 0 else 0)
