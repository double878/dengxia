extends SceneTree
## 真声卡验证：冻结 WAV 跳段后，逻辑时间不能领先实际唱白。

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CLOCK_SEEK: " + label)


func _run() -> void:
	check(AudioServer.get_driver_name() != "Dummy", "必须使用真实声音设备")
	var player := AudioStreamPlayer.new()
	player.stream = load("res://assets/audio/act2-hall/main.wav")
	root.add_child(player)
	var clock := MusicClock.new()
	clock.set_player(player)
	clock.start()
	await create_timer(.25).timeout
	clock.update(.25)
	clock.set_song_frozen(true)
	var real_before := clock.get_real_time_ms()
	clock.advance_to_ms(20119)
	await create_timer(.1).timeout
	print(
		(
			"CLOCK_SEEK frozen logic=%d actual=%d"
			% [clock.get_song_time_ms(), roundi(player.get_playback_position() * 1000)]
		)
	)
	check(absf(player.get_playback_position() - 20.119) < .08, "冻结跳段必须定位到对唱真实起点")
	check(player.stream_paused, "跳段保留动作等待冻结")
	check(clock.get_real_time_ms() == real_before, "跳段不重置真实时间")
	clock.set_song_frozen(false)
	for _i in range(12):
		await create_timer(.02).timeout
		clock.update(.02)
	check(
		absf(player.get_playback_position() * 1000 - clock.get_song_time_ms()) < 80, "解冻后逻辑与播放游标一致"
	)
	clock.pause()
	clock.advance_to_ms(61869)
	await create_timer(.1).timeout
	check(player.stream_paused and clock.is_paused(), "菜单暂停中的跳段保持暂停")
	check(absf(player.get_playback_position() - 61.869) < .08, "菜单暂停跳段也须定位实际对白")
	clock.resume()
	for _i in range(12):
		await create_timer(.02).timeout
		clock.update(.02)
	print(
		(
			"CLOCK_SEEK resumed logic=%d actual=%d"
			% [clock.get_song_time_ms(), roundi(player.get_playback_position() * 1000)]
		)
	)
	check(
		absf(player.get_playback_position() * 1000 - clock.get_song_time_ms()) < 80, "恢复菜单暂停不丢对白开头"
	)
	player.stop()
	player.queue_free()
	await process_frame
	print("CLOCK_SEEK checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
