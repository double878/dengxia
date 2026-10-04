extends RefCounted
class_name CueHint
## 落点前的可感知线索数据。供 B 显示图标用。
##
## 只描述「做什么」与「何时开始可见」，不泄露精确拍号、数值评分或观众心理
## （PRD 第 5.1、5.2、8 节）。A 只产出数据，不负责画出来。
##
## 本类刻意不引用 Cue 类的常量，只用同名字符串：
## Cue 与 CueHint 互相引用会在类解析阶段形成循环，导致构造期解析失败。

## 线索种类。前四关可用图标逐步教学，具体呈现由 B 决定。
const KIND_STANCE: String = "stance"        ## 站起 / 蹲下
const KIND_HAND: String = "hand"            ## 抬手 / 落手
const KIND_MOVE: String = "move"            ## 横向移动 / 转身
const KIND_REACH: String = "reach"          ## 移动到目标位置
const KIND_HOOK: String = "hook"            ## 挂起 / 取回影人（第 2 关）
const KIND_HEAD: String = "head"            ## 与备用头架换头（第 4 关）
const KIND_LAMP_DISTANCE: String = "lamp_distance"   ## 推拉灯位使影子缩放（第 3 关）
const KIND_LAMP_EXPOSURE: String = "lamp_exposure"   ## 倾灯改变影子显露（第 4 关）

## 与 Cue.ACTION_* 一一对应的动作名，保持字符串一致即可，不建立类依赖。
const ACTION_STAND_UP: String = "stand_up"
const ACTION_CROUCH: String = "crouch"
const ACTION_HAND_RAISE: String = "hand_raise"
const ACTION_HAND_LOWER: String = "hand_lower"
const ACTION_MOVE_LEFT: String = "move_left"
const ACTION_MOVE_RIGHT: String = "move_right"
const ACTION_REACH: String = "reach"
const ACTION_HOOK: String = "hook"
const ACTION_TAKE_BACK: String = "take_back"
const ACTION_HEAD_SWAP: String = "head_swap"
const ACTION_LAMP_DISTANCE: String = "lamp_distance"
const ACTION_LAMP_EXPOSURE: String = "lamp_exposure"


## 由动作类型推导线索种类，保证「线索说的动作」与「判定的动作」永远一致。
static func kind_for_action(action: String) -> String:
	match action:
		ACTION_STAND_UP, ACTION_CROUCH:
			return KIND_STANCE
		ACTION_HAND_RAISE, ACTION_HAND_LOWER:
			return KIND_HAND
		ACTION_MOVE_LEFT, ACTION_MOVE_RIGHT:
			return KIND_MOVE
		ACTION_REACH:
			return KIND_REACH
		ACTION_HOOK, ACTION_TAKE_BACK:
			return KIND_HOOK
		ACTION_HEAD_SWAP:
			return KIND_HEAD
		ACTION_LAMP_DISTANCE:
			return KIND_LAMP_DISTANCE
		ACTION_LAMP_EXPOSURE:
			return KIND_LAMP_EXPOSURE
	return KIND_STANCE


## 由 Cue 生成线索数据。target_range 原样带出，供 B 画目标边界。
static func make(cue: Dictionary) -> Dictionary:
	var action: String = str(cue.get("action", ""))
	var beat_ms: int = int(cue.get("beat_time_ms", 0))
	var lead_ms: int = maxi(int(cue.get("hint_lead_ms", 1000)), 0)
	return {
		"cue_id": str(cue.get("cue_id", "")),
		"kind": kind_for_action(action),
		"action": action,
		"target_object": int(cue.get("target_object", 0)),
		"demo_action": str(cue.get("demo_action", action)),
		"target_range": cue.get("target_range", {}).duplicate(true),
		"hint_time_ms": maxi(beat_ms - lead_ms, 0),
		"beat_time_ms": beat_ms,
	}


## 线索在 song_time_ms 是否已可感知。
static func is_visible(hint: Dictionary, song_time_ms: int) -> bool:
	return song_time_ms >= int(hint.get("hint_time_ms", 0))
