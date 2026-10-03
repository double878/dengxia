extends RefCounted
class_name CueTestBench
## 切片 3 的测试台：时钟 + 操控器 + 判定系统的固定步长驱动器。
##
## 时间由测试注入，因此每个落点的判定窗边界都是精确可断言的，不依赖真实帧率或音频设备。
## 只使用全局类名（MusicClock / StageDef / ...）构造依赖，
## 避免在 _init 阶段使用脚本资源常量的解析顺序问题。

const STEP_MS: int = 10
const STEP_S: float = 0.01
const STAGE_W: float = 1920.0
const STAGE_H: float = 1080.0

var clock: MusicClock = null
var controller: PuppetController = null
var performance: PerformanceSystem = null
var stage_def: StageDef = null
var time_ms: int = 0
var controller_log: Array = []        ## 控制器事件日志（drag_* / pose_* / hand_* / facing_*）
var judge_log: Array = []             ## 判定事件日志（cue_*）


func _init() -> void:
	stage_def = StageDef.make_level1()
	clock = MusicClock.new()
	clock.set_player(null, stage_def.bpm)
	clock.start()
	controller = PuppetController.new()
	controller.clock = clock
	controller.setup(3)
	performance = PerformanceSystem.new()
	performance.setup(stage_def.cues, clock, controller.puppets)


func state() -> PuppetState:
	return controller.get_controlled()


func chest_tag() -> Vector2:
	var s: PuppetState = state()
	return Vector2(s.stage_pos.x * STAGE_W,
		s.stage_pos.y * STAGE_H - PuppetController.CHEST_TAG_RADIUS_PX * 0.5)


## 推进 steps 步。每步：推进时钟（并取回它的读数）→ tick 控制器 → 把控制器事件喂给判定系统。
## 控制器事件的时间戳取自时钟，因此判定用的歌曲时间与事件时间戳始终同源。
func advance(steps: int, input_map: Dictionary = {}) -> void:
	if not input_map.is_empty():
		controller.set_input_map(input_map)
	for _i in maxi(steps, 0):
		clock.update(STEP_S)
		time_ms = clock.get_song_time_ms()
		controller.tick(STEP_S)
		var events: Array[Dictionary] = controller.take_events()
		controller_log.append_array(events)
		performance.update(time_ms, events)
		judge_log.append_array(performance.take_events())


## 把时钟推进到 target_ms（不产生任何动作），不早于当前时间。
func advance_to(target_ms: int) -> void:
	var steps: int = int(maxf(float(target_ms - time_ms) / float(STEP_MS), 0.0))
	advance(steps)


## 开始拖动。不额外步进：位移在随后的 drag() 步里累积，
## 否则「开始」与「移动」会被拆到两次 tick，累计位移被清零，姿势推不到位。
func begin_drag() -> void:
	controller.begin_drag(0, chest_tag())


func drag(delta: Vector2, steps: int) -> void:
	for _i in maxi(steps, 0):
		controller.drag_to(delta)
		advance(1)


func end_drag() -> void:
	controller.end_drag()
	advance(1)


## 持续拖动直到 predicate 成立或达到步数上限，返回实际用了多少步。
func drag_until(delta: Vector2, predicate: Callable, max_steps: int) -> int:
	var used: int = 0
	while used < max_steps:
		controller.drag_to(delta)
		advance(1)
		used += 1
		if predicate.call():
			break
	return used


func find_cue(cue_id: String) -> Dictionary:
	for cue in stage_def.cues:
		if str(cue.get("cue_id", "")) == cue_id:
			return cue
	return {}


func cues_of_kind(kind: String) -> Array:
	var out: Array = []
	for e in judge_log:
		if str(e.get("kind", "")) == kind:
			out.append(e)
	return out


func kinds_of(log: Array) -> Array[String]:
	var out: Array[String] = []
	for e in log:
		out.append(str(e.get("kind", "")))
	return out
