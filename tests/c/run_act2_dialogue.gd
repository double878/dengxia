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
	opening._process(0.1)
	check(dialogue.phase == "wait_arrival", "法海藏在树后便开口")
	controller.get_puppet(0).stage_pos.x = controller.get_puppet(1).stage_pos.x + 300.0 / 1920.0
	controller.get_puppet(0).facing = 1.0
	opening._refresh_views()
	opening._process(0.02)
	check(dialogue.phase == "wait_arrival", "背对许仙也能开始对白")
	controller.get_puppet(0).facing = -1.0
	opening._refresh_views()
	opening._process(0.1)
	check(dialogue.phase == "dialogue" and not clock.is_song_frozen(), "真实就位没有开始对白")
	opening._toggle_pause()
	var before: int = clock.get_real_time_ms()
	opening._process(0.1)
	check(clock.get_real_time_ms() == before and clock.is_paused(), "菜单暂停没有冻结双时钟")
	opening._toggle_pause()
	clock.set_free_time_ms(int(dialogue.config.agreement_gate_ms))
	opening._process(0.02)
	check(dialogue.phase == "wait_agreement" and clock.is_song_frozen(), "第五句后未等待实际应允")
	var origin: Vector2 = controller.get_puppet(1).stage_pos
	clock.update(20.0)
	opening._process(0.02)
	check(dialogue.phase == "wait_agreement", "等待超时跳过应允")
	controller.get_puppet(1).stage_pos.x -= 60.0 / 1920.0
	opening._process(0.02)
	check(dialogue.phase == "wait_agreement", "朝反方向走被当成应允")
	controller.get_puppet(1).stage_pos = origin + Vector2(48.0 / 1920.0, 0)
	controller.get_puppet(1).facing = 1.0
	opening._exit(0)
	opening._process(0.02)
	check(dialogue.phase == "wait_agreement", "法海缺席仍播放应允")
	opening._enter(0)
	opening._process(0.02)
	check(dialogue.phase == "agreement" and not clock.is_song_frozen(), "许仙真实上前没有解锁末句")
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
	await test_agreement_at_edge(scene)
	print("ACT2_DIALOGUE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func test_agreement_at_edge(scene: PackedScene) -> void:
	var opening: Node = scene.instantiate()
	root.add_child(opening)
	opening.set_process(false)
	var dialogue: Node = opening.dialogue
	var clock: MusicClock = opening.clock
	dialogue.player.stop()
	clock.set_player(null)
	clock.start()
	opening._enter(0)
	opening._enter(1)
	dialogue.phase = "dialogue"
	var edge := PuppetState.STAGE_POS_MAX
	opening.controller.get_puppet(0).stage_pos.x = edge
	opening.controller.get_puppet(1).stage_pos.x = edge
	clock.set_free_time_ms(int(dialogue.config.agreement_gate_ms))
	opening._process(0.02)
	opening._process(0.02)
	check(dialogue.phase == "wait_agreement", "重叠站位被当作应允")
	check(dialogue.get_hint().contains("先将法海"), "重叠站位没有恢复提示")
	opening.controller.get_puppet(0).stage_pos.x -= 150.0 / 1920.0
	opening._process(0.02)
	check(dialogue.phase == "wait_agreement", "只挪法海就播放应允")
	check(dialogue.agreement_target_x < edge, "重排站位后目标仍超出舞台边界")
	opening.controller.get_puppet(1).stage_pos.x -= 48.0 / 1920.0
	opening.controller.get_puppet(1).facing = -1.0
	opening._process(0.02)
	check(dialogue.phase == "agreement", "边界重排后真实上前无法恢复")
	opening.queue_free()
	await process_frame
