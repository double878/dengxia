extends RefCounted
class_name DirectorTestBench
## 切片 4 的测试台：关卡导演（判定 + 补救 + 结束）的固定步长驱动器。
##
## 时间由本测试台推进自由计时时钟，因此补救倒计时的每一毫秒都可精确断言，
## 不依赖真实帧率或音频设备。

const STEP_MS: int = 10
const STEP_S: float = 0.01
const STAGE_W: float = 1920.0
const STAGE_H: float = 1080.0

var clock: MusicClock = null
var controller: PuppetController = null
var director: StageDirector = null
var stage_def: StageDef = null
var time_ms: int = 0
var paused: bool = false
var director_log: Array = []          ## stage_* / remedy_* / cue_* 全部事件


func _init(custom_stage_def: StageDef = null) -> void:
	stage_def = custom_stage_def if custom_stage_def != null else StageDef.make_level1()
	clock = MusicClock.new()
	clock.set_player(null, stage_def.bpm)
	clock.start()
	controller = PuppetController.new()
	controller.clock = clock
	controller.setup(3)
	director = StageDirector.new()
	director.setup(stage_def, clock, controller.puppets)
	director.start()


func state() -> PuppetState:
	return controller.get_controlled()


func chest_tag() -> Vector2:
	var s: PuppetState = state()
	return Vector2(s.stage_pos.x * STAGE_W,
		s.stage_pos.y * STAGE_H - PuppetController.CHEST_TAG_RADIUS_PX * 0.5)


## 推进 steps 步。每步：推进时钟 → tick 控制器 → 把事件交给关卡导演。
## 注意：补救窗口开着时歌曲时间是冻结的，因此这段时间里 advance() 只推进真实时间。
func advance(steps: int, input_map: Dictionary = {}) -> void:
	if not input_map.is_empty():
		controller.set_input_map(input_map)
	for _i in maxi(steps, 0):
		if director.is_over():
			return
		clock.update(STEP_S)
		time_ms = clock.get_song_time_ms()
		var events: Array[Dictionary] = []
		if not paused:
			controller.tick(STEP_S)
			events = controller.take_events()
		director.update(events)
		director_log.append_array(director.take_events())


## 按**歌曲时间**推进到 target_ms。只在没有补救窗口开着时能真正到达目标；
## 补救冻结期间歌曲时间不前进，因此这时应该改用 advance() 按真实时间推进。
func advance_to(target_ms: int) -> void:
	var steps: int = int(maxf(float(target_ms - time_ms) / float(STEP_MS), 0.0))
	advance(steps)


## 一直推进到关卡结束。补救会冻结歌曲时间，所以真实步数会明显多于 35 秒；
## max_steps 是防呆上限（默认 20000 步 = 200 秒真实时间）。
## 返回实际用掉的步数，供测试断言「补救确实拉长了真实耗时」。
func run_to_end(max_steps: int = 20000) -> int:
	var steps: int = 0
	while not director.is_over() and steps < max_steps:
		advance(1)
		steps += 1
	return steps


## 按**真实时间**推进 ms 毫秒。补救冻结期间歌曲时间不动，只能这样推进，
## 也正是 8 秒补救窗口的计时依据。
func advance_real(ms: int) -> void:
	advance(int(ceil(float(ms) / float(STEP_MS))))


## 当前真实时间（毫秒）。补救窗口按真实时间倒计时。
func real_ms() -> int:
	return clock.get_real_time_ms()


## 暂停：时钟与操控一起冻结，与真实游戏一致（由 MusicClock.pause 负责）。
func set_paused(value: bool) -> void:
	paused = value
	if value:
		clock.pause()
	else:
		clock.resume()


func begin_drag() -> void:
	controller.begin_drag(0, chest_tag())


func drag(delta: Vector2, steps: int) -> void:
	for _i in maxi(steps, 0):
		controller.drag_to(delta)
		advance(1)


func end_drag() -> void:
	controller.end_drag()
	advance(1)


## 立即结束本关（例如玩家选择跳过），并把收尾事件收进日志。
## 必须走这个入口而不是直接调 director.force_end()：后者产生的事件不会被收进 director_log。
func force_end() -> void:
	director.force_end()
	director_log.append_array(director.take_events())


func find_cue(cue_id: String) -> Dictionary:
	for cue in stage_def.cues:
		if str(cue.get("cue_id", "")) == cue_id:
			return cue
	return {}


func events_of(kind: String) -> Array:
	var out: Array = []
	for e in director_log:
		if str(e.get("kind", "")) == kind:
			out.append(e)
	return out


func events_for(kind: String, cue_id: String) -> Array:
	var out: Array = []
	for e in director_log:
		if str(e.get("kind", "")) == kind and str(e.get("cue_id", "")) == cue_id:
			out.append(e)
	return out


func has_event(kind: String, cue_id: String = "") -> bool:
	if cue_id.is_empty():
		return events_of(kind).size() > 0
	return events_for(kind, cue_id).size() > 0


## 蹲到底
func crouch(at_ms: int) -> void:
	advance_to(at_ms)
	begin_drag()
	drag(Vector2(0.0, 120.0), 12)
	end_drag()


## 从蹲位起立到完全站姿（跨过站起范围上限 0.05）
func stand_up(step_px: float, steps: int) -> void:
	begin_drag()
	drag(Vector2(0.0, -step_px), steps)
	end_drag()
