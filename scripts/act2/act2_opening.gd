extends Node2D
## 第二关第一幕操演与动作许可对白；整关录放由后续切片接入。

## 第一幕收场（末句应允 → 暗场 → 「端阳」标题停留）走完，可以换景进第二幕了。
## 由宿主 `game_flow.gd` 接住：换到 `scenes/act2/hall.tscn`（编号 22 的厅堂布景）。
signal scene_finished

const PuppetView := preload("res://scripts/a_test/placeholder_puppet.gd")
const PuppetInput := preload("res://scripts/a_test/input_reader.gd")
const LampInput := preload("res://scripts/a_test/lamp_input_reader.gd")
const OperatorHand := preload("res://scripts/b/operator_hand.gd")
const Entrance := preload("res://scripts/act2/act2_entrance.gd")
const Dialogue := preload("res://scripts/act2/act2_dialogue.gd")
const CLOTH := Rect2(66, 92, 1788, 588)
const HAND_ANCHOR := Vector2(960, 856)
const HAND_AREA := Rect2(768, 712, 384, 256)
## 冠帽计入实际轮廓后接近房门上沿，实体与投影共用站立尺寸。
const FIGURE_HEIGHT: float = 200.0
const FIXED_DELTA: float = 1.0 / 60.0
const CAST: Array[String] = ["法海", "许仙"]
## 暗场后到换景之间，让「端阳」标题停留的时间（秒）。
## PRD 第 6.2 节要求「应允后自动暗场、清场换景」，两场之间不出现结算或回放。
## 幕面在 `duration_ms` 处已经全黑，此处只留一小段章节卡时间再发 `scene_finished`；
## 不留这段时间的话，「端阳」标题一帧都不会被看到。
const DARK_HOLD_S: float = 1.5

var controller := PuppetController.new()
var clock := MusicClock.new()
var lamp_controller := LampController.new()
var on_stage: Array[int] = []
var _puppet_input := PuppetInput.new()
var _lamp_input := LampInput.new()
var _views: Array[PlaceholderPuppet] = []
var _surface: StageSurface
var _lamp: PlaceholderLamp
var _foreground: Node2D
var _status: Label
var _hint: Label
var _pause_button: Button
var _cast_labels: Array[Label] = []
var _paused: bool = false
var _accumulator: float = 0.0
var _entrance := Entrance.new()
var _entrance_complete: Array[bool] = [false, false]
var dialogue := Dialogue.new()
## 暗场后章节卡的剩余停留时间（秒）。< 0 表示尚未进入收场。
var _dark_hold: float = -1.0
var _subtitle: Label
var _dark: ColorRect
var _transition_title: Label


func _ready() -> void:
	clock.start()
	# 先准备唯一时钟；正式主轨绑定后停在就位等待，真实时间供火光使用。
	clock.set_song_frozen(true)
	controller.clock = clock
	controller.setup(2)
	controller.controlled_id = -1
	_entrance.setup(CLOTH)
	for id in range(2):
		var state: PuppetState = controller.get_puppet(id)
		state.is_controlled = false
		state.stage_pos = _entrance.positions[id]
		state.facing = -1.0 if id == 0 else 1.0
		state.hand_angle = Vector2(0.1, PI * 0.5) if id == 0 else Vector2.ZERO
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
	_surface.projection_views[0].skin_override = 3
	for projection: PlaceholderPuppet in _surface.projection_views:
		projection.figure_height = FIGURE_HEIGHT
	var binding := CStageBinding.new()
	binding.name = "CStageBinding"
	binding.stage_id = 2
	binding.enable_rain = false
	add_child(binding)
	for id in range(2):
		var view: PlaceholderPuppet = PuppetView.new()
		view.name = "Fahai" if id == 0 else "Xuxian"
		view.render_mode = PlaceholderPuppet.RenderMode.ENTITY
		view.figure_height = FIGURE_HEIGHT
		view.skin_override = 3 if id == 0 else -1
		view.hand_anchor = HAND_ANCHOR
		view.z_index = 20
		add_child(view)
		_views.append(view)
	_lamp = PlaceholderLamp.new()
	_lamp.z_index = 30
	add_child(_lamp)
	_foreground = Node2D.new()
	_foreground.z_index = 80
	_foreground.draw.connect(_draw_operator_hand)
	add_child(_foreground)
	_build_hud()
	add_child(dialogue)
	dialogue.finished.connect(_finish_first_scene)
	dialogue.setup(clock, controller)
	_refresh_views()
	_puppet_input.set_views(_views)


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
		_sync_entrances()
		dialogue.update(on_stage, _entrance_complete[0])
	if steps == 8:
		_accumulator = 0.0
	_refresh_views()
	_advance_dark_hold(delta)


## 收场章节卡倒计时。倒计时结束后发一次 `scene_finished`，由宿主换景进第二幕。
## 停在暂停时 `_process` 提前返回，倒计时也随之停住（与演出其余部分同口径）。
func _advance_dark_hold(delta: float) -> void:
	if _dark_hold < 0.0:
		return
	_dark_hold -= delta
	if _dark_hold > 0.0:
		return
	_dark_hold = -1.0
	scene_finished.emit()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_toggle_pause()
		elif not _paused:
			if dialogue.phase in ["closing", "finished", "error"]:
				get_viewport().set_input_as_handled()
				return
			match event.keycode:
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
	if _paused or dialogue.phase in ["closing", "finished", "error"]:
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
			if (
				not _entrance_complete[controller.controlled_id]
				and _entrance.blocks_point(controller.controlled_id, event.position)
			):
				return
			var translated := event.duplicate() as InputEventMouseButton
			translated.position = _grab_position(event.position)
			puppet_event = translated
	_lamp_input.handle_event(event)
	if _puppet_input.handle_event(puppet_event):
		get_viewport().set_input_as_handled()


func _grab_position(at: Vector2) -> Vector2:
	var controlled: PuppetState = controller.get_controlled()
	if controlled == null or not HAND_AREA.has_point(at):
		return at
	# 手边抓签映射到当前影人的胸签；影人移动或换人后仍能在手边抓住。
	return (
		controlled.stage_pos * PuppetController.STAGE_PIXEL_SIZE
		- Vector2(0, PuppetController.CHEST_TAG_RADIUS_PX * 0.5)
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_puppet_input.release_drag()


func _enter(id: int) -> void:
	if dialogue.phase in ["closing", "finished", "error"]:
		return
	if id == 1 and dialogue.phase in ["wait_arrival", "first_line"]:
		return
	if on_stage.has(id):
		return
	on_stage.append(id)
	on_stage.sort()
	_refresh_views()


func _release_control() -> void:
	_puppet_input.release_drag()
	controller.set_controlled_puppet(-1)


func _take_next() -> void:
	if on_stage.is_empty():
		return
	var index: int = on_stage.find(controller.controlled_id)
	var next: int = on_stage[(index + 1) % on_stage.size()]
	_release_control()
	controller.set_controlled_puppet(next)
	_refresh_views()


func _exit(id: int) -> void:
	if controller.controlled_id == id:
		_release_control()
	on_stage.erase(id)
	_refresh_views()


func _puppet_at(at: Vector2) -> int:
	for index in range(on_stage.size() - 1, -1, -1):
		var id: int = on_stage[index]
		var view: PlaceholderPuppet = _views[id]
		var ground: Vector2 = view.stage_to_screen(controller.get_puppet(id).stage_pos)
		var height: float = view.figure_px_height()
		var bounds := Rect2(
			ground - Vector2(height * 0.27, height * 1.15), Vector2(height * 0.54, height * 1.2)
		)
		bounds = bounds.expand(view.hand_screen_position("left"))
		bounds = bounds.expand(view.hand_screen_position("right"))
		if bounds.grow(14).has_point(at):
			if not _entrance_complete[id] and _entrance.blocks_point(id, at):
				continue
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
	for id in range(_views.size()):
		_views[id].puppet_state = controller.get_puppet(id)
		_views[id].lamp_state = lamp_controller.lamp
		_views[id].visible = on_stage.has(id)
	_surface.sync_puppets(controller.puppets, on_stage)
	_surface.update_light(
		lamp_controller.lamp, clock.get_real_time_ms(), clock.get_song_time_ms(), clock.bpm
	)
	_sync_entrances()
	_lamp.lamp = lamp_controller.lamp
	_lamp.set_visual_time(clock.get_real_time_ms(), clock.get_song_time_ms(), clock.bpm)
	_status.text = "第二关 · 端阳惊变    第一幕 · 法海劝酒"
	if _paused:
		_hint.text = "演出已暂停 · 按 ESC 或点击继续"
	elif on_stage.is_empty():
		_hint.text = "按 1 请法海上场 · 空格接手后向左走出柳树"
	elif controller.controlled_id < 0:
		_hint.text = "按空格接手在场影人"
	else:
		_hint.text = (
			"正在接手：%s    空格换人 · 左键拖胸签或手边竹签 · A/D 抬手 · 右键点影人下场" % CAST[controller.controlled_id]
		)
		if not _entrance_complete[controller.controlled_id]:
			_hint.text = (
				"正在接手：%s · 左键拖手边竹签%s · 空格换人 · 右键退场" % [CAST[controller.controlled_id], "向左走出树后"]
			)
	for id in range(_cast_labels.size()):
		_cast_labels[id].text = (
			"%d    %s\n%s" % [id + 1, CAST[id], "已上场" if on_stage.has(id) else "待上场"]
		)
	queue_redraw()
	_foreground.queue_redraw()
	if not _paused and not on_stage.is_empty():
		_hint.text = dialogue.get_hint()
		if controller.controlled_id >= 0 and not _hint.text.is_empty():
			_hint.text = "正在接手：%s · %s" % [CAST[controller.controlled_id], _hint.text]
		if (
			dialogue.phase not in ["wait_arrival", "first_line", "wait_greeting"]
			and (not on_stage.has(0) or not on_stage.has(1))
		):
			_hint.text = "按 1 请法海上场，按 2 请许仙上场 · 重新上场保留原姿势"
	var line: Dictionary = dialogue.get_line()
	_subtitle.text = "" if line.is_empty() else "%s：%s" % [line.role_name, line.text]
	_dark.color.a = dialogue.fade_amount()
	_transition_title.visible = dialogue.phase == "finished"


func _sync_entrances() -> void:
	for id in range(_views.size()):
		var entity: PlaceholderPuppet = _views[id]
		var projection: PlaceholderPuppet = _surface.projection_views[id]
		if (
			on_stage.has(id)
			and not _entrance_complete[id]
			and _entrance.has_cleared(id, entity, projection)
		):
			_entrance_complete[id] = true
		var mask: Texture2D = null if _entrance_complete[id] else _entrance.masks[id]
		entity.entrance_mask = mask
		projection.entrance_mask = mask


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	_status = _label(hud, Vector2(76, 18), Vector2(1570, 50), 28)
	_hint = _label(hud, Vector2(80, 1005), Vector2(1770, 55), 26)
	_pause_button = Button.new()
	_pause_button.position = Vector2(1740, 16)
	_pause_button.size = Vector2(110, 48)
	_pause_button.add_theme_font_size_override("font_size", 24)
	_pause_button.pressed.connect(_toggle_pause)
	hud.add_child(_pause_button)
	_pause_button.text = "暂停"
	for id in range(2):
		var label := _label(hud, Vector2(1385 + id * 210, 782), Vector2(180, 86), 24)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_cast_labels.append(label)
	var lamp_hint := _label(hud, Vector2(72, 918), Vector2(680, 46), 22)
	lamp_hint.text = "滚轮推拉灯 · Q/E 调整显露"
	var hand_hint := _label(hud, Vector2(790, 925), Vector2(440, 46), 22)
	hand_hint.text = "空格接手 · 一次操纵一人"
	var pose_hint := _label(hud, Vector2(790, 966), Vector2(1040, 35), 19)
	pose_hint.text = "拖手签摆双臂 · 拖头调俯仰 · Alt 拖躯干前倾 · R 恢复上身"
	_subtitle = _label(hud, Vector2(130, 690), Vector2(1660, 65), 27)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var transition := CanvasLayer.new()
	transition.layer = 10
	add_child(transition)
	_dark = ColorRect.new()
	_dark.size = Vector2(1920, 1080)
	_dark.color = Color(0, 0, 0, 0)
	_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition.add_child(_dark)
	_transition_title = _label(transition, Vector2(460, 460), Vector2(1000, 160), 56)
	_transition_title.text = "端阳"
	_transition_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_transition_title.visible = false


func _label(parent: Node, at: Vector2, size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#e7c590"))
	parent.add_child(label)
	return label


func _draw() -> void:
	for id in range(2):
		draw_style_box(_card_style(on_stage.has(id)), Rect2(1370 + id * 210, 760, 190, 130))


func _draw_operator_hand() -> void:
	OperatorHand.draw_on(
		_foreground, HAND_ANCHOR, 0.65 + 0.35 * StageLight.unit(lamp_controller.lamp.oil)
	)
	if not _paused and on_stage.has(0):
		var target_x := -1.0
		var id := 0
		if dialogue.phase == "wait_arrival":
			target_x = dialogue.arrival_target_x * 1920.0
		elif dialogue.phase == "wait_greeting" and on_stage.has(1):
			target_x = dialogue.greeting_target_x * 1920.0
			id = 1
		if target_x >= CLOTH.position.x and target_x < CLOTH.end.x:
			var y := controller.get_puppet(id).stage_pos.y * 1080.0 + 6.0
			_foreground.draw_line(
				Vector2(target_x - 34, y), Vector2(target_x + 34, y), Color("e7c590"), 3
			)
			_foreground.draw_line(
				Vector2(target_x, y - 10), Vector2(target_x, y), Color("e7c590"), 3
			)


func _card_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#42372a") if active else Color("#25251f")
	style.border_color = Color("#af8c52")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style


func _exit_tree() -> void:
	_puppet_input.set_enabled(false)
	_lamp_input.set_enabled(false)
	clock.pause()
	if is_instance_valid(dialogue.player):
		dialogue.player.stop()


func _finish_first_scene() -> void:
	_release_control()
	on_stage.clear()
	_puppet_input.set_enabled(false)
	_lamp_input.set_enabled(false)
	# 末句应允 → 暗场 → 清场；标题停留 DARK_HOLD_S 后换景进第二幕。
	_dark_hold = DARK_HOLD_S
	_refresh_views()
