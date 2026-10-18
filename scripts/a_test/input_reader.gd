extends RefCounted
class_name InputReader
## 把物理键鼠事件翻译成 PuppetController 的输入接口。
## 只存在于 A 的测试目录：正式入口由 StageDirector 在切片 3 接管。
##
## 为什么不改 project.godot 注册 InputMap 动作：AGENTS.md 与本次任务范围
## 都不允许改工程配置，因此这里直接按物理键码与鼠标按钮读取。

const PuppetControllerScript := preload("res://scripts/a/puppet_controller.gd")

var controller: PuppetController = null
var scale_factor: float = 1.0  ## 虚拟画布像素 / 虚拟舞台像素；画布尺寸与舞台一致时为 1.0
var enabled: bool = true

var _drag_active: bool = false
var views: Array = []
var _upper_part: String = ""
var _upper_id: int = -1
var _upper_position: Vector2 = Vector2.ZERO
var _grab_offset: Vector2 = Vector2.ZERO


func set_views(value: Array) -> void:
	views = value
	for view: PlaceholderPuppet in views:
		view.show_upper_controls = true


func _controlled_view() -> PlaceholderPuppet:
	if (
		controller == null
		or controller.controlled_id < 0
		or controller.controlled_id >= views.size()
	):
		return null
	var view: PlaceholderPuppet = views[controller.controlled_id]
	return view if is_instance_valid(view) and view.visible and view.puppet_state != null else null


func set_controller(value: PuppetController) -> void:
	controller = value


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	if not value:
		release_drag()
		for view: PlaceholderPuppet in views:
			view.upper_hover_part = ""
	enabled = value


## 每帧读取键盘状态并写入控制器的输入快照。
func poll_keys() -> void:
	if controller == null or not enabled:
		return
	var shift: bool = Input.is_key_pressed(KEY_SHIFT)
	(
		controller
		. set_input_map(
			{
				"left_raise": Input.is_key_pressed(KEY_A) and not shift,
				"left_lower": Input.is_key_pressed(KEY_A) and shift,
				"right_raise": Input.is_key_pressed(KEY_D) and not shift,
				"right_lower": Input.is_key_pressed(KEY_D) and shift,
			}
		)
	)


## 处理一个鼠标事件。返回 true 表示该事件被本读取器消费。
func handle_event(event: InputEvent) -> bool:
	if controller == null or not enabled:
		return false
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode in [KEY_W, KEY_S]:
			if controller.motion.active():
				return true
			release_drag()
			var view: PlaceholderPuppet = _controlled_view()
			# 桥顶等高处收小跳高，给头冠留出幕布边缘；时长和张腿保持一致。
			var jump_px: float = (
				clampf(view.head_top_screen_position().y - 142.0, 24.0, 115.0)
				if view != null else 115.0
			)
			return controller.start_motion("jump" if event.keycode == KEY_W else "dodge", jump_px)
		if event.pressed and not event.echo and event.keycode == KEY_R:
			release_drag()
			controller.reset_upper_body()
			return true
		return false
	if controller.motion.active():
		return event is InputEventMouseButton or event is InputEventMouseMotion
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return false
		if button.pressed:
			var stage_pos: Vector2 = window_to_stage(button.position)
			var view: PlaceholderPuppet = _controlled_view()
			var part: String = (
				view.hit_upper_body(stage_pos, button.alt_pressed) if view != null else ""
			)
			if not part.is_empty():
				release_drag()
				_upper_part = part
				_upper_id = controller.controlled_id
				_upper_position = stage_pos
				_grab_offset = (
					view.hand_screen_position(part) - stage_pos
					if part in ["left", "right"]
					else Vector2.ZERO
				)
				controller.upper_drag_hand = part if part in ["left", "right"] else ""
				view.upper_drag_part = part
				return true
			_drag_active = controller.begin_drag(controller.controlled_id, stage_pos)
			return _drag_active
		if is_drag_active():
			release_drag()
			return true
		return false
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if not _upper_part.is_empty():
			var view: PlaceholderPuppet = _controlled_view()
			if view == null or controller.controlled_id != _upper_id:
				release_drag()
				return false
			var delta: Vector2 = stage_delta(motion.relative)
			_upper_position += delta
			if _upper_part in ["left", "right"]:
				controller.set_hand_target(
					_upper_part,
					view.hand_target_offset(_upper_position + _grab_offset, _upper_part),
					view.figure_px_height()
				)
			else:
				var state: PuppetState = view.puppet_state
				var step: float = delta.x * state.facing * 2.0 / view.figure_px_height()
				var angle: float = state.torso_lean + step
				if _upper_part == "head":
					angle = state.head_tilt + step * view.pose_reference_facing()
				controller.set_upper_angle(_upper_part, angle)
			return true
		update_hover(window_to_stage(motion.position), motion.alt_pressed)
		if not _drag_active:
			return false
		# 只使用 relative，避免与 position 差分重复计数
		controller.drag_to(stage_delta(motion.relative))
		return true
	return false


## 松开拖动。在 _input 之外单独调用，便于测试与失去焦点时收尾。
func release_drag() -> void:
	if controller == null:
		return
	controller.end_drag()
	_drag_active = false
	_upper_part = ""
	_upper_id = -1
	for view: PlaceholderPuppet in views:
		view.upper_drag_part = ""


func is_drag_active() -> bool:
	return _drag_active or not _upper_part.is_empty()


func update_hover(point: Vector2, alt: bool = false) -> void:
	for view: PlaceholderPuppet in views:
		view.upper_hover_part = ""
	var view: PlaceholderPuppet = _controlled_view()
	if enabled and view != null:
		view.upper_hover_part = view.hit_upper_body(point, alt)
		if view.upper_hover_part.is_empty() and view.hit_upper_body(point, true) == "torso":
			view.upper_hover_part = "torso"


## 窗口坐标 → 虚拟舞台像素坐标。
## 画布等比缩放时，鼠标事件落在虚拟画布坐标空间里；scale_factor 是
## 「虚拟画布像素 / 虚拟舞台像素」，用它把位移换回舞台尺度，手感保持不变。
func window_to_stage(window_pos: Vector2) -> Vector2:
	return window_pos / scale_factor


func stage_delta(relative: Vector2) -> Vector2:
	return relative / scale_factor
