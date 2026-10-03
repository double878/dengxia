extends RefCounted
class_name LampHarness
## 把「统一音乐时钟 + 输入读取 + 油灯控制器 + 临时节拍音」组装成一个
## 与帧率无关的固定步长驱动器。
##
## 图形测试场景与探针共用同一段步进逻辑；无头测试另有 LampTestBench 用注入时间，
## 两者都只经由 LampController 的公开接口，因此覆盖的是同一套行为。

const MusicClockScript := preload("res://scripts/a/music_clock.gd")
const LampControllerScript := preload("res://scripts/a/lamp_controller.gd")
const LampInputReaderScript := preload("res://scripts/a_test/lamp_input_reader.gd")
const MetronomeScript := preload("res://scripts/a_test/metronome.gd")

const FIXED_DELTA: float = 1.0 / 60.0

var clock: MusicClock = null
var lamp: LampController = null
var input_reader: LampInputReader = null
var metronome: Metronome = null
var metronome_enabled: bool = true
var paused: bool = false
var step_count: int = 0

var _events: Array[Dictionary] = []      ## 本帧产出的油灯事件，供接收端消费
var _parent: Node = null


func _init(parent: Node, bpm: float) -> void:
	_parent = parent
	metronome = MetronomeScript.new()
	metronome.name = "LampMetronome"
	parent.add_child(metronome)
	clock = MusicClockScript.new()
	metronome.setup(clock)
	# 先设播放器再 start()：start() 会从 0 播放并重置时间轴
	clock.set_player(metronome.get_player(), bpm)
	clock.start()

	lamp = LampControllerScript.new()
	lamp.clock = clock
	lamp.setup()

	input_reader = LampInputReaderScript.new()
	input_reader.set_lamp(lamp)


## 每帧一次。累积器上限防止长时间卡帧后出现「追帧风暴」。
func advance(frame_delta: float) -> void:
	if paused:
		return
	var remaining: float = maxf(frame_delta, 0.0)
	while remaining > 0.0:
		var step: float = minf(FIXED_DELTA, remaining)
		remaining -= step
		_step(step)


## 推进一个固定步：驱动节拍音与时钟，读输入，再让油灯更新。
func _step(delta: float) -> void:
	step_count += 1
	if metronome_enabled:
		metronome.update()
	clock.update(delta)
	input_reader.poll_keys()
	_events.append_array(lamp.update(delta, []))


## 收走本帧的油灯事件。
func take_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_events)
	_events.clear()
	return out


## 直接注入一个表现事件（命中/错拍演示）：只驱动 flame_feedback，不推进歌曲时间。
func inject_performance_event(kind: String, cue_id: String) -> void:
	_events.append_array(lamp.update(0.0, [{
		"time_ms": clock.get_song_time_ms(),
		"kind": kind,
		"object_id": 0,
		"cue_id": cue_id,
		"payload": {"kind": kind},
	}]))


func set_paused(value: bool) -> void:
	if paused == value:
		return
	if value:
		input_reader.set_enabled(false)
	paused = value
	if value:
		clock.pause()
	else:
		clock.resume()
		input_reader.set_enabled(true)


func finish_show() -> void:
	lamp.finish_show()
	_events.append_array(lamp.take_events())


## 退出前有序收尾：先停音频播放、断开时钟与播放器的引用，再退出。
## 否则音频线程可能仍持有生成器播放缓冲，导致退出时报
## 「ObjectDB instance was leaked」甚至偶发访问违例。
func shutdown() -> void:
	if metronome != null:
		metronome.stop()
	if clock != null:
		if clock.is_paused():
			clock.resume()
		clock.set_player(null, clock.bpm)
