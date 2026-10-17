extends SceneTree
## Windows 实际图形环境：正式厅堂输入和动作截图，禁止用 headless 代替。

var hall: Node
var audio_capture: AudioEffectCapture
const OUTPUT: String = "res://builds/act2-actions"
const ActionsInput := preload("res://tests/c/run_act2_actions.gd")


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("第二幕图形验收需要 Windows 图形环境")
		quit(1)
		return
	call_deferred("_run")


func capture(name: String) -> void:
	for _i in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(OUTPUT + "/" + name + ".png")
	if result != OK:
		push_error("第二幕截图保存失败：" + name)
		quit(1)


func capture_remedy(name: String, step: String) -> void:
	if (
		not hall.remedy.active()
		or hall.remedy.current_step != step
		or not hall._remedy_banner.visible
		or not hall._remedy_audio.playing
	):
		push_error("补救画面/音源未对应真实目标：" + step)
		quit(1)
		return
	await capture(name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	audio_capture = AudioEffectCapture.new()
	audio_capture.buffer_length = 2.0
	AudioServer.add_bus_effect(0, audio_capture)
	hall = load("res://scenes/act2/hall.tscn").instantiate()
	root.add_child(hall)
	hall.set_process(false)
	await capture("opening")
	if hall.actions.phase != "duet":
		push_error("厅堂未直接进入饮前对唱")
		quit(1)
		return
	await capture("duet-xu")
	ActionsInput.advance(
		hall,
		float(hall.audio.config.duet[1].start_ms - hall.audio.config.duet_start_ms) / 1000.0 + .1
	)
	await capture("duet-bai")
	if not ActionsInput.until_phase(hall, "cup"):
		push_error("饮前对唱未完整结束")
		quit(1)
		return
	ActionsInput.advance(hall, 9.0)
	await capture_remedy("remedy-cup-take", "cup_take")
	audio_capture.clear_buffer()
	await create_timer(1.4).timeout
	var peak: float = 0.0
	for sample: Vector2 in audio_capture.get_buffer(audio_capture.get_frames_available()):
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	if peak < .001:
		push_error("第二幕补救慢锣鼓未输出真实混音样本")
		quit(1)
		return
	ActionsInput.take(hall, 1)
	ActionsInput.drag(
		hall,
		hall._views[1].hand_screen_position("right"),
		Vector2(1035, 415) - hall._views[1].hand_screen_position("right")
	)
	await capture("cup-held")
	ActionsInput.drag(hall, hall._views[1].torso_screen_position(), Vector2(-152, 0))
	ActionsInput.advance(hall, 0.2)
	ActionsInput.take(hall, 0)
	ActionsInput.advance(hall, 9.0)
	await capture_remedy("remedy-cup-pass", "cup_pass")
	var offered: Vector2 = hall._views[1].hand_screen_position(hall.actions.cup_hand)
	ActionsInput.drag(
		hall,
		hall._views[0].hand_screen_position("left"),
		offered - hall._views[0].hand_screen_position("left")
	)
	await capture("cup-passed")
	ActionsInput.advance(hall, 9.0)
	await capture_remedy("remedy-drink", "drink")
	ActionsInput.drag(
		hall,
		hall._views[0].hand_screen_position("left"),
		hall._views[0].mouth_screen_position() - hall._views[0].hand_screen_position("left")
	)
	await capture("drink")
	ActionsInput.advance(hall, 0.8)
	if not hall.actions.drunk:
		push_error("图形真实输入未完成饮酒")
		quit(1)
		return
	if hall.actions.phase != "bend" or hall.actions.subtitle().contains("身子有些不适"):
		push_error("饮后未经弯腰就触发不适对白")
		quit(1)
		return
	await capture("before-bend")
	ActionsInput.advance(hall, 9.0)
	await capture_remedy("remedy-bend", "bend")
	ActionsInput.drag(hall, hall._views[0].torso_screen_position(), Vector2(75, 0), true)
	if (
		not hall.actions.bent
		or not hall.actions.subtitle().contains("身子有些不适")
		or hall.remedy.active()
	):
		push_error("实际 Alt 拖腰未完成补救并触发不适对白")
		quit(1)
		return
	await capture("bai-unwell")
	if not ActionsInput.until_phase(hall, "medicine_exit", 10.0):
		push_error("饮后对白未进入取药离场")
		quit(1)
		return
	ActionsInput.take(hall, 1)
	ActionsInput.drag(hall, hall._views[1].torso_screen_position(), Vector2(740, 0))
	ActionsInput.right(hall, 1)
	ActionsInput.advance(hall, 9.0)
	await capture_remedy("remedy-darken", "darken")
	ActionsInput.hold(hall, KEY_Q, 5.0)
	if hall.actions.phase != "replace":
		push_error(
			(
				"真实 Q 输入未压暗换身，phase=%s exposure=%f"
				% [hall.actions.phase, hall.lamp_controller.lamp.exposure]
			)
		)
		quit(1)
		return
	ActionsInput.right(hall, 0)
	ActionsInput.key(hall, KEY_4)
	ActionsInput.key(hall, KEY_SPACE)
	await capture("snake-dark")
	ActionsInput.advance(hall, 9.0)
	await capture_remedy("remedy-reveal", "reveal")
	ActionsInput.hold(hall, KEY_E, 5.0)
	if hall.actions.phase != "return":
		push_error("真实 E 输入未显形")
		quit(1)
		return
	await capture("snake-revealed")
	var before: PackedVector2Array = hall.snake.points.duplicate()
	ActionsInput.drag(hall, hall.snake.head_position(), Vector2(35, -20))
	if hall.snake.points == before:
		push_error("正式拖头没有带动蛇身")
		quit(1)
		return
	await capture("snake-bend")
	var bent: PackedVector2Array = hall.snake.points.duplicate()
	var body_before: Vector2 = hall.snake.position
	ActionsInput.drag(hall, hall.snake.body_position(), Vector2(60, 0))
	ActionsInput.advance(hall, 0.2)
	if hall.snake.points != bent or hall.snake.position.x <= body_before.x + 50:
		push_error("正式拖躯干未保持弯曲姿态整移")
		quit(1)
		return
	await capture("snake-moved")
	ActionsInput.advance(hall, 9.0)
	await capture_remedy("remedy-return", "restore_1")
	ActionsInput.key(hall, KEY_2)
	ActionsInput.take(hall, 1)
	ActionsInput.drag(hall, hall._views[1].torso_screen_position(), Vector2(-690, 0))
	ActionsInput.advance(hall, 0.2)
	await capture("fright")
	ActionsInput.advance(hall, float(hall.audio.config.fright_duration_ms) / 1000.0 + 2.0)
	if hall.actions.phase != "finished":
		push_error("实际返回未完成惊倒")
		quit(1)
		return
	await capture("ending")
	hall.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	print(
		"ACT2_GRAPHICS full actual-input sequence captured, Q/E, snake head/body dragging and ending passed"
	)
	quit(0)
