extends SceneTree

const TestBase := preload("res://tests/a/a_test_base.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestBase.new()
	t.begin("正式游戏入口读取真实对白与唱段")
	var config := Act1OperaAudio.read_config()
	if config.is_empty():
		t.check(false, "未交付正式第一幕音源")
		quit(t.report())
		return
	var def := Act1OperaStage.make_stage(config)
	t.check_eq(def.validate().size(), 0, "实际音源时长与关卡表一致")
	var parent := Node.new()
	root.add_child(parent)
	var harness := Level1Harness.new(parent, def, config)
	t.check(harness.runtime != null, "正式宿主成功建立")
	if harness.runtime == null:
		parent.queue_free()
		quit(t.report())
		return
	t.check(not harness.metronome_enabled, "正式第一幕不叠临时节拍")
	t.check(harness.clock.player == harness.opera_audio.get_player(), "只有一个正式主播放器驱动 MusicClock")
	var speech_count := 0
	var song_count := 0
	for line: Dictionary in config.lines:
		if str(line.delivery) == "speech":
			speech_count += 1
		else:
			song_count += 1
	t.check_eq(speech_count, 13, "四句开场加九句还伞全部交付")
	t.check_eq(song_count, 3, "六句对唱按三组完整乐句保留")
	var first: Dictionary = config.lines[0]
	harness.clock.set_free_time_ms(int(first.start_ms) + 100)
	harness.opera_audio.update()
	t.check_eq(str(harness.opera_audio.current_line().text), str(first.text), "字幕与实际交付台词相同")
	harness.set_paused(true)
	t.check(harness.clock.player.stream_paused, "菜单暂停正式主音轨")
	var frozen_song := harness.clock.get_song_time_ms()
	var frozen_real := harness.clock.get_real_time_ms()
	harness.clock.update(2.0)
	t.check_eq(harness.clock.get_song_time_ms(), frozen_song, "暂停保留当前对白位置")
	t.check_eq(harness.clock.get_real_time_ms(), frozen_real, "暂停冻结真实时间")
	harness.set_paused(false)
	t.check(not harness.clock.player.stream_paused, "恢复续播当前对白")
	harness.clock.set_free_time_ms(int(config.arrival_ms))
	harness.advance_steps(1)
	t.check_eq(harness.opera_flow.phase, "wait_arrival", "实际宿主未到位时等待")
	t.check(harness.clock.is_song_frozen(), "Director 保持等待冻结，不被补救覆盖")
	var wait_player: AudioStreamPlayer = harness.opera_audio.get_node("Act1_wait_loop")
	t.check(wait_player.playing, "等待播放真实器乐")
	harness.set_paused(true)
	t.check(wait_player.stream_paused, "等待器乐跟随菜单暂停")
	harness.set_paused(false)
	t.check(not wait_player.stream_paused and harness.clock.player.stream_paused, "恢复只续播等待器乐")
	var events := harness.take_events()
	var previous_sequence := -1
	for event in events:
		var sequence := int(event.payload.sequence)
		t.check(sequence > previous_sequence, "跨模块事件使用统一序号")
		previous_sequence = sequence
	harness.shutdown()
	t.check(harness.clock.player == null, "退出解绑主时钟")
	t.check(not wait_player.playing, "退出不留下器乐循环")
	parent.queue_free()
	await create_timer(0.15).timeout
	t.finish("实际音源、字幕、等待与暂停接线正确")
	quit(t.report())
