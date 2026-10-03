extends RefCounted
class_name Level1AProbe
## 第一关 A 侧图形进程探针。使用同一运行宿主，改用自由时钟快速跑完整时间线。

var _checks: int = 0
var _failures: int = 0


func run(harness: Object) -> int:
	print("")
	print("======== 切片 6 第一关 A 侧图形环境探针 ========")
	harness.metronome_enabled = false
	harness.metronome.stop()
	harness.clock.set_player(null, StageDef.LEVEL1_BPM)
	harness.clock.start()
	_expect(harness.runtime != null, "Level1Runtime 已建立")
	_expect(harness.runtime.stage_def.duration_ms == 35000, "第一关时长为 35000 ms")
	_expect(harness.runtime.stage_def.cues.size() == 6, "关键动作数量为 6")
	var start_events: Array = []
	start_events.append_array(harness.take_events())
	_expect(_count_kind(start_events, "stage_start") == 1, "收到 stage_start")

	harness.advance_steps(60)
	var paused_ms: int = harness.clock.get_song_time_ms()
	var paused_oil: float = harness.runtime.lamp_controller.lamp.oil
	harness.set_paused(true)
	harness.advance_steps(60)
	_expect(harness.clock.get_song_time_ms() == paused_ms, "暂停时歌曲时间冻结")
	_expect(is_equal_approx(harness.runtime.lamp_controller.lamp.oil, paused_oil), "暂停时油量冻结")
	harness.set_paused(false)
	harness.advance_steps(60)
	_expect(harness.clock.get_song_time_ms() > paused_ms, "恢复后歌曲时间继续")

	harness.advance_steps(2100)
	var events: Array = harness.take_events()
	_expect(harness.runtime.is_over(), "运行到 35 秒后结束")
	_expect(_count_kind(events, "stage_end") == 1, "收到 stage_end")
	_expect(_count_kind(events, "cue_hint") > 0, "收到 cue_hint")
	_expect(_count_kind(events, "remedy_open") > 0, "漏做收到 remedy_open")
	_expect(_count_kind(events, "lamp_state_changed") > 0, "收到 lamp_state_changed")
	var received: Array = LampController.receive_events(events)
	_expect(received.size() > 0, "模拟接收端解析到事件")
	print("======== 探针结论：%d 项检查，%d 项失败 ========" % [_checks, _failures])
	return _failures


func _count_kind(events: Array, kind: String) -> int:
	var count: int = 0
	for event in events:
		if str(event.get("kind", "")) == kind:
			count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  [通过] %s" % message)
	else:
		_failures += 1
		print("  [失败] %s" % message)
