extends RefCounted
class_name LampTestBench
## 切片 5 的测试台：统一时钟 + 油灯控制器的固定步长驱动器。
##
## 歌曲时间由测试显式注入（MusicClock 的自由计时 + set_free_time_ms），
## 因此灯油消耗的每一毫秒、同刻重复更新、时间倒退都可精确断言，
## 不依赖真实帧率、音频设备或墙钟。
##
## 输入约定：`advance_ms(ms)` 不改变当前输入；`advance_ms(ms, map)` 会把输入快照
## 设为 map（传 {} 即「全部松开」）。这样「按住 → 松开」可以被明确表达。
##
## 只使用全局类名构造依赖，避免在 _init 阶段使用脚本资源常量的解析顺序问题。

const STEP_MS: int = 10
const STEP_S: float = 0.01

var clock: MusicClock = null
var lamp: LampController = null
var time_ms: int = 0
var log: Array = []                    ## 油灯 controller 产出的全部事件


func _init() -> void:
	clock = MusicClock.new()
	clock.set_player(null, StageDef.LEVEL1_BPM)
	clock.start()
	lamp = LampController.new()
	lamp.clock = clock
	lamp.setup()
	time_ms = 0
	clock.set_free_time_ms(0)


func state() -> LampState:
	return lamp.lamp


## 设置输入快照。传 {} 表示全部松开。
func set_input(input_map: Dictionary) -> void:
	lamp.set_input_map(input_map)


## 全部松开：把输入快照设为空。
func release_input() -> void:
	lamp.set_input_map({})


## 推进 ms 毫秒歌曲时间。不改变当前输入（用 set_input / release_input 明确表达）。
## 不足一步的余数按一步处理，保证「推进 1 ms」也能产生一次更新。
func advance_ms(ms: int = 0) -> void:
	var steps: int = maxi(int(maxf(float(ms) / float(STEP_MS), 0.0)), 1)
	for _i in steps:
		_set_song_ms(time_ms + STEP_MS)
		_collect(lamp.update(STEP_S, []))
	_collect(lamp.take_events())        ## 收走 update 之外产生的事件（如 lamp_finished）


## 设置输入快照并推进 ms 毫秒。
func advance_with_input(ms: int, input_map: Dictionary) -> void:
	lamp.set_input_map(input_map)
	advance_ms(ms)


## 保持当前输入快照并推进 ms 毫秒；给了 input_map 就先把它设为当前输入。
## 这是「按住某几个键一段时间」的读写法。
func hold_input(ms: int = 0, input_map: Dictionary = {}) -> void:
	if not input_map.is_empty():
		lamp.set_input_map(input_map)
	advance_ms(ms)


## 只推进歌曲时间，不改变当前输入。
func idle_ms(ms: int) -> void:
	advance_ms(ms)


## 保持当前输入，只推进歌曲时间（可读写法）。
func hold_ms(ms: int) -> void:
	advance_ms(ms)


## 在同一歌曲时间上重复更新 steps 次，用于验证「同刻不重复扣油」。不改变输入。
func repeat_update_at_same_time(steps: int) -> void:
	for _i in maxi(steps, 1):
		_collect(lamp.update(STEP_S, []))


## 以 delta 推进一帧，但不改变歌曲时间。用于验证「输入本身不改动 oil」。
func tick(delta: float = STEP_S) -> void:
	_collect(lamp.update(delta, []))


## 把 performance 事件喂给油灯，用来驱动 flame_feedback。不推进歌曲时间。
func feed_performance(events: Array) -> void:
	_collect(lamp.update(STEP_S, events))


## 直接设定歌曲时间（不推进），用于验证倒退。
func set_song_ms(value_ms: int) -> void:
	time_ms = maxi(value_ms, 0)
	clock.set_free_time_ms(time_ms)


func pause() -> void:
	clock.pause()


func resume() -> void:
	clock.resume()


## 结束演出，并收走它产生的事件。
func finish_show() -> void:
	lamp.finish_show()
	_collect(lamp.take_events())


func last_event() -> Dictionary:
	if log.is_empty():
		return {}
	return log[log.size() - 1]


func events_of(kind: String) -> Array:
	var out: Array = []
	for e in log:
		if str(e.get("kind", "")) == kind:
			out.append(e)
	return out


func has_event(kind: String) -> bool:
	return events_of(kind).size() > 0


func clear_log() -> void:
	log.clear()


func _set_song_ms(value_ms: int) -> void:
	time_ms = maxi(value_ms, 0)
	clock.set_free_time_ms(time_ms)


func _collect(events: Array) -> void:
	log.append_array(events)
