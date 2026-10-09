extends RefCounted
class_name CReplayVerifier
## 回放验收器：用一份内容已知的记录，比对「原演出」与「幕前回放」是否同一场戏。
##
## 验收标准（TECH_DESIGN 第 4 节末段）：
##   用一次故意包含快速转身、双手不同姿势、换头、挂起、灯位变化和错拍的演出，
##   比对原演出与幕前回放的动作顺序、关键事件时间、持续时长及掌声。
##   允许插值带来的轻微过渡差异，不能漏动作、换错头、改变结局
##   或用预制动画代替。
##
## 本类不做画面、不建场景、不碰音频，只产出「哪里不一致」的判定。
## 定位是**独立复核**：它不复用 CReplayPlayer 的内部推导，而是从记录与
## 回放产出两侧各自取证再对账。若把回放器的实现抄一遍来验收，
## 那一处实现错了，验收会跟着一起错——那就不是验收。
##
## 六项核心检查（外加一项「回放可推进」前置）：
##   0. 回放可推进      记录能装载并走完全场（不通过则后面的走查无从谈起）
##   1. 记录自检        记录本身的不变量必须成立（错了就没有可比的基准）
##   2. 采样保真        在记录每一帧的时刻取回放状态，必须等于该帧原值
##                      → 漏动作 / 换错头 / 用预制动画代替 都在这里露出来
##   3. 时间轴          回放跑满整段时长、播放头单调、末尾精确对齐
##   4. 离散跳变顺序    换头与挂起的先后次序不得被打乱或合并
##   5. 关键事件时间    每条事件都被派发，且落在记录的时刻上（不早不晚）
##   6. 掌声与结局      掌声段数不被改写，结果页判出的结局与记录一致
##
## 依赖一律用 preload 常量：godot --headless --script 不读全局类名缓存。

const CReplayPlayerScript := preload("res://scripts/c/c_replay_player.gd")
const CResultFlowScript := preload("res://scripts/c/c_result_flow.gd")

## 回放推进步长，与模拟演出的采样步长一致，便于逐帧对账。
const DEFAULT_STEP_MS: int = 17

## 连续量的容差。在记录快照的**时刻**上取回放值，插值比例恰为 0，
## 理论上应精确相等，故容差只用于吸收浮点往返误差，不放宽到「近似」。
const CONTINUOUS_EPSILON: float = 1.0e-6

## 离散道具归属字段。头与挂钩是实物归属，取中间值等于造出从未存在的第三个头，
## 因此必须精确相等，不适用任何容差。
const DISCRETE_FIELDS: Array[String] = ["head_id", "hook_slot"]

## 影人的连续标量字段。
const PUPPET_SCALAR_FIELDS: Array[String] = ["stance", "facing", "turn_progress"]

## 影人的连续二维字段，内含 "x"/"y" 或 "left"/"right"。
const PUPPET_VECTOR_FIELDS: Array[String] = ["stage_pos", "hand_angle"]

## 灯态四字段，全为连续量。
const LAMP_FIELDS: Array[String] = ["distance", "exposure", "oil", "flame_feedback"]

## 单个检查最多记录多少条问题，超出的折叠成一条计数，
## 免得一处系统性错误刷出上万行，把真正的结论埋掉。
const MAX_PROBLEMS_PER_CHECK: int = 8


## 对一份记录做完整回放验收。
##
## 返回：
##   {
##     ok: bool,                     # 全部检查通过
##     stage_id: int,
##     duration_ms: int,
##     problems: Array[String],      # 汇总的问题，空即通过
##     checks: Array[Dictionary],    # [{name, ok, detail}]
##     stats: Dictionary,            # 供报告展示的实测数字
##   }
func verify(p_record: Variant, p_step_ms: int = DEFAULT_STEP_MS) -> Dictionary:
	var problems: Array = []
	var checks: Array = []

	if p_record == null:
		problems.append("记录为 null，无内容可验收")
		checks.append(_check_result("记录自检", false, "记录为 null"))
		return _report(problems, checks, {}, -1, 0)

	var stage_id: int = int(p_record.stage_id)
	var duration_ms: int = int(p_record.get_replay_duration_ms())

	# ---- 1. 记录自检 ----
	var invariant_problems: Array = p_record.validate_invariants()
	_append_check(checks, problems, "记录自检",
		invariant_problems, "不变量成立（快照 %d / 事件 %d）"
			% [p_record.snapshots.size(), p_record.events.size()])

	# 记录不合法时继续比对没有意义：基准本身是错的，
	# 后面每一项都会报错，反而看不出真正的原因。
	if not invariant_problems.is_empty():
		return _report(problems, checks, _base_stats(p_record), stage_id, duration_ms)

	# ---- 2. 采样保真 ----
	var fidelity: Dictionary = _check_sampling_fidelity(p_record)
	_append_check(checks, problems, "采样保真（不漏动作·不换错头·非预制）",
		fidelity["problems"], fidelity["detail"])

	# ---- 走一遍完整回放，收集帧与事件 ----
	var walk: Dictionary = _walk(p_record, p_step_ms)
	_append_check(checks, problems, "回放可推进", walk["problems"], walk["detail"])

	var frames: Array = walk["frames"]
	var dispatched: Array = walk["dispatched"]

	# ---- 3. 时间轴 ----
	var timeline: Dictionary = _check_timeline(p_record, frames, duration_ms)
	_append_check(checks, problems, "时间轴（时长覆盖·单调·末尾对齐）",
		timeline["problems"], timeline["detail"])

	# ---- 4. 离散跳变顺序 ----
	var order: Dictionary = _check_discrete_order(p_record, frames, p_step_ms)
	_append_check(checks, problems, "离散跳变顺序（换头/挂起不合并）",
		order["problems"], order["detail"])

	# ---- 5. 关键事件时间 ----
	var events: Dictionary = _check_events(p_record, dispatched, p_step_ms)
	_append_check(checks, problems, "关键事件时间（不漏·不重·不早不晚）",
		events["problems"], events["detail"])

	# ---- 6. 掌声与结局 ----
	var applause: Dictionary = _check_applause_and_ending(p_record, stage_id, p_step_ms)
	_append_check(checks, problems, "掌声与结局（不改变结局）",
		applause["problems"], applause["detail"])

	var stats: Dictionary = _base_stats(p_record)
	stats["replay_frames"] = frames.size()
	stats["dispatched_events"] = dispatched.size()
	stats["applause_act_count"] = applause.get("applause_act_count", 0)
	stats["ending"] = applause.get("ending", &"")
	stats["discrete_tokens"] = order.get("token_count", 0)
	return _report(problems, checks, stats, stage_id, duration_ms)


## 逐快照取回放状态并比对。
##
## 关键设计：在**记录的采样时刻**上取值。那一刻插值比例恰为 0，
## 回放应精确还原该帧原值——容差只用来吸收浮点误差，不是「大致相同」。
## 因此这一项同时覆盖三件事：
##   - 不漏动作：每一帧记录的状态都能在回放里被取到
##   - 不换错头：head_id / hook_slot 逐帧精确相等
##   - 非预制动画：若回放播的是预制动作，逐帧比对会大面积不符
func _check_sampling_fidelity(p_record: Variant) -> Dictionary:
	var problems: Array = []
	var player: Variant = CReplayPlayerScript.new()
	if not player.load(p_record):
		return {"problems": ["回放器拒绝装载记录，无法比对采样保真"],
			"detail": "装载失败"}

	var mismatches: int = 0
	var compared: int = 0
	var snapshots: Array = p_record.snapshots
	for idx in snapshots.size():
		var snap: Variant = snapshots[idx]
		var t: int = int(snap.time_ms)
		var frame: Dictionary = player.sample(t)
		var frame_puppets: Array = frame["puppets"]
		var frame_lamp: Dictionary = frame["lamp"]

		for i in mini(frame_puppets.size(), snap.puppets.size()):
			var got: Dictionary = frame_puppets[i]
			var want: Dictionary = snap.puppets[i]
			compared += 1
			mismatches += _diff_puppet(t, i, want, got, problems)
		compared += 1
		mismatches += _diff_lamp(t, snap.lamp, frame_lamp, problems)

	var detail: String = "逐帧比对 %d 帧，全部在采样时刻精确还原" % compared
	if mismatches > 0:
		detail = "共 %d 处不符" % mismatches
	return {"problems": problems, "detail": detail}


func _diff_puppet(t: int, index: int, want: Dictionary, got: Dictionary,
		p_problems: Array) -> int:
	var bad: int = 0
	for f in DISCRETE_FIELDS:
		if int(want.get(f, -1)) != int(got.get(f, -1)):
			bad += 1
			_push_problem(p_problems, "t=%dms puppets[%d].%s 记录 %d，回放 %d（离散量必须精确相等）"
				% [t, index, f, int(want.get(f, -1)), int(got.get(f, -1))])
	for f in PUPPET_SCALAR_FIELDS:
		if absf(float(want.get(f, 0.0)) - float(got.get(f, 0.0))) > CONTINUOUS_EPSILON:
			bad += 1
			_push_problem(p_problems, "t=%dms puppets[%d].%s 记录 %.6f，回放 %.6f"
				% [t, index, f, float(want.get(f, 0.0)), float(got.get(f, 0.0))])
	for f in PUPPET_VECTOR_FIELDS:
		var a: Dictionary = want.get(f, {})
		var b: Dictionary = got.get(f, {})
		for axis in a.keys():
			if absf(float(a.get(axis, 0.0)) - float(b.get(axis, 0.0))) > CONTINUOUS_EPSILON:
				bad += 1
				_push_problem(p_problems, "t=%dms puppets[%d].%s.%s 记录 %.6f，回放 %.6f"
					% [t, index, f, axis, float(a.get(axis, 0.0)), float(b.get(axis, 0.0))])
	if bool(want.get("is_controlled", false)) != bool(got.get("is_controlled", false)):
		bad += 1
		_push_problem(p_problems, "t=%dms puppets[%d].is_controlled 记录 %s，回放 %s"
			% [t, index, str(want.get("is_controlled")), str(got.get("is_controlled"))])
	return bad


func _diff_lamp(t: int, want: Dictionary, got: Dictionary, p_problems: Array) -> int:
	var bad: int = 0
	for f in LAMP_FIELDS:
		if absf(float(want.get(f, 0.0)) - float(got.get(f, 0.0))) > CONTINUOUS_EPSILON:
			bad += 1
			_push_problem(p_problems, "t=%dms lamp.%s 记录 %.6f，回放 %.6f"
				% [t, f, float(want.get(f, 0.0)), float(got.get(f, 0.0))])
	return bad


## 走一遍完整回放，收集每帧的播放时刻、影人状态与当帧派发的事件。
##
## 用步进推进而非直接取末帧：只有真的走完，才能发现「播放头不动」
## 或「某一帧起就不推进」这类问题。
func _walk(p_record: Variant, p_step_ms: int) -> Dictionary:
	var problems: Array = []
	var player: Variant = CReplayPlayerScript.new()
	# 验收是**离线批跑**：墙钟几乎不走，必须注入逻辑时间才能在有限步内走完。
	# 这不是放宽验收——插值与事件派发逻辑与时钟源无关，只改节奏。
	player.set_clock_source(CReplayPlayerScript.CLOCK_SOURCE_DELTA)
	if not player.load(p_record):
		return {"problems": ["回放器拒绝装载记录"], "detail": "装载失败",
			"frames": [], "dispatched": []}
	player.play()

	var duration_ms: int = int(p_record.get_replay_duration_ms())
	# 上限按理论帧数放宽若干帧：超过就说明播放头卡住了，直接停手报出来，
	# 不无限循环。
	var max_frames: int = int(ceil(float(duration_ms) / float(p_step_ms))) + 16

	var frames: Array = []
	var dispatched: Array = []
	var guard: int = 0
	while not player.is_finished() and guard < max_frames:
		var frame: Dictionary = player.advance(float(p_step_ms) / 1000.0)
		frames.append({"now_ms": int(frame["now_ms"]), "puppets": frame["puppets"]})
		for e in frame["events"]:
			dispatched.append({"ev": e, "at_ms": int(frame["now_ms"])})
		guard += 1

	var detail: String = "推进 %d 步走完全场" % frames.size()
	if guard >= max_frames and not player.is_finished():
		problems.append("回放推进 %d 步仍未结束（时长 %dms），播放头可能卡住"
			% [guard, duration_ms])
		detail = "推进超限未结束"
	return {"problems": problems, "detail": detail,
		"frames": frames, "dispatched": dispatched}


## 时间轴：跑满整段、播放头单调、末尾精确对齐。
##
## 末尾对齐是硬要求：步长通常除不尽时长（8000 % 17 ≠ 0），
## 若不做钉住，末帧会停在 7990，画面缺最后 10ms，重看时首尾对不上。
func _check_timeline(p_record: Variant, p_frames: Array, p_duration_ms: int) -> Dictionary:
	var problems: Array = []
	if p_frames.is_empty():
		return {"problems": ["回放没有产出任何帧"], "detail": "无帧"}

	var record_duration: int = int(p_record.duration_ms)
	if record_duration != p_duration_ms:
		problems.append("记录 duration_ms=%d 与回放时长口径 %d 不一致"
			% [record_duration, p_duration_ms])

	var prev: int = -1
	var first_backwards: int = -1
	for f in p_frames:
		var t: int = int(f["now_ms"])
		if t < prev and first_backwards < 0:
			first_backwards = t
		prev = t
	if first_backwards >= 0:
		problems.append("播放头出现倒退，落在 %dms" % first_backwards)

	var last: int = int(p_frames[-1]["now_ms"])
	if last != p_duration_ms:
		problems.append("末帧 %dms 未对齐到时长 %dms，尾部画面会缺一段"
			% [last, p_duration_ms])

	var detail: String = "末帧 %dms = 时长 %dms，%d 帧单调不减" % [last, p_duration_ms, p_frames.size()]
	return {"problems": problems, "detail": detail}


## 离散跳变顺序：换头与挂起的先后次序不得被打乱或合并。
##
## 为什么单独查「顺序」而不只查「值」：采样保真证明每一刻的值都对，
## 但若实现把两个跳变压到同一帧，值仍然对，而画面上「先换头后挂起」
## 会变成「同时发生」——TECH_DESIGN 允许过渡差异，不允许改动作顺序。
func _check_discrete_order(p_record: Variant, p_frames: Array, p_step_ms: int) -> Dictionary:
	var record_pairs: Array = []
	for snap in p_record.snapshots:
		record_pairs.append([int(snap.time_ms), snap.puppets])
	var replay_pairs: Array = []
	for f in p_frames:
		replay_pairs.append([int(f["now_ms"]), f["puppets"]])

	var want: Array = _discrete_tokens(record_pairs)
	var got: Array = _discrete_tokens(replay_pairs)
	var problems: Array = []

	if want.size() != got.size():
		problems.append("离散跳变条数不一致：记录 %d 条，回放 %d 条" % [want.size(), got.size()])

	var limit: int = mini(want.size(), got.size())
	for i in limit:
		var a: Dictionary = want[i]
		var b: Dictionary = got[i]
		if str(a["key"]) != str(b["key"]):
			_push_problem(problems, "第 %d 个离散跳变不一致：记录 %s@%dms，回放 %s@%dms"
				% [i, str(a["key"]), int(a["t"]), str(b["key"]), int(b["t"])])
		elif absi(int(a["t"]) - int(b["t"])) > p_step_ms:
			_push_problem(problems, "第 %d 个离散跳变 %s 时刻偏移过大：记录 %dms，回放 %dms"
				% [i, str(a["key"]), int(a["t"]), int(b["t"])])

	var detail: String = "两侧各 %d 次离散跳变，次序与时刻一致" % want.size()
	if not problems.is_empty():
		detail = "记录 %d 条 / 回放 %d 条" % [want.size(), got.size()]
	return {"problems": problems, "detail": detail, "token_count": want.size()}


## 从状态序列导出离散跳变序列。两侧用同一套规则，因此比对的是
## 「派生出的跳变序列」而不是实现细节。
func _discrete_tokens(p_pairs: Array) -> Array:
	var tokens: Array = []
	var prev: Array = []
	for pair in p_pairs:
		var t: int = int(pair[0])
		var puppets: Array = pair[1]
		var cur: Array = []
		for p in puppets:
			cur.append([int((p as Dictionary).get("head_id", -1)),
				int((p as Dictionary).get("hook_slot", -1))])
		if not prev.is_empty():
			for i in mini(prev.size(), cur.size()):
				if int(prev[i][0]) != int(cur[i][0]):
					tokens.append({"t": t, "key": "p%d.head=%d" % [i, int(cur[i][0])]})
				if int(prev[i][1]) != int(cur[i][1]):
					tokens.append({"t": t, "key": "p%d.hook=%d" % [i, int(cur[i][1])]})
		prev = cur
	return tokens


## 关键事件时间：每条事件都被派发且不重复，且落在记录的时刻上。
##
## 记录侧的事件是待办清单，回放侧的派发是实际发生。两者必须一一对应：
## 少一条=漏动作，多一条=重复播放，早于记录=提前触发，晚太多=滞后。
func _check_events(p_record: Variant, p_dispatched: Array, p_step_ms: int) -> Dictionary:
	var problems: Array = []
	var want: Array = p_record.events
	var got: Array = p_dispatched

	if want.size() != got.size():
		problems.append("派发事件数 %d 与记录事件数 %d 不一致" % [got.size(), want.size()])

	var limit: int = mini(want.size(), got.size())
	for i in limit:
		var a: Variant = want[i]
		var b: Variant = got[i]["ev"]
		var at: int = int(got[i]["at_ms"])
		if str(a.kind) != str(b.kind):
			_push_problem(problems, "第 %d 条事件 kind 不一致：记录 %s，回放 %s"
				% [i, str(a.kind), str(b.kind)])
			continue
		if str(a.cue_id) != str(b.cue_id):
			_push_problem(problems, "第 %d 条 %s 的 cue_id 不一致：记录 %s，回放 %s"
				% [i, str(a.kind), str(a.cue_id), str(b.cue_id)])
		if int(a.time_ms) != int(b.time_ms):
			_push_problem(problems, "第 %d 条 %s 的 time_ms 被改写：记录 %dms，回放 %dms"
				% [i, str(a.kind), int(a.time_ms), int(b.time_ms)])
		if typeof(a.object_id) != typeof(b.object_id) or a.object_id != b.object_id:
			_push_problem(problems, "第 %d 条 %s 的 object_id 不一致：记录 %s(%s)，回放 %s(%s)"
				% [i, str(a.kind), str(a.object_id), type_string(typeof(a.object_id)),
					str(b.object_id), type_string(typeof(b.object_id))])
		# 当帧派发：事件在到达 its time_ms 的那一帧内应用，最多晚一个步长。
		var lag: int = at - int(a.time_ms)
		if lag < 0:
			_push_problem(problems, "第 %d 条 %s 被提前派发：记录 %dms，实际 %dms"
				% [i, str(a.kind), int(a.time_ms), at])
		elif lag > p_step_ms:
			_push_problem(problems, "第 %d 条 %s 派发滞后 %dms（超过一个步长 %dms）"
				% [i, str(a.kind), lag, p_step_ms])

	var detail: String = "派发 %d 条 / 记录 %d 条，逐条 kind·对象·时刻一致" % [got.size(), want.size()]
	return {"problems": problems, "detail": detail}


## 掌声与结局：掌声段数不被改写，结果页判出的结局与记录一致。
##
## 掌声在记录里由 acts 的 has_applause 承载（21 个事件 kind 里没有掌声），
## 结果页据此判两档结局。回放不重新判定合拍度、不产生新分数，
## 所以正确的行为是「读同一份 acts、得同一个结局」。
func _check_applause_and_ending(p_record: Variant, p_stage_id: int,
		p_step_ms: int) -> Dictionary:
	var problems: Array = []
	var acts_before: Array = p_record.acts.duplicate(true)
	var expected_applause: int = 0
	for act in acts_before:
		if bool((act as Dictionary).get("has_applause", false)):
			expected_applause += 1

	var flow: Variant = CResultFlowScript.new()
	# 同 _walk：离线批跑用 delta 时钟源，否则回放永远推不完。
	flow.set_clock_source(CReplayPlayerScript.CLOCK_SOURCE_DELTA)
	if not flow.begin_replay(p_record, p_stage_id):
		return {"problems": ["结果页拒绝进入回放，无法核对掌声与结局"],
			"detail": "进入回放失败", "applause_act_count": expected_applause,
			"ending": &""}

	var duration_ms: int = int(p_record.get_replay_duration_ms())
	var max_steps: int = int(ceil(float(duration_ms) / float(p_step_ms))) + 16
	var steps: int = 0
	while not flow.player_frame().get("is_finished", false) and steps < max_steps:
		flow.advance(float(p_step_ms) / 1000.0)
		steps += 1

	var summary: Dictionary = flow.build_summary()
	if int(summary.get("applause_act_count", -1)) != expected_applause:
		problems.append("掌声段数被改写：记录 %d 段，结果页 %d 段"
			% [expected_applause, int(summary.get("applause_act_count", -1))])

	if p_record.acts != acts_before:
		problems.append("回放改写了记录的 acts——回放必须只读，不得回写记录")

	var expected_ending: StringName = _expected_ending(p_stage_id, expected_applause)
	var got_ending: StringName = StringName(summary.get("ending", &""))
	if got_ending != expected_ending:
		problems.append("结局被改变：记录推出 %s，回放判出 %s"
			% [str(expected_ending), str(got_ending)])

	if int(summary.get("replay_duration_ms", -1)) != duration_ms:
		problems.append("结果页回放时长 %dms 与本关时长 %dms 不一致"
			% [int(summary.get("replay_duration_ms", -1)), duration_ms])

	var detail: String = "掌声 %d 段，结局 %s，与本关记录一致" % [expected_applause, str(got_ending)]
	return {"problems": problems, "detail": detail,
		"applause_act_count": expected_applause, "ending": got_ending}


## 由记录的掌声段数推出应有结局。阈值与常量取自 CResultFlow，不另立一套。
func _expected_ending(p_stage_id: int, p_applause_count: int) -> StringName:
	if p_stage_id != int(CResultFlowScript.STAGE_FINAL):
		return &""
	if p_applause_count >= int(CResultFlowScript.APPLAUSE_THRESHOLD):
		return CResultFlowScript.ENDING_CURTAIN_CALL
	return CResultFlowScript.ENDING_PLAYED_OUT


## 把一项检查的结论记进 checks 与 problems。问题列表为空即通过。
func _append_check(p_checks: Array, p_problems: Array, p_name: String,
		p_check_problems: Array, p_detail: String) -> void:
	var ok: bool = p_check_problems.is_empty()
	p_checks.append(_check_result(p_name, ok, p_detail))
	for msg in p_check_problems:
		p_problems.append("[%s] %s" % [p_name, str(msg)])


func _check_result(p_name: String, p_ok: bool, p_detail: String) -> Dictionary:
	return {"name": p_name, "ok": p_ok, "detail": p_detail}


## 记录问题，但只留前 MAX_PROBLEMS_PER_CHECK 条，其余折叠成计数。
func _push_problem(p_problems: Array, p_message: String) -> void:
	if p_problems.size() < MAX_PROBLEMS_PER_CHECK:
		p_problems.append(p_message)
	elif p_problems.size() == MAX_PROBLEMS_PER_CHECK:
		p_problems.append("……同类问题已省略，详见本次比对的规模")


func _base_stats(p_record: Variant) -> Dictionary:
	return {
		"snapshot_count": p_record.snapshots.size(),
		"event_count": p_record.events.size(),
		"act_count": p_record.acts.size(),
	}


func _report(p_problems: Array, p_checks: Array, p_stats: Dictionary,
		p_stage_id: int, p_duration_ms: int) -> Dictionary:
	return {
		"ok": p_problems.is_empty(),
		"stage_id": p_stage_id,
		"duration_ms": p_duration_ms,
		"problems": p_problems,
		"checks": p_checks,
		"stats": p_stats,
	}


## 把报告渲染成可读文本。供无头探针直接打印。
func describe_report(p_report: Dictionary) -> String:
	var lines: Array = []
	lines.append("回放验收 · 第 %d 关 · 时长 %dms" % [int(p_report.get("stage_id", -1)),
		int(p_report.get("duration_ms", 0))])
	lines.append("")
	for check in p_report.get("checks", []):
		var mark: String = "通过" if bool(check["ok"]) else "未过"
		lines.append("  [%s] %s —— %s" % [mark, str(check["name"]), str(check["detail"])])
	lines.append("")
	var stats: Dictionary = p_report.get("stats", {})
	if not stats.is_empty():
		lines.append("实测：快照 %d 帧 / 事件 %d 条 / 幕 %d 段 / 回放帧 %d / 派发 %d / 离散跳变 %d"
			% [int(stats.get("snapshot_count", 0)), int(stats.get("event_count", 0)),
				int(stats.get("act_count", 0)), int(stats.get("replay_frames", 0)),
				int(stats.get("dispatched_events", 0)), int(stats.get("discrete_tokens", 0))])
	var problems: Array = p_report.get("problems", [])
	if problems.is_empty():
		lines.append("结论：通过 —— 回放与原演出是同一场戏。")
	else:
		lines.append("结论：未通过，共 %d 项问题：" % problems.size())
		for msg in problems:
			lines.append("  - " + str(msg))
	return "\n".join(lines)
