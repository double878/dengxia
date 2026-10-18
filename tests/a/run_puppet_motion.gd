extends SceneTree
## 共用人形短跳/躲闪的行为回归；同时守住锁姿与旧记录兼容。
const Controller := preload("res://scripts/a/puppet_controller.gd")
const Reader := preload("res://scripts/a_test/input_reader.gd")
var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PUPPET_MOTION: " + label)


func key(code: Key, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	return event


func _initialize() -> void:
	var controller := Controller.new()
	controller.setup()
	var reader := Reader.new()
	reader.set_controller(controller)
	check(reader.handle_event(key(KEY_W)), "W 触发一次短跳")
	check(controller.has_method("start_motion"), "共用控制器提供短动作入口")
	if failures == 0:
		exercise(controller, reader)
	print("PUPPET_MOTION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func exercise(controller: PuppetController, reader: InputReader) -> void:
	var state: PuppetState = controller.get_controlled()
	state.hand_angle = Vector2(.4, 1.2)
	state.elbow_angle = Vector2(.3, .6)
	var ground: Vector2 = state.stage_pos
	var hands: Vector2 = state.hand_angle
	check(not reader.handle_event(key(KEY_W, true)), "系统重复键不触发")
	var view := preload("res://scripts/a_test/placeholder_puppet.gd").new()
	view.render_mode = view.RenderMode.ENTITY
	view.puppet_state = state
	var grounded_hand: Vector2 = view.hand_screen_position("right")
	controller.tick(.21)
	check(state.air_height > .10 and state.leg_spread > .98, "短跳顶点离地并张开双腿")
	check(
		(
			absf(view.hand_screen_position("right").y - grounded_hand.y + state.air_height * 1080)
			< .01
		),
		"显示和持物腕点同步升高"
	)
	check(
		not controller.begin_drag(0, state.stage_pos * Vector2(1920, 1080) - Vector2(0, 45)),
		"空中不能抓胸签"
	)
	controller.drag_to(Vector2(200, 100))
	controller.set_hand_target("right", Vector2(30, -40), 200)
	controller.set_upper_angle("torso", .6)
	controller.reset_upper_body()
	controller.set_input_map({"left_raise": true, "right_lower": true})
	controller.tick(.04)
	check(state.stage_pos == ground and state.hand_angle == hands, "空中拖身、拖手、抬落手和 R 都不改身形")
	check(state.torso_lean == 0.0, "空中锁定腰姿")
	check(not controller.start_motion("dodge"), "短跳未结束不能叠加躲闪")
	controller.tick(.3)
	check(
		state.air_height == 0 and state.leg_spread == 0 and not controller.motion.active(),
		"半秒内落地并恢复"
	)
	reader.poll_keys()
	controller.tick(.1)
	check(not controller.motion.active(), "按住 W 不会自动连跳")
	for facing: float in [-1.0, 1.0]:
		state.facing = facing
		state.stage_pos.x = .5
		state.torso_lean = .15
		state.stance = .1
		check(reader.handle_event(key(KEY_S)), "S 触发压身后撤")
		controller.tick(.21)
		check(state.stance > .8 and state.stage_pos.x * facing < .5 * facing, "压低身体并向身后撤")
		check(state.facing == facing, "后撤始终保持面朝对手")
		controller.tick(.3)
		check(absf(absf(state.stage_pos.x - .5) * 1920 - 92) < .01, "后撤一步后停下")
		check(
			is_equal_approx(state.torso_lean, .15) and is_equal_approx(state.stance, .1),
			"结束恢复原腰姿和站姿"
		)
	state.stage_pos.x = .01
	state.facing = 1
	controller.start_motion("dodge")
	controller.tick(.5)
	check(state.stage_pos.x == 0, "台边后撤夹紧，不越界")
	controller.start_motion("jump")
	controller.tick(.2)
	controller.set_controlled_puppet(1)
	check(state.air_height == 0 and not controller.motion.active(), "切人立即清理旧人的腾空")
	check(controller.get_controlled().air_height == 0, "动作不串给接手者")
	reader.set_enabled(false)
	check(not reader.handle_event(key(KEY_W)), "暂停禁用时不开始跳跃")
	reader.set_enabled(true)
	controller.start_motion("jump")
	controller.tick(.2)
	check(controller.hook_current(), "可在动作中挂起影人")
	check(controller.get_puppet(1).air_height == 0 and not controller.motion.active(), "挂起清理腾空")
	for source: Dictionary in controller.take_events():
		var event := CTimedEvent.new(
			0, StringName(source.kind), source.object_id, "", source.payload
		)
		check(event.validate().is_empty(), "动作事件可正式记录 " + source.kind)
	view.free()
	_bridge(controller)
	_replay(controller)


func _bridge(controller: PuppetController) -> void:
	controller.setup()
	var path := preload("res://scripts/a/stage_walk_path.gd").new()
	controller.set_walk_path(path)
	var state: PuppetState = controller.get_controlled()
	state.stage_pos.x = .45
	state.stage_pos.y = path.height_at(.45)
	var ground: Vector2 = state.stage_pos
	controller.start_motion("jump")
	controller.tick(.2)
	controller.tick(.3)
	check(state.stage_pos == ground and state.air_height == 0, "第一关短跳落回同一桥面点")
	controller.start_motion("dodge")
	controller.tick(.5)
	check(is_equal_approx(state.stage_pos.y, path.height_at(state.stage_pos.x)), "桥上后撤沿当前桥面落脚")


func _replay(controller: PuppetController) -> void:
	controller.setup()
	var views: Array = []
	for state: PuppetState in controller.puppets:
		views.append(state.to_dict())
	var first: CSnapshot = CSnapshot.from_views(0, views)
	views[0].air_height = .1
	views[0].leg_spread = 1.0
	views[0].body_angle = -.6
	var second: CSnapshot = CSnapshot.from_views(100, views)
	var record := CPerformanceRecord.new(1, 100)
	record.append_snapshot(first)
	record.append_snapshot(second)
	var player := CReplayPlayer.new()
	check(player.load(record), "回放装载人形短动作")
	var halfway: Dictionary = player.sample(50).puppets[0]
	for field: String in ["air_height", "leg_spread", "body_angle"]:
		check(second.changed_fields(first).has("puppets[0]." + field), "新姿态触发补采样 " + field)
		check(absf(halfway[field] - views[0][field] * .5) < .00001, "回放按真实姿态插值 " + field)
		views[0].erase(field)
	var legacy: CSnapshot = CSnapshot.from_views(0, views)
	check(
		(
			legacy.puppets[0].air_height == 0
			and legacy.puppets[0].leg_spread == 0
			and legacy.puppets[0].body_angle == 0
		),
		"旧记录缺省站地姿态"
	)
	check(CReplayVerifier.new().verify(record).ok, "独立采样保真校验通过")
