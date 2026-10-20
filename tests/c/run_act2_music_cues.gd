extends SceneTree
## 空台立即播放完整单次音乐；不因出退场重播；厅堂默认模式和重音沿用。

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ACT2_MUSIC: " + label)


func key(target: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	target._input(event)


func _run() -> void:
	var opening: Node = load("res://scenes/act2/opening.tscn").instantiate()
	root.add_child(opening)
	opening.set_process(false)
	await process_frame
	var music: Node = opening.get("music_cues")
	check(music != null, "第二关声音状态须保留供回放记录")
	if music == null or music.entry == null:
		opening.queue_free()
		await process_frame
		quit(1)
		return
	if music != null:
		check(music.entry.playing, "第二关空台就须立即播放音乐")
		check(music.entry.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "开场音乐不得循环")
		check(not music.can_start_main(), "音乐刚起便允许对白")
		key(opening, KEY_1)
		check(music.entry.playing and not music.can_start_main(), "上场不得提前放行对白")
		opening._toggle_pause()
		check(music._paused and music.entry.stream_paused, "暂停同步冻结出场器乐")
		opening._toggle_pause()
		check(not music.entry.stream_paused and music.entry.playing, "恢复后原位续播出场器乐")
		opening.dialogue.player.stop()
		opening.clock.set_player(null)
		opening.clock.start()
		opening.clock.set_song_frozen(true)
		opening.controller.get_puppet(0).stage_pos.x -= 380.0 / 1920.0
		opening.controller.get_puppet(0).facing = -1.0
		opening._process(.1)
		check(opening.dialogue.phase == "wait_greeting" and music.entry.playing, "迎接等待持续同源器乐")
		opening._exit(0)
		opening._enter(0)
		opening._process(.1)
		check(music.entry.playing, "迎接等待退场回来仍有器乐")
		music.update_entrance("wait_arrival", false)
		check(music.entry.playing, "缺场不得截断开场音乐")
		music.entry.seek(music.entry.stream.get_length() - .02)
		check(not music.can_start_main(), "尾音尚未播完就允许对白")
		music.entry.stop()
		check(not music.can_start_main(), "手动停止不得冒充音乐完整结束")
		music.entry.finished.emit()
		check(music.can_start_main(), "音乐完整结束后未放行对白")
		music.update_entrance("wait_greeting", true)
		music.update_entrance("wait_arrival", false)
		check(not music.entry.playing, "音乐结束后出退场不得重播")
		check(not music.hit.playing, "见蛇前不得提前喊叫")
		music.play_fright()
		check(music.hit.playing and music.HIT.ends_with("xu-fright.wav"), "播放许仙惊叫，取消落地重音")
		check(music.hit_count == 1, "惊叫只触发一次")
		music.set_paused(true)
		check(music.hit.stream_paused, "暂停冻结惊叫")
		music.set_paused(false)
		music.play_fright()
		check(music.hit_count == 1, "倒地后不重复惊叫")
	opening.queue_free()
	await process_frame
	var hall_music := preload("res://scripts/act2/act2_music_cues.gd").new()
	root.add_child(hall_music)
	check(hall_music.setup(), "厅堂默认音乐初始化")
	check(not hall_music.entry.playing, "厅堂默认模式不应自动播放")
	hall_music.update_entrance("wait_arrival", true)
	check(
		(
			hall_music.entry.playing
			and hall_music.entry.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD
		),
		"厅堂默认循环行为改变"
	)
	hall_music.queue_free()
	await process_frame
	var replay_audio := preload("res://scripts/b/act2_replay_audio.gd").new()
	root.add_child(replay_audio)
	replay_audio.setup()
	var recorded := {"entry": {"playing": true, "paused": false, "position_ms": 0}}
	replay_audio.apply_recorded(2, recorded, false)
	check(replay_audio.players.entry.playing, "回放零点未播放开场音乐")
	check(
		replay_audio.players.entry.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "回放第一场音乐不得循环"
	)
	replay_audio.apply_recorded(22, recorded, false)
	check(
		replay_audio.players.entry.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "厅堂回放须保留原循环模式"
	)
	check(
		(
			(
				replay_audio.players.entry.stream.resource_path
				!= replay_audio._entry_streams[2].resource_path
			)
			or replay_audio.players.entry.stream != replay_audio._entry_streams[2]
		),
		"换幕回放仍使用第一场音乐"
	)
	replay_audio.queue_free()
	await process_frame
	print("ACT2_MUSIC checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
