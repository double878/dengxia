extends RefCounted
class_name TestRemedy
## 切片 4 的行为测试：补救与收场。
##
## 本版最大的口径变化：**补救窗口开启期间冻结歌曲时间轴**，8 秒窗口按**真实时间**计。
## 于是有两条必须分别验证的性质，缺一不可：
##   1. 冻结期间歌曲时间、拍点、灯油、关卡计时全都停住（真实时间照走）；
##   2. 关卡固定的 35 秒（歌曲时间）一分不少，代价是真实耗时会变长。
## 另外，冻结使得「两条窗口并存」在正常游玩里几乎不可能出现（歌一停就走不到下一个落点），
## 因此并存与优先级改由直接开窗构造，见 02b 与 10。

const ATestBaseScript := preload("res://tests/a/a_test_base.gd")
const BenchScript := preload("res://tests/a/director_test_bench.gd")
const StageDefScript := preload("res://scripts/a/stage_def.gd")
const CueScript := preload("res://scripts/a/cue.gd")
const RemedySystemScript := preload("res://scripts/a/remedy_system.gd")
const StageDirectorScript := preload("res://scripts/a/stage_director.gd")
const UmbrellaControllerScript := preload("res://scripts/a/umbrella_controller.gd")

const CROUCH_ID: String = "l1_c0_crouch"     ## 落点 1250 ms，判定窗 1000-1500
const STAND_ID: String = "l1_c1_stand"       ## 落点 2500 ms，判定窗 2250-2750
const WINDOW_MS: int = 8000


func _bench(custom: StageDef = null) -> DirectorTestBench:
	return BenchScript.new(custom)


func run_all() -> Dictionary:
	var t: ATestBase = ATestBaseScript.new()
	_test_01_normal_run_no_remedy(t)
	_test_01b_all_hits_no_remedy(t)
	_test_01c_borrow_and_return_journey(t)
	_test_02_miss_opens_window_and_freezes(t)
	_test_02b_two_windows_single_demo(t)
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
	_test_13_freeze_holds_song_time(t)
	return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed,
		"failures": t.failures}


func _test_01_normal_run_no_remedy(t: ATestBase) -> void:
	t.begin("01 空场跑完：八条落点全部漏做、逐条补救，歌曲时间仍按时到达 35 秒")
	var b: DirectorTestBench = _bench()
	var steps_used: int = b.run_to_end()
	t.check(b.director.is_over(), "歌曲时间到 35 秒应已收场")
	t.check_eq(b.director.end_reason, StageDirectorScript.END_REASON_DURATION, "结束原因为到时")
	t.check(b.events_of("stage_start").size() >= 1, "应发出 stage_start")
	t.check_eq(b.events_of("stage_end").size(), 1, "应只发出一次 stage_end")
	t.check_in_range(float(b.director.song_time_ms()), 35000.0, 35010.0,
		"结束时歌曲时间恰为 35000 ms（实际 %d）" % b.director.song_time_ms())
	var missed: int = b.director.performance.missed_outright_cue_ids().size()
	t.check_eq(missed, b.stage_def.cues.size(),
		"未做的关键动作应全部记为「完全没做」（%d / %d）" % [missed, b.stage_def.cues.size()])
	t.check_eq(b.events_of("remedy_open").size(), b.stage_def.cues.size(),
		"每条漏做应各开一次补救窗口（实际 %d）" % b.events_of("remedy_open").size())
	var open_ids: Array[String] = []
	for e in b.events_of("remedy_open"):
		open_ids.append(str(e.get("cue_id", "")))
	print("DBGOPEN %s" % str(open_ids))
	# 冻结的核心证据：真实时间被六条补救各拉长 8 秒
	t.check(b.real_ms() > b.director.song_time_ms() + 30000,
		"六条补救各冻结 8 秒，真实耗时应明显长于歌曲时间（真实 %d ms / 歌曲 %d ms）"
			% [b.real_ms(), b.director.song_time_ms()])
	t.check(steps_used > 6000, "真实步数应远多于 35 秒（实际用了 %d 步）" % steps_used)
	t.finish("空场跑完：歌曲时间按时到 35 秒，真实耗时被补救拉长")


## 正常演出：关键动作都在容差内做到时，**不产生任何补救窗口**，因此也不会冻结。
## 这是唯一一条验证「做对了就没有补救」的正向测试；空场跑完的 01 验证的是相反情况。
##
## 走完整条「游湖借伞」流程：蹲下 → 站起 → 向左走 → 抬左手到打伞位（90°）与许仙右手相接 →
## 接伞 → 持伞走到最右边 → 转身走回交接窗口还伞 → 放手收势。
## 每一步都按落点排好，因此这条测试同时是「借伞还伞能不能按时做完」的端到端验证。
func _test_01b_all_hits_no_remedy(t: ATestBase) -> void:
	t.begin("01b 正常演出：前半场五条落点都在容差内做到，全程无补救")
	var b: DirectorTestBench = _bench()

	# 蹲下（落点 1250）：蹲到底，stance 到 1.0
	b.advance_to(1200)
	b.begin_drag()
	b.crouch_here()
	b.end_drag()

	# 站起（落点 2500，判定窗 2250~2750）：判定时刻是 stance 跨进 [0, 0.05] 的那一帧。
	# 每步 8 px 时 stance 每步降 0.0074，从 1.0 降到 0.05 要 ~128 步 = 1280 ms，
	# 而蹲到底约在 1330 ms 结束——因此站起必须**紧接蹲下**开始，跨过阈值约在 2730 ms。
	b.advance_to(1450)
	b.begin_drag()
	b.stand_up(8.0, 130)
	b.end_drag()

	# 向左移动（落点 5000）：走到 x≈0.34，仍在接伞区（0.07~0.19）右侧
	b.advance_to(4950)
	b.begin_drag()
	b.drag_to_x(0.34, 16.0)
	b.end_drag()

	# 抬手（落点 8750，第一关的到位区间 75°~90°）：4.5 rad/s 下抬到本关上界（90°）约需
	# 0.35 s，因此从 8250 ms 起按住 80 步。按到头会停在上界 90°（StageDef.LEVEL1_HAND_MAX_RAD），
	# 与许仙举着的右手齐平；**一直举着**——中途放手就接不到伞。
	b.advance_to(8250)
	b.hold_left_raise(80)

	# 持抬起的左手向左走进**交接窗口**（落点 10000，容差 ±250）。
	# 窗口是「两只手相接」的那一段（约 0.176~0.296），她从窗口右侧踏进来；
	# 步长与起始时刻一起决定「跨进窗口」落在哪一帧：每步 18 px 时第 5 帧跨进（约 +10 ms）。
	# 步长过大（50 px）会一帧跨过整条窗口；过小（2 px）要七十多帧才走到，反被推到 +260 ms。
	b.advance_to(9940)
	b.begin_drag()
	b.drag_to_x(0.28, 18.0)
	b.end_drag()

	for cue_id in ["l1_c0_crouch", "l1_c1_stand", "l1_c2_move_left",
			"l1_c3_hand_raise", "l1_c4_take_umbrella"]:
		var outcome: Dictionary = b.director.performance.get_outcome(cue_id)
		t.check_eq(bool(outcome.get("hit", false)), true,
			"「%s」应在容差内命中（实际 offset=%s，x=%.4f）"
				% [cue_id, str(outcome.get("offset_ms", "无判定")), b.state().stage_pos.x])
	t.check_eq(b.events_of("remedy_open").size(), 0, "前半场全部做对时不应开出补救窗口")
	t.check_eq(b.events_of(StageDirectorScript.KIND_FREEZE_BEGIN).size(), 0,
		"前半场不应冻结过时间轴")
	t.finish("前半场五条落点全部命中，没有补救窗口与冻结")


## 借伞还伞后半程的端到端走查：接到伞 → 走到小青身旁 → 转身走回 → 按拍还伞 → 放手收势。
##
## 与 01b 拆开的原因：补救窗口开着时歌曲时间是冻结的，前半场只要有一条错拍，
## 后半场的落点时刻就全部对不上。
##
## 这条测试覆盖**八条落点全部命中且零补救窗口**，因此它同时钉住三件容易悄悄退化的事：
##   ① 长距离移动落点的时间预算（走到小青身旁 6.25 s、走回还伞 8.75 s）——
##      步长按「正常拖速」折算，走不完就会错过拍点；
##   ② `l1_c6_return_umbrella` 的 `target_object` 必须等于交接事件上报的 `object_id`（许仙）。
##      写错时这条落点永远判不到（判定直接跳过、窗后判死），本测试会立刻失败；
##   ③ 折返点是**小青身旁**（0.74），不是舞台最右端——`has_reached_turn_point()` 必须置起，
##      否则还伞不触发。
func _test_01c_borrow_and_return_journey(t: ATestBase) -> void:
	t.begin("01c 借伞还伞后半程：走到小青身旁、转身走回、按拍还伞、放手收势")
	var b: DirectorTestBench = _bench()
	var umb: UmbrellaController = b.director.umbrella
	t.check(umb != null and umb.is_enabled(), "第一关应启用借伞还伞流程")

	# 前摇必须照做：少做一条落点就会开出一个 8 秒补救窗口，**歌曲时间随之冻结**，
	# 后面每条落点的时刻全部错位（这条测试第一版就是漏了前摇，五条后半场落点一起判错）。
	# 这也正是真实玩法顺序：蹲下 → 站起 → 左移 → 抬手 → 接伞 → 走到最右边 → 转身走回还伞。
	b.advance_to(1200)
	b.begin_drag()
	b.crouch_here()
	b.end_drag()
	b.advance_to(1450)
	b.begin_drag()
	b.stand_up(8.0, 130)
	b.end_drag()
	b.advance_to(4950)
	b.begin_drag()
	b.drag_to_x(0.34, 16.0)
	b.end_drag()
	b.advance_to(8250)
	b.hold_left_raise(80)

	# 握伞向左走入交接窗口接住伞（落点 10000）
	b.advance_to(9940)
	b.begin_drag()
	b.drag_to_x(0.28, 18.0)
	b.end_drag()
	t.check_eq(umb.holder_id_of(), UmbrellaControllerScript.BAISUZHEN_ID,
		"两只手相接后应已接过伞")

	# 向右走，走到**小青身旁**（落点 16250，目标带 x ∈ [0.74, 0.84]）。
	# `drag_to_x(target_x, step_px)` 的第二个参数是**每步位移量（像素）**：从 0.28 走到 0.74
	# 是 883 px、每步 10 px（89 步 = 890 ms），因此从 15350 ms 起走，跨进目标带约在 16240。
	b.advance_to(15350)
	b.begin_drag()
	b.drag_to_x(0.80, 10.0)
	b.end_drag()
	t.check(umb.has_reached_turn_point(), "走到小青身旁后应记下「已到过折返点」")

	# 转身向左走回许仙身旁还伞（落点 25000）。一次连续左扫：从小青身旁一路走回交接窗口，
	# 还伞应当在「踏进交接窗口」的那一刻触发。影人的「转身」由拖动方向自动完成
	# （皮影只有正反两面，0.1 秒翻面），因此不为它单开落点。
	# 从 0.80 走回窗口上界 0.296 是 968 px、每步 12 px（81 步 = 810 ms），
	# 因此从 24190 ms 起走，跨进窗口约在 25000。
	#
	# 这里**可以**断言还伞的拍点容差了（此前不能）。原来的注释把「还伞稳定偏 +260 ms」
	# 归因成「测试台拖动模型的时序问题」，其实根因是关卡数据：`l1_c6_return_umbrella` 的
	# `target_object` 写成 0（白素贞），而交接事件上报的 `object_id` 是「接手的那个人」=许仙(1)，
	# 判定时被 `target_object != object_id` 直接跳过——**这条落点从来没被判过**，
	# 每次都是窗过之后由 detect_misses 判死，offset 正好是窗上界后的 +260 ms。
	# 2026-10-04 把 `target_object` 改成许仙后，这条落点恢复判定（这条断言就是验证）。
	b.advance_to(24190)
	b.begin_drag()
	b.drag_to_x(0.22, 12.0)
	b.end_drag()
	b.advance_to(25100)

	# 放下已经空掉的左手收势（落点 30000，判定窗 29750~30250）：放手速度 4.5 rad/s，
	# 从 90° 落回 0 约需 0.35 s，因此从 29800 ms 开始按住。
	b.advance_to(29800)
	b.hold_left_lower(80)
	b.idle(1)

	var hits: Array[String] = []
	for cue_id in ["l1_c0_crouch", "l1_c1_stand", "l1_c2_move_left", "l1_c3_hand_raise",
			"l1_c4_take_umbrella", "l1_c5_move_to_xiaoping", "l1_c6_return_umbrella",
			"l1_c7_hand_lower"]:
		var outcome: Dictionary = b.director.performance.get_outcome(cue_id)
		if bool(outcome.get("hit", false)):
			hits.append(cue_id)
		else:
			t.check(false, "「%s」应在容差内命中（实际 offset=%s，x=%.4f）"
				% [cue_id, str(outcome.get("offset_ms", "无判定")), b.state().stage_pos.x])
	t.check_eq(hits.size(), 8, "八条关键动作应全部命中（实际命中 %d 条）" % hits.size())
	t.check_eq(b.events_of("remedy_open").size(), 0,
		"整条借伞还伞做对时不应开出任何补救窗口")
	t.finish("接到伞、走到最右边、转身走回、按拍还伞、放手收势全部命中")


func _test_02_miss_opens_window_and_freezes(t: ATestBase) -> void:
	t.begin("02 漏做：落点过后立刻开窗并冻结时间轴，原失误记为「完全没做」")
	var b: DirectorTestBench = _bench()
	b.advance_to(1400)
	b.advance(20)                        # 跨过 cue0 的判定窗上界（1500）
	t.check(b.director.performance.has_outcome(CROUCH_ID), "漏做应先产生判定结果")
	t.check_eq(bool(b.director.performance.get_outcome(CROUCH_ID).get("missed_outright", false)),
		true, "应标记为「完全没做」")
	t.check(b.director.remedy.is_open(CROUCH_ID), "落点 + 容差刚过就应开出补救窗口")
	var window: Dictionary = b.director.remedy.get_window(CROUCH_ID)
	t.check_eq(str(window["reason"]), RemedySystemScript.REASON_MISSED, "开窗原因为错过落点")
	t.check_eq(int(window["started_song_ms"]), 1510, "开窗时的歌曲时间应是判定窗刚过的那一帧")
	t.check_eq(int(window["started_ms"]), 1510, "此时真实时间与歌曲时间尚未分离")
	t.check_eq(b.director.remedy.remaining_ms(CROUCH_ID, int(window["started_ms"])), WINDOW_MS,
		"窗口长度应为 8 秒")
	t.check(b.has_event("remedy_open", CROUCH_ID), "应发出 remedy_open")
	t.check(b.has_event("remedy_show"), "应发出 remedy_show")
	# 冻结：歌曲时间停住，真实时间照走
	t.check(b.director.is_remedy_frozen(), "有窗口开着就应冻结时间轴")
	t.check_eq(b.clock.is_song_frozen(), true, "时钟应报告歌曲时间已冻结")
	t.check_eq(b.clock.is_paused(), false, "补救冻结不是菜单暂停：时钟整体不算「已暂停」")
	t.check(b.has_event(StageDirectorScript.KIND_FREEZE_BEGIN), "应发出 remedy_freeze_begin")
	var song_now: int = b.director.song_time_ms()
	b.advance_real(2000)
	t.check_eq(b.director.song_time_ms(), song_now, "冻结期间歌曲时间一分不走")
	t.check(b.real_ms() >= 3500, "冻结期间真实时间照常推进")
	b.advance_real(7000)                 # 让窗口超时，测试结束前恢复干净
	t.check(not b.director.is_remedy_frozen(), "窗口关闭后应解冻")
	t.finish("漏做开窗、冻结时间轴，且冻结与菜单暂停是两回事")


## 冻结之后，正常游玩几乎不可能同时出现两条窗口——歌一停就走不到下一个落点。
## 因此这条用直接开窗来构造并存，专门验证「还有窗口就继续冻结」与「同屏唯一示范」。
func _test_02b_two_windows_single_demo(t: ATestBase) -> void:
	t.begin("02b 两条窗口并存：只示范最早到期的一条，且只要还有窗口就继续冻结")
	var b: DirectorTestBench = _bench()
	b.advance_to(1400)
	b.advance(20)
	t.check(b.director.remedy.is_open(CROUCH_ID), "第一条错误应已开窗")
	t.check(b.director.remedy.open(STAND_ID, RemedySystemScript.REASON_MISSED,
		b.director.song_time_ms(), b.real_ms()), "第二条错误应能各自开窗")
	t.check_eq(b.director.remedy.open_count(), 2, "应有两条窗口并存")

	var real_now: int = b.real_ms()
	t.check(b.director.remedy.remaining_ms(CROUCH_ID, real_now)
		< b.director.remedy.remaining_ms(STAND_ID, real_now),
		"先开的窗口剩余时间应更少")
	t.check_eq(b.director.remedy.current_demo_cue_id, _earliest_deadline_id(b),
		"当前示范应是开着窗口里最早到期的那一个")
	var shows: Array = b.events_of("remedy_show")
	t.check(shows.size() >= 1, "应发出 remedy_show")
	t.check_eq(str(shows[shows.size() - 1]["cue_id"]), b.director.remedy.current_demo_cue_id,
		"最后一条示范事件应指向当前示范")

	# 让第一条到期：只要第二条还开着，冻结就要继续
	var first: Dictionary = b.director.remedy.get_window(CROUCH_ID)
	b.advance_real(int(first["deadline_ms"]) - b.real_ms() + 20)
	t.check(not b.director.remedy.is_open(CROUCH_ID), "第一条窗口应已到期关闭")
	t.check(b.director.remedy.is_open(STAND_ID), "第二条窗口应仍开着")
	t.check(b.director.is_remedy_frozen(), "只要还有窗口开着就应继续冻结")
	t.check_eq(b.director.remedy.current_demo_cue_id, _earliest_deadline_id(b),
		"示范应切换到只剩的那条窗口")
	t.check_eq(b.events_of(StageDirectorScript.KIND_FREEZE_BEGIN).size(), 1,
		"并存窗口不应重复冻结（只应有一次 freeze_begin）")

	# 第二条也到期之后才解冻
	var second: Dictionary = b.director.remedy.get_window(STAND_ID)
	b.advance_real(int(second["deadline_ms"]) - b.real_ms() + 20)
	t.check_eq(b.director.remedy.has_open_windows(), false, "两条窗口都应已关闭")
	t.check(not b.director.is_remedy_frozen(), "窗口全部关闭后应解冻")
	t.check_eq(b.events_of(StageDirectorScript.KIND_FREEZE_END).size(), 1,
		"整段冻结只应发出一次 remedy_freeze_end")
	t.check(b.director.song_time_ms() > 1510, "解冻后歌曲时间应恢复推进")
	t.finish("并存窗口只示范最早到期的一条，且冻结延续到最后一个窗口关闭")


func _test_03_out_of_sync_action_still_happens(t: ATestBase) -> void:
	t.begin("03 错拍：动作照常发生、只记未命中，不重复开补救窗口")
	var b: DirectorTestBench = _bench()
	var stand_cue: Dictionary = b.find_cue(STAND_ID)
	b.crouch(1000)
	# 落点前 2100 ms 就开始快速站起，跨过阈值时明显早于容差
	b.advance_to(int(stand_cue["beat_time_ms"]) - 2100)
	b.stand_up(15.0, 69)
	var outcome: Dictionary = b.director.performance.get_outcome(STAND_ID)
	t.check(b.director.performance.has_outcome(STAND_ID), "应产生判定结果")
	t.check_eq(bool(outcome.get("hit", true)), false,
		"错拍站起应记为未命中（offset=%d ms）" % int(outcome.get("offset_ms", 0)))
	t.check_eq(bool(outcome.get("missed_outright", false)), false,
		"错拍做了不算「完全没做」")
	t.check(b.state().stance <= 0.05,
		"错拍时姿势照常到位（stance=%.4f）" % b.state().stance)
	t.check(b.has_event("cue_fire", STAND_ID), "仍应发出 cue_fire")
	t.check(not b.director.remedy.is_open(STAND_ID),
		"错拍做了不重复开补救窗口（该错误已记录）")
	t.check(not b.director.is_remedy_frozen(), "没有窗口时不应冻结时间轴")
	t.finish("错拍动作照常发生、记为未命中，不重复开窗、不冻结")


func _test_04_make_up_in_window_keeps_failure(t: ATestBase) -> void:
	t.begin("04 补做：窗口内完成动作即恢复，原失误仍保留在记录里")
	var b: DirectorTestBench = _bench()
	_crouch_on_beat(b)                   # 让蹲下在容差内命中，于是第一个漏做是站起
	b.advance_to(2760)
	t.check(b.director.remedy.is_open(STAND_ID), "站起漏做应已开出窗口")
	t.check(b.director.is_remedy_frozen(), "补救期间应冻结歌曲时间轴")
	var song_frozen: int = b.director.song_time_ms()

	# 做了别的动作（抬手）不算补做站起
	b.advance(20, {"left_raise": true})
	t.check_eq(b.director.song_time_ms(), song_frozen, "冻结期间歌曲时间不应前进")
	t.check(b.director.remedy.is_open(STAND_ID), "只抬手不算补做站起，窗口应仍开着")
	b.controller.set_input_map({})

	# 补做站起
	b.stand_up(10.0, 110)
	t.check(not b.director.remedy.is_open(STAND_ID), "补做成功后窗口应关闭")
	t.check(b.has_event("remedy_success", STAND_ID), "应发出 remedy_success")
	var success: Dictionary = {}
	for e in b.events_for("remedy_success", STAND_ID):
		success = e
	t.check_eq(bool(success["payload"]["still_missed"]), true,
		"补救成功不抹去原失误（still_missed 应为 true）")
	var record: Dictionary = {}
	for r in b.director.remedy.get_records():
		if str(r.get("cue_id", "")) == STAND_ID:
			record = r
	t.check(not record.is_empty(), "记录里应留有这次失误")
	t.check_eq(bool(record.get("missed", false)), true, "记录里的失误标记应保留")
	t.check_eq(str(record.get("close_reason", "")), RemedySystemScript.CLOSE_SUCCESS,
		"记录的关窗原因为补救成功")
	t.check_eq(bool(b.director.performance.get_outcome(STAND_ID).get("hit", true)), false,
		"原判定结果仍是未命中")
	t.check(not b.director.is_remedy_frozen(), "窗口关完应解冻")
	t.check(b.has_event(StageDirectorScript.KIND_FREEZE_END), "应发出 remedy_freeze_end")

	b.run_to_end()
	t.check(b.director.is_over(), "补做之后演出继续并按时收尾")
	t.finish("窗口内补做成功即关窗解冻，原失误与记录都保留")


func _test_05_timeout_keeps_show_going(t: ATestBase) -> void:
	t.begin("05 超时：8 秒（真实时间）到期仍不补做，记录未完成并继续演出")
	var b: DirectorTestBench = _bench()
	b.advance_to(1400)
	b.advance(20)
	var song_frozen: int = b.director.song_time_ms()
	t.check(b.director.remedy.is_open(CROUCH_ID), "应已开出窗口")

	b.advance_real(WINDOW_MS - 100)
	t.check(b.director.remedy.is_open(CROUCH_ID), "不到 8 秒窗口应仍开着")
	t.check_eq(b.director.song_time_ms(), song_frozen, "这 7.9 秒里歌曲时间应一直冻结")
	b.advance_real(200)                  # 跨过 8 秒
	t.check(not b.director.remedy.is_open(CROUCH_ID), "8 秒到期后窗口应关闭")
	t.check(b.has_event("remedy_timeout", CROUCH_ID), "应发出 remedy_timeout")
	t.check(b.has_event("remedy_hide", CROUCH_ID), "应结束当前示范")
	t.check(not b.director.is_over(), "一次补救超时不结束关卡，演出继续")
	t.check(not b.director.is_remedy_frozen(), "窗口关完应解冻")
	t.check(b.director.song_time_ms() > song_frozen, "解冻后歌曲时间继续推进")

	b.run_to_end()
	t.check(b.director.is_over(), "后续仍按时结束")
	t.check_eq(b.director.end_reason, StageDirectorScript.END_REASON_DURATION, "结束原因为到时")
	var timeout: Dictionary = {}
	for e in b.events_for("remedy_timeout", CROUCH_ID):
		timeout = e
	t.check_in_range(float(timeout["payload"]["elapsed_ms"]), 8000.0, 8010.0,
		"超时事件应按真实时间记录恰好 8 秒（实际 %d ms）"
			% int(timeout["payload"]["elapsed_ms"]))
	t.finish("超时按真实时间计、记录未完成、解冻后演出继续并按时收尾")


func _test_06_no_reopen_for_same_cue(t: ATestBase) -> void:
	t.begin("06 同一 cue_id 不能重复触发或重置自己的窗口")
	var b: DirectorTestBench = _bench()
	b.advance_to(1400)
	b.advance(20)
	var window: Dictionary = b.director.remedy.get_window(CROUCH_ID)
	var deadline: int = int(window["deadline_ms"])
	var opened_count: int = b.director.remedy.open_count()

	# 反复尝试对同一条 cue 开窗，应全部被拒绝
	var accepted: int = 0
	for _i in 20:
		if b.director.remedy.open(CROUCH_ID, RemedySystemScript.REASON_MISSED,
				b.director.song_time_ms(), b.real_ms()):
			accepted += 1
	t.check_eq(accepted, 0, "重复 open 应全部被拒绝")
	t.check_eq(b.director.remedy.open_count(), opened_count, "窗口数量不应增加")
	var after: Dictionary = b.director.remedy.get_window(CROUCH_ID)
	t.check_eq(int(after["deadline_ms"]), deadline, "原窗口的截止时刻不应被重置")

	b.advance_real(deadline - b.real_ms() + 20)
	t.check(not b.director.remedy.is_open(CROUCH_ID), "到期后关闭，而不是被刷新")
	t.check_eq(b.events_for("remedy_open", CROUCH_ID).size(), 1,
		"整场只应产出一次 remedy_open")
	t.finish("同一错误不刷窗口，截止时刻不被重置")


func _test_07_pause_freezes_countdown(t: ATestBase) -> void:
	t.begin("07 菜单暂停：歌曲时间、真实时间与补救倒计时一起冻结")
	var b: DirectorTestBench = _bench()
	b.advance_to(1400)
	b.advance(20)
	t.check(b.director.remedy.is_open(CROUCH_ID), "应已开出窗口")
	var remaining_before: int = b.director.remedy.remaining_ms(CROUCH_ID, b.real_ms())
	var song_before: int = b.director.song_time_ms()
	var real_before: int = b.real_ms()

	b.set_paused(true)
	b.advance(600)                        # 暂停期间推进 600 帧（6 秒）
	t.check_eq(b.director.song_time_ms(), song_before, "暂停期间歌曲时间应冻结")
	t.check_eq(b.real_ms(), real_before, "菜单暂停连真实时间也一起冻结")
	t.check(b.director.remedy.is_open(CROUCH_ID), "暂停期间窗口应仍开着")
	t.check_eq(b.director.remedy.remaining_ms(CROUCH_ID, b.real_ms()), remaining_before,
		"暂停期间补救倒计时不应减少")

	b.set_paused(false)
	b.advance(50)                         # 恢复后推进 500 ms 真实时间
	t.check_eq(b.real_ms(), real_before + 500, "恢复后真实时间继续推进")
	t.check_eq(b.director.remedy.remaining_ms(CROUCH_ID, b.real_ms()), remaining_before - 500,
		"恢复后补救倒计时从冻结值继续递减")

	var frozen_song: int = b.director.song_time_ms()
	b.advance_real(remaining_before - 500)
	t.check(not b.director.remedy.is_open(CROUCH_ID), "补足原定 8 秒后应超时关闭")
	t.check(not b.director.is_remedy_frozen(), "超时关窗后应解冻")
	t.check_eq(b.director.song_time_ms(), frozen_song, "整个补救期间歌曲时间都没走")
	t.finish("菜单暂停同时冻结歌曲时间、真实时间与补救倒计时；恢复后不跳变")


## 边界测试用一份**没有落点**的数据：标准第一关数据下空场跑会先花掉五条补救的冻结时间，
## 根本走不到 34990 ms 这个边界。本测试要验的是时间轴本身的边界，因此把补救因素排除掉。
func _test_08_stage_ends_on_time(t: ATestBase) -> void:
	t.begin("08 到时结束：35 秒一到就结束，不延长、不重播")
	var def: StageDef = StageDefScript.make_level1()
	def.cues = []
	var b: DirectorTestBench = _bench(def)
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


## 冻结之后，「窗口跨过 35 秒」这件事不可能自然发生：歌曲时间冻住了，永远到不了 35 秒。
## 仍会走到这条路径的是玩家主动跳过（force_end）——收场时还开着的窗口必须被关闭并留记录，
## 否则时钟会带着冻结状态离开本关。
func _test_09_window_at_stage_end(t: ATestBase) -> void:
	t.begin("09 收场时仍开着的窗口随演出结束关闭，并把时间轴解冻")
	var b: DirectorTestBench = _bench()
	b.advance_to(1400)
	b.advance(20)
	t.check(b.director.remedy.is_open(CROUCH_ID), "应已开出窗口")
	t.check(b.director.is_remedy_frozen(), "此时时间轴应处于冻结状态")

	b.force_end()
	t.check(b.director.is_over(), "立即结束应生效")
	t.check(not b.director.remedy.is_open(CROUCH_ID), "未到期的窗口应随演出结束关闭")
	t.check(not b.director.is_remedy_frozen(), "收场后不应把冻结状态带出本关")
	t.check_eq(b.clock.is_song_frozen(), false, "时钟应已解冻")
	var timeout: Dictionary = {}
	for e in b.events_for("remedy_timeout", CROUCH_ID):
		timeout = e
	t.check(not timeout.is_empty(), "随结束关闭也要留记录")
	t.check_eq(str(timeout["payload"].get("reason", "")), RemedySystemScript.CLOSE_STAGE_END,
		"关窗原因应为 stage_end")
	var end_event: Dictionary = {}
	for e in b.events_of("stage_end"):
		end_event = e
	t.check_eq(int(end_event["payload"]["remedy_open_count"]), 1,
		"结束时应报告仍有 1 个窗口未到期")
	t.finish("收场时窗口随演出关闭并留记录，冻结一并解除")


func _test_10_single_demo_and_separate_records(t: ATestBase) -> void:
	t.begin("10 同屏只选一个当前示范，不同错误各自留记录")
	var b: DirectorTestBench = _bench()
	b.advance_to(1400)
	b.advance(20)
	t.check(b.director.remedy.is_open(CROUCH_ID), "第一条错误应已开窗")
	# 再人为补两条不同错误的窗口，检验「不同错误各自留记录」与示范优先级
	t.check(b.director.remedy.open(STAND_ID, RemedySystemScript.REASON_MISSED,
		b.director.song_time_ms(), b.real_ms()), "第二条错误应能开窗")
	t.check(b.director.remedy.open("l1_c2_move_left", RemedySystemScript.REASON_MISSED,
		b.director.song_time_ms(), b.real_ms()), "第三条错误应能开窗")
	t.check_eq(b.director.remedy.open_count(), 3, "应有三个错误各自开着窗口")
	t.check_eq(b.director.remedy.get_records().size(), 3, "每个错误各自留一条记录")
	t.check(b.director.remedy.current_demo_cue_id != "", "应有当前示范")
	t.check_eq(b.director.remedy.current_demo_cue_id, _earliest_deadline_id(b),
		"当前示范应是所有开着窗口里最早到期的那一个")
	t.check_eq(b.events_of("remedy_show").size(), 1, "示范只应发布一次（同屏唯一）")

	# 让最早的那条超时，示范应切换到下一条
	b.advance_real(120)
	t.check_eq(b.director.remedy.current_demo_cue_id, _earliest_deadline_id(b),
		"示范仍应指向最早到期的窗口")
	var still_open: Array[String] = []
	for cue_id in b.director.remedy.windows.keys():
		still_open.append(str(cue_id))
	t.check(still_open.size() >= 1, "仍应有窗口开着")
	t.check(still_open.has(b.director.remedy.current_demo_cue_id),
		"当前示范必须是仍开着的窗口之一")
	t.finish("多个错误各自留记录，同屏只展示一个当前示范")


## 合拍度跌破警戒线时同样触发补救（PRD 第 5.1、5.2.1 节）。
##
## 低合拍补救要求「段内已判定数 >= min_graded（2）且合拍度跌破警戒线」，
## 然后开在段内「既未判定、也未开窗」的下一个落点上。三个条件必须同时成立：
##   1. 目标段里有至少两条落点**都已判定**（才够 min_graded，且合拍度被压到 0）；
##   2. 段里还有第三条落点**既未判定、也没开窗**，才有可示范的对象；
##   3. 那条待示范的落点必须与用来判负的动作**不同**（这里是落手 vs 抬手/移动），
##      否则玩家手里的姿势都已经到了目标带，落点会立刻被顺手判掉。
##
## 本测试因此用一段专门构造的数据，而不是第一关的真实数据：补救会冻结歌曲时间，
## 第一关的落点间隔只有一两秒，冻结一开就再也走不到后面的落点，测不到这条路径。
func _test_11_low_sync_triggers_remedy(t: ATestBase) -> void:
	t.begin("11 低合拍：段内合拍度跌破警戒线也触发补救，理由与漏做分开")
	var def: StageDef = StageDef.new()
	def.id = 99
	def.duration_ms = 20000
	def.bpm = StageDefScript.LEVEL1_BPM
	def.segments = [{"name": "低协", "start_ms": 0, "end_ms": 20000}]
	def.cues = [
		_segment(CueScript.make("t_m1", 6000, CueScript.ACTION_MOVE_LEFT, 0,
			{"key": "x", "min": 0.0, "max": 0.35}, 250, "move_left"), "低协"),
		_segment(CueScript.make("t_m2", 9000, CueScript.ACTION_MOVE_RIGHT, 0,
			{"key": "x", "min": 0.65, "max": 1.0}, 250, "move_right"), "低协"),
		_segment(CueScript.make("t_l", 12000, CueScript.ACTION_HAND_LOWER, 0,
			{"key": "angle", "min": -PI * 0.5, "max": -1.2}, 250, "hand_lower"), "低协"),
	]
	t.check_eq(def.validate().size(), 0, "构造的数据应通过校验")

	var b: DirectorTestBench = _bench(def)
	t.check_eq(b.director.performance.segment_graded_count("低协"), 0, "开局该段还没有判定")

	# 在判定窗之外做掉左移与右移：两条都记错拍（不是漏做），该段合拍度跌到 0
	b.advance_to(5200)
	b.begin_drag()
	b.drag(Vector2(-260.0, 0.0), 8)
	b.end_drag()
	t.check(b.director.performance.has_outcome("t_m1"), "左移落点应已被判定")
	t.check_eq(bool(b.director.performance.get_outcome("t_m1").get("hit", true)), false,
		"窗外做应记为错拍")
	b.advance_to(8400)
	b.begin_drag()
	b.drag(Vector2(260.0, 0.0), 6)
	b.end_drag()
	t.check(b.director.performance.has_outcome("t_m2"), "右移落点应已被判定")
	t.check_eq(b.director.performance.segment_graded_count("低协") >= 2, true,
		"该段应已有至少两条判定（实际 %d）"
			% b.director.performance.segment_graded_count("低协"))
	t.check(b.director.performance.segment_score("低协") < b.director.remedy.sync_threshold,
		"该段合拍度应已跌破警戒线（实际 %.3f）"
			% b.director.performance.segment_score("低协"))

	var low_sync_events: Array = []
	for e in b.events_of("remedy_open"):
		if str(e["payload"].get("reason", "")) == RemedySystemScript.REASON_LOW_SYNC:
			low_sync_events.append(e)
	t.check_eq(low_sync_events.size(), 1, "跌破警戒线后应开出恰好一个低合拍窗口（实际 %d）"
		% low_sync_events.size())
	var low_sync_id: String = ""
	if low_sync_events.size() == 1:
		low_sync_id = str(low_sync_events[0]["cue_id"])
	t.check_eq(low_sync_id, "t_l", "低合拍示范应指向段内还没做过、也没开窗的那条落点")
	t.check(b.director.remedy.is_open(low_sync_id), "该低合拍窗口应开着")
	t.check(not b.director.performance.has_outcome(low_sync_id),
		"低合拍示范应指向段内还没做过的落点「%s」" % low_sync_id)
	t.check(b.director.is_remedy_frozen(), "低合拍补救同样应冻结歌曲时间轴")

	# 窗口内按示范补做落手，窗口应关闭。先落到目标角之外，确认这段时间歌曲时间没走。
	b.advance_real(600)
	t.check(b.director.remedy.is_open(low_sync_id), "还没补做时窗口应仍开着")
	var song_frozen: int = b.director.song_time_ms()
	b.advance(25, {"left_lower": true})
	t.check_eq(b.director.song_time_ms(), song_frozen, "补救期间歌曲时间不应前进")
	t.check(b.director.remedy.is_open(low_sync_id), "还没落到目标角时窗口应仍开着")
	b.advance(10, {"left_lower": true})
	t.check(b.director.performance.has_outcome(low_sync_id),
		"补做后该落点应产生新的判定（实际 hand_angle.x=%.4f）" % b.state().hand_angle.x)
	t.check(not b.director.remedy.is_open(low_sync_id), "补做示范动作后低合拍窗口应关闭")
	var success: Dictionary = {}
	for e in b.events_of("remedy_success"):
		if str(e["cue_id"]) == low_sync_id:
			success = e
	t.check(not success.is_empty(), "补做后应发出 remedy_success（%s）" % low_sync_id)
	if not success.is_empty():
		t.check_eq(bool(success["payload"].get("still_missed", false)), true,
			"合拍度已经跌破，补救成功也不抹去原失误")
	var record: Dictionary = {}
	for r in b.director.remedy.get_records():
		if str(r.get("cue_id", "")) == low_sync_id:
			record = r
	t.check(not record.is_empty(), "低合拍补救也应留记录")
	t.check_eq(str(record.get("reason", "")), RemedySystemScript.REASON_LOW_SYNC,
		"记录里的开窗理由应为低合拍")
	var before_more: int = _count_low_sync_opens(b)
	b.advance_real(300)
	t.check_eq(_count_low_sync_opens(b), before_more, "低合拍补救每段只开一次，不反复刷窗口")
	t.finish("低合拍段触发补救、可补做成功，理由与漏做分开且原失误保留")


## 畸形输入不得让演出崩溃或进入不一致状态：空事件、缺 payload、非法 cue_id。
## 这些都不是正常玩法会走到的路径，但一旦抛错就会整关中断，因此固定成回归断言。
func _test_12_invalid_input_robustness(t: ATestBase) -> void:
	t.begin("12 畸形输入：空事件、缺 payload、非法 cue_id 都不崩溃且状态自洽")

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
		b.advance_to(1510)
		# 若入口不判类型，`e.get()` 会在批内抛 `Invalid call ... in base 'Nil'/'String'`，
		# 整帧判定被静默打断；因此断言畸形输入**不产生任何判定、也不开窗**，
		# 而不是只看「有没有崩」。
		var before_windows: int = b.director.remedy.open_count()
		var before_outcomes: int = b.director.performance.get_outcomes().size()
		var batch: Array = case["events"].duplicate()
		b.director.update(batch)
		t.check_eq(b.director.performance.get_outcomes().size(), before_outcomes,
			"喂入「%s」不应凭空产生判定结果" % str(case["label"]))
		t.check(b.director.remedy.open_count() == before_windows,
			"喂入「%s」不应凭空增开补救窗口" % str(case["label"]))
		# 灌完畸形事件后仍能正常跑完并按时结束（补救冻结不影响收场）
		b.run_to_end()
		t.check(b.director.is_over(), "喂入「%s」后仍应按时结束" % str(case["label"]))
		t.check_eq(b.director.end_reason, StageDirectorScript.END_REASON_DURATION,
			"喂入「%s」后结束原因仍为到时" % str(case["label"]))
		t.check_eq(b.events_of("stage_end").size(), 1,
			"喂入「%s」后仍只结束一次" % str(case["label"]))

	# 非法 cue_id 的查询与开窗都是安全失败，不留下半开状态
	var b2: DirectorTestBench = _bench()
	b2.advance_to(1510)
	var known_windows: int = b2.director.remedy.open_count()
	t.check_eq(b2.director.remedy.open("不存在的 cue", RemedySystemScript.REASON_MISSED,
		b2.director.song_time_ms(), b2.real_ms()), false,
		"非法 cue_id 开窗应失败并返回 false")
	t.check_eq(b2.director.remedy.open("", RemedySystemScript.REASON_MISSED,
		b2.director.song_time_ms(), b2.real_ms()), false,
		"空 cue_id 开窗应失败并返回 false")
	t.check_eq(b2.director.remedy.open_count(), known_windows, "非法 cue_id 不应改变已开窗口数")
	t.check_eq(b2.director.remedy.is_open("不存在的 cue"), false, "非法 cue_id 不应被当作已开窗")
	t.check(b2.director.remedy.get_window("不存在的 cue").is_empty(),
		"非法 cue_id 不应返回窗口数据")
	t.check_eq(b2.director.remedy.remaining_ms("不存在的 cue", b2.real_ms()), 0,
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


## 补救冻结最关键的一条：歌曲时间、拍点、关卡计时全停，**真实时间照走**。
## 与菜单暂停（07）的区别就在这里——暂停连真实时间也停，因此补救倒计时会一起停。
## （灯油由 LampController 持有时钟自行冻结，见 test_level1_runtime。）
func _test_13_freeze_holds_song_time(t: ATestBase) -> void:
	t.begin("13 补救冻结：歌曲时间与拍点全停，真实时间与 8 秒倒计时照走")
	var b: DirectorTestBench = _bench()
	b.advance_to(1400)
	b.advance(20)
	var song_before: int = b.director.song_time_ms()
	var beat_before: int = b.clock.get_beat_index()
	var remaining_before: int = b.director.remedy.remaining_ms(CROUCH_ID, b.real_ms())
	var real_before: int = b.real_ms()
	t.check(b.director.is_remedy_frozen(), "窗口开着时应处于冻结状态")

	b.advance_real(3000)
	t.check_eq(b.director.song_time_ms(), song_before, "3 秒真实时间里歌曲时间应完全不动")
	t.check_eq(b.clock.get_beat_index(), beat_before, "拍点应停在同一拍")
	t.check_eq(b.real_ms(), real_before + 3000, "真实时间应推进了 3 秒")
	t.check_eq(b.director.remedy.remaining_ms(CROUCH_ID, b.real_ms()),
		remaining_before - 3000, "补救倒计时应按真实时间递减")
	t.check(not b.director.is_over(), "冻结期间关卡不应结束")
	t.check(b.director.duration_ms() - b.director.song_time_ms() > 33000,
		"关卡剩余时间（歌曲时间口径）不应被补救吃掉")
	t.finish("冻结只作用于歌曲时间与判定，真实时间与 8 秒倒计时照走")


## 让蹲下在容差窗内完成（cue l1_c0_crouch 落点 1250 ms），于是后面第一个漏做的是站起。
func _crouch_on_beat(b: DirectorTestBench) -> void:
	b.advance_to(1150)
	b.begin_drag()
	b.drag(Vector2(0.0, 130.0), 12)
	b.end_drag()


## 给一条 Cue 标注所属段落。低合拍补救按段汇总合拍度，没有 segment 就永远走不到。
func _segment(cue: Dictionary, segment_name: String) -> Dictionary:
	cue["segment"] = segment_name
	return cue


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
		if str(e["payload"].get("reason", "")) == RemedySystemScript.REASON_LOW_SYNC:
			count += 1
	return count
