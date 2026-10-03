extends RefCounted
class_name PerformanceSystem
## 第一关关键动作判定。
##
## 依 TECH_DESIGN.md 第 2.1、2.2 节与 PRD 第 5.1 节：
## - 判定的是「动作到位或状态切换」的那一瞬间，不是连续移动的每一帧；
## - 落点在 Cue.beat_time_ms，判定窗为 ±tolerance_ms（原型 250 ms，可配置）；
## - 每个落点在其 hint_time_ms 之前就产出可读的线索数据，绝不落点后才告知；
## - 物理动作即使错拍也照常发生：本系统只读状态与事件，从不写回、从不阻止动作。
##
## 输出的事件（登记在 docs/superpowers/plans/2026-10-03-level1-a.md 第 1.3 节）：
##   cue_hint  {hint_kind, action, demo_action, target_range, beat_time_ms}
##   cue_fire  {action, metric, window_start_ms, window_end_ms}
##   cue_hit   {cue_id, action, offset_ms, tolerance_ms, metric}
##   cue_miss  {cue_id, action, offset_ms, tolerance_ms, metric}
## cue_fire 表示「玩家做出了这个动作」（无论是否合拍），供 B 打出物理动作表现；
## cue_hit / cue_miss 才是判定结果。三者分开，保证错拍也照常发生。
##
## 本系统不决定补救、不结束关卡：那是切片 4 的范围。它只如实记录全部失误。

const CueScript := preload("res://scripts/a/cue.gd")
const CueHintScript := preload("res://scripts/a/cue_hint.gd")

var cues: Array = []                  ## 由 StageDef 提供的 Cue 列表
var clock: Object = null              ## 鸭子类型：只需 get_song_time_ms() -> int
var puppets: Array = []               ## Array[PuppetState]，由调用方在 setup() 后保持同步

var _events: Array[Dictionary] = []
var _outcomes: Dictionary = {}        ## cue_id -> 判定结果，同一 cue 只判定一次
var _hint_emitted: Dictionary = {}
var _fired: Dictionary = {}           ## "cue_id|拖动代次" -> 已判定
var _drag_generation: int = 0         ## 每次 begin_drag 递增，用于「一次拖动只算一次」
var _dragging: bool = false           ## 仅在拖动中才判定「到位」，避免站定不动也被判到位
var _reach_outside: Dictionary = {}   ## 本次拖动中「已离开过目标范围」的 reach cue_id


func setup(p_cues: Array, p_clock: Object, p_puppets: Array) -> void:
	cues = p_cues
	clock = p_clock
	puppets = p_puppets
	_events.clear()
	_outcomes.clear()
	_hint_emitted.clear()
	_fired.clear()
	_drag_generation = 0
	_dragging = false
	_reach_outside.clear()


## 校验本关 Cue 表。返回问题列表；空列表表示通过。
func validate() -> Array[String]:
	var problems: Array[String] = []
	var seen: Dictionary = {}
	for cue in cues:
		for p in CueScript.validate(cue):
			problems.append(p)
		var cue_id: String = str(cue.get("cue_id", ""))
		if seen.has(cue_id):
			problems.append("cue_id 重复「%s」" % cue_id)
		seen[cue_id] = true
	return problems


## 每帧一次。必须在状态已更新（PuppetController.tick）之后调用。
## 传入本帧从控制器取走的事件（含 drag_begin / pose_stance / facing_turn / hand_motion）。
func update(song_time_ms: int, controller_events: Array) -> void:
	_emit_hints(song_time_ms)
	for e in controller_events:
		match str(e.get("kind", "")):
			"drag_begin":
				_drag_generation += 1
				_fired.clear()
				_reach_outside.clear()
				_dragging = true
				continue
			"drag_end":
				_dragging = false
				continue
		_evaluate_action_event(song_time_ms, e)
	_evaluate_reach(song_time_ms)


func get_outcome(cue_id: String) -> Dictionary:
	return _outcomes.get(cue_id, {})


func get_outcomes() -> Array:
	return _outcomes.values()


func has_outcome(cue_id: String) -> bool:
	return _outcomes.has(cue_id)


## 供测试/诊断读取当前是否处于拖动中。
func is_dragging() -> bool:
	return _dragging


func pending_count() -> int:
	return maxi(cues.size() - _outcomes.size(), 0)


func take_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_events)
	_events.clear()
	return out


func _emit_hints(song_time_ms: int) -> void:
	for cue in cues:
		var cue_id: String = str(cue.get("cue_id", ""))
		if _hint_emitted.has(cue_id):
			continue
		if song_time_ms < CueScript.hint_time_ms(cue):
			continue
		_hint_emitted[cue_id] = true
		var hint: Dictionary = CueHintScript.make(cue)
		_emit(song_time_ms, "cue_hint", int(cue.get("target_object", 0)), cue_id, {
			"hint_kind": hint["kind"],
			"action": hint["action"],
			"demo_action": hint["demo_action"],
			"target_range": hint["target_range"],
			"beat_time_ms": hint["beat_time_ms"],
		})


## 判定一个由状态切换触发的动作（站起/蹲下/抬手/落手/横向移动）。
func _evaluate_action_event(song_time_ms: int, event: Dictionary) -> void:
	var match_result: Dictionary = _match_event(event)
	if match_result.is_empty():
		return
	_register_action(song_time_ms, match_result, int(event.get("object_id", 0)))


## 「到位」是连续状态，没有状态切换事件，因此每帧检查一次。
## 判定条件是「本次拖动中先离开过目标范围、再进入」：
## 只要求「当前在范围内」会让玩家原地起拖就被判到位，那不是移动到到位。
## 去重仍交给 _register_action 统一处理，避免这里先写去重键导致它直接跳过。
func _evaluate_reach(song_time_ms: int) -> void:
	if not _dragging:
		return
	for cue in cues:
		if str(cue.get("action", "")) != CueScript.ACTION_REACH:
			continue
		var cue_id: String = str(cue.get("cue_id", ""))
		if _outcomes.has(cue_id):
			continue
		var range: Dictionary = cue.get("target_range", {})
		var metric: float = _metric_value(str(range.get("key", "")), int(cue.get("target_object", 0)))
		if is_nan(metric):
			continue
		if not CueScript.condition_met(cue, CueScript.ACTION_REACH, metric):
			_reach_outside[cue_id] = true
			continue
		if not _reach_outside.has(cue_id):
			continue
		_register_action(song_time_ms,
			{"actions": [CueScript.ACTION_REACH], "metric": metric},
			int(cue.get("target_object", 0)))


## 把控制器事件翻译成候选动作列表与度量值。返回空数组表示该事件不代表任何关键动作。
## 「站起」与「蹲下」共用 pose_stance 事件，由目标范围区分，因此这里返回两个候选。
func _match_event(event: Dictionary) -> Dictionary:
	var kind: String = str(event.get("kind", ""))
	var payload: Dictionary = event.get("payload", {})
	match kind:
		"pose_stance":
			var stance: float = float(payload.get("stance", 0.0))
			return {"actions": [CueScript.ACTION_STAND_UP, CueScript.ACTION_CROUCH],
				"metric": stance}
		"facing_turn":
			var target: float = float(payload.get("to", 0.0))
			if is_zero_approx(target):
				return {}
			var action: String = CueScript.ACTION_MOVE_RIGHT if target > 0.0 \
				else CueScript.ACTION_MOVE_LEFT
			return {"actions": [action], "metric": _state_x(int(event.get("object_id", 0)))}
		"hand_motion":
			var direction: int = int(payload.get("dir", 0))
			if direction == 0:
				return {}                 # 冲突保持姿势不算动作
			var hand_action: String = CueScript.ACTION_HAND_RAISE if direction > 0 \
				else CueScript.ACTION_HAND_LOWER
			return {"actions": [hand_action], "metric": float(payload.get("angle", 0.0))}
	return {}


## 对每个待判定的 Cue 尝试匹配这次状态切换。
## 去重键含拖动代次：一次拖动里同一 Cue 只判定一次，但新一次手势可以再次判定，
## 因此「错拍做了一次、随后在容差内又做一次」都能被如实记录。
func _register_action(song_time_ms: int, match_result: Dictionary, object_id: int) -> void:
	var actions: Array = match_result["actions"]
	var metric: float = match_result["metric"]
	for cue in cues:
		var cue_id: String = str(cue.get("cue_id", ""))
		if _outcomes.has(cue_id):
			continue
		if int(cue.get("target_object", 0)) != object_id:
			continue
		var expected: String = str(cue.get("action", ""))
		if not actions.has(expected):
			continue
		var fire_key: String = "%s|%d" % [cue_id, _drag_generation]
		if _fired.has(fire_key):
			continue
		if not CueScript.condition_met(cue, expected, metric):
			continue
		_fired[fire_key] = song_time_ms
		_emit(song_time_ms, "cue_fire", object_id, cue_id, {
			"action": expected,
			"metric": metric,
			"window_start_ms": CueScript.window_start_ms(cue),
			"window_end_ms": CueScript.window_end_ms(cue),
		})
		_resolve(cue, song_time_ms, expected, metric)


## 落点是否落在判定窗内。窗内记命中，窗外仍记未命中——动作照常发生。
func _resolve(cue: Dictionary, song_time_ms: int, action: String, metric: float) -> void:
	var cue_id: String = str(cue.get("cue_id", ""))
	var beat_ms: int = int(cue.get("beat_time_ms", 0))
	var tolerance: int = int(cue.get("tolerance_ms", 0))
	var offset: int = song_time_ms - beat_ms
	var outcome: Dictionary = {
		"cue_id": cue_id,
		"action": action,
		"beat_time_ms": beat_ms,
		"tolerance_ms": tolerance,
		"time_ms": song_time_ms,
		"offset_ms": offset,
		"metric": metric,
		"hit": absi(offset) <= tolerance,
	}
	_outcomes[cue_id] = outcome
	_emit(song_time_ms, "cue_hit" if outcome["hit"] else "cue_miss",
		int(cue.get("target_object", 0)), cue_id, {
			"action": action,
			"offset_ms": offset,
			"tolerance_ms": tolerance,
			"metric": metric,
		})


func _metric_value(key: String, object_id: int) -> float:
	var state: PuppetState = _state_of(object_id)
	if state == null:
		return NAN
	match key:
		"stance":
			return state.stance
		"hand":
			return state.hand_angle.x
		"angle":
			return state.hand_angle.x
		"facing":
			return state.facing
		"x":
			return state.stage_pos.x
		"y":
			return state.stage_pos.y
	return NAN


func _state_x(object_id: int) -> float:
	var state: PuppetState = _state_of(object_id)
	return state.stage_pos.x if state != null else NAN


func _state_of(object_id: int) -> PuppetState:
	for state in puppets:
		if state.puppet_id == object_id:
			return state
	return null


func _emit(song_time_ms: int, kind: String, object_id: int, cue_id: String,
		payload_extra: Dictionary) -> void:
	var payload := {"kind": kind}
	payload.merge(payload_extra, true)
	_events.append({
		"time_ms": song_time_ms,
		"kind": kind,
		"object_id": object_id,
		"cue_id": cue_id,
		"payload": payload,
	})
