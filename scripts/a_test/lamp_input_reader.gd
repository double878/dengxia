extends RefCounted
class_name LampInputReader
## 把物理键鼠事件翻译成 LampController 的输入接口。
##
## 只存在于 A 的测试目录：正式入口由后续切片的关卡编排接管。
## 为什么不改 project.godot 注册 InputMap 动作：AGENTS.md 与本切片范围
## 都不允许改工程配置，因此这里直接按物理键码读取。
##
## 临时键位映射（切片 5 专用，未写入任何公共配置）：
##   上 / 下   灯距 distance 增加 / 减少
##   右 / 左   显露度 exposure 增加 / 减少
## 暂停键由测试场景自己处理（与操控场景一致：空格）。

const KEY_DISTANCE_INCREASE: Key = KEY_UP
const KEY_DISTANCE_DECREASE: Key = KEY_DOWN
const KEY_EXPOSURE_INCREASE: Key = KEY_RIGHT
const KEY_EXPOSURE_DECREASE: Key = KEY_LEFT

var lamp: LampController = null
var enabled: bool = true


func set_lamp(value: LampController) -> void:
	lamp = value


func set_enabled(value: bool) -> void:
	enabled = value


## 每帧读取键盘状态并写入油灯的输入快照。
## 整体替换而非逐键累加，避免漏掉「松开」。
func poll_keys() -> void:
	if lamp == null or not enabled:
		return
	lamp.set_input_map({
		"distance_increase": Input.is_key_pressed(KEY_DISTANCE_INCREASE),
		"distance_decrease": Input.is_key_pressed(KEY_DISTANCE_DECREASE),
		"exposure_increase": Input.is_key_pressed(KEY_EXPOSURE_INCREASE),
		"exposure_decrease": Input.is_key_pressed(KEY_EXPOSURE_DECREASE),
	})


## 键位说明，供 HUD 显示。只有一处定义，避免文档与实现漂移。
static func describe_keys() -> String:
	return "↑/↓=灯距增减     ←/→=显露度增减    空格=暂停/继续    F=命中演示    G=错拍演示"
