extends "res://tests/c/run_act2_opening.gd"
## 复用真实 viewport 输入工具，验收首次入口、遮挡及恢复规则。


func _run() -> void:
	var opening: Node = load("res://scenes/act2/opening.tscn").instantiate()
	root.add_child(opening)
	opening.set_process(false)
	var controller: PuppetController = opening.get("controller")
	var fahai: PuppetState = controller.get_puppet(0)
	var xuxian: PuppetState = controller.get_puppet(1)
	key(KEY_1)
	# 独立验证入口几何；首句结束后的上场许可由对白回归覆盖。
	opening.dialogue.phase = "wait_greeting"
	key(KEY_2)
	check(fahai.stage_pos.x * 1920 > 1655, "法海首次没有出现在树的右后方")
	check(fahai.stage_pos.x * 1920 < 1824, "法海首次在幕布右缘之外")
	check(absf(xuxian.stage_pos.x * 1920 - 434.4) < 2.0, "许仙首次没有在门洞中央")
	check(fahai.facing == -1.0 and xuxian.facing == 1.0, "两人首次未面向出场方向")
	check(controller.controlled_id == -1, "数字键自动接手")
	click(Vector2(1770, 550), MOUSE_BUTTON_RIGHT)
	check(opening.get("on_stage").has(0), "右键点树的遮挡区域误收走法海")
	key(KEY_1)
	var original_fahai: Vector2 = fahai.stage_pos
	var original_xuxian: Vector2 = xuxian.stage_pos
	opening._process(1.0)
	check(fahai.stage_pos == original_fahai and xuxian.stage_pos == original_xuxian, "出场自动移动")
	var views: Array = opening.get("_views")
	var projection_views: Array = opening.get("_surface").projection_views
	for id in range(2):
		if id == 0:
			check(views[id].get("entrance_mask") != null, "法海首次上场没有树的遮挡")
			check(
				projection_views[id].get("entrance_mask") == views[id].get("entrance_mask"),
				"实体与投影遮挡不一致"
			)
		else:
			check(
				(
					views[id].get("entrance_mask") == null
					and projection_views[id].get("entrance_mask") == null
				),
				"许仙首次上场仍被门遮挡"
			)
		await test_initial_visibility(opening, id)
	key(KEY_SPACE)
	check(controller.controlled_id == 0, "空格没有接手法海")
	press(Vector2(1770, 550))
	check(not controller.is_dragging(), "左键点树的遮挡区域误抓法海胸签")
	click(Vector2(1770, 550), MOUSE_BUTTON_LEFT, false)
	drag_hand(opening, -30)
	check(
		fahai.stage_pos.x < original_fahai.x and xuxian.stage_pos == original_xuxian,
		"法海不能手动向左出场或带动了许仙"
	)
	var halfway: Vector2 = fahai.stage_pos
	var halfway_mask: Texture2D = views[0].get("entrance_mask")
	fahai.hand_angle = Vector2(0.4, 1.2)
	opening._exit(0)
	key(KEY_1)
	check(fahai.stage_pos == halfway and fahai.hand_angle == Vector2(0.4, 1.2), "部分出场后再上场重置了位置或姿势")
	check(views[0].get("entrance_mask") == halfway_mask, "再上场没有恢复部分出场进度")
	key(KEY_SPACE)
	check(controller.controlled_id == 0, "再上场后空格没有接手法海")
	key(KEY_ESCAPE)
	drag_hand(opening, -300)
	key(KEY_1)
	opening._process(1.0)
	check(
		fahai.stage_pos == halfway and views[0].get("entrance_mask") == halfway_mask,
		"暂停时入口位置或遮挡仍变化"
	)
	key(KEY_ESCAPE)
	drag_hand(opening, -330)
	check(
		views[0].get("entrance_mask") == null and projection_views[0].get("entrance_mask") == null,
		"法海完全走出后没有解除实体和投影遮挡"
	)
	await capture("entrance-fahai-out")
	drag_hand(opening, 360)
	check(views[0].get("entrance_mask") == null, "法海返回树旁又被遮挡")
	key(KEY_SPACE)
	check(controller.controlled_id == 1, "空格没有接手许仙")
	press(Vector2(450, 600))
	check(controller.is_dragging(), "门中直接上场的许仙不能抓胸签")
	click(Vector2(450, 600), MOUSE_BUTTON_LEFT, false)
	drag_hand(opening, 25)
	check(xuxian.stage_pos.x > original_xuxian.x, "许仙不能手动向右出场")
	check(views[1].get("entrance_mask") == null, "许仙移动后又被门遮挡")
	drag_hand(opening, 200)
	check(
		views[1].get("entrance_mask") == null and projection_views[1].get("entrance_mask") == null,
		"许仙完全出门后遮挡没有解除"
	)
	await capture("entrance-both-out")
	drag_hand(opening, -225)
	check(views[1].get("entrance_mask") == null, "许仙回到门前又被遮挡")
	var place: Vector2 = xuxian.stage_pos
	var wrist: Vector2 = views[1].hand_screen_position("right")
	click(wrist, MOUSE_BUTTON_RIGHT)
	check(not opening.get("on_stage").has(1) and controller.controlled_id == -1, "右键没有退场和放手")
	key(KEY_2)
	key(KEY_2)
	check(
		xuxian.stage_pos == place and views[1].get("entrance_mask") == null, "退场后再次或重复上场重置了位置和出场进度"
	)
	check(controller.controlled_id == -1, "再上场自动接手")
	opening.queue_free()
	await process_frame
	print("ACT2_ENTRANCES checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func drag_hand(opening: Node, dx: float) -> void:
	press(Vector2(960, 856))
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(dx, 0)
	root.push_input(motion, true)
	opening._process(0.15)
	click(Vector2(960 + dx, 856), MOUSE_BUTTON_LEFT, false)
	opening._refresh_views()


func test_initial_visibility(opening: Node, id: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var views: Array = opening.get("_views")
	var surface: StageSurface = opening.get("_surface")
	var view: PlaceholderPuppet = views[id]
	var projected: PlaceholderPuppet = surface.projection_views[id]
	var mask: Texture2D = view.get("entrance_mask")
	opening._exit(id)
	await settle_render()
	var absent: Image = root.get_texture().get_image()
	var absent_projection: Image = surface.projection_viewport.get_texture().get_image()
	opening._enter(id)
	await settle_render()
	var sliver: Image = root.get_texture().get_image()
	var sliver_projection: Image = surface.projection_viewport.get_texture().get_image()
	view.set("entrance_mask", null)
	projected.set("entrance_mask", null)
	await settle_render()
	var full: Image = root.get_texture().get_image()
	var full_projection: Image = surface.projection_viewport.get_texture().get_image()
	var region := Rect2(1480, 410, 360, 260) if id == 0 else Rect2(370, 410, 300, 260)
	for pair: Array in [
		[absent, sliver, full], [absent_projection, sliver_projection, full_projection]
	]:
		var partial_pixels: int = changed_pixels(pair[0], pair[1], region)
		var full_pixels: int = changed_pixels(pair[0], pair[2], region)
		print("ENTRANCE_VISIBLE id=%d partial=%d full=%d" % [id, partial_pixels, full_pixels])
		check(partial_pixels > 5, "初始完全隐藏")
		if id == 0:
			check(partial_pixels < full_pixels * 0.65, "法海初始露出大部分身体，树没有遮挡")
		else:
			check(partial_pixels == full_pixels, "许仙在门中没有完整显示")
	view.set("entrance_mask", mask)
	projected.set("entrance_mask", mask)
	await capture("entrance-%s-start" % ("fahai" if id == 0 else "xuxian"))


func settle_render() -> void:
	for _i in range(3):
		await process_frame
		await RenderingServer.frame_post_draw


func changed_pixels(before: Image, after: Image, region: Rect2) -> int:
	var scale: Vector2 = Vector2(before.get_size()) / Vector2(1920, 1080)
	var changed: int = 0
	for y in range(int(region.position.y * scale.y), int(region.end.y * scale.y)):
		for x in range(int(region.position.x * scale.x), int(region.end.x * scale.x)):
			var a: Color = before.get_pixel(x, y)
			var b: Color = after.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.10:
				changed += 1
	return changed
