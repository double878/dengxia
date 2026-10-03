extends RefCounted
class_name LampProbe
## 切片 5 的图形环境脚本化实测。
##
## 验证者无法向运行中的窗口注入真实键鼠事件，因此本探针在**真实渲染进程**里
## 用与游玩完全相同的公开接口（LampController 的输入快照与 update）走完整链路，
## 并打印可核对数值。它证明的是「代码在这台机器的真实图形进程里跑出这些数值」，
## 不能替代人去按真实按键、听音频、看画面。
##
## 时间由探针显式注入（MusicClock.set_free_time_ms），因此结果确定、不依赖帧率。

const LampControllerScript := preload("res://scripts/a/lamp_controller.gd")

const KEY_DIST_UP: String = "distance_increase"
const KEY_DIST_DOWN: String = "distance_decrease"
const KEY_EXPO_UP: String = "exposure_increase"
const KEY_EXPO_DOWN: String = "exposure_decrease"

var _failures: int = 0
var _checks: int = 0


func run(harness: LampHarness) -> int:
	print("")
	print("======== 切片 5 图形环境脚本化实测（真实渲染进程）========")
	var lamp: LampController = harness.lamp
	var clock: MusicClock = harness.clock

	_section("1 按住灯距输入，distance 连续变化并停在边界")
	var samples: Array[float] = []
	lamp.set_input_map({KEY_DIST_UP: true})
	for _i in 6:
		clock.set_free_time_ms(clock.get_song_time_ms() + 100)
		lamp.update(0.1, [])
		samples.append(lamp.lamp.distance)
	_expect_true(_is_monotonic(samples), "灯距连续单调增大 %s" % _fmt(samples))
	for _i in 200:
		clock.set_free_time_ms(clock.get_song_time_ms() + 100)
		lamp.update(0.1, [])
	_expect_eq(lamp.lamp.distance, 1.0, "长时间按住后停在上界 distance=1.0")

	_section("2 松开后 distance 保持")
	var held: float = lamp.lamp.distance
	lamp.set_input_map({})
	clock.set_free_time_ms(clock.get_song_time_ms() + 2000)
	lamp.update(0.1, [])
	_expect_eq(lamp.lamp.distance, held, "松开 2 秒后 distance 仍为 %.4f" % held)

	_section("3 按住显露度输入，exposure 连续变化并停在边界")
	lamp.set_input_map({KEY_EXPO_DOWN: true})
	var expo_samples: Array[float] = []
	for _i in 6:
		clock.set_free_time_ms(clock.get_song_time_ms() + 100)
		lamp.update(0.1, [])
		expo_samples.append(lamp.lamp.exposure)
	_expect_true(_is_monotonic(expo_samples), "显露度连续单调减小 %s" % _fmt(expo_samples))
	for _i in 200:
		clock.set_free_time_ms(clock.get_song_time_ms() + 100)
		lamp.update(0.1, [])
	_expect_eq(lamp.lamp.exposure, 0.0, "长时间按住后停在下界 exposure=0.0")
	lamp.set_input_map({KEY_EXPO_UP: true})
	for _i in 100:
		clock.set_free_time_ms(clock.get_song_time_ms() + 100)
		lamp.update(0.1, [])
	_expect_eq(lamp.lamp.exposure, 1.0, "反向按住后停在上界 exposure=1.0")

	_section("4 输入变化不会直接改变 oil")
	var oil_before: float = lamp.lamp.oil
	lamp.set_input_map({KEY_DIST_DOWN: true, KEY_EXPO_DOWN: true})
	for _i in 100:
		lamp.update(0.1, [])            # 不推进歌曲时间
	_expect_eq(lamp.lamp.oil, oil_before,
		"同刻 100 次输入后 oil 未变（%.6f）" % oil_before)

	_section("5 歌曲时间推进时 oil 下降")
	lamp.set_input_map({})
	var oil_series: Array[float] = []
	for _i in 5:
		clock.set_free_time_ms(clock.get_song_time_ms() + 1000)
		lamp.update(1.0, [])
		oil_series.append(lamp.lamp.oil)
	_expect_true(_is_monotonic(oil_series), "oil 单调下降 %s" % _fmt(oil_series))
	_expect_true(oil_series[oil_series.size() - 1] < oil_series[0], "推进 5 秒后 oil 确实下降")

	_section("6 暂停后歌曲时间和 oil 冻结")
	clock.pause()
	var song_paused: int = clock.get_song_time_ms()
	var oil_paused: float = lamp.lamp.oil
	for _i in 60:
		lamp.update(1.0, [])            # 模拟墙钟空转
	_expect_eq(clock.get_song_time_ms(), song_paused, "暂停期间歌曲时间冻结在 %d ms" % song_paused)
	_expect_eq(lamp.lamp.oil, oil_paused, "暂停期间 oil 冻结在 %.6f" % oil_paused)

	_section("7 恢复后从原时间继续")
	clock.resume()
	_expect_eq(clock.get_song_time_ms(), song_paused, "恢复瞬间歌曲时间不跳变")
	_expect_eq(lamp.lamp.oil, oil_paused, "恢复瞬间 oil 不跳变")
	# 恢复后按 100 ms 逐步推进 1 秒：消耗必须由歌曲时间的**增量**驱动，
	# 不能靠一次跳变大步跨过去（跳变会被当作暂停时长而不计消耗）。
	lamp.set_input_map({})
	for _i in 10:
		clock.set_free_time_ms(clock.get_song_time_ms() + 100)
		lamp.update(0.1, [])
	var expected_oil: float = LampControllerScript.clamp_unit(
		oil_paused - LampControllerScript.OIL_CONSUME_PER_S)
	_expect_true(absf(lamp.lamp.oil - expected_oil) <= 0.002,
		"恢复后推进 1 秒 oil=%.6f，符合消耗速率（期望 ≈%.6f）" % [lamp.lamp.oil, expected_oil])

	_section("8 命中与错拍事件驱动 flame_feedback")
	var fb_before: float = lamp.lamp.flame_feedback
	lamp.update(0.0, [_event("cue_hit", "probe_hit", clock.get_song_time_ms())])
	var fb_hit: float = lamp.lamp.flame_feedback
	_expect_true(fb_hit > fb_before, "命中后 flame_feedback 上升（%.4f → %.4f）" % [fb_before, fb_hit])
	lamp.update(0.0, [_event("cue_miss", "probe_miss", clock.get_song_time_ms())])
	var fb_miss: float = lamp.lamp.flame_feedback
	_expect_true(fb_miss < fb_hit, "错拍后 flame_feedback 下降（%.4f → %.4f）" % [fb_hit, fb_miss])
	# 同一事件重复喂入不得重复叠加
	var fb_once: float = lamp.lamp.flame_feedback
	var duplicate: Dictionary = _event("cue_miss", "probe_miss", clock.get_song_time_ms())
	for _i in 10:
		lamp.update(0.0, [duplicate])
	_expect_eq(lamp.lamp.flame_feedback, fb_once, "同一事件重复 10 次不重复叠加")
	_expect_true(lamp.lamp.is_in_range(), "四个连续量全部落在 [0,1]")

	_section("9 事件面板字段（time_ms / object_id / cue_id / payload）")
	# 逐步推进 1 秒使灯油下降；事件由 update() 直接返回（它取走即清空队列）。
	var events: Array[Dictionary] = []
	for _i in 10:
		clock.set_free_time_ms(clock.get_song_time_ms() + 100)
		events.append_array(lamp.update(0.1, []))
	_expect_true(events.size() > 0, "产生了 %d 条事件" % events.size())
	var receiver: Array = LampControllerScript.receive_events(events)
	_expect_eq(receiver.size(), events.size(), "模拟接收端逐条解析成功")
	_expect_true(lamp.take_events().is_empty(), "事件被取走后队列清空，不会重复记录")
	if not events.is_empty():
		var e: Dictionary = events[events.size() - 1]
		var complete: bool = e.has("time_ms") and e.has("kind") and e.has("object_id") \
			and e.has("cue_id") and e.has("payload")
		_expect_true(complete, "事件五字段齐备：t=%d kind=%s obj=%s cue=%s" % [
			int(e["time_ms"]), str(e["kind"]), str(e["object_id"]), str(e["cue_id"])])
		_expect_true(typeof(e["object_id"]) == TYPE_STRING,
			"object_id 为字符串「%s」" % str(e["object_id"]))
		var payload: Dictionary = e["payload"]
		_expect_true(payload.has("distance") and payload.has("exposure") \
			and payload.has("oil") and payload.has("flame_feedback"),
			"payload 带四个 LampState 字段：distance=%.3f exposure=%.3f oil=%.4f fb=%.3f" % [
				float(payload["distance"]), float(payload["exposure"]),
				float(payload["oil"]), float(payload["flame_feedback"])])

	_section("10 结束演出后不再消耗灯油")
	var oil_finished: float = lamp.lamp.oil
	lamp.finish_show()
	clock.set_free_time_ms(clock.get_song_time_ms() + 20000)
	lamp.update(1.0, [])
	_expect_eq(lamp.lamp.oil, oil_finished, "结束后推进 20 秒 oil 不变（%.6f）" % oil_finished)
	_expect_true(lamp.is_finished(), "演出处于已结束状态")
	# 结束事件必须能被接收端读到（放在最后，避免提前结束使后续检查不再产生事件）
	var finish_events: Array[Dictionary] = lamp.take_events()
	var finish_ok: bool = false
	for e in finish_events:
		if str(e["kind"]) == LampControllerScript.KIND_FINISHED:
			finish_ok = true
	_expect_true(finish_ok, "结束演出发出 lamp_finished 并被读出")

	print("")
	print("======== 探针结论：%d 项检查，%d 项失败 ========" % [_checks, _failures])
	return _failures


func _event(kind: String, cue_id: String, time_ms: int) -> Dictionary:
	return {"time_ms": time_ms, "kind": kind, "object_id": 0, "cue_id": cue_id,
		"payload": {"kind": kind}}


func _section(title: String) -> void:
	print("")
	print("-- %s" % title)


func _expect_true(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("   [通过] %s" % message)
	else:
		_failures += 1
		print("   [失败] %s" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual == expected:
		print("   [通过] %s" % message)
	else:
		_failures += 1
		print("   [失败] %s（期望 %s，实际 %s）" % [message, str(expected), str(actual)])


func _is_monotonic(values: Array[float]) -> bool:
	if values.size() < 2:
		return true
	var increasing: bool = values[1] > values[0]
	for i in range(1, values.size()):
		if increasing and values[i] < values[i - 1]:
			return false
		if not increasing and values[i] > values[i - 1]:
			return false
	return true


func _fmt(values: Array[float]) -> String:
	var parts: Array[String] = []
	for v in values:
		parts.append("%.4f" % v)
	return "[%s]" % ", ".join(parts)
