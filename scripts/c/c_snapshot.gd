extends RefCounted
class_name CSnapshot
## 一帧采样的连续状态。契约由 A 端冻结（见 A 侧 puppet_state.gd 的 to_dict()）。
##
## 采样时机（A 端每帧固定顺序中的第 3 步）：
##   输入 → PuppetController.tick() → 【C 采 Snapshot】→ PerformanceSystem.update()
##   → RemedySystem.update() → 【C 采离散事件】
## 也就是「状态先变化，再供表现与录制读取」；在 remedy.update() 之前采，
## 连续量一定是 tick() 之后的最终值。
##
## 本类是纯数据容器：不持有引擎对象，不回读 A 的状态，不做任何推导。
## C 侧唯一职责是把当帧状态原样存下来，回放时再原样取出来。

## 采样频率。30 Hz 是常规节拍；瞬时动作另有补采样，见 CHANGE_TRIGGERED。
const SAMPLE_HZ: float = 30.0
const SAMPLE_INTERVAL_MS: int = 1000  ## 1000 / 30 取整为 33ms，见 README 说明

## 影人数量固定为 3，下标即 puppet_id，回放直接索引，不做查找。
const PUPPET_COUNT: int = 3

## 判定「字段是否变化」的阈值。与 A 端 LampState.CHANGE_EPSILON 同量级，
## 不能用 is_equal_approx：它按相对误差工作，会把单帧的小幅变化判成「没变」，
## 那样补采样就不会触发，30 Hz 会漏掉瞬时动作。
const CHANGE_EPSILON: float = 1.0e-9

## 灯态四字段。字段名与 A 端 LampState.to_dict() 严格一致：
## 注意第四个是 flame_feedback，不是契约初稿里写的 flame。
## 归属尚未认领（见 README「待确认」），当前为占位，不接真实生产者。
const LAMP_PLACEHOLDER_DISTANCE: float = 0.5
const LAMP_PLACEHOLDER_EXPOSURE: float = 0.5
const LAMP_PLACEHOLDER_OIL: float = 1.0
const LAMP_PLACEHOLDER_FLAME: float = 0.5

var time_ms: int = 0
## 长度固定为 PUPPET_COUNT，下标 == puppet_id。每项是一份 to_dict() 形状的字典。
var puppets: Array = []
## 四项均为 0.0-1.0；字段名与 A 端 LampState.to_dict() 一致。
var lamp: Dictionary = {}


func _init(p_time_ms: int = 0) -> void:
	time_ms = p_time_ms
	puppets.resize(PUPPET_COUNT)
	for i in PUPPET_COUNT:
		puppets[i] = _default_puppet_dict(i)
	lamp = default_lamp_dict()


## 单个影人缺失时使用的缺省值。字段名与 A 端 to_dict() 严格一致。
## 缺省不等于「不存在」——A 端保证三具身体始终在状态里，
## 挂起时 hook_slot 变为槽位号、is_controlled 变为 false，而不是从数组里移除。
static func _default_puppet_dict(puppet_id: int) -> Dictionary:
	return {
		"puppet_id": puppet_id,
		"stage_pos": {"x": 0.5, "y": 0.0},
		"stance": 0.0,
		"facing": 0.0,
		"turn_progress": 0.0,
		"hand_angle": {"left": 0.0, "right": 0.0},
		"head_id": -1,
		"hook_slot": -1,
		"is_controlled": false,
	}


## 灯态占位值。切到真实 LampController 后由调用方覆盖，本函数仅提供安全缺省。
static func default_lamp_dict() -> Dictionary:
	return {
		"distance": LAMP_PLACEHOLDER_DISTANCE,
		"exposure": LAMP_PLACEHOLDER_EXPOSURE,
		"oil": LAMP_PLACEHOLDER_OIL,
		"flame_feedback": LAMP_PLACEHOLDER_FLAME,
	}


## 从 A 端的 to_dict() 视图构造一份 Snapshot。
##
## p_puppet_views 必须是长度 3 的数组，每项是 A 端 PuppetState.to_dict() 的返回值。
## 字段名以 A 端实际实现为准，不做任何改名或单位换算——转换是 A 的职责。
## 缺失或类型不符时 push_error 并保留缺省值，不静默写入错误数据。
static func from_views(p_time_ms: int, p_puppet_views: Array, p_lamp_view: Dictionary = {}) -> CSnapshot:
	var snap := CSnapshot.new(p_time_ms)
	if p_puppet_views.size() != PUPPET_COUNT:
		push_error("CSnapshot: puppets 长度应为 %d，实际 %d，缺失位置用缺省值"
			% [PUPPET_COUNT, p_puppet_views.size()])
	for i in mini(PUPPET_COUNT, p_puppet_views.size()):
		snap.puppets[i] = _sanitize_puppet_view(p_puppet_views[i], i)
	if not p_lamp_view.is_empty():
		snap.lamp = _sanitize_lamp_view(p_lamp_view)
	return snap


static func _sanitize_puppet_view(view: Variant, index: int) -> Dictionary:
	if typeof(view) != TYPE_DICTIONARY:
		push_error("CSnapshot: puppets[%d] 不是字典，保留缺省值" % index)
		return _default_puppet_dict(index)
	var base := _default_puppet_dict(index)
	var out: Dictionary = base.duplicate(true)

	var pid: int = int(view.get("puppet_id", index))
	# 下标即 puppet_id，不一致说明数据源有问题，报出来而不是默默改。
	if pid != index:
		push_error("CSnapshot: puppets[%d].puppet_id 为 %d，下标与 id 不一致" % [index, pid])
	out["puppet_id"] = pid

	var pos: Variant = view.get("stage_pos", {})
	if typeof(pos) == TYPE_DICTIONARY:
		out["stage_pos"] = {
			"x": float(pos.get("x", base["stage_pos"]["x"])),
			"y": float(pos.get("y", base["stage_pos"]["y"])),
		}
	else:
		push_error("CSnapshot: puppets[%d].stage_pos 不是字典，保留缺省值" % index)

	var hand: Variant = view.get("hand_angle", {})
	if typeof(hand) == TYPE_DICTIONARY:
		out["hand_angle"] = {
			"left": float(hand.get("left", 0.0)),
			"right": float(hand.get("right", 0.0)),
		}
	else:
		push_error("CSnapshot: puppets[%d].hand_angle 不是字典，保留缺省值" % index)

	for key in ["stance", "facing", "turn_progress"]:
		out[key] = float(view.get(key, base[key]))
	for key in ["head_id", "hook_slot"]:
		out[key] = int(view.get(key, base[key]))
	out["is_controlled"] = bool(view.get("is_controlled", base["is_controlled"]))
	return out


static func _sanitize_lamp_view(view: Dictionary) -> Dictionary:
	var out := default_lamp_dict()
	for key in out.keys():
		if view.has(key):
			out[key] = float(view[key])
		else:
			push_error("CSnapshot: lamp 缺少字段 %s，用占位值" % key)
	return out


## 与另一帧相比，返回发生变化的字段名。顺序固定，便于同帧内容可复现。
## puppets 的字段路径用 "puppets[i].field" 表示，lamp 用 "lamp.field" 表示。
## 变化检测覆盖全部字段，包括 head_id / hook_slot / is_controlled 这类离散量——
## 它们跳变时必须触发当帧补采样，否则 30 Hz 会漏掉换头与挂起。
func changed_fields(before: CSnapshot) -> Array:
	var out: Array = []
	if before == null:
		return out
	for i in PUPPET_COUNT:
		out.append_array(_changed_puppet_fields(i, before.puppets[i], puppets[i]))
	out.append_array(_changed_lamp_fields(before.lamp, lamp))
	return out


func _changed_puppet_fields(index: int, a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	var prefix := "puppets[%d]." % index
	if _dict_differs(a.get("stage_pos"), b.get("stage_pos")):
		out.append(prefix + "stage_pos")
	if _dict_differs(a.get("hand_angle"), b.get("hand_angle")):
		out.append(prefix + "hand_angle")
	for key in ["stance", "facing", "turn_progress"]:
		if _float_differs(float(a.get(key, 0.0)), float(b.get(key, 0.0))):
			out.append(prefix + key)
	for key in ["head_id", "hook_slot"]:
		if int(a.get(key, -1)) != int(b.get(key, -1)):
			out.append(prefix + key)
	if bool(a.get("is_controlled", false)) != bool(b.get("is_controlled", false)):
		out.append(prefix + "is_controlled")
	return out


func _changed_lamp_fields(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for key in ["distance", "exposure", "oil", "flame_feedback"]:
		if _float_differs(float(a.get(key, 0.0)), float(b.get(key, 0.0))):
			out.append("lamp." + key)
	return out


func _float_differs(a: float, b: float) -> bool:
	return absf(a - b) > CHANGE_EPSILON


func _dict_differs(a: Variant, b: Variant) -> bool:
	if typeof(a) != TYPE_DICTIONARY or typeof(b) != TYPE_DICTIONARY:
		return true
	var keys: Array = (a as Dictionary).keys()
	for k in (b as Dictionary).keys():
		if not keys.has(k):
			return true
	for k in keys:
		var va: Variant = a[k]
		var vb: Variant = b[k]
		if typeof(va) == TYPE_DICTIONARY or typeof(vb) == TYPE_DICTIONARY:
			if _dict_differs(va, vb):
				return true
		elif typeof(va) == TYPE_FLOAT or typeof(vb) == TYPE_FLOAT:
			if _float_differs(float(va), float(vb)):
				return true
		elif va != vb:
			return true
	return false


## 只比较内容，不含 time_ms。用于「同一时刻是否重复采样」的判断。
func same_content_as(other: CSnapshot) -> bool:
	if other == null:
		return false
	return changed_fields(other).is_empty()


## 供测试与诊断使用的紧凑描述。
func describe() -> String:
	return "CSnapshot(t=%dms, puppets=%d, lamp=%s)" % [time_ms, puppets.size(), str(lamp)]
