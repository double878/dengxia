extends RefCounted
## 防止灯距改变实体挂点、显露度隐藏操作对象，以及火光使用不可重现的墙钟。

const TestBase := preload("res://tests/a/a_test_base.gd")
const PuppetView := preload("res://scripts/a_test/placeholder_puppet.gd")
const LampView := preload("res://scripts/a_test/placeholder_lamp.gd")
const PuppetData := preload("res://scripts/a/puppet_state.gd")
const LampData := preload("res://scripts/a/lamp_state.gd")
const Clock := preload("res://scripts/a/music_clock.gd")
const UmbrellaView := preload("res://scripts/b/umbrella_visual.gd")


func run_all() -> Dictionary:
	var t: ATestBase = TestBase.new()
	_test_entity_geometry(t)
	_test_projection_geometry(t)
	_test_female_shoulders(t)
	_test_flame_time_and_feedback(t)
	_test_prop_attachments(t)
	return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed}


func _view(mode: int) -> PlaceholderPuppet:
	var view: PlaceholderPuppet = PuppetView.new()
	view.puppet_state = PuppetData.new(0)
	view.puppet_state.head_id = 0
	view.puppet_state.stage_pos = Vector2(0.5, 0.5)
	view.puppet_state.hand_angle = Vector2(PI * 0.5, PI * 0.2)
	view.lamp_state = LampData.new()
	view.set("render_mode", mode)
	return view


func _test_entity_geometry(t: ATestBase) -> void:
	t.begin("实体尺寸、手腕和命中不受灯距/显露度影响")
	var view: PlaceholderPuppet = _view(1)
	var before: Dictionary = view.puppet_state.to_dict().duplicate(true)
	view.lamp_state.distance = 0.0
	view.lamp_state.exposure = 0.0
	var height: float = view.figure_px_height()
	var left: Vector2 = view.hand_screen_position("left")
	var right: Vector2 = view.hand_screen_position("right")
	var tag: Vector2 = view.chest_tag_screen()
	view.lamp_state.distance = 1.0
	view.lamp_state.exposure = 1.0
	t.check_approx(view.figure_px_height(), height, 0.001, "移动灯不能改变实体物件尺寸")
	t.check(view.hand_screen_position("left").is_equal_approx(left), "实体左腕不能随灯移动")
	t.check(view.hand_screen_position("right").is_equal_approx(right), "实体右腕不能随灯移动")
	t.check(view.chest_tag_screen().is_equal_approx(tag), "实体命中点应保持原坐标")
	view.lamp_state.exposure = 0.0
	t.check_approx(view.exposure_alpha(), 1.0, 0.001, "低显露仍可辨认并操作实体")
	t.check_eq(view.puppet_state.to_dict(), before, "显示不能改写姿态状态")
	view.free()
	t.finish("灯操作只改变幕影，不改变实体与输入坐标")


func _test_projection_geometry(t: ATestBase) -> void:
	t.begin("全部影人及挂起者的投影响应灯距")
	for id in range(3):
		var view: PlaceholderPuppet = _view(2)
		view.puppet_state.puppet_id = id
		view.puppet_state.head_id = id
		view.puppet_state.hook_slot = 0 if id > 0 else -1
		view.lamp_state.distance = 0.0
		var far_height: float = view.figure_px_height()
		view.lamp_state.distance = 1.0
		t.check(view.figure_px_height() > far_height * 1.5, "滚轮应明显放大全场投影，含挂起者")
		var centre: Vector2 = view.stage_to_screen(view.puppet_state.stage_pos)
		var first: Vector2 = view.hand_screen_position("left")
		view.puppet_state.facing *= -1.0
		var flipped: Vector2 = view.hand_screen_position("left")
		t.check_approx(first.x + flipped.x, centre.x * 2.0, 0.01, "投影的手和身体一起翻面")
		t.check_approx(first.y, flipped.y, 0.01, "翻面保持腕高")
		view.free()
	t.finish("同一灯距作用于所有在场实体的影像")


func _test_female_shoulders(t: ATestBase) -> void:
	t.begin("女性肩间距收窄，双臂长度与道具挂点连续")
	for id in [0, 2]:
		for mode in [0, 1, 2]:
			var view: PlaceholderPuppet = _view(mode)
			view.puppet_state.puppet_id = id
			view.puppet_state.hand_angle = Vector2.ZERO
			for stance in [0.0, 1.0]:
				view.puppet_state.stance = stance
				var height: float = view.figure_px_height()
				var left: Vector2 = view.hand_screen_position("left")
				var right: Vector2 = view.hand_screen_position("right")
				# 垂臂时腕间距就是肩间距，不依赖绘制端内部的比例配置。
				t.check_in_range(
					absf(right.x - left.x) / height, 0.10, 0.17, "白素贞和小青应有窄肩，站蹲与三种显示口径一致"
				)
				var centre: Vector2 = view.stage_to_screen(view.puppet_state.stage_pos)
				for angle in [-PI * 0.5, 0.0, PI * 0.5, PI]:
					view.puppet_state.hand_angle = Vector2(angle, angle)
					for hand: String in ["left", "right"]:
						var wrist: Vector2 = view.hand_screen_position(hand)
						var shoulder := Vector2(
							left.x if hand == "left" else right.x, centre.y - height * 0.80
						)
						t.check_approx(
							wrist.distance_to(shoulder) / height, 0.31, 0.001, "收肩不能拉长、缩短或断开手腕运动链"
						)
				view.puppet_state.hand_angle = Vector2.ZERO
			view.free()
	var male: PlaceholderPuppet = _view(1)
	male.puppet_state.puppet_id = 1
	male.puppet_state.hand_angle = Vector2.ZERO
	t.check_approx(
		(
			male.hand_screen_position("left").distance_to(male.hand_screen_position("right"))
			/ male.figure_px_height()
		),
		0.21,
		0.001,
		"许仙仍使用原肩间距"
	)
	male.free()
	t.finish("美术收肩不改变臂长、手角及原状态语义")


func _test_flame_time_and_feedback(t: ATestBase) -> void:
	t.begin("火光可重现、暂停冻结且合拍更稳")
	var view: PlaceholderLamp = LampView.new()
	view.lamp = LampData.new()
	if not t.check(view.has_method("set_visual_time"), "油灯须接受统一视觉时间"):
		view.free()
		t.finish("当前油灯还没有可重现的视觉时钟接口")
		return
	var clock: MusicClock = Clock.new()
	clock.start()
	clock.update(0.25)
	view.call("set_visual_time", clock.get_real_time_ms(), clock.get_song_time_ms(), 96.0)
	var sample: Dictionary = view.call("lighting_sample")
	clock.pause()
	clock.update(5.0)
	view.call("set_visual_time", clock.get_real_time_ms(), clock.get_song_time_ms(), 96.0)
	t.check_eq(view.call("lighting_sample"), sample, "暂停五秒也必须保持同一火光样本")
	clock.resume()
	clock.update(0.3)
	view.call("set_visual_time", clock.get_real_time_ms(), clock.get_song_time_ms(), 96.0)
	t.check(view.call("lighting_sample") != sample, "恢复后自然火光应继续变化")
	view.lamp.flame_feedback = 1.0
	var stable: Dictionary = view.call("lighting_sample")
	view.lamp.flame_feedback = 0.0
	var unstable: Dictionary = view.call("lighting_sample")
	t.check(float(stable["shake_amplitude"]) < float(unstable["shake_amplitude"]), "高合拍不能比低合拍更抖")
	var lamp_before: Dictionary = view.lamp.to_dict().duplicate(true)
	for ms in range(0, 10000, 83):
		view.call("set_visual_time", ms, ms, 96.0)
		var frame: Dictionary = view.call("lighting_sample")
		t.check_in_range(float(frame["cloth_flicker"]), 0.96, 1.04, "整块幕亮度波动须受限")
		t.check_finite(float(frame["tip_x"]), "火苗位置必须有限")
	t.check_eq(view.lamp.to_dict(), lamp_before, "自然火光不得扣油或修改反馈")
	view.free()
	t.finish("既有时钟决定画面，反馈只改变稳定程度")


func _test_prop_attachments(t: ATestBase) -> void:
	t.begin("实体伞和投影伞分别跟随各自手腕与交接")
	var views: Array = []
	var states: Array = []
	# 🔴 站位**由判据算出，不写死**。旧写法硬写「白素贞 0.236 / 许仙 0.13」，那是加号口径
	#    （许仙在台左 0.13、交接窗口在他的右侧 0.176~0.296）时代的数；两轮站位翻面之后
	#    （许仙到桥头 0.5285、两位娘子到柳树下）她想接伞必须站在他**左**边，
	#    硬写的 0.236 早已落在窗口之外——接伞根本不会发生，本测试的两条断言于是连锁误报。
	#    （同一条教训 `tests/a/test_umbrella.gd` 已经吃过一次：那里也曾硬写 0.13。）
	var xuxian_x: float = StageDef.LEVEL1_XUXIAN_X
	var join: Vector2 = UmbrellaController.join_window_x(xuxian_x)
	var borrow_x: float = (join.x + join.y) * 0.5
	for id in range(3):
		var view: PlaceholderPuppet = _view(1)
		view.puppet_state.puppet_id = id
		view.puppet_state.head_id = id
		var at_x: float = join.x - 0.05  ## 小青：不参与判定，随便站在窗口外侧
		if id == UmbrellaController.XUXIAN_ID:
			at_x = xuxian_x
		elif id == UmbrellaController.BAISUZHEN_ID:
			at_x = borrow_x  ## 窗口中心：那里两只手正好碰上（接伞条件之一）
		view.puppet_state.stage_pos = Vector2(at_x, 0.50)
		view.puppet_state.hand_angle = Vector2(PI * 0.5, PI * 0.5)
		if id == UmbrellaController.XUXIAN_ID:
			# 许仙把伞**托在头顶**（用户 2026-10-16 参考图）。这正是「两人握在伞杆不同高度」、
			# 因而交接必须走递伞过渡而不是瞬间落位的来源。
			view.puppet_state.hand_angle.y = StageDef.LEVEL1_XUXIAN_UMBRELLA_RAISE_RAD
		views.append(view)
		states.append(view.puppet_state)
	var controller := UmbrellaController.new()
	controller.setup(StageDef.make_level1(), states)
	var prop := UmbrellaView.new()
	prop.views = views
	prop.umbrella = controller
	for mode in [1, 2]:
		for view: PlaceholderPuppet in views:
			view.set("render_mode", mode)
		for distance: float in [0.0, 1.0]:
			for view: PlaceholderPuppet in views:
				view.lamp_state.distance = distance
			var data: Dictionary = prop.geometry()
			t.check(
				(data["hand"] as Vector2).is_equal_approx(
					views[UmbrellaController.XUXIAN_ID].hand_screen_position("right")
				),
				"两种灯距下伞柄握点与相应腕点一致"
			)
	controller.update(8750, [])
	t.check_eq(controller.holder_id_of(), 0, "样例确实通过原控制器接伞")
	# 接伞是一次**真实的递伞过渡**：他的手在头顶（举伞 140°）、她握在 90° 的打伞位，
	# 两只手高度不同，伞必须从高处那只手过渡过来、不能瞬间落位。
	# ⚠️ 旧版这一段测的是「低手**还伞**」的过渡——还伞通路已随 2026-10-16 流程简化删除
	#    （见 `UmbrellaController` 头注），故改在**接伞**那一刻查同一个读数。
	t.check(controller.handing_off, "接伞那一刻进入真实递伞过渡")
	t.check_eq(
		controller.handoff_from_id(), UmbrellaController.XUXIAN_ID, "过渡的起点应是许仙"
	)
	for mode in [1, 2]:
		for view: PlaceholderPuppet in views:
			view.set("render_mode", mode)
		var data: Dictionary = prop.geometry()
		# 🔴 方向必须与控制器记录的一致（从**许仙右手**到她**左手**）：反过来写只有在
		#    过渡进度落在 0 或 1 时才碰巧相等，中途就会静默失真。
		var from: Vector2 = views[UmbrellaController.XUXIAN_ID].hand_screen_position("right")
		var to: Vector2 = views[UmbrellaController.BAISUZHEN_ID].hand_screen_position("left")
		t.check(
			(data["hand"] as Vector2).is_equal_approx(from.lerp(to, controller.handoff_blend())),
			"交接时实体与投影各自在对应腕点间过渡"
		)
	prop.free()
	for view: PlaceholderPuppet in views:
		view.free()
	t.finish("同一归属与过渡驱动两套道具几何")
