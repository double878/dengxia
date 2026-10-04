extends RefCounted
class_name TestPuppetControls
## 切片 1 的行为测试：16 条，覆盖数据契约、边界、冲突、事件时序与挂起/换头。
## 通过 controls_harness 复用测试场景同一段步进逻辑，因此这里通过的行为
## 就是图形场景里玩家会触发的行为。

const ATestBaseScript := preload("res://tests/a/a_test_base.gd")
const HarnessScript := preload("res://scripts/a_test/controls_harness.gd")
const PuppetStateScript := preload("res://scripts/a/puppet_state.gd")
const PuppetControllerScript := preload("res://scripts/a/puppet_controller.gd")
## HUD 的空格提示文案是呈现层规则，但它决定玩家「看到的能力」，
## 所以要能被无头测试直接断言——因此从场景脚本里取那个静态纯函数。
const Level1ASceneScript := preload("res://scripts/a_test/level1_a_scene.gd")

const STAGE_W: float = 1920.0
const STAGE_H: float = 1080.0


## 每条测试独立的干净环境：新控制器、新时钟，从 0 ms 起。
func _new_harness() -> ControlsHarness:
	var harness: ControlsHarness = HarnessScript.new(3)
	return harness


## 模拟「按住胸签并拖动」。每步给一次累计位移，等价于玩家的连续拖曳。
func _drag_by(harness: ControlsHarness, delta: Vector2, steps: int = 1) -> void:
	for _i in steps:
		harness.input_reader.controller.drag_to(delta)
		_step(harness, 1)


## 无头测试的步进：保留 _press() 注入的输入，不读真实键盘。
func _step(harness: ControlsHarness, steps: int = 1) -> void:
	harness.step_scripted(steps)


## 与 PuppetController.begin_drag 使用同一命中位置公式
func _chest_tag_px(state: PuppetState) -> Vector2:
	return Vector2(state.stage_pos.x * STAGE_W,
		state.stage_pos.y * STAGE_H - PuppetControllerScript.CHEST_TAG_RADIUS_PX * 0.5)


func _press(harness: ControlsHarness, input_map: Dictionary) -> void:
	harness.controller.set_input_map(input_map)


func _release_all(harness: ControlsHarness) -> void:
	harness.controller.set_input_map({})


func run_all() -> Dictionary:
	var t: ATestBase = ATestBaseScript.new()
	_test_01_initial_state(t)
	_test_02_drag_horizontal(t)
	_test_03_drag_horizontal_bounds(t)
	_test_04_drag_vertical_stance_bounds(t)
	_test_05_turn_is_gradual(t)
	_test_06_hands_independent(t)
	_test_07_hold_continuous_release_keeps(t)
	_test_08_opposite_commands_hold_pose(t)
	_test_09_all_continuous_values_bounded(t)
	_test_10_event_contract(t)
	_test_11_state_changes_before_events(t)
	_test_12_release_keeps_pending_drag(t)
	_test_13_paused_input_is_ignored(t)
	_test_14_hook_and_take_back(t)
	_test_15_head_swap(t)
	_test_16_hook_hint_speaks_from_availability(t)
	return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed,
		"failures": t.failures}


## 六个头（三个影人 + 头架三个槽位）排好序，用来断言「各出现恰好一次」。
func _all_heads(controller: PuppetController) -> Array:
	var heads: Array = []
	for puppet in controller.puppets:
		heads.append(puppet.head_id)
	for slot in controller.rack_heads.size():
		heads.append(controller.head_on_rack(slot))
	heads.sort()
	return heads


func _test_15_head_swap(t: ATestBase) -> void:
	t.begin("15 换头是交换而非复制，六个头仍各出现恰好一次")
	var harness: ControlsHarness = _new_harness()
	var controller: PuppetController = harness.controller
	t.check(controller.has_method("swap_head"), "控制器应支持换头")
	if not controller.has_method("swap_head"):
		t.finish("换头接口尚未实现")
		return
	t.check_eq(controller.rack_heads.size(), 3, "头架应有三个备用头槽位")
	var state: PuppetState = controller.get_controlled()
	var head_before: int = state.head_id
	var rack_before: int = controller.head_on_rack(1)
	t.check(controller.call("swap_head", 1), "按 2 应与头架第二个位置换头")
	t.check_eq(state.head_id, rack_before, "影人戴上架上的那个头")
	t.check_eq(controller.head_on_rack(1), head_before, "换下的头留在原位置")
	t.check_eq(_all_heads(controller), [0, 1, 2, 3, 4, 5],
		"六个头仍然各出现恰好一次")
	# PRD 第 4.2 节：换头只作用于当前受控影人
	t.check(controller.call("hook_current"), "先把影人挂起")
	t.check(not controller.call("swap_head", 0), "无人受控时换头不生效")
	t.check(not controller.call("swap_head", 9), "越界的头架槽位应被拒绝")
	t.finish("换头不复制头部道具，也不影响已挂起的影人")


func _test_14_hook_and_take_back(t: ATestBase) -> void:
	t.begin("14 空格挂起和取回保持影人姿势")
	var harness: ControlsHarness = _new_harness()
	var controller: PuppetController = harness.controller
	t.check(controller.has_method("hook_current"), "控制器应支持挂起")
	t.check(controller.has_method("take_back"), "控制器应支持取回")
	if not controller.has_method("hook_current") or not controller.has_method("take_back"):
		t.finish("挂起和取回接口尚未实现")
		return
	var state: PuppetState = controller.get_controlled()
	state.hand_angle = Vector2(0.48, -0.21)
	var before: Vector2 = state.hand_angle
	t.check(controller.call("hook_current"), "空格应挂起当前影人")
	t.check_eq(controller.controlled_id, -1, "挂起后无人受控")
	t.check_eq(state.hook_slot, 0, "影人占用第一个挂钩")
	t.check(controller.call("take_back", 0), "选中后空格应取回")
	t.check_eq(controller.controlled_id, 0, "取回后重新受控")
	t.check_eq(state.hook_slot, -1, "挂钩已释放")
	t.check_eq(state.hand_angle, before, "挂起前姿势保持不变")
	t.finish("挂起和取回保留姿势及唯一受控状态")


func _test_01_initial_state(t: ATestBase) -> void:
	t.begin("01 初始状态合法且满足全部不变量")
	var harness: ControlsHarness = _new_harness()
	t.check_eq(harness.controller.puppets.size(), 3, "应有 3 个影人")

	var controlled_count: int = 0
	var head_owners: Dictionary = {}
	for state in harness.controller.puppets:
		if state.is_controlled:
			controlled_count += 1
		t.check_in_range(state.stage_pos.x, 0.0, 1.0, "影人 %d 的 stage_pos.x" % state.puppet_id)
		t.check_in_range(state.stage_pos.y, 0.0, 1.0, "影人 %d 的 stage_pos.y" % state.puppet_id)
		t.check_in_range(state.stance, 0.0, 1.0, "影人 %d 的 stance" % state.puppet_id)
		t.check_in_range(state.facing, -1.0, 1.0, "影人 %d 的 facing" % state.puppet_id)
		t.check_in_range(state.hand_angle.x, -0.6, 0.6, "影人 %d 的左手角" % state.puppet_id)
		t.check_in_range(state.hand_angle.y, -0.6, 0.6, "影人 %d 的右手角" % state.puppet_id)
		t.check(state.head_id >= 0 and state.head_id <= 5,
			"影人 %d 的 head_id 应在 0-5，实际 %d" % [state.puppet_id, state.head_id])
		t.check(not head_owners.has(state.head_id),
			"head_id %d 不应被两个影人同时占用" % state.head_id)
		head_owners[state.head_id] = state.puppet_id
	t.check_eq(controlled_count, 1, "恰好一个影人受控")
	t.check_eq(harness.controller.controlled_id, 0, "0 号影人受控")
	t.finish("三个影人字段合法，恰好 0 号受控，三个头各占一位")


func _test_02_drag_horizontal(t: ATestBase) -> void:
	t.begin("02 拖动胸签产生横向移动")
	var harness: ControlsHarness = _new_harness()
	var state: PuppetState = harness.controller.get_controlled()
	var x0: float = state.stage_pos.x
	var started: bool = harness.controller.begin_drag(
		harness.controller.controlled_id, _chest_tag_px(state))
	t.check(started, "在胸签位置按下左键应进入拖动")
	var events_begin: Array[Dictionary] = harness.controller.take_events()
	t.check(_has_kind(events_begin, "drag_begin"), "拖动开始应发出 drag_begin 事件")
	_drag_by(harness, Vector2(240.0, 0.0), 3)
	t.check(state.stage_pos.x > x0, "向右拖动后 stage_pos.x 应增大（%.4f → %.4f）"
		% [x0, state.stage_pos.x])
	t.check_approx(state.stage_pos.x, x0 + 720.0 / STAGE_W, 1e-4,
		"累计 240px x 3 应移动 720px 的名义位置")
	t.finish("胸签拖动可连续横移，并发出 drag_begin")


func _test_03_drag_horizontal_bounds(t: ATestBase) -> void:
	t.begin("03 横向拖动到限后不再越界")
	var harness: ControlsHarness = _new_harness()
	var state: PuppetState = harness.controller.get_controlled()
	harness.input_reader.controller.begin_drag(harness.controller.controlled_id, _chest_tag_px(state))
	_drag_by(harness, Vector2(600.0, 0.0), 20)
	t.check_eq(state.stage_pos.x, 1.0, "持续向右拖应停在 stage_pos.x = 1.0")
	_drag_by(harness, Vector2(600.0, 0.0), 10)
	t.check_eq(state.stage_pos.x, 1.0, "到限后继续向右拖仍为 1.0")
	_drag_by(harness, Vector2(-600.0, 0.0), 40)
	t.check_eq(state.stage_pos.x, 0.0, "持续向左拖应停在 stage_pos.x = 0.0")
	_drag_by(harness, Vector2(-600.0, 0.0), 10)
	t.check_eq(state.stage_pos.x, 0.0, "到限后继续向左拖仍为 0.0")
	t.finish("横向有明确上下限，到限后不产生额外动作")


func _test_04_drag_vertical_stance_bounds(t: ATestBase) -> void:
	t.begin("04 纵向拖动控制站蹲并在两端截断")
	var harness: ControlsHarness = _new_harness()
	var state: PuppetState = harness.controller.get_controlled()
	t.check_eq(state.stance, 0.0, "初始应为完全站立")
	harness.input_reader.controller.begin_drag(harness.controller.controlled_id, _chest_tag_px(state))

	_drag_by(harness, Vector2(0.0, 60.0), 4)
	t.check_in_range(state.stance, 0.0, 1.0, "向下拖后的 stance")
	t.check(state.stance > 0.0, "向下拖应开始蹲下，实际 %.4f" % state.stance)
	t.check_approx(state.stage_pos.x, 0.5, 1e-6, "纯纵向拖动不应改变 stage_pos.x")

	_drag_by(harness, Vector2(0.0, 600.0), 30)
	t.check_eq(state.stance, 1.0, "持续向下拖应停在 stance = 1.0")
	_drag_by(harness, Vector2(0.0, 600.0), 10)
	t.check_eq(state.stance, 1.0, "到限后继续向下拖仍为 1.0")

	_drag_by(harness, Vector2(0.0, -600.0), 40)
	t.check_eq(state.stance, 0.0, "持续向上拖应停在 stance = 0.0")
	_drag_by(harness, Vector2(0.0, -600.0), 10)
	t.check_eq(state.stance, 0.0, "到限后继续向上拖仍为 0.0")
	t.finish("纵向拖动改 stance，两端截断，纯纵向不动横坐标")


func _test_05_turn_is_gradual(t: ATestBase) -> void:
	t.begin("05 转身有短过渡且不瞬间翻面")
	var harness: ControlsHarness = _new_harness()
	var state: PuppetState = harness.controller.get_controlled()
	t.check_eq(state.facing, 0.0, "初始朝向应为正面")
	harness.input_reader.controller.begin_drag(harness.controller.controlled_id, _chest_tag_px(state))

	_drag_by(harness, Vector2(-40.0, 0.0), 1)
	t.check(state.facing > -1.0, "第一帧不应瞬间到达 -1.0，实际 %.4f" % state.facing)
	t.check(state.facing < 0.0, "向左移动应开始向左转身，实际 %.4f" % state.facing)
	t.check_approx(state.turn_progress, absf(state.facing), 1e-6, "turn_progress 应等于 |facing|")

	var previous: float = state.facing
	var monotonic: bool = true
	var saw_intermediate: bool = false
	for _i in 20:
		_drag_by(harness, Vector2(-40.0, 0.0), 1)
		if state.facing > previous + 1e-9:
			monotonic = false
		if state.facing < -0.05 and state.facing > -0.95:
			saw_intermediate = true
		previous = state.facing
	t.check(monotonic, "朝向应单调逼近目标，不来回抖动")
	t.check(saw_intermediate, "过渡期间应取到 -1 < facing < 0 的中间值（渐进转身）")
	t.check_approx(state.facing, -1.0, 1e-6, "约 0.25 s 后应转到 -1.0")

	_drag_by(harness, Vector2(40.0, 0.0), 1)
	t.check(state.facing < 0.0, "反向移动的第一帧仍应保留向左的过渡过程")
	_drag_by(harness, Vector2(40.0, 0.0), 30)
	t.check_approx(state.facing, 1.0, 1e-6, "向右移动后应转到 +1.0")
	t.finish("转身按 0.25 s 过渡推进，中间值可见，方向随移动方向")


func _test_06_hands_independent(t: ATestBase) -> void:
	t.begin("06 双手键位可独立与双手同时控制")
	var harness: ControlsHarness = _new_harness()
	var state: PuppetState = harness.controller.get_controlled()
	var left0: float = state.hand_angle.x
	var right0: float = state.hand_angle.y

	_press(harness, {"left_raise": true})
	_step(harness, 4)
	t.check(state.hand_angle.x > left0, "按住 A 左手应抬起（%.4f → %.4f）"
		% [left0, state.hand_angle.x])
	t.check_approx(state.hand_angle.y, right0, 1e-9, "按住 A 不应影响右手")
	var left_after_a: float = state.hand_angle.x
	_release_all(harness)
	_step(harness, 1)

	_press(harness, {"right_raise": true})
	_step(harness, 4)
	t.check(state.hand_angle.y > right0, "按住 D 右手应抬起（%.4f → %.4f）"
		% [right0, state.hand_angle.y])
	t.check_approx(state.hand_angle.x, left_after_a, 1e-9, "按住 D 不应影响左手")
	_release_all(harness)
	_step(harness, 1)

	var left_before_w: float = state.hand_angle.x
	var right_before_w: float = state.hand_angle.y
	_press(harness, {"both_raise": true})
	_step(harness, 4)
	t.check(state.hand_angle.x > left_before_w, "按住 W 左手应同时抬起")
	t.check(state.hand_angle.y > right_before_w, "按住 W 右手应同时抬起")
	_release_all(harness)
	_step(harness, 1)

	var left_before_s: float = state.hand_angle.x
	var right_before_s: float = state.hand_angle.y
	_press(harness, {"both_lower": true})
	_step(harness, 4)
	t.check(state.hand_angle.x < left_before_s, "按住 S 左手应同时落下")
	t.check(state.hand_angle.y < right_before_s, "按住 S 右手应同时落下")
	t.finish("A/D 分别独立控制单手，W/S 双手同动")


func _test_07_hold_continuous_release_keeps(t: ATestBase) -> void:
	t.begin("07 按住连续变化，松开保持姿势")
	var harness: ControlsHarness = _new_harness()
	var state: PuppetState = harness.controller.get_controlled()
	_press(harness, {"left_raise": true})
	var samples: Array[float] = []
	for _i in 6:
		_step(harness, 1)
		samples.append(state.hand_angle.x)
	var increasing: bool = true
	for i in range(1, samples.size()):
		if samples[i] <= samples[i - 1]:
			increasing = false
	t.check(increasing, "按住 A 期间左手角应逐帧增大：%s" % str(samples))

	var held: float = state.hand_angle.x
	_release_all(harness)
	_step(harness, 12)
	t.check_approx(state.hand_angle.x, held, 1e-9, "松开 A 后左手角应保持不变")
	t.finish("按住期间连续增大，松开后停在新姿势")


func _test_08_opposite_commands_hold_pose(t: ATestBase) -> void:
	t.begin("08 同一只手收到相反指令时保持原姿势")
	var harness: ControlsHarness = _new_harness()
	var state: PuppetState = harness.controller.get_controlled()
	_press(harness, {"left_raise": true})
	_step(harness, 5)
	harness.controller.take_events()
	var locked_left: float = state.hand_angle.x
	var locked_right: float = state.hand_angle.y

	_press(harness, {"left_raise": true, "left_lower": true})
	_step(harness, 30)
	t.check_approx(state.hand_angle.x, locked_left, 1e-9, "A+Shift+A 同按时左手角应冻结")
	t.check_approx(state.hand_angle.y, locked_right, 1e-9, "A+Shift+A 同按不应影响右手")
	var events_conflict: Array[Dictionary] = harness.controller.take_events()
	t.check(_has_hand_dir(events_conflict, "left", 0), "冲突时应发出 left dir=0 的事件")

	_press(harness, {"both_raise": true, "both_lower": true})
	_step(harness, 30)
	t.check_approx(state.hand_angle.x, locked_left, 1e-9, "W+S 同按时左手角应冻结")
	t.check_approx(state.hand_angle.y, locked_right, 1e-9, "W+S 同按时右手角应冻结")

	_press(harness, {"left_raise": true, "both_lower": true})
	_step(harness, 30)
	t.check_approx(state.hand_angle.x, locked_left, 1e-9, "A+S 净零时左手角应冻结")
	t.check(state.hand_angle.y < locked_right,
		"A+S 时右手只收到落手指令，应继续落下（%.4f → %.4f）"
		% [locked_right, state.hand_angle.y])
	var right_after_conflict: float = state.hand_angle.y

	_release_all(harness)
	_press(harness, {"left_raise": true})
	_step(harness, 3)
	t.check(state.hand_angle.x > locked_left, "冲突解除后左手应恢复动作")
	t.check_approx(state.hand_angle.y, right_after_conflict, 1e-9, "松开后右手应保持")
	t.finish("相反指令互相抵消，姿势冻结，冲突解除后恢复")


func _test_09_all_continuous_values_bounded(t: ATestBase) -> void:
	t.begin("09 所有连续量在极端输入下都不越界")
	var harness: ControlsHarness = _new_harness()
	var state: PuppetState = harness.controller.get_controlled()
	harness.input_reader.controller.begin_drag(harness.controller.controlled_id, _chest_tag_px(state))
	_press(harness, {"left_raise": true, "right_raise": true, "both_raise": true})
	var bounded: bool = true
	var worst: String = ""
	for i in 200:
		harness.input_reader.controller.drag_to(Vector2(120.0, 90.0))
		_step(harness, 1)
		if not (is_finite(state.stage_pos.x) and is_finite(state.stage_pos.y)
				and is_finite(state.stance) and is_finite(state.facing)
				and is_finite(state.hand_angle.x) and is_finite(state.hand_angle.y)):
			bounded = false
			worst = "第 %d 帧出现非有限值" % i
			break
		if state.stage_pos.x < 0.0 or state.stage_pos.x > 1.0:
			bounded = false
			worst = "第 %d 帧 stage_pos.x=%.6f" % [i, state.stage_pos.x]
			break
		if state.stance < 0.0 or state.stance > 1.0:
			bounded = false
			worst = "第 %d 帧 stance=%.6f" % [i, state.stance]
			break
		if state.facing < -1.0 or state.facing > 1.0:
			bounded = false
			worst = "第 %d 帧 facing=%.6f" % [i, state.facing]
			break
		if absf(state.hand_angle.x) > 0.6 + 1e-6 or absf(state.hand_angle.y) > 0.6 + 1e-6:
			bounded = false
			worst = "第 %d 帧 hand_angle=(%.6f, %.6f)" % [i, state.hand_angle.x, state.hand_angle.y]
			break
	t.check(bounded, "200 帧极端输入后连续量仍全部在界内：%s" % worst)
	t.check_approx(state.stage_pos.x, 1.0, 1e-6, "横向应停在右边界")
	t.check_approx(state.stance, 1.0, 1e-6, "站蹲应停在下边界（完全蹲下）")
	t.check_approx(state.hand_angle.x, 0.6, 1e-6, "左手角应停在上限 +0.6")
	t.check_approx(state.hand_angle.y, 0.6, 1e-6, "右手角应停在上限 +0.6")
	t.finish("极端输入 200 帧后无越界、无非有限值")


func _test_10_event_contract(t: ATestBase) -> void:
	t.begin("10 TimedEvent 契约与 take_events 语义")
	var harness: ControlsHarness = _new_harness()
	var state: PuppetState = harness.controller.get_controlled()
	_step(harness, 3)
	var t_before: int = harness.clock.get_song_time_ms()
	harness.input_reader.controller.begin_drag(harness.controller.controlled_id, _chest_tag_px(state))
	_drag_by(harness, Vector2(200.0, 80.0), 3)
	_press(harness, {"left_raise": true})
	_step(harness, 3)
	harness.input_reader.controller.end_drag()

	var events: Array[Dictionary] = harness.controller.take_events()
	t.check(events.size() > 0, "上述操作应产生事件")
	var kinds: Array[String] = []
	var previous_time: int = -1
	var monotonic: bool = true
	var shape_ok: bool = true
	for e in events:
		if not (e.has("time_ms") and e.has("kind") and e.has("object_id")
				and e.has("cue_id") and e.has("payload")):
			shape_ok = false
			continue
		if typeof(e["time_ms"]) != TYPE_INT or typeof(e["object_id"]) != TYPE_INT:
			shape_ok = false
		if typeof(e["kind"]) != TYPE_STRING or typeof(e["cue_id"]) != TYPE_STRING:
			shape_ok = false
		if typeof(e["payload"]) != TYPE_DICTIONARY:
			shape_ok = false
		if e["time_ms"] < previous_time:
			monotonic = false
		previous_time = e["time_ms"]
		kinds.append(e["kind"])
	t.check(shape_ok, "每个事件都应含 time_ms(int)/kind(String)/object_id(int)/cue_id(String)/payload(Dictionary)")
	t.check(monotonic, "time_ms 应按歌曲时间单调不减")
	t.check(previous_time >= t_before, "事件时间应不早于操作前的时钟")
	t.check(kinds.has("drag_begin"), "应含 drag_begin")
	t.check(kinds.has("drag_end"), "应含 drag_end")
	t.check(kinds.has("pose_stance"), "应含 pose_stance")
	t.check(kinds.has("facing_turn"), "应含 facing_turn")
	t.check(kinds.has("hand_motion"), "应含 hand_motion")

	var again: Array[Dictionary] = harness.controller.take_events()
	t.check_eq(again.size(), 0, "take_events 取走后队列应清空")
	t.finish("事件五个字段齐备、时间单调、类型正确、取走即清空")


func _test_11_state_changes_before_events(t: ATestBase) -> void:
	t.begin("11 状态先变化，再供表现和录制读取")
	var harness: ControlsHarness = _new_harness()
	var state: PuppetState = harness.controller.get_controlled()
	harness.input_reader.controller.begin_drag(harness.controller.controlled_id, _chest_tag_px(state))
	_step(harness, 2)
	harness.controller.take_events()

	# 一次拖动只调用一次 tick，然后立刻按「模拟接收端」的方式读状态与事件
	var x_before: float = state.stage_pos.x
	harness.input_reader.controller.drag_to(Vector2(300.0, 100.0))
	_step(harness, 1)
	var x_after: float = state.stage_pos.x
	var events: Array[Dictionary] = harness.controller.take_events()
	t.check(x_after > x_before, "同一帧内状态应先更新（%.4f → %.4f）" % [x_before, x_after])

	var stance_event_value: float = NAN
	for e in events:
		if e["kind"] == "pose_stance":
			stance_event_value = float(e["payload"]["stance"])
	t.check(not is_nan(stance_event_value), "同一帧应能读到 pose_stance 事件")
	t.check_approx(stance_event_value, state.stance, 1e-9,
		"事件载荷应等于同帧状态值，而不是上一帧的旧值")

	var hand_snapshot: float = state.hand_angle.x
	_press(harness, {"left_raise": true})
	_step(harness, 1)
	var motion_angle: float = NAN
	for e in harness.controller.take_events():
		if e["kind"] == "hand_motion" and e["payload"]["hand"] == "left":
			motion_angle = float(e["payload"]["angle"])
	t.check(state.hand_angle.x > hand_snapshot, "按住 A 后状态应先于事件更新")
	if not is_nan(motion_angle):
		t.check_approx(motion_angle, state.hand_angle.x, 1e-9,
			"hand_motion 载荷应等于同帧的 hand_angle")
	t.finish("同帧内 PuppetState 已是新值，事件载荷与之一致")


func _test_12_release_keeps_pending_drag(t: ATestBase) -> void:
	t.begin("12 鼠标移动后同帧松开仍结算拖动")
	var harness: ControlsHarness = _new_harness()
	var state: PuppetState = harness.controller.get_controlled()
	var x_before: float = state.stage_pos.x
	var stance_before: float = state.stance
	t.check(harness.controller.begin_drag(0, _chest_tag_px(state)), "应命中胸签")
	harness.controller.drag_to(Vector2(192.0, 108.0))
	harness.controller.end_drag()
	t.check_approx(state.stage_pos.x, x_before + 0.1, 1e-6,
		"松开前积累的横向位移不能丢失")
	t.check_approx(state.stance, stance_before + 0.1, 1e-6,
		"松开前积累的站蹲位移不能丢失")
	t.check(not harness.controller.is_dragging(), "松开后应退出拖动")
	t.check(_has_kind(harness.controller.take_events(), "drag_end"), "应记录拖动结束")
	t.finish("同一帧内的最后一次移动在松开时结算")


func _test_13_paused_input_is_ignored(t: ATestBase) -> void:
	t.begin("13 暂停期间的拖动不产生动作或事件")
	var harness: ControlsHarness = _new_harness()
	var state: PuppetState = harness.controller.get_controlled()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = _chest_tag_px(state)
	t.check(harness.input_reader.handle_event(down), "暂停前应能开始拖动")
	harness.controller.take_events()
	harness.set_paused(true)
	t.check(not harness.input_reader.is_drag_active(), "暂停时应结束当前拖动")
	harness.controller.take_events()
	var x_before: float = state.stage_pos.x
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(384.0, 108.0)
	t.check(not harness.input_reader.handle_event(motion), "暂停时应忽略鼠标移动")
	t.check(not harness.input_reader.handle_event(down), "暂停时应忽略重新按下")
	harness.advance(1.0 / 60.0)
	t.check_approx(state.stage_pos.x, x_before, 1e-9, "暂停中位置应不变")
	t.check_eq(harness.controller.take_events().size(), 0, "暂停中不应新增操控事件")
	harness.set_paused(false)
	t.check(harness.input_reader.handle_event(down), "恢复后应能重新拖动")
	harness.input_reader.handle_event(motion)
	harness.advance(1.0 / 60.0)
	t.check(state.stage_pos.x > x_before, "恢复后新输入应正常生效")
	t.finish("暂停输入被丢弃，恢复后只处理新输入")


## 16 空格提示必须与「真的能不能挂起」一致。
##
## 背景：第一关开局三个影人同时在场，其中两个分别挂在两个挂钩上（PRD 第 4.2 节），
## 于是两个挂钩槽从第一帧起就是满的，`hook_current()` 永远找不到空位。原来的 HUD
## 只按「有没有人受控」判断，仍然写着「空格 = 挂起这个影人」——说了做不到，玩家按下去
## 什么都不会发生，只会以为按键坏了。这里把「按可用性说话」这条规则钉住。
func _test_16_hook_hint_speaks_from_availability(t: ATestBase) -> void:
	t.begin("16 空格提示按挂钩的实际可用性说话")
	var harness: ControlsHarness = _new_harness()
	var controller: PuppetController = harness.controller
	t.check(controller.has_method("find_free_hook_slot"), "控制器应能报告空闲挂钩槽位")
	if not controller.has_method("find_free_hook_slot"):
		t.finish("空闲槽位查询尚未实现")
		return

	# 空场：有槽可用，提示可以挂起
	t.check_eq(controller.find_free_hook_slot(), 0, "空场时第一个挂钩可用")
	t.check_eq(Level1ASceneScript.hook_hint_text(controller, -1), "空格 = 挂起这个影人",
		"有空槽时才提示可以挂起")

	# 挂起 0 号之后：受控为空，提示取回
	t.check(controller.call("hook_current"), "挂起受控影人")
	t.check_eq(Level1ASceneScript.hook_hint_text(controller, 0), "空格 = 取回 1 号影人",
		"选中挂起的影人时提示取回")
	t.check_eq(Level1ASceneScript.hook_hint_text(controller, -1),
		"点手边的签选中挂起的影人，再按空格取回", "没选中时提示先选中")
	t.check(controller.call("take_back", 0), "取回影人")

	# 第一关开局布景：0 号受控，另两个影人占满两个挂钩 —— 此时挂起不可能成功
	controller.puppets[1].hook_slot = 0
	controller.puppets[2].hook_slot = 1
	t.check_eq(controller.find_free_hook_slot(), -1, "两个挂钩都被占满时没有空槽")
	t.check(not controller.call("hook_current"), "没有空槽时按空格挂不起影人")
	t.check_eq(Level1ASceneScript.hook_hint_text(controller, -1), "",
		"挂不起来时不再显示「空格 = 挂起」，不承诺做不到的操作")
	t.finish("提示与挂钩可用性一致")


func _has_kind(events: Array[Dictionary], kind: String) -> bool:
	for e in events:
		if e["kind"] == kind:
			return true
	return false


func _has_hand_dir(events: Array[Dictionary], hand: String, dir: int) -> bool:
	for e in events:
		if e["kind"] == "hand_motion" and e["payload"]["hand"] == hand \
				and int(e["payload"]["dir"]) == dir:
			return true
	return false
