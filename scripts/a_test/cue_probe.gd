extends RefCounted
class_name CueProbe
## 图形环境下的关键动作判定实测。
##
## 为什么能在真实窗口里同步跑完 35 秒的判定：
## 本段只用 PuppetController 的输入接口驱动姿势、用 MusicClock 的自由计时
## 推进歌曲时间（探针模式不读音频位置），因此每一步都是确定的，不依赖真实帧率。
## 它验证「判定逻辑在真实渲染进程里跑通、且与状态一致」；
## 与真实音频时钟耦合的整关一把过，由人工按 tests/a/README.md 第 3 节实测。

const CueScript := preload("res://scripts/a/cue.gd")
const StageDefScript := preload("res://scripts/a/stage_def.gd")
const PuppetControllerScript := preload("res://scripts/a/puppet_controller.gd")
const PerformanceSystemScript := preload("res://scripts/a/performance_system.gd")
const MusicClockScript := preload("res://scripts/a/music_clock.gd")

const STAGE_W: float = 1920.0
const STAGE_H: float = 1080.0

var failures: Array[String] = []


## 一套干净的时钟 + 控制器 + 判定系统。歌曲时间由本测试台推进（自由计时）。
class Rig extends RefCounted:
	const STEP_MS: int = 10
	const STEP_S: float = 0.01
	const STAGE_W: float = 1920.0
	const STAGE_H: float = 1080.0

	var clock: MusicClock = null
	var controller: PuppetController = null
	var performance: PerformanceSystem = null
	var stage_def: StageDef = null
	var time_ms: int = 0
	var judge_log: Array = []

	func advance(steps: int) -> void:
		for _i in maxi(steps, 0):
			clock.update(STEP_S)
			time_ms = clock.get_song_time_ms()
			controller.tick(STEP_S)
			var events: Array[Dictionary] = controller.take_events()
			performance.update(time_ms, events)
			judge_log.append_array(performance.take_events())

	func advance_to(target_ms: int) -> void:
		advance(int(maxf(float(target_ms - time_ms) / float(STEP_MS), 0.0)))

	func state() -> PuppetState:
		return controller.get_controlled()

	func chest_tag() -> Vector2:
		var s: PuppetState = state()
		return Vector2(s.stage_pos.x * STAGE_W,
			s.stage_pos.y * STAGE_H - PuppetController.CHEST_TAG_RADIUS_PX * 0.5)

	func find_cue(cue_id: String) -> Dictionary:
		for cue in stage_def.cues:
			if str(cue.get("cue_id", "")) == cue_id:
				return cue
		return {}


func run() -> int:
	print("")
	print("[8] 第一关关键动作判定：线索提前量 / 窗内命中 / 窗外照常发生 / 平移不逐帧评分")

	var def: StageDef = StageDefScript.make_level1()
	_check_data(def)
	_check_hint_lead(def)
	_check_stand_up_window(def)
	_check_translation_single_grade(def)
	_check_reach(def)

	print("")
	print("判定实测结论：%s" % ("全部符合预期" if failures.is_empty()
		else "%d 项不符合预期" % failures.size()))
	for line in failures:
		print("  不符合预期：%s" % line)
	return failures.size()


func _rig() -> Rig:
	var r := Rig.new()
	r.stage_def = StageDefScript.make_level1()
	r.clock = MusicClockScript.new()
	r.clock.set_player(null, r.stage_def.bpm)
	r.clock.start()
	r.controller = PuppetControllerScript.new()
	r.controller.clock = r.clock
	r.controller.setup(3)
	r.performance = PerformanceSystemScript.new()
	r.performance.setup(r.stage_def.cues, r.clock, r.controller.puppets)
	return r


func _check_data(def: StageDef) -> void:
	var problems: Array[String] = def.validate()
	_expect(problems.is_empty(), "第一关数据校验通过（%d 条关键动作）" % def.cues.size())
	_expect(def.duration_ms == 35000, "第一关演出固定 35 秒（实际 %d ms）" % def.duration_ms)
	var actions: Array[String] = []
	for cue in def.cues:
		actions.append(str(cue["action"]))
	_expect(actions.has(CueScript.ACTION_STAND_UP), "含站起")
	_expect(actions.has(CueScript.ACTION_MOVE_LEFT) and actions.has(CueScript.ACTION_MOVE_RIGHT),
		"含横向移动（左右）")
	_expect(actions.has(CueScript.ACTION_HAND_RAISE), "含抬手")
	var accent: int = 0
	for cue in def.cues:
		var beat_index: int = int(round(float(cue["beat_time_ms"]) / def.beat_duration_ms()))
		if beat_index > 0 and beat_index % 4 == 0:
			accent += 1
	_expect(accent >= 1, "至少一次关键动作落在重音上（实际 %d 次）" % accent)


func _check_hint_lead(def: StageDef) -> void:
	var early: bool = true
	var details: Array[String] = []
	for cue in def.cues:
		var hint_ms: int = CueScript.hint_time_ms(cue)
		if hint_ms >= int(cue["beat_time_ms"]) or hint_ms < 0:
			early = false
			details.append("%s hint=%d beat=%d" % [str(cue["cue_id"]), hint_ms,
				int(cue["beat_time_ms"])])
	_expect(early, "每条关键动作的线索都早于落点%s"
		% ("" if early else "：" + ", ".join(details)))

	var verified: int = 0
	for cue in def.cues:
		var cue_id: String = str(cue["cue_id"])
		var hint_ms: int = CueScript.hint_time_ms(cue)
		var r: Rig = _rig()
		r.advance_to(maxi(hint_ms - Rig.STEP_MS, 0))
		var before: bool = _has_event(r.judge_log, "cue_hint", cue_id)
		r.advance(1)
		var after: bool = _has_event(r.judge_log, "cue_hint", cue_id)
		if not before and after:
			verified += 1
	_expect(verified == def.cues.size(),
		"%d / %d 条线索在正确时刻出现（早一帧看不到、到达即可见）"
		% [verified, def.cues.size()])


func _check_stand_up_window(def: StageDef) -> void:
	var beat_ms: int = int(_find(def, "l1_c1_stand")["beat_time_ms"])

	var r: Rig = _rig()
	_crouch(r, 1000)
	r.advance_to(maxi(beat_ms - 1250, 0))
	_drag(r, Vector2(0.0, -8.0), 130)
	var outcome: Dictionary = r.performance.get_outcome("l1_c1_stand")
	_expect(r.performance.has_outcome("l1_c1_stand"), "窗内站起产生了判定结果")
	_expect(bool(outcome.get("hit", false)),
		"窗内站起判为命中（offset=%d ms，容差 %d ms）"
		% [int(outcome.get("offset_ms", 0)), int(outcome.get("tolerance_ms", 0))])
	_expect(absf(float(outcome.get("offset_ms", 9999))) <= 250.0,
		"命中偏移在 ±250 ms 内（实际 %d ms）" % int(outcome.get("offset_ms", 0)))

	var r2: Rig = _rig()
	_crouch(r2, 1000)
	r2.advance_to(maxi(beat_ms - 2100, 0))
	_drag(r2, Vector2(0.0, -15.0), 69)
	var miss: Dictionary = r2.performance.get_outcome("l1_c1_stand")
	_expect(r2.performance.has_outcome("l1_c1_stand"), "窗外站起也产生了判定结果")
	_expect(not bool(miss.get("hit", true)),
		"窗外站起判为未命中（offset=%d ms）" % int(miss.get("offset_ms", 0)))
	_expect(r2.state().stance <= 0.05,
		"错拍站起时姿势照常到位（stance=%.4f）" % r2.state().stance)
	_expect(_has_event(r2.judge_log, "cue_fire", "l1_c1_stand"),
		"未命中时仍发出 cue_fire（物理动作发生了）")


func _check_translation_single_grade(def: StageDef) -> void:
	var beat_ms: int = int(_find(def, "l1_c2_move_left")["beat_time_ms"])
	var r: Rig = _rig()
	r.advance_to(maxi(beat_ms - 600, 0))
	_drag(r, Vector2(-30.0, 0.0), 20)
	r.advance(20)
	var fires: int = _count(r.judge_log, "cue_fire", "l1_c2_move_left")
	var graded: int = _count(r.judge_log, "cue_hit", "l1_c2_move_left") \
		+ _count(r.judge_log, "cue_miss", "l1_c2_move_left")
	_expect(fires == 1, "20 帧持续平移只产生 1 次 cue_fire（实际 %d）" % fires)
	_expect(graded == 1, "该关键动作只判定一次（实际 %d）" % graded)


func _check_reach(def: StageDef) -> void:
	var cue: Dictionary = _find(def, "l1_c5_reach_center")
	var beat_ms: int = int(cue["beat_time_ms"])
	var r: Rig = _rig()
	r.advance_to(maxi(beat_ms - 1000, 0))
	_expect(not r.performance.has_outcome("l1_c5_reach_center"),
		"站定不动不算「移动到到位」")

	# 在落点前 1 s 开始拖动（窗口之外），先移出范围
	r.advance_to(maxi(beat_ms - 1000, 0))
	r.controller.begin_drag(0, r.chest_tag())
	for _i in 19:
		r.controller.drag_to(Vector2(19.0, 0.0))
		r.advance(1)
	_expect(r.state().stage_pos.x > 0.53,
		"已移出中位范围（x=%.4f）" % r.state().stage_pos.x)
	# 仍在同一次拖动中，但把时间推到落点附近，再拖回范围内
	r.advance_to(maxi(beat_ms - 150, 0))
	_expect(not r.performance.has_outcome("l1_c5_reach_center"),
		"移出范围期间不算到位")
	# 每步 -24 px（约 -0.0125），从 x≈0.688 回到 0.53 以内约需 13 步，
	# 13 步 = 130 ms，因此跨进范围时仍落在 ±250 ms 判定窗内。
	var used: int = 0
	while used < 15 and not r.performance.has_outcome("l1_c5_reach_center"):
		r.controller.drag_to(Vector2(-24.0, 0.0))
		r.advance(1)
		used += 1
	r.controller.end_drag()
	r.advance(1)
	var reached: Dictionary = r.performance.get_outcome("l1_c5_reach_center")
	_expect(r.performance.has_outcome("l1_c5_reach_center"),
		"拖动中回到目标范围判为到位（用了 %d 步）" % used)
	_expect(bool(reached.get("hit", false)),
		"到位判为命中（offset=%d ms，x=%.4f）"
		% [int(reached.get("offset_ms", 0)), float(reached.get("metric", 0.0))])


func _crouch(r: Rig, at_ms: int) -> void:
	r.advance_to(at_ms)
	_drag(r, Vector2(0.0, 120.0), 12)


func _drag(r: Rig, delta: Vector2, steps: int) -> void:
	r.controller.begin_drag(0, r.chest_tag())
	for _i in maxi(steps, 0):
		r.controller.drag_to(delta)
		r.advance(1)
	r.controller.end_drag()
	r.advance(1)


func _find(def: StageDef, cue_id: String) -> Dictionary:
	for cue in def.cues:
		if str(cue.get("cue_id", "")) == cue_id:
			return cue
	return {}


func _has_event(log: Array, kind: String, cue_id: String) -> bool:
	return _count(log, kind, cue_id) > 0


func _count(log: Array, kind: String, cue_id: String) -> int:
	var n: int = 0
	for e in log:
		if str(e["kind"]) == kind and str(e["cue_id"]) == cue_id:
			n += 1
	return n


func _expect(condition: bool, message: String) -> void:
	var mark: String = "OK  " if condition else "BAD "
	if not condition:
		failures.append(message)
	print("  %s %s" % [mark, message])
