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
## 第一关抬手落点的到位区间必须包住接伞的对齐窗口，两侧读数都取自它，故在这里对表。
const UmbrellaControllerScript := preload("res://scripts/a/umbrella_controller.gd")

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
	_test_15_level1_uses_90_degree_umbrella_pose(t)
	return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed,
		"failures": t.failures}


func _test_01_cue_table_covers_level1(t: ATestBase) -> void:
	t.begin("01 第一关关键动作表覆盖 PRD 要求")
	var def: StageDef = StageDefScript.make_level1()
	t.check_eq(def.cues.size(), 8, "应有 8 条关键动作")
	var problems: Array[String] = def.validate()
	t.check_eq(problems.size(), 0, "数据应通过校验：%s" % str(problems))

	var actions: Array[String] = []
	for cue in def.cues:
		actions.append(str(cue["action"]))
	t.check(actions.has(CueScript.ACTION_CROUCH) and actions.has(CueScript.ACTION_STAND_UP),
		"应含蹲下与站起（蹲下为站起提供起点）")
	t.check(actions.has(CueScript.ACTION_MOVE_LEFT) and actions.has(CueScript.ACTION_MOVE_RIGHT),
		"应含向左移动与向右移动（走到许仙身旁 → 持伞走到最右端 → 转身走回）")
	t.check(actions.has(CueScript.ACTION_HAND_RAISE), "应含抬手")
	# 借伞还伞流程（用户 2026-10-04 修订）：两次交接各占一条落点，
	# 加上「抬手到打伞位」「走到最右端」，就是这一折的全部关键动作。
	t.check(actions.has(CueScript.ACTION_UMBRELLA_TAKE), "应含接伞")
	t.check(actions.has(CueScript.ACTION_UMBRELLA_RETURN), "应含还伞")

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

	# 「走到最右端」的目标带必须与交接窗口完全不重叠：否则这一趟会先经过交接窗口，
	# 在还没到过右端的时候就被还伞判定抢走伞，流程顺序颠倒。
	var edge_band: Dictionary = _find(def, "l1_c5_move_to_edge")["target_range"]
	var take_band: Dictionary = _find(def, "l1_c4_take_umbrella")["target_range"]
	t.check(float(edge_band["min"]) > float(take_band["max"]),
		"最右端目标带（≥%.2f）应完全在交接窗口（≤%.2f）右侧"
			% [float(edge_band["min"]), float(take_band["max"])])
	# 两次交接共用同一个窗口：还伞遵循与接伞相同的判据
	t.check_approx(float(_find(def, "l1_c6_return_umbrella")["target_range"]["min"]),
		float(take_band["min"]), 1e-9, "还伞目标带应与接伞同一段窗口")
	t.finish("8 条关键动作覆盖蹲下/站起/左右移动/抬手/接伞/还伞，含重音落点，全部在时长内")


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


## 「到位」是全系统通用的判定规则，而第一关（游湖借伞）本身没有中位到位落点。
## 因此这里按引擎契约注入一条自定义 Cue，而不是借某一关的关卡数据：
## 关卡数据会随流程改动（借伞还伞定案就换过一次落点表），判定规则的回归测试不该跟着抖。
const REACH_CUE_ID: String = "t_reach_center"


func _reach_bench() -> CueTestBench:
	var b: CueTestBench = _bench()
	b.stage_def.cues.append(CueScript.make(REACH_CUE_ID, 14000, CueScript.ACTION_REACH, 0,
		{"key": "x", "min": 0.47, "max": 0.53}, 250, "reach_center"))
	b.performance.setup(b.stage_def.cues, b.clock, b.controller.puppets)
	return b


func _test_07_reach_is_continuous(t: ATestBase) -> void:
	t.begin("07 到位是连续条件：拖动中进入目标范围即判定")
	var b: CueTestBench = _reach_bench()
	var cue: Dictionary = b.find_cue(REACH_CUE_ID)
	var beat_ms: int = int(cue["beat_time_ms"])
	var range: Dictionary = cue["target_range"]
	t.check_approx(float(range["min"]), 0.47, 1e-9, "到位目标范围下限应为 0.47")
	t.check_approx(float(range["max"]), 0.53, 1e-9, "到位目标范围上限应为 0.53")

	# 落点前 1 s 停留：x=0.5 已在范围内，但玩家不在移动，不得判为「移动到到位」
	b.advance_to(maxi(beat_ms - 1000, 0))
	t.check(not b.performance.has_outcome(REACH_CUE_ID),
		"站定不动即使恰在目标范围内，也不得判为到位")

	# 先在窗口之外移出范围（约到 x≈0.58），这样回到范围的那一刻才代表「移动到到位」
	b.begin_drag()
	b.drag(Vector2(19.0, 0.0), 19)
	t.check(b.state().stage_pos.x > 0.53, "已移出中位范围：x=%.4f" % b.state().stage_pos.x)

	# 在落点前 60 ms 开始回到范围边缘；只用少量步数，确保判定落在窗口内
	b.advance_to(beat_ms - 60)
	var used: int = b.drag_until(Vector2(-19.0, 0.0), func() -> bool:
		return b.performance.has_outcome(REACH_CUE_ID), 4)
	if b.performance.has_outcome(REACH_CUE_ID):
		var outcome: Dictionary = b.performance.get_outcome(REACH_CUE_ID)
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
	t.check_eq(b.performance.pending_count(), 8, "开演时 8 条全部待判定")
	b.advance_to(7000)                     # 已过前两条落点，但什么都没做
	t.check(not b.performance.has_outcome("l1_c1_stand"),
		"没做动作就不应产生判定结果（留给切片 4 的补救处理）")
	t.check_eq(b.performance.pending_count(), 8, "未做的仍计入待判定")
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
	# 手角以「自然垂下」为 0、π/2 为水平前伸。第一关的抬手是「打伞位」：
	# 到位区间 75°~90°，且 90° 就是本关的手角上限（抬到顶即到位）。
	# 抬手速度 4.5 rad/s，从 0 抬到 75°（≈1.309 rad）约需 0.29 s，
	# 因此要在落点前约 300 ms 开始按住，让「跨入目标角度」正好落在判定窗内。
	b.advance_to(8300)
	b.advance(60, {"left_raise": true})
	var outcome: Dictionary = b.performance.get_outcome("l1_c3_hand_raise")
	# 手角存在 Vector2（float32）里：把上界 π/2 写进去、再读回来会大 4e-8，
	# 所以这里用判定侧同一个容差来断言（见 CueScript.CONDITION_EPSILON）。
	t.check_in_range(b.state().hand_angle.x, StageDef.LEVEL1_UMBRELLA_RAISE_MIN_RAD,
		StageDef.LEVEL1_UMBRELLA_RAISE_MAX_RAD + CueScript.CONDITION_EPSILON,
		"左手已抬到打伞位（水平前伸，停在本关上界也算）")
	# 停在上界必须仍算「到位」：玩家按住 A 到顶恰好停在本关上界，
	# 若边界比较不含表示误差，这一姿态会被判成「不在区间内」。
	t.check(CueScript.condition_met(b.find_cue("l1_c3_hand_raise"),
		CueScript.ACTION_HAND_RAISE, b.state().hand_angle.x),
		"停在 90°（本关上界）应算抬手到位，否则按住到顶反而判不到位")
	t.check_eq(bool(outcome.get("hit", false)), true,
		"进入角度范围时应命中，不必松键或反复按键")
	t.check_in_range(float(outcome.get("time_ms", -1)), 8500, 9000,
		"判定应发生在角度到位的时刻、且落在落点容差窗内")
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
	b.advance(60, {"left_raise": true})          # 提前把手举到顶：错拍
	var early: Dictionary = b.performance.get_outcome("l1_c3_hand_raise")
	t.check_eq(bool(early.get("hit", true)), false, "提前做应记为错拍")
	b.controller.set_input_map({"left_lower": true})
	b.advance(60)                                 # 放下来，退出目标角度
	b.controller.set_input_map({})
	b.advance_to(8300)
	b.advance(60, {"left_raise": true})          # 在判定窗内重新举到顶
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
	t.check(_find(b.stage_def, "l1_c5_move_to_edge").size() > 0,
		"本折的「走到最右端」落点存在（第 20 拍）")
	# 「走到最右端」的目标带是 x ∈ [0.94, 1.0]，落点 12500、判定窗 12250~12750。
	# 先把白素贞拖到目标带左侧，再在松开当帧用一次大位移跨进目标带——
	# 验证 drag_end 不会抢先关掉到位判定（末段位移必须仍按「进入目标区」计）。
	b.advance_to(12300)
	b.begin_drag()
	b.drag(Vector2(440.0, 0.0), 1)
	t.check(b.state().stage_pos.x < 0.94, "松开前还在目标带左侧：x=%.4f" % b.state().stage_pos.x)
	b.controller.drag_to(Vector2(434.0, 0.0))
	b.controller.end_drag()
	b.advance(1)
	var outcome: Dictionary = b.performance.get_outcome("l1_c5_move_to_edge")
	t.check_in_range(b.state().stage_pos.x, 0.94, 1.0, "松开当帧位置已进入目标区")
	t.check_eq(bool(outcome.get("hit", false)), true,
		"drag_end 不能抢先关闭拖动判定")
	t.finish("末段位移在松开当帧仍参与到位判定")


## 第一关「打伞位」：许仙举 90°、本关手角上限也是 90°（用户 2026-10-04 定案），
## 而且「抬手」落点的到位区间必须**完整包住接伞的对齐窗口**。
##
## 这条不变量是关键：接伞要求「两手手高差 ≤ 容差」，抬手落点又要求「角度在某区间内」，
## 两者若错配，玩家就会遇到「拍点算抬手到位、伞却不换手」。这里用数值扫描反推对齐窗口
## （而不是把公式再抄一遍），再要求它落在落点区间之内。
func _test_15_level1_uses_90_degree_umbrella_pose(t: ATestBase) -> void:
	t.begin("15 第一关打伞位：许仙举 90°，抬手落点包住接伞对齐窗口")
	var def: StageDef = StageDefScript.make_level1()
	t.check_approx(def.hand_angle_max_rad, StageDef.LEVEL1_HAND_MAX_RAD, 1e-9,
		"第一关的手角上限应是 90°（打伞位）")
	t.check_approx(def.hand_angle_max_rad, PI * 0.5, 1e-9, "90° 即 π/2")
	var angles: Array = def.initial["hand_angles"][UmbrellaControllerScript.XUXIAN_ID]
	t.check_approx(float(angles[1]), StageDef.LEVEL1_HAND_MAX_RAD, 1e-9,
		"许仙开局右手应举在 90°（水平前伸）持伞")

	var cue: Dictionary = _find(def, "l1_c3_hand_raise")
	t.check(not cue.is_empty(), "应存在抬手落点 l1_c3_hand_raise")
	var range: Dictionary = cue.get("target_range", {})
	var reference: float = UmbrellaController.hand_height(StageDef.LEVEL1_HAND_MAX_RAD, 0.0)
	var tolerance: float = UmbrellaControllerScript.HAND_HEIGHT_TOLERANCE
	var step: float = 0.0025
	var window_min: float = INF
	var window_max: float = -INF
	var angle: float = 0.0
	while angle <= def.hand_angle_max_rad + step * 0.5:
		if absf(UmbrellaController.hand_height(angle, 0.0) - reference) <= tolerance:
			window_min = minf(window_min, angle)
			window_max = maxf(window_max, angle)
		angle += step
	t.check(window_min < INF,
		"本关上限之内应存在与许仙右手齐平的角度（容差 %.3f）" % tolerance)
	t.check(window_min >= float(range.get("min", 0.0)) - 1e-9
			and window_max <= float(range.get("max", PI)) + 1e-9,
		"抬手到位区间 %.4f~%.4f 应包住对齐窗口 %.4f~%.4f（否则会出现「算到位、不换手」）"
			% [float(range.get("min", 0.0)), float(range.get("max", PI)),
				window_min, window_max])
	t.finish("打伞位 90°：抬手到位与接伞对齐落在同一段角度里")
