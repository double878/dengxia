extends Node2D
## 幕前表现端：只读 CReplayPlayer 的记录帧，不接操影输入或评分模块。

signal finished
var flow: CResultFlow
var stage_id: int = 1
var title: String = "幕前回放"
var _surface: StageSurface
var _binding: CStageBinding
var _umbrella := UmbrellaController.new()
var _audio: Act1OperaAudio
var _metronome: Metronome
var _states: Array = []
var _lamp := LampState.new()
var _pause_button: Button
var _time_label: Label
var _subtitle: Label
var _last_frame: Dictionary = {}


func _ready() -> void:
	var background := ColorRect.new()
	background.size = Vector2(1920, 1080)
	background.color = Color("#1d2422")
	background.z_index = -3
	add_child(background)
	_surface = StageSurface.new()
	_surface.front_view = true
	_surface.z_index = -1
	add_child(_surface)
	_surface.configure(Rect2(66, 92, 1788, 588))
	_binding = preload("res://scripts/c/c_stage_binding.gd").new()
	_binding.stage_id = stage_id
	# 布景和雨幕先于影人合成，再随整个幕面镜像；布景不受影人灯距变换影响。
	_binding.z_index = -16
	_surface.projection_viewport.add_child(_binding)
	for id in range(3):
		_states.append(PuppetState.new(id))
	if stage_id == 1:
		_audio = Act1OperaAudio.new()
		add_child(_audio)
		if not _audio.setup_replay(Act1OperaAudio.read_config()):
			push_error("幕前回放音源加载失败：%s" % _audio.problems)
	else:
		_metronome = preload("res://scripts/a_test/metronome.gd").new()
		add_child(_metronome)
		_metronome.setup(MusicClock.new())
	var heading := Label.new()
	heading.text = title + " · 幕前回放"
	heading.position = Vector2(66, 20)
	heading.add_theme_font_size_override("font_size", 30)
	add_child(heading)
	_subtitle = Label.new()
	_subtitle.position = Vector2(120, 710)
	_subtitle.size = Vector2(1680, 65)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 30)
	add_child(_subtitle)
	_time_label = Label.new()
	_time_label.position = Vector2(66, 820)
	_time_label.add_theme_font_size_override("font_size", 26)
	add_child(_time_label)
	_pause_button = _button("暂停回放", Vector2(1050, 810), toggle_pause)
	_button("跳过回放", Vector2(1450, 810), _skip)
	apply_frame(flow.player_frame())


func _button(text: String, at: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = Vector2(330, 72)
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(action)
	add_child(button)
	return button


func _process(delta: float) -> void:
	if not flow.is_replaying():
		return
	apply_frame(flow.advance(delta))
	if not flow.is_replaying():
		finished.emit()


func apply_frame(frame: Dictionary) -> void:
	_last_frame = frame
	for view: Dictionary in frame.get("puppets", []):
		var state: PuppetState = _states[int(view.puppet_id)]
		state.stage_pos = Vector2(float(view.stage_pos.x), float(view.stage_pos.y))
		state.hand_angle = Vector2(float(view.hand_angle.left), float(view.hand_angle.right))
		var elbows: Dictionary = view.get("elbow_angle", {})
		state.elbow_angle = Vector2(float(elbows.get("left", 0.0)), float(elbows.get("right", 0.0)))
		state.head_tilt = float(view.get("head_tilt", 0.0))
		state.torso_lean = float(view.get("torso_lean", 0.0))
		for key: String in [
			"stance",
			"facing",
			"turn_progress",
			"head_id",
			"hook_slot",
			"is_controlled",
			"walk_phase",
			"walk_amount"
		]:
			if view.has(key):
				state.set(key, view[key])
	for key: String in frame.get("lamp", {}):
		_lamp.set(key, frame.lamp[key])
	var performance: Dictionary = frame.get("performance", {})
	_umbrella.apply_recorded_view(performance.get("umbrella", {}))
	_surface.sync_puppets(_states, performance.get("on_stage", [0, 1, 2]), _umbrella)
	_surface.update_light(
		_lamp,
		int(frame.now_ms),
		int(performance.get("song_ms", frame.now_ms)),
		float(performance.get("bpm", 96))
	)
	_binding.set_visual_time(int(frame.now_ms))
	if _metronome != null:
		_metronome.clock.bpm = float(performance.get("bpm", 96))
		_metronome.apply_replay_state(
			bool(performance.get("frozen", false)), frame.state == &"paused"
		)
	_time_label.text = (
		"%d:%02d / %d:%02d"
		% [
			int(frame.now_ms) / 60000,
			(int(frame.now_ms) / 1000) % 60,
			flow.get_replay_duration_ms() / 60000,
			(flow.get_replay_duration_ms() / 1000) % 60
		]
	)
	if _audio != null:
		_audio.apply_replay(
			performance.get("audio", {}), frame.get("events", []), frame.state == &"paused"
		)
		var line_text: String = ""
		for line: Dictionary in _audio.config.lines:
			if (
				int(performance.get("song_ms", 0)) >= int(line.start_ms)
				and int(performance.get("song_ms", 0)) < int(line.end_ms)
			):
				line_text = "%s：%s" % [line.role_name, line.text]
				break
		_subtitle.text = line_text


func toggle_pause() -> void:
	if flow.get_player().get_state() == &"paused":
		flow.resume()
		_pause_button.text = "暂停回放"
	else:
		flow.pause()
		_pause_button.text = "继续回放"
	if _audio != null:
		_audio.set_replay_paused(flow.get_player().get_state() == &"paused")
	apply_frame(flow.player_frame())


func _skip() -> void:
	flow.skip()
	finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		toggle_pause()
		get_viewport().set_input_as_handled()


func stop() -> void:
	set_process(false)
	set_process_unhandled_input(false)
	if _audio != null:
		_audio.stop()
	if _metronome != null:
		_metronome.stop()


func _exit_tree() -> void:
	stop()
