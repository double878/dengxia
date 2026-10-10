extends RefCounted
class_name StageDirector
## A 范围的第一关推进与结束判定。
##
## 职责边界：只管「演出时间轴」这一件事——把判定系统、补救系统与关卡时长串起来，
## 并保证：
## - 有补救窗口开着时**冻结歌曲时间轴**（时钟只冻结歌曲时间，真实时间照走），
##   于是 8 秒补救按真实时间计、而关卡固定的 35 秒一分不少；
## - 8 秒到期仍未完成时演出继续，不重播、不失败；
## - 到 35 秒按时结束，绝不延长、绝不重播；未到期的窗口随演出结束关闭。
##
## 输出事件：stage_start {duration_ms}、stage_end {reason, song_time_ms, remedy_open_count}，
## 以及 remedy_freeze_begin / remedy_freeze_end（冻结区间起止，供 B 提示、C 记录回放节奏）。
## 编排顺序固定为：先 detect_misses（判定落点是否已过）→ 再 remedy.update（开窗/结算）
## → 再按窗口同步冻结 → 最后判断关卡是否到时。这样「落点刚过」与「窗口刚开」在同一帧内一次完成。

const PerformanceSystemScript := preload("res://scripts/a/performance_system.gd")
const RemedySystemScript := preload("res://scripts/a/remedy_system.gd")
const UmbrellaControllerScript := preload("res://scripts/a/umbrella_controller.gd")

const END_REASON_DURATION: String = "duration_reached"   ## 正常到时结束
const END_REASON_FORCED: String = "forced"               ## 外部要求立即结束（如跳过）
## 补救冻结的起止事件。回放必须靠它还原「这一段真实时间不计入歌曲时间」，
## 否则 1:1 回放会比重看演出的实际耗时要短（TECH_DESIGN.md 第 4 节）。
const KIND_FREEZE_BEGIN: String = "remedy_freeze_begin"
const KIND_FREEZE_END: String = "remedy_freeze_end"

var stage_def: StageDef = null
var clock: Object = null                ## 鸭子类型：get_song_time_ms() -> int
var performance: PerformanceSystem = null
var remedy: RemedySystem = null
## 第一关「借伞还伞」状态机。**其它关卡为 null**（流程表只定义第一关）：
## `UmbrellaController.setup()` 在非第一关返回 false，这里据此把引用置空，
## 于是「本关有没有伞」在显示端只需判一个 null，不必各自去查 stage_id。
var umbrella: UmbrellaController = null
var opera: Act1OperaFlow = null

var started: bool = false
var ended: bool = false
var end_reason: String = ""

var _events: Array[Dictionary] = []
var _end_ms: int = -1
var _remedy_frozen: bool = false         ## 当前是否因补救窗口而冻结歌曲时间轴
var _frozen_since_real_ms: int = -1      ## 本次冻结开始时的真实时间


## 建立第一关的演出：判定系统与补救系统共用同一个时钟与同一批 Cue。
## p_lamp 是灯位/倾灯类 Cue 的读数来源；第 1、2 关没有这类落点，允许传 null。
func setup(p_stage_def: StageDef, p_clock: Object, p_puppets: Array,
		p_lamp: LampState = null) -> void:
	stage_def = p_stage_def
	clock = p_clock
	performance = PerformanceSystemScript.new()
	performance.setup(stage_def.cues, clock, p_puppets, p_lamp)
	umbrella = UmbrellaControllerScript.new()
	umbrella.clock = clock
	if not umbrella.setup(stage_def, p_puppets):
		umbrella = null
	remedy = RemedySystemScript.new()
	remedy.setup(stage_def.cues, clock)
	started = false
	ended = false
	end_reason = ""
	_events.clear()
	_end_ms = -1
	_remedy_frozen = false
	_frozen_since_real_ms = -1


func start() -> void:
	if started:
		return
	started = true
	_events.append({
		"time_ms": song_time_ms(),
		"kind": "stage_start",
		"object_id": 0,
		"cue_id": "",
		"payload": {"kind": "stage_start", "duration_ms": duration_ms()},
	})


## 每帧一次。必须在 PuppetController.tick() 之后调用。
## 事件按「判定 → 补救 → 结束」的顺序并进同一个队列，调用方只读一次。
func update(controller_events: Array) -> void:
	if not started or ended:
		return
	if opera != null:
		opera.before_update()
	var now_ms: int = song_time_ms()
	var now_real_ms: int = real_time_ms()
	# 借伞还伞先走：它只读影人状态，交接在同一帧产生 umbrella_take / umbrella_return 事件。
	# 交接事件**不再混回判定系统的常规事件流**：常规事件流里每一条都会先被
	# `_evaluate_action_event` 当成一次状态切换动作、随后又被 `_evaluate_continuous`
	# 当成「本帧的影子状态」再评估一遍，而伞的交接事件两件事都不是——
	# 混进去会让它在 5 秒前的拖动帧里就把「走到最左边」判掉。
	# 因此交接事件走 `_register_action` 这个单一入口直接登记（`cue_fire` / `cue_hit` /
	# `cue_miss` 的产出与常规动作完全一致），其余判定仍只看操控事件。
	var umbrella_events: Array = []
	if umbrella != null:
		umbrella.update(now_ms, controller_events)
		umbrella_events.append_array(umbrella.take_events())
		_events.append_array(umbrella_events)
	if opera != null:
		opera.after_update(umbrella_events)
		_events.append_array(opera.take_events())
		now_ms = song_time_ms()
	performance.update(now_ms, controller_events)
	_events.append_array(performance.take_events())
	for umbrella_event in umbrella_events:
		if umbrella_event is Dictionary:
			performance.register_external_action(now_ms, umbrella_event as Dictionary)
	_events.append_array(performance.take_events())
	performance.detect_misses(now_ms)
	_events.append_array(performance.take_events())
	remedy.update(now_ms, now_real_ms, performance, false)
	_events.append_array(remedy.take_events())
	_sync_remedy_freeze(now_ms, now_real_ms)
	if now_ms >= duration_ms():
		_finish(END_REASON_DURATION, now_ms)


## 立即结束（例如玩家选择跳过）。仍走同一套收尾，不重播。
func force_end() -> void:
	if ended:
		return
	_finish(END_REASON_FORCED, song_time_ms())


func is_over() -> bool:
	return ended


func duration_ms() -> int:
	return stage_def.duration_ms if stage_def != null else 0


## 本关剩余时间（毫秒），到点后为 0。
func remaining_ms() -> int:
	if ended:
		return 0
	return maxi(duration_ms() - song_time_ms(), 0)


func progress() -> float:
	if duration_ms() <= 0:
		return 0.0
	return clampf(float(song_time_ms()) / float(duration_ms()), 0.0, 1.0)


func take_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_events)
	_events.clear()
	return out


func song_time_ms() -> int:
	return int(clock.get_song_time_ms()) if clock != null else 0


## 真实时间读数。补救窗口按真实时间计时，因此歌曲时间被冻结时这里仍要能读到推进。
## 鸭子类型时钟没有这个方法时退回歌曲时间——那种自由计时的测试时钟两者本就同步。
func real_time_ms() -> int:
	if clock != null and clock.has_method("get_real_time_ms"):
		return int(clock.call("get_real_time_ms"))
	return song_time_ms()


## 是否正因补救窗口开着而冻结歌曲时间轴。
func is_remedy_frozen() -> bool:
	return _remedy_frozen


## 按「有没有补救窗口开着」同步时钟的冻结状态，并在翻转时对外发事件。
## 反复调用同值不做任何事，因此每帧直接调即可。
func _sync_remedy_freeze(song_ms: int, real_ms: int) -> void:
	var want: bool = remedy.has_open_windows()
	if clock != null and clock.has_method("set_song_frozen"):
		clock.call("set_song_frozen", want or (opera != null and opera.is_waiting()))
	if want == _remedy_frozen:
		return
	_remedy_frozen = want
	if want:
		_frozen_since_real_ms = real_ms
		_emit_event(song_ms, KIND_FREEZE_BEGIN, {
			"reason": "remedy",
			"open_windows": remedy.open_count(),
			"real_time_ms": real_ms,
		})
		return
	var frozen_ms: int = maxi(real_ms - _frozen_since_real_ms, 0) \
		if _frozen_since_real_ms >= 0 else 0
	_frozen_since_real_ms = -1
	_emit_event(song_ms, KIND_FREEZE_END, {
		"reason": "remedy",
		"frozen_ms": frozen_ms,
		"real_time_ms": real_ms,
	})


func _finish(reason: String, now_ms: int) -> void:
	ended = true
	end_reason = reason
	_end_ms = now_ms
	# 窗口随演出结束关闭，随后解冻时间轴（已收场，解冻只是让时钟状态干净）
	var open_before: int = remedy.open_count()
	remedy.update(now_ms, real_time_ms(), performance, true)
	_events.append_array(remedy.take_events())
	_sync_remedy_freeze(now_ms, real_time_ms())
	var still_open: int = remedy.open_count()
	if still_open > 0:
		push_error("关卡结束时仍有 %d 个补救窗口未关闭" % still_open)
	_emit_event(now_ms, "stage_end", {
		"reason": reason,
		"song_time_ms": now_ms,
		"remedy_open_count": open_before,
		"duration_ms": duration_ms(),
	})


func _emit_event(time_ms: int, kind: String, payload_extra: Dictionary) -> void:
	var payload := {"kind": kind}
	payload.merge(payload_extra, true)
	_events.append({
		"time_ms": time_ms,
		"kind": kind,
		"object_id": 0,
		"cue_id": "",
		"payload": payload,
	})
