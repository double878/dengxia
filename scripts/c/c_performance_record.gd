extends RefCounted
class_name CPerformanceRecord
## 一次演出的完整记录。契约见 TECH_DESIGN.md 第 2.3 节与第 4 节。
##
## 生命周期：一关开始时新建，演出期间由 Recorder 写入，关后只在本关结果页保留，
## 离开本关即释放。不写入长期存档，不做录像库。
##
## 时长口径：duration_ms 用关卡固定时长（第一关 35000），
## 不用最后一个 Snapshot 的 time_ms。否则「第 30 帧才采到 34983」
## 会被回放成 34.98 秒，与 1:1 重演差一帧。
##
## 本类只做存储与顺序保证。回放器只读本对象，不回调输入和评分模块——
## 这是 TECH_DESIGN 第 2.3 节「单向数据流」在 C 侧的边界。

## 第一关固定时长。PRD 1.1 的时长口径：35/45/50/55/110 秒，合计 295 秒。
const STAGE1_DURATION_MS: int = 35000

## 采样频率。30 Hz × 110 秒 ≈ 3300 个 Snapshot，单场数百 KB，内存保存可行。
const SAMPLE_HZ: float = 30.0
## 采样间隔以微秒表示，避免整数毫秒步进的累计误差。
## 1000000 / 30 = 33333.33 微秒；若按整数 33 毫秒固定步进，
## 35 秒会累计到 34980（差 20ms）且永远采不到 35000 整点，
## 110 秒累计误差更大。因此用微秒整数逐帧累进，采样点本身仍落在整数毫秒上。
const SAMPLE_INTERVAL_US: int = 33333
## 采样点的毫秒对齐容差：累进到 33333us 时取整仍是 33ms，不做额外偏移。
const US_PER_MS: int = 1000

var stage_id: int = -1
var duration_ms: int = 0
## 按 time_ms 升序；同一 time_ms 内只可能有一条（见 append_snapshot 的去重）。
var snapshots: Array = []
## 按 (time_ms, seq) 升序。seq 从 1 开始连续。
var events: Array = []
## 第 5 关三段的掌声结果；第 1–4 关为空数组。
## 结构：[{act_index:int, has_applause:bool, start_ms:int, end_ms:int}]
var acts: Array = []

## seq 分配器：仅在事件成功追加时 +1，写入失败不消耗。
var _next_seq: int = CTimedEvent.SEQ_FIRST
## 上一次采样的时刻，用于「同一时刻不追加重复 Snapshot」。
var _last_snapshot_time_ms: int = -1
## 上一次采到的内容，用于跳变检测。
var _last_snapshot: CSnapshot = null
## 已记录的幕前结果（掌声），供回放端原样读取，不重算。
var _finished: bool = false


func _init(p_stage_id: int = -1, p_duration_ms: int = 0) -> void:
	stage_id = p_stage_id
	duration_ms = p_duration_ms
	_reset_cursors(0)


## 演出开始时把采样游标归零。t0_ms 是本关音乐起点对应的 time_ms。
func _reset_cursors(t0_ms: int) -> void:
	_sample_origin_ms = t0_ms
	_next_sample_index = 0
	_last_snapshot_time_ms = -1
	_last_snapshot = null


## 是否到了常规采样点。跳变补采样的优先级高于这里：即使本帧不是整点，
## 只要状态发生跳变也必须采样，见 should_sample()。
##
## 判定按相位而非单一游标：now_ms 落在任何一个采样网格点上即为到期。
## 用相位重算而非「下一采样点」单点推进，是因为暂停恢复后时间可能
## 跨过多个采样点，单点推进会漏掉中间的整点（实测 35 秒少采约 2%）。
func is_due_for_sampling(now_ms: int) -> bool:
	if _sample_origin_ms < 0:
		return false
	return _elapsed_us(now_ms) >= _next_sample_index * SAMPLE_INTERVAL_US


## 演出起点。相位计算的基准，第一帧采样时确定。
var _sample_origin_ms: int = -1
## 已通过的常规采样点数。下一个采样点 = origin + count * interval。
var _next_sample_index: int = 0


func _elapsed_us(now_ms: int) -> int:
	return (now_ms - _sample_origin_ms) * US_PER_MS


## 本帧是否需要采样。两种触发：
## 1) 到达常规 30 Hz 采样点；
## 2) 与上一帧相比有字段跳变（换头、挂起、快速转身等瞬时动作）。
## 2) 的优先级高于 1：同一时刻两者都成立时只追加一条。
##
## p_now_ms 必须来自 MusicClock.get_song_time_ms()，不用墙钟——
## 否则回放时长会和判定时间轴错开。
func should_sample(p_now_ms: int, candidate: CSnapshot) -> bool:
	# 暂停时读数冻结：不追加。相位不推进，恢复后按同一网格继续，
	# 因此暂停时长不会挤掉采样点，也不会让 30 Hz 采样相位漂移。
	if _last_snapshot_time_ms >= 0 and p_now_ms == _last_snapshot_time_ms:
		return false
	var jumped := _last_snapshot != null and not candidate.same_content_as(_last_snapshot)
	return jumped or is_due_for_sampling(p_now_ms)


## 追加一帧。调用方须先通过 should_sample() 判定。
## 返回是否真的写入（false 表示被拒绝，已 push_error）。
func append_snapshot(snap: CSnapshot) -> bool:
	if snap == null:
		push_error("CPerformanceRecord.append_snapshot: snap 为 null")
		return false
	if snap.time_ms == _last_snapshot_time_ms:
		# 同一时刻只有一条。跳变与常规采样同帧相遇时走这条，不追加第二条。
		return true
	snapshots.append(snap)
	_last_snapshot_time_ms = snap.time_ms
	_last_snapshot = snap
	# 相位推进：把已过去的采样整点全部计入。跳变帧也走这里，但跳变
	# 不重置相位——否则频繁跳变会把 30 Hz 网格整体推后，
	# 35 秒实测会少采约 2%。
	if _sample_origin_ms < 0:
		_sample_origin_ms = snap.time_ms
	var now_us := _elapsed_us(snap.time_ms)
	while _next_sample_index * SAMPLE_INTERVAL_US <= now_us:
		_next_sample_index += 1
	return true


## 追加一条离散事件。校验不通过则拒绝写入且不消耗 seq。
## 返回是否写入成功。
func append_event(event: CTimedEvent) -> bool:
	if event == null:
		push_error("CPerformanceRecord.append_event: event 为 null")
		return false
	var problems := event.validate()
	if not problems.is_empty():
		push_error("CPerformanceRecord.append_event: 拒绝写入 —— " + "; ".join(problems))
		return false
	if duration_ms > 0 and event.time_ms > duration_ms:
		push_error("CPerformanceRecord.append_event: time_ms %d 超出本关时长 %d"
			% [event.time_ms, duration_ms])
		return false
	event.assign_seq(_next_seq)
	_next_seq += 1
	_insert_event_sorted(event)
	return true


## 顺序不变的前提下插入。多数情况追加在末尾即可；
## take_events() 可能在同一帧吐出多条、或 A 端补发更早时刻的事件，故仍需定位。
func _insert_event_sorted(event: CTimedEvent) -> void:
	var lo := 0
	var hi := events.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if events[mid].compare_order(event) <= 0:
			lo = mid + 1
		else:
			hi = mid
	events.insert(lo, event)


## 写入第 5 关某一段的掌声结果。回放端读这里的值，不重新判定。
func append_act(p_act_index: int, p_has_applause: bool, p_start_ms: int, p_end_ms: int) -> void:
	if p_start_ms > p_end_ms:
		push_error("CPerformanceRecord.append_act: 段落起止时间非法 [%d, %d]" % [p_start_ms, p_end_ms])
		return
	acts.append({
		"act_index": p_act_index,
		"has_applause": p_has_applause,
		"start_ms": p_start_ms,
		"end_ms": p_end_ms,
	})


## 演出结束，冻结记录。此后只读。
## t_end_ms 来自 stage_end 事件的 song_time_ms，但对外一律以 duration_ms 为准。
func finish(t_end_ms: int = -1) -> void:
	_finished = true
	if t_end_ms >= 0 and duration_ms > 0 and t_end_ms > duration_ms:
		push_warning("CPerformanceRecord.finish: 收尾时间 %d 超出本关时长 %d，仍以 duration_ms 为准"
			% [t_end_ms, duration_ms])


## 回放时长。以固定时长为准，不用最后一帧的时间戳（见类注释的时长口径）。
func get_replay_duration_ms() -> int:
	return duration_ms


## 不变量自检。回放前和测试里都应跑一遍，返回问题列表（空表示通过）。
## 这些是契约里写死的规则，实现一旦偏离必须在这里被抓住。
func validate_invariants() -> Array:
	var problems: Array = []

	if duration_ms <= 0:
		problems.append("duration_ms 未设置：%d" % duration_ms)
	elif duration_ms != STAGE1_DURATION_MS and stage_id == 0:
		problems.append("第一关 duration_ms 应为 %d，实际 %d" % [STAGE1_DURATION_MS, duration_ms])

	# snapshots：time_ms 严格递增，且不超出本关时长。
	var prev := -1
	for s in snapshots:
		var snap: CSnapshot = s
		if snap.time_ms < 0:
			problems.append("snapshot time_ms 为负：%d" % snap.time_ms)
		if snap.time_ms <= prev:
			problems.append("snapshot time_ms 非递增：%d 出现在 %d 之后" % [snap.time_ms, prev])
		if duration_ms > 0 and snap.time_ms > duration_ms:
			problems.append("snapshot time_ms %d 超出本关时长 %d" % [snap.time_ms, duration_ms])
		if snap.puppets.size() != CSnapshot.PUPPET_COUNT:
			problems.append("snapshot t=%d 的 puppets 长度应为 %d，实际 %d"
				% [snap.time_ms, CSnapshot.PUPPET_COUNT, snap.puppets.size()])
		prev = snap.time_ms

	# events：按 (time_ms, seq) 升序，且 seq 从 1 连续。
	var expected_seq := CTimedEvent.SEQ_FIRST
	for e in events:
		var ev: CTimedEvent = e
		if ev.seq != expected_seq:
			problems.append("events seq 不连续：期望 %d 实际 %d" % [expected_seq, ev.seq])
		expected_seq += 1
		if duration_ms > 0 and ev.time_ms > duration_ms:
			problems.append("event time_ms %d 超出本关时长 %d" % [ev.time_ms, duration_ms])
		if ev.seq < 0:
			problems.append("event 未分配 seq：%s" % ev.describe())
	for i in range(1, events.size()):
		if events[i - 1].compare_order(events[i]) > 0:
			problems.append("events 顺序错误：%s 出现在 %s 之前"
				% [events[i - 1].describe(), events[i].describe()])
			break

	# 忠实性：补救成功不得抹除此前的失误记录。
	# PRD 5.2.3 —— 已经错过的落点仍计入该幕表现。
	# 只校验 still_missed 的取值与事件流留存，不推断因果关系：
	# 补救成功可能针对的不是关键动作落点，cue_miss 与 remedy_success 的
	# 数量不必一一对应。
	for e in events:
		var ev: CTimedEvent = e
		if ev.kind == CTimedEvent.KIND_REMEDY_SUCCESS \
				and not bool(ev.payload.get("still_missed", true)):
			problems.append("remedy_success 的 still_missed 应为 true：%s" % ev.describe())

	# 忠实性：错拍时动作照常发生，cue_fire 与 cue_miss 必须并存。
	# 只有 cue_miss 而无同 cue_id 的 cue_fire，说明「动作做了」这个事实丢了，
	# 回放将无法呈现。
	for e in events:
		var ev2: CTimedEvent = e
		if ev2.kind == CTimedEvent.KIND_CUE_MISS \
				and not _has_kind_in(events, CTimedEvent.KIND_CUE_FIRE, ev2.cue_id):
			problems.append("cue_miss(%s) 没有对应的 cue_fire，回放将看不到动作确实发生过"
				% ev2.describe())

	return problems


## 同一 cue_id 是否存在指定 kind 的事件。
func _has_kind_in(event_list: Array, kind: StringName, cue_id: String) -> bool:
	for e in event_list:
		var ev: CTimedEvent = e
		if ev.kind == kind and ev.cue_id == cue_id:
			return true
	return false


## 取不超过 now_ms 的最后一帧索引。没有可用帧时返回 -1。
## 回放端按此定位插值区间。
func find_snapshot_index_at(now_ms: int) -> int:
	if snapshots.is_empty():
		return -1
	var lo := 0
	var hi := snapshots.size() - 1
	var found := -1
	while lo <= hi:
		var mid := (lo + hi) / 2
		if snapshots[mid].time_ms <= now_ms:
			found = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return found


## 取时间不晚于 now_ms 的全部事件索引。回放端按记录顺序逐条应用，
## 同毫秒按 seq 顺序；不合并、不去重、不推导。
func collect_event_indices_up_to(now_ms: int) -> Array:
	var out: Array = []
	for i in events.size():
		var ev: CTimedEvent = events[i]
		if ev.time_ms <= now_ms:
			out.append(i)
		else:
			break  # events 已按 time_ms 升序
	return out


## 本关的采样统计，供测试与诊断。
func get_stats() -> Dictionary:
	return {
		"stage_id": stage_id,
		"duration_ms": duration_ms,
		"snapshot_count": snapshots.size(),
		"event_count": events.size(),
		"act_count": acts.size(),
		"last_snapshot_time_ms": _last_snapshot_time_ms,
		"expected_30hz_count": int(ceil(float(duration_ms) / 1000.0 * SAMPLE_HZ)),	}
