extends RefCounted
class_name ControlsProbe
## 图形环境下的脚本化实测探针。
##
## 为什么需要它：验证者无法向运行中的窗口注入真实鼠标/键盘事件，而
## 「脚本能解析」不能当作「操控正确」。本探针在真实窗口里用同一套
## PuppetController 输入接口（begin_drag / drag_to / end_drag / set_input_map）
## 走完整链路，并把可核对的数值打到 stdout。
##
## 它不替代人工实测：真实鼠标手感、真实按键与音频仍需人在 1080p 环境下确认。
## 运行方式见 tests/a/README.md。

const HarnessScript := preload("res://scripts/a_test/controls_harness.gd")
const PuppetStateScript := preload("res://scripts/a/puppet_state.gd")
const PuppetControllerScript := preload("res://scripts/a/puppet_controller.gd")

const STAGE_W: float = 1920.0
const STAGE_H: float = 1080.0

## 由测试场景注入：第一关数据，用于校验时长与段落。
var clock: MusicClock = null
var stage_def: StageDef = null

var _harness: ControlsHarness = null
var _failures: Array[String] = []


func _init() -> void:
	_harness = HarnessScript.new(3)


## 按顺序跑完全部实测步骤。返回失败条数（0 表示全部符合预期）。
func run() -> int:
	print("")
	print("================ 图形环境脚本化实测（a_controls_probe）================")
	print("Godot %s  渲染后端: %s" % [
		Engine.get_version_info().get("string", "?"), RenderingServer.get_video_adapter_name()])
	_check_chest_tag_hit_test()
	_reset()
	_check_drag_horizontal_and_turn()
	_reset()
	_check_drag_vertical_stance()
	_reset()
	_check_hands()
	_reset()
	_check_conflict()
	_reset()
	_check_bounds_stress()
	_check_music_clock()
	print("")
	print("实测结论：%s" % ("全部符合预期" if _failures.is_empty()
		else "%d 项不符合预期" % _failures.size()))
	for line in _failures:
		print("  不符合预期：%s" % line)
	print("=====================================================================")
	print("")
	return _failures.size()


## 每个阶段之间重置操控状态，避免上一阶段的姿势污染下一阶段。
func _reset() -> void:
	_harness.controller.setup(3)
	_harness.clock.reset()
	_harness.input_reader.release_drag()
	_harness.controller.take_events()


func _step(steps: int = 1) -> void:
	_harness.step_scripted(steps)


func _state() -> PuppetState:
	return _harness.controller.get_controlled()


func _press(input_map: Dictionary) -> void:
	_harness.controller.set_input_map(input_map)


func _chest_tag_px() -> Vector2:
	var s: PuppetState = _state()
	return Vector2(s.stage_pos.x * STAGE_W,
		s.stage_pos.y * STAGE_H - PuppetControllerScript.CHEST_TAG_RADIUS_PX * 0.5)


func _expect(condition: bool, message: String) -> void:
	var mark: String = "OK  " if condition else "BAD "
	if not condition:
		_failures.append(message)
	print("  %s %s" % [mark, message])


func _check_chest_tag_hit_test() -> void:
	print("")
	print("[1] 胸签命中判定：只有按在胸签圆圈内才开始拖动")
	var far_click: bool = _harness.controller.begin_drag(0, _chest_tag_px() + Vector2(400.0, 0.0))
	_expect(not far_click, "按在胸签之外不进入拖动，is_dragging=%s"
		% _harness.input_reader.is_drag_active())
	_reset()
	var near_click: bool = _harness.controller.begin_drag(0, _chest_tag_px())
	_expect(near_click, "按在胸签正中心进入拖动")
	_expect(_harness.controller.is_dragging(), "控制器报告拖动中")
	var events: Array[Dictionary] = _harness.controller.take_events()
	_expect(_events_have(events, "drag_begin"), "发出 drag_begin 事件（time_ms=%d）"
		% (events[0]["time_ms"] if events.size() > 0 else -1))
	_harness.controller.end_drag()


func _check_drag_horizontal_and_turn() -> void:
	print("")
	print("[2] 横向拖动 + 沿移动方向快速翻面（正/反两面二值，过渡 0.1 s）")
	_harness.controller.begin_drag(0, _chest_tag_px())
	var x0: float = _state().stage_pos.x
	# 开局是正面。第一帧向左拖：翻面已经开始，但还没换面——这正是「不能瞬间翻面」
	_expect(_state().facing == PuppetState.FACING_FRONT, "开局为正面朝外")
	_harness.controller.drag_to(Vector2(-100.0, 0.0))
	_step(1)
	_expect(_state().facing == PuppetState.FACING_FRONT,
		"翻面第一帧仍在正面（有过渡，不是瞬间翻面）")
	_expect(_state().turn_progress < 1.0,
		"翻面已开始：turn_progress = %.4f" % _state().turn_progress)

	var progress_samples: Array[String] = ["%.3f" % _state().turn_progress]
	var swap_frames: int = 1
	while _state().facing == PuppetState.FACING_FRONT and swap_frames < 20:
		_harness.controller.drag_to(Vector2(-100.0, 0.0))
		_step(1)
		swap_frames += 1
		progress_samples.append("%.3f" % _state().turn_progress)
	_expect(_state().facing == PuppetState.FACING_BACK, "向左拖动后应翻到反面")
	_expect(swap_frames <= 8, "换面应发生在 0.1 秒之内（实际第 %d 帧）" % swap_frames)

	var total_frames: int = swap_frames
	while _state().turn_progress < 1.0 and total_frames < 20:
		_harness.controller.drag_to(Vector2(-100.0, 0.0))
		_step(1)
		total_frames += 1
	_expect(is_equal_approx(_state().turn_progress, 1.0) and total_frames <= 8,
		"整个翻面 %d 帧完成（期望 ≤ 8 帧 = 0.1 s）；进度序列 %s"
			% [total_frames, ", ".join(progress_samples)])
	_expect(_state().stage_pos.x < x0, "stage_pos.x 减小：%.4f -> %.4f" % [x0, _state().stage_pos.x])

	var x_after_left: float = _state().stage_pos.x
	_harness.controller.end_drag()
	_step(20)
	_expect(is_equal_approx(_state().stage_pos.x, x_after_left),
		"松开后停在新位置：%.4f" % _state().stage_pos.x)

	# 反向：向右拖动应翻回正面，第一帧同样仍停在反面
	_harness.controller.begin_drag(0, _chest_tag_px())
	_harness.controller.drag_to(Vector2(300.0, 0.0))
	_step(1)
	_expect(_state().facing == PuppetState.FACING_BACK, "反向的第一帧仍停在反面（有过渡）")
	for _i in 10:
		_harness.controller.drag_to(Vector2(300.0, 0.0))
		_step(1)
	_expect(_state().facing == PuppetState.FACING_FRONT,
		"向右拖动后翻回正面（实际 %.1f）" % _state().facing)
	_harness.controller.end_drag()


func _check_drag_vertical_stance() -> void:
	print("")
	print("[3] 纵向站蹲：向下拖蹲下、向上拖站起，两端截断")
	_harness.controller.begin_drag(0, _chest_tag_px())
	var stance_samples: Array[String] = []
	for i in 40:
		_harness.controller.drag_to(Vector2(0.0, 90.0))
		_step(1)
		if i % 8 == 0:
			stance_samples.append("%.3f" % _state().stance)
	_expect(is_equal_approx(_state().stance, 1.0), "持续向下拖到达 stance = 1.0（采样 %s）"
		% ", ".join(stance_samples))
	for _i in 40:
		_harness.controller.drag_to(Vector2(0.0, -90.0))
		_step(1)
	_expect(is_equal_approx(_state().stance, 0.0), "持续向上拖回到 stance = 0.0（实际 %.4f）" % _state().stance)
	_harness.controller.end_drag()


func _check_hands() -> void:
	print("")
	print("[4] 双手控制：A/D 独立，W/S 双手同动，按住连续、松开保持")
	var left0: float = _state().hand_angle.x
	var right0: float = _state().hand_angle.y
	_press({"left_raise": true})
	_step(6)
	_expect(_state().hand_angle.x > left0, "按住 A：左手 %.4f -> %.4f" % [left0, _state().hand_angle.x])
	_expect(is_equal_approx(_state().hand_angle.y, right0), "按住 A 时右手不动：%.4f" % _state().hand_angle.y)
	var held: float = _state().hand_angle.x
	_press({})
	_step(30)
	_expect(is_equal_approx(_state().hand_angle.x, held), "松开 A 后保持 %.4f" % _state().hand_angle.x)

	_press({"both_raise": true})
	_step(6)
	_expect(_state().hand_angle.x > held, "按住 W：左手继续抬起 %.4f -> %.4f"
		% [held, _state().hand_angle.x])
	var before_lower: float = _state().hand_angle.x
	_press({"both_lower": true})
	_step(6)
	_expect(_state().hand_angle.x < before_lower, "按住 S：双手转为落下 %.4f -> %.4f"
		% [before_lower, _state().hand_angle.x])
	_press({})


func _check_conflict() -> void:
	print("")
	print("[5] 同一只手收到相反指令时保持原姿势")
	_press({"left_raise": true})
	_step(6)
	var locked: float = _state().hand_angle.x
	_harness.controller.take_events()
	_press({"left_raise": true, "left_lower": true})
	_step(40)
	_expect(is_equal_approx(_state().hand_angle.x, locked),
		"A+Shift+A 同按 40 帧后左手仍为 %.4f" % _state().hand_angle.x)
	var events: Array[Dictionary] = _harness.controller.take_events()
	_expect(_events_have_hand_dir(events, "left", 0), "冲突时发出 left dir=0 事件")
	_press({})
	_press({"left_raise": true})
	_step(4)
	_expect(_state().hand_angle.x > locked, "冲突解除后恢复动作：%.4f -> %.4f"
		% [locked, _state().hand_angle.x])
	_press({})


func _check_bounds_stress() -> void:
	print("")
	print("[6] 边界压力：横向 + 纵向 + 双手同时拉满 240 帧")
	_harness.controller.begin_drag(0, _chest_tag_px())
	_press({"left_raise": true, "right_raise": true, "both_raise": true})
	var x: float = 0.0
	var c: float = 0.0
	var l: float = 0.0
	var r: float = 0.0
	var oob: String = ""
	for _i in 240:
		_harness.controller.drag_to(Vector2(200.0, 120.0))
		_step(1)
		var s: PuppetState = _state()
		x = s.stage_pos.x
		c = s.stance
		l = s.hand_angle.x
		r = s.hand_angle.y
		if x > 1.0 or x < 0.0 or c > 1.0 or c < 0.0 \
				or l < PuppetState.HAND_ANGLE_MIN - 1e-6 or l > PuppetState.HAND_ANGLE_MAX + 1e-6 \
				or r < PuppetState.HAND_ANGLE_MIN - 1e-6 or r > PuppetState.HAND_ANGLE_MAX + 1e-6:
			oob = "x=%.6f stance=%.6f hand=(%.6f,%.6f)" % [x, c, l, r]
			break
	_expect(oob == "", "240 帧后无越界%s" % ("" if oob == "" else "：" + oob))
	_expect(is_equal_approx(x, 1.0), "横向停在右边界 x = %.4f" % x)
	_expect(is_equal_approx(c, 1.0), "站蹲停在完全蹲下 stance = %.4f" % c)
	_expect(is_equal_approx(l, PuppetState.HAND_ANGLE_MAX)
		and is_equal_approx(r, PuppetState.HAND_ANGLE_MAX),
		"双手角停在上限 180° = %.4f rad (%.4f, %.4f)" % [PuppetState.HAND_ANGLE_MAX, l, r])
	_harness.controller.end_drag()
	_press({})


## 真实窗口里的音乐时钟实测：确认时钟真的由音频播放位置驱动（而不是悄悄退化成自由计时），
## 并确认暂停会同时冻结时钟、恢复后沿同一时间轴继续、不跳变。
## 听感（是否真的听见鼓点）无法由本探针证明，必须人工听。
func _check_music_clock() -> void:
	print("")
	print("[7] 音乐时钟：真实时间测量由测试场景在 _process 中逐帧驱动（见 clock_check.gd）")
	if stage_def == null:
		print("  SKIP 未注入关卡数据，跳过本段")
		return
	_expect(stage_def.duration_ms == 35000, "第一关时长为 35000 ms（实际 %d）" % stage_def.duration_ms)
	var problems: Array[String] = stage_def.validate()
	_expect(problems.is_empty(), "第一关数据校验通过%s"
		% ("" if problems.is_empty() else "：" + str(problems)))


func _events_have(events: Array[Dictionary], kind: String) -> bool:
	for e in events:
		if e["kind"] == kind:
			return true
	return false


func _events_have_hand_dir(events: Array[Dictionary], hand: String, dir: int) -> bool:
	for e in events:
		if e["kind"] == "hand_motion" and e["payload"]["hand"] == hand \
				and int(e["payload"]["dir"]) == dir:
			return true
	return false
