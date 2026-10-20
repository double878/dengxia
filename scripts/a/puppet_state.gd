extends RefCounted
class_name PuppetState
## 单个影人的运行状态。契约见 docs/superpowers/plans/2026-10-03-level1-a.md 第 1.2 节。
## A 写入本对象；B 的显示与 C 的录制只读，不写。
## 单位：stage_pos 为归一化 0-1（接地点）；stance 0-1；facing 二值 ±1；hand_angle 为弧度。

const HEAD_ID_NONE: int = -1  ## 未分配头部
const HEAD_ID_MIN: int = 0  ## 头部编号下限
const HEAD_ID_MAX: int = 5  ## 头部编号上限（三个影人初始头 + 三个备用头）
const HOOK_SLOT_NONE: int = -1  ## 未挂起
const HOOK_SLOT_MIN: int = 0  ## 挂钩槽位下限
const HOOK_SLOT_MAX: int = 1  ## 挂钩槽位上限（两个挂钩）

## 影人是一张只有正反两面的皮影，所以「沿移动方向转身」在本项目里实现成一次快速翻面，
## facing 因此是二值：+1 = 正面朝外，-1 = 反面朝外。翻面的过程由 turn_progress 表达。
const FACING_BACK: float = -1.0
const FACING_FRONT: float = 1.0

var puppet_id: int = -1
var stage_pos: Vector2 = Vector2(0.5, 0.0)  ## 接地点在幕布中的归一化位置
var stance: float = 0.0  ## 0.0 完全站立，1.0 完全蹲下
var facing: float = FACING_FRONT  ## 二值：+1 正面朝外，-1 反面朝外
var turn_progress: float = 1.0  ## 翻面过渡完成度：1 = 已停稳在某一面
var hand_angle: Vector2 = Vector2.ZERO  ## x = 左手，y = 右手（弧度）
var elbow_angle: Vector2 = Vector2.ZERO  ## 左右肘的屈曲角，零为直臂
var head_tilt: float = 0.0  ## 头部绕颈部俯仰，弧度
var torso_lean: float = 0.0  ## 腰部前倾，弧度；下半身不参与
var head_id: int = HEAD_ID_NONE
var hook_slot: int = HOOK_SLOT_NONE
var is_controlled: bool = false
var walk_phase: float = 0.0  ## 距离驱动的连续迈步相位（弧度）
var walk_amount: float = 0.0  ## 0 收脚站定，1 小步走；回放原样读取
var air_height: float = 0.0  ## 相对脚下地面的腾空高度，归一化舞台单位
var leg_spread: float = 0.0  ## 0 并腿，1 空中张腿
var body_angle: float = 0.0  ## 整身绕髋倾转，世界弧度；与强制跌倒无关

## 连续量范围。PuppetController 与 clamp_continuous() 共用同一组上下限。
const STAGE_POS_MIN: float = 0.0
const STAGE_POS_MAX: float = 1.0
const STANCE_MIN: float = 0.0
const STANCE_MAX: float = 1.0
const FACING_MIN: float = -1.0
const FACING_MAX: float = 1.0
const TURN_PROGRESS_MIN: float = 0.0
const TURN_PROGRESS_MAX: float = 1.0
## 手角范围（弧度）。0 = 手臂自然垂下（开局位），+π/2 = 水平前伸，+π = 举过头顶；
## 负值表示手臂向内收，给「落手」与收手姿势留余地。
## 这是**硬边界**：某一折实际能抬到多高还要看该关的手角上界
## （`StageDef.hand_angle_max_rad`，第 1 关收到 90° 的打伞位；由 PuppetController 执行）。
const HAND_ANGLE_MIN: float = -PI * 0.5
const HAND_ANGLE_MAX: float = PI


func _init(p_id: int = -1) -> void:
	puppet_id = p_id


## 把所有连续量收进合法区间。每次 tick 结束后都必须调用。
## facing 是二值量，不做区间 clamp，而是吸附到最近的合法面：B/C 传入 0 之类的非法值
## 也会自愈，不会让影人停在「没有面」的状态上。
func clamp_continuous() -> void:
	stage_pos.x = clampf(stage_pos.x, STAGE_POS_MIN, STAGE_POS_MAX)
	stage_pos.y = clampf(stage_pos.y, STAGE_POS_MIN, STAGE_POS_MAX)
	stance = clampf(stance, STANCE_MIN, STANCE_MAX)
	facing = FACING_FRONT if facing >= 0.0 else FACING_BACK
	turn_progress = clampf(turn_progress, TURN_PROGRESS_MIN, TURN_PROGRESS_MAX)
	walk_amount = clampf(walk_amount, 0.0, 1.0)
	air_height = clampf(air_height, 0.0, .3)
	leg_spread = clampf(leg_spread, 0.0, 1.0)
	body_angle = clampf(body_angle, -PI, PI)
	hand_angle.x = clampf(hand_angle.x, HAND_ANGLE_MIN, HAND_ANGLE_MAX)
	hand_angle.y = clampf(hand_angle.y, HAND_ANGLE_MIN, HAND_ANGLE_MAX)
	elbow_angle.x = clampf(elbow_angle.x, 0.0, PI * 5.0 / 6.0)
	elbow_angle.y = clampf(elbow_angle.y, 0.0, PI * 5.0 / 6.0)
	head_tilt = clampf(head_tilt, -PI / 6.0, PI / 6.0)
	torso_lean = clampf(torso_lean, 0.0, PI / 4.0)


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
		"elbow_angle": {"left": elbow_angle.x, "right": elbow_angle.y},
		"head_tilt": head_tilt,
		"torso_lean": torso_lean,
		"head_id": head_id,
		"hook_slot": hook_slot,
		"is_controlled": is_controlled,
		"walk_phase": walk_phase,
		"walk_amount": walk_amount,
		"air_height": air_height,
		"leg_spread": leg_spread,
		"body_angle": body_angle,
	}
