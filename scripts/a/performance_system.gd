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
## 油灯状态（LampState）。灯位推拉（`lamp_distance`）与倾灯显露（`lamp_exposure`）
## 这两类 Cue 的读数取自这里。传 null 时这两类 Cue 不判定，但绝不影响影人动作的判定
## ——第 1、2 关没有灯位类落点，缺油灯不应让整关的判定失效。
var lamp: LampState = null

var _events: Array[Dictionary] = []
var _outcomes: Dictionary = {}        ## cue_id -> 判定结果，同一 cue 只判定一次
var _hint_emitted: Dictionary = {}
var _fired: Dictionary = {}           ## "cue_id|拖动代次" -> 已判定
var _drag_generation: int = 0         ## 每次 begin_drag 递增，用于「一次拖动只算一次」
var _dragging: bool = false           ## 仅在拖动中才判定「到位」，避免站定不动也被判到位
var _reach_outside: Dictionary = {}   ## 本次拖动中「已离开过目标范围」的 reach cue_id
var _lamp_outside: Dictionary = {}    ## 灯位/倾灯类 cue：此刻是否在目标范围之外（只判上升沿）
var _last_state: Dictionary = {}       ## puppet_id -> 上次判定时的连续状态


func setup(p_cues: Array, p_clock: Object, p_puppets: Array, p_lamp: LampState = null) -> void:
	cues = p_cues
	clock = p_clock
	puppets = p_puppets
	lamp = p_lamp
	_events.clear()
	_outcomes.clear()
	_hint_emitted.clear()
	_fired.clear()
	_drag_generation = 0
	_dragging = false
	_reach_outside.clear()
	_lamp_outside.clear()
	_last_state.clear()
	for state in puppets:
		_last_state[state.puppet_id] = _snapshot(state)


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
## 传入本帧从控制器取走的事件；连续姿态由同帧 PuppetState 的前后值判定。
##
## 事件元素必须是 Dictionary：记录层或测试台可能传入空槽、null 或其他类型，
## 直接 `e.get()` 会抛 `Invalid call. Nonexistent function 'get' in base 'Nil'`
## 把整帧判定打断（错误只进日志，演出会静默带病继续）。入口先判类型，坏元素跳过。
func update(song_time_ms: int, controller_events: Array) -> void:
	_emit_hints(song_time_ms)
	var drag_ended: bool = false
	for e in controller_events:
		if not (e is Dictionary):
			continue
		match str(e.get("kind", "")):
			"drag_begin":
				_drag_generation += 1
				_fired.clear()
				_reach_outside.clear()
				_dragging = true
				_seed_reach_from_previous_state()
				continue
			"drag_end":
				drag_ended = true
				continue
		_evaluate_action_event(song_time_ms, e)
	_evaluate_continuous(song_time_ms)
	_evaluate_reach(song_time_ms)
	_evaluate_lamp(song_time_ms)
	if drag_ended:
		_dragging = false


## 检测「漏做」的关键动作：落点 + 容差已过，玩家始终没有做出对应动作。
## 必须每帧调用（或至少在每个落点窗口关闭后调用一次），否则漏做不会被记录。
## 由 RemedySystem 消费这些结果来开补救窗口，本系统只如实记录。
func detect_misses(song_time_ms: int) -> void:
	for cue in cues:
		var cue_id: String = str(cue.get("cue_id", ""))
		if _outcomes.has(cue_id):
			continue
		if song_time_ms <= CueScript.window_end_ms(cue):
			continue
		var action: String = str(cue.get("action", ""))
		_outcomes[cue_id] = {
			"cue_id": cue_id,
			"action": action,
			"beat_time_ms": int(cue.get("beat_time_ms", 0)),
			"tolerance_ms": int(cue.get("tolerance_ms", 0)),
			"time_ms": song_time_ms,
			"offset_ms": song_time_ms - int(cue.get("beat_time_ms", 0)),
			"metric": NAN,
			"hit": false,
			"missed_outright": true,      ## 与「错拍做了」区分：这次是完全没做
		}
		_emit(song_time_ms, "cue_miss", _resolve_object_id(int(cue.get("target_object", 0))),
			cue_id, {
			"action": action,
			"offset_ms": song_time_ms - int(cue.get("beat_time_ms", 0)),
			"tolerance_ms": int(cue.get("tolerance_ms", 0)),
			"metric": NAN,
			"reason": "missed_outright",
		})


func get_outcome(cue_id: String) -> Dictionary:
	return _outcomes.get(cue_id, {})


## 供补救系统判断：漏做的关键动作清单（不含「错拍做了」的）。
func missed_outright_cue_ids() -> Array[String]:
	var out: Array[String] = []
	for cue_id in _outcomes:
		var outcome: Dictionary = _outcomes[cue_id]
		if bool(outcome.get("missed_outright", false)):
			out.append(str(cue_id))
	return out


## 按段汇总合拍度：仅用已判定的落点，返回 0.0-1.0；无已判定落点时返回 -1.0。
func segment_score(segment_name: String) -> float:
	var total: int = 0
	var hits: int = 0
	for cue in cues:
		if str(cue.get("segment", "")) != segment_name:
			continue
		var cue_id: String = str(cue.get("cue_id", ""))
		var outcome: Dictionary = _outcomes.get(cue_id, {})
		if outcome.is_empty():
			continue
		total += 1
		if bool(outcome.get("hit", false)):
			hits += 1
	if total == 0:
		return -1.0
	return float(hits) / float(total)


## 段内已判定落点数，供补救系统套用「近期合拍度」阈值时避免样本过少。
func segment_graded_count(segment_name: String) -> int:
	var total: int = 0
	for cue in cues:
		if str(cue.get("segment", "")) != segment_name:
			continue
		if _outcomes.has(str(cue.get("cue_id", ""))):
			total += 1
	return total


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


## 只读地看当前待取事件，不改动队列。`take_events()` 是「取走即清空」，
## 断言「本帧确实产出了事件」若用 take 会影响后续读取，因此另开一个只读入口。
func get_events_for_test() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_events)
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
		_emit(song_time_ms, "cue_hint", _resolve_object_id(int(cue.get("target_object", 0))),
			cue_id, {
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


## 由**控制器之外**的模块上报一次离散动作（当前只有第一关的借伞还伞）。
##
## 为什么不让这类事件走 `update()` 的常规事件流：常规流里的每一条都会被当成
## 「本帧的状态切换事件」与「本帧的连续状态」各评估一次，而伞的交接只是
## 「一次离散动作发生」——它既不是控制器事件，也不该顺带改写任何连续读数。
## 混进去的后果是实测过的：拖动帧里的一条交接事件会让「走到最左边」在离落点
## 还有 7.5 秒的时候就被判掉。
##
## 判定规则本身（拍点、容差、`cue_fire` / `cue_hit` / `cue_miss` 的产出、
## 「一次拖动只判一次」的去重口径）与控制器动作共用同一条路径，不另起一套。
func register_external_action(song_time_ms: int, event: Dictionary) -> void:
	_evaluate_action_event(song_time_ms, event)


func _seed_reach_from_previous_state() -> void:
	for cue in cues:
		if str(cue.get("action", "")) != CueScript.ACTION_REACH:
			continue
		var object_id: int = _resolve_object_id(int(cue.get("target_object", 0)))
		var previous: Dictionary = _last_state.get(object_id, {})
		if previous.is_empty():
			continue
		var range: Dictionary = cue.get("target_range", {})
		if str(range.get("key", "")) == "x" and not CueScript.condition_met(
				cue, CueScript.ACTION_REACH, float(previous["x"])):
			_reach_outside[str(cue.get("cue_id", ""))] = true


## 连续姿态只在真实变化并进入目标范围时触发；控制器的方向事件不代表到位时刻。
func _evaluate_continuous(song_time_ms: int) -> void:
	for state in puppets:
		var object_id: int = state.puppet_id
		var previous: Dictionary = _last_state.get(object_id, _snapshot(state))
		var previous_x: float = float(previous["x"])
		var current_x: float = state.stage_pos.x
		if _dragging and not is_equal_approx(previous_x, current_x):
			var move_action: String = CueScript.ACTION_MOVE_RIGHT if current_x > previous_x \
				else CueScript.ACTION_MOVE_LEFT
			_register_action(song_time_ms, {"actions": [move_action], "metric": current_x}, object_id)
		for hand_key in ["left_angle", "right_angle"]:
			var before: float = float(previous[hand_key])
			var after: float = state.hand_angle.x if hand_key == "left_angle" else state.hand_angle.y
			if is_equal_approx(before, after):
				continue
			var hand_action: String = CueScript.ACTION_HAND_RAISE if after > before \
				else CueScript.ACTION_HAND_LOWER
			_register_action(song_time_ms, {
				"actions": [hand_action], "metric": after,
				"previous_metric": before, "enter_only": true,
			}, object_id)
		_last_state[object_id] = _snapshot(state)


func _snapshot(state: PuppetState) -> Dictionary:
	return {"x": state.stage_pos.x, "left_angle": state.hand_angle.x,
		"right_angle": state.hand_angle.y}


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
		if not _can_attempt(cue):
			continue
		var range: Dictionary = cue.get("target_range", {})
		var metric: float = _metric_value(str(range.get("key", "")),
			_resolve_object_id(int(cue.get("target_object", 0))))
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


## 灯位推拉与倾灯显露：连续量，每帧检查一次，但只判「从范围外跨入范围内」的上升沿。
##
## 为什么只判上升沿：这两类读数在整个演出里一直存在（灯距从开局就有值），
## 若按「当前在范围内」判定，一个开局恰好落在目标区间的关卡会在第 0 帧就被判命中。
## 要求先离开过、再进入，等价于「玩家真的把灯推/倾到了那个位置」。
## 上升沿后立刻清除标记，于是「错拍推到位」与「补救时重新推到位」都能各自被判定，
## 去重仍由 `_can_attempt`（命中即定案）与 `_register_action` 统一处理。
func _evaluate_lamp(song_time_ms: int) -> void:
	if lamp == null:
		return
	for cue in cues:
		var action: String = str(cue.get("action", ""))
		if not CueScript.LAMP_ACTIONS.has(action):
			continue
		# 装填点：灯位/倾灯读数整场一直存在。若从第 0 帧就参与判定，
		# 「目标区间恰好与开局值重合」的落点会在开演瞬间被当成一次动作（判命中或判错拍），
		# 而且会让同一条读数区间上的两个不同落点互相顶掉。因此这类落点只在
		# **线索时间**之后才参与判定——线索时间就是玩家被告知「现在该把灯推/倾到哪」的时刻。
		if song_time_ms < CueScript.hint_time_ms(cue):
			continue
		var cue_id: String = str(cue.get("cue_id", ""))
		if not _can_attempt(cue):
			continue
		var range: Dictionary = cue.get("target_range", {})
		var metric: float = _metric_value(str(range.get("key", "")),
			_resolve_object_id(int(cue.get("target_object", 0))))
		if is_nan(metric):
			continue
		if not CueScript.condition_met(cue, action, metric):
			_lamp_outside[cue_id] = true
			continue
		if not _lamp_outside.has(cue_id):
			continue
		_lamp_outside.erase(cue_id)
		_register_action(song_time_ms, {"actions": [action], "metric": metric},
			int(cue.get("target_object", 0)))


## 站蹲沿用控制器的到位事件；手和位移读状态跨越，避免方向事件早于到位时刻。
##
## `pose_stance` 必须真的带 `stance` 读数：缺字段或空 payload 时若按 0.0 默认值判定，
## 一个畸形事件就会被当成一次真实的「站起」，甚至会凭它关掉正在开的补救窗口。
## 宁可不判定，也不接受一个没有读数的动作事件。
## 把控制器事件翻译成「这次做出了哪些动作」+「读数是多少」。
##
## 与 `pose_stance` 同一条纪律：**读数缺失就不判定**。缺字段的事件若按默认值参与判定，
## 一个空 payload 就能伪造一次真实的挂起/换头，甚至关掉正在开的补救窗口。
func _match_event(event: Dictionary) -> Dictionary:
	var kind: String = str(event.get("kind", ""))
	var payload: Dictionary = event.get("payload", {})
	match kind:
		"pose_stance":
			if not payload.has("stance"):
				return {}
			var stance: float = float(payload.get("stance", 0.0))
			return {"actions": [CueScript.ACTION_STAND_UP, CueScript.ACTION_CROUCH],
				"metric": stance}
		"puppet_hook":
			if not payload.has("hook_slot"):
				return {}
			return {"actions": [CueScript.ACTION_HOOK], "metric": float(payload["hook_slot"])}
		"puppet_take_back":
			if not payload.has("hook_slot"):
				return {}
			return {"actions": [CueScript.ACTION_TAKE_BACK], "metric": float(payload["hook_slot"])}
		"head_swap":
			if not payload.has("slot"):
				return {}
			return {"actions": [CueScript.ACTION_HEAD_SWAP], "metric": float(payload["slot"])}
		# 第一关借伞还伞：交接由 UmbrellaController 在对齐条件成立时自动完成，
		# 这里只把「伞确实换手了」翻译成一次动作，读数用白素贞当时的接地点 x。
		# 与 pose_stance 同一条纪律：**读数缺失就不判定**，空 payload 不能伪造一次交接。
		"umbrella_take":
			if not payload.has("metric"):
				return {}
			return {"actions": [CueScript.ACTION_UMBRELLA_TAKE], "metric": float(payload["metric"])}
		"umbrella_return":
			if not payload.has("metric"):
				return {}
			return {"actions": [CueScript.ACTION_UMBRELLA_RETURN], "metric": float(payload["metric"])}
	return {}


## 对每个待判定的 Cue 尝试匹配这次状态切换。
## 去重键含拖动代次：一次拖动里同一 Cue 只判定一次，但新一次手势可以再次判定，
## 因此「错拍做了一次、随后在容差内又做一次」都能被如实记录。
func _register_action(song_time_ms: int, match_result: Dictionary, object_id: int) -> void:
	var actions: Array = match_result["actions"]
	var metric: float = match_result["metric"]
	var resolved_object: int = _resolve_object_id(object_id)
	for cue in cues:
		var cue_id: String = str(cue.get("cue_id", ""))
		if not _can_attempt(cue):
			continue
		# target_object < 0 表示「当前受控影人」：动作作用于谁由玩家当下的操控决定。
		var target_object: int = int(cue.get("target_object", 0))
		if target_object >= 0 and target_object != object_id:
			continue
		var expected: String = str(cue.get("action", ""))
		if not actions.has(expected):
			continue
		if bool(match_result.get("enter_only", false)) and CueScript.condition_met(
				cue, expected, float(match_result["previous_metric"])):
			continue
		var fire_key: String = "%s|%d" % [cue_id, _drag_generation]
		# 「一次拖动只算一次」只适用于由**拖动本身**触发的动作（平移、到位、站蹲）。
		# 借伞交接、挂起、取回、换头是离散事件：一次交接就一条事件，
		# 用拖动代次去重反而会把「还伞之后再借一次」在没重新拖动的帧里挡掉。
		var once_per_drag: bool = expected == CueScript.ACTION_MOVE_LEFT \
			or expected == CueScript.ACTION_MOVE_RIGHT or expected == CueScript.ACTION_REACH \
			or expected == CueScript.ACTION_STAND_UP or expected == CueScript.ACTION_CROUCH
		if once_per_drag and _fired.has(fire_key):
			continue
		if not CueScript.condition_met(cue, expected, metric):
			continue
		if once_per_drag:
			_fired[fire_key] = song_time_ms
		_emit(song_time_ms, "cue_fire", resolved_object, cue_id, {
			"action": expected,
			"metric": metric,
			"window_start_ms": CueScript.window_start_ms(cue),
			"window_end_ms": CueScript.window_end_ms(cue),
		})
		_resolve(cue, song_time_ms, expected, metric)


## 这个 Cue 现在还能不能被判定。
##
## 判定只发生在容差窗内：窗内做出动作记命中，窗外做出同一动作记未命中。
## 一旦判成命中就定案；判成未命中则**仍可再次判定**，否则 8 秒补救永远无法成功
## （PRD 第 5.2.3 节：窗口内补做对应动作即算补救成功）。重复判定的次数由
## `_register_action` 的「一次拖动同一 Cue 只判一次」去重键限制，不靠本函数。
func _can_attempt(cue: Dictionary) -> bool:
	var cue_id: String = str(cue.get("cue_id", ""))
	if not _outcomes.has(cue_id):
		return true
	return not bool(_outcomes[cue_id].get("hit", false))


## 落点是否落在判定窗内。窗内记命中，窗外仍记未命中——动作照常发生。
## `hit` 一旦为 false 就再也不会翻成 true：补救补的是「把动作做出来」，
## 不是把已经错过的落点改判成命中，原失误永远留在结果与记录里（PRD 第 5.2.3 节）。
func _resolve(cue: Dictionary, song_time_ms: int, action: String, metric: float) -> void:
	var cue_id: String = str(cue.get("cue_id", ""))
	var beat_ms: int = int(cue.get("beat_time_ms", 0))
	var tolerance: int = int(cue.get("tolerance_ms", 0))
	var offset: int = song_time_ms - beat_ms
	var hit: bool = absi(offset) <= tolerance
	var previous: Dictionary = _outcomes.get(cue_id, {})
	var outcome: Dictionary = {
		"cue_id": cue_id,
		"action": action,
		"beat_time_ms": beat_ms,
		"tolerance_ms": tolerance,
		"time_ms": song_time_ms,
		"offset_ms": offset,
		"metric": metric,
		"hit": hit,
	}
	if not hit:
		## 落点过后才把动作做出来 = 补救尝试；原失误已记录，补救不抹去它。
		outcome["remedy_attempt"] = song_time_ms > CueScript.window_end_ms(cue) \
			and not previous.is_empty()
	_outcomes[cue_id] = outcome
	_emit(song_time_ms, "cue_hit" if outcome["hit"] else "cue_miss",
		_resolve_object_id(int(cue.get("target_object", 0))), cue_id, {
			"action": action,
			"offset_ms": offset,
			"tolerance_ms": tolerance,
			"metric": metric,
		})


func _metric_value(key: String, object_id: int) -> float:
	# 灯位类读数取自油灯、与影人无关，因此先于影人查找处理：
	# 否则 object_id 对应的影人不存在时会直接返回 NAN，灯位落点永远判不了。
	if key == "distance" or key == "exposure":
		if lamp == null:
			return NAN
		return float(lamp.distance) if key == "distance" else float(lamp.exposure)
	var state: PuppetState = _state_of(_resolve_object_id(object_id))
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


func _state_of(object_id: int) -> PuppetState:
	for state in puppets:
		if state.puppet_id == object_id:
			return state
	return null


## 当前受控影人的状态；无人受控时为 null。
func _controlled_state() -> PuppetState:
	for state in puppets:
		if state.is_controlled:
			return state
	return null


## 把「-1 = 当前受控影人」解析成具体编号；已经是具体编号时原样返回。
##
## 存在的理由：第 2 关的挂起/取回之后「谁受控」由玩家决定，若把编号写死在关卡数据里，
## 取回之后紧跟着的移动/抬手落点就会与实际的受控影人错配，整关判定必然失败。
## 事件与结果里对外输出的 object_id 一律是**解析后的具体编号**，不让 -1 流给显示与录制。
func _resolve_object_id(object_id: int) -> int:
	if object_id >= 0:
		return object_id
	var controlled: PuppetState = _controlled_state()
	return controlled.puppet_id if controlled != null else -1


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
