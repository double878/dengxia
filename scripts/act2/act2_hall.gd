extends Node2D
## 第二关第二幕正式幕后宿主，复用现有控制、时钟、灯与厅堂。

const PuppetView := preload("res://scripts/a_test/placeholder_puppet.gd")
const PuppetInput := preload("res://scripts/a_test/input_reader.gd")
const LampInput := preload("res://scripts/a_test/lamp_input_reader.gd")
const OperatorHand := preload("res://scripts/b/operator_hand.gd")
const CLOTH := Rect2(66, 92, 1788, 588)
const HALL_STAGE_ID: int = 22
const FIGURE_HEIGHT: float = 340.0
const FIXED_DELTA: float = 1.0 / 60.0
const HAND_ANCHOR := Vector2(960, 856)
const HAND_AREA := Rect2(768, 755, 384, 213)
const GROUND_Y: float = CSceneryDef.LEVEL2_ACT2_GROUND_Y
const SEAT_Y: float = 525.4
const SEAT_X: Array[float] = [0.4, 0.6]
const CAST: Array[String] = ["白素贞", "许仙", "小青"]

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
	_lamp = PlaceholderLamp.new()
	_lamp.z_index = 30
	add_child(_lamp)
	_foreground = Node2D.new()
	_foreground.z_index = 80
	_foreground.draw.connect(_draw_operator_hand)
	add_child(_foreground)
	_build_hud()
	_refresh_views()


func _process(delta: float) -> void:
	if _paused:
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
		controller.take_events()
		lamp_controller.take_events()
		_update_seats()
	if steps == 8:
		_accumulator = 0.0
	_refresh_views()


func _update_seats() -> void:
	for id in range(2):
		if seated[id] and absf(controller.get_puppet(id).stage_pos.x - SEAT_X[id]) > 0.025:
			seated[id] = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_toggle_pause()
		elif not _paused:
			match event.keycode:
				KEY_1: _enter(0)
				KEY_2: _enter(1)
				KEY_3: _enter(2)
				KEY_SPACE: _take_next()
				KEY_R:
					_puppet_input.release_drag()
					controller.reset_upper_body()
		get_viewport().set_input_as_handled()
		return
	if _paused:
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
				if HAND_AREA.has_point(event.position) or event.position.distance_to(view.torso_screen_position()) < FIGURE_HEIGHT * 0.22:
					var translated := event.duplicate() as InputEventMouseButton
					translated.position = controller.get_controlled().stage_pos * PuppetController.STAGE_PIXEL_SIZE - Vector2(0, PuppetController.CHEST_TAG_RADIUS_PX * 0.5)
					puppet_event = translated
	_lamp_input.handle_event(event)
	if _puppet_input.handle_event(puppet_event):
		get_viewport().set_input_as_handled()
	_update_seats()
	_refresh_views()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_puppet_input.release_drag()


func _enter(id: int) -> void:
	if id < 0 or id >= 3 or on_stage.has(id):
		return
	on_stage.append(id)
	on_stage.sort()
	_refresh_views()


func _take_next() -> void:
	if on_stage.is_empty():
		return
	var next: int = on_stage[(on_stage.find(controller.controlled_id) + 1) % on_stage.size()]
	_puppet_input.release_drag()
	controller.set_controlled_puppet(next)
	_refresh_views()


func _exit(id: int) -> void:
	if controller.controlled_id == id:
		_puppet_input.release_drag()
		controller.set_controlled_puppet(-1)
	on_stage.erase(id)
	_refresh_views()


func _puppet_at(at: Vector2) -> int:
	for index in range(on_stage.size() - 1, -1, -1):
		var id: int = on_stage[index]
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
	for id in range(3):
		var state: PuppetState = controller.get_puppet(id)
		for view: PlaceholderPuppet in [_views[id], _surface.projection_views[id]]:
			view.puppet_state = state
			view.lamp_state = lamp_controller.lamp
			view.visible = on_stage.has(id)
			view.seated = seated[id]
			view.seat_y = SEAT_Y
	_surface.sync_puppets(controller.puppets, on_stage)
	_surface.update_light(lamp_controller.lamp, clock.get_real_time_ms(), clock.get_song_time_ms(), clock.bpm)
	_lamp.lamp = lamp_controller.lamp
	_lamp.set_visual_time(clock.get_real_time_ms(), clock.get_song_time_ms(), clock.bpm)
	_hint.text = "空格接手 · 1 白素贞 / 2 许仙 / 3 小青 · 拖手、拖头、Alt 拖躯干 · R 恢复上身"
	if _paused:
		_hint.text = "演出已暂停 · ESC 或点击继续"
	elif controller.controlled_id >= 0:
		_hint.text = "正在接手：%s · %s" % [CAST[controller.controlled_id], _hint.text]
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
	_pause_button = Button.new()
	_pause_button.position = Vector2(1740, 16)
	_pause_button.size = Vector2(110, 48)
	_pause_button.text = "暂停"
	_pause_button.pressed.connect(_toggle_pause)
	hud.add_child(_pause_button)
	var lamp_hint := _label(hud, Vector2(72, 918), Vector2(640, 46), 22)
	lamp_hint.text = "滚轮推拉灯 · Q/E 调整显露 · 空格换人"


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
	OperatorHand.draw_on(_foreground, HAND_ANCHOR, 0.65 + 0.35 * StageLight.unit(lamp_controller.lamp.oil))


func _exit_tree() -> void:
	_puppet_input.set_enabled(false)
	_lamp_input.set_enabled(false)
	clock.pause()
