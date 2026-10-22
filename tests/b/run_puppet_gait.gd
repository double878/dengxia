extends SceneTree
## 固定身体位置，实际 GPU 下半身必须随步相改变；停止后不受残留步相影响。
const OUTPUT := "res://builds/gait-revision-20261022"
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PUPPET_GAIT: " + label)

func _run() -> void:
	check(DisplayServer.get_name() != "headless", "需要真实图形驱动")
	if failures:
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for id in [0,1,3,4,5,6]:
		await _check_gait(id)
	await _capture_walk_movie()
	print("PUPPET_GAIT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)

func _capture(viewport: SubViewport, view: PlaceholderPuppet) -> Image:
	view.queue_redraw()
	for frame in range(2):
		await process_frame
		await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _check_gait(id: int) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640,640)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var bg := ColorRect.new()
	bg.size = Vector2(640,640)
	bg.color = Color("464b55")
	viewport.add_child(bg)
	var view := PlaceholderPuppet.new()
	var state := PuppetState.new(id if id < 3 else 0)
	state.head_id = id if id < 3 else 0
	state.stage_pos = Vector2(.5,.88)
	state.hand_angle = Vector2(.4,1.4)
	view.puppet_state = state
	view.stage_size = Vector2(640,640)
	view.figure_height = 400
	view.skin_override = id
	view.render_mode = PlaceholderPuppet.RenderMode.ENTITY
	viewport.add_child(view)
	# 接地半周期向后蹬、腾空半周期向前送；不改变演出状态的数据契约。
	state.walk_amount = 1
	for side in [-1.0,1.0]:
		var offset: float = PI if side < 0 else 0.0
		state.walk_phase = PI * .25 - offset
		var swing_start: Vector2 = view.walk_step_offset(side,400)
		state.walk_phase = PI * .75 - offset
		var swing_end: Vector2 = view.walk_step_offset(side,400)
		check((swing_end.x-swing_start.x)*view.pose_reference_facing() > 20, "腾空脚沿面向前送")
		check(swing_start.y < -5 and swing_end.y < -5, "送脚时离地")
		state.walk_phase = PI * 1.25 - offset
		var contact_start: Vector2 = view.walk_step_offset(side,400)
		state.walk_phase = PI * 1.75 - offset
		var contact_end: Vector2 = view.walk_step_offset(side,400)
		check((contact_end.x-contact_start.x)*view.pose_reference_facing() < -20, "落地脚向后蹬地")
		check(contact_start.y == 0 and contact_end.y == 0, "蹬地期脚不悬空")
	for pose in range(4):
		var facing: float = 1.0 if pose % 2 == 0 else -1.0
		view.render_mode = PlaceholderPuppet.RenderMode.ENTITY if pose < 2 else PlaceholderPuppet.RenderMode.PROJECTION
		state.facing = facing
		state.walk_amount = 1
		state.walk_phase = PI / 2
		var first: Image = await _capture(viewport,view)
		state.walk_phase = PI * 1.5
		var second: Image = await _capture(viewport,view)
		var changed: int = 0
		for y in range(430,570):
			for x in range(180,460):
				if first.get_pixel(x,y) != second.get_pixel(x,y):
					changed += 1
		check(changed > 250, "下半身交替迈步 id=%d pose=%d pixels=%d" % [id,pose,changed])
		check(first.save_png(OUTPUT + "/step-%d-%d-a.png" % [id,pose]) == OK, "保存迈步图 A")
		check(second.save_png(OUTPUT + "/step-%d-%d-b.png" % [id,pose]) == OK, "保存迈步图 B")
		state.walk_amount = 0
		var idle_first: Image = await _capture(viewport,view)
		state.walk_phase = .13
		var idle_second: Image = await _capture(viewport,view)
		check(idle_first.get_data() == idle_second.get_data(), "停止后无残留滑步或裙摆变形")
	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame


func _capture_walk_movie() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1536,640)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var bg := ColorRect.new()
	bg.size = Vector2(1536,640)
	bg.color = Color("464b55")
	viewport.add_child(bg)
	var views: Array[PlaceholderPuppet] = []
	for index in range(3):
		var view := PlaceholderPuppet.new()
		var id: int = [0,1,3][index]
		view.puppet_state = PuppetState.new(id if id < 3 else 0)
		view.puppet_state.head_id = id if id < 3 else 0
		view.puppet_state.stage_pos = Vector2((index*512.0+210)/1536.0,.88)
		view.puppet_state.hand_angle = Vector2(.4,1.4)
		view.stage_size = Vector2(1536,640)
		view.figure_height = 380
		view.skin_override = id
		view.render_mode = PlaceholderPuppet.RenderMode.ENTITY
		viewport.add_child(view)
		views.append(view)
	for frame in range(104):
		for view: PlaceholderPuppet in views:
			var state: PuppetState = view.puppet_state
			var direction: float = 1.0 if frame < 56 else -1.0
			var moving: bool = (frame >= 8 and frame < 48) or (frame >= 56 and frame < 96)
			state.walk_amount = 1.0 if moving else 0.0
			if moving:
				state.facing = direction
				state.stage_pos.x += direction * 4.0/1536.0
				state.walk_phase += TAU/24.0
			view.queue_redraw()
		var image: Image = await _capture(viewport,views[0])
		check(image.save_png(OUTPUT + "/walk-%03d.png" % frame) == OK,"保存起停和往返动态帧")
	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame
