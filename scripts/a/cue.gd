extends RefCounted
class_name Cue
## 第一关关键动作的数据契约与校验。
##
## 依 TECH_DESIGN.md 第 2.2 节的 Cue 行与 docs/superpowers/plans/2026-10-03-level1-a.md：
## 唯一 cue_id、beat_time_ms（落点）、动作类型、目标对象、目标范围、
## 判定容差、示范动作。本文件另加 hint_lead_ms（落点前多久必须能看到线索）。
##
## Cue 用 Dictionary 表示（与 StageDef 的 cues 数组一致，便于 JSON 化与录制），
## 本类只提供常量、工厂与校验，不持有状态。

## 动作类型。判定的是「姿势到位或状态切换」的那一瞬间，不是每一帧的平移。
const ACTION_STAND_UP: String = "stand_up"      ## 站起：stance 从蹲位升到目标范围
const ACTION_CROUCH: String = "crouch"          ## 蹲下：stance 落到目标范围
const ACTION_HAND_RAISE: String = "hand_raise"  ## 抬手：该手角度在目标范围内且方向为抬
const ACTION_HAND_LOWER: String = "hand_lower"  ## 落手：该手角度在目标范围内且方向为落
const ACTION_MOVE_LEFT: String = "move_left"    ## 向左横向移动（转身跟随）
const ACTION_MOVE_RIGHT: String = "move_right"  ## 向右横向移动（转身跟随）
const ACTION_REACH: String = "reach"            ## 到位：横向到达目标范围

const ALL_ACTIONS: Array[String] = [
	ACTION_STAND_UP, ACTION_CROUCH, ACTION_HAND_RAISE, ACTION_HAND_LOWER,
	ACTION_MOVE_LEFT, ACTION_MOVE_RIGHT, ACTION_REACH,
]

## 目标范围里允许出现的字段名。范围一律为归一化或弧度值，闭区间。
const RANGE_KEYS: Array[String] = ["stance", "hand", "angle", "facing", "x", "y"]

const DEFAULT_TOLERANCE_MS: int = 250   ## PRD 第 5.1 节的原型起点，可配置
const DEFAULT_HINT_LEAD_MS: int = 1000  ## 落点前 1 s 必须已能读到线索


## 建立一条 Cue。range 形如 {"stance": {"min": 0.7, "max": 1.0}}。
static func make(cue_id: String, beat_time_ms: int, action: String, target_object: int,
		target_range: Dictionary, tolerance_ms: int = DEFAULT_TOLERANCE_MS,
		demo_action: String = "", hint_lead_ms: int = DEFAULT_HINT_LEAD_MS) -> Dictionary:
	return {
		"cue_id": cue_id,
		"beat_time_ms": beat_time_ms,
		"action": action,
		"target_object": target_object,
		"target_range": target_range,
		"tolerance_ms": tolerance_ms,
		"demo_action": demo_action if not demo_action.is_empty() else action,
		"hint_lead_ms": hint_lead_ms,
	}


## 落点前多久必须能看到线索。数据缺失时退回默认值，不允许「落点后才知道要做什么」。
static func hint_time_ms(cue: Dictionary) -> int:
	var lead: int = int(cue.get("hint_lead_ms", DEFAULT_HINT_LEAD_MS))
	return maxi(int(cue.get("beat_time_ms", 0)) - maxi(lead, 0), 0)


## 落点 + 容差的上界，判定窗右端。
static func window_end_ms(cue: Dictionary) -> int:
	return int(cue.get("beat_time_ms", 0)) + maxi(int(cue.get("tolerance_ms", 0)), 0)


## 落点 − 容差的下界，判定窗左端。
static func window_start_ms(cue: Dictionary) -> int:
	return int(cue.get("beat_time_ms", 0)) - maxi(int(cue.get("tolerance_ms", 0)), 0)


## 判定某条 Cue 的判定条件是否满足（不含时间）。
## 连续量读数由调用方给出，避免本类依赖 PuppetState。
static func condition_met(cue: Dictionary, action: String, metric_value: float) -> bool:
	if str(cue.get("action", "")) != action:
		return false
	var range: Dictionary = cue.get("target_range", {})
	if range.is_empty():
		return true                   # 未指定范围视为「任意值都算到位」
	var key: String = str(range.get("key", ""))
	if key.is_empty():
		return true
	return metric_value >= float(range.get("min", -INF)) \
		and metric_value <= float(range.get("max", INF))


## 校验一条 Cue。返回问题列表；空列表表示通过。
static func validate(cue: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var cue_id: String = str(cue.get("cue_id", ""))
	if cue_id.is_empty():
		problems.append("存在空 cue_id")
		return problems
	var action: String = str(cue.get("action", ""))
	if not ALL_ACTIONS.has(action):
		problems.append("cue「%s」的动作类型非法：%s" % [cue_id, action])
	if int(cue.get("tolerance_ms", 0)) <= 0:
		problems.append("cue「%s」缺少有效判定容差" % cue_id)
	if int(cue.get("hint_lead_ms", 0)) < 0:
		problems.append("cue「%s」的 hint_lead_ms 为负" % cue_id)
	if str(cue.get("demo_action", "")).is_empty():
		problems.append("cue「%s」缺少示范动作" % cue_id)
	var range: Dictionary = cue.get("target_range", {})
	if not range.is_empty():
		var key: String = str(range.get("key", ""))
		if not RANGE_KEYS.has(key):
			problems.append("cue「%s」的目标范围 key 非法：%s" % [cue_id, key])
		if not range.has("min") or not range.has("max"):
			problems.append("cue「%s」的目标范围缺少 min/max" % cue_id)
		elif float(range["min"]) > float(range["max"]):
			problems.append("cue「%s」的目标范围 min > max" % cue_id)
	return problems
