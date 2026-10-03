extends RefCounted
class_name LampState
## 油灯运行状态。契约见 TECH_DESIGN.md 第 2.3 节与任务书切片 5。
##
## 单位：四个量都是归一化 0.0-1.0 的连续量，0.0 与 1.0 都是合法边界值。
## - distance    灯距控制量（滚轮推拉灯的抽象量；越大表示灯离影人越近）
## - exposure    显露度控制量（Q/E 倾灯，幕布上影子的显露程度）
## - oil         剩余灯油比例；只由统一歌曲时间推进消耗，输入不得直接修改，
##               不可回升，不可低于 0.0
## - flame_feedback 由合拍表现驱动的火焰反馈强度；A 侧判定结果写入，
##               B 的表现层只读，不得反向修改
##
## 单向数据流（TECH_DESIGN.md 2.3）：A 先改本状态，再把 TimedEvent 写入队列；
## B 的显示与 C 的录制在同一帧读状态，因此一定读到改动后的值。

const UNIT_MIN: float = 0.0
const UNIT_MAX: float = 1.0

## 判定「字段是否变化」的比较阈值。
## 不能用 is_equal_approx：它按相对误差工作（约 1e-5），而单帧灯油消耗量级只有
## 1.5e-4 的百分之一，会被它判成「没变」，导致灯油事件整帧丢失。
const CHANGE_EPSILON: float = 1.0e-9

var distance: float = 0.5
var exposure: float = 0.5
var oil: float = 1.0
var flame_feedback: float = 0.5


## 把所有连续量收进合法区间。每次 update 结束后都必须调用。
func clamp_continuous() -> void:
	distance = clampf(distance, UNIT_MIN, UNIT_MAX)
	exposure = clampf(exposure, UNIT_MIN, UNIT_MAX)
	oil = clampf(oil, UNIT_MIN, UNIT_MAX)
	flame_feedback = clampf(flame_feedback, UNIT_MIN, UNIT_MAX)


## 四个连续量是否都落在合法区间内（诊断与断言用，不修改状态）。
func is_in_range() -> bool:
	return _in_unit(distance) and _in_unit(exposure) and _in_unit(oil) \
		and _in_unit(flame_feedback)


## 与另一份状态快照相比，哪些字段发生了变化。changed_fields 按固定顺序输出，
## 保证同一帧的事件内容可复现（不依赖字典迭代顺序）。
func changed_fields(before: Dictionary) -> Array:
	var out: Array = []
	if _differs(float(before.get("distance", distance)), distance):
		out.append("distance")
	if _differs(float(before.get("exposure", exposure)), exposure):
		out.append("exposure")
	if _differs(float(before.get("oil", oil)), oil):
		out.append("oil")
	if _differs(float(before.get("flame_feedback", flame_feedback)), flame_feedback):
		out.append("flame_feedback")
	return out


## 供 C 的录制、B 的显示与测试读取的纯数据视图。
func to_dict() -> Dictionary:
	return {
		"distance": distance,
		"exposure": exposure,
		"oil": oil,
		"flame_feedback": flame_feedback,
	}


func _in_unit(value: float) -> bool:
	return value >= UNIT_MIN and value <= UNIT_MAX


func _differs(a: float, b: float) -> bool:
	return absf(a - b) > CHANGE_EPSILON
