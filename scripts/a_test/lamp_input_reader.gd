extends RefCounted
class_name LampInputReader
## 把物理键鼠事件翻译成 LampController 的输入接口。
##
## 只存在于 A 的测试目录：正式入口由后续切片的关卡编排接管。
## 为什么不改 project.godot 注册 InputMap 动作：AGENTS.md 与本切片范围
## 都不允许改工程配置，因此这里直接按物理键码读取。
##
## 测试场景键位映射（不写入任何公共 InputMap）：
##   鼠标滚轮上 / 下   灯距 distance 增加 / 减少
##   Q / E             显露度 exposure 降低 / 增加
## 暂停键由测试场景自己处理（与操控场景一致：空格）。

const KEY_EXPOSURE_DECREASE: Key = KEY_Q
const KEY_EXPOSURE_INCREASE: Key = KEY_E

var lamp: LampController = null
var enabled: bool = true
var _wheel_distance_direction: int = 0


func set_lamp(value: LampController) -> void:
	lamp = value


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		_wheel_distance_direction = 0


## 接收离散滚轮输入。滚轮方向只保留到下一次 poll_keys，避免暂停后补发旧输入。
func handle_event(event: InputEvent) -> void:
	if not enabled or not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	match mouse_event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_wheel_distance_direction = 1
		MOUSE_BUTTON_WHEEL_DOWN:
			_wheel_distance_direction = -1


## 每帧读取键盘状态并写入油灯的输入快照。
## 整体替换而非逐键累加，避免漏掉「松开」。
func poll_keys() -> void:
	if lamp == null or not enabled:
		return
	lamp.set_input_map({
		"distance_increase": _wheel_distance_direction > 0,
		"distance_decrease": _wheel_distance_direction < 0,
		"exposure_increase": Input.is_key_pressed(KEY_EXPOSURE_INCREASE),
		"exposure_decrease": Input.is_key_pressed(KEY_EXPOSURE_DECREASE),
	})
	_wheel_distance_direction = 0


## 键位说明，供 HUD 显示。只有一处定义，避免文档与实现漂移。
static func describe_keys() -> String:
	return "滚轮=灯距增减     Q/E=显露度减/增    空格=暂停/继续    F=命中演示    G=错拍演示"
