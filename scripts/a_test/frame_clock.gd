extends RefCounted
class_name FrameClock
## 切片 1 的朴素整数毫秒时钟，仅满足 PuppetController 依赖的鸭子类型接口：
## get_song_time_ms() -> int。
## 切片 2 会被 MusicClock 替换；本类只存在于 A 的测试目录，不进正式目录。

var _time_ms: int = 0
var _paused: bool = false


func advance(delta_s: float) -> void:
	if _paused:
		return
	_time_ms += int(round(maxf(delta_s, 0.0) * 1000.0))


func get_song_time_ms() -> int:
	return _time_ms


func get_time_s() -> float:
	return float(_time_ms) / 1000.0


func set_time_ms(value: int) -> void:
	_time_ms = maxi(value, 0)


func pause() -> void:
	_paused = true


func resume() -> void:
	_paused = false


func is_paused() -> bool:
	return _paused


func reset() -> void:
	_time_ms = 0
	_paused = false
