extends RefCounted
class_name Level1Harness
## 第一关 A 侧图形场景宿主：音频时钟、输入轮询与 Level1Runtime 的固定步长接线。

const MusicClockScript := preload("res://scripts/a/music_clock.gd")
const MetronomeScript := preload("res://scripts/a_test/metronome.gd")
const Level1RuntimeScript := preload("res://scripts/a/level1_runtime.gd")
const InputReaderScript := preload("res://scripts/a_test/input_reader.gd")
const LampInputReaderScript := preload("res://scripts/a_test/lamp_input_reader.gd")

const FIXED_DELTA: float = 1.0 / 60.0
const MAX_STEPS_PER_FRAME: int = 8

var clock: MusicClock = null
var metronome: Metronome = null
var runtime: Object = null
var puppet_input: InputReader = null
var lamp_input: LampInputReader = null
var metronome_enabled: bool = true
var paused: bool = false
var opera_audio: Act1OperaAudio = null
var opera_flow: Act1OperaFlow = null

var _accumulator: float = 0.0
var _events: Array[Dictionary] = []
var _parent: Node = null
var _sequence: int = 0


func _init(parent: Node, stage_def: StageDef = null, audio_config: Dictionary = {}) -> void:
	_parent = parent
	var def: StageDef = stage_def if stage_def != null else StageDef.make_level1()
	metronome = MetronomeScript.new()
	metronome.name = "Level1Metronome"
	parent.add_child(metronome)
	clock = MusicClockScript.new()
	if audio_config.is_empty():
		metronome.setup(clock)
		clock.set_player(metronome.get_player(), def.bpm)
	runtime = Level1RuntimeScript.new()
	if not runtime.setup(clock, def.id, def):
		push_error("Level1Harness：Level1Runtime 建立失败")
		runtime = null
		return
	if not audio_config.is_empty():
		metronome_enabled = false
		opera_flow = Act1OperaFlow.new()
		if not opera_flow.setup(audio_config, clock, runtime.director.umbrella):
			push_error("第一幕剧情与音源配置建立失败")
			runtime = null
			return
		opera_flow.start()
		runtime.director.opera = opera_flow
		opera_audio = Act1OperaAudio.new()
		parent.add_child(opera_audio)
		if not opera_audio.setup(audio_config, clock, opera_flow):
			push_error("第一幕正式音频建立失败：%s" % opera_audio.problems)
			runtime = null
			return
		clock.set_player(opera_audio.get_player(), def.bpm)
	clock.start()
	runtime.start()
	_queue_events(runtime.take_events())
	puppet_input = InputReaderScript.new()
	puppet_input.set_controller(runtime.puppet_controller)
	lamp_input = LampInputReaderScript.new()
	lamp_input.set_lamp(runtime.lamp_controller)


func advance(frame_delta: float) -> void:
	if paused or runtime == null or runtime.is_over():
		return
	_accumulator += maxf(frame_delta, 0.0)
	var steps: int = 0
	while _accumulator >= FIXED_DELTA and steps < MAX_STEPS_PER_FRAME:
		_accumulator -= FIXED_DELTA
		steps += 1
		_step(FIXED_DELTA)
	if steps >= MAX_STEPS_PER_FRAME:
		_accumulator = 0.0


func advance_steps(steps: int) -> void:
	for _i in maxi(steps, 0):
		if runtime == null or runtime.is_over():
			return
		_step(FIXED_DELTA)


func _step(delta: float) -> void:
	if metronome_enabled:
		metronome.update()
	clock.update(delta)
	puppet_input.poll_keys()
	lamp_input.poll_keys()
	runtime.tick(delta)
	var events: Array[Dictionary] = runtime.take_events()
	if opera_audio != null:
		opera_audio.update(events, delta)
		events.append_array(opera_audio.take_events())
	_queue_events(events)
	if runtime.is_over():
		metronome.stop()
		if opera_audio != null:
			opera_audio.stop()


func take_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_events)
	_events.clear()
	return out


func handle_input(event: InputEvent) -> bool:
	if paused or puppet_input == null or lamp_input == null:
		return false
	var consumed: bool = puppet_input.handle_event(event)
	lamp_input.handle_event(event)
	return consumed


func set_paused(value: bool) -> void:
	if paused == value or runtime == null or runtime.is_over():
		return
	paused = value
	puppet_input.set_enabled(not value)
	lamp_input.set_enabled(not value)
	runtime.set_paused(value)
	if opera_audio != null:
		opera_audio.update()


func shutdown() -> void:
	if opera_audio != null:
		opera_audio.stop()
	if metronome != null:
		metronome.stop()
	if clock != null:
		# 先解冻补救、再解除暂停：冻结状态下 stream_paused 会让 stream 换不干净
		if clock.is_song_frozen():
			clock.set_song_frozen(false)
		if clock.is_paused():
			clock.resume()
		clock.set_player(null, clock.bpm)


func _queue_events(events: Array) -> void:
	for source: Dictionary in events:
		var event := source.duplicate(true)
		event.payload["real_time_ms"] = clock.get_real_time_ms()
		event.payload["sequence"] = _sequence
		_sequence += 1
		_events.append(event)
