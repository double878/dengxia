extends RefCounted
class_name PuppetState
## 单个影人的运行状态。契约见 docs/superpowers/plans/2026-10-03-level1-a.md 第 1.2 节。
## A 写入本对象；B 的显示与 C 的录制只读，不写。
## 单位：stage_pos 为归一化 0-1（接地点）；stance 0-1；facing -1..1；hand_angle 为弧度。

const HEAD_ID_NONE: int = -1        ## 未分配头部
const HEAD_ID_MIN: int = 0          ## 头部编号下限
const HEAD_ID_MAX: int = 5          ## 头部编号上限（三个影人初始头 + 三个备用头）
const HOOK_SLOT_NONE: int = -1      ## 未挂起
const HOOK_SLOT_MIN: int = 0        ## 挂钩槽位下限
const HOOK_SLOT_MAX: int = 1        ## 挂钩槽位上限（两个挂钩）

var puppet_id: int = -1
var stage_pos: Vector2 = Vector2(0.5, 0.0)  ## 接地点在幕布中的归一化位置
var stance: float = 0.0                     ## 0.0 完全站立，1.0 完全蹲下
var facing: float = 0.0                     ## -1.0 面向左，0.0 正面，+1.0 面向右
var turn_progress: float = 0.0              ## abs(facing)，转身过渡完成程度
var hand_angle: Vector2 = Vector2.ZERO      ## x = 左手，y = 右手（弧度）
var head_id: int = HEAD_ID_NONE
var hook_slot: int = HOOK_SLOT_NONE
var is_controlled: bool = false

## 连续量范围。PuppetController 与 clamp_continuous() 共用同一组上下限。
const STAGE_POS_MIN: float = 0.0
const STAGE_POS_MAX: float = 1.0
const STANCE_MIN: float = 0.0
const STANCE_MAX: float = 1.0
const FACING_MIN: float = -1.0
const FACING_MAX: float = 1.0
const HAND_ANGLE_MIN: float = -0.6
const HAND_ANGLE_MAX: float = 0.6


func _init(p_id: int = -1) -> void:
	puppet_id = p_id


## 把所有连续量收进合法区间，并同步 turn_progress。每次 tick 结束后都必须调用。
func clamp_continuous() -> void:
	stage_pos.x = clampf(stage_pos.x, STAGE_POS_MIN, STAGE_POS_MAX)
	stage_pos.y = clampf(stage_pos.y, STAGE_POS_MIN, STAGE_POS_MAX)
	stance = clampf(stance, STANCE_MIN, STANCE_MAX)
	facing = clampf(facing, FACING_MIN, FACING_MAX)
	turn_progress = absf(facing)
	hand_angle.x = clampf(hand_angle.x, HAND_ANGLE_MIN, HAND_ANGLE_MAX)
	hand_angle.y = clampf(hand_angle.y, HAND_ANGLE_MIN, HAND_ANGLE_MAX)


## 幂等的合法性修复：编号越界时报告错误并回到最近的合法值，不静默通过。
func sanitize_ids() -> void:
	if puppet_id < 0:
		push_error("PuppetState 的 puppet_id 非法：%d" % puppet_id)
		puppet_id = 0
	if head_id != HEAD_ID_NONE and (head_id < HEAD_ID_MIN or head_id > HEAD_ID_MAX):
		push_error("PuppetState(%d) 的 head_id 越界：%d" % [puppet_id, head_id])
		head_id = HEAD_ID_NONE
	if hook_slot != HOOK_SLOT_NONE and (hook_slot < HOOK_SLOT_MIN or hook_slot > HOOK_SLOT_MAX):
		push_error("PuppetState(%d) 的 hook_slot 越界：%d" % [puppet_id, hook_slot])
		hook_slot = HOOK_SLOT_NONE


## 供 C 的录制与测试读取的纯数据视图。Vector2 展开为具名标量，避免 JSON 化歧义。
func to_dict() -> Dictionary:
	return {
		"puppet_id": puppet_id,
		"stage_pos": {"x": stage_pos.x, "y": stage_pos.y},
		"stance": stance,
		"facing": facing,
		"turn_progress": turn_progress,
		"hand_angle": {"left": hand_angle.x, "right": hand_angle.y},
		"head_id": head_id,
		"hook_slot": hook_slot,
		"is_controlled": is_controlled,
	}
