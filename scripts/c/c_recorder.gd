extends RefCounted
class_name CRecorder
## 演出录制器：在 A 端每帧固定顺序中的两个位置读取数据并写入 PerformanceRecord。
##
## 数据源是 A 端 Level1Runtime（scripts/a/level1_runtime.gd），一经接入不再用 stub。
## 每帧调用顺序（契约由 A 端冻结，见 PRD 5.1 与 TECH_DESIGN 2.1）：
##   1. 输入
##   2. puppet_controller.tick()      —— A 侧，状态更新
##   3. 【C：capture_states()】       —— 本类，采连续状态 Snapshot
##   4. performance.update()          —— A 侧，关键动作判定
##   5. remedy.update()               —— A 侧，8 秒补救
##   6. 【C：capture_events()】       —— 本类，取离散事件
##
## A 侧把 4/5 两步封装在 Level1Runtime.tick() 内部，因此 C 侧的实际调用是：
##   runtime.tick(delta)              # 内含 2/4/5
##   recorder.capture_states(runtime) # 第 3 步的语义：读 tick 后的最终状态
##   recorder.capture_events(runtime) # 第 6 步：取本帧事件
## 「第 3 步在第 4/5 步之前」这一语义由 A 端 tick() 内部顺序保证；
## C 侧在 tick() 之后读到的必然是本帧最终值（lamp_controller.update 是 tick 内最后一步）。
##
## 两种采样触发（TECH_DESIGN 第 4 节）：
## - 30 Hz 定频采样，覆盖连续姿态变化；
## - 字段跳变当帧立刻追加，覆盖 30 Hz 会漏掉的瞬时动作（快速转身、
##   抬手到底、换头、挂起）。跳变优先级更高，同一时刻只追加一条。
##
## 时钟：本类不持有时间源，从 p_clock.get_song_time_ms() 读歌曲时间。
## 绝不使用 Time.get_ticks_msec() 等墙钟——否则回放时长会和判定时间轴错开。
##
## 暂停：A 端 set_paused(true) 会 clock.pause()，而 tick() 开头即
## `if clock.is_paused(): return`，因此暂停期间 tick 不产生新状态与新事件，
## capture_* 自然也采不到东西——「暂停冻结不追加不推进」由 A 端保证。
##
## 单向数据流（TECH_DESIGN 2.3）：本类只读 A 的状态与事件，不写回任何状态。
## 这是「幕后与幕前画面一致」的边界所在。

const CSnapshotScript := preload("res://scripts/c/c_snapshot.gd")
const CTimedEventScript := preload("res://scripts/c/c_timed_event.gd")
const CPerformanceRecordScript := preload("res://scripts/c/c_performance_record.gd")

## 本帧累计写入的事件数，供 StageDirector 判断是否需要刷新示范显示。
var _pending_event_count: int = 0
var _record: Variant = null
## 是否已记录过 stage_start。
var _stage_started: bool = false
## 时钟倒退的次数。正常演出不应出现；出现说明上游时钟有问题，需报出。
var _backwards_clock_count: int = 0
## 上一次读到的时间，用于检测时钟倒退。
var _last_now_ms: int = -1
## 累计补救冻结时长（真实时间 - 歌曲时间 的差值）。
## 单调不减，诊断与测试用它核对「补救过程确实被录进去了」。
var _frozen_accum_ms: int = 0


func _init(p_record: Variant = null) -> void:
	_record = p_record


## 绑定本次演出的记录对象。一关开始时调用一次。
func begin(p_stage_id: int, p_duration_ms: int) -> Variant:
	_record = CPerformanceRecordScript.new(p_stage_id, p_duration_ms)
	_stage_started = false
	_pending_event_count = 0
	_backwards_clock_count = 0
	_last_now_ms = -1
	_frozen_accum_ms = 0
	return _record


## 第 3 步：采连续状态。
##
## p_runtime 是 A 端的 Level1Runtime，本类按鸭子类型读取两个视图：
##   p_runtime.puppet_controller.puppets → Array[PuppetState]，各有 to_dict()
##   p_runtime.lamp_controller.lamp      → LampState，有 to_dict()
##   p_runtime.clock.get_song_time_ms()  → 唯一时钟
## 用鸭子类型而非具体类型，既便于切换数据源，也避开 --script 模式的类名缓存问题。
##
## **重要语义**：lamp.distance 越大表示灯离影人越近（不是普通距离），
## 本类只原样记录数值，不做任何方向换算——换算若需要，是回放表现层的事。
##
## 返回是否真的写入了一条 Snapshot。
func capture_states(p_runtime: Variant, p_now_ms: int = -1) -> bool:
	if _record == null:
		push_error("CRecorder.capture_states: 尚未 begin()，忽略本帧")
		return false
	if p_runtime == null:
		push_error("CRecorder.capture_states: runtime 为 null，忽略本帧")
		return false
	if p_runtime.clock == null or not p_runtime.clock.has_method("get_song_time_ms"):
		push_error("CRecorder.capture_states: clock 缺少 get_song_time_ms()，忽略本帧")
		return false

	var raw_ms: int = p_now_ms if p_now_ms >= 0 else _resolve_now_ms(p_runtime)

	# 时钟倒退检测：正常演出单调不减。暂停时读数冻结（相等），不算倒退。
	# 用**钳制前**的原始读数检测，钳制本身不会掩盖真实倒退。
	#
	# 补救冻结会让时间轴超出 duration_ms（见下面钳制说明），
	# 倒退检测必须放在钳制**之前**，否则会被钳到 duration_ms 而看不出问题。
	if _last_now_ms >= 0 and raw_ms < _last_now_ms:
		_backwards_clock_count += 1
		push_error("CRecorder.capture_states: 时钟倒退 %dms → %dms" % [_last_now_ms, raw_ms])
	_last_now_ms = raw_ms

	# 时间钳到 duration_ms。
	#
	# 越界有两个来源，**都要钳**：
	# 1) 末帧步长除不尽。A 的 MusicClock 是不钳制的自由秒表
	#    （music_clock.gd:196 直接返回 int(round(_free_s * 1000))），
	#    而 35000 不是 16.67ms 的整数倍，收尾帧常读到 35007 之类。
	# 2) 补救冻结把时间轴拉长（_resolve_now_ms 的补偿）。实测空演 40 秒
	#    累计冻结约 5 秒，末帧会到 40000+ —— 这是**如实记录补救**的必然结果，
	#    不是 bug。钳制保证不变量（c_performance_record.gd:211/225）仍成立。
	#
	# 钳制会让越界的那几帧都落在 duration_ms 上（此时 should_sample 的同刻去重
	# 会跳过它们），代价是「演出末尾极短的一段补救」在回放里被压到最后一帧。
	# 换来的是记录一定合法、准入闸门一定放行——这个取舍是划算的：
	# 补救的主体（长达数秒的那几段）都在 duration_ms 之前，已被完整记录。
	var now_ms: int = raw_ms
	if _record.duration_ms > 0 and now_ms > _record.duration_ms:
		now_ms = _record.duration_ms

	var views: Dictionary = _collect_views(p_runtime)
	var candidate: Variant = CSnapshotScript.from_views(
		now_ms, views.get("puppets", []), views.get("lamp", {}))
	if not _record.should_sample(now_ms, candidate):
		return false
	return _record.append_snapshot(candidate)


## 取本帧该用的时间戳：**歌曲时间 + 累计补救冻结时长**。
##
## 为什么冻结期必须补偿（2026-10-07 实测）：
## A 端 `music_clock.gd:89-95` 在补救冻结时直接 `return false` ——
## **歌曲时间与拍点全部停住，但 `_real_s` 照常走**（8 秒补救窗按真实时间计时）。
## 而本类只读 `get_song_time_ms()`，于是冻结期里 runtime.tick() 仍在推进
## （灯油每帧消耗、补救动作演出），可所有快照与事件都被钉在**同一个 time_ms**：
## 指纹是「快照数不变、事件数持续递增」（用户日志 t=1503ms 时 快照 81 / 事件 170→260）。
## 回放时这几秒的补救被压缩进一帧 —— 观感就是闪现。
##
## 为什么用「差值」而不是「冻结期改读 get_real_time_ms()」：
## `get_real_time_ms() - get_song_time_ms()` **恰好等于累计冻结时长**——
## 非冻结期两者同步前进（差值恒定），冻结期只有真实时间走（差值增长）。
## 因此 `歌曲时间 + 差值` 是一个**跨全片单调不减、无需任何重基**的时间轴：
##   - 冻结期：歌曲时间停住，差值随真实时间涨 → 时间继续走，补救逐帧落进记录；
##   - 解冻后：歌曲时间恢复前进，差值保持 → 直接续上，不会倒退；
##   - 多次冻结/解冻：差值是累加量，逐段叠加，不会回落。
## 早期实现用的是「冻结期读真实时间 + 解冻时把歌曲时间顶到 last+1」，
## 探针实测在**第二次**冻结时就失效（歌曲时间远小于已推进的 last），
## 报「snapshot time_ms 非递增：1533 出现在 9501 之后」。差值法从根上避免了重基。
##
## 代价：时间轴被拉长（冻结期时长计入总长），末帧 time_ms 会超过 duration_ms。
## 这是「如实记录补救时长」必然要付的，见 capture_states 的钳制说明。
##
## 真实时间读数不存在时（老版本 A 侧）退回歌曲时间，行为与改动前完全一致。
func _resolve_now_ms(p_runtime: Variant) -> int:
	var clock: Variant = p_runtime.clock
	var song_ms: int = int(clock.get_song_time_ms())
	if not clock.has_method("get_real_time_ms"):
		return song_ms
	var drift: int = int(clock.get_real_time_ms()) - song_ms
	if drift > _frozen_accum_ms:
		_frozen_accum_ms = drift
	return song_ms + _frozen_accum_ms


## 从 runtime 收集 A 端状态视图。缺任何一路都报错并返回已取到的部分，
## 由 CSnapshot.from_views 的缺省逻辑兜底，不静默写入错误数据。
func _collect_views(p_runtime: Variant) -> Dictionary:
	var out: Dictionary = {"puppets": [], "lamp": {}}
	if p_runtime.puppet_controller == null:
		push_error("CRecorder: runtime.puppet_controller 为 null")
	else:
		var puppet_views: Array = []
		for p in p_runtime.puppet_controller.puppets:
			puppet_views.append(p.to_dict())
		out["puppets"] = puppet_views
	if p_runtime.lamp_controller == null or p_runtime.lamp_controller.lamp == null:
		push_error("CRecorder: runtime.lamp_controller.lamp 为 null")
	else:
		out["lamp"] = p_runtime.lamp_controller.lamp.to_dict()
	return out


## 第 6 步：取离散事件。
##
## A 端 take_events() 返回 Array[Dictionary]，**取走即清空**，因此每帧取一次
## 不会重复记录。**不做任何节流**：lamp_oil_changed 在演出期间基本每帧一条，
## 原样全量记录——节流会让回放与真实演出不一致。
##
## 返回本帧成功写入的事件数。校验失败的事件由 PerformanceRecord 拒绝，
## 并已在其中 push_error；此处补一条上下文说明哪一帧丢了事件。
func capture_events(p_runtime: Variant) -> int:
	if _record == null:
		push_error("CRecorder.capture_events: 尚未 begin()，忽略本帧")
		return 0
	if p_runtime == null or not p_runtime.has_method("take_events"):
		# 事件源不存在不算错误：本帧没有事件是正常情况。
		return 0

	var raw: Array = p_runtime.take_events()
	var written: int = 0
	for item in raw:
		var event: Variant = _to_timed_event(item, _frozen_accum_ms)
		if event == null:
			continue
		if not _record.append_event(event):
			push_error("CRecorder.capture_events: 本帧丢弃事件 %s" % str(item))
			continue
		written += 1
		if String(event.kind) == "stage_start":
			_stage_started = true
	_pending_event_count += written
	return written


## 把 A 端产出的 Dictionary 统一成 CTimedEvent。
## 不改字段名、不改单位、不解释 payload——转换是 A 的职责。
##
## object_id 原样透传（Variant）：影人 int 0-2 / 油灯 String "lamp_main"，
## 两个命名空间由 CTimedEvent.validate() 按类型分别校验。
##
## p_frozen_accum_ms 是**本帧的累计冻结时长**，与 capture_states 用的是同一个值
## （两者由 CStageRecorder.advance 按 states→events 顺序调用，中途不会变）。
## A 端给的事件时间戳是歌曲时间，补救冻结期它会停住——`remedy_freeze_begin/end`
## 于是全挤在同一毫秒上，回放时补救段等于消失（实测 t=1517ms 处 6 条补救事件同刻）。
## 因此事件时间要加同一个补偿量，与快照对齐到**同一条时间轴**：
## 快照与事件的时间基准不一致，回放端无法把「补救画面」和「补救提示」对上。
## 这正是 A 侧 `stage_director.gd:13` 写明「供 C 记录回放节奏」的本意。
func _to_timed_event(item: Variant, p_frozen_accum_ms: int = 0) -> Variant:
	if item is CTimedEventScript:
		return item
	if typeof(item) != TYPE_DICTIONARY:
		push_error("CRecorder._to_timed_event: 事件不是字典也不是 CTimedEvent")
		return null
	var d: Dictionary = item
	var time_ms: int = int(d.get("time_ms", -1))
	if time_ms < 0:
		# 事件时间必须由 A 端给出；缺失就是上游问题，不猜。
		push_error("CRecorder._to_timed_event: 事件缺少合法 time_ms：%s" % str(item))
		return null
	# **先加补偿、再钳制**（顺序不可颠倒）。
	# 早先写成「先钳到 duration_ms、再加 _frozen_accum_ms」，补偿会把刚钳好的值
	# 重新推出边界，事件最终时间仍 > duration_ms，被 append_event 与
	# validate_invariants 拒绝——补救末段的freeze_end 恰好落在这一格里。
	# 钳在加补偿之后，快照与事件才真正落在同一条（同时合法）的时间轴上。
	var kind: StringName = StringName(str(d.get("kind", "")))
	# object_id 不做 int() 强转：String命名空间会被毁掉。原样透传。
	var object_id: Variant = d.get("object_id", CTimedEventScript.OBJECT_ID_NONE)
	var cue_id: String = str(d.get("cue_id", CTimedEventScript.CUE_ID_NONE))
	var payload: Dictionary = {}
	if typeof(d.get("payload", {})) == TYPE_DICTIONARY:
		payload = d.get("payload", {})
	time_ms += p_frozen_accum_ms
	if _record != null and _record.duration_ms > 0 and time_ms > _record.duration_ms:
		time_ms = _record.duration_ms
	return CTimedEventScript.new(time_ms, kind, object_id, cue_id, payload)


## 演出结束。t_end_ms 来自 stage_end 事件的 song_time_ms，
## 但对外一律以 record.duration_ms 为准。
func finish(t_end_ms: int = -1) -> void:
	if _record == null:
		push_error("CRecorder.finish: 尚未 begin()")
		return
	_record.finish(t_end_ms)
	var problems: Array = _record.validate_invariants()
	if not problems.is_empty():
		for p in problems:
			push_error("CRecorder.finish: 记录不变量被破坏 —— %s" % str(p))


## 取得本次演出的记录。离开本关后调用方应释放，不写入长期存档。
func get_record() -> Variant:
	return _record


## 本关采样与事件统计，供诊断与测试。
func get_stats() -> Dictionary:
	if _record == null:
		return {}
	var stats: Dictionary = _record.get_stats()
	stats["backwards_clock_count"] = _backwards_clock_count
	stats["pending_event_count"] = _pending_event_count
	stats["stage_started"] = _stage_started
	stats["frozen_accum_ms"] = _frozen_accum_ms
	return stats


## 释放记录。离开本关时调用，避免 PerformanceRecord 跨关残留。
func release() -> void:
	_record = null
	_stage_started = false
	_pending_event_count = 0
	_last_now_ms = -1
	_frozen_accum_ms = 0