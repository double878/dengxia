extends RefCounted
class_name TestLevel1Runtime

const ATestBaseScript := preload("res://tests/a/a_test_base.gd")
const RUNTIME_PATH: String = "res://scripts/a/level1_runtime.gd"
const STEP_S: float = 0.01


func run_all() -> Dictionary:
	var t: ATestBase = ATestBaseScript.new()
	if not ResourceLoader.exists(RUNTIME_PATH):
		t.begin("第一关 A 侧运行编排")
		t.check(false, "缺少 Level1Runtime")
		return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed,
			"failures": t.failures}
	_test_start_to_end(t)
	_test_hit_and_offbeat(t)
	_test_miss_and_remedy(t)
	_test_pause_and_resume(t)
	_test_end_event_boundary(t)
	_test_cues_belong_to_timeline_segments(t)
	_test_mixed_event_stream_object_ids(t)
	return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed,
		"failures": t.failures}


func _new_run() -> Dictionary:
	var clock := MusicClock.new()
	clock.set_player(null, StageDef.LEVEL1_BPM)
	clock.start()
	var runtime: Object = load(RUNTIME_PATH).new()
	runtime.setup(clock)
	runtime.start()
	return {"clock": clock, "runtime": runtime, "events": runtime.take_events()}


## 推进到歌曲时间目标值。补救窗口开着时歌曲时间会冻结，此时循环会一直走到窗口到期、
## 解冻之后才可能到达目标，因此真实步数明显多于「目标毫秒 ÷ 10」。
func _advance(run: Dictionary, target_ms: int, max_steps: int = 20000) -> void:
	var clock: MusicClock = run["clock"]
	var runtime: Object = run["runtime"]
	var steps: int = 0
	while clock.get_song_time_ms() < target_ms and not runtime.is_over() and steps < max_steps:
		_steps(run, 1)
		steps += 1


## 固定步数推进。补救冻结期间只能用这个按真实时间推进。
func _steps(run: Dictionary, count: int) -> void:
	var clock: MusicClock = run["clock"]
	var runtime: Object = run["runtime"]
	for _i in maxi(count, 0):
		clock.update(STEP_S)
		runtime.tick(STEP_S)
		run["events"].append_array(runtime.take_events())


func _events(run: Dictionary, kind: String, cue_id: String = "") -> Array:
	var found: Array = []
	for event in run["events"]:
		if event.get("kind", "") == kind and (cue_id.is_empty() or event.get("cue_id", "") == cue_id):
			found.append(event)
	return found


func _test_start_to_end(t: ATestBase) -> void:
	t.begin("第一关从开演到 35 秒结束，状态和事件可交给接收端")
	var run: Dictionary = _new_run()
	var runtime: Object = run["runtime"]
	t.check_eq(runtime.stage_def.duration_ms, 35000, "使用第一关 35 秒数据")
	t.check_eq(runtime.stage_def.cues.size(), 6, "使用第一关 6 条关键动作")
	t.check_eq(_events(run, "stage_start").size(), 1, "开演只发一次 stage_start")
	_advance(run, 35000)
	t.check(runtime.is_over(), "35 秒（歌曲时间）时结束")
	t.check(runtime.lamp_controller.is_finished(), "油灯随关卡结束停止")
	t.check_eq(_events(run, "stage_end").size(), 1, "关卡结束事件只发一次")
	t.check_eq(_events(run, "stage_end")[0]["time_ms"], 35000,
		"stage_end 使用歌曲时间 35000 ms")
	t.check(_events(run, "cue_hint").size() > 0, "有落点前提示事件")
	t.check(_events(run, "cue_miss").size() > 0, "空场漏做仍有结果事件")
	t.check(_events(run, "remedy_freeze_begin").size() > 0, "空场跑应有补救冻结")
	t.check(_events(run, "remedy_freeze_end").size() > 0, "补救结束应解冻")
	t.check(run["clock"].get_real_time_ms() > 35000,
		"补救冻结使真实耗时长于歌曲时长（真实 %d ms / 歌曲 %d ms）"
			% [run["clock"].get_real_time_ms(), run["clock"].get_song_time_ms()])
	t.check(_events(run, "lamp_oil_changed").size() > 0, "油灯状态持续可读")
	var finished_oil: float = runtime.lamp_controller.lamp.oil
	_advance(run, 36000)
	t.check_eq(runtime.lamp_controller.lamp.oil, finished_oil, "结束后不再扣油")
	t.finish("第一关完整时间线和接收事件闭环")


func _test_hit_and_offbeat(t: ATestBase) -> void:
	t.begin("同一第一关 Cue 可正常命中，也可提前错拍且动作照常发生")
	var hit_run: Dictionary = _new_run()
	_advance(hit_run, 1120)
	_crouch(hit_run)
	t.check(_events(hit_run, "cue_hit", "l1_c0_crouch").size() > 0,
		"容差窗内蹲下应命中")
	t.check(hit_run["runtime"].puppet_controller.get_controlled().stance >= 0.85,
		"命中时物理姿态到位")
	var miss_run: Dictionary = _new_run()
	_advance(miss_run, 100)
	var feedback_before: float = miss_run["runtime"].lamp_controller.lamp.flame_feedback
	_crouch(miss_run)
	t.check(_events(miss_run, "cue_fire", "l1_c0_crouch").size() > 0,
		"提前错拍仍发出物理动作事件")
	t.check(_events(miss_run, "cue_miss", "l1_c0_crouch").size() > 0,
		"提前错拍应记为未命中")
	t.check(miss_run["runtime"].puppet_controller.get_controlled().stance >= 0.85,
		"错拍时物理姿态照常到位")
	t.check(miss_run["runtime"].lamp_controller.lamp.flame_feedback < feedback_before,
		"错拍后油灯反馈下降")
	t.finish("命中与错拍经同一运行时可观察")


func _crouch(run: Dictionary) -> void:
	var runtime: Object = run["runtime"]
	var controller: PuppetController = runtime.puppet_controller
	var state: PuppetState = controller.get_controlled()
	var chest := Vector2(state.stage_pos.x * 1920.0,
		state.stage_pos.y * 1080.0 - PuppetController.CHEST_TAG_RADIUS_PX * 0.5)
	controller.begin_drag(0, chest)
	for _i in 8:
		controller.drag_to(Vector2(0.0, 120.0))
		var clock: MusicClock = run["clock"]
		clock.update(STEP_S)
		runtime.tick(STEP_S)
		run["events"].append_array(runtime.take_events())
	controller.end_drag()
	var clock: MusicClock = run["clock"]
	clock.update(STEP_S)
	runtime.tick(STEP_S)
	run["events"].append_array(runtime.take_events())


func _test_miss_and_remedy(t: ATestBase) -> void:
	t.begin("漏做开窗并冻结时间轴，补做成功后解冻，但原失误保留")
	var run: Dictionary = _new_run()
	var runtime: Object = run["runtime"]
	var clock: MusicClock = run["clock"]
	_advance(run, 1400)
	_steps(run, 20)                       # 跨过 cue0 的判定窗上界（1500）
	var cue_id: String = "l1_c0_crouch"
	t.check(_events(run, "cue_miss", cue_id).size() > 0, "漏做先产生 cue_miss")
	t.check(_events(run, "remedy_open", cue_id).size() > 0, "漏做打开补救窗口")
	t.check(runtime.director.is_remedy_frozen(), "补救期间应冻结歌曲时间轴")
	t.check(_events(run, "remedy_freeze_begin").size() > 0, "应产出 freeze_begin 事件")
	var song_frozen: int = clock.get_song_time_ms()
	var feedback_before: float = runtime.lamp_controller.lamp.flame_feedback
	var oil_frozen: float = runtime.lamp_controller.lamp.oil
	_steps(run, 50)
	t.check_eq(clock.get_song_time_ms(), song_frozen, "冻结期间歌曲时间一分不走")
	t.check_eq(runtime.lamp_controller.lamp.oil, oil_frozen, "冻结期间灯油不消耗")

	# 补做蹲下。要点：**结算成功的那一帧歌曲时间仍是冻结值**——解冻只对它之后生效，
	# 否则「补救期间歌曲时间一分不走」就会被结算本身的那一帧破坏。
	var controller: PuppetController = runtime.puppet_controller
	var state: PuppetState = controller.get_controlled()
	controller.begin_drag(0, Vector2(state.stage_pos.x * 1920.0,
		state.stage_pos.y * 1080.0 - PuppetController.CHEST_TAG_RADIUS_PX * 0.5))
	var fix_steps: int = 0
	while runtime.director.remedy.is_open(cue_id) and fix_steps < 30:
		controller.drag_to(Vector2(0.0, 120.0))
		_steps(run, 1)
		fix_steps += 1
	t.check(fix_steps > 0, "拖动应最终把蹲下做到位（用了 %d 步）" % fix_steps)
	t.check(_events(run, "remedy_success", cue_id).size() > 0,
		"窗口内补做动作应产生 remedy_success")
	t.check_eq(clock.get_song_time_ms(), song_frozen,
		"结算成功的那一帧歌曲时间仍是冻结值")
	controller.end_drag()
	_steps(run, 1)
	t.check(not runtime.director.remedy.is_open(cue_id), "成功后关闭补救窗口")
	t.check(runtime.director.remedy.get_records().size() > 0, "原失误留在记录中")
	t.check(runtime.lamp_controller.lamp.flame_feedback != feedback_before,
		"判定和补救结果已驱动油灯火苗")
	t.check(not runtime.director.is_remedy_frozen(), "补做成功后应解冻")
	_advance(run, 3000)
	t.check(clock.get_song_time_ms() >= 3000, "解冻后歌曲时间恢复推进")
	t.finish("漏做开窗冻结、补做成功解冻，原失误保留")


func _test_pause_and_resume(t: ATestBase) -> void:
	t.begin("暂停冻结时间、油灯和输入，恢复后继续")
	var run: Dictionary = _new_run()
	var runtime: Object = run["runtime"]
	_advance(run, 1000)
	var paused_ms: int = run["clock"].get_song_time_ms()
	var paused_oil: float = runtime.lamp_controller.lamp.oil
	var paused_distance: float = runtime.lamp_controller.lamp.distance
	runtime.set_paused(true)
	runtime.lamp_controller.set_input_map({"distance_increase": true})
	for _i in 100:
		run["clock"].update(STEP_S)
		runtime.tick(STEP_S)
	t.check_eq(run["clock"].get_song_time_ms(), paused_ms, "暂停时歌曲时间冻结")
	t.check_eq(runtime.lamp_controller.lamp.oil, paused_oil, "暂停时油量冻结")
	t.check_eq(runtime.lamp_controller.lamp.distance, paused_distance, "暂停时输入不推进灯距")
	t.check(runtime.take_events().is_empty(), "暂停时没有虚假变化事件")
	runtime.set_paused(false)
	runtime.lamp_controller.set_input_map({})
	_advance(run, 2000)
	t.check_eq(run["clock"].get_song_time_ms(), 2000, "恢复后沿原时间轴继续")
	t.check(runtime.lamp_controller.lamp.oil < paused_oil, "恢复后继续耗油")
	t.finish("暂停与恢复保持统一歌曲时间")


func _test_end_event_boundary(t: ATestBase) -> void:
	t.begin("最后一帧跨过 35 秒时，对外事件仍落在关卡时间内")
	var run: Dictionary = _new_run()
	_advance(run, 34990)
	var clock: MusicClock = run["clock"]
	var runtime: Object = run["runtime"]
	clock.update(0.11)
	runtime.tick(0.11)
	run["events"].append_array(runtime.take_events())
	t.check(runtime.is_over(), "跨过结束点后立即结束")
	var end_events: Array = _events(run, "stage_end")
	t.check_eq(end_events.size(), 1, "只收到一次结束事件")
	if end_events.size() == 1:
		t.check_eq(end_events[0]["time_ms"], 35000, "结束事件时间固定为 35000 ms")
		t.check_eq(end_events[0]["payload"]["song_time_ms"], 35000,
			"结束载荷时间固定为 35000 ms")
	var out_of_range: int = 0
	for event in run["events"]:
		if int(event["time_ms"]) > 35000:
			out_of_range += 1
	t.check_eq(out_of_range, 0, "没有超出关卡时长的对外事件")
	t.finish("结束帧不会向 B/C 输出越界时间戳")


func _test_cues_belong_to_timeline_segments(t: ATestBase) -> void:
	t.begin("每条关键动作都属于落点所在的演出段落")
	var stage: StageDef = StageDef.make_level1()
	for cue in stage.cues:
		var matched: bool = false
		for segment in stage.segments:
			if str(cue["segment"]) == str(segment["name"]) \
				and int(cue["beat_time_ms"]) >= int(segment["start_ms"]) \
				and int(cue["beat_time_ms"]) < int(segment["end_ms"]):
				matched = true
				break
		t.check(matched, "%s 的段落归属与落点一致" % str(cue["cue_id"]))
	t.finish("时间线与段落合拍分组一致")


## A 的对外事件流里，影人事件 object_id 是 int（0-2），油灯事件是字符串 "lamp_main"。
## 两类对象共用一条流，因此任何「按事件类型分流」的接收端都不能假设 object_id 是字符串：
## 把影人事件喂给只认油灯契约的接收端会被判成畸形事件（实测会逐帧刷 push_error），
## 而油灯事件仍必须被严格校验。这条测试固定两类事件的类型与分流规则。
func _test_mixed_event_stream_object_ids(t: ATestBase) -> void:
	t.begin("同一事件流里影人是 int、油灯是字符串，接收端按类型分流")
	var run: Dictionary = _new_run()
	var runtime: Object = run["runtime"]
	_advance(run, 6000)
	var events: Array = run["events"]
	t.check(events.size() > 0, "开演后应产生事件")

	var lamp_events: Array = []
	var puppet_events: Array = []
	for event in events:
		if typeof(event.get("object_id", null)) == TYPE_STRING:
			lamp_events.append(event)
		else:
			puppet_events.append(event)
	t.check(lamp_events.size() > 0, "应有 object_id 为字符串的油灯事件")
	t.check(puppet_events.size() > 0, "应有 object_id 为 int 的影人事件")
	var puppet_ids_are_int: bool = true
	for event in puppet_events:
		if typeof(event.get("object_id", null)) != TYPE_INT:
			puppet_ids_are_int = false
	t.check(puppet_ids_are_int, "影人事件的 object_id 应全为 int")
	var lamp_id_matches: int = 0
	for event in lamp_events:
		if str(event.get("object_id", "")) == LampController.LAMP_OBJECT_ID:
			lamp_id_matches += 1
	t.check_eq(lamp_id_matches, lamp_events.size(),
		"油灯事件的 object_id 应全为 %s（%d / %d）"
			% [LampController.LAMP_OBJECT_ID, lamp_id_matches, lamp_events.size()])

	# 接收端必须只拿油灯事件去校验：混入影人事件会被判成畸形
	var parsed: Array = LampController.receive_events(lamp_events)
	t.check_eq(parsed.size(), lamp_events.size(), "油灯事件应全部通过接收端校验")
	t.finish("两类 object_id 类型明确，接收端按字符串/整型分流")
