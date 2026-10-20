extends SceneTree
## 上身姿态、输入与录放的定向回归；可单独运行。

const TestBase := preload("res://tests/a/a_test_base.gd")
const State := preload("res://scripts/a/puppet_state.gd")
const View := preload("res://scripts/a_test/placeholder_puppet.gd")
const Controller := preload("res://scripts/a/puppet_controller.gd")
const Reader := preload("res://scripts/a_test/input_reader.gd")
const TimedEvent := preload("res://scripts/c/c_timed_event.gd")


func _initialize() -> void:
	var t := TestBase.new()
	t.begin("上半身共用姿态几何存在")
	if not t.check(FileAccess.file_exists("res://scripts/a/upper_body_pose.gd"), "缺少上身姿态计算"):
		quit(t.report())
		return
	var pose: Variant = load("res://scripts/a/upper_body_pose.gd")
	_test_geometry(t, pose)
	_test_view(t)
	_test_input(t)
	_test_pose_events(t)
	_test_capture_replay(t)
	_test_hand_judgment(t, pose)
	quit(t.report())


func _test_geometry(t: ATestBase, pose: Variant) -> void:
	t.begin("拖手解算保持两段长度，边界与肩点有限")
	for right in [false, true]:
		var side: float = 1.0 if right else -1.0
		for offset in [
			Vector2(side * 30, -12),
			Vector2(side * 22, 22),
			Vector2(0, -62),
			Vector2(side * 150, -90),
			Vector2.ZERO
		]:
			var angles: Vector2 = pose.solve_arm(offset, right, 200.0)
			var points: Dictionary = pose.arm_points(Vector2.ZERO, angles.x, angles.y, right, 200.0)
			t.check(angles.is_finite(), "肩点和越界输入不能产生非有限角度")
			t.check_approx(points.elbow.length(), 32.0, 0.001, "上臂长度固定")
			t.check_approx(points.wrist.distance_to(points.elbow), 30.0, 0.001, "前臂长度固定")
			if offset.length() > 20 and offset.length() < 50:
				t.check(points.wrist.distance_to(offset) < 0.001, "可达手目标必须到位")
			if offset == Vector2(0, -62):
				t.check(points.wrist.distance_to(offset) < 0.001, "举过头顶不能跳到收手边界")
			t.check_in_range(angles.y, 0.0, deg_to_rad(150), "肘部不能反折")
	t.finish("两侧独立弯肘，越界保持长度")


func _test_view(t: ATestBase) -> void:
	t.begin("弯肘和头腰改变上身，保持下半身与只读显示")
	var state := State.new(0)
	state.head_id = 0
	state.is_controlled = true
	state.hand_angle = Vector2(PI * 0.5, PI * 0.5)
	var view := View.new()
	view.render_mode = View.RenderMode.ENTITY
	view.puppet_state = state
	var straight: Vector2 = view.hand_screen_position("right")
	state.set("elbow_angle", Vector2(0, PI * 0.5))
	var bent: Vector2 = view.hand_screen_position("right")
	t.check(bent.distance_to(straight) > 20, "弯肘应改变实际手的位置")
	var lower: Vector2 = state.stage_pos
	state.set("torso_lean", deg_to_rad(30))
	state.set("head_tilt", deg_to_rad(20))
	var before: Dictionary = state.to_dict().duplicate(true)
	t.check(view.hand_screen_position("right").distance_to(bent) > 10, "腰转动应带动手")
	t.check_eq(state.to_dict(), before, "几何查询不能写状态")
	t.check_eq(state.stage_pos, lower, "上身姿态不能移动脚点")
	t.check(
		before.has("elbow_angle") and before.has("head_tilt") and before.has("torso_lean"),
		"实际关节须进入录放数据"
	)
	view.free()
	t.finish("实体查询与姿态数据共用同一几何")


func _button(point: Vector2, pressed: bool, alt: bool = false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = pressed
	event.alt_pressed = alt
	return event


func _motion(delta: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = delta
	return event


func _test_input(t: ATestBase) -> void:
	t.begin("实体拖手、头腰、复位与输入释放")
	var controller := Controller.new()
	controller.setup(2)
	var state: PuppetState = controller.get_controlled()
	state.hand_angle.y = PI * 0.5
	var view := View.new()
	view.render_mode = View.RenderMode.ENTITY
	view.figure_height = 200
	view.puppet_state = state
	var reader := Reader.new()
	reader.set_controller(controller)
	if not t.check(reader.has_method("set_views"), "正式输入需接入实体几何"):
		view.free()
		return
	reader.call("set_views", [view])
	var before: Dictionary = state.to_dict()
	var wrist: Vector2 = view.hand_screen_position("right")
	var movement := Vector2(signf(view.torso_screen_position().x - wrist.x) * 20.0, -25.0)
	t.check(reader.handle_event(_button(wrist + Vector2(3, 2), true)), "应能抓住手")
	t.check(view.hand_screen_position("right").is_equal_approx(wrist), "抓取不跳变")
	reader.handle_event(_motion(movement))
	t.check(view.hand_screen_position("right").distance_to(wrist + movement) < 0.01, "拖手必须到达实际目标")
	t.check(state.elbow_angle.y > 0.1, "靠近肩时应自动弯肘")
	controller.set_input_map({"right_lower": true, "left_raise": true})
	controller.tick(1.0 / 60.0)
	t.check(view.hand_screen_position("right").distance_to(wrist + movement) < 0.01, "同手键盘不能覆盖鼠标")
	t.check(state.hand_angle.x > 0, "另一只手仍能用快捷键")
	reader.handle_event(_button(Vector2.ZERO, false))
	var held: Vector2 = state.elbow_angle
	controller.set_input_map({})
	controller.tick(1.0 / 60.0)
	t.check_eq(state.elbow_angle, held, "松开后保留弯肘")
	t.check_eq(state.stage_pos, Vector2(before.stage_pos.x, before.stage_pos.y), "拖手不改变下半身位置")
	reader.handle_event(_button(view.head_screen_position(), true))
	reader.handle_event(_motion(Vector2(30, 0)))
	t.check(absf(state.head_tilt) > 0.01, "拖头应改变俯仰")
	reader.handle_event(_button(Vector2.ZERO, false))
	reader.handle_event(_button(view.call("torso_screen_position"), true, true))
	reader.handle_event(_motion(Vector2(35, 0)))
	t.check(state.torso_lean > 0.1, "Alt 拖躯干应前倾")
	state.stance = 0.3
	state.turn_progress = 0.7
	state.walk_phase = 1.1
	state.walk_amount = 0.4
	var lower_before: Dictionary = state.to_dict()
	var reset := InputEventKey.new()
	reset.keycode = KEY_R
	reset.pressed = true
	t.check(reader.handle_event(reset), "R 应由共用输入接收")
	t.check(state.hand_angle == Vector2.ZERO and state.elbow_angle == Vector2.ZERO, "R 恢复双臂")
	t.check(state.head_tilt == 0 and state.torso_lean == 0, "R 恢复头腰")
	t.check(not reader.is_drag_active(), "R 结束旧拖动")
	t.check_eq(state.stage_pos, Vector2(before.stage_pos.x, before.stage_pos.y), "R 不移动脚点")
	for key in [
		"stance",
		"facing",
		"turn_progress",
		"walk_phase",
		"walk_amount",
		"head_id",
		"hook_slot",
		"is_controlled"
	]:
		t.check_eq(state.to_dict()[key], lower_before[key], "R 保留 " + key)
	reader.set_enabled(false)
	t.check(not reader.handle_event(_button(view.hand_screen_position("right"), true)), "暂停不接受拖手")
	reader.set_enabled(true)
	reader.handle_event(_button(view.hand_screen_position("right"), true))
	controller.set_controlled_puppet(1)
	reader.handle_event(_motion(Vector2(40, -40)))
	t.check_eq(controller.get_puppet(1).hand_angle, Vector2.ZERO, "换人后旧拖动不能串到新影人")
	view.free()
	t.finish("正式鼠标事件与键盘复位遵守上身边界")


func _test_pose_events(t: ATestBase) -> void:
	t.begin("拖手和复位事件可进入正式记录")
	var controller := Controller.new()
	controller.setup()
	controller.set_hand_target("left", Vector2(-30, -12), 200)
	controller.reset_upper_body()
	for source: Dictionary in controller.take_events():
		var event := TimedEvent.new(
			0, StringName(source.kind), source.object_id, "", source.payload
		)
		t.check(event.validate().is_empty(), "记录器应接受 " + str(source.kind))
	t.finish("上身操作事件不被白名单拒写")


func _test_capture_replay(t: ATestBase) -> void:
	t.begin("上身快照、插值、旧记录与瞬时复位")
	var Snapshot := preload("res://scripts/c/c_snapshot.gd")
	var states: Array = [State.new(0), State.new(1), State.new(2)]
	var views: Array = []
	for state: PuppetState in states:
		views.append(state.to_dict())
	var first: Variant = Snapshot.from_views(0, views)
	states[0].elbow_angle = Vector2(0.8, 1.2)
	states[0].head_tilt = 0.3
	states[0].torso_lean = 0.4
	views[0] = states[0].to_dict()
	var posed: Variant = Snapshot.from_views(100, views)
	t.check_eq(posed.puppets[0].get("elbow_angle", {}), views[0].elbow_angle, "快照保留双肘")
	for key in ["elbow_angle", "head_tilt", "torso_lean"]:
		t.check(posed.changed_fields(first).has("puppets[0]." + key), "姿态变化触发补采样 " + key)
	var record := preload("res://scripts/c/c_performance_record.gd").new(1, 200)
	record.append_snapshot(first)
	record.append_snapshot(posed)
	var reset: Variant = Snapshot.from_views(200, [State.new(0).to_dict(), views[1], views[2]])
	record.append_snapshot(reset)
	record.append_event(TimedEvent.new(200, &"upper_body_reset", 0))
	var player := preload("res://scripts/c/c_replay_player.gd").new()
	t.check(player.load(record), "正式播放器装载记录")
	var midway: Dictionary = player.sample(50).puppets[0]
	t.check_approx(float(midway.get("head_tilt", -1)), 0.15, 0.00001, "头部按实际角插值")
	t.check_approx(float(midway.get("torso_lean", -1)), 0.2, 0.00001, "躯干按实际角插值")
	t.check_approx(float(midway.get("elbow_angle", {}).get("right", -1)), 0.6, 0.00001, "肘角插值")
	t.check_eq(
		player.sample(199).puppets[0].get("elbow_angle", {}), views[0].elbow_angle, "R 前不能提前收肘"
	)
	t.check_approx(
		float(player.sample(199).puppets[0].get("head_tilt", -1)), 0.3, 0.00001, "R 前不能提前归头"
	)
	t.check_approx(
		float(player.sample(200).puppets[0].get("head_tilt", -1)), 0.0, 0.00001, "R 在原时间复位"
	)
	t.check(preload("res://scripts/c/c_replay_verifier.gd").new().verify(record).ok, "独立核对涵盖新姿态")
	for view: Dictionary in views:
		for key in ["elbow_angle", "head_tilt", "torso_lean"]:
			view.erase(key)
	var legacy: Variant = Snapshot.from_views(0, views)
	t.check_eq(legacy.puppets[0].get("elbow_angle", {}), {"left": 0.0, "right": 0.0}, "旧数据缺省直臂")
	t.check_eq(legacy.puppets[0].get("head_tilt", -1), 0.0, "旧数据缺省头归正")
	t.finish("实际姿态完整录放，复位不提前")


func _test_hand_judgment(t: ATestBase, pose: Variant) -> void:
	t.begin("接伞和抬手读实际腕点")
	var umbrella := preload("res://scripts/a/umbrella_controller.gd").new()
	var states: Array = [State.new(0), State.new(1), State.new(2)]
	states[0].stage_pos.x = 0.236
	states[1].stage_pos.x = 0.13
	states[0].hand_angle.x = PI * 0.5
	states[1].hand_angle.y = PI * 0.5
	umbrella.setup(StageDef.make_level1(), states)
	t.check(umbrella.alignment().aligned, "原打伞位仍可接伞")
	states[0].elbow_angle.x = PI * 0.5
	t.check(not umbrella.alignment().aligned, "同肩角弯肘后手高不同不能接伞")
	var performance := preload("res://scripts/a/performance_system.gd").new()
	performance.setup([], null, states)
	t.check(float(performance._metric_value("hand", 0)) > PI * 0.5 + 0.1, "抬手指标读取弯肘后的高度")
	for id in [0, 1, 2]:
		var state: PuppetState = states[id]
		state.head_id = id
		state.torso_lean = 0.4
		state.stance = 0.3
		state.walk_phase = 0.7
		state.walk_amount = 0.8
		var view := View.new()
		view.render_mode = View.RenderMode.ENTITY
		view.puppet_state = state
		var wrist: Vector2 = view.hand_screen_position("left")
		var expected: float = (
			(view.stage_to_screen(state.stage_pos).y - wrist.y) / view.figure_height
		)
		t.check_approx(pose.hand_height(state, "left"), expected, 0.00001, "判定与身体美术朝向的腕高一致")
		view.free()
	t.finish("肘腰进入接伞与抬手判定")
