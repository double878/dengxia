extends SceneTree
## 音轨时标来自实波形；动作等待、跳段和暂停共用唯一时钟。

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ACT2_HALL_AUDIO: " + label)


func _run() -> void:
	var hall: Node = load("res://scenes/act2/hall.tscn").instantiate()
	root.add_child(hall)
	hall.set_process(false)
	await process_frame
	var audio: Node = hall.get("audio")
	check(audio != null, "正式厅堂应接入对白和连续唱腔")
	if audio != null:
		check(audio.problem.is_empty(), "音源、格式和清单合法")
		check(hall.clock.player == audio.player, "只有宿主的 MusicClock 绑定主轨")
		check(hall.actions.phase == "duet" and hall.on_stage == [0, 1], "厅堂双人直接开始对唱")
		check(audio.config.duet.size() == 4, "四组连续劝酒对唱")
		check(not hall.actions.subtitle().contains("临时"), "正式字幕不保留排练标签")
		var before_real: int = hall.clock.get_real_time_ms()
		check(not hall.actions.can_enter(2), "已删除的小青剧情不能重新上场")
		check(hall.clock.get_song_time_ms() >= int(audio.config.duet_start_ms), "按主轨时标前向进入唱段")
		check(hall.clock.get_real_time_ms() >= before_real, "跳段保留真实时间")
		hall._exit(0)
		check(audio.player.stream_paused, "误退演员立即冻结唱腔")
		hall._enter(0)
		hall._process(.02)
		check(not audio.player.stream_paused, "原姿态上场后继续同一唱段")
		hall._toggle_pause()
		check(audio.player.stream_paused, "菜单暂停主轨")
		hall._toggle_pause()
		hall.clock.advance_to_ms(int(audio.config.duet_gate_ms))
		hall._process(.02)
		check(hall.actions.phase == "cup" and audio.player.stream_paused, "完整尾腔后才能递杯，等待无下一句声音")
		check(not hall.actions.drunk and hall.actions.cup_owner == -1, "唱腔不能代替实际饮酒")
		# 仅隔离后段许可；实际弯腰和整条输入链由 run_act2_actions 验证。
		hall.actions.drunk = true
		hall.actions._set_phase("bend")
		hall.actions._bend_armed = true
		hall.controller.get_puppet(0).torso_lean = PI / 6.0
		hall._process(.02)
		check(hall.actions.bent and hall.actions.line_index == 5, "真实腰角到位才许可不适对白")
		check(
			hall.clock.get_song_time_ms() >= int(audio.config.lines[5].start_ms) - 100,
			"弯腰后前向续播普通对白"
		)
		check(not audio.player.stream_paused, "饮后对白有真实主轨")
		hall.clock.advance_to_ms(int(audio.config.medicine_gate_ms))
		hall._process(.02)
		check(hall.actions.phase == "medicine_exit" and audio.player.stream_paused, "取药对白完整结束再等待离场")
	hall.queue_free()
	await process_frame
	await create_timer(.1).timeout
	print("ACT2_HALL_AUDIO checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
