extends Node2D
## 第二关第二幕正式幕后宿主，复用现有控制、时钟、灯与厅堂。

signal scene_finished

const PuppetView := preload("res://scripts/a_test/placeholder_puppet.gd")
const PuppetInput := preload("res://scripts/a_test/input_reader.gd")
const LampInput := preload("res://scripts/a_test/lamp_input_reader.gd")
const OperatorHand := preload("res://scripts/b/operator_hand.gd")
const Actions := preload("res://scripts/act2/act2_hall_actions.gd")
const CupView := preload("res://scripts/act2/wine_cup_view.gd")
const SnakePose := preload("res://scripts/act2/snake_pose.gd")
const SnakeView := preload("res://scripts/act2/snake_view.gd")
const Remedy := preload("res://scripts/act2/act2_remedy.gd")
const RemedyGuide := preload("res://scripts/act2/remedy_guide.gd")
const MusicCues := preload("res://scripts/act2/act2_music_cues.gd")
const HallAudio := preload("res://scripts/act2/act2_hall_audio.gd")
const CLOTH := Rect2(66, 92, 1788, 588)
const HALL_STAGE_ID: int = 22
const FIGURE_HEIGHT: float = 340.0
const FIXED_DELTA: float = 1.0 / 60.0
const END_HOLD_MS: int = 2200
const HAND_ANCHOR := Vector2(960, 856)
const HAND_AREA := Rect2(768, 755, 384, 213)
const GROUND_Y: float = CSceneryDef.LEVEL2_ACT2_GROUND_Y
const SEAT_Y: float = 525.4
const SEAT_X: Array[float] = [0.4, 0.6]
const CAST: Array[String] = ["白素贞", "许仙", "小青", "白蛇"]

var controller := PuppetController.new()
var clock := MusicClock.new()
var lamp_controller := LampController.new()
var on_stage: Array[int] = [0, 1, 2]
var seated: Array[bool] = [true, true, false]
var _puppet_input := PuppetInput.new()
var _lamp_input := LampInput.new()
var _views: Array[PlaceholderPuppet] = []
var _surface: StageSurface
var _lamp: PlaceholderLamp
var _binding: CStageBinding
var _foreground: Node2D
var _status: Label
var _hint: Label
var _subtitle: Label
var _pause_button: Button
var _paused: bool = false
var _accumulator: float = 0.0
## 跳过按钮的按下事件是否已经让给 GUI；松开事件按这个标记配对放行。
var _skip_press_passed: bool = false
var actions := Actions.new()
var _cup: Node2D
var _cup_projection: Node2D
var snake := SnakePose.new()
var _snake_view: Node2D
var _snake_projection: Node2D
var _snake_controlled: bool = false
var _snake_part: String = ""
var _snake_grab_offset := Vector2.ZERO
var _snake_initialized: bool = false
var _fall_origin := Vector2.ZERO
var _fall_direction: float = 1.0
var remedy := Remedy.new()
var _remedy_banner: Label
var _remedy_audio: AudioStreamPlayer
var music_cues := MusicCues.new()
var audio := HallAudio.new()
var capture: RefCounted
var _end_since_ms: int = -1
var _finished_sent: bool = false
var _pending_remedy_events: Array = []


func _ready() -> void:
	clock.start()
	clock.set_song_frozen(true)
	controller.clock = clock
	controller.setup(3)
	controller.set_controlled_puppet(-1)
	for id in range(3):
		var state: PuppetState = controller.get_puppet(id)
		state.stage_pos = Vector2(SEAT_X[id] if id < 2 else 0.30, GROUND_Y)
		state.facing = -1.0 if id == 1 else 1.0
		state.hand_angle = Vector2.ZERO
	lamp_controller.clock = clock
	lamp_controller.setup()
	_puppet_input.set_controller(controller)
	_lamp_input.set_lamp(lamp_controller)
	var backdrop := StageBackdrop.new()
	backdrop.z_index = -2
	add_child(backdrop)
	_surface = StageSurface.new()
	_surface.z_index = -1
	add_child(_surface)
	_surface.configure(CLOTH)
	for projection: PlaceholderPuppet in _surface.projection_views:
		projection.figure_height = FIGURE_HEIGHT
	_binding = CStageBinding.new()
	_binding.name = "CStageBinding"
	_binding.stage_id = HALL_STAGE_ID
	_binding.enable_rain = false
	add_child(_binding)
	for id in range(3):
		var view: PlaceholderPuppet = PuppetView.new()
		view.name = ["Baisuzhen", "Xuxian", "Xiaoqing"][id]
		view.render_mode = PlaceholderPuppet.RenderMode.ENTITY
		view.figure_height = FIGURE_HEIGHT
		view.hand_anchor = HAND_ANCHOR
		view.z_index = 20
		add_child(view)
		_views.append(view)
	_puppet_input.set_views(_views)
	add_child(audio)
	if not audio.setup(clock):
		clock.set_song_frozen(true)
		set_process(false)
		set_process_input(false)
		return
	actions.setup(clock, audio.config)
	add_child(music_cues)
	music_cues.setup()
	remedy.setup(clock)
	_remedy_audio = AudioStreamPlayer.new()
	_remedy_audio.name = "RemedyDrums"
	var loop: AudioStreamWAV = preload("res://assets/audio/act1-natural/remedy.wav").duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = int(round(loop.get_length() * loop.mix_rate))
	_remedy_audio.stream = loop
	_remedy_audio.volume_db = -6.0
	add_child(_remedy_audio)
	_cup = CupView.new()
	_cup.actions = actions
	_cup.views = _views
	_cup.z_index = 25
	add_child(_cup)
	_cup_projection = CupView.new()
	_cup_projection.actions = actions
	_cup_projection.views = _surface.projection_views
	var cup_material := ShaderMaterial.new()
	cup_material.shader = preload("res://shaders/puppet_transmission.gdshader")
	_cup_projection.material = cup_material
	_surface.projection_viewport.add_child(_cup_projection)
	_snake_view = SnakeView.new()
	_snake_view.name = "WhiteSnake"
	_snake_view.pose = snake
	_snake_view.z_index = 20
	add_child(_snake_view)
	_snake_projection = SnakeView.new()
	_snake_projection.pose = snake
	_snake_projection.projection = true
	_snake_projection.material = cup_material
	_surface.projection_viewport.add_child(_snake_projection)
	_lamp = PlaceholderLamp.new()
	_lamp.z_index = 30
	add_child(_lamp)
	_foreground = Node2D.new()
	_foreground.z_index = 80
	_foreground.draw.connect(_draw_operator_hand)
	add_child(_foreground)
	_build_hud()
	_refresh_views()
	if capture != null:
		capture.begin_scene(self, HALL_STAGE_ID)


func _process(delta: float) -> void:
	if _paused:
		return
	_accumulator += maxf(delta, 0.0)
	var steps: int = 0
	while _accumulator >= FIXED_DELTA and steps < 8:
		_accumulator -= FIXED_DELTA
		steps += 1
		clock.update(FIXED_DELTA)
		snake.tick(FIXED_DELTA)
		_puppet_input.poll_keys()
		_lamp_input.poll_keys()
		controller.tick(FIXED_DELTA)
		lamp_controller.update(FIXED_DELTA)
		var events: Array = controller.take_events()
		events.append_array(lamp_controller.take_events())
		_update_seats()
		_update_actions()
		music_cues.update_fall(actions.collapse_progress)
		_update_remedy()
		events.append_array(_pending_remedy_events)
		_pending_remedy_events = []
		if capture != null:
			_refresh_views()
			capture.capture(self, events)
		_check_finished()
	if steps == 8:
		_accumulator = 0.0
	_refresh_views()


func _check_finished() -> void:
	if _finished_sent or actions.phase != "finished":
		return
	if _end_since_ms < 0:
		_end_since_ms = clock.get_real_time_ms()
	if clock.get_real_time_ms() - _end_since_ms < END_HOLD_MS:
		return
	_finished_sent = true
	if capture == null or capture.finish():
		scene_finished.emit()


func _update_seats() -> void:
	for id in range(2):
		if controller.motion.active() and controller.controlled_id == id:
			seated[id] = false
		if seated[id] and absf(controller.get_puppet(id).stage_pos.x - SEAT_X[id]) > 0.025:
			seated[id] = false


func _update_actions() -> void:
	_refresh_views()
	var hands: Array[Dictionary] = []
	var mouths: Array[Vector2] = []
	var positions: Array[Vector2] = []
	for id in range(3):
		hands.append(
			{
				"left": _views[id].hand_screen_position("left"),
				"right": _views[id].hand_screen_position("right")
			}
		)
		mouths.append(_views[id].mouth_screen_position())
		positions.append(controller.get_puppet(id).stage_pos * PuppetController.STAGE_PIXEL_SIZE)
	var before: String = actions.phase
	var xu: PuppetState = controller.get_puppet(1)
	# 先完成真实翻面，再接惊倒；切断控制不能把影人永久留在压窄的中间帧。
	var visible_facing: float = xu.facing if xu.turn_progress >= 0.99 else 0.0
	actions.update(
		on_stage,
		hands,
		mouths,
		positions,
		lamp_controller.lamp.exposure,
		snake.position,
		visible_facing,
		controller.get_puppet(0).torso_lean
	)
	if before != "startled" and actions.phase == "startled":
		_fall_origin = controller.get_puppet(1).stage_pos
		_fall_direction = signf(_fall_origin.x * 1920.0 - snake.position.x)
		seated[1] = false
		_release_control()
		_puppet_input.set_enabled(false)
	if actions.phase in ["startled", "finished"]:
		var state: PuppetState = controller.get_puppet(1)
		state.stage_pos.x = (
			_fall_origin.x
			+ _fall_direction * 55.0 / 1920.0 * smoothstep(0.0, 0.3, actions.collapse_progress)
		)
		state.head_tilt = -0.25 * actions.collapse_progress
		var settle: float = smoothstep(0.3, 0.95, actions.collapse_progress)
		# 横卧后以衣身厚度支撑在地面上，避免衣摆穿过幕台下缘。
		state.stage_pos.y = _fall_origin.y - FIGURE_HEIGHT * 0.15 / 1080.0 * settle
		state.hand_angle = Vector2(lerpf(1.25, -0.6, settle), lerpf(1.45, -0.6, settle))
		state.elbow_angle = Vector2.ONE * lerpf(0.0, 0.6, settle)


func _input(event: InputEvent) -> void:
	if _skip_button_pressed(event):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_toggle_pause()
		elif not _paused:
			if actions.phase in ["startled", "finished"]:
				get_viewport().set_input_as_handled()
				return
			match event.keycode:
				KEY_W, KEY_S:
					if not _snake_controlled:
						_puppet_input.handle_event(event)
				KEY_1:
					_enter(0)
				KEY_2:
					_enter(1)
				KEY_3:
					_enter(2)
				KEY_4:
					_enter(3)
				KEY_SPACE:
					_take_next()
				KEY_R:
					_end_drag()
					if _snake_controlled:
						snake.reset()
					else:
						controller.reset_upper_body()
		get_viewport().set_input_as_handled()
		return
	if _paused:
		return
	_lamp_input.handle_event(event)
	if actions.phase in ["startled", "finished"]:
		return
	if _snake_controlled and _handle_snake(event):
		get_viewport().set_input_as_handled()
		_refresh_views()
		return
	var puppet_event: InputEvent = event
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			var id: int = _puppet_at(event.position)
			if id >= 0:
				_exit(id)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if controller.controlled_id < 0:
				return
			var view: PlaceholderPuppet = _views[controller.controlled_id]
			if view.hit_upper_body(event.position, event.alt_pressed).is_empty():
				if (
					HAND_AREA.has_point(event.position)
					or (
						event.position.distance_to(view.torso_screen_position())
						< FIGURE_HEIGHT * 0.22
					)
				):
					var translated := event.duplicate() as InputEventMouseButton
					translated.position = (
						controller.get_controlled().stage_pos * PuppetController.STAGE_PIXEL_SIZE
						- Vector2(0, PuppetController.CHEST_TAG_RADIUS_PX * 0.5)
					)
					puppet_event = translated
	if _puppet_input.handle_event(puppet_event):
		get_viewport().set_input_as_handled()
	_update_seats()
	_refresh_views()


## 正式入口注入的「跳过第二关」按钮（`GameFlow._add_skip_button`）：把它矩形内的左键
## 按下与**配对松开**都留给 GUI。这里必须拦：操控白蛇时 `_handle_snake` 会吃掉全屏
## 左键（按下和松开都吃），不拦按钮按不动。`_input` 在 GUI 之前跑，所以只能在这里让路。
## 松开必须跟着按下一起放行，否则按钮收不到松开、永远发不出 `pressed`。
## 第一关的跳过按钮同理（那边幕布输入只在按下时吃事件，所以只判按下也成立）。
func _skip_button_pressed(event: InputEvent) -> bool:
	if not event is InputEventMouseButton:
		return false
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT:
		return false
	if not button.pressed:
		var passed: bool = _skip_press_passed
		_skip_press_passed = false
		return passed
	var skip := get_node_or_null("Hud/SkipAct2Button") as Button
	_skip_press_passed = (
		skip != null
		and skip.is_visible_in_tree()
		and skip.get_global_rect().has_point(button.position)
	)
	return _skip_press_passed


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_end_drag()


func _end_drag() -> void:
	_puppet_input.release_drag()
	_snake_part = ""


func _release_control() -> void:
	_end_drag()
	_snake_controlled = false
	controller.set_controlled_puppet(-1)


func _handle_snake(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_snake_part = _snake_view.hit(event.position)
			_snake_grab_offset = snake.head_position() - event.position
		else:
			_snake_part = ""
		return true
	if event is InputEventMouseMotion and not _snake_part.is_empty():
		if _snake_part == "head":
			snake.drag_head(event.position + _snake_grab_offset)
		else:
			snake.move(event.relative)
		return true
	return false


func _enter(id: int) -> void:
	if id < 0 or id > 3 or on_stage.has(id) or not actions.can_enter(id):
		return
	if id == 3:
		if not _snake_initialized:
			snake.setup(controller.get_puppet(0).stage_pos * PuppetController.STAGE_PIXEL_SIZE)
			_snake_initialized = true
		actions.snake_entered()
	elif id == 1 and actions.medicine_departed and not actions.returned:
		var state: PuppetState = controller.get_puppet(1)
		state.stage_pos = Vector2(0.91, GROUND_Y)
		state.facing = -1.0
		state.turn_progress = 1.0
		actions.enter_return()
	on_stage.append(id)
	on_stage.sort()
	_update_remedy()
	_refresh_views()


func _take_next() -> void:
	if on_stage.is_empty():
		return
	var current: int = 3 if _snake_controlled else controller.controlled_id
	var next: int = on_stage[(on_stage.find(current) + 1) % on_stage.size()]
	_release_control()
	_snake_controlled = next == 3
	controller.set_controlled_puppet(next if next < 3 else -1)
	_puppet_input.set_enabled(not _snake_controlled)
	_refresh_views()


func _exit(id: int) -> void:
	if id == 3:
		on_stage.erase(3)
		if _snake_controlled:
			_release_control()
			_puppet_input.set_enabled(true)
		_update_remedy()
		_refresh_views()
		return
	if id == 0 and actions.phase == "darken":
		return
	var at_edge: bool = (
		controller.get_puppet(id).stage_pos.x <= 0.10
		if id == 2
		else controller.get_puppet(id).stage_pos.x >= 0.90
	)
	actions.leave(id, at_edge)
	if controller.controlled_id == id:
		_release_control()
	on_stage.erase(id)
	if actions.phase in ["dialogue", "duet"]:
		clock.set_song_frozen(true)
	_update_remedy()
	_refresh_views()


func _puppet_at(at: Vector2) -> int:
	for index in range(on_stage.size() - 1, -1, -1):
		var id: int = on_stage[index]
		if id == 3:
			if not _snake_view.hit(at).is_empty():
				return 3
			continue
		var view: PlaceholderPuppet = _views[id]
		var bounds := Rect2(view.head_screen_position() - Vector2(45, 50), Vector2(90, 100))
		bounds = bounds.expand(view.torso_screen_position())
		bounds = bounds.expand(view.hand_screen_position("left"))
		bounds = bounds.expand(view.hand_screen_position("right"))
		if bounds.grow(20).has_point(at):
			return id
	return -1


func _toggle_pause() -> void:
	_paused = not _paused
	_end_drag()
	_puppet_input.set_enabled(
		not _paused and not _snake_controlled and actions.phase not in ["startled", "finished"]
	)
	_lamp_input.set_enabled(not _paused)
	_remedy_audio.stream_paused = _paused
	music_cues.set_paused(_paused)
	controller.set_input_map({})
	if _paused:
		clock.pause()
	else:
		clock.resume()
	_pause_button.text = "继续" if _paused else "暂停"
	_refresh_views()


func _refresh_views() -> void:
	for id in range(3):
		var state: PuppetState = controller.get_puppet(id)
		for view: PlaceholderPuppet in [_views[id], _surface.projection_views[id]]:
			view.puppet_state = state
			view.lamp_state = lamp_controller.lamp
			view.visible = on_stage.has(id)
			view.seated = seated[id]
			view.seat_y = SEAT_Y
			view.fall_angle = (
				_fall_direction * PI * 0.49 * smoothstep(0.15, 0.95, actions.collapse_progress)
				if id == 1
				else 0.0
			)
	_surface.sync_puppets(controller.puppets, on_stage)
	_surface.update_light(
		lamp_controller.lamp, clock.get_real_time_ms(), clock.get_song_time_ms(), clock.bpm
	)
	_cup.on_stage = on_stage
	_cup_projection.on_stage = on_stage
	_cup_projection.transform = _surface.projection_views[0].transform
	_snake_view.visible = on_stage.has(3)
	_snake_projection.visible = on_stage.has(3)
	_snake_view.lamp = lamp_controller.lamp
	_snake_projection.lamp = lamp_controller.lamp
	_snake_view.controlled = _snake_controlled
	_snake_view.drag_part = _snake_part
	_snake_projection.transform = _surface.projection_views[0].transform
	var scenery := _binding.get("_scenery") as CSceneryView
	if scenery != null:
		scenery.set_item_visible("wine_cup_red", actions.cup_owner < 0)
	_lamp.lamp = lamp_controller.lamp
	_lamp.set_visual_time(clock.get_real_time_ms(), clock.get_song_time_ms(), clock.bpm)
	_hint.text = actions.hint()
	_remedy_banner.visible = remedy.active() and not _paused
	_remedy_banner.text = "补救中 · 演出已暂停 · " + remedy.instruction(actions) if remedy.active() else ""
	_subtitle.text = actions.subtitle()
	if _paused:
		_hint.text = "演出已暂停 · ESC 或点击继续"
	elif controller.controlled_id >= 0:
		_hint.text = "正在接手：%s · %s" % [CAST[controller.controlled_id], _hint.text]
	elif _snake_controlled:
		_hint.text = "正在接手：白蛇 · 拖头摆颈身，拖躯干整移 · %s" % _hint.text
	_foreground.queue_redraw()


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "Hud"
	add_child(hud)
	_status = _label(hud, Vector2(76, 18), Vector2(1570, 50), 28)
	_status.text = "第二关 · 端阳惊变    第二幕 · 端阳饮酒"
	_hint = _label(hud, Vector2(80, 1005), Vector2(1770, 55), 22)
	_subtitle = _label(hud, Vector2(130, 690), Vector2(1660, 65), 27)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_remedy_banner = _label(hud, Vector2(100, 962), Vector2(1720, 36), 24)
	_remedy_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_remedy_banner.visible = false
	_pause_button = Button.new()
	_pause_button.position = Vector2(1740, 16)
	_pause_button.size = Vector2(110, 48)
	_pause_button.text = "暂停"
	_pause_button.pressed.connect(_toggle_pause)
	hud.add_child(_pause_button)
	var lamp_hint := _label(hud, Vector2(72, 918), Vector2(640, 46), 22)
	lamp_hint.text = "滚轮推拉灯 · Q/E 显露 · W 短跳 · S 后撤"
	var cast_hint := _label(hud, Vector2(1210, 795), Vector2(630, 90), 22)
	cast_hint.text = "1 白素贞    2 许仙\n3 小青      4 白蛇"


func _label(parent: Node, at: Vector2, size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#e7c590"))
	parent.add_child(label)
	return label


func _draw_operator_hand() -> void:
	OperatorHand.draw_on(
		_foreground, HAND_ANCHOR, 0.65 + 0.35 * StageLight.unit(lamp_controller.lamp.oil)
	)
	if remedy.active() and not _paused:
		var guide: Dictionary = _remedy_target()
		RemedyGuide.draw_on(
			_foreground, CLOTH, guide.start, guide.target, guide.label, clock.get_real_time_s()
		)


func _update_remedy() -> void:
	remedy.update(actions, on_stage, lamp_controller.lamp.exposure)
	var events: Array = remedy.take_events()
	# 第二关漏做的剧情动作没有 cue_fire，明确记录为 missed_outright。
	for event: Dictionary in events:
		if str(event.kind) == "cue_miss":
			event.payload["reason"] = "missed_outright"
		if int(event.get("object_id", 0)) == 3:
			event["object_id"] = "white_snake"
	lamp_controller.update(0.0, events)
	if remedy.active():
		if not _remedy_audio.playing:
			_remedy_audio.play()
	elif _remedy_audio.playing:
		_remedy_audio.stop()
	# 输入帧也可能完成补救；把事件留在宿主队列供下一固定步采集。
	_pending_remedy_events.append_array(events)


func _remedy_target() -> Dictionary:
	var id: String = remedy.guide_step()
	var actor: int = int(remedy.STEPS[id])
	var start: Vector2 = (
		_views[actor].torso_screen_position() if actor < 3 else snake.body_position()
	)
	var target: Vector2 = start
	var label: String = ""
	match id:
		"qing_exit":
			target.x = 180
			label = "向左走 · 右键退场"
		"medicine_exit":
			target.x = 1740
			label = "向右走 · 右键退场"
		"cup_take":
			start = _views[1].hand_screen_position("right")
			target = actions.CUP_POSITION
			label = "拖手取红杯"
		"cup_pass":
			start = _views[0].hand_screen_position("left")
			target = _views[1].hand_screen_position(actions.cup_hand)
			label = "两人的手靠近"
		"drink":
			start = _views[0].hand_screen_position(actions.cup_hand)
			target = _views[0].mouth_screen_position()
			label = "送到嘴边 · 保持"
		"bend":
			target = start + Vector2(75 * controller.get_puppet(0).facing, 0)
			label = "Alt 拖躯干 · 弯腰"
		"darken", "reveal":
			start = Vector2(272, 844)
			target = start + Vector2(0, 60 if id == "darken" else -60)
			label = "按住 Q 压暗" if id == "darken" else "按住 E 调亮"
		"replace":
			label = "右键收白素贞"
		"snake_entry":
			label = "按 4 上白蛇"
		"return":
			target = snake.position + Vector2(280, -100)
			label = "面对白蛇 · 走近"
		_:
			if id.begins_with("restore_"):
				start = Vector2(1400 + actor * 100, 824)
				target = start + Vector2(0, -80)
				label = "按 %d 上场 · 空格接手" % (actor + 1)
	return {"start": start, "target": target, "label": label}


func _exit_tree() -> void:
	_end_drag()
	_puppet_input.set_enabled(false)
	_lamp_input.set_enabled(false)
	clock.pause()
	if _remedy_audio != null:
		_remedy_audio.stream_paused = false
		_remedy_audio.stop()
		_remedy_audio.stream = null
