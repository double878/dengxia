extends "res://tests/c/run_act2_opening.gd"
## 原片从许仙开口；入场等待不漏播，接头、尾音、暂停和误退场均沿唯一时钟。

var completed_signals: int = 0


func _run() -> void:
	var opening: Node = load("res://scenes/act2/opening.tscn").instantiate()
	root.add_child(opening)
	opening.set_process(false)
	var dialogue: Node = opening.dialogue
	check(dialogue.phase != "error", "原声音源初始化失败：" + dialogue.problem)
	if dialogue.phase == "error":
		opening.queue_free()
		await process_frame
		quit(1)
		return
	dialogue.finished.connect(func(): completed_signals += 1)
	var clock: MusicClock = opening.clock
	var controller: PuppetController = opening.controller
	dialogue.player.stop()
	clock.set_player(null)
	clock.start()
	clock.set_song_frozen(true)
	opening._process(.1)
	check(dialogue.phase == "wait_arrival" and clock.get_song_time_ms() == 0, "空台漏播原声")
	opening._enter(0)
	opening._enter(1)
	check(opening.on_stage == [0], "法海未走出柳树便允许许仙上场")
	opening._process(.1)
	check(dialogue.phase == "wait_arrival", "法海藏在树后便进入迎接")
	controller.get_puppet(0).stage_pos.x -= 380.0 / 1920.0
	controller.get_puppet(0).facing = 1.0
	opening._refresh_views()
	opening._process(.02)
	check(dialogue.phase == "wait_arrival", "背对许仙也能开始迎接")
	controller.get_puppet(0).facing = -1.0
	opening._refresh_views()
	opening._process(.02)
	check(dialogue.phase == "wait_greeting" and clock.is_song_frozen(), "走出柳树后未等待许仙迎接")
	check(clock.get_song_time_ms() == 0 and dialogue.get_line().is_empty(), "许仙未迎接便漏播首句")
	clock.update(20)
	opening._process(.02)
	check(clock.get_song_time_ms() == 0, "迎接等待超时跳过原声")
	opening._enter(1)
	opening._process(.02)
	check(dialogue.phase == "wait_greeting", "许仙只在门内上场便回话")
	var fahai_position: Vector2 = controller.get_puppet(0).stage_pos
	controller.get_puppet(1).stage_pos.x -= 80.0 / 1920.0
	opening._process(.02)
	check(dialogue.phase == "wait_greeting", "许仙走反方向仍回话")
	controller.get_puppet(1).stage_pos.x = fahai_position.x - 300.0 / 1920.0
	controller.get_puppet(1).facing = -1.0
	opening._process(.02)
	check(dialogue.phase == "wait_greeting", "背对法海仍回话")
	controller.get_puppet(1).facing = 1.0
	opening._exit(0)
	opening._process(.02)
	check(clock.is_song_frozen(), "法海缺席仍完成迎接")
	opening._enter(0)
	opening._process(.02)
	check(dialogue.phase == "dialogue" and not clock.is_song_frozen(), "真实迎接后原声未开始")
	check(controller.get_puppet(0).stage_pos == fahai_position, "迎接自动移动法海")
	check(dialogue.config.lines[0].role_id == "xuxian", "原片首句身份应为许仙")
	for row: Dictionary in dialogue.config.lines:
		clock.set_free_time_ms(int(row.start_ms))
		opening._process(.02)
		check(dialogue.get_line().get("line_id") == row.line_id, "原片字幕未按时切换：" + row.line_id)
		check(dialogue.phase == "dialogue", "旧六句应允逻辑截断新原声：" + row.line_id)
	var splice: int = int(dialogue.config.splice_ms)
	clock.set_free_time_ms(splice - 100)
	opening._process(.02)
	opening._toggle_pause()
	var paused_song: int = clock.get_song_time_ms()
	var paused_real: int = clock.get_real_time_ms()
	opening._process(1)
	check(clock.get_song_time_ms() == paused_song, "接头暂停未冻结歌曲时间")
	check(clock.get_real_time_ms() == paused_real and clock.is_paused(), "接头暂停未冻结真实时间")
	opening._toggle_pause()
	clock.set_free_time_ms(splice + 1000)
	opening._process(.02)
	check(dialogue.get_line().get("text") == "老僧查明，", "第二段未按接头时标接续")
	opening._exit(1)
	opening._process(.02)
	var missing_song: int = clock.get_song_time_ms()
	clock.update(2)
	check(clock.is_song_frozen() and clock.get_song_time_ms() == missing_song, "缺场仍消耗原声")
	check(dialogue.get_line().is_empty(), "缺场仍显示回话")
	opening._enter(1)
	opening._process(.02)
	check(not clock.is_song_frozen() and clock.get_song_time_ms() == missing_song, "回来后未原位续播")
	clock.set_free_time_ms(int(dialogue.config.dark_start_ms) - 500)
	opening._process(.02)
	check(dialogue.phase == "dialogue" and dialogue.fade_amount() == 0, "原片尾音未完便暗场")
	clock.set_free_time_ms(int(dialogue.config.dark_start_ms) + 1000)
	opening._process(.02)
	check(dialogue.phase == "closing" and dialogue.fade_amount() > .4, "原声结束未开始暗场")
	opening._exit(1)
	opening._process(.02)
	check(not clock.is_song_frozen(), "暗场时人物缺席阻止换景")
	clock.set_free_time_ms(int(dialogue.config.duration_ms))
	opening._process(.02)
	check(dialogue.phase == "finished" and opening.on_stage.is_empty(), "暗场结束未清场")
	opening._process(.1)
	check(completed_signals == 1, "完成信号重复触发")
	opening._enter(0)
	check(opening.on_stage.is_empty(), "收场后仍接受第一场上场输入")
	opening.queue_free()
	await process_frame
	print("ACT2_DIALOGUE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
