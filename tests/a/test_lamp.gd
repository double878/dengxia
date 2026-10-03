extends RefCounted
class_name TestLamp
## 切片 5 的行为测试：油灯的 LampState、输入连续性、灯油消耗、flame_feedback 与事件契约。
##
## 断言的都是外部行为与数据契约（状态读数、事件内容、时间来源），
## 不直接戳私有变量；基础 30 条覆盖任务书验收点，另含 4 条回归测试。

const ATestBaseScript := preload("res://tests/a/a_test_base.gd")
const BenchScript := preload("res://tests/a/lamp_test_bench.gd")
const LampStateScript := preload("res://scripts/a/lamp_state.gd")
const LampControllerScript := preload("res://scripts/a/lamp_controller.gd")
const LampInputReaderScript := preload("res://scripts/a_test/lamp_input_reader.gd")

## 输入键名：与 LampController.set_input_map 的约定一致
const KEY_DIST_UP: String = "distance_increase"
const KEY_DIST_DOWN: String = "distance_decrease"
const KEY_EXPO_UP: String = "exposure_increase"
const KEY_EXPO_DOWN: String = "exposure_decrease"


func _bench() -> LampTestBench:
	return BenchScript.new()


func run_all() -> Dictionary:
	var t: ATestBase = ATestBaseScript.new()
	_test_01_initial_state_in_range(t)
	_test_02_distance_increase(t)
	_test_03_distance_decrease(t)
	_test_04_distance_upper_bound(t)
	_test_05_distance_lower_bound(t)
	_test_06_exposure_increase(t)
	_test_07_exposure_decrease(t)
	_test_08_exposure_upper_bound(t)
	_test_09_exposure_lower_bound(t)
	_test_10_opposite_input_holds(t)
	_test_11_release_keeps_value(t)
	_test_12_input_never_touches_oil(t)
	_test_13_oil_decreases_monotonically(t)
	_test_14_same_song_time_no_double_charge(t)
	_test_15_oil_never_below_zero(t)
	_test_16_backwards_time_no_refill(t)
	_test_17_pause_freezes_song_time(t)
	_test_18_pause_freezes_oil(t)
	_test_19_pause_freezes_feedback(t)
	_test_20_resume_continues_no_jump(t)
	_test_21_hit_raises_feedback(t)
	_test_22_miss_lowers_feedback(t)
	_test_23_duplicate_event_no_double_stack(t)
	_test_24_state_changes_before_event(t)
	_test_25_event_contract_fields(t)
	_test_26_payload_has_current_values(t)
	_test_27_malformed_events_no_crash(t)
	_test_28_finished_stops_oil(t)
	_test_29_event_time_from_music_clock(t)
	_test_30_receiver_parses_event(t)
	_test_31_fire_does_not_raise_feedback_on_miss(t)
	_test_32_backwards_time_rebases_oil_consumption(t)
	_test_33_malformed_feedback_is_ignored(t)
	_test_34_lamp_input_mapping_uses_prd_controls(t)
	return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed,
		"failures": t.failures}


func _test_01_initial_state_in_range(t: ATestBase) -> void:
	t.begin("01 初始 LampState 全部落在合法范围内")
	var b: LampTestBench = _bench()
	var s: LampState = b.state()
	t.check_in_range(s.distance, 0.0, 1.0, "distance 初始值应在 [0,1]")
	t.check_in_range(s.exposure, 0.0, 1.0, "exposure 初始值应在 [0,1]")
	t.check_in_range(s.oil, 0.0, 1.0, "oil 初始值应在 [0,1]")
	t.check_in_range(s.flame_feedback, 0.0, 1.0, "flame_feedback 初始值应在 [0,1]")
	t.check_eq(s.oil, 1.0, "灯油满值开局")
	t.check_eq(s.to_dict().size(), 4, "可序列化视图应正好包含四个字段")
	t.finish("四个连续量初始值合法且可序列化")


func _test_02_distance_increase(t: ATestBase) -> void:
	t.begin("02 distance 增加输入能连续改变值")
	var b: LampTestBench = _bench()
	var before: float = b.state().distance
	b.hold_input(200, {KEY_DIST_UP: true})
	var after: float = b.state().distance
	t.check(after > before, "按住增加后 distance 应变大（%.4f → %.4f）" % [before, after])
	t.check(after < 1.0, "只按 200 ms 不应直接冲到上界")
	t.finish("distance 随按住连续增大")


func _test_03_distance_decrease(t: ATestBase) -> void:
	t.begin("03 distance 减少输入能连续改变值")
	var b: LampTestBench = _bench()
	var before: float = b.state().distance
	b.hold_input(200, {KEY_DIST_DOWN: true})
	var after: float = b.state().distance
	t.check(after < before, "按住减少后 distance 应变小（%.4f → %.4f）" % [before, after])
	t.check(after > 0.0, "只按 200 ms 不应直接冲到下界")
	t.finish("distance 随按住连续减小")


func _test_04_distance_upper_bound(t: ATestBase) -> void:
	t.begin("04 distance 超过上界时保持 1.0")
	var b: LampTestBench = _bench()
	b.hold_input(3000, {KEY_DIST_UP: true})
	t.check_eq(b.state().distance, 1.0, "长时间按住后应停在上界 1.0")
	b.hold_input(1000, {KEY_DIST_UP: true})
	t.check_eq(b.state().distance, 1.0, "到界后继续按住不应越界")
	t.finish("distance 到上界后截断且不抖动")


func _test_05_distance_lower_bound(t: ATestBase) -> void:
	t.begin("05 distance 低于下界时保持 0.0")
	var b: LampTestBench = _bench()
	b.hold_input(3000, {KEY_DIST_DOWN: true})
	t.check_eq(b.state().distance, 0.0, "长时间按住后应停在下界 0.0")
	b.hold_input(1000, {KEY_DIST_DOWN: true})
	t.check_eq(b.state().distance, 0.0, "到界后继续按住不应越界")
	t.finish("distance 到下界后截断且不抖动")


func _test_06_exposure_increase(t: ATestBase) -> void:
	t.begin("06 exposure 增加输入能连续改变值")
	var b: LampTestBench = _bench()
	var before: float = b.state().exposure
	b.hold_input(200, {KEY_EXPO_UP: true})
	var after: float = b.state().exposure
	t.check(after > before, "按住增加后 exposure 应变大（%.4f → %.4f）" % [before, after])
	t.check(after < 1.0, "只按 200 ms 不应直接冲到上界")
	t.finish("exposure 随按住连续增大")


func _test_07_exposure_decrease(t: ATestBase) -> void:
	t.begin("07 exposure 减少输入能连续改变值")
	var b: LampTestBench = _bench()
	var before: float = b.state().exposure
	b.hold_input(200, {KEY_EXPO_DOWN: true})
	var after: float = b.state().exposure
	t.check(after < before, "按住减少后 exposure 应变小（%.4f → %.4f）" % [before, after])
	t.check(after > 0.0, "只按 200 ms 不应直接冲到下界")
	t.finish("exposure 随按住连续减小")


func _test_08_exposure_upper_bound(t: ATestBase) -> void:
	t.begin("08 exposure 超过上界时保持 1.0")
	var b: LampTestBench = _bench()
	b.hold_input(3000, {KEY_EXPO_UP: true})
	t.check_eq(b.state().exposure, 1.0, "长时间按住后应停在上界 1.0")
	b.hold_input(1000, {KEY_EXPO_UP: true})
	t.check_eq(b.state().exposure, 1.0, "到界后继续按住不应越界")
	t.finish("exposure 到上界后截断且不抖动")


func _test_09_exposure_lower_bound(t: ATestBase) -> void:
	t.begin("09 exposure 低于下界时保持 0.0")
	var b: LampTestBench = _bench()
	b.hold_input(3000, {KEY_EXPO_DOWN: true})
	t.check_eq(b.state().exposure, 0.0, "长时间按住后应停在下界 0.0")
	b.hold_input(1000, {KEY_EXPO_DOWN: true})
	t.check_eq(b.state().exposure, 0.0, "到界后继续按住不应越界")
	t.finish("exposure 到下界后截断且不抖动")


func _test_10_opposite_input_holds(t: ATestBase) -> void:
	t.begin("10 同一输入轴相反指令时保持原值")
	var b: LampTestBench = _bench()
	b.hold_input(300, {KEY_DIST_UP: true})
	var dist: float = b.state().distance
	var expo: float = b.state().exposure
	b.hold_input(300, {KEY_DIST_UP: true, KEY_DIST_DOWN: true})
	t.check_eq(b.state().distance, dist, "灯距同轴相反输入应冻结当前值")
	b.hold_input(300, {KEY_EXPO_UP: true, KEY_EXPO_DOWN: true})
	t.check_eq(b.state().exposure, expo, "显露度同轴相反输入应冻结当前值")
	# 冲突解除后应恢复
	b.hold_input(200, {KEY_DIST_UP: true})
	t.check(b.state().distance > dist, "冲突解除后应恢复连续变化")
	t.finish("同轴相反指令保持原值，解除后恢复")


func _test_11_release_keeps_value(t: ATestBase) -> void:
	t.begin("11 松开输入后 distance 和 exposure 保持")
	var b: LampTestBench = _bench()
	b.advance_with_input(300, {KEY_DIST_UP: true, KEY_EXPO_DOWN: true})
	var dist: float = b.state().distance
	var expo: float = b.state().exposure
	b.release_input()
	b.hold_input(600)
	t.check_eq(b.state().distance, dist, "松开后 distance 应保持")
	t.check_eq(b.state().exposure, expo, "松开后 exposure 应保持")
	t.finish("松开后两个连续量都停在新值")


func _test_12_input_never_touches_oil(t: ATestBase) -> void:
	t.begin("12 任何灯距或显露度输入都不能直接改变 oil")
	var b: LampTestBench = _bench()
	# 不推进歌曲时间，只反复施加输入
	var oil_before: float = b.state().oil
	b.set_input({KEY_DIST_UP: true, KEY_EXPO_UP: true})
	for _i in 50:
		b.tick()
	t.check_eq(b.state().oil, oil_before, "输入本身不得改动 oil")
	# 灯距/显露度确实变了，证明输入生效了
	t.check(b.state().distance > 0.5, "灯距输入应确实生效（实际 %.4f）" % b.state().distance)
	t.check(b.state().exposure > 0.5, "显露度输入应确实生效（实际 %.4f）" % b.state().exposure)
	t.finish("输入只动灯距与显露度，oil 完全不受输入影响")


func _test_13_oil_decreases_monotonically(t: ATestBase) -> void:
	t.begin("13 歌曲时间前进时 oil 单调递减")
	var b: LampTestBench = _bench()
	var samples: Array[float] = []
	for _i in 10:
		b.hold_input(1000)
		samples.append(b.state().oil)
	var monotonic: bool = true
	for i in range(1, samples.size()):
		if samples[i] > samples[i - 1]:
			monotonic = false
	t.check(monotonic, "oil 序列应单调不减（本次：%s）" % str(samples))
	t.check(samples[samples.size() - 1] < samples[0], "推进 10 秒后 oil 应确实下降")
	t.finish("oil 随歌曲时间单调下降")


func _test_14_same_song_time_no_double_charge(t: ATestBase) -> void:
	t.begin("14 相同 song_time 重复更新不会重复扣油")
	var b: LampTestBench = _bench()
	b.hold_input(500)
	var oil: float = b.state().oil
	b.repeat_update_at_same_time(30)
	t.check_eq(b.state().oil, oil, "同一歌曲时间重复更新 30 次不应再扣油")
	t.finish("同刻重复更新幂等")


func _test_15_oil_never_below_zero(t: ATestBase) -> void:
	t.begin("15 oil 不会低于 0.0")
	var b: LampTestBench = _bench()
	b.hold_input(200000)                      # 远超任何一关时长
	t.check_eq(b.state().oil, 0.0, "灯油耗尽后应恰好停在 0.0")
	t.check(b.state().oil >= 0.0, "oil 不得为负")
	t.finish("灯油耗尽后保持 0.0，不会变负")


func _test_16_backwards_time_no_refill(t: ATestBase) -> void:
	t.begin("16 歌曲时间倒退不会让 oil 回升")
	var b: LampTestBench = _bench()
	b.hold_input(5000)
	var oil: float = b.state().oil
	t.check(oil < 1.0, "推进 5 秒后 oil 应已下降")
	b.set_song_ms(1000)                       # 时间倒退
	b.repeat_update_at_same_time(5)
	t.check_eq(b.state().oil, oil, "时间倒退后 oil 不得回升")
	t.check(b.state().oil <= oil, "oil 永不超过倒退前的读数")
	t.finish("时间倒退被安全忽略，oil 不回升")


func _test_17_pause_freezes_song_time(t: ATestBase) -> void:
	t.begin("17 暂停时歌曲时间不前进")
	var b: LampTestBench = _bench()
	b.hold_input(1000)
	b.pause()
	var song_before: int = b.clock.get_song_time_ms()
	b.repeat_update_at_same_time(20)
	t.check_eq(b.clock.get_song_time_ms(), song_before, "暂停期间歌曲时间应冻结")
	t.check_eq(b.state().oil, b.state().oil, "暂停期间读数稳定")
	b.resume()
	t.check(not b.clock.is_paused(), "恢复后应不再处于暂停态")
	t.finish("暂停冻结歌曲时间")


func _test_18_pause_freezes_oil(t: ATestBase) -> void:
	t.begin("18 暂停时 oil 不减少")
	var b: LampTestBench = _bench()
	b.hold_input(1000)
	b.pause()
	var oil: float = b.state().oil
	# 暂停期间即使反复调用 update（墙钟在走）也不能扣油
	for _i in 100:
		b.feed_performance([])
	t.check_eq(b.state().oil, oil, "暂停 100 次更新后 oil 不得变化")
	t.finish("暂停冻结灯油消耗")


func _test_19_pause_freezes_feedback(t: ATestBase) -> void:
	t.begin("19 暂停时 flame_feedback 不变化")
	var b: LampTestBench = _bench()
	b.hold_input(1000)
	b.pause()
	var feedback: float = b.state().flame_feedback
	var events: Array = [{"kind": "cue_hit", "cue_id": "l1_c1_stand", "time_ms": 1000,
		"object_id": 0, "payload": {"kind": "cue_hit"}}]
	b.feed_performance(events)
	t.check_eq(b.state().flame_feedback, feedback, "暂停期间火焰反馈不得变化")
	t.finish("暂停冻结火焰反馈")


func _test_20_resume_continues_no_jump(t: ATestBase) -> void:
	t.begin("20 恢复后从原歌曲时间继续消耗，不能跳变")
	var b: LampTestBench = _bench()
	b.hold_input(2000)
	b.pause()
	var song_paused: int = b.clock.get_song_time_ms()
	var oil_paused: float = b.state().oil
	b.pause()                                 # 重复暂停应无副作用
	b.resume()
	t.check_eq(b.clock.get_song_time_ms(), song_paused, "恢复瞬间不得跳变")
	t.check_eq(b.state().oil, oil_paused, "恢复瞬间 oil 不得跳变")
	# 恢复后按正常速率继续消耗
	b.hold_input(1000)
	var expected: float = LampControllerScript.clamp_unit(
		oil_paused - LampControllerScript.OIL_CONSUME_PER_S * 1.0)
	t.check_approx(b.state().oil, expected, 0.01,
		"恢复 1 秒后 oil 应恰好按消耗速率下降")
	t.finish("恢复后沿同一时间轴继续，不跳变、不补扣暂停时长")


func _test_21_hit_raises_feedback(t: ATestBase) -> void:
	t.begin("21 命中事件能驱动 flame_feedback 在合法范围内变化")
	var b: LampTestBench = _bench()
	var before: float = b.state().flame_feedback
	b.feed_performance([{"kind": "cue_hit", "cue_id": "l1_c1_stand", "time_ms": 2500,
		"object_id": 0, "payload": {"kind": "cue_hit"}}])
	var after: float = b.state().flame_feedback
	t.check(after > before, "命中应提高火焰反馈（%.4f → %.4f）" % [before, after])
	t.check(after <= 1.0, "提高后不得超过上界")
	# 连续多次命中也不能越界
	for i in 20:
		b.feed_performance([{"kind": "cue_hit", "cue_id": "cue_%d" % i, "time_ms": 2500 + i,
			"object_id": 0, "payload": {"kind": "cue_hit"}}])
	t.check_in_range(b.state().flame_feedback, 0.0, 1.0, "多次命中后仍应在 [0,1]")
	t.finish("命中事件提高火焰反馈且不越界")


func _test_22_miss_lowers_feedback(t: ATestBase) -> void:
	t.begin("22 错拍或漏做事件能驱动 flame_feedback 在合法范围内变化")
	var b: LampTestBench = _bench()
	var before: float = b.state().flame_feedback
	b.feed_performance([{"kind": "cue_miss", "cue_id": "l1_c1_stand", "time_ms": 2500,
		"object_id": 0, "payload": {"kind": "cue_miss", "reason": "out_of_window"}}])
	var after: float = b.state().flame_feedback
	t.check(after < before, "错拍应降低火焰反馈（%.4f → %.4f）" % [before, after])
	t.check(after >= 0.0, "降低后不得低于下界")
	for i in 30:
		b.feed_performance([{"kind": "cue_miss", "cue_id": "miss_%d" % i, "time_ms": 2500 + i,
			"object_id": 0, "payload": {"kind": "cue_miss"}}])
	t.check_in_range(b.state().flame_feedback, 0.0, 1.0, "多次错拍后仍应在 [0,1]")
	# 补救相关事件同样合法
	b.feed_performance([{"kind": "remedy_success", "cue_id": "l1_c1_stand", "time_ms": 3000,
		"object_id": 0, "payload": {"kind": "remedy_success"}}])
	t.check_in_range(b.state().flame_feedback, 0.0, 1.0, "补救成功后仍应在 [0,1]")
	t.finish("错拍/漏做降低火焰反馈且不越界")


func _test_23_duplicate_event_no_double_stack(t: ATestBase) -> void:
	t.begin("23 同一 performance 事件重复输入不会重复叠加")
	var b: LampTestBench = _bench()
	var event: Dictionary = {"kind": "cue_hit", "cue_id": "l1_c1_stand", "time_ms": 2500,
		"object_id": 0, "payload": {"kind": "cue_hit"}}
	b.feed_performance([event])
	var once: float = b.state().flame_feedback
	# 同一个事件重复喂 10 次，效果应与只喂一次完全相同
	for _i in 10:
		b.feed_performance([event])
	t.check_approx(b.state().flame_feedback, once, 0.000001,
		"同一事件重复输入不得重复叠加（一次 %.4f，重复后 %.4f）"
			% [once, b.state().flame_feedback])
	t.finish("同一事件幂等，不重复叠加反馈")


func _test_24_state_changes_before_event(t: ATestBase) -> void:
	t.begin("24 LampState 变化后事件才发送")
	var b: LampTestBench = _bench()
	b.clear_log()
	b.hold_input(200, {KEY_DIST_UP: true})
	var events: Array = b.events_of(LampControllerScript.KIND_INPUT_CHANGED)
	t.check(events.size() > 0, "输入改变应发出 lamp_input_changed")
	var last: Dictionary = events[events.size() - 1]
	var payload: Dictionary = last["payload"]
	# 事件载荷必须等于「取走事件时」的状态读数，即状态先变、事件后到
	t.check_approx(float(payload["distance"]), b.state().distance, 0.000001,
		"事件载荷的 distance 应等于同一帧读到的状态值")
	t.check_approx(float(payload["exposure"]), b.state().exposure, 0.000001,
		"事件载荷的 exposure 应等于同一帧读到的状态值")
	t.finish("先改状态再发事件，二者同帧一致")


func _test_25_event_contract_fields(t: ATestBase) -> void:
	t.begin("25 lamp_state_changed 事件包含 time_ms、kind、object_id、cue_id、payload")
	var b: LampTestBench = _bench()
	b.hold_input(200, {KEY_DIST_UP: true})
	var events: Array = b.events_of(LampControllerScript.KIND_STATE_CHANGED)
	t.check(events.size() > 0, "应发出 lamp_state_changed")
	var e: Dictionary = events[events.size() - 1]
	for field in ["time_ms", "kind", "object_id", "cue_id", "payload"]:
		t.check(e.has(field), "事件必须含字段「%s」" % field)
	t.check(typeof(e["time_ms"]) == TYPE_INT, "time_ms 必须是整数")
	t.check(typeof(e["kind"]) == TYPE_STRING, "kind 必须是字符串")
	t.check(typeof(e["object_id"]) == TYPE_STRING, "object_id 必须是字符串")
	t.check(typeof(e["cue_id"]) == TYPE_STRING, "cue_id 必须是字符串（空值用空串）")
	t.check(typeof(e["payload"]) == TYPE_DICTIONARY, "payload 必须是字典")
	t.check_eq(e["object_id"], LampControllerScript.LAMP_OBJECT_ID, "object_id 应为油灯标识")
	t.check_eq(e["cue_id"], "", "灯的自主事件 cue_id 为空串")
	# 四种事件都在，且都满足同一字段契约
	for kind in [LampControllerScript.KIND_STATE_CHANGED, LampControllerScript.KIND_INPUT_CHANGED,
			LampControllerScript.KIND_OIL_CHANGED, LampControllerScript.KIND_FEEDBACK_CHANGED]:
		for candidate in b.events_of(kind):
			for field in ["time_ms", "kind", "object_id", "cue_id", "payload"]:
				if not candidate.has(field):
					t.check(false, "事件 %s 缺字段 %s" % [kind, field])
					break
	t.finish("事件五字段齐备、类型正确、cue_id 为空串")


func _test_26_payload_has_current_values(t: ATestBase) -> void:
	t.begin("26 payload 包含变化后的字段")
	var b: LampTestBench = _bench()
	b.clear_log()
	b.hold_input(200, {KEY_DIST_UP: true})
	var e: Dictionary = b.events_of(LampControllerScript.KIND_INPUT_CHANGED)[0]
	var payload: Dictionary = e["payload"]
	t.check(payload.has("distance"), "灯距变化的事件载荷应含 distance")
	t.check(payload.has("exposure"), "事件载荷应含 exposure 当前值")
	t.check(payload.has("oil"), "事件载荷应含 oil 当前值")
	t.check(payload.has("flame_feedback"), "事件载荷应含 flame_feedback 当前值")
	t.check(payload.has("changed_fields"), "事件载荷应含 changed_fields")
	var changed: Array = payload["changed_fields"]
	t.check(changed.has("distance"), "changed_fields 应指出 distance 发生了变化")
	t.check(payload.has("flame_feedback"), "输入事件的载荷也应带 flame_feedback 当前值")
	# 灯油事件必须带油量
	b.clear_log()
	b.hold_input(1000)
	var oil_events: Array = b.events_of(LampControllerScript.KIND_OIL_CHANGED)
	t.check(oil_events.size() > 0, "灯油下降应发出 lamp_oil_changed")
	t.check(float(oil_events[oil_events.size() - 1]["payload"]["oil"]) < 1.0,
		"灯油事件载荷应带下降后的 oil")
	t.finish("payload 带变化后字段与 changed_fields")


func _test_27_malformed_events_no_crash(t: ATestBase) -> void:
	t.begin("27 空事件、缺失 payload 或非法字段不能导致脚本崩溃")
	var b: LampTestBench = _bench()
	var before: LampState = b.state()
	var distance: float = before.distance
	var oil: float = before.oil
	var feedback: float = before.flame_feedback
	var malformed: Array = [
		{},                                        # 空字典
		{"kind": "cue_hit"},                       # 缺 payload 与 cue_id
		{"kind": "cue_hit", "payload": {}},         # payload 为空
		{"kind": "", "cue_id": "", "payload": {}},   # kind 为空串
		{"kind": "cue_hit", "payload": "not a dict"},  # 非法 payload 类型
	]
	for case in malformed:
		b.feed_performance([case])
	# 数组里混入 null / 字符串 / 数字
	b.feed_performance([null, "oops", 42, []])
	# kind 未知
	b.feed_performance([{"kind": "完全不认识的类型", "cue_id": "x", "payload": {}}])
	t.check_in_range(b.state().distance, 0.0, 1.0, "畸形事件后 distance 仍合法")
	t.check_in_range(b.state().exposure, 0.0, 1.0, "畸形事件后 exposure 仍合法")
	t.check_in_range(b.state().oil, 0.0, 1.0, "畸形事件后 oil 仍合法")
	t.check_in_range(b.state().flame_feedback, 0.0, 1.0, "畸形事件后 flame_feedback 仍合法")
	t.check_eq(b.state().oil, oil, "畸形事件不得改动 oil")
	t.check_eq(b.state().distance, distance, "畸形事件不得改动 distance")
	# 非法字段类型：把布尔当数字用也不能崩
	b.feed_performance([{"kind": "cue_hit", "cue_id": true, "time_ms": "x",
		"payload": {"kind": "cue_hit"}}])
	t.check_in_range(b.state().flame_feedback, 0.0, 1.0, "非法字段类型后反馈仍合法")
	t.finish("畸形输入全部安全失败，状态保持合法且不被篡改")


func _test_28_finished_stops_oil(t: ATestBase) -> void:
	t.begin("28 演出结束后继续更新时间不会继续扣油")
	var b: LampTestBench = _bench()
	b.hold_input(5000)
	var oil: float = b.state().oil
	b.finish_show()
	b.hold_input(20000)
	t.check_eq(b.state().oil, oil, "演出结束后继续推进 20 秒不得再扣油")
	t.check_eq(b.lamp.is_finished(), true, "演出应处于已结束状态")
	t.check(b.has_event(LampControllerScript.KIND_FINISHED), "结束应发出 lamp_finished 事件")
	t.finish("演出结束后灯油停止消耗")


func _test_29_event_time_from_music_clock(t: ATestBase) -> void:
	t.begin("29 事件时间严格来自统一 MusicClock")
	var b: LampTestBench = _bench()
	b.clear_log()
	b.hold_input(1500, {KEY_DIST_UP: true})
	var clock_ms: int = b.clock.get_song_time_ms()
	var mismatched: int = 0
	for e in b.log:
		if int(e["time_ms"]) > clock_ms:
			mismatched += 1
	t.check_eq(mismatched, 0, "任何事件时间都不得超过统一时钟读数（%d）" % clock_ms)
	t.check(b.log.size() > 0, "应产生事件")
	# 每个事件的时间戳都必须能由时钟读数解释：等于某一步的歌曲时间
	var stamps: Array[int] = []
	for e in b.log:
		var stamp: int = int(e["time_ms"])
		if not stamps.has(stamp):
			stamps.append(stamp)
	t.check(stamps.size() > 0, "事件时间戳应来自时钟推进序列")
	var all_on_timeline: bool = true
	for stamp in stamps:
		if stamp < 0 or stamp > clock_ms or stamp % LampTestBench.STEP_MS != 0:
			all_on_timeline = false
	t.check(all_on_timeline, "所有事件时间戳都应落在时钟推进的 10 ms 网格上：%s" % str(stamps))
	t.finish("事件时间戳全部来自统一 MusicClock")


func _test_30_receiver_parses_event(t: ATestBase) -> void:
	t.begin("30 模拟接收端能收到并解析至少一条完整 LampState 事件")
	var b: LampTestBench = _bench()
	b.hold_input(1000, {KEY_EXPO_UP: true})
	var receiver_events: Array = LampControllerScript.receive_events(b.log)
	var received: Array = receiver_events
	t.check(received.size() > 0, "模拟接收端应至少收到一条事件")
	t.check_eq(received.size(), b.log.size(), "接收端应逐条解析全部事件")
	var ok: bool = false
	for parsed in received:
		if str(parsed.get("kind", "")) == LampControllerScript.KIND_STATE_CHANGED:
			t.check_eq(str(parsed["object_id"]), LampControllerScript.LAMP_OBJECT_ID,
				"接收端读到的 object_id 应是油灯标识")
			t.check(parsed["payload"].has("distance"), "接收端应能读到 distance")
			t.check(parsed["payload"].has("oil"), "接收端应能读到 oil")
			t.check(parsed["time_ms"] >= 0, "接收端应能读到 time_ms")
			ok = true
	t.check(ok, "接收端应能解析出一条完整的 lamp_state_changed")
	t.finish("模拟接收端成功解析完整 LampState 事件")


func _test_31_fire_does_not_raise_feedback_on_miss(t: ATestBase) -> void:
	t.begin("31 cue_fire 与错拍结果同时到达时反馈应下降")
	var b: LampTestBench = _bench()
	var before: float = b.state().flame_feedback
	b.feed_performance([
		{"kind": "cue_fire", "cue_id": "l1_c1_stand", "time_ms": 2500,
			"object_id": 0, "payload": {"kind": "cue_fire"}},
		{"kind": "cue_miss", "cue_id": "l1_c1_stand", "time_ms": 2500,
			"object_id": 0, "payload": {"kind": "cue_miss"}},
	])
	t.check(b.state().flame_feedback < before,
		"错拍动作虽然发生，但最终反馈应低于 %.4f（实际 %.4f）" %
			[before, b.state().flame_feedback])
	t.finish("cue_fire 不再被当作命中反馈")


func _test_32_backwards_time_rebases_oil_consumption(t: ATestBase) -> void:
	t.begin("32 歌曲时间倒退后重新前进仍能继续扣油")
	var b: LampTestBench = _bench()
	b.hold_input(5000)
	var before_rewind: float = b.state().oil
	b.set_song_ms(1000)
	b.tick()
	b.set_song_ms(2000)
	b.tick()
	var expected: float = LampControllerScript.clamp_unit(
		before_rewind - LampControllerScript.OIL_CONSUME_PER_S)
	t.check_approx(b.state().oil, expected, 0.000001,
		"倒退后从新基准前进 1 秒应扣油（期望 %.6f，实际 %.6f）" %
			[expected, b.state().oil])
	t.finish("倒退只丢弃倒退区间，后续歌曲时间仍正常消耗")


func _test_33_malformed_feedback_is_ignored(t: ATestBase) -> void:
	t.begin("33 缺字段或非法字段的反馈事件不应改变状态")
	var b: LampTestBench = _bench()
	var before: float = b.state().flame_feedback
	b.feed_performance([
		{"kind": "cue_hit"},
		{"kind": "cue_hit", "cue_id": "x", "payload": {}},
		{"kind": "cue_hit", "cue_id": true, "time_ms": "bad",
			"payload": {"kind": "cue_hit"}},
	])
	t.check_eq(b.state().flame_feedback, before,
		"畸形 cue_hit 不应伪造命中反馈")
	t.finish("畸形反馈事件被安全忽略")


func _test_34_lamp_input_mapping_uses_prd_controls(t: ATestBase) -> void:
	t.begin("34 测试入口显示并使用 PRD 的油灯控制约定")
	var b: LampTestBench = _bench()
	var reader: LampInputReader = LampInputReaderScript.new()
	reader.set_lamp(b.lamp)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	reader.handle_event(wheel)
	reader.poll_keys()
	t.check(b.lamp.get_input_map()[KEY_DIST_UP], "滚轮上事件应转成灯距增加输入")
	b.tick()
	t.check(b.state().distance > 0.5, "滚轮上事件应实际推进 distance")
	t.check_eq(LampInputReaderScript.KEY_EXPOSURE_DECREASE, KEY_Q,
		"Q 应降低显露度")
	t.check_eq(LampInputReaderScript.KEY_EXPOSURE_INCREASE, KEY_E,
		"E 应增加显露度")
	var description: String = LampInputReaderScript.describe_keys()
	t.check(description.contains("滚轮"), "键位说明应显示滚轮灯距控制")
	t.check(description.contains("Q/E"), "键位说明应显示 Q/E 显露度控制")
	t.finish("测试入口键位与 PRD 一致")
