extends RefCounted
class_name CReplayPlayer
## 回放播放器：把一份 PerformanceRecord 按原时间线 1:1 重演。
##
## 契约见 TECH_DESIGN 第 4 节：回放从 t=0 推进，连续姿态在相邻样本间插值，
## 离散事件在原时间点应用；**回放不再接收操影输入，也不重新判定合拍度**。
##
## 只读边界（TECH_DESIGN 2.3）：本类只读记录，绝不写回。
## 表现层（B 侧）拿本类产出的状态字典自己渲染，渲染时不回改这份数据。
## 这一点是「幕后与幕前画面一致」的边界——两边读同一份数据、同一时刻。
##
## 本类不持有任何引擎对象，不碰音频。锣鼓与音效由 B 侧按时间轴自行触发
## （C 录不到声音是设计而非缺陷），所以这里只提供「当前该播哪条事件」。
##
## 依赖一律用 preload 常量：godot --headless --script 不读全局类名缓存。

const CSnapshotScript := preload("res://scripts/c/c_snapshot.gd")

## 插值区间容差（微秒）。用于判断「正好落在某个采样点上」。
const TIME_EPSILON_US: int = 1

## 状态名称。与任务书要求的十态对齐，回放侧用它们驱动表现层。
const STATE_IDLE: StringName = &"idle"                ## 未开始
const STATE_READY: StringName = &"ready"              ## 已装载记录，t=0 待播
const STATE_PLAYING: StringName = &"playing"          ## 正在回放
const STATE_PAUSED: StringName = &"paused"            ## 已暂停，画面冻结
const STATE_REPLAY: StringName = &"replay"            ## 结果页重看中
const STATE_FINISHED: StringName = &"finished"        ## 回放结束

## 记录。只读。
var _record: Variant = null
## 当前播放时刻（毫秒），从 0 到 duration_ms。
var _now_ms: int = 0
## 当前状态。
var _state: StringName = STATE_IDLE
## 已应用到本时刻的事件索引游标。事件按 (time_ms, seq) 有序，
## 用游标而非每帧重扫，长演出下 O(1) 推进。
var _event_cursor: int = 0
## 本次回放已派发的事件索引，供表现层逐条消费。
var _pending_events: Array = []
## 累计派发的事件数，诊断与验收用。
var _dispatched_event_count: int = 0
## 暂停前的时刻，resume 时回到这里。
var _resume_from_ms: int = 0
## 本次回放是否已到过终点。用于区分「正在播」与「播完了」。
var _reached_end: bool = false
## **墙钟基准**（微秒）。播放头由「现在 − 基准」得出，而不是由调用方
## 逐帧累加传进来的 delta 累加得出。
##
## 为什么必须这样（2026-10-07 实测）：原先 `_now_ms += delta` 完全依赖
## 调用方喂 delta，而集成层（scratch/real_record_demo.gd:313）喂的是
## **墙钟差值**。于是「进入回放前的重活」（建遮罩层、建 HUD、镜像变换、
## 遍历并打印全部伞事件）以及截图卡顿产生的时长，会被**整段算进播放头**。
## 实测后果：回放第一帧 now_ms 已到约 1500ms，前 1500ms 整段没播，
## `umbrella_take@1268ms` 已生效 → **伞直接闪现在白素贞手上、开场被跳过**。
## 自持基准后，播放头只从 `play()` 那一刻起算，前置耗时不再计入。
var _wall_base_us: int = 0
## 进入暂停的那一刻（微秒），仅供诊断。
var _pause_wall_us: int = 0
## 是否已推进过至少一帧。用于首帧保护：play() 之后的那一次 advance()
## 无论墙钟走了多久，都必须产出 now_ms=0，并在**那一刻**重设墙钟基准
## （见 _next_now_ms 的注释——基准设在第一次推进，不是只设在 play()）。
var _has_advanced: bool = false

## 时钟来源：自持墙钟（默认，运行时用）/ 由调用方注入 delta（测试批跑用）。
##
## 为什么要有第二种：headless 批跑时墙钟几乎不走，测试必须能注入逻辑时间
## 才能把 35s 的演出在毫秒内推进完。**这不是绕过校验，而是同一语义的两个时钟源**——
## 墙钟源决定真实播放的节奏，delta 源决定测试的推进节奏，插值与事件派发逻辑共用。
const CLOCK_SOURCE_WALL: int = 0
const CLOCK_SOURCE_DELTA: int = 1
var _clock_source: int = CLOCK_SOURCE_WALL


## 选择时钟来源。必须在 play() 之前调用。
##
## 参数：CLOCK_SOURCE_WALL（默认，运行时）/ CLOCK_SOURCE_DELTA（测试批跑）。
func set_clock_source(p_source: int) -> void:
	_clock_source = p_source


## 当前时钟来源。诊断与断言用。
func get_clock_source() -> int:
	return _clock_source


func _init(p_record: Variant = null) -> void:
	if p_record != null:
		load(p_record)


## 装载一份记录并复位到 t=0。此时状态为 ready，尚未开始推进。
func load(p_record: Variant) -> bool:
	if p_record == null:
		push_error("CReplayPlayer.load: record 为 null")
		return false
	var problems: Array = p_record.validate_invariants()
	if not problems.is_empty():
		# 带着已知错误开始回放，画面会稳定地错，比不回放更难排查。
		# 因此这里直接拒绝加载，而不是让错误往后传。
		for p in problems:
			push_error("CReplayPlayer.load: 记录不变量未通过 —— %s" % str(p))
		return false
	_record = p_record
	reset()
	return true


## 回到 t=0 待机。结果页「重看」调本方法，而不是重新 load——
## 重新 load 会丢掉同一条记录，重看必须是同一次演出的重演。
func reset() -> void:
	_now_ms = 0
	_event_cursor = 0
	_pending_events.clear()
	_dispatched_event_count = 0
	_resume_from_ms = 0
	_reached_end = false
	_has_advanced = false
	_wall_base_us = Time.get_ticks_usec()
	_state = STATE_READY if _record != null else STATE_IDLE


## 从 t=0 开始播放。已结束的重看也走这里。
func play() -> void:
	if _record == null:
		push_error("CReplayPlayer.play: 尚未 load()")
		return
	_now_ms = 0
	_event_cursor = 0
	_pending_events.clear()
	_dispatched_event_count = 0
	_reached_end = false
	_has_advanced = false
	# 基准设在 play() 这一刻。**不是**在 load() 那一刻——
	# load() 与 play() 之间集成层还要装载场景、建遮罩层、做镜像变换，
	# 那段时间不属于演出，不该算进播放头。
	_wall_base_us = Time.get_ticks_usec()
	_state = STATE_PLAYING


## 暂停。**冻结播放头**，不推进、不派发新事件。
##
## 注意：本类不碰音频与动画——暂停音画同步是 B 侧的事，
## B 侧以「now_ms 未变」作为暂停判据，因此这里必须真的停住。
func pause() -> void:
	if _state != STATE_PLAYING and _state != STATE_REPLAY:
		return
	_resume_from_ms = _now_ms
	_pause_wall_us = Time.get_ticks_usec()
	_state = STATE_PAUSED


## 从暂停处继续。**不重置时钟**，否则恢复瞬间会跳一段。
func resume() -> void:
	if _state != STATE_PAUSED:
		return
	_now_ms = _resume_from_ms
	# 基准重设到「此刻」，于是暂停时长不会在恢复后被一次性补进播放头。
	# 不重设的话，恢复后第一帧会把暂停的整段时长当成经过时间补上——
	# 表现就是「按了继续，画面猛地往前跳一段」。
	_wall_base_us = Time.get_ticks_usec() - int(_now_ms) * 1000
	_state = STATE_PLAYING


## 跳过：不播剩余部分，直接进入 finished。
##
## PRD 第 5.2 节：「跳过直接进入本关结果」。因此本方法不改变 now_ms 语义之外的东西，
## 也不派发未到时刻的事件——被跳过的动作就该被跳过。
func skip() -> void:
	if _record == null:
		push_error("CReplayPlayer.skip: 尚未 load()")
		return
	_now_ms = _record.get_replay_duration_ms()
	_state = STATE_FINISHED
	_reached_end = true
	_pending_events.clear()
	_event_cursor = _record.events.size()


## 推进 p_delta 毫秒并产出当前状态。
##
## 返回给表现层的字典：
##   {
##     "now_ms": int,                  # 当前播放时刻
##     "progress": float,              # 0.0-1.0
##     "puppets": Array[Dictionary],   # 长度 3，字段形状同 PuppetState.to_dict()
##     "lamp": Dictionary,             # 字段形状同 LampState.to_dict()
##     "events": Array[Dictionary],    # 本帧新到达的事件，调用方消费后即失效
##     "state": StringName,            # 十态之一
##     "is_finished": bool,
##   }
##
## 暂停时**返回同一份内容**且 now_ms 不变——这是 B 侧判断「该停帧了」的依据。
func advance(p_delta: float) -> Dictionary:
	if _record == null:
		return _empty_frame()

	# 暂停态：只返回，不推进。delta 完全不消耗。
	if _state == STATE_PAUSED:
		return sample(_now_ms)
	if _state != STATE_PLAYING and _state != STATE_REPLAY:
		return sample(_now_ms)

	_now_ms = _next_now_ms(p_delta)
	var duration: int = _record.get_replay_duration_ms()
	if _now_ms >= duration:
		# 末尾对齐：把播放头钉在 duration 上，否则最后一帧的位置会被
		# 越过，重看时开头与结尾对不上。
		_now_ms = duration
		_reached_end = true
		_state = STATE_FINISHED

	_dispatch_events()
	return sample(_now_ms)


## 计算下一次推进后的播放头时刻（毫秒）。
##
## 播放头的来源是**自持墙钟基准**（play() 那一刻的 ticks_usec），
## 而不是调用方逐帧累加传进来的 delta。
##
## p_delta 只作为**墙钟不可用时的兜底**（基准为 0，说明 play() 没走过），
## 以及首帧保护后第一帧的增量来源。传入的 delta 仍是必需的：headless 批跑
## 时墙钟与逻辑帧不同步，只有 headless 且尚未 play() 才会走到兜底分支。
func _next_now_ms(p_delta: float) -> int:
	if _clock_source == CLOCK_SOURCE_DELTA:
		# delta 源：完全保持原有累加语义（含首帧照常推进）。
		# 测试批跑靠这个把 35s 演出在毫秒内走完；若在这里套首帧保护，
		# 所有依赖精确步进的既有断言都会整体偏移一帧。
		return _now_ms + int(round(maxf(p_delta, 0.0) * 1000.0))
	#首帧保护：play() 之后的第一次 advance() 无论墙钟走了多久，
	# 都必须产出 now_ms = _now_ms（play() 已把它置0）。
	# 没有这条，一次卡顿就会让回放从第一帧就跳到几百毫秒之后。
	#
	# **关键：基准在这里重设，而不是只在 play() 里设一次。**
	# 实测（2026-10-07）：只靠 play() 设基准 + 首帧返回 0 是不够的——
	# 探针显示首帧确实是 0，但第二帧就跳到 1527ms，因为 play() 与第一次
	# advance() 之间集成层仍在做重活（建遮罩/HUD/镜像），这段墙钟仍被
	# 基准计入。**演出起点的定义是「第一次真正推进」，不是「调用 play()」。**
	if not _has_advanced:
		_has_advanced = true
		_wall_base_us = Time.get_ticks_usec()
		return _now_ms
	var wall_ms: int = int((Time.get_ticks_usec() - _wall_base_us) / 1000)
	# 墙钟基准不可用或还没走够 1ms 时退回调用方 delta 累加。
	if wall_ms <= 0:
		return _now_ms + int(round(maxf(p_delta, 0.0) * 1000.0))
	return wall_ms


## 取 now_ms 时刻的完整状态（插值后）。不推进时间。
func sample(p_now_ms: int) -> Dictionary:
	if _record == null:
		return _empty_frame()
	var duration: int = _record.get_replay_duration_ms()
	var t: int = clampi(p_now_ms, 0, duration)
	var blended: Dictionary = _blend_at(t)
	return {
		"now_ms": t,
		"progress": 0.0 if duration <= 0 else clampf(float(t) / float(duration), 0.0, 1.0),
		"puppets": blended["puppets"],
		"lamp": blended["lamp"],
		"events": _pending_events.duplicate(true),
		"state": _state,
		"is_finished": _reached_end,
	}


## 在 now_ms 时刻插值出影人与灯的状态。
##
## 线性插值，不做任何平滑或缓动：TECH_DESIGN 允许「插值带来的轻微过渡差异」，
## 但不允许改变动作顺序。加缓动会让停下再启动的过渡时长与记录不符，
## 那才是真正的漂移。
func _blend_at(now_ms: int) -> Dictionary:
	var idx: int = _record.find_snapshot_index_at(now_ms)
	if idx < 0:
		# t 早于第一帧。**返回首帧内容**，而不是默认站位。
		#
		# 为什么（2026-10-07 实测）：记录的首帧 time_ms 不是 0，而是首个tick 后的
		# 时刻（实测 17ms）—— `c_stage_recorder.advance()` 先 `clock.update(delta)`
		# 再capture，所以第一帧就带着 17ms。回放起步的0~17ms 正好落在这个区间。
		# 若这里返回 `_default_puppets()`（三具都站x=0.5 的通用默认位），
		# 就会演出「开场三具影人挤在中间站定 17ms，然后跳到真实站位」——
		# 观感就是**开场瞬移**，而且它发生在回放最开始的 17ms，比插值跳变更显眼。
		#
		# 「首帧内容」就是t<17ms 时的正确答案：那段时间确实只有首帧那一份数据。
		var first: Variant = _record.snapshots[0]
		return {"puppets": _copy_puppets(first), "lamp": first.lamp.duplicate(true)}

	var a: Variant = _record.snapshots[idx]
	# 已经越过最后一帧：直接用最后一帧，不外推。
	if idx >= _record.snapshots.size() - 1:
		return {"puppets": _copy_puppets(a), "lamp": a.lamp.duplicate(true)}

	var b: Variant = _record.snapshots[idx + 1]
	var span: int = int(b.time_ms) - int(a.time_ms)
	if span <= 0:
		# 同一时刻不该有两帧（记录侧已去重）。出现时用 a，宁可停顿也不外推。
		return {"puppets": _copy_puppets(a), "lamp": a.lamp.duplicate(true)}
	var ratio: float = clampf(float(now_ms - int(a.time_ms)) / float(span), 0.0, 1.0)
	return {
		"puppets": _lerp_puppets(a, b, ratio),
		"lamp": _lerp_lamp(a.lamp, b.lamp, ratio),
	}


## 影人插值。离散量（head_id / hook_slot / is_controlled）**不插值**——
## 头和挂钩是道具归属，在两帧之间取中间值等于造出从未存在过的第三个头。
## 它们的正确表现是在原时间点跳变，由事件与快照的跳变呈现。
func _lerp_puppets(a: Variant, b: Variant, ratio: float) -> Array:
	var out: Array = []
	var count: int = mini(a.puppets.size(), b.puppets.size())
	for i in count:
		var pa: Dictionary = a.puppets[i]
		var pb: Dictionary = b.puppets[i]
		var pos_a: Dictionary = pa.get("stage_pos", {})
		var pos_b: Dictionary = pb.get("stage_pos", {})
		var hand_a: Dictionary = pa.get("hand_angle", {})
		var hand_b: Dictionary = pb.get("hand_angle", {})
		out.append({
			"puppet_id": int(pa.get("puppet_id", i)),
			"stage_pos": {
				"x": _lerp_float(pos_a.get("x", 0.0), pos_b.get("x", 0.0), ratio),
				"y": _lerp_float(pos_a.get("y", 0.0), pos_b.get("y", 0.0), ratio),
			},
			"stance": _lerp_float(pa.get("stance", 0.0), pb.get("stance", 0.0), ratio),
			"facing": _lerp_float(pa.get("facing", 0.0), pb.get("facing", 0.0), ratio),
			"turn_progress": _lerp_float(
				pa.get("turn_progress", 0.0), pb.get("turn_progress", 0.0), ratio),
			"hand_angle": {
				"left": _lerp_float(hand_a.get("left", 0.0), hand_b.get("left", 0.0), ratio),
				"right": _lerp_float(hand_a.get("right", 0.0), hand_b.get("right", 0.0), ratio),
			},
			# 离散量跟随「时间已过 b 的落点」翻转，等价于在 b.time_ms 那一刻跳变。
			"head_id": int(pb.get("head_id", -1)) if ratio >= 1.0 else int(pa.get("head_id", -1)),
			"hook_slot": int(pb.get("hook_slot", -1)) if ratio >= 1.0 else int(pa.get("hook_slot", -1)),
			"is_controlled": bool(pa.get("is_controlled", false)),
		})
	return out


## 灯态插值。四字段全是连续量，全部插值。
func _lerp_lamp(a: Dictionary, b: Dictionary, ratio: float) -> Dictionary:
	var out: Dictionary = CSnapshotScript.default_lamp_dict()
	for key in out.keys():
		out[key] = _lerp_float(a.get(key, out[key]), b.get(key, out[key]), ratio)
		# 灯距越大=灯越近（B 侧已确认方向），插值不改变方向，只在端点之间取值。
	return out


func _lerp_float(a: Variant, b: Variant, ratio: float) -> float:
	return lerpf(float(a), float(b), ratio)


## 派发本帧新到达的事件到 _pending_events。
##
## 按记录原顺序逐条应用，同毫秒按 seq 顺序；**不合并、不去重、不推导**
## （TECH_DESIGN 2.3：换头、挂起、补救、掌声等事件不由回放重新推导）。
func _dispatch_events() -> void:
	_pending_events.clear()
	var events: Array = _record.events
	while _event_cursor < events.size():
		var ev: Variant = events[_event_cursor]
		if int(ev.time_ms) > _now_ms:
			break
		_pending_events.append(ev)
		_event_cursor += 1
		_dispatched_event_count += 1


## 当前状态名称。给 HUD 与表现层用。
func get_state() -> StringName:
	return _state


## 当前播放时刻。
func get_now_ms() -> int:
	return _now_ms


## 本次回放已派发的事件数。验收应用「没有漏动作、没有改变结局」时用它。
func get_dispatched_event_count() -> int:
	return _dispatched_event_count


## 是否已到终点。
func is_finished() -> bool:
	return _reached_end


## 记录是否已装载。
func has_record() -> bool:
	return _record != null


func _copy_puppets(snap: Variant) -> Array:
	var out: Array = []
	for p in snap.puppets:
		out.append((p as Dictionary).duplicate(true))
	return out


func _default_puppets() -> Array:
	var snap: Variant = CSnapshotScript.new(0)
	var out: Array = []
	for p in snap.puppets:
		out.append((p as Dictionary).duplicate(true))
	return out


func _empty_frame() -> Dictionary:
	return {
		"now_ms": 0,
		"progress": 0.0,
		"puppets": _default_puppets(),
		"lamp": CSnapshotScript.default_lamp_dict(),
		"events": [],
		"state": STATE_IDLE,
		"is_finished": false,
	}
