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


func set_controller(value: PuppetController) -> void:
	controller = value


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	if not value:
		release_drag()
	enabled = value


## 每帧读取键盘状态并写入控制器的输入快照。
func poll_keys() -> void:
	if controller == null or not enabled:
		return
	var shift: bool = Input.is_key_pressed(KEY_SHIFT)
	controller.set_input_map({
		"left_raise": Input.is_key_pressed(KEY_A) and not shift,
		"left_lower": Input.is_key_pressed(KEY_A) and shift,
		"right_raise": Input.is_key_pressed(KEY_D) and not shift,
		"right_lower": Input.is_key_pressed(KEY_D) and shift,
		"both_raise": Input.is_key_pressed(KEY_W),
		"both_lower": Input.is_key_pressed(KEY_S),
	})


## 处理一个鼠标事件。返回 true 表示该事件被本读取器消费。
func handle_event(event: InputEvent) -> bool:
	if controller == null or not enabled:
		return false
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return false
		if button.pressed:
			var stage_pos: Vector2 = window_to_stage(button.position)
			_drag_active = controller.begin_drag(controller.controlled_id, stage_pos)
			return _drag_active
		if _drag_active:
			release_drag()
			return true
		return false
	if event is InputEventMouseMotion and _drag_active:
		var motion := event as InputEventMouseMotion
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


func is_drag_active() -> bool:
	return _drag_active


## 窗口坐标 → 虚拟舞台像素坐标。
## 画布等比缩放时，鼠标事件落在虚拟画布坐标空间里；scale_factor 是
## 「虚拟画布像素 / 虚拟舞台像素」，用它把位移换回舞台尺度，手感保持不变。
func window_to_stage(window_pos: Vector2) -> Vector2:
	return window_pos / scale_factor


func stage_delta(relative: Vector2) -> Vector2:
	return relative / scale_factor
