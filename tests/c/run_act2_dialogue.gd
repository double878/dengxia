extends "res://tests/c/run_act2_opening.gd"
## 第一幕真实动作许可、暂停和误退场回归。

var completed_signals: int = 0


func _run() -> void:
	if not ResourceLoader.exists("res://scripts/act2/act2_dialogue.gd"):
		check(false, "缺少第一幕对白与应允流程")
		quit(1)
		return
	var scene: PackedScene = load("res://scenes/act2/opening.tscn")
	var opening: Node = scene.instantiate()
	root.add_child(opening)
	opening.set_process(false)
	var dialogue: Node = opening.get("dialogue")
	if dialogue.phase == "error":
		check(false, dialogue.problem)
		opening.queue_free()
		await process_frame
		quit(1)
		return
	dialogue.finished.connect(func(): completed_signals += 1)
	var clock: MusicClock = opening.get("clock")
	var controller: PuppetController = opening.get("controller")
	dialogue.player.stop()
	clock.set_player(null)
	clock.start()
	clock.set_song_frozen(true)
	opening._process(0.1)
	check(dialogue.phase == "wait_arrival" and clock.is_song_frozen(), "空台播放对白")
	opening._enter(0)
	opening._enter(1)
	check(opening.on_stage == [0], "首句结束前许仙提前出门")
	opening._process(0.1)
	check(dialogue.phase == "wait_arrival", "法海藏在树后便开口")
	controller.get_puppet(0).stage_pos.x -= 380.0 / 1920.0
	controller.get_puppet(0).facing = 1.0
	opening._refresh_views()
	opening._process(0.02)
	check(dialogue.phase == "wait_arrival", "背对许仙也能开始对白")
	controller.get_puppet(0).facing = -1.0
	opening._refresh_views()
	opening._process(0.1)
	check(dialogue.phase == "first_line" and not clock.is_song_frozen(), "法海走出树旁后没有独自说首句")
	if dialogue.phase != "first_line":
		opening.queue_free()
		await process_frame
		quit(1)
		return
	opening._toggle_pause()
	var before: int = clock.get_real_time_ms()
	opening._process(0.1)
	check(clock.get_real_time_ms() == before and clock.is_paused(), "菜单暂停没有冻结双时钟")
	opening._toggle_pause()
	opening._exit(0)
	opening._process(0.02)
	check(clock.is_song_frozen(), "首句法海误退场没有冻结")
	check(dialogue.get_hint().contains("法海重新上场"), "首句退场提示误要求许仙")
	opening._enter(0)
	opening._process(0.02)
	check(dialogue.phase == "first_line" and not clock.is_song_frozen(), "法海回来后首句未原位续播")
	clock.set_free_time_ms(int(dialogue.config.lines[0].end_ms) - 50)
	opening._process(0.02)
	check(dialogue.phase == "first_line", "法海首句尚未说完便等待迎接")
	opening._enter(1)
	check(opening.on_stage == [0], "说首句时允许许仙提前上场")
	clock.set_free_time_ms(int(dialogue.config.lines[0].end_ms) + 120)
	opening._process(0.02)
	check(dialogue.phase == "wait_greeting" and clock.is_song_frozen(), "首句之后没有冻结并等待许仙迎接")
	check(dialogue.get_line().is_empty(), "许仙未出门便播放回话字幕")
	clock.update(20.0)
	opening._process(0.02)
	check(dialogue.phase == "wait_greeting", "迎接等待超时后自动回话")
	opening._enter(1)
	opening._process(0.02)
	check(opening.on_stage == [0, 1] and dialogue.phase == "wait_greeting", "许仙只在门内上场便回话")
	var fahai_position: Vector2 = controller.get_puppet(0).stage_pos
	controller.get_puppet(1).stage_pos.x -= 80.0 / 1920.0
	opening._process(0.02)
	check(dialogue.phase == "wait_greeting", "许仙走反方向仍回话")
	controller.get_puppet(1).stage_pos.x = fahai_position.x - 300.0 / 1920.0
	controller.get_puppet(1).facing = -1.0
	opening._process(0.02)
	check(dialogue.phase == "wait_greeting", "迎接时背对法海仍回话")
	controller.get_puppet(1).facing = 1.0
	opening._exit(0)
	opening._process(0.02)
	check(dialogue.phase == "wait_greeting", "法海缺席仍完成迎接")
	opening._enter(0)
	opening._process(0.02)
	check(dialogue.phase == "dialogue" and not clock.is_song_frozen(), "许仙迎接就位后没有回话")
	check(controller.get_puppet(0).stage_pos == fahai_position, "迎接要求法海继续走到门前")
	var silence_start: int = int(dialogue.config.lines[4].end_ms)
	var reply_start: int = int(dialogue.config.lines[5].start_ms)
	check(
		reply_start - silence_start >= 1000 and reply_start - silence_start <= 1500,
		"末句前未留出短暂沉默"
	)
	clock.set_free_time_ms(silence_start + 120)
	opening._process(0.02)
	check(dialogue.phase == "thinking" and not clock.is_song_frozen(), "沉默阶段仍要求许仙走位")
	check(dialogue.get_line().is_empty(), "沉默时提前显示许仙回话")
	check(not dialogue.get_hint().contains("上前一步"), "沉默时仍提示上前一步")
	var origin: Vector2 = controller.get_puppet(1).stage_pos
	opening._toggle_pause()
	var silence_paused_ms: int = clock.get_song_time_ms()
	opening._process(1.0)
	check(clock.get_song_time_ms() == silence_paused_ms, "菜单暂停消耗了许仙沉默时间")
	opening._toggle_pause()
	clock.set_free_time_ms(reply_start - 80)
	opening._process(0.02)
	check(dialogue.phase == "thinking" and dialogue.get_line().is_empty(), "沉默尚未结束便回话")
	opening._exit(0)
	opening._process(0.02)
	check(clock.is_song_frozen(), "沉默时法海误退场没有冻结")
	opening._enter(0)
	opening._process(0.02)
	check(not clock.is_song_frozen(), "沉默时法海回来后未续播")
	clock.set_free_time_ms(reply_start)
	opening._process(0.02)
	check(dialogue.phase == "agreement" and not clock.is_song_frozen(), "许仙不走位无法自动回话")
	check(controller.get_puppet(1).stage_pos == origin, "自动回话移动了许仙")
	check(dialogue.get_line().get("role_id") == "xuxian", "沉默结束没有显示许仙回应")
	opening._exit(1)
	opening._process(0.02)
	check(clock.is_song_frozen(), "误退场没有冻结对白")
	opening._enter(1)
	opening._process(0.02)
	check(not clock.is_song_frozen(), "重新上场没有续播")
	clock.set_free_time_ms(int(dialogue.config.dark_start_ms) + 1000)
	opening._process(0.02)
	check(dialogue.phase == "closing" and dialogue.fade_amount() > 0.4, "应允后未开始暗场")
	clock.set_free_time_ms(int(dialogue.config.duration_ms))
	opening._process(0.02)
	check(dialogue.phase == "finished" and opening.on_stage.is_empty(), "暗场完成未清场")
	opening._process(0.1)
	check(completed_signals == 1, "暗场完成信号重复触发")
	opening._enter(0)
	check(opening.on_stage.is_empty(), "暗场后仍接受第一幕上场输入")
	opening.queue_free()
	await process_frame
	await test_reply_at_edge(scene)
	print("ACT2_DIALOGUE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func test_reply_at_edge(scene: PackedScene) -> void:
	var opening: Node = scene.instantiate()
	root.add_child(opening)
	opening.set_process(false)
	var dialogue: Node = opening.dialogue
	var clock: MusicClock = opening.clock
	dialogue.player.stop()
	clock.set_player(null)
	clock.start()
	opening._enter(0)
	dialogue.phase = "wait_greeting"
	opening._enter(1)
	dialogue.phase = "dialogue"
	var edge := PuppetState.STAGE_POS_MAX
	opening.controller.get_puppet(0).stage_pos.x = edge
	opening.controller.get_puppet(1).stage_pos.x = edge
	clock.set_free_time_ms(int(dialogue.config.lines[4].end_ms) + 120)
	opening._process(0.02)
	check(dialogue.phase == "thinking" and not clock.is_song_frozen(), "舞台边缘沉默仍等待走位")
	clock.set_free_time_ms(int(dialogue.config.lines[5].start_ms))
	opening._process(0.02)
	check(dialogue.phase == "agreement", "边缘重叠站位阻止自动回话")
	check(opening.controller.get_puppet(1).stage_pos.x == edge, "边缘自动回话移动了许仙")
	opening.queue_free()
	await process_frame
