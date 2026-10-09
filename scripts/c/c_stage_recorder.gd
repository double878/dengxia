extends RefCounted
class_name CStageRecorder
## 演出录制接线层：把 A 端 Level1Runtime 与 CRecorder 按契约顺序编排起来。
##
## 存在的理由：CRecorder 只管「怎么采」，不负责「什么时候采」。
## 而采样的正确时机取决于 A 端每帧的固定顺序（见 TECH_DESIGN 2.1、2.3）：
##   输入 → clock.update() → puppet_controller.tick() → 【C 采 Snapshot】
##        → performance.update() → remedy.update() → 【C 采事件】
## A 端把状态更新与中间判定封装进 Level1Runtime.tick()，因此接线只剩这几步：
##   clock.update(delta)               # 音乐时钟：歌曲时间只在这里前进
##   runtime.tick(delta)               # 内含状态更新 / 判定 / 补救 / 灯更新
##   recorder.capture_states(runtime)  # 读 tick 后的最终状态
##   recorder.capture_events(runtime)  # 取本帧事件（take_events 取走即清空）
##   is_over() 为真则 finish           # **必须在采完之后判**，否则丢掉最后一帧
## 顺序颠倒会读到 tick 之前的旧状态，插值整体错一帧——
## 这是本类唯一需要小心的正确性问题，故在此显式固定。
##
## **本类不重算任何数据**：不推导状态、不判定合拍、不重排事件、不写回 A 端。
## 它只做三件事：按时机 begin、每帧编排、按时机 finish。
##
## 落盘约定：TECH_DESIGN 第 132 行明确「一次演出的 PerformanceRecord 留在内存，
## 不做录像库或云端同步」，因此本类**不提供任何写文件接口**。
## 记录留在 get_record() 返回的对象上，由回放端读完即释放。
##
## 单向数据流（TECH_DESIGN 2.3）：本类只读 A 的状态与事件，永久不回写。
## 这是「幕后操演与幕前回放一致」的边界所在。

const CRecorderScript := preload("res://scripts/c/c_recorder.gd")

## 本关采样与事件统计的对外摘要，供 HUD 与诊断显示。
var _recorder: Variant = null
## 是否已完成 begin()。未 begin 就 advance 会报出，避免静默丢数据。
var _begun: bool = false
## 是否已 finish()。结束后不再追加，重复 finish 视为无操作。
var _finished: bool = false
## 记录对象，便于随时取用而不必每次问 Recorder。
var _record: Variant = null
## 累计帧数，诊断用。
var _frame_count: int = 0
## 时钟倒退次数，由 Recorder 统计后汇总。
var _backwards_clock_count: int = 0


func _init(p_recorder: Variant = null) -> void:
	_recorder = p_recorder if p_recorder != null else CRecorderScript.new()


## 演出开始前调用一次，创建记录。
##
## p_stage_id 与 p_duration_ms 直接透传给 CPerformanceRecord，不在这里校验：
## 时长口径由关卡定义（A 端 StageDef）冻结，C 侧擅自改会与判定时间轴错开。
func begin(p_stage_id: int, p_duration_ms: int) -> Variant:
	_record = _recorder.begin(p_stage_id, p_duration_ms)
	_begun = true
	_finished = false
	_frame_count = 0
	_backwards_clock_count = 0
	return _record


## 每帧唯一的入口。p_runtime 是 A 端 Level1Runtime。
##
## 内部顺序即契约，**时钟必须先于 runtime 推进**：
##   clock.update(delta)   # MusicClock 自由计时或跟随音轨推进
##   runtime.tick(delta)   # 内含状态更新 / 判定 / 补救 / 灯更新
##   capture_states()      # 读 tick 后的最终状态
##   capture_events()      # 取本帧事件（take_events 取走即清空）
##
## 时钟这一句不可省：MusicClock 的歌曲时间只有在 update() 里才前进
## （见 music_clock.gd:66），漏掉它 runtime 收到的 delta 正确但时间轴停在 0，
## 表现是「跑满 2100 帧但末帧仍是 t=0」。A 端 level1_harness 也是这个顺序。
##
## 顺序颠倒（capture 早于 tick）会读到 tick 之前的旧状态，插值整体错一帧。
##
## 返回本帧写入的快照数（0 或 1）。不返回是否成功，成功与否由
## Recorder 的 push_error 与 get_stats() 反映。
func advance(p_runtime: Variant, p_delta: float) -> int:
	if not _begun:
		push_error("CStageRecorder.advance: 尚未 begin()，本帧不录制")
		return 0
	if p_runtime == null:
		push_error("CStageRecorder.advance: runtime 为 null，本帧不录制")
		return 0
	# 已收尾：彻底停止录制。回放端此时才可安全读取记录。
	if _finished:
		return 0

	# 1) 先推进音乐时钟。runtime 判定所依据的 song_time_ms 由此更新。
	var clock: Variant = p_runtime.clock
	if clock != null and clock.has_method("update"):
		clock.update(p_delta)
	# 2) 再让 A 端推进：状态更新、动作判定、补救、灯更新都在这一句内部。
	p_runtime.tick(p_delta)
	_frame_count += 1

	# 3) 采连续状态。读的是 tick 之后的最终值——
	#    A 端把 lamp_controller.update() 放在 tick 最后一步，正是为此。
	var wrote: bool = _recorder.capture_states(p_runtime)
	# 4) 采离散事件。take_events() 取走即清空，因此每帧一次不多不少。
	_recorder.capture_events(p_runtime)

	_backwards_clock_count = int(_recorder.get_stats().get("backwards_clock_count", 0))

	# 5) 采完再判结束。顺序反过来会丢掉最后一帧：
	#    stage_end 事件、35 秒整点的末帧都产生在「runtime 刚变成 over」的那一帧，
	#    先判结束就等于把演出最后一份数据扔掉。
	if _is_over(p_runtime):
		finish()
		return 0
	return 1 if wrote else 0


## 演出结束。冻结记录并自检不变量。
##
## t_end_ms 来自 stage_end 事件的 song_time_ms，但对外一律以
## record.duration_ms 为准（CPerformanceRecord 类注释的时长口径）。
##
## **此处不调用 Recorder.release()**：finish 之后回放端才要把这份记录读走，
## 提前释放等于让回放拿不到数据。释放交给 discard()，由宿主在回放结束后决定。
func finish(p_t_end_ms: int = -1) -> void:
	if not _begun:
		push_error("CStageRecorder.finish: 尚未 begin()")
		return
	if _finished:
		return
	_finished = true
	_recorder.finish(p_t_end_ms)


## 主动丢弃本关记录。
##
## CPerformanceRecord 的生命周期是「一关开始时新建，离开本关即释放，
## 不写入长期存档」。因此回放播完、离开结果页时应调本方法释放，
## 而不是等到下一次 begin() 被覆盖。
func discard() -> void:
	_recorder.release()
	_record = null
	_begun = false
	_finished = false
	_frame_count = 0


## 取得本次演出的记录。**只读**：回放端读完即释放，不得回写。
## 未 begin() 时返回 null；已 discard() 后返回 null。
func get_record() -> Variant:
	if not _begun or _record == null:
		return null
	return _record


## 是否可以安全地进入回放。记录已收尾且不变量自检通过才为真。
##
## 这是给回放端的准入闸门：TECH_DESIGN 2.3 要求回放前跑一遍不变量，
## 带着已知错误开始回放，画面会稳定地错，比不回放更难排查。
func is_ready_for_replay() -> bool:
	if not _begun or not _finished or _record == null:
		return false
	return (_record.validate_invariants() as Array).is_empty()


## 不变量自检结果。空数组表示通过。回放前应由调用方跑一次。
func validate() -> Array:
	if not _begun or _record == null:
		return ["尚未 begin()，无记录可检"]
	return _record.validate_invariants()


## 供 HUD 与诊断显示的统计。不含任何推导值，全部来自记录自身。
func get_stats() -> Dictionary:
	if not _begun or _record == null:
		return {}
	var stats: Dictionary = _record.get_stats()
	stats["frame_count"] = _frame_count
	stats["backwards_clock_count"] = _backwards_clock_count
	stats["finished"] = _finished
	stats["snapshot_bytes_estimate"] = _estimate_size()
	return stats


## 粗估记录占用，供发现「35 秒约多少 KB」这类问题时有个量级参考。
## 只作诊断提示，不作为任何判断依据。
func _estimate_size() -> int:
	if _record == null:
		return 0
	return _record.snapshots.size() * 120 + _record.events.size() * 80


## A 端 is_over() 是可选接口：缺方法时视为未结束，
## 避免因数据源版本差异把一场演出提前冻住。
func _is_over(p_runtime: Variant) -> bool:
	if not p_runtime.has_method("is_over"):
		return false
	return bool(p_runtime.is_over())


## 是否已 begin。给外部宿主判断该不该调 advance。
func is_begun() -> bool:
	return _begun


## 是否已收尾。
func is_finished() -> bool:
	return _finished
