extends SceneTree
## Windows GPU 像素回归：法杖在翻面/弯肘/前倾后仍竖直且跟随实际腕点。
var checks: int = 0
var failures: int = 0
const OUTPUT := "res://builds/reference-revision-20261022"
var board: Image

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("REFERENCE_PUPPETS: " + label)

func _run() -> void:
	check(DisplayServer.get_name() != "headless", "需要真实图形驱动")
	if failures:
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	board = Image.create(1920,1280,false,Image.FORMAT_RGBA8)
	for id in [0,1]:
		await _check_neck(id)
	for pose in range(4):
		var viewport := SubViewport.new()
		viewport.size = Vector2i(640,640)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var bg := ColorRect.new()
		bg.size = Vector2(640,640)
		bg.color = Color("d8d0b9")
		viewport.add_child(bg)
		var view := PlaceholderPuppet.new()
		var state := PuppetState.new(0)
		state.head_id = 0
		state.stage_pos = Vector2(.5,.87)
		state.hand_angle = Vector2(.4,1.4)
		state.facing = 1 if pose % 2 == 0 else -1
		if pose >= 2:
			state.elbow_angle = Vector2(.3,.7)
			state.head_tilt = .12
			state.torso_lean = .2
		view.puppet_state = state
		view.stage_size = Vector2(640,640)
		view.figure_height = 380
		view.skin_override = 3
		view.render_mode = PlaceholderPuppet.RenderMode.ENTITY if pose < 2 else PlaceholderPuppet.RenderMode.PROJECTION
		viewport.add_child(view)
		for frame in range(3):
			await process_frame
			await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var wrist: Vector2 = view.hand_screen_position("right")
		var centers: Array[float] = []
		for distance in [55,80,105,130]:
			var xs: Array[int] = []
			var y: int = roundi(wrist.y - distance)
			for x in range(roundi(wrist.x)-12,roundi(wrist.x)+13):
				var color: Color = image.get_pixel(x,y)
				if color.r < .48 and color.g < .48 and color.b < .4:
					xs.append(x)
			check(not xs.is_empty(), "竖杖实际像素 pose=%d dy=%d" % [pose,distance])
			if not xs.is_empty():
				var center: float = (xs[0]+xs[-1])*.5
				centers.append(center)
				check(absf(center-wrist.x) <= 3, "杖轴穿过真实持手腕点")
		if centers.size() == 4:
			check(absf(centers.max()-centers.min()) <= 2, "杖轴竖直且不随腰部转横")
		var ground_y: int = roundi(view.stage_to_screen(state.stage_pos).y)
		for y in [ground_y-12,ground_y,ground_y+12]:
			var ink: bool = false
			for x in range(roundi(wrist.x)-4,roundi(wrist.x)+5):
				var pixel: Color = image.get_pixel(x,y)
				ink = ink or (pixel.r < .48 and pixel.g < .48 and pixel.b < .4)
			check(ink, "杖尾延伸并穿过地面 pose=%d y=%d" % [pose,y])
		check(image.save_png(OUTPUT + "/staff-%d.png" % pose) == OK, "保存杖像素证据")
		if pose < 2:
			board.blit_rect(image,Rect2i(0,0,640,640),Vector2i(1280,pose*640))
		root.remove_child(viewport)
		viewport.queue_free()
		await process_frame
	check(board.save_png(OUTPUT + "/character-check.png") == OK, "保存三角色当前图形证据")
	print("REFERENCE_PUPPETS checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)


func _check_neck(id: int) -> void:
	for pose in range(3):
		var viewport := SubViewport.new()
		viewport.size = Vector2i(640,640)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var bg := ColorRect.new()
		bg.size = Vector2(640,640)
		bg.color = Color("464b55")
		viewport.add_child(bg)
		var view := PlaceholderPuppet.new()
		var state := PuppetState.new(id)
		state.head_id = id
		state.stage_pos = Vector2(.5,.88)
		state.hand_angle = Vector2(.4,1.4)
		state.facing = -1 if pose == 1 else 1
		state.head_tilt = [0.0,PI/6.0,-PI/6.0][pose]
		state.torso_lean = [0.0,.5,-.4][pose]
		view.puppet_state = state
		view.stage_size = Vector2(640,640)
		view.figure_height = 440
		view.render_mode = PlaceholderPuppet.RenderMode.ENTITY
		viewport.add_child(view)
		for frame in range(3):
			await process_frame
			await RenderingServer.frame_post_draw
		var image: Image = viewport.get_texture().get_image()
		var skin: Dictionary = view._skins[str(id)]
		check(skin.has("neck_attachment_ratio"), "新参考图必须有源图颈根定位")
		if skin.has("neck_attachment_ratio"):
			var ratio: Array = skin["neck_attachment_ratio"]
			var ground: Vector2 = view.stage_to_screen(state.stage_pos)
			var neck: Vector2 = ground + Vector2(ratio[0],ratio[1]-.8) * 440
			var transform: Transform2D = view._skin_figure_transform(ground) * view.upper_transform()
			var continuous: bool = true
			# Inspect the visible neck-to-collar path in actual GPU output.
			for distance in range(-11,7):
				var offset := Vector2(0,distance)
				if distance < 0:
					offset = offset.rotated(state.head_tilt)
				var point: Vector2i = Vector2i((transform * (neck + offset)).round())
				var found: bool = false
				for dx in range(-1,2):
					var c: Color = image.get_pixel(point.x+dx,point.y)
					found = found or Vector3(c.r-bg.color.r,c.g-bg.color.g,c.b-bg.color.b).length() > .2
				continuous = continuous and found
			check(continuous, "实际颈部到衣领连续 id=%d pose=%d" % [id,pose])
		check(image.save_png(OUTPUT + "/couple-%d-%d.png" % [id,pose]) == OK, "保存颈部实际渲染")
		if pose < 2:
			board.blit_rect(image,Rect2i(0,0,640,640),Vector2i(id*640,pose*640))
		root.remove_child(viewport)
		viewport.queue_free()
		await process_frame
