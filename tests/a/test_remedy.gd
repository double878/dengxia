extends RefCounted
class_name TestRemedy
## 切片 4 的行为测试：8 秒补救与按时结束。
## 覆盖 7 个场景：正常、错拍、漏做、补做、超时、临近结尾、暂停恢复。

const ATestBaseScript := preload("res://tests/a/a_test_base.gd")
const BenchScript := preload("res://tests/a/director_test_bench.gd")
const StageDefScript := preload("res://scripts/a/stage_def.gd")
const CueScript := preload("res://scripts/a/cue.gd")
const RemedySystemScript := preload("res://scripts/a/remedy_system.gd")
const StageDirectorScript := preload("res://scripts/a/stage_director.gd")

const STAND_BEAT_MS: int = 2500          ## l1_c1_stand 的落点
const WINDOW_MS: int = 8000


func _bench(custom: StageDef = null) -> DirectorTestBench:
	return BenchScript.new(custom)


func run_all() -> Dictionary:
	var t: ATestBase = ATestBaseScript.new()
	_test_01_normal_run_no_remedy(t)
	_test_01b_all_hits_no_remedy(t)
	_test_02_miss_triggers_remedy(t)
	_test_02b_earlier_window_still_open(t)
	_test_03_out_of_sync_action_still_happens(t)
	_test_04_make_up_in_window_keeps_failure(t)
	_test_05_timeout_keeps_show_going(t)
	_test_06_no_reopen_for_same_cue(t)
	_test_07_pause_freezes_countdown(t)
	_test_08_stage_ends_on_time(t)
	_test_09_window_at_stage_end(t)
	_test_10_single_demo_and_separate_records(t)
	_test_11_low_sync_triggers_remedy(t)
	_test_12_invalid_input_robustness(t)
	return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed,
		"failures": t.failures}


func _test_01_normal_run_no_remedy(t: ATestBase) -> void:
	t.begin("01 空场跑完：未做动作全部记为未命中并触发补救，关卡仍按时结束")
	var b: DirectorTestBench = _bench()
	b.advance_to(40000)                 # 什么都不做也要能跑到结束
	t.check(b.director.is_over(), "到 35 秒应已结束")
	t.check_eq(b.director.end_reason, StageDirectorScript.END_REASON_DURATION, "结束原因为到时")
	t.check(b.has_event("stage_start"), "应发出 stage_start")
	t.check(b.has_event("stage_end"), "应发出 stage_end")
	t.check(b.director_log.size() > 0, "应有事件产生")
	t.check_eq(int(b.director.song_time_ms()) >= 35000, true,
		"结束时歌曲时间应不少于 35 秒（实际 %d）" % b.director.song_time_ms())
	# 什么都不做 = 每条关键动作都漏做，因此应逐条触发补救
	var missed: int = b.director.performance.missed_outright_cue_ids().size()
	t.check_eq(missed, b.stage_def.cues.size(),
		"未做的关键动作应全部记为「完全没做」（%d / %d）" % [missed, b.stage_def.cues.size()])
	t.check(b.events_of("remedy_open").size() >= 1, "漏做应触发补救")
	t.finish("空场跑完 35 秒按时结束，未做动作全部记为未命中并各自开窗")


## 正常演出：关键动作都在容差内做到时，**不产生任何补救窗口**。
## 这是唯一一条验证「做对了就没有补救」的正向测试；空场跑完的 01 验证的是相反情况。
## 顺序按第一关关键动作表的落点排列，每条动作都落在自己的容差窗内。
func _test_01b_all_hits_no_remedy(t: ATestBase) -> void:
	t.begin("01b 正常演出：六条关键动作都在容差内做到，全程无补救")
	var b: DirectorTestBench = _bench()

	# 1200 ms 蹲下、2450 ms 站起（先蹲再起，站起才是一次真实的姿势切换）
	b.advance_to(1200)
	b.begin_drag()
	b.drag(Vector2(0.0, 130.0), 24)          # 蹲到底
	b.end_drag()
	b.advance_to(2450)
	b.begin_drag()
	b.drag(Vector2(0.0, -100.0), 20)         # 站起
	b.end_drag()

	# 4950 ms 向左移动、8700 ms 抬手、12450 ms 向右移动、14950 ms 回到中位
	b.advance_to(4950)
	b.begin_drag()
	b.drag(Vector2(-380.0, 0.0), 22)
	b.end_drag()
	b.advance_to(8700)
	b.advance(25, {"left_raise": true})
	b.advance_to(12450)
	b.begin_drag()
	b.drag(Vector2(1100.0, 0.0), 30)
	b.end_drag()
	b.advance_to(14700)
	b.begin_drag()
	# 从右端回到中位：目标带只有 0.47-0.53 这么窄（且为闭区间），单帧位移必须远小于
	# 带宽，否则会一帧跨过整条带（0.53 → 0.06）而不留下任何「进入范围」的帧。
	b.drag(Vector2(-20.0, 0.0), 60)
	b.end_drag()

	# 逐条核对：每条关键动作都应命中
	for cue in b.stage_def.cues:
		var cue_id: String = str(cue["cue_id"])
		var outcome: Dictionary = b.director.performance.get_outcome(cue_id)
		t.check_eq(bool(outcome.get("hit", false)), true,
			"「%s」应在容差内命中（实际 offset=%s，stance/x/angle 见下）"
				% [cue_id, str(outcome.get("offset_ms", "无判定"))])
	t.check_eq(b.director.performance.missed_outright_cue_ids().size(), 0,
		"做对的动作不应被记为「完全没做」")
	t.check_eq(b.events_of("remedy_open").size(), 0, "全部做对时不应开出任何补救窗口")
	t.check_eq(b.events_of("remedy_show").size(), 0, "不应出现任何示范提示")
	t.check(b.director.remedy.get_records().is_empty(), "不应留下任何失误记录")

	b.advance_to(40000)
	t.check(b.director.is_over(), "正常演出仍应按时结束")
	t.check_eq(b.events_of("stage_end").size(), 1, "应只结束一次")
	t.finish("六条关键动作全部命中，全程没有补救窗口与失误记录")


func _test_02_miss_triggers_remedy(t: ATestBase) -> void:
	t.begin("02 漏做：落点过后立刻开出 8 秒窗口，原失误记为「完全没做」")
	var b: DirectorTestBench = _bench()
	b.advance_to(STAND_BEAT_MS + 260)
	t.check(not b.director.performance.has_outcome("l1_c1_stand")
		or bool(b.director.performance.get_outcome("l1_c1_stand").get("hit", false)) == false,
		"此时站起尚未命中")
	t.check(b.director.remedy.is_open("l1_c1_stand"),
		"落点 + 容差刚过就应开出补救窗口")
	var window: Dictionary = b.director.remedy.get_window("l1_c1_stand")
	t.check_eq(int(window["started_ms"]), STAND_BEAT_MS + 260,
		"窗口从落点+容差那一帧开始（实际 %d）" % int(window["started_ms"]))
	t.check_eq(b.director.remedy.remaining_ms("l1_c1_stand", b.time_ms), WINDOW_MS,
		"窗口长度应为 8 秒")
	t.check_eq(str(window["reason"]), RemedySystemScript.REASON_MISSED, "开窗原因为错过落点")
	t.check(b.has_event("remedy_open", "l1_c1_stand"), "应发出 remedy_open")
	# 站起落点之前 1.25 s 的蹲下落点同样漏做，因此此刻蹲下窗口也开着；
	# 「同屏只展示一个示范」由 02b 单独验证，本测试只确认站起窗口本身开对了。
	t.check(b.has_event("remedy_show"), "应发出 remedy_show")


## 更早的落点先漏做时，先开的窗口仍在 8 秒内，此时同屏只能展示一个示范。
## 这条与 02 分开，是为了让「同屏唯一示范」的优先级在两条窗口并存时才被检验：
## 02 只验证漏做触发窗口，本测试验证多条窗口并存时示范仍唯一且按最早到期选。
func _test_02b_earlier_window_still_open(t: ATestBase) -> void:
	t.begin("02b 多条窗口并存时，同屏仍只有一个示范（最早到期者）")
	var b: DirectorTestBench = _bench()
	# 蹲下落点（1250 ms）漏做后先开出窗口，站起落点（2500 ms）随后也漏做
	b.advance_to(STAND_BEAT_MS + 260)
	var open_ids: Array[String] = []
	for cue_id in b.director.remedy.windows.keys():
		open_ids.append(str(cue_id))
	t.check_eq(open_ids.size(), 2, "此时应有两个错误各自开着窗口（实际 %s）"
		% ", ".join(open_ids))
	t.check(b.director.remedy.is_open("l1_c0_crouch"), "先漏做的蹲下窗口应仍开着")
	t.check(b.director.remedy.is_open("l1_c1_stand"), "站起窗口也应开着")
	t.check(b.director.remedy.current_demo_cue_id != "", "应有当前示范")
	t.check(b.director.remedy.current_demo_cue_id == "l1_c0_crouch"
		or b.director.remedy.current_demo_cue_id == "l1_c1_stand",
		"当前示范必须是开着的窗口之一（实际 %s）" % b.director.remedy.current_demo_cue_id)
	t.check_eq(b.director.remedy.current_demo_cue_id, _earliest_deadline_id(b),
		"当前示范应是开着窗口里最早到期的那一个")
	var shows: Array = b.events_of("remedy_show")
	t.check(shows.size() >= 1, "应发出 remedy_show")
	t.check_eq(str(shows[shows.size() - 1]["cue_id"]),
		b.director.remedy.current_demo_cue_id, "最后一条示范事件应指向当前示范")
	t.finish("多个错误各自开窗，同屏只示范最早到期的一个")
	var outcome: Dictionary = b.director.performance.get_outcome("l1_c1_stand")
	t.check_eq(bool(outcome.get("missed_outright", false)), true, "应标记为完全没做")
	t.finish("漏做触发 8 秒窗口，原因与起始时刻可核对")


func _test_03_out_of_sync_action_still_happens(t: ATestBase) -> void:
	t.begin("03 错拍：动作照常发生、只记未命中，仍会触发补救")
	var b: DirectorTestBench = _bench()
	var stand_cue: Dictionary = b.find_cue("l1_c1_stand")
	b.crouch(1000)
	# 落点前 2100 ms 就开始快速站起，跨过阈值时明显早于容差
	b.advance_to(int(stand_cue["beat_time_ms"]) - 2100)
	b.stand_up(15.0, 69)
	var outcome: Dictionary = b.director.performance.get_outcome("l1_c1_stand")
	t.check(b.director.performance.has_outcome("l1_c1_stand"), "应产生判定结果")
	t.check_eq(bool(outcome.get("hit", true)), false,
		"错拍站起应记为未命中（offset=%d ms）" % int(outcome.get("offset_ms", 0)))
	t.check_eq(bool(outcome.get("missed_outright", false)), false,
		"错拍做了不算「完全没做」")
	t.check(b.state().stance <= 0.05,
		"错拍时姿势照常到位（stance=%.4f）" % b.state().stance)
	t.check(b.has_event("cue_fire", "l1_c1_stand"), "仍应发出 cue_fire")
	t.check(not b.director.remedy.is_open("l1_c1_stand"),
		"错拍做了不重复开补救窗口（该错误已记录）")
	t.finish("错拍动作照常发生、记为未命中，不重复开窗")


func _test_04_make_up_in_window_keeps_failure(t: ATestBase) -> void:
	t.begin("04 补做：窗口内完成动作关闭提示，但原失误仍保留在记录里")
	var b: DirectorTestBench = _bench()
	b.advance_to(STAND_BEAT_MS + 260)
	t.check(b.director.remedy.is_open("l1_c1_stand"), "应已开出窗口")

	# 窗口内补做：从站姿蹲下再站起太绕，这里直接做出「站起」要求的姿势变化：
	# 先蹲下（满足蹲下，不影响站起窗口），再站起到完全站姿。
	b.begin_drag()
	b.drag(Vector2(0.0, 120.0), 12)          # 蹲下
	b.end_drag()
	b.advance(5)
	t.check(b.director.remedy.is_open("l1_c1_stand"), "只蹲下还不算补做站起，窗口应仍开着")
	b.stand_up(8.0, 130)

	t.check(not b.director.remedy.is_open("l1_c1_stand"), "补做成功后窗口应关闭")
	t.check(b.has_event("remedy_success", "l1_c1_stand"), "应发出 remedy_success")
	var success: Dictionary = {}
	for e in b.events_for("remedy_success", "l1_c1_stand"):
		success = e
	t.check_eq(bool(success["payload"]["still_missed"]), true,
		"补救成功不抹去原失误（still_missed 应为 true）")
	var record: Dictionary = {}
	for r in b.director.remedy.get_records():
		if str(r.get("cue_id", "")) == "l1_c1_stand":
			record = r
	t.check(not record.is_empty(), "记录里应留有这次失误")
	t.check_eq(bool(record.get("missed", false)), true, "记录里的失误标记应保留")
	t.check_eq(str(record.get("close_reason", "")), RemedySystemScript.CLOSE_SUCCESS,
		"记录的关窗原因为补救成功")
	t.check_eq(bool(b.director.performance.get_outcome("l1_c1_stand").get("hit", true)), false,
		"原判定结果仍是未命中")
	t.finish("窗口内补做成功关窗，原失误与记录都保留")


func _test_05_timeout_keeps_show_going(t: ATestBase) -> void:
	t.begin("05 超时：8 秒到期仍不补做，记录未完成并继续演出")
	var b: DirectorTestBench = _bench()
	b.advance_to(STAND_BEAT_MS + 260)
	var start_ms: int = b.time_ms
	t.check(b.director.remedy.is_open("l1_c1_stand"), "应已开出窗口")

	b.advance_to(start_ms + WINDOW_MS - 10)
	t.check(b.director.remedy.is_open("l1_c1_stand"), "不到 8 秒窗口应仍开着")
	b.advance(2)                          # 跨过 8 秒
	t.check(not b.director.remedy.is_open("l1_c1_stand"), "8 秒到期后窗口应关闭")
	t.check(b.has_event("remedy_timeout", "l1_c1_stand"), "应发出 remedy_timeout")
	t.check(b.has_event("remedy_hide", "l1_c1_stand"), "应结束当前示范")
	t.check(not b.director.is_over(), "一次补救超时不结束关卡，演出继续")
	t.check(b.director.song_time_ms() < 35000, "此时远未到 35 秒")

	# 继续跑到结束，确认演出没有被打断
	b.advance_to(40000)
	t.check(b.director.is_over(), "后续仍按时结束")
	t.check_eq(b.director.end_reason, StageDirectorScript.END_REASON_DURATION, "结束原因为到时")
	var timeout: Dictionary = {}
	for e in b.events_for("remedy_timeout", "l1_c1_stand"):
		timeout = e
	t.check(int(timeout["payload"]["elapsed_ms"]) >= WINDOW_MS,
		"超时事件应记录已耗时（%d ms）" % int(timeout["payload"]["elapsed_ms"]))
	t.finish("超时记录未完成、示范结束、演出继续并按时收尾")


func _test_06_no_reopen_for_same_cue(t: ATestBase) -> void:
	t.begin("06 同一 cue_id 不能重复触发或重置自己的窗口")
	var b: DirectorTestBench = _bench()
	b.advance_to(STAND_BEAT_MS + 260)
	var window: Dictionary = b.director.remedy.get_window("l1_c1_stand")
	var deadline: int = int(window["deadline_ms"])
	var opened_count: int = b.director.remedy.open_count()

	# 反复尝试对同一条 cue 开窗，应全部被拒绝
	var accepted: int = 0
	for _i in 20:
		if b.director.remedy.open("l1_c1_stand", RemedySystemScript.REASON_MISSED, b.time_ms):
			accepted += 1
	t.check_eq(accepted, 0, "重复 open 应全部被拒绝")
	t.check_eq(b.director.remedy.open_count(), opened_count, "窗口数量不应增加")
	var after: Dictionary = b.director.remedy.get_window("l1_c1_stand")
	t.check_eq(int(after["deadline_ms"]), deadline, "原窗口的截止时刻不应被重置")
	b.advance_to(deadline + 20)
	t.check(not b.director.remedy.is_open("l1_c1_stand"), "到期后关闭，而不是被刷新")
	t.check_eq(b.events_for("remedy_open", "l1_c1_stand").size(), 1,
		"整场只应产出一次 remedy_open")
	t.finish("同一错误不刷窗口，截止时刻不被重置")


func _test_07_pause_freezes_countdown(t: ATestBase) -> void:
	t.begin("07 暂停恢复：倒计时与演出时间一起冻结，恢复后继续")
	var b: DirectorTestBench = _bench()
	b.advance_to(STAND_BEAT_MS + 260)
	t.check(b.director.remedy.is_open("l1_c1_stand"), "应已开出窗口")
	var remaining_before: int = b.director.remedy.remaining_ms("l1_c1_stand", b.time_ms)
	var song_before: int = b.director.song_time_ms()

	b.set_paused(true)
	b.advance(600)                        # 冻结期间推进 600 帧（6 秒）
	t.check_eq(b.director.song_time_ms(), song_before, "暂停期间歌曲时间应冻结")
	t.check(b.director.remedy.is_open("l1_c1_stand"), "暂停期间窗口应仍开着")
	t.check_eq(b.director.remedy.remaining_ms("l1_c1_stand", b.director.song_time_ms()),
		remaining_before, "暂停期间剩余时间不应减少")

	b.set_paused(false)
	b.advance(50)                         # 恢复后推进 500 ms
	t.check(b.director.song_time_ms() > song_before, "恢复后歌曲时间继续推进")
	t.check(b.director.remedy.is_open("l1_c1_stand"), "恢复 500 ms 后窗口仍应开着")
	t.check_eq(b.director.remedy.remaining_ms("l1_c1_stand", b.director.song_time_ms()),
		remaining_before - 500, "恢复后剩余时间应继续从冻结值递减")
	b.advance_to(song_before + remaining_before + 100)
	t.check(not b.director.remedy.is_open("l1_c1_stand"), "补足原定 8 秒后应超时关闭")
	t.finish("暂停同时冻结演出时间、倒计时与判定；恢复后不跳变")


func _test_08_stage_ends_on_time(t: ATestBase) -> void:
	t.begin("08 到时结束：35 秒一到就结束，不延长、不重播")
	var b: DirectorTestBench = _bench()
	b.advance_to(34990)
	t.check(not b.director.is_over(), "34990 ms 时不应已结束")
	b.advance(2)
	t.check(b.director.is_over(), "跨过 35000 ms 后应结束")
	t.check_eq(b.director.end_reason, StageDirectorScript.END_REASON_DURATION, "结束原因为到时")
	t.check_in_range(float(b.director.song_time_ms()), 35000.0, 35010.0,
		"结束时歌曲时间应恰好到达 35 秒（实际 %d）" % b.director.song_time_ms())
	var end_event: Dictionary = {}
	for e in b.events_of("stage_end"):
		end_event = e
	t.check_eq(int(end_event["payload"]["duration_ms"]), 35000, "结束事件记录关卡固定时长")
	t.check_eq(b.events_of("stage_start").size(), 1, "整场只开始一次")
	t.check_eq(b.events_of("stage_end").size(), 1, "整场只结束一次")
	var frames_after_end: int = b.time_ms
	b.advance(200)
	t.check_eq(b.time_ms, frames_after_end, "结束后不应再产生任何推进")
	t.finish("关卡在 35 秒整点结束，不延长、不重播")


func _test_09_window_at_stage_end(t: ATestBase) -> void:
	t.begin("09 临近结尾：窗口跨过 35 秒时随结束关闭，不延长关卡")
	# 造一条落点在 34 s 的 cue，窗口会跨过 35 秒
	var def: StageDef = StageDefScript.make_level1()
	var late_cue: Dictionary = CueScript.make("l1_c_late", 34000, CueScript.ACTION_HAND_RAISE, 0,
		{"key": "angle", "min": 0.5, "max": 0.6}, 250, "hand_raise")
	late_cue["segment"] = "收势"
	def.cues.append(late_cue)
	t.check_eq(def.validate().size(), 0, "含 34 s 落点的数据应通过校验")

	var b: DirectorTestBench = _bench(def)
	b.advance_to(34300)
	t.check(b.director.remedy.is_open("l1_c_late"), "34 s 落点漏做后应开出窗口")
	t.check(b.director.remedy.remaining_ms("l1_c_late", b.time_ms) > 5000,
		"窗口本应跨过 35 秒（剩余 %d ms）"
		% b.director.remedy.remaining_ms("l1_c_late", b.time_ms))

	b.advance_to(40000)
	t.check(b.director.is_over(), "关卡应按时结束")
	t.check_eq(b.director.song_time_ms(), 35000, "结束时歌曲时间应恰为 35000 ms")
	t.check(not b.director.remedy.is_open("l1_c_late"), "未到期的窗口应随演出结束关闭")
	var timeout: Dictionary = {}
	for e in b.events_for("remedy_timeout", "l1_c_late"):
		timeout = e
	t.check(not timeout.is_empty(), "随结束关闭也要留记录")
	t.check_eq(str(timeout["payload"].get("reason", "")), RemedySystemScript.CLOSE_STAGE_END,
		"关窗原因应为 stage_end")
	var end_event: Dictionary = {}
	for e in b.events_of("stage_end"):
		end_event = e
	t.check_eq(int(end_event["payload"]["remedy_open_count"]), 1,
		"结束时应报告仍有 1 个窗口未到期")
	t.finish("跨过结尾的窗口随演出关闭并留记录，关卡时长不被延长")


func _test_10_single_demo_and_separate_records(t: ATestBase) -> void:
	t.begin("10 同屏只选一个当前示范，不同错误各自留记录")
	var b: DirectorTestBench = _bench()
	# 错过站起后不再做任何动作，会连续错过后续落点
	b.advance_to(9000)
	var open_ids: Array[String] = []
	for cue_id in b.director.remedy.windows.keys():
		open_ids.append(str(cue_id))
	t.check(open_ids.size() >= 2, "此时应有多个错误各自开出窗口（实际 %d 个：%s）"
		% [open_ids.size(), ", ".join(open_ids)])
	t.check(b.director.remedy.current_demo_cue_id != "", "应有当前示范")
	t.check_eq(b.director.remedy.current_demo_cue_id, _earliest_deadline_id(b),
		"当前示范应是所有开着窗口里最早到期的那一个")
	var show_events: int = b.events_of("remedy_show").size()
	t.check(show_events >= 1, "应发出 remedy_show")
	t.check_eq(b.director.remedy.get_records().size(), open_ids.size(),
		"每个错误各自留一条记录")

	# 让最早的那条超时，示范应切换到下一条
	b.advance_to(b.time_ms + 300)
	var still_open: Array[String] = []
	for cue_id in b.director.remedy.windows.keys():
		still_open.append(str(cue_id))
	t.check(still_open.size() >= 1, "仍应有窗口开着")
	t.check(b.director.remedy.current_demo_cue_id != "",
		"示范应切换到下一个未结束的窗口")
	t.check(still_open.has(b.director.remedy.current_demo_cue_id),
		"当前示范必须是仍开着的窗口之一")
	t.check_eq(b.director.remedy.current_demo_cue_id, _earliest_deadline_id(b),
		"示范切换后仍应是开着窗口里最早到期的那一个")
	t.finish("多个错误各自留记录，同屏只展示一个当前示范")


## 合拍度跌破警戒线时同样触发补救（PRD 第 5.1、5.2.1 节）。
##
## 需要额外一条落点才能把这条路径与「漏做」路径分开：漏做路径会为段内每条漏做的
## cue 开窗，而低合拍补救开的是段内「既未判定、也未开窗」的下一个落点。没有这条
## 额外落点时，低合拍检查会因为段内已无可用落点而静默跳过，本路径就永远不被执行。
## 额外落点也是合理的演出调度：本段已经整段失准，师父示范接下来该做的动作。
##
## 触发靠一次方向相反的拖动：玩家向左移动，会在移步段里留下「未命中」的判定，
## 使该段合拍度跌到 0.0；同时这一刻向后「扫」到的落点也不再剩下可示范的对象。
func _test_11_low_sync_triggers_remedy(t: ATestBase) -> void:
	t.begin("11 低合拍：段内合拍度跌破警戒线也触发补救，理由与漏做分开")
	var def: StageDef = StageDefScript.make_level1()
	var next_cue: Dictionary = CueScript.make("l1_c_slide", def.beat_ms(18),
		CueScript.ACTION_MOVE_LEFT, 0, {"key": "x", "min": 0.0, "max": 0.35}, 250, "move_left")
	next_cue["segment"] = "移步"
	def.cues.append(next_cue)
	t.check_eq(def.validate().size(), 0, "追加落点后的数据应通过校验")

	var b: DirectorTestBench = _bench(def)
	# 只漏做蹲下与站起，让这两条先各自开出「漏做」窗口
	b.advance_to(STAND_BEAT_MS + 260)
	t.check_eq(b.director.remedy.records.size(), 2,
		"此时应有蹲下、站起两条漏做记录（实际 %d）" % b.director.remedy.records.size())

	# 向左拖动：移步段的判定全部未命中，合拍度跌破警戒线
	b.begin_drag()
	b.drag(Vector2(-110.0, 0.0), 5)
	b.end_drag()
	b.advance(5)
	t.check_eq(b.director.performance.segment_graded_count("移步") >= 2, true,
		"移步段应已有至少两条判定供合拍度汇总")
	t.check_eq(b.director.performance.segment_score("移步") < b.director.remedy.sync_threshold,
		true, "移步段合拍度应已跌破警戒线（实际 %.3f）"
			% b.director.performance.segment_score("移步"))

	var low_sync_events: Array = []
	for e in b.events_of("remedy_open"):
		var event: Dictionary = e
		var payload: Dictionary = event["payload"]
		if str(payload.get("reason", "")) == RemedySystemScript.REASON_LOW_SYNC:
			low_sync_events.append(event)
	t.check_eq(low_sync_events.size(), 1, "跌破警戒线后应开出恰好一个低合拍窗口（实际 %d）"
		% low_sync_events.size())
	var low_sync_id: String = ""
	if low_sync_events.size() == 1:
		var low_event: Dictionary = low_sync_events[0]
		low_sync_id = str(low_event["cue_id"])
		t.check(not low_sync_id.is_empty(), "低合拍窗口应挂在一条具体落点上")
		t.check(b.director.remedy.is_open(low_sync_id), "该低合拍窗口应开着")
		t.check(not b.director.performance.has_outcome(low_sync_id),
			"低合拍示范应指向段内还没做过的落点「%s」" % low_sync_id)
	# 低合拍补救每段只开一次，不能反复刷窗口
	var before_more: int = _count_low_sync_opens(b)
	b.advance(30)
	t.check_eq(_count_low_sync_opens(b), before_more, "低合拍补救每段只开一次，不反复刷窗口")
	# 窗口内按示范补做该落点要求的动作，低合拍窗口应关闭，而原失误仍保留。
	# 方向必须跟着示范走：示范指向段内尚未做过的落点，玩家照做才算补救成功。
	var demo_action: String = str(b.find_cue(low_sync_id).get("action", ""))
	var drag_sign: float = -1.0 if demo_action == CueScript.ACTION_MOVE_LEFT else 1.0
	b.begin_drag()
	b.drag(Vector2(520.0 * drag_sign, 0.0), 25)
	b.end_drag()
	t.check(b.director.performance.has_outcome(low_sync_id),
		"补做后该落点应产生新的判定（示范动作 %s，实际 x=%.4f）"
			% [demo_action, b.state().stage_pos.x])
	t.check(not b.director.remedy.is_open(low_sync_id),
		"补做示范动作 %s 后低合拍窗口应关闭" % demo_action)
	var success: Dictionary = {}
	for e in b.events_of("remedy_success"):
		var event: Dictionary = e
		if str(event["cue_id"]) == low_sync_id:
			success = event
	t.check(not success.is_empty(), "补做后应发出 remedy_success（%s）" % low_sync_id)
	if not success.is_empty():
		var payload: Dictionary = success["payload"]
		t.check_eq(bool(payload.get("still_missed", false)), true,
			"合拍度已经跌破，补救成功也不抹去原失误")
	t.check(not b.director.remedy.is_open(low_sync_id), "补做后低合拍窗口应关闭")
	var record: Dictionary = {}
	for r in b.director.remedy.get_records():
		var record_entry: Dictionary = r
		if str(record_entry.get("cue_id", "")) == low_sync_id:
			record = record_entry
	t.check(not record.is_empty(), "低合拍补救也应留记录")
	t.check_eq(str(record.get("reason", "")), RemedySystemScript.REASON_LOW_SYNC,
		"记录里的开窗理由应为低合拍")
	t.finish("低合拍段触发补救、可补做成功，理由与漏做分开且原失误保留")


## 当前所有开着窗口里最早到期的那一个——同屏唯一示范的优先级规则。
## 按「最早到期」计算而不是按字典迭代顺序，避免断言依赖窗口的插入次序。
func _earliest_deadline_id(b: DirectorTestBench) -> String:
	var best_id: String = ""
	var best_deadline: int = 1 << 62
	for cue_id in b.director.remedy.windows.keys():
		var deadline: int = int(b.director.remedy.windows[cue_id]["deadline_ms"])
		if deadline < best_deadline:
			best_deadline = deadline
			best_id = str(cue_id)
	return best_id


## 到目前为止以「低合拍」为理由开出的窗口数量。
func _count_low_sync_opens(b: DirectorTestBench) -> int:
	var count: int = 0
	for e in b.events_of("remedy_open"):
		var event: Dictionary = e
		var payload: Dictionary = event["payload"]
		if str(payload.get("reason", "")) == RemedySystemScript.REASON_LOW_SYNC:
			count += 1
	return count


## 畸形输入不得让演出崩溃或进入不一致状态：空事件、缺 payload、非法 cue_id。
## 这些都不是正常玩法会走到的路径，但一旦抛错就会整关中断，因此固定成回归断言。
func _test_12_invalid_input_robustness(t: ATestBase) -> void:
	t.begin("12 畸形输入：空事件、缺 payload、非法 cue_id 都不崩溃且状态自洽")

	# 逐种畸形事件直接喂给关卡导演
	var malformed: Array = [
		{"label": "空事件数组", "events": []},
		{"label": "空字典事件", "events": [{}]},
		{"label": "缺 payload", "events": [{"kind": "pose_stance"}]},
		{"label": "payload 为空字典", "events": [{"kind": "pose_stance", "payload": {}}]},
		{"label": "kind 为空串", "events": [{"kind": ""}, {"kind": "drag_begin"}, {}]},
		{"label": "含 null 元素", "events": [null]},
		{"label": "含非字典元素", "events": ["坏事件", 42]},
		{"label": "cue_id 为空串", "events": [{"kind": "cue_miss", "cue_id": ""}]},
		{"label": "缺 cue_id 与 object_id", "events": [{"kind": "cue_hit"}]},
	]
	for case in malformed:
		var b: DirectorTestBench = _bench()
		b.advance_to(2760)
		var before_windows: int = b.director.remedy.open_count()
		var before_outcomes: int = b.director.performance.get_outcomes().size()
		# 畸形元素与合法事件混在同一批里喂进去。若入口不判类型，`e.get()` 会在批内
		# 抛 `Invalid call ... in base 'Nil'/'String'`，整帧判定被静默打断；
		# 因此这里断言畸形输入**不产生任何判定、也不开窗**，而不是只看「有没有崩」。
		var batch: Array = case["events"].duplicate()
		b.director.update(batch)
		t.check_eq(b.director.performance.get_outcomes().size(), before_outcomes,
			"喂入「%s」不应凭空产生判定结果" % str(case["label"]))
		t.check(b.director.remedy.open_count() == before_windows,
			"喂入「%s」不应凭空增开补救窗口" % str(case["label"]))
		# 灌完畸形事件后仍能正常跑完并按时结束
		b.advance_to(40000)
		t.check(b.director.is_over(), "喂入「%s」后仍应按时结束" % str(case["label"]))
		t.check_eq(b.director.end_reason, StageDirectorScript.END_REASON_DURATION,
			"喂入「%s」后结束原因仍为到时" % str(case["label"]))
		t.check_eq(b.events_of("stage_end").size(), 1,
			"喂入「%s」后仍只结束一次" % str(case["label"]))

	# 非法 cue_id 的查询与开窗都是安全失败，不留下半开状态
	var b2: DirectorTestBench = _bench()
	b2.advance_to(2760)
	var known_windows: int = b2.director.remedy.open_count()
	t.check_eq(b2.director.remedy.open("不存在的 cue", RemedySystemScript.REASON_MISSED,
		b2.time_ms), false, "非法 cue_id 开窗应失败并返回 false")
	t.check_eq(b2.director.remedy.open("", RemedySystemScript.REASON_MISSED,
		b2.time_ms), false, "空 cue_id 开窗应失败并返回 false")
	t.check_eq(b2.director.remedy.open_count(), known_windows,
		"非法 cue_id 不应改变已开窗口数")
	t.check_eq(b2.director.remedy.is_open("不存在的 cue"), false, "非法 cue_id 不应被当作已开窗")
	t.check(b2.director.remedy.get_window("不存在的 cue").is_empty(),
		"非法 cue_id 不应返回窗口数据")
	t.check_eq(b2.director.remedy.remaining_ms("不存在的 cue", b2.time_ms), 0,
		"非法 cue_id 的剩余时间应为 0 而不是报错")
	t.check(b2.director.performance.get_outcome("不存在的 cue").is_empty(),
		"非法 cue_id 不应返回判定结果")
	t.check_eq(b2.director.performance.segment_score("不存在的段"), -1.0,
		"无落点的段合拍度应为 -1.0")
	t.check_eq(b2.director.performance.segment_graded_count("不存在的段"), 0,
		"无落点的段判定数应为 0")
	t.check_eq(b2.director.performance.has_outcome("不存在的 cue"), false,
		"非法 cue_id 不应被当作已有判定")
	t.finish("畸形事件与非法 cue_id 均安全失败，演出照常按时结束")
