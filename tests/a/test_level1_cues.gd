extends RefCounted
class_name TestLevel1Cues
## 切片 3 的行为测试：第一关关键动作判定、线索提前量、判定窗与容差、
## 错拍照常发生、平移不逐帧评分、事件契约。
##
## 时间由测试台推进时钟给出，因此每个落点的窗口边界都可精确断言。

const ATestBaseScript := preload("res://tests/a/a_test_base.gd")
const BenchScript := preload("res://tests/a/cue_test_bench.gd")
const StageDefScript := preload("res://scripts/a/stage_def.gd")
const CueScript := preload("res://scripts/a/cue.gd")
const CueHintScript := preload("res://scripts/a/cue_hint.gd")

const CROUCH_STEP_PX: float = 120.0
const CROUCH_STEPS: int = 12            ## 12 x 120/1080 ≈ 1.33，足以蹲到底并被截断
## 站起：每步 8 px 时 stance 每步降 8/1080 ≈ 0.0074，从 1.0 降到 0.05 需 130 步 = 1300 ms。
## 因此把「开始站起」的时刻设在落点前 1250 ms，跨过阈值约在落点后 50 ms。
const STAND_STEP_PX: float = 8.0
const STAND_STEPS: int = 130
const STAND_WINDOW_MS: int = 250


func _bench() -> CueTestBench:
	return BenchScript.new()


## 蹲到底（stance 被截断在 1.0）
func _crouch(b: CueTestBench, at_ms: int) -> void:
	b.advance_to(at_ms)
	b.begin_drag()
	b.drag(Vector2(0.0, CROUCH_STEP_PX), CROUCH_STEPS)
	b.end_drag()


## 从蹲位起立指定的拖动步数（每步 step_px），用于把「跨过站起阈值」的时刻对准落点。
## 每步 = STEP_MS 毫秒，stance 每步变化 step_px/1080。
func _stand_up_steps(b: CueTestBench, step_px: float, steps: int) -> void:
	b.begin_drag()
	b.drag(Vector2(0.0, -step_px), steps)
	b.end_drag()


func _filter(log: Array, kind: String) -> Array:
	var out: Array = []
	for e in log:
		if str(e["kind"]) == kind:
			out.append(e)
	return out


func _count_for_cue(log: Array, kind: String, cue_id: String) -> int:
	var n: int = 0
	for e in log:
		if str(e["kind"]) == kind and str(e["cue_id"]) == cue_id:
			n += 1
	return n


func _has_cue_event(log: Array, kind: String, cue_id: String) -> bool:
	return _count_for_cue(log, kind, cue_id) > 0


func _find(def: StageDef, cue_id: String) -> Dictionary:
	for cue in def.cues:
		if str(cue["cue_id"]) == cue_id:
			return cue
	return {}


func run_all() -> Dictionary:
	var t: ATestBase = ATestBaseScript.new()
	_test_01_cue_table_covers_level1(t)
	_test_02_hints_before_deadline(t)
	_test_03_hit_inside_window(t)
	_test_04_miss_outside_window_action_still_happens(t)
	_test_05_tolerance_is_configurable(t)
	_test_06_translation_not_scored_per_frame(t)
	_test_07_reach_is_continuous(t)
	_test_08_event_contract(t)
	_test_09_unchosen_cues_remain_pending(t)
	_test_10_no_leak_of_beat_or_score(t)
	_test_11_held_hand_enters_target_range(t)
	_test_12_same_direction_move_hits(t)
	_test_13_early_action_can_be_retried_on_beat(t)
	_test_14_release_applies_final_reach(t)
	return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed,
		"failures": t.failures}


func _test_01_cue_table_covers_level1(t: ATestBase) -> void:
	t.begin("01 第一关关键动作表覆盖 PRD 要求")
	var def: StageDef = StageDefScript.make_level1()
	t.check_eq(def.cues.size(), 6, "应有 6 条关键动作")
	var problems: Array[String] = def.validate()
	t.check_eq(problems.size(), 0, "数据应通过校验：%s" % str(problems))

	var actions: Array[String] = []
	for cue in def.cues:
		actions.append(str(cue["action"]))
	t.check(actions.has(CueScript.ACTION_CROUCH) and actions.has(CueScript.ACTION_STAND_UP),
		"应含蹲下与站起（蹲下为站起提供起点）")
	t.check(actions.has(CueScript.ACTION_MOVE_LEFT) and actions.has(CueScript.ACTION_MOVE_RIGHT),
		"应含横向移动（左右）")
	t.check(actions.has(CueScript.ACTION_HAND_RAISE), "应含抬手")

	# 重音每 4 拍一次；至少一次关键动作落在重音上
	var accent_hits: int = 0
	for cue in def.cues:
		var beat_index: int = int(round(float(cue["beat_time_ms"]) / def.beat_duration_ms()))
		if beat_index > 0 and beat_index % 4 == 0:
			accent_hits += 1
	t.check(accent_hits >= 1, "至少一次关键动作落在重音上，实际 %d 次" % accent_hits)

	var within_level: bool = true
	for cue in def.cues:
		var beat_ms: int = int(cue["beat_time_ms"])
		if beat_ms <= 0 or beat_ms + int(cue["tolerance_ms"]) > def.duration_ms:
			within_level = false
	t.check(within_level, "所有落点（含容差）都应在 35 s 内")

	# 站起与蹲下的目标范围方向必须相反，否则蹲到底会被判成站起
	var stand_max: float = float(_find(def, "l1_c1_stand")["target_range"]["max"])
	var crouch_min: float = float(_find(def, "l1_c0_crouch")["target_range"]["min"])
	t.check(stand_max <= 0.1, "站起到位范围应接近完全站立（stance≈0），实际 max=%.4f" % stand_max)
	t.check(crouch_min >= 0.8, "蹲下到位范围应接近完全蹲下（stance≈1），实际 min=%.4f" % crouch_min)
	t.finish("6 条关键动作覆盖蹲下/站起/左右移动/抬手，含重音落点，全部在时长内")


func _test_02_hints_before_deadline(t: ATestBase) -> void:
	t.begin("02 每条关键动作在落点前都能读到线索数据")
	var def: StageDef = StageDefScript.make_level1()
	var all_early: bool = true
	var details: Array[String] = []
	for cue in def.cues:
		var cue_id: String = str(cue["cue_id"])
		var hint_ms: int = CueScript.hint_time_ms(cue)
		var beat_ms: int = int(cue["beat_time_ms"])
		if hint_ms >= beat_ms or hint_ms < 0:
			all_early = false
			details.append("%s 线索 %d 落点 %d" % [cue_id, hint_ms, beat_ms])
	t.check(all_early, "每条线索时间都应早于落点：%s"
		% ("全部满足" if all_early else ", ".join(details)))

	for cue in def.cues:
		var cue_id: String = str(cue["cue_id"])
		var hint_ms: int = CueScript.hint_time_ms(cue)
		var b: CueTestBench = _bench()
		b.advance_to(maxi(hint_ms - b.STEP_MS, 0))
		t.check(not _has_cue_event(b.judge_log, "cue_hint", cue_id),
			"%s 在线索时间之前不应已发出线索" % cue_id)
		b.advance(1)
		t.check(_has_cue_event(b.judge_log, "cue_hint", cue_id),
			"%s 在线索时间到达时应发出 cue_hint" % cue_id)
		var payload: Dictionary = {}
		for e in b.judge_log:
			if str(e["kind"]) == "cue_hint" and str(e["cue_id"]) == cue_id:
				payload = e["payload"]
		t.check(payload.has("hint_kind") and payload.has("action")
			and payload.has("demo_action") and payload.has("target_range"),
			"%s 的线索载荷应含 hint_kind/action/demo_action/target_range" % cue_id)
	t.finish("线索在落点前 1 s 准时可见，载荷字段齐备")


func _test_03_hit_inside_window(t: ATestBase) -> void:
	t.begin("03 判定窗内做出动作记为命中，并记录偏移")
	var b: CueTestBench = _bench()
	var beat_ms: int = int(b.find_cue("l1_c1_stand")["beat_time_ms"])
	_crouch(b, 1000)
	t.check_in_range(b.state().stance, 0.99, 1.0, "已蹲到底")

	# 起立约 130 步 x 10 ms = 1300 ms；从落点前 1250 ms 开始，跨过阈值约在 +50 ms，
	# 落在 ±250 ms 判定窗内。
	b.advance_to(maxi(beat_ms - 1250, 0))
	_stand_up_steps(b, 8.0, STAND_STEPS)
	t.check(b.performance.has_outcome("l1_c1_stand"), "应产生判定结果")
	if b.performance.has_outcome("l1_c1_stand"):
		var outcome: Dictionary = b.performance.get_outcome("l1_c1_stand")
		t.check_eq(bool(outcome["hit"]), true,
			"窗内站起应命中（offset=%d ms，容差 %d ms）"
			% [int(outcome["offset_ms"]), int(outcome["tolerance_ms"])])
		t.check_in_range(float(outcome["offset_ms"]), -STAND_WINDOW_MS, STAND_WINDOW_MS,
			"命中偏移应在 ±250 ms 内")
	t.check(b.state().stance <= 0.05, "站起后姿势确实到位：stance=%.4f" % b.state().stance)
	t.finish("窗内站起命中，偏移被记录，姿势照常到位")


func _test_04_miss_outside_window_action_still_happens(t: ATestBase) -> void:
	t.begin("04 窗外做同一动作记为未命中，但动作照常发生")
	var b: CueTestBench = _bench()
	var beat_ms: int = int(b.find_cue("l1_c1_stand")["beat_time_ms"])
	_crouch(b, 1000)

	# 起立约需 1290 ms。开始得越早，跨过阈值时离落点越远：
	# 从落点前 2100 ms 开始，跨过阈值约在 -810 ms，明确落在容差之外。
	b.advance_to(maxi(beat_ms - 2100, 0))
	t.check(b.state().stance > 0.85, "错拍开始前仍在蹲位：stance=%.4f" % b.state().stance)
	# 用每步 15 px、共 68 步尽快站起：跨过阈值约在落点前 690 ms，明确落在容差之外
	_stand_up_steps(b, 15.0, 69)
	t.check_in_range(b.state().stance, 0.0, 0.05, "错拍做站起，姿势照常到位：stance=%.4f"
		% b.state().stance)
	t.check(b.performance.has_outcome("l1_c1_stand"), "应产生判定结果")
	if b.performance.has_outcome("l1_c1_stand"):
		var miss: Dictionary = b.performance.get_outcome("l1_c1_stand")
		t.check_eq(bool(miss["hit"]), false,
			"窗外站起应记为未命中（offset=%d ms）" % int(miss["offset_ms"]))
		t.check(int(miss["offset_ms"]) < -STAND_WINDOW_MS,
			"未命中偏移应超出容差：%d ms" % int(miss["offset_ms"]))
	t.check(_has_cue_event(b.judge_log, "cue_fire", "l1_c1_stand"),
		"即使未命中也应发出 cue_fire（物理动作发生了）")
	t.finish("窗外动作照常发生，如实记为未命中")


func _test_05_tolerance_is_configurable(t: ATestBase) -> void:
	t.begin("05 判定容差是可配置字段，改变它即改变命中边界")
	var b: CueTestBench = _bench()
	for cue in b.stage_def.cues:
		if str(cue["cue_id"]) == "l1_c1_stand":
			cue["tolerance_ms"] = 2500
	b.performance.setup(b.stage_def.cues, b.clock, b.controller.puppets)
	var beat_ms: int = int(b.find_cue("l1_c1_stand")["beat_time_ms"])
	_crouch(b, 1000)

	b.advance_to(maxi(beat_ms - 2100, 0))   # 与上一条测试完全相同的时刻
	_stand_up_steps(b, 15.0, 69)
	t.check(b.performance.has_outcome("l1_c1_stand"), "应产生判定结果")
	if b.performance.has_outcome("l1_c1_stand"):
		var outcome: Dictionary = b.performance.get_outcome("l1_c1_stand")
		t.check_eq(int(outcome["tolerance_ms"]), 2500,
			"判定结果应记录使用的容差：%d" % int(outcome["tolerance_ms"]))
		t.check_eq(bool(outcome["hit"]), true,
			"容差放大到 2500 ms 后同一时刻应判为命中（offset=%d ms）" % int(outcome["offset_ms"]))
	t.finish("容差为可配置项，判定边界随配置改变")


func _test_06_translation_not_scored_per_frame(t: ATestBase) -> void:
	t.begin("06 平移不逐帧评分：一次持续横向拖动只判定一次")
	var b: CueTestBench = _bench()
	var beat_ms: int = int(b.find_cue("l1_c2_move_left")["beat_time_ms"])
	b.advance_to(maxi(beat_ms - 600, 0))
	b.begin_drag()
	b.drag(Vector2(-30.0, 0.0), 20)        # 持续向左拖 20 帧
	b.end_drag()
	b.advance(20)                          # 松手后继续观察

	t.check_eq(_count_for_cue(b.judge_log, "cue_fire", "l1_c2_move_left"), 1,
		"20 帧持续平移只应产出 1 次 cue_fire，实际 %d"
		% _count_for_cue(b.judge_log, "cue_fire", "l1_c2_move_left"))
	var graded: int = _count_for_cue(b.judge_log, "cue_hit", "l1_c2_move_left") \
		+ _count_for_cue(b.judge_log, "cue_miss", "l1_c2_move_left")
	t.check_eq(graded, 1, "该 Cue 只应被判定一次，实际 %d" % graded)
	t.check(b.controller_log.size() > 1, "控制器事件确实有很多条（%d 条），但判定只有一条"
		% b.controller_log.size())
	t.finish("持续平移只记一次动作与一次判定，不逐帧评分")


func _test_07_reach_is_continuous(t: ATestBase) -> void:
	t.begin("07 到位是连续条件：拖动中进入目标范围即判定")
	var b: CueTestBench = _bench()
	var cue: Dictionary = b.find_cue("l1_c5_reach_center")
	var beat_ms: int = int(cue["beat_time_ms"])
	var range: Dictionary = cue["target_range"]
	t.check_approx(float(range["min"]), 0.47, 1e-9, "到位目标范围下限应为 0.47")
	t.check_approx(float(range["max"]), 0.53, 1e-9, "到位目标范围上限应为 0.53")

	# 落点前 1 s 停留：x=0.5 已在范围内，但玩家不在移动，不得判为「移动到到位」
	b.advance_to(maxi(beat_ms - 1000, 0))
	t.check(not b.performance.has_outcome("l1_c5_reach_center"),
		"站定不动即使恰在目标范围内，也不得判为到位")

	# 先在窗口之外移出范围（约到 x≈0.58），这样回到范围的那一刻才代表「移动到到位」
	b.begin_drag()
	b.drag(Vector2(19.0, 0.0), 19)
	t.check(b.state().stage_pos.x > 0.53, "已移出中位范围：x=%.4f" % b.state().stage_pos.x)

	# 在落点前 60 ms 开始回到范围边缘；只用少量步数，确保判定落在窗口内
	b.advance_to(beat_ms - 60)
	var used: int = b.drag_until(Vector2(-19.0, 0.0), func() -> bool:
		return b.performance.has_outcome("l1_c5_reach_center"), 4)
	if b.performance.has_outcome("l1_c5_reach_center"):
		var outcome: Dictionary = b.performance.get_outcome("l1_c5_reach_center")
		t.check_eq(bool(outcome["hit"]), true,
			"落点附近回到中位应命中（offset=%d ms，x=%.4f）"
			% [int(outcome["offset_ms"]), float(outcome["metric"])])
		t.check(b.state().stage_pos.x >= 0.47 and b.state().stage_pos.x <= 0.53,
			"判定发生时确实在目标范围内：x=%.4f" % b.state().stage_pos.x)
	b.end_drag()
	t.finish("到位按拖动中的连续状态判定，站定不动不算到位")


func _test_08_event_contract(t: ATestBase) -> void:
	t.begin("08 cue_* 事件契约与 take_events 语义")
	var b: CueTestBench = _bench()
	var beat_ms: int = int(b.find_cue("l1_c1_stand")["beat_time_ms"])
	_crouch(b, 1000)
	b.advance_to(maxi(beat_ms - 1250, 0))
	_stand_up_steps(b, 8.0, STAND_STEPS)
	b.advance(10)

	var shape_ok: bool = true
	var cue_events: int = 0
	var monotonic: bool = true
	var previous: int = -1
	for e in b.judge_log:
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
		if str(e["kind"]).begins_with("cue_"):
			cue_events += 1
			if str(e["cue_id"]).is_empty():
				shape_ok = false
		if int(e["time_ms"]) < previous:
			monotonic = false
		previous = int(e["time_ms"])
	t.check(shape_ok, "每个判定事件都应含五个字段且类型正确，cue_* 必须带 cue_id")
	t.check(monotonic, "判定事件 time_ms 应单调不减")
	t.check(cue_events >= 3, "应至少产生线索、动作、判定三类事件，实际 %d 条" % cue_events)
	t.check_eq(b.performance.take_events().size(), 0, "take_events 取走后应清空")

	var hit_payload: Dictionary = {}
	for e in b.judge_log:
		if str(e["kind"]) == "cue_hit":
			hit_payload = e["payload"]
	t.check(hit_payload.has("offset_ms") and hit_payload.has("tolerance_ms")
		and hit_payload.has("action") and hit_payload.has("metric"),
		"cue_hit 载荷应含 offset_ms/tolerance_ms/action/metric")
	t.finish("判定事件字段齐备、带 cue_id、时间单调、取走即清空")


func _test_09_unchosen_cues_remain_pending(t: ATestBase) -> void:
	t.begin("09 未做的关键动作保持待判定，不被静默跳过")
	var b: CueTestBench = _bench()
	b.advance(1)
	t.check_eq(b.performance.pending_count(), 6, "开演时 6 条全部待判定")
	b.advance_to(7000)                     # 已过前两条落点，但什么都没做
	t.check(not b.performance.has_outcome("l1_c1_stand"),
		"没做动作就不应产生判定结果（留给切片 4 的补救处理）")
	t.check_eq(b.performance.pending_count(), 6, "未做的仍计入待判定")
	t.check_eq(_filter(b.judge_log, "cue_hit").size(), 0, "不应凭空产生命中")
	t.check(_has_cue_event(b.judge_log, "cue_hint", "l1_c1_stand"),
		"线索仍应按时发出（目标在落点前已被告知）")
	t.finish("未做的关键动作保持待判定，不静默跳过、不凭空判定")


func _test_10_no_leak_of_beat_or_score(t: ATestBase) -> void:
	t.begin("10 线索不泄露精确拍号、容差或评分")
	var def: StageDef = StageDefScript.make_level1()
	var forbidden: Array[String] = ["score", "percent", "accuracy", "tolerance_ms",
		"offset_ms", "beat_index", "applause"]
	var leaked: Array[String] = []
	for cue in def.cues:
		var hint: Dictionary = CueHintScript.make(cue)
		for key in hint.keys():
			if forbidden.has(str(key)):
				leaked.append("%s 的线索含 %s" % [str(cue["cue_id"]), str(key)])
	t.check(leaked.is_empty(), "线索载荷不应含评分/容差/精确拍号字段：%s"
		% ("无" if leaked.is_empty() else ", ".join(leaked)))
	t.check(CueHintScript.kind_for_action(CueScript.ACTION_STAND_UP)
		== CueHintScript.KIND_STANCE, "站起应映射为站姿线索")
	t.check(CueHintScript.kind_for_action(CueScript.ACTION_HAND_RAISE)
		== CueHintScript.KIND_HAND, "抬手应映射为手部线索")
	t.check(CueHintScript.kind_for_action(CueScript.ACTION_MOVE_LEFT)
		== CueHintScript.KIND_MOVE, "横向移动应映射为移动线索")
	t.finish("线索只表达「做什么」，不含评分、容差或精确拍号")


func _test_11_held_hand_enters_target_range(t: ATestBase) -> void:
	t.begin("11 按住抬手键进入目标角度时命中")
	var b: CueTestBench = _bench()
	b.advance_to(8600)
	b.advance(12, {"left_raise": true})
	var outcome: Dictionary = b.performance.get_outcome("l1_c3_hand_raise")
	t.check_in_range(b.state().hand_angle.x, 0.5, 0.6, "左手已抬到目标角度")
	t.check_eq(bool(outcome.get("hit", false)), true,
		"进入角度范围时应命中，不必松键或反复按键")
	t.check_in_range(float(outcome.get("time_ms", -1)), 8600, 8750,
		"判定应发生在角度到位的时刻")
	t.check_eq(_count_for_cue(b.judge_log, "cue_hit", "l1_c3_hand_raise"), 1,
		"持续按键只产生一次命中")
	t.finish("持续按键跨入目标角度时只判定一次")


func _test_12_same_direction_move_hits(t: ATestBase) -> void:
	t.begin("12 已面向左时再次左移到目标范围仍能命中")
	var b: CueTestBench = _bench()
	b.begin_drag()
	b.drag(Vector2(-30.0, 0.0), 10)
	b.end_drag()
	b.advance(30)
	t.check_approx(b.state().facing, -1.0, 0.001, "已完成向左转身")
	b.performance.setup(b.stage_def.cues, b.clock, b.controller.puppets)
	b.advance_to(4800)
	b.begin_drag()
	b.drag(Vector2(-30.0, 0.0), 10)
	b.end_drag()
	var outcome: Dictionary = b.performance.get_outcome("l1_c2_move_left")
	t.check(b.state().stage_pos.x < 0.35, "实际已向左移动到目标区")
	t.check_eq(bool(outcome.get("hit", false)), true,
		"同向继续移动应按位置变化判定，不能依赖新转身事件")
	t.check_eq(_count_for_cue(b.judge_log, "cue_hit", "l1_c2_move_left"), 1,
		"同一次拖动只命中一次")
	t.finish("再次同向移动能命中且不逐帧评分")


func _test_13_early_action_can_be_retried_on_beat(t: ATestBase) -> void:
	t.begin("13 提前做错后重新抬手，拍点内可命中并保留失误事件")
	var b: CueTestBench = _bench()
	b.advance_to(1000)
	b.advance(12, {"left_raise": true})
	var early: Dictionary = b.performance.get_outcome("l1_c3_hand_raise")
	t.check_eq(bool(early.get("hit", true)), false, "提前做应记为错拍")
	b.controller.set_input_map({"left_lower": true})
	b.advance(12)
	b.controller.set_input_map({})
	b.advance_to(8600)
	b.advance(12, {"left_raise": true})
	var retried: Dictionary = b.performance.get_outcome("l1_c3_hand_raise")
	t.check_eq(bool(retried.get("hit", false)), true, "重新进入目标范围应在拍点内命中")
	t.check(_has_cue_event(b.judge_log, "cue_miss", "l1_c3_hand_raise"),
		"原错拍事件应留在事件流中")
	t.check_eq(_count_for_cue(b.judge_log, "cue_hit", "l1_c3_hand_raise"), 1,
		"后续命中只记录一次")
	t.finish("提前错拍不会永久锁死 cue，原失误事件仍可录制")


func _test_14_release_applies_final_reach(t: ATestBase) -> void:
	t.begin("14 松开鼠标当帧的末段位移进入目标区仍判到位")
	var b: CueTestBench = _bench()
	b.advance_to(14900)
	b.begin_drag()
	b.drag(Vector2(50.0, 0.0), 3)
	t.check(b.state().stage_pos.x > 0.53, "松开前已移出中位范围")
	b.advance_to(14980)
	b.controller.drag_to(Vector2(-120.0, 0.0))
	b.controller.end_drag()
	b.advance(1)
	var outcome: Dictionary = b.performance.get_outcome("l1_c5_reach_center")
	t.check_in_range(b.state().stage_pos.x, 0.47, 0.53, "松开当帧位置已进入目标区")
	t.check_eq(bool(outcome.get("hit", false)), true,
		"drag_end 不能抢先关闭拖动判定")
	t.finish("末段位移在松开当帧仍参与到位判定")
