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

	# 第一关开局：三个影人同时在场，另两个分别挂在两个挂钩上（PRD 第 4.2 节），
	# 于是两个挂钩槽从第一帧起就被占满。这决定了本关「空格 = 挂起」不可能成功，
	# HUD 因此不显示那条提示（见 level1_a_scene.hook_hint_text）。
	# 若日后改布景让出空槽，这两条会失败，提醒同步提示文案与测试。
	var controller: PuppetController = harness.runtime.puppet_controller
	_expect(controller.find_free_hook_slot() == -1, "第一关开局两个挂钩槽都被布景占满")
	_expect(not controller.call("hook_current"), "本关不接受挂起当前影人")
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

	# 补救会冻结歌曲时间（8 秒真实时间/次，空场跑共 6 次），因此真实步数明显多于 35 秒。
	var guard: int = 0
	while not harness.runtime.is_over() and guard < 8000:
		harness.advance_steps(1)
		guard += 1
	var events: Array = harness.take_events()
	_expect(harness.runtime.is_over(), "运行到 35 秒（歌曲时间）后结束")
	_expect(guard < 8000, "补救冻结拉长了真实耗时但不应无上限（实际用了 %d 步）" % guard)
	_expect(harness.clock.get_song_time_ms() <= 35010,
		"歌曲时间应停在 35 秒（实际 %d ms）" % harness.clock.get_song_time_ms())
	_expect(harness.clock.get_real_time_ms() > 40000,
		"真实耗时应长于歌曲时长（真实 %d ms）" % harness.clock.get_real_time_ms())
	_expect(_count_kind(events, "stage_end") == 1, "收到 stage_end")
	_expect(_count_kind(events, "cue_hint") > 0, "收到 cue_hint")
	_expect(_count_kind(events, "remedy_open") > 0, "漏做收到 remedy_open")
	_expect(_count_kind(events, "remedy_freeze_begin") > 0, "收到 remedy_freeze_begin")
	_expect(_count_kind(events, "remedy_freeze_end") > 0, "收到 remedy_freeze_end")
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
