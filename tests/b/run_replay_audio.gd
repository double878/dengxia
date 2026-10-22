extends SceneTree
## 真实图形/声卡环境下检查幕前音轨输出、等待、暂停和收锣去重。
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("REPLAY_AUDIO: " + label)


func _run() -> void:
	var config: Dictionary = Act1OperaAudio.read_config()
	check(config.get("background_music", false), "正式第一关对唱已恢复新伴奏")
	var audio := Act1OperaAudio.new()
	root.add_child(audio)
	check(audio.setup_replay(config), "正式回放音源加载")
	var bus: int = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, "ReplayVerification")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus, capture)
	for player: AudioStreamPlayer in audio.get_children():
		player.bus = "ReplayVerification"
	var view := {
		"main":
		{"playing": true, "paused": false, "position_ms": float(config.lines[0].start_ms) + 1000.0},
		"wait": {"playing": false},
		"slow": {"playing": false},
		"wait_gain": 0.0
	}
	audio.apply_replay(view, [], false)
	await create_timer(0.3).timeout
	check(audio.get_player().playing and not audio.get_player().stream_paused, "主轨开始播放")
	if DisplayServer.get_name() != "headless":
		check(_peak(capture) > 0.001, "声卡混音确实输出对白样本")
	audio.set_replay_paused(true)
	await create_timer(0.1).timeout
	var position: float = audio.get_player().get_playback_position()
	await create_timer(0.15).timeout
	check(audio.get_player().stream_paused, "暂停冻结主轨")
	check(absf(audio.get_player().get_playback_position() - position) < 0.01, "暂停位置不前进")
	view.main.position_ms = position * 1000
	view.main.paused = true
	view.wait = {"playing": true, "paused": false, "position_ms": 0.0}
	view.wait_gain = 1.0
	audio.apply_replay(view, [], false)
	await create_timer(0.2).timeout
	check(
		audio.get_player().stream_paused and audio.get_node("Act1_wait_loop").playing,
		"等待器乐接管且主轨保持原位"
	)
	if DisplayServer.get_name() != "headless":
		capture.clear_buffer()
		await create_timer(0.2).timeout
		check(_peak(capture) < 0.001, "动作等待期间没有背景音乐")
	var gong := CTimedEvent.new(1000, &"opera_take_close", "performance_audio")
	gong.seq = 42
	audio.apply_replay(view, [gong], false)
	audio.apply_replay(view, [gong], true)
	check(audio.replay_gong_count == 1, "暂停/重复帧没有重复收锣")
	check(audio.get_node("Act1_take_close").stream_paused, "暂停冻结收锣")
	view.main.paused = false
	view.wait.playing = false
	audio.apply_replay(view, [], false)
	check(
		not audio.get_player().stream_paused and not audio.get_node("Act1_wait_loop").playing,
		"继续恢复主轨、关闭等待器乐"
	)
	view.main.position_ms = float(config.closing_ms)
	audio.apply_replay(view, [], false)
	await create_timer(0.08).timeout
	check(
		absf(audio.get_player().get_playback_position() * 1000 - float(config.closing_ms)) < 250,
		"前向跳段到同一音源位置"
	)
	audio.stop()
	check(not audio.get_player().playing and not audio.get_node("Act1_wait_loop").playing, "退出释放音频")
	audio.queue_free()
	await process_frame
	AudioServer.remove_bus(bus)
	print("REPLAY_AUDIO checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _peak(capture: AudioEffectCapture) -> float:
	var peak: float = 0.0
	for frame: Vector2 in capture.get_buffer(capture.get_frames_available()):
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	return peak
