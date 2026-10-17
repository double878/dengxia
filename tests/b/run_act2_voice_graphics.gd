extends SceneTree
## 实时 Windows 声音/输入回归。保持真实主轨与音频时钟，不使用快速推进。

const InputHelper := preload("res://tests/c/run_act2_actions.gd")
const OUTPUT := "res://builds/act2-voice"
var capture: AudioEffectCapture
var opening: Node
var hall: Node
var checks: int = 0
var failures: int = 0
var levels: Dictionary = {}
var label: String = ""


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ACT2_VOICE_WINDOWS: " + message)


func pump(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		await create_timer(.04).timeout
		var key: String = label
		if is_instance_valid(hall):
			key = hall.actions.phase
			if key == "dialogue":
				key += "_%d" % hall.actions.line_index
			elif key == "duet":
				key += "_%d" % hall.actions.duet_index
		var row: Dictionary = levels.get(key, {"peak": 0.0, "frames": 0})
		for sample: Vector2 in capture.get_buffer(capture.get_frames_available()):
			row.peak = maxf(row.peak, maxf(absf(sample.x), absf(sample.y)))
			row.frames += 1
		levels[key] = row


func phase(target: Node, expected: String, limit: float = 80.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(limit * 1000)
	while target.actions.phase != expected and Time.get_ticks_msec() < deadline:
		await pump(.05)
	check(target.actions.phase == expected, "未在真实音轨中到达 " + expected)
	return target.actions.phase == expected


func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT + "/" + name + ".png") == OK, "截图 " + name)


func silence() -> float:
	await create_timer(.2).timeout
	capture.clear_buffer()
	await create_timer(.4).timeout
	var peak: float = 0.0
	for sample: Vector2 in capture.get_buffer(capture.get_frames_available()):
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	return peak


func _run() -> void:
	check(
		DisplayServer.get_name() != "headless" and AudioServer.get_driver_name() != "Dummy",
		"需要真实 Windows 图形和音频设备"
	)
	if failures:
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(0, capture)
	opening = load("res://scenes/act2/opening.tscn").instantiate()
	root.add_child(opening)
	label = "fahai_entry"
	await pump(1.3)
	check(
		(
			opening.on_stage.is_empty()
			and opening.music_cues.entry.playing
			and levels[label].peak > .001
		),
		"第二关空台开场立即播放视频音乐"
	)
	await shot("fahai-entry")
	InputHelper.key(opening, KEY_ESCAPE)
	check(await silence() < .001, "出场音乐暂停后实际静音")
	InputHelper.key(opening, KEY_ESCAPE)
	InputHelper.key(opening, KEY_1)
	InputHelper.key(opening, KEY_SPACE)
	# 法海起初在树遮罩后；从幕布下方的真实操作签抓取。
	InputHelper.drag(opening, opening.HAND_ANCHOR, Vector2(-400, 0))
	await pump(.2)
	check(
		opening.dialogue.phase == "wait_greeting" and opening.music_cues.entry.playing,
		"走出柳树保持器乐，等待许仙迎接"
	)
	check(await silence() > .001 and opening.dialogue.player.stream_paused, "迎接前持续器乐但不提前唱词")
	InputHelper.key(opening, KEY_2)
	InputHelper.key(opening, KEY_SPACE)
	var greeting_x: float = opening.controller.get_puppet(0).stage_pos.x * 1920 - 300
	var xu_x: float = opening.controller.get_puppet(1).stage_pos.x * 1920
	InputHelper.drag(opening, opening.HAND_ANCHOR, Vector2(greeting_x - xu_x, 0))
	label = "opening_original"
	var singing_deadline: int = Time.get_ticks_msec() + 10000
	while opening.dialogue.phase == "wait_greeting" and Time.get_ticks_msec() < singing_deadline:
		await pump(.03)
	check(
		opening.dialogue.phase == "dialogue" and not opening.music_cues.entry.playing,
		"音乐完整结束且迎接后开始对白"
	)
	await pump(1.8)
	check(levels[label].peak > .001, "许仙实际迎接后原片首句有真实声音")
	opening.queue_free()
	await process_frame
	await create_timer(.2).timeout
	capture.clear_buffer()
	hall = load("res://scenes/act2/hall.tscn").instantiate()
	root.add_child(hall)
	check(hall.clock.is_audio_driven(), "厅堂唯一时钟来自真实主轨")
	check(hall.actions.phase == "duet" and hall.on_stage == [0, 1], "厅堂直接双人对唱，没有小青段落")
	await shot("duet-xu")
	await pump(2.5)
	InputHelper.key(hall, KEY_ESCAPE)
	var frozen_song: int = hall.clock.get_song_time_ms()
	var frozen_real: int = hall.clock.get_real_time_ms()
	check(await silence() < .001, "唱腔暂停后真实静音")
	check(
		(
			hall.clock.get_song_time_ms() == frozen_song
			and hall.clock.get_real_time_ms() == frozen_real
		),
		"暂停冻结双时钟"
	)
	InputHelper.key(hall, KEY_ESCAPE)
	InputHelper.right(hall, 0)
	check(await silence() < .001, "对唱演员缺场时真实静音")
	InputHelper.key(hall, KEY_1)
	while hall.actions.duet_index < 1 and hall.actions.phase == "duet":
		await pump(.1)
	await shot("duet-bai")
	if not await phase(hall, "cup"):
		quit(1)
		return
	check(
		(
			hall.audio.player.get_playback_position() * 1000
			>= float(hall.audio.config.duet[-1].end_ms)
		),
		"实际播放游标已越过白素贞完整尾腔"
	)
	# 动作等待会暂停主轨，playing 此时为 false；音频驱动标志必须保留。
	check(hall.clock.is_active_flag() and hall.clock.player == hall.audio.player, "暂停与恢复后仍绑定同一主轨时钟")
	check(await silence() < .001, "完整唱完后等待取杯没有不适对白")
	InputHelper.take(hall, 1)
	InputHelper.drag(
		hall,
		hall._views[1].hand_screen_position("right"),
		Vector2(1075, 410) - hall._views[1].hand_screen_position("right")
	)
	check(hall.actions.cup_owner == 1, "偏离杯心约40像素仍可实际取杯")
	InputHelper.drag(hall, hall._views[1].torso_screen_position(), Vector2(-152, 0))
	await pump(.2)
	InputHelper.take(hall, 0)
	var offered: Vector2 = hall._views[1].hand_screen_position(hall.actions.cup_hand)
	InputHelper.drag(
		hall,
		hall._views[0].hand_screen_position("left"),
		offered - hall._views[0].hand_screen_position("left")
	)
	check(hall.actions.cup_owner == 0, "实际手部递杯")
	InputHelper.drag(
		hall,
		hall._views[0].hand_screen_position("left"),
		(
			hall._views[0].head_screen_position()
			+ Vector2(40, -30)
			- hall._views[0].hand_screen_position("left")
		)
	)
	await pump(.8)
	check(hall.actions.phase == "bend" and not hall.actions.bent, "实际饮酒后仍等待弯腰")
	await shot("before-bend")
	check(await silence() < .001, "弯腰前不播放不适对白")
	InputHelper.drag(hall, hall._views[0].torso_screen_position(), Vector2(75, 0), true)
	await pump(.1)
	check(hall.actions.bent and hall.actions.line_index == 5, "真实 Alt 拖腰后才说不适")
	await shot("bai-unwell")
	if not await phase(hall, "medicine_exit", 15):
		quit(1)
		return
	check(
		(
			hall.audio.player.get_playback_position() * 1000
			>= float(hall.audio.config.lines[6].end_ms)
		),
		"实际播放游标已越过完整取药台词"
	)
	InputHelper.take(hall, 1)
	InputHelper.drag(hall, hall._views[1].torso_screen_position(), Vector2(740, 0))
	InputHelper.right(hall, 1)
	hall.lamp_controller.lamp.exposure = .1
	await pump(.1)
	InputHelper.right(hall, 0)
	InputHelper.key(hall, KEY_4)
	hall.lamp_controller.lamp.exposure = .8
	await pump(.1)
	InputHelper.key(hall, KEY_2)
	InputHelper.take(hall, 1)
	InputHelper.drag(hall, hall._views[1].torso_screen_position(), Vector2(-690, 0))
	if not await phase(hall, "fright", 2):
		quit(1)
		return
	await pump(.25)
	InputHelper.key(hall, KEY_ESCAPE)
	check(await silence() < .001 and hall.actions.collapse_progress == 0, "惊叫暂停时声音和倒地时序同时冻结")
	InputHelper.key(hall, KEY_ESCAPE)
	if not await phase(hall, "finished", 5):
		quit(1)
		return
	await pump(1.5)
	await shot("fallen")
	check(
		hall.music_cues.hit_count == 1 and levels.get("fright", {}).get("peak", 0.0) > .001,
		"见蛇时许仙真实喊叫一次，再倒地"
	)
	check(await silence() < .001, "落地后没有视频重音")
	check(hall.audio.player.stream_paused, "惊倒时不恢复已结束的对白主轨")
	for i in [5, 6]:
		check(levels.get("dialogue_%d" % i, {}).get("peak", 0.0) > .001, "普通对白真实混音 %d" % i)
	for i in range(4):
		check(levels.get("duet_%d" % i, {}).get("peak", 0.0) > .001, "连续对唱真实混音 %d" % i)
	var report: Dictionary = {
		"checks": checks,
		"failures": failures,
		"display": DisplayServer.get_name(),
		"audio_driver": AudioServer.get_driver_name(),
		"levels": levels,
		"human_listening_verified": false
	}
	FileAccess.open(OUTPUT + "/windows-verification.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	hall.queue_free()
	await process_frame
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	print("ACT2_VOICE_WINDOWS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
