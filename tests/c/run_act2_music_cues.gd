extends SceneTree
## 法海出场起同源器乐，迎接不断，接唱交叉淡化，厅堂落地重音沿用。

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
	if music != null:
		check(not music.entry.playing, "法海未上场时不播放音乐")
		key(opening, KEY_1)
		check(music.entry.playing, "法海实际上场后立即播放同源器乐")
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
		music.update_entrance("dialogue", true, 125, 250)
		check(music.entry.playing and music.entry.volume_db < -5, "接唱时出场器乐交叉淡出")
		music.update_entrance("dialogue", true, 300, 250)
		check(not music.entry.playing, "交叉衔接完成后不叠放出场辅轨")
		music.update_fall(.8)
		check(not music.hit.playing, "没有真实落地就不响重音")
		music.update_fall(.96)
		check(music.hit.playing, "倒地到落点才响视频中的重音")
		check(music.hit_count == 1, "落点只触发一次")
		music.set_paused(true)
		check(music.hit.stream_paused, "暂停冻结落地重音")
		music.set_paused(false)
		music.update_fall(1.0)
		check(music.hit_count == 1, "倒地后不重复重音")
	opening.queue_free()
	await process_frame
	print("ACT2_MUSIC checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
