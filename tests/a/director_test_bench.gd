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
var lamp_controller: LampController = null
var director: StageDirector = null
var stage_def: StageDef = null
var time_ms: int = 0
var paused: bool = false
var director_log: Array = []          ## stage_* / remedy_* / cue_* 全部事件


## 按关卡数据的开演布景布置影人，与场景 `_configure_initial_stage` 同一口径：
## 起始受控、挂起分布、站位、手角与初始朝向。
## 第 2 关的「挂起/取回」判定依赖开局就有人挂在钩上、且留有一个空槽，
## 不摆布景的话这两条落点在本测试台下永远判不了。
func apply_initial_puppets() -> void:
	var positions: Dictionary = stage_def.initial.get("positions", {})
	var hand_angles: Dictionary = stage_def.initial.get("hand_angles", {})
	var hung: Dictionary = stage_def.initial.get("hung", {})
	var facing: Dictionary = stage_def.initial.get("facing", {})
	for state in controller.puppets:
		var puppet_id: int = state.puppet_id
		state.is_controlled = false
		state.hook_slot = PuppetState.HOOK_SLOT_NONE
		# 与场景同一口径：缺省 FACING_FRONT（+1，朝右），并把翻面过渡复位成「已停稳」。
		state.facing = float(facing.get(puppet_id, PuppetState.FACING_FRONT))
		state.turn_progress = 1.0
		if positions.has(puppet_id):
			var place: Array = positions[puppet_id]
			state.stage_pos = Vector2(float(place[0]), float(place[1]))
		if hand_angles.has(puppet_id):
			var angles: Array = hand_angles[puppet_id]
			state.hand_angle = Vector2(float(angles[0]), float(angles[1]))
		if hung.has(puppet_id):
			state.hook_slot = int(hung[puppet_id])
	var controlled: int = int(stage_def.initial.get("controlled", 0))
	controller.controlled_id = controlled
	controller.get_puppet(controlled).is_controlled = true


func _init(custom_stage_def: StageDef = null) -> void:
	stage_def = custom_stage_def if custom_stage_def != null else StageDef.make_level1()
	clock = MusicClock.new()
	clock.set_player(null, stage_def.bpm)
	clock.start()
	controller = PuppetController.new()
	controller.clock = clock
	controller.setup(3)
	# 手角上界按本关数据收（第一关是 90° 打伞位）。**这条不能漏**：测试台若允许手举到
	# 180°，而布景里许仙只有 90°，两手永远不齐平，接伞与整条借伞还伞流程都跑不通
	# ——实测就是这个原因让「前半场五条落点全部命中」的端到端走查失败。
	# 真实游戏走 Level1Runtime.setup 的同一处接线。
	controller.hand_angle_max = stage_def.hand_angle_max_rad
	apply_initial_puppets()
	lamp_controller = LampController.new()
	lamp_controller.clock = clock
	lamp_controller.setup()
	apply_initial_lamp()
	director = StageDirector.new()
	director.setup(stage_def, clock, controller.puppets, lamp_controller.lamp)
	director.start()


## 按关卡数据的开演布景设置灯况，与场景 `_configure_initial_stage` 的灯部分同一口径。
## 灯位/倾灯类落点的判定读 LampState，不先摆好初值就没法断言「推到目标区间才命中」。
func apply_initial_lamp() -> void:
	lamp_controller.lamp.distance = float(stage_def.initial.get("distance", 0.5))
	lamp_controller.lamp.exposure = float(stage_def.initial.get("exposure", 0.5))
	lamp_controller.lamp.oil = float(stage_def.initial.get("oil", 1.0))


## 设置油灯输入快照，下一帧 advance 生效。
func lamp_input(input_map: Dictionary) -> void:
	lamp_controller.set_input_map(input_map)


func state() -> PuppetState:
	return controller.get_controlled()


func chest_tag() -> Vector2:
	var s: PuppetState = state()
	if s == null:
		# 挂起之后可能一时无人受控（第 2 关的挂起/取回中间态），此时没有可抓的胸签。
		return Vector2.ZERO
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
			# 灯况先于判定推进：判定要读 LampState 判灯位/倾灯落点。
			# 真实运行里灯况滞后判定一帧（17 ms，远小于 ±250 ms 容差），此处不刻意复刻那一帧差。
			lamp_controller.update(STEP_S, [])
			lamp_controller.take_events()
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


## 按住左手抬起键 steps 步（每步 10 ms），让手角单调升到目标区间。
func hold_left_raise(steps: int) -> void:
	advance(steps, {"left_raise": true})


## 按住左手放下键 steps 步。
func hold_left_lower(steps: int) -> void:
	advance(steps, {"left_lower": true})


## 不拖动的空推进 steps 步。
func idle(steps: int) -> void:
	advance(steps)


## 把受控影人拖到目标横坐标附近（每步位移量上限由 step_px 给出）。
##
## 存在的理由：`PuppetController.drag_to()` 传的是**逐步位移**，而 `tick()` 会把它累积
## 之后一次性应用。连续 `drag()` 多步时每步都往同一个累加器里加一次，于是一次 -310 px
## 的「22 步拖动」实际累计了 -6820 px——影人直接被推到幕布边、整段测试的时序随之作废。
## 本方法按差值反推每步位移，并在到达目标带时停止，因此不会踩到这个陷阱：
## 无论调用者写多少步，影人都停在 target_x 附近。
## 返回实际用掉的步数；已经在目标带内时返回 0（此时拖动仍算一次真实的横移，
## 「到位」类落点因此仍能按「先离开过、再进入」判定）。
func drag_to_x(target_x: float, step_px: float, tolerance: float = 0.005) -> int:
	var state: PuppetState = state()
	if state == null:
		return 0
	var steps: int = 0
	var direction: float = 1.0 if target_x >= state.stage_pos.x else -1.0
	while steps < 200:
		var remaining: float = absf(target_x - state.stage_pos.x)
		if remaining <= tolerance:
			break
		var step_norm: float = minf(remaining, maxf(step_px, 1.0) / STAGE_W)
		controller.drag_to(Vector2(direction * step_norm * STAGE_W, 0.0))
		advance(1)
		steps += 1
	return steps


## 挂起当前影人（PRD 第 4.1 节：空格）。返回是否成功；随后步进一帧让事件进入判定。
func hook_current() -> bool:
	var ok: bool = controller.hook_current()
	advance(1)
	return ok


## 取回指定影人。随后步进一帧让事件进入判定。
func take_back(puppet_id: int) -> bool:
	var ok: bool = controller.take_back(puppet_id)
	advance(1)
	return ok


## 与备用头架第 slot 个位置换头（PRD 第 4.1 节：按键 1/2/3）。
func swap_head(slot: int) -> bool:
	var ok: bool = controller.swap_head(slot)
	advance(1)
	return ok


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


## 蹲到底（stance 到 1.0）。每步 130 px、12 步：`drag_to()` 是逐步位移，
## tick 时一次累积应用，因此这里会在第一帧直接越过 stance 上限并被 clamp 到蹲位。
## 必须在已经 `begin_drag()` 之后调用。
func crouch_here() -> void:
	drag(Vector2(0.0, 130.0), 12)


## 蹲到底（含 begin/end），沿用旧的整段用法。
func crouch(at_ms: int) -> void:
	advance_to(at_ms)
	begin_drag()
	crouch_here()
	end_drag()


## 从蹲位起立到完全站姿（跨过站起范围上限 0.05）
func stand_up(step_px: float, steps: int) -> void:
	begin_drag()
	drag(Vector2(0.0, -step_px), steps)
	end_drag()
