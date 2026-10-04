extends RefCounted
class_name TestUmbrella
## 第一关「借伞还伞」流程的行为测试（用户 2026-10-04 定案的第一关流程表）。
##
## 流程逐条对应：
##   开场 → 伞在许仙右手；接伞 → 白素贞走到身旁且左手与许仙右手等高；
##   向左走 → 伞跟白素贞的手；到达最左边 → 记下「已到过左端」；
##   向右返回 → 反向拖回；还伞 → 已经到过左端且回到实际接伞位置才自动交回。

const ATestBaseScript := preload("res://tests/a/a_test_base.gd")
const StageDefScript := preload("res://scripts/a/stage_def.gd")
const PuppetStateScript := preload("res://scripts/a/puppet_state.gd")
const UmbrellaControllerScript := preload("res://scripts/a/umbrella_controller.gd")
const LampStateScript := preload("res://scripts/a/lamp_state.gd")
## 伞的落点由显示端算（A 不给绝对坐标），所以这里要连显示端的影人一起验证。
const PlaceholderPuppetScript := preload("res://scripts/a_test/placeholder_puppet.gd")

## 许仙站位与举伞角：与 StageDef.make_level1 的开演布景一致
## （他举满 π，因此白素贞抬到「抬手」到位区间上段时两手恰好齐平）。
const XUXIAN_X: float = 0.13
const XUXIAN_RAISE: float = PI
## 白素贞接伞时的站位：0.16 落在接伞容差（0.13 ± 0.06）内。
const BORROW_X: float = 0.16
## 舞台最左侧可达区域内的位置（UmbrellaController.LEFT_EDGE_X = 0.05）。
const LEFT_EDGE_X: float = 0.02


## 三个影人的初始状态：0 = 白素贞（玩家控制），1 = 许仙（固定站位举伞），2 = 小青。
func _puppets() -> Array:
	var puppets: Array = []
	for i in 3:
		var state: PuppetState = PuppetStateScript.new(i)
		state.stage_pos = Vector2(0.5, 0.5)
		state.hand_angle = Vector2.ZERO
		puppets.append(state)
	puppets[UmbrellaControllerScript.XUXIAN_ID].stage_pos = Vector2(XUXIAN_X, 0.5)
	puppets[UmbrellaControllerScript.XUXIAN_ID].hand_angle.y = XUXIAN_RAISE
	return puppets


## 建立控制器。默认把白素贞摆在「已对齐许仙、左手已抬到与他右手等高」的位置，
## 也就是流程表里「接伞」成立的瞬间；各条测试再自行挪动它。
func _controller(stage_id: int = 1, puppets: Array = []) -> UmbrellaController:
	var controller: UmbrellaController = UmbrellaControllerScript.new()
	controller.setup(StageDefScript.make_stage(stage_id), puppets)
	return controller


## 对齐的白素贞：站位在接伞容差内、左手角度与许仙右手相同（因此两手等高）。
func _aligned_puppets() -> Array:
	var puppets: Array = _puppets()
	puppets[UmbrellaControllerScript.BAISUZHEN_ID].stage_pos = Vector2(BORROW_X, 0.5)
	puppets[UmbrellaControllerScript.BAISUZHEN_ID].hand_angle.x = XUXIAN_RAISE
	return puppets


func run_all() -> Dictionary:
	var t: ATestBase = ATestBaseScript.new()
	_test_only_level1(t)
	_test_starts_in_xuxian_hand(t)
	_test_drawn_at_holder_wrist(t)
	_test_take_requires_alignment(t)
	_test_misaligned_take_does_not_transfer(t)
	_test_umbrella_follows_lowered_hand(t)
	_test_return_requires_left_edge_then_borrow_position(t)
	_test_return_requires_returning_direction(t)
	_test_low_hand_needs_handoff_transition(t)
	_test_single_transfer_event_per_round(t)
	return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed,
		"failures": t.failures}


## 事件构造：只发控制器事件，不带判定结果（判定由 PerformanceSystem 负责）。
func _event(kind: String, cue_id: String = "") -> Dictionary:
	return {"time_ms": 8750, "kind": kind, "cue_id": cue_id,
		"object_id": 0, "payload": {"kind": kind}}


func _has_event(controller: UmbrellaController, kind: String) -> bool:
	for event in controller.take_events():
		if str(event.get("kind", "")) == kind:
			return true
	return false


func _test_only_level1(t: ATestBase) -> void:
	t.begin("伞流程只在第一关启用")
	var l1: UmbrellaController = _controller(1, _puppets())
	var l2: UmbrellaController = _controller(2, _puppets())
	var unknown: UmbrellaController = _controller(99, _puppets())
	t.check(l1.is_enabled(), "第一关应启用伞流程")
	t.check(not l2.is_enabled(), "第二关不应启用伞流程")
	t.check(not unknown.is_enabled(), "未知关卡不应启用伞流程")
	t.check_eq(l2.holder_id_of(), -1, "未启用时不应有持伞人")
	t.finish("第一关启用，其它关关闭")


func _test_starts_in_xuxian_hand(t: ATestBase) -> void:
	t.begin("开场：许仙右手举起持伞")
	var puppets: Array = _puppets()
	var controller: UmbrellaController = _controller(1, puppets)
	t.check_eq(controller.holder_id_of(), UmbrellaControllerScript.XUXIAN_ID,
		"开场伞应在许仙手里")
	t.check_eq(controller.holder_hand_of(), UmbrellaControllerScript.XUXIAN_HAND,
		"开场持伞的手应是右手")
	t.check_approx(controller.position.x, XUXIAN_X, 0.0001, "伞应画在许仙站位的横坐标上")
	t.check_approx(controller.position.y,
		UmbrellaController.hand_height(XUXIAN_RAISE, 0.0), 0.0001,
		"伞应画在许仙右手的高度上")
	t.finish("伞随开演布景挂在许仙右手")


## 伞画在「持伞那只手」上——落点由显示端按**它自己画出的手腕**算，A 不给绝对坐标
## （A→B 交接文档 6.2 节）。
##
## 这条断言防的是 2026-10-04 实测的那个错：显示端曾按 A 的手高公式（归一化「幕布」坐标）
## 换算像素，许仙举伞那一帧伞被画在幕布底部 y≈668，而他自己画出的右手在 267 高处。
## 这里独立复算一遍**显示端**的几何链（不调用显示端的求解函数），再额外钉一条性质：
## 落点必须随灯距（影子尺寸）一起变化——旧写法读不到灯距，这条会失败。
func _test_drawn_at_holder_wrist(t: ATestBase) -> void:
	t.begin("伞落在持伞那只手画出的手腕上")
	var view: PlaceholderPuppet = PlaceholderPuppetScript.new()
	view.stage_origin = Vector2.ZERO
	view.stage_size = Vector2(1920.0, 1080.0)
	view.lamp_state = LampStateScript.new()   # 灯距取默认 0.5
	var xuxian: PuppetState = _puppets()[UmbrellaControllerScript.XUXIAN_ID]
	view.puppet_state = xuxian
	var at: Vector2 = view.hand_screen_position(UmbrellaControllerScript.XUXIAN_HAND)

	# 独立复算：身高 = 站高 × 灯距倍率；肩在接地点上方 SHOULDER_RATIO 个身高、再横移半个身宽；
	# 手臂从肩起往手角方向走 (上臂 + 下臂) 个身高（右手屏幕角 = π/2 − 手角）。
	var scale: float = lerpf(PlaceholderPuppetScript.SHADOW_SCALE_MIN,
		PlaceholderPuppetScript.SHADOW_SCALE_MAX, view.lamp_state.distance)
	var height: float = view.figure_height * scale
	var half_w: float = height * PlaceholderPuppetScript.HALF_W_RATIO
	var shoulder := Vector2(xuxian.stage_pos.x * 1920.0 + half_w,
		xuxian.stage_pos.y * 1080.0 - height * PlaceholderPuppetScript.SHOULDER_RATIO)
	var arm: float = height * (PlaceholderPuppetScript.UPPER_ARM_RATIO
		+ PlaceholderPuppetScript.LOWER_ARM_RATIO)
	var screen_angle: float = PI * 0.5 - xuxian.hand_angle.y
	var expected: Vector2 = shoulder + Vector2(cos(screen_angle), sin(screen_angle)) * arm
	t.check(at.distance_to(expected) < 1.0,
		"伞应落在许仙右手腕上（实际 %s，期望 %s）" % [str(at), str(expected)])

	# 另一条独立的性质：落点跟着影子的尺寸走。灯推近 → 影子放大 → 手（和手上的伞）一起抬高；
	# 旧写法（按 A 的归一化手高换算像素）根本读不到灯距，这条它会失败。
	view.lamp_state.distance = 0.0
	var far_lamp: Vector2 = view.hand_screen_position(UmbrellaControllerScript.XUXIAN_HAND)
	view.lamp_state.distance = 1.0
	var near_lamp: Vector2 = view.hand_screen_position(UmbrellaControllerScript.XUXIAN_HAND)
	t.check(near_lamp.y < far_lamp.y - 20.0,
		"灯推近时伞应随影子一起抬高（实际 %.1f → %.1f）" % [far_lamp.y, near_lamp.y])
	view.free()
	t.finish("伞的落点来自影人自己画出的手腕")


func _test_take_requires_alignment(t: ATestBase) -> void:
	t.begin("白素贞对齐许仙右手后自动接伞")
	var controller: UmbrellaController = _controller(1, _aligned_puppets())
	controller.update(8750, [])
	t.check_eq(controller.holder_id_of(), UmbrellaControllerScript.BAISUZHEN_ID,
		"接伞后伞的持有者应为白素贞")
	t.check_eq(controller.holder_hand_of(), UmbrellaControllerScript.BAISUZHEN_HAND,
		"接伞后应握在白素贞左手")
	t.check_approx(controller.borrow_position(), BORROW_X, 0.0001, "应记录接伞位置")
	t.check(_has_event(controller, UmbrellaControllerScript.KIND_TAKE),
		"应发出 umbrella_take 事件")
	t.finish("位置与手高同时满足时接伞")


func _test_misaligned_take_does_not_transfer(t: ATestBase) -> void:
	t.begin("未对齐时不应凭空接伞")
	# 位置没对齐：白素贞离许仙 0.47，远超 0.06 的容差
	var far: Array = _aligned_puppets()
	far[UmbrellaControllerScript.BAISUZHEN_ID].stage_pos = Vector2(0.60, 0.5)
	var far_controller: UmbrellaController = _controller(1, far)
	far_controller.update(8750, [])
	t.check_eq(far_controller.holder_id_of(), UmbrellaControllerScript.XUXIAN_ID,
		"位置未对齐时伞仍应在许仙手里")
	t.check(far_controller.take_events().is_empty(), "位置未对齐时不应发出交接事件")

	# 位置对齐但手高差得远：白素贞左手自然垂下
	var low: Array = _puppets()
	low[UmbrellaControllerScript.BAISUZHEN_ID].stage_pos = Vector2(BORROW_X, 0.5)
	var low_controller: UmbrellaController = _controller(1, low)
	low_controller.update(8750, [])
	t.check(not bool(low_controller.alignment()["aligned"]), "手高未对齐时不应判为对齐")
	t.check_eq(low_controller.holder_id_of(), UmbrellaControllerScript.XUXIAN_ID,
		"手没抬到同一高度时伞仍应在许仙手里")
	t.check(low_controller.take_events().is_empty(), "手未对齐时不应发出交接事件")
	t.finish("错位或手高不符都不会触发接伞")


## 递伞过渡是 0.18 秒（约 11 帧 @60fps）。测试里没有真实帧循环，
## 因此「过渡结束后」的状态要么多调几次 update，要么直接查递伞进度。
func _settle(controller: UmbrellaController, frames: int = 12) -> void:
	for _i in frames:
		controller.update(0, [])


## 流程表「向左走」：白素贞可以自行放下左手，伞跟随她的手。
func _test_umbrella_follows_lowered_hand(t: ATestBase) -> void:
	t.begin("白素贞自行放下左手时伞跟手走")
	var puppets: Array = _aligned_puppets()
	var controller: UmbrellaController = _controller(1, puppets)
	controller.update(8750, [])
	controller.take_events()
	t.check_eq(controller.holder_id_of(), UmbrellaControllerScript.BAISUZHEN_ID,
		"先接住伞，才谈得上「伞跟手走」")
	_settle(controller)
	var state: PuppetState = puppets[UmbrellaControllerScript.BAISUZHEN_ID]
	# 放手之前先走一段，确认伞跟的是位置
	state.stage_pos.x = 0.10
	controller.update(9000, [])
	t.check_approx(controller.position.x, 0.10, 0.0001, "伞应跟到白素贞的新位置")
	# 再放下左手：伞应随手下落
	var raised_y: float = controller.position.y
	state.hand_angle.x = 0.0
	controller.update(9100, [])
	_settle(controller)
	t.check(controller.position.y < raised_y - 0.05,
		"放下左手后伞应随手下落（%.4f → %.4f）" % [raised_y, controller.position.y])
	t.check_approx(controller.position.y,
		UmbrellaController.hand_height(0.0, 0.0), 0.0001, "伞应停在左手的新高度上")
	t.check_approx(controller.position.x, 0.10, 0.0001, "放下手不改变横向位置")
	t.finish("伞始终跟随持伞的那只手")


func _test_return_requires_left_edge_then_borrow_position(t: ATestBase) -> void:
	t.begin("先到左端再返回接伞位置才自动还伞")
	var puppets: Array = _aligned_puppets()
	var controller: UmbrellaController = _controller(1, puppets)
	controller.update(8750, [])
	controller.take_events()
	var state: PuppetState = puppets[UmbrellaControllerScript.BAISUZHEN_ID]

	# 还没到左端：此刻正好在接伞位置上，也不能还伞
	controller.update(9000, [])
	t.check(not controller.has_reached_left_edge(), "尚未左移时不应记下已到左端")
	controller.update(9500, [])
	t.check_eq(controller.holder_id_of(), UmbrellaControllerScript.BAISUZHEN_ID,
		"没到过左端时不应还伞")

	# 向左走到舞台最左侧的可达区域
	state.stage_pos.x = LEFT_EDGE_X
	controller.update(11000, [])
	t.check(controller.has_reached_left_edge(), "持伞走到最左边后应记下已到左端")

	# 回程途中、还没走到接伞位置（0.145 距接伞位置 0.16 有 0.015，超出还伞容差 0.03？
	# 不——0.015 在容差内，必须取更远的点。这里取 0.115：距 0.16 有 0.045 > 0.03，
	# 同时也 > LEFT_EDGE_X，因此既不在左端、也没回到接伞位置）
	state.stage_pos.x = 0.115
	controller.update(12000, [])
	t.check_eq(controller.holder_id_of(), UmbrellaControllerScript.BAISUZHEN_ID,
		"尚未回到接伞位置时不能还伞")

	# 从左侧回到实际接伞位置 → 自动还伞。
	# 位置走真实回程：她从左端一路向右（0.115 → 0.14 → 0.16），
	# 中途每一帧的 x 都比上一帧大，所以「往左走在接伞位置左侧」不会误清标记。
	for x in [0.14, BORROW_X]:
		state.stage_pos.x = x
		controller.update(13000 + int(x * 1000.0), [])
	t.check_eq(controller.holder_id_of(), UmbrellaControllerScript.XUXIAN_ID,
		"返回接伞位置后应自动还给许仙")
	t.check_eq(controller.holder_hand_of(), UmbrellaControllerScript.XUXIAN_HAND,
		"还伞后应回到许仙右手")
	t.check(_has_event(controller, UmbrellaControllerScript.KIND_RETURN),
		"应发出 umbrella_return 事件")
	t.finish("返回路径必须经过左端并回到接伞位置")


## 流程表「向右返回」：反向拖动才算返回；站着不动或还在向左走都不算。
func _test_return_requires_returning_direction(t: ATestBase) -> void:
	t.begin("只有反向拖回时才还伞")
	var puppets: Array = _aligned_puppets()
	var controller: UmbrellaController = _controller(1, puppets)
	controller.update(8750, [])
	controller.take_events()
	var state: PuppetState = puppets[UmbrellaControllerScript.BAISUZHEN_ID]
	state.stage_pos.x = LEFT_EDGE_X
	controller.update(11000, [])

	# 从左侧一路向左经过接伞区内的一点：方向不对（仍在向左），不得还伞
	state.stage_pos.x = 0.12
	controller.update(11500, [])
	t.check_eq(controller.holder_id_of(), UmbrellaControllerScript.BAISUZHEN_ID,
		"仍在向左移动时经过接伞区不应还伞")

	# 向右返回接伞位置：这一次方向正确
	state.stage_pos.x = BORROW_X
	controller.update(11600, [])
	t.check_eq(controller.holder_id_of(), UmbrellaControllerScript.XUXIAN_ID,
		"向右返回接伞位置后应还伞")
	t.finish("还伞要求方向为向右返回")


## 流程表「还伞」：不要求白素贞重新抬手；手位较低时用短暂递伞过渡衔接。
func _test_low_hand_needs_handoff_transition(t: ATestBase) -> void:
	t.begin("手位较低时用短暂递伞过渡衔接，不瞬间跳过去")
	var puppets: Array = _aligned_puppets()
	var controller: UmbrellaController = _controller(1, puppets)
	controller.update(8750, [])
	controller.take_events()
	var state: PuppetState = puppets[UmbrellaControllerScript.BAISUZHEN_ID]
	state.stage_pos.x = LEFT_EDGE_X
	controller.update(11000, [])
	# 放下左手后持伞走回来：还伞时她的手明显低于许仙举起的右手
	state.hand_angle.x = 0.0
	state.stage_pos.x = BORROW_X
	controller.update(13000, [])
	t.check_eq(controller.holder_id_of(), UmbrellaControllerScript.XUXIAN_ID,
		"手放低了也应还伞（不要求重新抬手）")
	t.check(controller.handing_off, "手位不同时应进入递伞过渡")
	var from_low_y: float = UmbrellaController.hand_height(0.0, 0.0)
	var to_high_y: float = UmbrellaController.hand_height(XUXIAN_RAISE, 0.0)
	t.check(controller.position.y > from_low_y - 0.0001
		and controller.position.y < to_high_y + 0.0001,
		"过渡中的伞应在两只手之间（%.4f，手高 %.4f→%.4f）"
			% [controller.position.y, from_low_y, to_high_y])
	# 过渡走完后伞稳稳落在许仙右手上
	_settle(controller, 30)
	t.check(not controller.handing_off, "过渡应在有限时间内结束")
	t.check_approx(controller.position.y, to_high_y, 0.0001, "过渡结束后伞落在许仙右手高度")
	t.finish("低手位还伞有过渡，且最终停在许仙手里")


## 同一轮交接只报一次：站在对齐位置上不动，不应每帧都产出一次接伞。
func _test_single_transfer_event_per_round(t: ATestBase) -> void:
	t.begin("同一次交接只上报一次，走完一轮后可再接一次")
	var controller: UmbrellaController = _controller(1, _aligned_puppets())
	controller.update(8750, [])
	var first: Array = controller.take_events()
	t.check_eq(first.size(), 1, "接伞只应上报一次（实际 %d 条）" % first.size())
	for _i in 10:
		controller.update(8800, [])
	t.check(controller.take_events().is_empty(), "持续对齐不应反复上报接伞")
	# 走到左端再返回：这一轮应当且只应当再报一次还伞
	var puppets: Array = controller.puppets
	puppets[UmbrellaControllerScript.BAISUZHEN_ID].stage_pos.x = LEFT_EDGE_X
	controller.update(11000, [])
	puppets[UmbrellaControllerScript.BAISUZHEN_ID].stage_pos.x = BORROW_X
	controller.update(12000, [])
	var second: Array = controller.take_events()
	t.check_eq(second.size(), 1, "还伞只应上报一次（实际 %d 条）" % second.size())
	if second.size() == 1:
		t.check_eq(str(second[0]["kind"]), UmbrellaControllerScript.KIND_RETURN,
			"这一条应是 umbrella_return")
	for _i in 10:
		controller.update(12100, [])
	t.check(controller.take_events().is_empty(), "还伞后停在原地不应反复上报")
	t.finish("每次交接只上报一次，回合可重复")
