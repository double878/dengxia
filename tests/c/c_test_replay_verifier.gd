extends RefCounted
class_name CTestReplayVerifier
## 切片 7 行为测试：回放验收器。
##
## 重点不在「干净记录能通过」——那是最容易写对的一半。真正要证明的是
## **验收器抓得住问题**：一个永远报通过的验收器等于没有验收。
## 因此本套件花了大半篇幅构造「不一致的输入」，逐项验证对应检查会报出来。
##
## 两类用例：
##   A. 端到端篡改记录 → 走 verify() 全流程，问题必须被报出
##   B. 检测器判别力 → 直接给某项检查喂不一致的数据，验证它报错
##      （B 类是必要的：采样保真这类检查两侧数据同源于记录，
##        只有回放器本身有 bug 才会不一致，测试里无法制造；
##        故改为直接测它的比对函数能否识别差异。）
##
## 依赖一律用 preload 常量：--headless --script 不读全局类名缓存。

const CReplayVerifierScript := preload("res://scripts/c/c_replay_verifier.gd")
const CMockPerformerScript := preload("res://scripts/c/c_mock_performer.gd")
const CTimedEventScript := preload("res://scripts/c/c_timed_event.gd")
const CResultFlowScript := preload("res://scripts/c/c_result_flow.gd")


func run_all() -> Dictionary:
	var t: Variant = preload("res://tests/c/c_test_base.gd").new()
	_test_01_clean_record_passes(t)
	_test_02_six_checks_all_pass(t)
	_test_03_stage5_applause_curtain_call(t)
	_test_04_stage5_no_applause_played_out(t)
	_test_05_stats_match_record(t)
	_test_06_event_seq_gap_caught(t)
	_test_07_snapshot_time_reversed_caught(t)
	_test_08_event_time_beyond_duration_caught(t)
	_test_09_timeline_last_frame_misaligned_caught(t)
	_test_10_timeline_backwards_caught(t)
	_test_11_events_count_mismatch_caught(t)
	_test_12_event_time_rewritten_caught(t)
	_test_13_event_dispatched_early_caught(t)
	_test_14_event_dispatched_late_caught(t)
	_test_15_canned_animation_caught_by_order(t)
	_test_16_swapped_discrete_order_caught(t)
	_test_17_puppet_mismatch_detected(t)
	_test_18_lamp_mismatch_detected(t)
	_test_19_expected_ending_boundaries(t)
	_test_20_report_renders(t)
	_test_21_mock_discrete_transitions_exactly_two(t)
	return t.report()


func _clean(p_stage_id: int = 1, p_with_applause: bool = false) -> Variant:
	return CMockPerformerScript.new().build(p_stage_id, p_with_applause)


## ---------------------------------------------------------------- 正向：通过


func _test_01_clean_record_passes(t: Variant) -> void:
	t.begin("干净记录必须通过验收")
	var report: Dictionary = CReplayVerifierScript.new().verify(_clean())
	t.check(bool(report["ok"]), "整体通过")
	t.check_eq(report["problems"].size(), 0, "无问题项")
	t.check_eq(int(report["duration_ms"]), 8000, "时长 8000ms")
	t.finish("基准通过")


func _test_02_six_checks_all_pass(t: Variant) -> void:
	t.begin("六项核心检查逐一通过")
	var report: Dictionary = CReplayVerifierScript.new().verify(_clean())
	var checks: Array = report["checks"]
	# 六项核心检查 + 一项「回放可推进」前置（不通过则后面的走查无从谈起）
	t.check_eq(checks.size(), 7, "七项检查都跑了")
	var names: Array = []
	for c in checks:
		names.append(str(c["name"]))
		t.check(bool(c["ok"]), "「%s」通过（%s）" % [str(c["name"]), str(c["detail"])])
	# 核心六项一个都不能少：少一项就等于有维度没验
	t.check(names.has("记录自检"), "含记录自检")
	t.check(names.has("采样保真（不漏动作·不换错头·非预制）"), "含采样保真")
	t.check(names.has("时间轴（时长覆盖·单调·末尾对齐）"), "含时间轴")
	t.check(names.has("离散跳变顺序（换头/挂起不合并）"), "含离散跳变顺序")
	t.check(names.has("关键事件时间（不漏·不重·不早不晚）"), "含关键事件时间")
	t.check(names.has("掌声与结局（不改变结局）"), "含掌声与结局")
	t.finish("六项核心齐备且通过")


func _test_03_stage5_applause_curtain_call(t: Variant) -> void:
	t.begin("第 5 关两段掌声判满堂彩且通过验收")
	var report: Dictionary = CReplayVerifierScript.new().verify(_clean(5, true))
	t.check(bool(report["ok"]), "整体通过")
	t.check_eq(int(report["stats"]["applause_act_count"]), 2, "掌声段数为 2")
	t.check_eq(StringName(report["stats"]["ending"]),
		CResultFlowScript.ENDING_CURTAIN_CALL, "结局满堂彩")
	t.finish("结局与文案一致")


func _test_04_stage5_no_applause_played_out(t: Variant) -> void:
	t.begin("第 5 关无掌声判戏散了且通过验收")
	var report: Dictionary = CReplayVerifierScript.new().verify(_clean(5, false))
	t.check(bool(report["ok"]), "整体通过")
	t.check_eq(int(report["stats"]["applause_act_count"]), 0, "掌声段数为 0")
	t.check_eq(StringName(report["stats"]["ending"]),
		CResultFlowScript.ENDING_PLAYED_OUT, "结局戏散了")
	t.finish("两档结局都能判对")


func _test_05_stats_match_record(t: Variant) -> void:
	t.begin("报告统计与记录一致")
	var record: Variant = _clean(5, true)
	var report: Dictionary = CReplayVerifierScript.new().verify(record)
	var stats: Dictionary = report["stats"]
	t.check_eq(int(stats["snapshot_count"]), record.snapshots.size(), "快照数与记录一致")
	t.check_eq(int(stats["event_count"]), record.events.size(), "事件数与记录一致")
	t.check_eq(int(stats["act_count"]), record.acts.size(), "幕数与记录一致")
	t.check(int(stats["replay_frames"]) > 0, "回放确实产出了帧")
	t.check_eq(int(stats["dispatched_events"]), record.events.size(), "派发事件数等于记录事件数")
	t.check(int(stats["discrete_tokens"]) > 0, "导出到离散跳变")
	t.finish("统计可信")


## ------------------------------------------------- 端到端篡改：必须被 verify 报出


func _test_06_event_seq_gap_caught(t: Variant) -> void:
	t.begin("篡改：事件 seq 断裂被记录自检拦下")
	var record: Variant = _clean()
	# 抽掉中间一条，seq 出现空洞（10 的值域不再连续）
	record.events.remove_at(3)
	var report: Dictionary = CReplayVerifierScript.new().verify(record)
	t.check_eq(bool(report["ok"]), false, "整体不通过")
	t.check_eq(report["checks"].size(), 1, "只跑记录自检就停手（基准已错，继续比对没有意义）")
	t.check_eq(str(report["checks"][0]["name"]), "记录自检", "停在记录自检")
	var joined: String = "\n".join(report["problems"])
	t.check(joined.contains("seq"), "报出 seq 问题")
	t.finish("闸门生效")


func _test_07_snapshot_time_reversed_caught(t: Variant) -> void:
	t.begin("篡改：快照时间倒序被记录自检拦下")
	var record: Variant = _clean()
	var tmp: Variant = record.snapshots[10]
	record.snapshots[10] = record.snapshots[11]
	record.snapshots[11] = tmp
	var report: Dictionary = CReplayVerifierScript.new().verify(record)
	t.check_eq(bool(report["ok"]), false, "整体不通过")
	var joined: String = "\n".join(report["problems"])
	t.check(joined.contains("非递增"), "报出时间非递增")
	t.finish("闸门生效")


func _test_08_event_time_beyond_duration_caught(t: Variant) -> void:
	t.begin("篡改：事件时刻超出本关时长被拦下")
	var record: Variant = _clean()
	record.events[0].time_ms = 99999
	var report: Dictionary = CReplayVerifierScript.new().verify(record)
	t.check_eq(bool(report["ok"]), false, "整体不通过")
	var joined: String = "\n".join(report["problems"])
	t.check(joined.contains("超出本关时长"), "报出越界")
	t.finish("闸门生效")


## ------------------------------------------- 检测器判别力：直接喂不一致的数据


func _test_09_timeline_last_frame_misaligned_caught(t: Variant) -> void:
	t.begin("检测器：末帧未对齐时长会被报出")
	var v: Variant = CReplayVerifierScript.new()
	var record: Variant = _clean()
	var walk: Dictionary = v._walk(record, 17)
	var frames: Array = walk["frames"]
	# 抹掉末尾 10ms：正是步长除不尽时不补末帧的真实症状
	frames[-1]["now_ms"] = 7990
	var r: Dictionary = v._check_timeline(record, frames, 8000)
	t.check_eq(r["problems"].size(), 1, "报出一处")
	t.check(str(r["problems"][0]).contains("未对齐"), "指出末帧未对齐")
	t.finish("末尾对齐被守住")


func _test_10_timeline_backwards_caught(t: Variant) -> void:
	t.begin("检测器：播放头倒退会被报出")
	var v: Variant = CReplayVerifierScript.new()
	var record: Variant = _clean()
	var frames: Array = v._walk(record, 17)["frames"]
	frames[5]["now_ms"] = 0
	var r: Dictionary = v._check_timeline(record, frames, 8000)
	t.check_eq(r["problems"].size(), 1, "报出一处")
	t.check(str(r["problems"][0]).contains("倒退"), "指出倒退")
	t.finish("单调性被守住")


func _test_11_events_count_mismatch_caught(t: Variant) -> void:
	t.begin("检测器：少派发一条事件会被报出")
	var v: Variant = CReplayVerifierScript.new()
	var record: Variant = _clean()
	var dispatched: Array = v._walk(record, 17)["dispatched"]
	dispatched.pop_back()
	var r: Dictionary = v._check_events(record, dispatched, 17)
	t.check(r["problems"].size() >= 1, "报出问题")
	t.check(str(r["problems"][0]).contains("不一致"), "指出数量不一致")
	t.finish("漏派发被抓住")


func _test_12_event_time_rewritten_caught(t: Variant) -> void:
	t.begin("检测器：事件时刻被改写会被报出")
	var v: Variant = CReplayVerifierScript.new()
	var record: Variant = _clean()
	var dispatched: Array = v._walk(record, 17)["dispatched"]
	var idx: int = 3
	var original: Variant = record.events[idx]
	# 换一条「同一事件、时刻被改」的副本：模拟回放改写了记录的时刻
	var tampered: Variant = CTimedEventScript.new(
		int(original.time_ms) + 500, original.kind, original.object_id,
		original.cue_id, original.payload.duplicate(true))
	tampered.seq = int(original.seq)
	dispatched[idx] = {"ev": tampered, "at_ms": int(original.time_ms) + 500}
	var r: Dictionary = v._check_events(record, dispatched, 17)
	var joined: String = "\n".join(r["problems"])
	t.check(joined.contains("time_ms 被改写"), "指出时刻被改写")
	t.finish("时刻篡改被抓住")


func _test_13_event_dispatched_early_caught(t: Variant) -> void:
	t.begin("检测器：事件被提前派发会被报出")
	var v: Variant = CReplayVerifierScript.new()
	var record: Variant = _clean()
	var dispatched: Array = v._walk(record, 17)["dispatched"]
	var idx: int = 3
	dispatched[idx]["at_ms"] = int(record.events[idx].time_ms) - 5
	var r: Dictionary = v._check_events(record, dispatched, 17)
	var joined: String = "\n".join(r["problems"])
	t.check(joined.contains("提前派发"), "指出提前派发")
	t.finish("提前触发被抓住")


func _test_14_event_dispatched_late_caught(t: Variant) -> void:
	t.begin("检测器：事件派发滞后超过一个步长会被报出")
	var v: Variant = CReplayVerifierScript.new()
	var record: Variant = _clean()
	var dispatched: Array = v._walk(record, 17)["dispatched"]
	var idx: int = 3
	dispatched[idx]["at_ms"] = int(record.events[idx].time_ms) + 100
	var r: Dictionary = v._check_events(record, dispatched, 17)
	var joined: String = "\n".join(r["problems"])
	t.check(joined.contains("滞后"), "指出滞后")
	t.finish("滞后被抓住")


func _test_15_canned_animation_caught_by_order(t: Variant) -> void:
	t.begin("检测器：用预制动画代替记录会被报出")
	var v: Variant = CReplayVerifierScript.new()
	var record: Variant = _clean()
	# 造一份「无视记录、姿态恒定」的帧序列：正是预制动画的特征
	var canned: Array = _frames_with_discrete_constants(record)
	var r: Dictionary = v._check_discrete_order(record, canned, 17)
	t.check(r["problems"].size() >= 1, "报出问题")
	t.check(str(r["problems"][0]).contains("条数不一致"), "指出跳变条数不一致")
	t.finish("预制动画被抓住")


func _test_16_swapped_discrete_order_caught(t: Variant) -> void:
	t.begin("检测器：换头与挂起顺序被颠倒会被报出")
	var v: Variant = CReplayVerifierScript.new()
	var record: Variant = _clean()
	# 记录里是「先换头(5000ms)后挂起(5200ms)」；把两者阈值对调，模拟顺序被压平
	var swapped: Array = _frames_with_swapped_discrete(record)
	var r: Dictionary = v._check_discrete_order(record, swapped, 17)
	t.check(r["problems"].size() >= 1, "报出问题")
	t.check(str(r["problems"][0]).contains("不一致"), "指出跳变不一致")
	t.finish("顺序颠倒被抓住")


func _test_17_puppet_mismatch_detected(t: Variant) -> void:
	t.begin("检测器：影人离散量不符会被逐字段抓出")
	var v: Variant = CReplayVerifierScript.new()
	var want: Dictionary = {
		"head_id": 3, "hook_slot": 0, "stance": 0.0, "facing": 1.0,
		"turn_progress": 1.0, "stage_pos": {"x": 0.2, "y": 0.0},
		"hand_angle": {"left": -0.5, "right": 0.45}, "is_controlled": true,
	}
	var got: Dictionary = want.duplicate(true)
	got["head_id"] = 4
	var problems: Array = []
	var n: int = v._diff_puppet(1234, 0, want, got, problems)
	t.check_eq(n, 1, "只报一处")
	t.check_eq(problems.size(), 1, "问题列表一条")
	t.check(str(problems[0]).contains("head_id"), "指出是 head_id")
	t.check(str(problems[0]).contains("离散量必须精确相等"), "点明离散量不容差")
	t.finish("换错头会被抓住")


func _test_18_lamp_mismatch_detected(t: Variant) -> void:
	t.begin("检测器：灯态不符会被抓出")
	var v: Variant = CReplayVerifierScript.new()
	var want: Dictionary = {"distance": 0.5, "exposure": 0.5, "oil": 0.8, "flame_feedback": 0.5}
	var got: Dictionary = want.duplicate(true)
	got["distance"] = 0.2
	var problems: Array = []
	var n: int = v._diff_lamp(900, want, got, problems)
	t.check_eq(n, 1, "只报一处")
	t.check(str(problems[0]).contains("lamp.distance"), "指出是哪一项灯态")
	t.finish("灯态差异会被抓住")


func _test_19_expected_ending_boundaries(t: Variant) -> void:
	t.begin("结局判定：阈值两侧与关卡分支")
	var v: Variant = CReplayVerifierScript.new()
	t.check_eq(v._expected_ending(1, 3), &"", "非最终关无结局")
	t.check_eq(v._expected_ending(5, 0), CResultFlowScript.ENDING_PLAYED_OUT, "0 段=戏散了")
	t.check_eq(v._expected_ending(5, 1), CResultFlowScript.ENDING_PLAYED_OUT, "1 段=戏散了")
	t.check_eq(v._expected_ending(5, 2), CResultFlowScript.ENDING_CURTAIN_CALL, "2 段=满堂彩")
	t.check_eq(v._expected_ending(5, 3), CResultFlowScript.ENDING_CURTAIN_CALL, "3 段=满堂彩")
	t.check_eq(int(CResultFlowScript.APPLAUSE_THRESHOLD), 2, "阈值取自 CResultFlow 常量")
	t.finish("两档边界正确")


func _test_20_report_renders(t: Variant) -> void:
	t.begin("报告可读且含结论")
	var v: Variant = CReplayVerifierScript.new()
	var text: String = v.describe_report(v.verify(_clean(5, true)))
	t.check(text.contains("回放验收"), "含标题")
	t.check(text.contains("结论：通过"), "含通过结论")
	t.check(text.contains("采样保真"), "列出各项检查")
	var bad: String = v.describe_report(v.verify(_tampered_seq()))
	t.check(bad.contains("结论：未通过"), "不通过时明确写出")
	t.finish("报告可读")


func _test_21_mock_discrete_transitions_exactly_two(t: Variant) -> void:
	t.begin("模拟演出：换头与挂起各跳变一次并保持")
	var v: Variant = CReplayVerifierScript.new()
	var record: Variant = _clean()
	var tokens: Array = v._discrete_tokens(_pairs_of(record))
	# 各一次：head 与 hook 都只在发生的那一刻跳一下，之后保持到演出结束。
	# 若分段实现把归属在各段分支里重算，头与钩会中途掉回 -1 再设回来，
	# 这里就会数出 4 或 6 次——那正是本用例要守住的回归。
	t.check_eq(tokens.size(), 2, "恰好两次离散跳变")
	t.check_eq(str(tokens[0]["key"]), "p0.head=3", "先换头")
	t.check_eq(str(tokens[1]["key"]), "p0.hook=0", "后挂起")
	t.check(int(tokens[0]["t"]) < int(tokens[1]["t"]), "换头早于挂起")
	var last: Variant = record.snapshots[-1]
	t.check_eq(int(last.puppets[0].head_id), 3, "末帧仍带着换过的头")
	t.check_eq(int(last.puppets[0].hook_slot), 0, "末帧仍挂在槽位 0")
	t.finish("归属保持到结束")


## 把记录的快照整理成 _discrete_tokens 需要的 [time_ms, puppets] 序列。
func _pairs_of(p_record: Variant) -> Array:
	var out: Array = []
	for snap in p_record.snapshots:
		out.append([int(snap.time_ms), snap.puppets])
	return out


## ---------------------------------------------------------------- 构造辅助


## 一份「无视记录」的帧序列：离散量恒定。预制动画的典型特征。
func _frames_with_discrete_constants(p_record: Variant) -> Array:
	var out: Array = []
	for snap in p_record.snapshots:
		var puppets: Array = []
		for p in snap.puppets:
			var copy: Dictionary = (p as Dictionary).duplicate(true)
			copy["head_id"] = -1
			copy["hook_slot"] = -1
			puppets.append(copy)
		out.append({"now_ms": int(snap.time_ms), "puppets": puppets})
	return out


## 帧序列：把「先换头后挂起」对调成「先挂起后换头」。
func _frames_with_swapped_discrete(p_record: Variant) -> Array:
	var out: Array = []
	for snap in p_record.snapshots:
		var t: int = int(snap.time_ms)
		var puppets: Array = []
		for i in snap.puppets.size():
			var copy: Dictionary = (snap.puppets[i] as Dictionary).duplicate(true)
			if i == 0:
				# 阈值对调：挂钩先到位（5000ms），头后换（5200ms）
				copy["hook_slot"] = 0 if t >= 5000 else -1
				copy["head_id"] = 3 if t >= 5200 else -1
			puppets.append(copy)
		out.append({"now_ms": t, "puppets": puppets})
	return out


func _tampered_seq() -> Variant:
	var record: Variant = _clean()
	record.events.remove_at(3)
	return record
