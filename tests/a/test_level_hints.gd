extends RefCounted
class_name TestLevelHints
## 前四关教学关与两类提示手的行为测试。
##
## 覆盖四件事：
## 1. 四关数据（时长/拍数/关键动作）符合 PRD 第 6 节，且校验通过；
## 2. PRD 第 6 节要求第 2~4 关教的动作（挂起/取回、换头、灯位、倾灯）**真的判得了**；
## 3. 教学提示手与补救提示手的互斥规则（`level1_a_scene.hint_hand_choice`）；
## 4. 补救慢放倍率是 0.5 倍速（PRD 2026-10-04 修订）。
##
## 时间由测试台推进，因此每个落点的判定窗边界都可精确断言，不依赖真实帧率或音频设备。

const ATestBaseScript := preload("res://tests/a/a_test_base.gd")
const BenchScript := preload("res://tests/a/director_test_bench.gd")
const StageDefScript := preload("res://scripts/a/stage_def.gd")
const CueScript := preload("res://scripts/a/cue.gd")
const MetronomeScript := preload("res://scripts/a_test/metronome.gd")
const SceneScript := preload("res://scripts/a_test/level1_a_scene.gd")

const STEP_S: float = 0.01


func run_all() -> Dictionary:
	var t: ATestBase = ATestBaseScript.new()
	_test_01_four_levels_data(t)
	_test_02_stage_lookup(t)
	_test_03_hook_and_take_back_judged(t)
	_test_04_head_swap_judged(t)
	_test_05_lamp_distance_judged(t)
	_test_06_lamp_not_armed_before_hint(t)
	_test_07_lamp_exposure_judged(t)
	_test_08_hint_hand_is_mutually_exclusive(t)
	_test_09_remedy_slow_factor(t)
	_test_10_stage_arg_parsing(t)
	_test_11_levels_run_end_to_end(t)
	return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed,
		"failures": t.failures}


## 造一关最小数据，用于把某一条新动作单独隔离出来判定。
## 关键动作的落点、范围全部由调用方给出，避免被真实关卡的其它落点干扰。
func _custom_stage(cues: Array, duration_ms: int = 20000,
		initial: Dictionary = {}) -> StageDef:
	var def: StageDef = StageDefScript.new()
	def.id = 1
	def.duration_ms = duration_ms
	def.bpm = StageDefScript.LEVEL1_BPM
	def.segments = [{"name": "试", "start_ms": 0, "end_ms": duration_ms}]
	for cue in cues:
		if not cue.has("segment"):
			cue["segment"] = "试"
	def.cues = cues
	var opening: Dictionary = {
		"controlled": 0, "on_stage": [0, 1, 2], "hung": {1: 0},
		"distance": 0.5, "exposure": 0.2, "oil": 1.0,
	}
	opening.merge(initial, true)
	def.initial = opening
	return def


func _has(log: Array, kind: String, cue_id: String) -> bool:
	for e in log:
		if str(e.get("kind", "")) == kind and str(e.get("cue_id", "")) == cue_id:
			return true
	return false


func _outcome(bench: DirectorTestBench, cue_id: String) -> Dictionary:
	return bench.director.performance.get_outcome(cue_id)


## —— 1. 四关数据 ——
func _test_01_four_levels_data(t: ATestBase) -> void:
	t.begin("01 前四关数据符合 PRD 第 6 节，且四关都是教学关")
	var expected: Dictionary = {
		1: {"duration": 35000, "beats": 56, "cues": 8},
		2: {"duration": 45000, "beats": 72, "cues": 7},
		3: {"duration": 50000, "beats": 80, "cues": 7},
		4: {"duration": 55000, "beats": 88, "cues": 9},
	}
	var total_duration: int = 0
	for stage_id in [1, 2, 3, 4]:
		var def: StageDef = StageDefScript.make_stage(stage_id)
		t.check(def != null, "第 %d 关数据应存在" % stage_id)
		if def == null:
			continue
		var want: Dictionary = expected[stage_id]
		t.check_eq(def.id, stage_id, "第 %d 关编号正确" % stage_id)
		t.check_eq(def.duration_ms, int(want["duration"]),
			"第 %d 关时长应为 %d ms（PRD 第 6 节）" % [stage_id, int(want["duration"])])
		t.check_eq(def.total_beats(), int(want["beats"]), "第 %d 关拍数" % stage_id)
		t.check_eq(def.cues.size(), int(want["cues"]), "第 %d 关关键动作条数" % stage_id)
		t.check(def.is_tutorial(), "第 %d 关属教学关（前四关）" % stage_id)
		t.check(not def.act.is_empty() and not def.summary.is_empty(),
			"第 %d 关应有折名与戏单简介（PRD 第 3、5.1 节）" % stage_id)
		var problems: Array[String] = def.validate()
		t.check_eq(problems.size(), 0, "第 %d 关数据应通过校验：%s" % [stage_id, str(problems)])
		total_duration += def.duration_ms

	# PRD A02：五关歌曲时间合计不超过 300 秒。第 5 关 110 秒，前四关之和须留出余量。
	t.check(total_duration + 110000 <= 300000,
		"前四关歌曲时间合计 %d ms，加第 5 关 110 秒后应不超过 300 秒" % total_duration)

	# 每关要教的动作必须真的出现在该关的 cue 表里（PRD 第 6 节的最低可验收动作）
	var l2: StageDef = StageDefScript.make_stage(2)
	t.check(_actions_of(l2).has(CueScript.ACTION_HOOK), "第 2 关应含挂起")
	t.check(_actions_of(l2).has(CueScript.ACTION_TAKE_BACK), "第 2 关应含取回")
	var l3: StageDef = StageDefScript.make_stage(3)
	t.check(_actions_of(l3).has(CueScript.ACTION_LAMP_DISTANCE), "第 3 关应含灯位推拉")
	var l4: StageDef = StageDefScript.make_stage(4)
	t.check(_actions_of(l4).has(CueScript.ACTION_HEAD_SWAP), "第 4 关应含换头")
	t.check(_actions_of(l4).has(CueScript.ACTION_LAMP_EXPOSURE), "第 4 关应含倾灯显露")

	# 第 2 关要教挂起，开局必须留出一个空挂钩，否则玩家会卡死（挂起失败 + 取回需要无人受控）
	var free_slot_ok: bool = true
	var used: Dictionary = {}
	for puppet_id in l2.initial.get("hung", {}).keys():
		used[int(l2.initial["hung"][puppet_id])] = true
	free_slot_ok = used.size() < 2
	t.check(free_slot_ok, "第 2 关开局应留出至少一个空挂钩槽（否则挂起永远失败）")
	t.finish("四关时长/拍数/动作覆盖与校验均符合 PRD")


func _actions_of(def: StageDef) -> Array[String]:
	var out: Array[String] = []
	for cue in def.cues:
		out.append(str(cue.get("action", "")))
	return out


## —— 2. 关卡查找 ——
func _test_02_stage_lookup(t: ATestBase) -> void:
	t.begin("02 关卡查找：1-4 有效，未知编号返回 null 而不是默认关")
	t.check(StageDefScript.make_stage(1) != null, "第 1 关可查")
	t.check(StageDefScript.make_stage(4) != null, "第 4 关可查")
	t.check(StageDefScript.make_stage(0) == null, "第 0 关不存在")
	t.check(StageDefScript.make_stage(5) == null, "第 5 关数据尚未定义")
	t.check(StageDefScript.make_stage(-1) == null, "负编号不存在")
	t.finish("未知关卡明确返回 null，不静默给一关默认数据")


## —— 3. 挂起与取回 ——
func _test_03_hook_and_take_back_judged(t: ATestBase) -> void:
	t.begin("03 挂起/取回在判定窗内命中，窗外记为错拍但动作照常发生")
	var def: StageDef = _custom_stage([
		CueScript.make("hook_cue", 5000, CueScript.ACTION_HOOK, -1, {}, 250, "hook"),
		CueScript.make("back_cue", 12000, CueScript.ACTION_TAKE_BACK, -1, {}, 250, "take_back"),
	], 20000)
	var bench := BenchScript.new(def)
	# 先挂起一次（窗外）：动作照常发生（cue_fire 本来就照发），但记为未命中
	bench.advance_to(2000)
	t.check(bench.hook_current(), "开局应留有空挂钩，挂起成功")
	t.check(_has(bench.director_log, "cue_fire", "hook_cue"),
		"窗外挂起仍应发出 cue_fire（物理动作确实发生了）")
	t.check(not _has(bench.director_log, "cue_hit", "hook_cue"),
		"窗外挂起不得判成命中")
	t.check(_has(bench.director_log, "cue_miss", "hook_cue"), "窗外挂起记未命中")
	t.check(bench.controller.get_controlled() == null, "挂起后无人受控")

	# 窗内取回：此时挂起的是 0 号，取回 1 号（开局挂着的那个）
	bench.advance_to(11900)
	t.check(bench.take_back(1), "应能取回开局挂在钩上的影人")
	var back: Dictionary = _outcome(bench, "back_cue")
	t.check_eq(bool(back.get("hit", false)), true,
		"窗内取回应命中（offset=%d ms）" % int(back.get("offset_ms", -99999)))
	t.check(bench.controller.get_controlled() != null, "取回后有影人受控")

	# 另一个方向：窗内挂起也应命中
	var def2: StageDef = _custom_stage([
		CueScript.make("hook_cue", 6000, CueScript.ACTION_HOOK, -1, {}, 250, "hook"),
	], 20000)
	var bench2 := BenchScript.new(def2)
	bench2.advance_to(5900)
	t.check(bench2.hook_current(), "窗内挂起应成功")
	var hook: Dictionary = _outcome(bench2, "hook_cue")
	t.check_eq(bool(hook.get("hit", false)), true,
		"窗内挂起应命中（offset=%d ms）" % int(hook.get("offset_ms", -99999)))
	t.finish("挂起与取回都参与鼓点判定，窗内命中、窗外记错拍")


## —— 4. 换头 ——
func _test_04_head_swap_judged(t: ATestBase) -> void:
	t.begin("04 换头在判定窗内命中，且六个头仍各出现恰好一次")
	var def: StageDef = _custom_stage([
		CueScript.make("head_cue", 5000, CueScript.ACTION_HEAD_SWAP, -1, {}, 250, "head_swap"),
	], 20000)
	var bench := BenchScript.new(def)
	var before: int = bench.controller.get_controlled().head_id
	bench.advance_to(4900)
	t.check(bench.swap_head(1), "与头架第 2 个位置换头应成功")
	var outcome: Dictionary = _outcome(bench, "head_cue")
	t.check_eq(bool(outcome.get("hit", false)), true,
		"窗内换头应命中（offset=%d ms）" % int(outcome.get("offset_ms", -99999)))
	t.check(bench.controller.get_controlled().head_id != before, "换头后受控影人的头确实变了")
	var heads: Array = []
	for state in bench.controller.puppets:
		heads.append(state.head_id)
	for slot in 3:
		heads.append(bench.controller.head_on_rack(slot))
	heads.sort()
	t.check_eq(heads, [0, 1, 2, 3, 4, 5], "六个头应仍各出现恰好一次（不复制、不丢失）")
	t.finish("换头可判定，且头道具的实体归属不变")


## —— 5. 灯位推拉 ——
func _test_05_lamp_distance_judged(t: ATestBase) -> void:
	t.begin("05 灯位推拉到目标区间时命中（滚轮推拉灯）")
	var def: StageDef = _custom_stage([
		CueScript.make("lamp_cue", 5000, CueScript.ACTION_LAMP_DISTANCE, -1,
			{"key": "distance", "min": 0.70, "max": 1.0}, 250, "lamp_near"),
	], 20000, {"distance": 0.50})
	var bench := BenchScript.new(def)
	bench.advance_to(4700)
	bench.lamp_input({"distance_increase": true})
	var steps_used: int = 0
	while not bench.director.performance.has_outcome("lamp_cue") and steps_used < 200:
		bench.advance(1)
		steps_used += 1
	bench.lamp_input({})
	var outcome: Dictionary = _outcome(bench, "lamp_cue")
	t.check(not outcome.is_empty(), "推拉灯到位后应产生判定结果")
	t.check_eq(bool(outcome.get("hit", false)), true,
		"窗内把灯推到目标区间应命中（offset=%d ms，distance=%.3f）"
			% [int(outcome.get("offset_ms", -99999)), bench.lamp_controller.lamp.distance])
	t.check(bench.lamp_controller.lamp.distance >= 0.70, "判定时灯距确实在目标区间内")
	t.finish("灯位落点读 LampState.distance，推到位即命中")


## —— 6. 灯位落点的「装填点」——
func _test_06_lamp_not_armed_before_hint(t: ATestBase) -> void:
	t.begin("06 灯位落点在线索时间之前不参与判定，之后须重新推到位才算")
	var cue: Dictionary = CueScript.make("lamp_cue", 12500, CueScript.ACTION_LAMP_DISTANCE, -1,
		{"key": "distance", "min": 0.70, "max": 1.0}, 250, "lamp_near")
	var def: StageDef = _custom_stage([cue], 20000, {"distance": 0.50})
	var hint_ms: int = CueScript.hint_time_ms(cue)
	var bench := BenchScript.new(def)

	# 线索时间之前就把灯推到目标区间：不得判成一次动作
	bench.advance_to(2000)
	bench.lamp_input({"distance_increase": true})
	var guard: int = 0
	while bench.lamp_controller.lamp.distance < 0.95 and guard < 400:
		bench.advance(1)
		guard += 1
	bench.lamp_input({})
	bench.advance_to(hint_ms)
	t.check(not _has(bench.director_log, "cue_fire", "lamp_cue"),
		"线索时间之前推到位不得触发该落点（否则开局值恰好落在目标区间就会被算成一次动作）")
	t.check(bench.lamp_controller.lamp.distance >= 0.95, "此时灯确实已经在目标区间内")

	# 装填之后必须先离开目标区间、再进入，才算「把灯推到位」
	bench.lamp_input({"distance_decrease": true})
	guard = 0
	while bench.lamp_controller.lamp.distance > 0.55 and guard < 400:
		bench.advance(1)
		guard += 1
	bench.lamp_input({})
	t.check(not bench.director.performance.has_outcome("lamp_cue"),
		"装填后离开目标区间不产生判定")

	bench.advance_to(12250)
	t.check(bench.lamp_controller.lamp.distance <= 0.70, "此刻灯在目标区间之外")
	bench.lamp_input({"distance_increase": true})
	guard = 0
	while not bench.director.performance.has_outcome("lamp_cue") and guard < 200:
		bench.advance(1)
		guard += 1
	bench.lamp_input({})
	var outcome: Dictionary = _outcome(bench, "lamp_cue")
	t.check_eq(bool(outcome.get("hit", false)), true,
		"重新推入目标区间应命中（offset=%d ms）" % int(outcome.get("offset_ms", -99999)))
	t.finish("灯位落点只在线索时间之后判上升沿，避免开演瞬间被误判")


## —— 7. 倾灯显露 ——
func _test_07_lamp_exposure_judged(t: ATestBase) -> void:
	t.begin("07 倾灯把显露推到目标区间时命中")
	var def: StageDef = _custom_stage([
		CueScript.make("expo_cue", 6000, CueScript.ACTION_LAMP_EXPOSURE, -1,
			{"key": "exposure", "min": 0.45, "max": 0.60}, 250, "exposure_up"),
	], 20000, {"exposure": 0.20})
	var bench := BenchScript.new(def)
	bench.advance_to(5500)
	bench.lamp_input({"exposure_increase": true})
	var steps_used: int = 0
	while not bench.director.performance.has_outcome("expo_cue") and steps_used < 200:
		bench.advance(1)
		steps_used += 1
	bench.lamp_input({})
	var outcome: Dictionary = _outcome(bench, "expo_cue")
	t.check_eq(bool(outcome.get("hit", false)), true,
		"窗内推高显露应命中（offset=%d ms，exposure=%.3f）"
			% [int(outcome.get("offset_ms", -99999)), bench.lamp_controller.lamp.exposure])
	# 镜头拉到目标之外不应命中
	var bench2 := BenchScript.new(_custom_stage([
		CueScript.make("expo_cue", 6000, CueScript.ACTION_LAMP_EXPOSURE, -1,
			{"key": "exposure", "min": 0.95, "max": 1.0}, 250, "exposure_up"),
	], 20000, {"exposure": 0.20}))
	bench2.advance_to(5500)
	bench2.lamp_input({"exposure_increase": true})
	steps_used = 0
	while not bench2.director.performance.has_outcome("expo_cue") and steps_used < 200:
		bench2.advance(1)
		steps_used += 1
	bench2.lamp_input({})
	t.check_eq(bool(_outcome(bench2, "expo_cue").get("hit", false)), false,
		"只推到中段（未达目标区间）应记为未命中，动作照常发生")
	t.finish("倾灯按目标区间判定，未达区间记错拍")


## —— 8. 两类提示手互斥 ——
func _test_08_hint_hand_is_mutually_exclusive(t: ATestBase) -> void:
	t.begin("08 两类提示手互斥：补救手优先，补救冻结期间不出教学手")
	var NONE: int = SceneScript.HAND_NONE
	var TEACH: int = SceneScript.HAND_TEACHING
	var REMEDY: int = SceneScript.HAND_REMEDY

	t.check_eq(SceneScript.hint_hand_choice(false, false, true, false, "", "c1"), TEACH,
		"教学关、正常演出、有已告知未判定的落点 → 教学手")
	t.check_eq(SceneScript.hint_hand_choice(false, false, true, true, "", "c1"), NONE,
		"补救冻结 + 无补救示范 → 不画教学手（落点不会到来，预告只会误导）")
	t.check_eq(SceneScript.hint_hand_choice(false, false, true, true, "c9", "c1"), REMEDY,
		"补救冻结 + 有补救示范 → 补救手（且教学手被压制）")
	t.check_eq(SceneScript.hint_hand_choice(false, false, true, false, "c9", "c1"), REMEDY,
		"同一 cue 上补救手优先于教学手")
	t.check_eq(SceneScript.hint_hand_choice(false, false, false, false, "", "c1"), NONE,
		"非教学关（第 5 关）没有常驻教学手")
	t.check_eq(SceneScript.hint_hand_choice(false, false, true, false, "", ""), NONE,
		"没有已告知的落点时两只手都不出")
	t.check_eq(SceneScript.hint_hand_choice(true, false, true, false, "", "c1"), NONE,
		"菜单暂停时不出手")
	t.check_eq(SceneScript.hint_hand_choice(false, true, true, false, "c9", "c1"), NONE,
		"演出结束后不出手")

	# 穷举全部组合：结果只可能是三种取值之一，不可能「两只手同时为真」。
	var seen: Dictionary = {}
	for paused in [false, true]:
		for over in [false, true]:
			for tutorial in [false, true]:
				for frozen in [false, true]:
					for demo in ["", "c9"]:
						for active in ["", "c1"]:
							seen[SceneScript.hint_hand_choice(paused, over, tutorial,
								frozen, demo, active)] = true
	var allowed: bool = true
	for key in seen.keys():
		if key != NONE and key != TEACH and key != REMEDY:
			allowed = false
	t.check(allowed, "选择结果只可能是「无 / 教学 / 补救」三者之一")
	t.check_eq(seen.size(), 3, "三种取值都应被穷举覆盖到（实际 %s）" % str(seen.keys()))
	t.finish("两类提示手在触发时机与条件上互相区分、互不重叠")


## —— 9. 补救慢放倍率 ——
func _test_09_remedy_slow_factor(t: ATestBase) -> void:
	t.begin("09 补救慢放为 0.5 倍速（PRD 2026-10-04 修订）")
	t.check_approx(MetronomeScript.REMEDY_SLOW_FACTOR, 0.5, 1e-9,
		"补救慢放倍率应为 0.5")
	var music: Metronome = MetronomeScript.new()
	# 慢放内容的时间只按 0.5 前进，并在一小段（4 拍）里循环。
	var loop_s: float = (60.0 / StageDefScript.LEVEL1_BPM) * 4.0
	var expected: float = music.call("sample_at", fposmod(2.0 * 0.5, loop_s))
	var actual: float = music.call("sample_at_slow", 2.0)
	t.check_approx(actual, expected, 1e-9, "sample_at_slow 应按 0.5 倍速取样")
	t.check(absf(MetronomeScript.REMEDY_SLOW_FACTOR - 0.1) > 1e-6,
		"不应再是 0.1 倍速")
	t.finish("补救音乐按 0.5 倍速播放")


## —— 10. 切关参数 ——
func _test_10_stage_arg_parsing(t: ATestBase) -> void:
	t.begin("10 开发用切关参数解析：缺省回第 1 关，非法值不静默变成别的关")
	var stage_id: int = SceneScript.requested_stage_id()
	t.check(stage_id >= 1 and stage_id <= StageDefScript.LAST_TUTORIAL_LEVEL,
		"解析结果应落在 1–4，实际 %d" % stage_id)
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	var has_arg: bool = false
	for arg in args:
		if str(arg).begins_with("stage="):
			has_arg = true
	if not has_arg:
		t.check_eq(stage_id, StageDefScript.LEVEL1_ID, "没有切关参数时回第 1 关")
	t.finish("切关参数只在 1–4 内生效，其余一律回第 1 关")


## —— 11. 四关能跑完 ——
func _test_11_levels_run_end_to_end(t: ATestBase) -> void:
	t.begin("11 第 2–4 关空场也能按时收场，全部落点都有如实记录")
	for stage_id in [2, 3, 4]:
		var def: StageDef = StageDefScript.make_stage(stage_id)
		if def == null:
			t.check(false, "第 %d 关数据缺失" % stage_id)
			continue
		var bench := BenchScript.new(def)
		var steps: int = bench.run_to_end(30000)
		t.check(bench.director.is_over(), "第 %d 关应能跑到结束" % stage_id)
		t.check_eq(bench.clock.get_song_time_ms(), def.duration_ms,
			"第 %d 关歌曲时间应恰好走满 %d ms" % [stage_id, def.duration_ms])
		t.check(bench.clock.get_real_time_ms() > def.duration_ms,
			"第 %d 关因补救冻结，真实耗时应长于歌曲时长" % stage_id)
		t.check(steps < 30000, "第 %d 关应在步数上限内结束（实际 %d 步）" % [stage_id, steps])
		var missing: Array[String] = []
		for cue in def.cues:
			var cue_id: String = str(cue["cue_id"])
			if not bench.director.performance.has_outcome(cue_id):
				missing.append(cue_id)
		t.check_eq(missing.size(), 0, "第 %d 关每条落点都应有判定结果：%s"
			% [stage_id, str(missing)])
		bench.director.force_end()
		bench.director_log.append_array(bench.director.take_events())
	t.finish("第 2–4 关空场端到端可跑通，时间轴与记录完整")
