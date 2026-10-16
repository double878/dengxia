extends Node2D
## 第三幕单场连续演出：上山、求情、双童交战、仙翁赠草。
signal performance_finished(record: CPerformanceRecord, stage_id: int, title: String)

const PuppetInput := preload("res://scripts/a_test/input_reader.gd")
const LampInput := preload("res://scripts/a_test/lamp_input_reader.gd")
const OperatorHand := preload("res://scripts/b/operator_hand.gd")
const TeacherHand := preload("res://scripts/b/teacher_hand.gd")
const Actions := preload("res://scripts/act3/act3_actions.gd")
const Audio := preload("res://scripts/act3/act3_audio.gd")
const Sword := preload("res://scripts/act3/sword_view.gd")
const Capture := preload("res://scripts/c/c_act3_capture.gd")
const GuardEntrance := preload("res://scripts/act3/guard_entrance.gd")
const Fight := preload("res://scripts/act3/fight_choreography.gd")
const Finale := preload("res://scripts/act3/finale_choreography.gd")
const FinaleView := preload("res://scripts/act3/finale_view.gd")
const CLOTH := CStageBinding.CLOTH
const HAND_ANCHOR := Vector2(960, 856)
const HAND_AREA := Rect2(768, 712, 384, 256)
const FIGURE_HEIGHT: float = 310.0
const FIXED_DELTA: float = 1.0 / 60.0
const CAST: Array[String] = ["白素贞", "鹿童", "鹤童"]
const SKINS: Array[int] = [0, 5, 6]

var controller := PuppetController.new()
var clock := MusicClock.new()
var lamp_controller := LampController.new()
var on_stage: Array[int] = []
var actions := Actions.new()
var audio := Audio.new()
var capture := Capture.new()
var guard_entrance := GuardEntrance.new()
var fight := Fight.new()
var finale := Finale.new()
var _finale_view: Node2D
var _projected_finale: Node2D
var _puppet_input := PuppetInput.new()
var _lamp_input := LampInput.new()
var _views: Array[PlaceholderPuppet] = []
var _surface: StageSurface
var _binding: CStageBinding
var _lamp: PlaceholderLamp
var _sword: Node2D
var _projected_sword: Node2D
var _swords: Array[Node2D] = []
var _projected_swords: Array[Node2D] = []
var _foreground: Node2D
var _status: Label
var _intent: Label
var _subtitle: Label
var _control: Label
var _motion_hint: Label
var _pause_button: Button
var _cast_buttons: Array[Button] = []
var _card: Control
var _audio_note: Label
var _started: bool = false
var _paused: bool = false
var _emitted: bool = false
var _accumulator: float = 0.0
var _finished_at: int = -1


func _ready() -> void:
	controller.clock = clock
	controller.setup(3)
	controller.set_controlled_puppet(-1)
	for id in range(3):
		var state: PuppetState = controller.get_puppet(id)
		state.stage_pos = Vector2(.14 if id == 0 else .82, 642.0 / 1080.0)
		state.facing = 1.0 if id == 0 else -1.0
		state.turn_progress = 1.0
		state.hand_angle = Vector2.ZERO
	lamp_controller.clock = clock
	lamp_controller.setup()
	_puppet_input.set_controller(controller)
	_lamp_input.set_lamp(lamp_controller)
	var backdrop := StageBackdrop.new()
	backdrop.name = "StageBackdrop"
	backdrop.z_index = -2
	add_child(backdrop)
	_surface = StageSurface.new()
	_surface.name = "StageSurface"
	_surface.z_index = -1
	add_child(_surface)
	_surface.configure(CLOTH)
	_binding = CStageBinding.new()
	_binding.name = "CStageBinding"
	_binding.stage_id = 3
	_binding.enable_rain = false
	add_child(_binding)
	for id in range(3):
		var view := PlaceholderPuppet.new()
		view.name = ["Baisuzhen", "Bailu", "Baihe"][id]
		view.skin_override = SKINS[id]
		view.figure_height = FIGURE_HEIGHT
		view.render_mode = PlaceholderPuppet.RenderMode.ENTITY
		view.hand_anchor = HAND_ANCHOR
		view.z_index = 20
		add_child(view)
		_views.append(view)
		var projection: PlaceholderPuppet = _surface.projection_views[id]
		projection.skin_override = view.skin_override
		projection.figure_height = FIGURE_HEIGHT
	for id in range(3):
		var sword: Node2D = Sword.new()
		sword.actor_id = id
		sword.views = _views
		sword.z_index = 21
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/puppet_back.gdshader")
		sword.material = material
		add_child(sword)
		_swords.append(sword)
		var projected: Node2D = Sword.new()
		projected.actor_id = id
		projected.views = _surface.projection_views
		var projection_material := ShaderMaterial.new()
		projection_material.shader = preload("res://shaders/puppet_transmission.gdshader")
		projected.material = projection_material
		_surface.projection_viewport.add_child(projected)
		_projected_swords.append(projected)
	_sword = _swords[1]
	_projected_sword = _projected_swords[1]
	guard_entrance.setup(CLOTH)
	_finale_view = FinaleView.new()
	_finale_view.z_index = 22
	add_child(_finale_view)
	_finale_view.setup(_views, false)
	_finale_view.mask = guard_entrance.mask
	_projected_finale = FinaleView.new()
	_surface.projection_viewport.add_child(_projected_finale)
	_projected_finale.setup(_surface.projection_views, true)
	_projected_finale.mask = guard_entrance.mask
	_lamp = PlaceholderLamp.new()
	_lamp.name = "OilLamp"
	_lamp.cloth_rect = CLOTH
	_lamp.z_index = 30
	add_child(_lamp)
	_foreground = Node2D.new()
	_foreground.z_index = 80
	_foreground.draw.connect(_draw_operator)
	add_child(_foreground)
	_build_hud()
	add_child(audio)
	if not audio.setup(clock):
		actions.phase = "error"
		_intent.text = audio.problem
	else:
		actions.setup(clock, controller, audio.config)
		fight.setup(audio.config, controller)
		finale.setup(audio.config)
	_puppet_input.set_views(_views)
	_refresh_views()


func start_scene() -> void:
	if _started or actions.phase == "error":
		return
	_started = true
	_card.hide()
	actions.start()
	_pause_button.disabled = false
	capture.capture(self)
	_refresh_views()


func _process(delta: float) -> void:
	if not _started or _paused or _emitted or actions.phase == "error":
		return
	_accumulator += maxf(delta, 0.0)
	var steps: int = 0
	while _accumulator >= FIXED_DELTA and steps < 8:
		_accumulator -= FIXED_DELTA
		steps += 1
		clock.update(FIXED_DELTA)
		_puppet_input.poll_keys()
		_lamp_input.poll_keys()
		controller.tick(FIXED_DELTA)
		lamp_controller.update(FIXED_DELTA)
		for state: PuppetState in controller.puppets:
			state.stage_pos.x = clampf(state.stage_pos.x, .08, .88)
		guard_entrance.update(
			FIXED_DELTA,
			controller,
			on_stage,
			clock.get_song_time_ms(),
			int(audio.config.gates[1].at_ms)
		)
		fight.update(FIXED_DELTA, clock.get_song_time_ms(), on_stage)
		finale.update(FIXED_DELTA, clock.get_song_time_ms(), controller, on_stage)
		if fight.active and controller.controlled_id > 0:
			_release_control()
			if on_stage.has(0):
				controller.set_controlled_puppet(0)
		_update_contacts()
		actions.update(on_stage, lamp_controller.lamp.exposure, guard_entrance.triggered)
		var events: Array = controller.take_events()
		events.append_array(lamp_controller.take_events())
		events.append_array(actions.take_events())
		capture.capture(self, events)
	if steps == 8:
		_accumulator = 0.0
	_refresh_views()
	if actions.phase == "finished":
		if _finished_at < 0:
			_finished_at = clock.get_real_time_ms()
		var hold_ms: int = 0 if actions.departure_requested else 1200
		if clock.get_real_time_ms() - _finished_at >= hold_ms:
			_release_control()
			capture.capture(self, controller.take_events())
			if capture.finish():
				_emitted = true
				_puppet_input.set_enabled(false)
				_lamp_input.set_enabled(false)
				if audio.player != null:
					audio.player.stop()
				performance_finished.emit(capture.record, 3, "盗仙草")


func _input(event: InputEvent) -> void:
	if not _started or _emitted or actions.phase == "error":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_toggle_pause()
		elif not _paused and actions.phase != "finished":
			match event.keycode:
				KEY_W, KEY_S:
					_puppet_input.handle_event(event)
					if event.keycode == KEY_W:
						fight.begin_jump_cut()
				KEY_1:
					_enter(0)
				KEY_2:
					_enter(1)
				KEY_SPACE:
					_take_next()
				KEY_R:
					_puppet_input.release_drag()
					controller.reset_upper_body()
		get_viewport().set_input_as_handled()
		return
	if _paused or actions.phase == "finished":
		return
	var translated: InputEvent = event
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			var id: int = _puppet_at(event.position)
			if id >= 0:
				_exit(id)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_LEFT and HAND_AREA.has_point(event.position):
			var state: PuppetState = controller.get_controlled()
			if state != null:
				translated = event.duplicate()
				translated.position = state.stage_pos * controller.STAGE_PIXEL_SIZE - Vector2(0, 45)
	_lamp_input.handle_event(event)
	if _puppet_input.handle_event(translated):
		get_viewport().set_input_as_handled()


func _enter(id: int) -> void:
	if not _started or _paused or _emitted or actions.phase == "finished" or on_stage.has(id):
		return
	if id == 2 or (id == 1 and fight.active):
		return
	if id == 1 and (not guard_entrance.triggered or guard_entrance.active):
		return
	on_stage.append(id)
	on_stage.sort()
	_refresh_views()


func _take_next() -> void:
	if on_stage.is_empty():
		return
	var available: Array[int] = on_stage.duplicate()
	if fight.active:
		available.erase(1)
		available.erase(2)
	if guard_entrance.active:
		available.erase(1)
	if available.is_empty():
		return
	var next: int = available[(available.find(controller.controlled_id) + 1) % available.size()]
	_release_control()
	controller.set_controlled_puppet(next)
	_refresh_views()


func _release_control() -> void:
	_puppet_input.release_drag()
	controller.set_controlled_puppet(-1)


func _exit(id: int) -> void:
	if not _started or _paused or _emitted or actions.phase == "finished" or not on_stage.has(id):
		return
	if id > 0 and fight.active:
		return
	if id == 1 and guard_entrance.active:
		return
	if controller.controlled_id == id:
		_release_control()
	on_stage.erase(id)
	actions.actor_exited(id)
	_refresh_views()


func _puppet_at(point: Vector2) -> int:
	for id: int in on_stage:
		var view: PlaceholderPuppet = _views[id]
		var state: PuppetState = controller.get_puppet(id)
		var foot: Vector2 = (
			view.stage_to_screen(state.stage_pos) - Vector2(0, state.air_height * 1080.0)
		)
		var height: float = view.figure_px_height()
		var bounds := Rect2(
			foot - Vector2(height * .28, height * 1.15), Vector2(height * .56, height * 1.2)
		)
		bounds = bounds.expand(view.hand_screen_position("left")).expand(
			view.hand_screen_position("right")
		)
		bounds = bounds.expand(view.head_top_screen_position())
		if bounds.grow(12).has_point(point):
			return id
	return -1


func _toggle_pause() -> void:
	if not _started or _emitted:
		return
	_paused = not _paused
	_puppet_input.set_enabled(not _paused)
	_lamp_input.set_enabled(not _paused)
	controller.set_input_map({})
	if _paused:
		clock.pause()
	else:
		clock.resume()
	_pause_button.text = "继续" if _paused else "暂停"
	_refresh_views()


func _refresh_views() -> void:
	var progress: Array[float] = fight.sword_progress()
	_surface.sync_puppets(controller.puppets, on_stage)
	for id in range(3):
		_views[id].puppet_state = controller.get_puppet(id)
		_views[id].lamp_state = lamp_controller.lamp
		_views[id].visible = on_stage.has(id)
		for view: PlaceholderPuppet in [_views[id], _surface.projection_views[id]]:
			view._held_prop_hand = Sword.holding_hand(id) if progress[id] > .01 else ""
		for sword: Node2D in [_swords[id], _projected_swords[id]]:
			sword.on_stage = on_stage.duplicate()
			sword.draw_progress = progress[id]
			sword.flash_point = fight.flash_point
			sword.flash = fight.flash_strength(clock.get_song_time_ms())
		_projected_swords[id].transform = _surface.projection_views[id].transform
	_surface.update_light(
		lamp_controller.lamp, clock.get_real_time_ms(), clock.get_song_time_ms(), clock.bpm
	)
	_projected_finale.transform = _surface.projection_views[0].transform
	_finale_view.sync(finale.recorded_view(), lamp_controller.lamp)
	_projected_finale.sync(finale.recorded_view(), lamp_controller.lamp)
	var deer_behind: bool = (
		guard_entrance.behind_mountain or fight.phase == "deer_retreat" or finale.deer_behind
	)
	guard_entrance.apply_mask(_views, _sword, deer_behind)
	guard_entrance.apply_mask(_surface.projection_views, _projected_sword, deer_behind)
	guard_entrance.apply_mask(_views, _swords[2], fight.crane_behind_mountain, 2)
	guard_entrance.apply_mask(
		_surface.projection_views, _projected_swords[2], fight.crane_behind_mountain, 2
	)
	_lamp.lamp = lamp_controller.lamp
	_lamp.set_visual_time(clock.get_real_time_ms(), clock.get_song_time_ms(), clock.bpm)
	_status.text = "第三关 · 盗仙草"
	if not bool(audio.config.get("audio_available", false)):
		_status.text += "    原声待补 · 字幕排练"
		_audio_note.text = "录屏未录入声音；当前为字幕排练，原声待补。"
	else:
		_audio_note.text = "声音：视频原声"
	if actions.phase == "error":
		_audio_note.text = audio.problem
		_card.get_node("StartScene").disabled = true
	_subtitle.text = actions.subtitle() if _started else ""
	_intent.text = "演出已暂停" if _paused else actions.intent()
	if actions.remedy.has_open_windows():
		_intent.text = "补救中 · 演出已暂停    " + actions.intent()
	_control.text = "候场" if controller.controlled_id < 0 else "接手：" + CAST[controller.controlled_id]
	_motion_hint.text = (
		("W 张腿跳劈" if fight.draw_progress >= .99 else "W 张腿短跳") + " · S 压身后撤 · 拖手操演"
	)
	for id in range(3):
		var entry: String = "上场"
		if id == 2:
			entry = "随唱词自动接战"
		elif id == 1 and fight.active:
			entry = "自动配合演出"
		elif id == 1 and not guard_entrance.triggered:
			entry = "近山自动出场"
		elif id == 1 and guard_entrance.active:
			entry = "跃出山门"
		elif on_stage.has(id):
			entry = "在场"
		_cast_buttons[id].text = ("%d   %s\n%s" % [id + 1, CAST[id], entry])
		_cast_buttons[id].disabled = (
			_paused
			or not _started
			or _emitted
			or id == 2
			or (id == 1 and fight.active)
			or (id == 1 and (not guard_entrance.triggered or guard_entrance.active))
		)
	_foreground.queue_redraw()


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "Hud"
	add_child(hud)
	_status = _label(hud, Vector2(76, 18), Vector2(1600, 50), 26)
	_subtitle = _label(hud, Vector2(140, 695), Vector2(1640, 60), 28)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intent = _label(hud, Vector2(80, 1002), Vector2(1760, 50), 25)
	_control = _label(hud, Vector2(850, 930), Vector2(500, 44), 24)
	_motion_hint = _label(hud, Vector2(76, 935), Vector2(730, 38), 21)
	_pause_button = Button.new()
	_pause_button.position = Vector2(1740, 16)
	_pause_button.size = Vector2(110, 48)
	_pause_button.text = "暂停"
	_pause_button.disabled = true
	_pause_button.pressed.connect(_toggle_pause)
	hud.add_child(_pause_button)
	for id in range(3):
		var button := Button.new()
		button.position = Vector2(1330 + id * 185, 790)
		button.size = Vector2(175, 100)
		button.add_theme_font_size_override("font_size", 21)
		button.pressed.connect(_enter.bind(id))
		hud.add_child(button)
		_cast_buttons.append(button)
	_card = Control.new()
	_card.size = Vector2(1920, 1080)
	hud.add_child(_card)
	var background := ColorRect.new()
	background.size = _card.size
	background.color = Color("#1d2422")
	_card.add_child(background)
	var title := _label(_card, Vector2(290, 220), Vector2(1340, 100), 48)
	title.text = "盗仙草"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var text := _label(_card, Vector2(340, 365), Vector2(1240, 210), 30)
	text.text = "为救许郎，白素贞奔赴仙山，遇双童拦路，拔剑交锋。\n仙翁出山止战，赠草相助，嘱她速回镇江救夫。\n你操演白素贞；末尾谢别后，可跃起并右键退场，完成这一幕。"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var controls := _label(_card, Vector2(310, 600), Vector2(1300, 110), 23)
	controls.text = "1 白素贞上场 · 鹿童近山随重音出场 · 空格接手\n拖签走位摆剑 · W 张腿短跳 · S 压身后撤 · Alt 前倾 · R 复位 · Q / E 调灯 · ESC 暂停"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_audio_note = _label(_card, Vector2(310, 725), Vector2(1300, 70), 23)
	_audio_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var start := Button.new()
	start.name = "StartScene"
	start.position = Vector2(740, 825)
	start.size = Vector2(440, 80)
	start.text = "开演"
	start.add_theme_font_size_override("font_size", 30)
	start.pressed.connect(start_scene)
	_card.add_child(start)


func _update_contacts() -> void:
	if (
		not fight.active
		or fight.active_actor < 0
		or fight.draw_progress < .99
		or not on_stage.has(0)
	):
		return
	for id in range(3):
		_views[id].puppet_state = controller.get_puppet(id)
		_swords[id].draw_progress = fight.sword_progress()[id]
	var white: Dictionary = _swords[0].geometry()
	var opponent: Dictionary = _swords[fight.active_actor].geometry()
	if white.is_empty() or opponent.is_empty():
		return
	var point: Variant = Geometry2D.segment_intersects_segment(
		white.wrist, white.tip, opponent.wrist, opponent.tip
	)
	if point != null:
		fight.contact(point, clock.get_song_time_ms())


func _label(parent: Node, at: Vector2, size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#e7c590"))
	parent.add_child(label)
	return label


func _draw_operator() -> void:
	OperatorHand.draw_on(
		_foreground, HAND_ANCHOR, .65 + .35 * StageLight.unit(lamp_controller.lamp.oil)
	)
	if _paused or not actions.remedy.has_open_windows():
		return
	var id: String = actions.remedy.current_demo_cue_id
	var actor: int = int(actions.remedy.get_cue(id).get("target_object", 0))
	var point: Vector2 = _views[actor].torso_screen_position()
	var movement := Vector2(120, 0)
	var window: Dictionary = actions.remedy.get_window(id)
	var progress: float = (
		float(clock.get_real_time_ms() - int(window.get("started_ms", 0))) / 1800.0
	)
	point += movement * (1.0 - cos(progress * TAU)) * .5
	TeacherHand.draw_on(_foreground, point, true, .85)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_puppet_input.release_drag()


func _exit_tree() -> void:
	_puppet_input.set_enabled(false)
	_lamp_input.set_enabled(false)
	clock.pause()
