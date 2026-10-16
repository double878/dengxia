extends RefCounted
class_name Act1OperaFlow
## 只读唯一双时钟和真实道具交接；不播放声音、不代演。
##
## 🔴 2026-10-16 用户定案：本关流程 = 「唱段听完 → 提示借伞 → 接到伞 → 走回小青身旁 → 结束」。
##   还伞与「游湖对白」两段随之退役，锚点表也一并瘦身（见 `setup()`）。

const WAIT_LIMIT_MS := 8000
var config: Dictionary = {}
var clock: MusicClock
var umbrella: UmbrellaController
var phase: String = "opening"
var taken: bool = false
var _arrived: bool = false
var _deadline_ms: int = -1
var _events: Array[Dictionary] = []


## 锚点表必须**严格递增**，否则时间表自相矛盾（舞台段落表与服务端记录都按它切分）。
## 五条锚点的含义（与 `Act1OperaStage.make_stage` 的段界、score.json 一一对应）：
##   opening_end_ms  唱段（含全部字幕）结束 → 从这里起**提示玩家借伞**
##   arrival_ms      她本该走进交接窗口的时刻；到点还没进去就冻住歌曲时钟等她（最多 WAIT_LIMIT_MS）
##   take_ms         她本该接到伞的时刻（舞台段落表的「接伞」段起点）
##   closing_ms      收势/收场点；她一旦走回小青身旁就直接跳到这里
##   duration_ms     整轨长度（主轨 WAV 必须正好这么长，见 Act1OperaAudio.setup）
func setup(value: Dictionary, p_clock: MusicClock, p_umbrella: UmbrellaController) -> bool:
	var previous := -1
	for key in [
		"opening_end_ms",
		"arrival_ms",
		"take_ms",
		"closing_ms",
		"duration_ms"
	]:
		var point := int(value.get(key, -1))
		if point <= previous:
			push_error("第一幕音频时间表非法：%s=%d" % [key, point])
			return false
		previous = point
	if p_clock == null or p_umbrella == null or str(value.get("audio_version", "")).is_empty():
		return false
	config = value.duplicate(true)
	clock = p_clock
	umbrella = p_umbrella
	return true


func start() -> void:
	phase = ""
	taken = false
	_arrived = false
	_deadline_ms = -1
	_events.clear()
	umbrella.take_allowed = false
	_set_phase("opening", "start")


## 每帧推进。三条出路，按优先级：
##   ① 歌曲时间到了 closing_ms（或收场）→ closing；
##   ② 唱段未结束 → opening（玩家不操作）；
##   ③ 已接伞且她走回小青身旁 → closing（**操作完成即结束**）。
func before_update() -> void:
	if clock.is_paused():
		return
	if is_waiting():
		if clock.get_real_time_ms() >= _deadline_ms:
			_timeout()
		elif phase == "wait_arrival" and umbrella.in_join_window():
			_arrived = true
			_end_wait("arrived", "borrow")
		return
	var now := clock.get_song_time_ms()
	if now >= int(config.closing_ms):
		_set_phase("closing", "timeline")
		return
	if phase == "closing":
		return
	if now < int(config.opening_end_ms):
		# 唱段（带字幕）——玩家不操作，跟着听即可。
		_set_phase("opening", "timeline")
		return
	# —— 唱段收尾：「如此 多谢君子」唱完，从这里起提示玩家借伞 ——
	umbrella.take_allowed = true
	if not taken:
		_set_phase("borrow", "timeline")
		# 到 arrival_ms 还没走进交接窗口 → 冻住歌曲时钟等她（最多 WAIT_LIMIT_MS）
		if now >= int(config.arrival_ms) and not umbrella.in_join_window():
			_begin_wait("wait_arrival")
		return
	# —— 已接到伞：等她走回小青身旁。到了即收关（用户 2026-10-16：「操作完成即结束」）——
	umbrella.take_allowed = false
	if umbrella.is_at_home():
		_set_phase("closing", "home")
		clock.advance_to_ms(int(config.closing_ms))
		return
	_set_phase("return_home", "timeline")


func after_update(events: Array) -> void:
	if clock.is_paused():
		return
	for event in events:
		match str(event.get("kind", "")):
			"umbrella_take":
				if taken:
					continue
				taken = true
				umbrella.take_allowed = false
				_emit("opera_take_close", {"asset_id": "take_close", "phase_id": "borrow"})
				_end_wait("taken", "return_home")


func is_waiting() -> bool:
	return phase.begins_with("wait_")


func take_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


func _begin_wait(value: String) -> void:
	_deadline_ms = clock.get_real_time_ms() + WAIT_LIMIT_MS
	_set_phase(value, "condition_pending")
	clock.set_song_frozen(true)
	_emit(
		"opera_wait_begin",
		{"phase_id": value, "deadline_real_ms": _deadline_ms, "asset_id": "wait_loop"}
	)


func _end_wait(reason: String, next: String) -> void:
	if is_waiting():
		_emit(
			"opera_wait_end",
			{
				"phase_id": phase,
				"reason": reason,
				"wait_ms": WAIT_LIMIT_MS - maxi(_deadline_ms - clock.get_real_time_ms(), 0)
			}
		)
	_deadline_ms = -1
	_set_phase(next, reason)
	clock.set_song_frozen(false)


func _timeout() -> void:
	var from := clock.get_song_time_ms()
	_end_wait("timeout", "closing")
	umbrella.take_allowed = false
	clock.advance_to_ms(int(config.closing_ms))
	_emit(
		"opera_score_skipped",
		{
			"from_ms": from,
			"to_ms": int(config.closing_ms),
			"reason": "timeout",
			"phase_id": "closing",
			"asset_id": "main"
		}
	)


func _set_phase(value: String, reason: String) -> void:
	if phase == value:
		return
	phase = value
	_emit("opera_phase_changed", {"phase_id": value, "reason": reason, "asset_id": "main"})


func _emit(kind: String, data: Dictionary) -> void:
	data.merge(
		{
			"real_time_ms": clock.get_real_time_ms(),
			"audio_version": config.audio_version,
			"stage_id": 1
		},
		true
	)
	_events.append(
		{
			"time_ms": clock.get_song_time_ms(),
			"kind": kind,
			"object_id": "performance_audio",
			"cue_id": "",
			"payload": data
		}
	)
