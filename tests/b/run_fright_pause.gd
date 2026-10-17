extends SceneTree
## 短促惊叫的真实声卡暂停回归；也可用编辑器引擎加载导出 PCK 运行。
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FRIGHT_PAUSE: " + label)


func key(hall: Node) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	hall._input(event)


func _run() -> void:
	check(
		DisplayServer.get_name() != "headless" and AudioServer.get_driver_name() != "Dummy",
		"需要实际图形与音频设备"
	)
	if failures:
		quit(1)
		return
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(0, capture)
	var hall: Node = load("res://scenes/act2/hall.tscn").instantiate()
	root.add_child(hall)
	# 首帧渲染/着色器准备完成后再测 331 ms 的音效，避免冷启动耗时吃掉它。
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	capture.clear_buffer()
	# 只准备返回场景；仍由正式几何判定触发惊叫和正式时钟推进倒地。
	hall.actions._set_phase("return")
	hall.actions.returned = true
	hall.on_stage.assign([1, 3])
	hall.snake.position = Vector2(950, 700)
	hall.lamp_controller.lamp.exposure = .8
	hall.controller.get_puppet(1).stage_pos.x = 1200.0 / 1920.0
	hall.controller.get_puppet(1).facing = -1.0
	hall.controller.get_puppet(1).turn_progress = 1.0
	hall._update_actions()
	await create_timer(float(hall.audio.config.fright_duration_ms) / 4000.0).timeout
	var phase: String = hall.actions.phase
	var real: int = hall.clock.get_real_time_ms()
	var progress: float = hall.actions.collapse_progress
	var cursor: float = hall.music_cues.hit.get_playback_position()
	key(hall)
	await create_timer(.2).timeout
	capture.clear_buffer()
	await create_timer(.3).timeout
	var peak: float = 0.0
	for frame: Vector2 in capture.get_buffer(capture.get_frames_available()):
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	print(
		(
			"FRIGHT_PAUSE phase=%s real=%d->%d progress=%f->%f peak=%f"
			% [
				phase,
				real,
				hall.clock.get_real_time_ms(),
				progress,
				hall.actions.collapse_progress,
				peak
			]
		)
	)
	check(phase == "fright", "在实际惊叫期间暂停")
	check(
		real == hall.clock.get_real_time_ms() and progress == hall.actions.collapse_progress,
		"暂停冻结双时序和倒地动作"
	)
	check(peak < .001, "暂停实际输出静音")
	capture.clear_buffer()
	key(hall)
	await create_timer(.6).timeout
	peak = 0.0
	for frame: Vector2 in capture.get_buffer(capture.get_frames_available()):
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	print(
		(
			"FRIGHT_RESUME paused_cursor=%f peak=%f playing=%s"
			% [cursor, peak, hall.music_cues.hit.playing]
		)
	)
	check(peak > .1 and peak < .9, "恢复完整续播正式惊叫且保留幅度余量")
	check(hall.actions.phase == "startled" and hall.actions.collapse_progress > 0.0, "叫完之后进入倒地")
	check(hall.music_cues.hit_count == 1, "惊叫只触发一次")
	check(
		(
			absf(
				(
					hall.music_cues.hit.stream.get_length() * 1000
					- float(hall.audio.config.fright_duration_ms)
				)
			)
			< 1.0
		),
		"真实惊叫时长匹配动作清单"
	)
	hall.queue_free()
	await process_frame
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	print(
		(
			"FRIGHT_PAUSE checks=%d failures=%d driver=%s"
			% [checks, failures, AudioServer.get_driver_name()]
		)
	)
	quit(1 if failures else 0)
