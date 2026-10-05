extends RefCounted
class_name ControlsHarness
## 把「时钟 + 输入读取 + 控制器」组装成一个与帧率无关的固定步长驱动器。
## 测试场景（图形实测）与无头行为测试共用同一段步进逻辑，
## 因此无头测试覆盖的行为就是玩家实际会触发的行为。

const PuppetControllerScript := preload("res://scripts/a/puppet_controller.gd")
const FrameClockScript := preload("res://scripts/a_test/frame_clock.gd")
const InputReaderScript := preload("res://scripts/a_test/input_reader.gd")

const FIXED_DELTA: float = 1.0 / 60.0
const MAX_STEPS_PER_FRAME: int = 8

var clock: FrameClock = null
var controller: PuppetController = null
var input_reader: InputReader = null
var paused: bool = false

var _accumulator: float = 0.0
var _step_count: int = 0
var _frame_events: Array[Dictionary] = []


func _init(puppet_count: int = 3) -> void:
	clock = FrameClockScript.new()
	controller = PuppetControllerScript.new()
	controller.clock = clock
	controller.setup(puppet_count)
	input_reader = InputReaderScript.new()
	input_reader.set_controller(controller)


## 固定步长推进。累积器上限防止长时间卡帧后出现「追帧风暴」。
## 返回本帧实际推进的步数；产生的事件保留在 _frame_events 中供判定系统消费。
func advance(frame_delta: float) -> int:
	if paused:
		return 0
	_accumulator += maxf(frame_delta, 0.0)
	var steps: int = 0
	_frame_events.clear()
	while _accumulator >= FIXED_DELTA and steps < MAX_STEPS_PER_FRAME:
		_accumulator -= FIXED_DELTA
		steps += 1
		_step_count += 1
		input_reader.poll_keys()
		clock.advance(FIXED_DELTA)
		controller.tick(FIXED_DELTA)
		_frame_events.append_array(controller.take_events())
	if steps >= MAX_STEPS_PER_FRAME:
		_accumulator = 0.0
	return steps


## 取走本帧由 advance() 产生、尚未被判定系统消费的控制器事件。
func take_frame_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_frame_events)
	_frame_events.clear()
	return out


## 直接步进固定数量的 tick，供测试精确控制帧数。
func step(steps: int = 1) -> void:
	for _i in maxi(steps, 0):
		_step_count += 1
		input_reader.poll_keys()
		clock.advance(FIXED_DELTA)
		controller.tick(FIXED_DELTA)


## 步进时保留调用方用 set_input_map() 注入的输入，不读真实键盘。
## 无头测试用它来模拟「玩家正按住某几个键」；图形场景永远走 step()。
func step_scripted(steps: int = 1) -> void:
	for _i in maxi(steps, 0):
		_step_count += 1
		clock.advance(FIXED_DELTA)
		controller.tick(FIXED_DELTA)


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


func get_step_count() -> int:
	return _step_count


func reset() -> void:
	_accumulator = 0.0
	_step_count = 0
	clock.reset()
	controller.setup(controller.puppets.size())
