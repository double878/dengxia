extends RefCounted
class_name CMockPerformer
## 模拟演出生成器：造出一场用于验证回放的完整记录，不依赖 A 端 runtime，
## 也不依赖 B 端任何贴图或音频。
##
## 为什么需要它：回放播放器（CReplayPlayer）的验收标准是
## TECH_DESIGN 第 4 节末段——「用一次故意包含快速转身、双手不同姿势、换头、
## 挂起、灯位变化和错拍的演出，比对原演出与幕前回放」。这个验收必须有一个
## 内容已知、边界齐备的输入，否则只能靠人肉看画面判断「像不像」，
## 无法自动化、无法回归。
##
## 本类把那份「刻意设计的演出」固化成可重复生成的代码：
## 每一段的起止时间、动作、事件都是显式写死的，不含随机。
## 同一份代码每次跑出完全相同的记录，因此回放可以逐帧断言。
##
## 与 A 端的关系：本类**不复现 A 的判定规则**，也不建立第二套计时器。
## 它只产出 PerformanceRecord 里该有的内容，用的字段名与 A 端
## PuppetState/LampState.to_dict() 严格一致（见 c_snapshot.gd 的字段表）。
## 谁在何时做了什么，由本类的脚本决定，不由本类去问 A。
##
## 依赖一律用 preload 常量：godot --headless --script 不读全局类名缓存。

const CSnapshotScript := preload("res://scripts/c/c_snapshot.gd")
const CTimedEventScript := preload("res://scripts/c/c_timed_event.gd")
const CPerformanceRecordScript := preload("res://scripts/c/c_performance_record.gd")

## 模拟演出的总时长。取 8 秒而非第一关的 35 秒：
## 验收要能跑得快，又必须装下六个动作段与两次错拍。8 秒足够且便于心算。
const DURATION_MS: int = 8000
const STAGE_ID: int = 1

## 采样步长（毫秒）。取 17ms ≈ 59Hz，贴近真实 60Hz 演出。
## 真实录制实测是 60Hz 输入下每帧全采，跳变补采样会覆盖 30Hz 网格，
## 因此这里也按 17ms 逐帧写入，让回放端面对与实战一致的输入密度。
const STEP_MS: int = 17

## 影人数量，与 CSnapshot.PUPPET_COUNT 一致。
const PUPPET_COUNT: int = 3

## 影人接地点的归一化纵深（stage_pos.y）。
##
## 为什么是 0.5：A 端全工程只有一处给 stage_pos.y 赋值——puppet_controller.gd:99
## 初始化即 Vector2(0.5, 0.5)，此后只有 clamp（puppet_state.gd:55），再无写入。
## 因此真实演出里这个值恒为 0.5。
##
## 早期本类写的是 0.0。0.0 虽在 STAGE_POS_MIN..MAX 之内（合法），但显示端是
## **从接地点向上画身体**（placeholder_puppet.gd:175-182：ground.y - height * 比率），
## 接地点落在画布顶边时整具影人被画到屏幕外——2026-10-05 把它搬上画面时才暴露
## （此前本类的记录只被数值断言消费，从未被渲染过）。
##
## 教训：模拟数据只要沾过显示端，就必须与真实取值对齐，不能只满足 clamp 区间。
const GROUND_Y: float = 0.5

## 三具影人的**基准站位**（stage_pos.x）与**静态姿态**（hand_angle）。
##
## 数值照抄 A 端第一关的真实初始化（stage_def.gd 的 make_level1().initial）：
##   on_stage    = [0, 1, 2]                      三具都在场上
##   positions   = {0: 0.50, 1: 0.13, 2: 0.86}    ← LEVEL1_XUXIAN_X / LEVEL1_XIAOPING_X
##   hand_angles = {0: [0.00, 0.00], 1: [1.20, 1.57], 2: [0.10, 1.20]}
##
## 为什么必须分开站：第一关是**单人**教学关（stage_def.gd:8「单人：站起/移步/抬手/到位」），
## 全场只有 0 号白素贞会动，#1 许仙与 #2 小青**整关静止**——但他们是分开站位的布景：
## 许仙立在 x=0.13、右手举到 90°(π/2≈1.57) 持伞等白素贞来对齐，#2 小青站在舞台最右 x=0.86
## 当折返点路标（两人的挂钩还占满了两个槽位，所以第一关不会产生挂起/取回）。
##
## 早期本类让三具共用同一 x=0.5，于是另外两具与 0 号**完全重叠**：搬上画面后
## 肉眼只数得到「一个人」，把「三具在场」和「三人分开站」两个事实一起抹掉
## （2026-10-05 用户提问「第一关只有一个人吗」时暴露）。
## 手法上与 stage_pos.y 那次同源：**模拟数据只要沾过显示端，就必须与真实取值对齐。**
##
## 注：字典是引用类型，常量本身不可改但内容会被共享，取值时必须 duplicate。
const PUPPET_HOME_X: Array[float] = [0.50, 0.13, 0.86]
const PUPPET_HOME_HAND: Array = [
	{"left": 0.00, "right": 0.00},   # 0 号白素贞：双手自然垂下，要用左手去接伞
	{"left": 1.20, "right": 1.57},   # 1 号许仙：右手举到 90° 持伞（第一关打伞位）
	{"left": 0.10, "right": 1.20},   # 2 号小青：开局站姿，整关不动
]

## 三具影人**开场时的挂起槽位**，-1 表示未挂起（不在挂钩上）。
##
## 照抄 A 端第一关真实布景：`stage_def.gd:161` 的 `initial.hung = {1: 0, 2: 1}`，
## 由 `level1_a_scene.gd:_configure_initial_stage()` 直接写进 `PuppetState.hook_slot`。
##
## 为什么必须有：第一关的两个挂钩从第一帧起就被许仙(1)与小青(2)占满——
## 这正是 `level1_a_scene.gd` 里 `hook_hint_text()` 判定「本关不宣传挂起」的依据，
## 也是「第一关不会产生挂起/取回事件」的原因。若这里留 -1，记录就与真实布景不符。
##
## 注意挂起**不是事件**：A 端开演布景是直接赋值，没有对应的 hook 事件，
## 因此这里也只设初始值，不为它造事件（造了反而是假的）。
const PUPPET_HOME_HOOK: Array[int] = [-1, 0, 1]

## 动作段定义。每一段是 {name, start_ms, end_ms}，端点闭区间。
## 时间轴（共 8000ms）：
##   0-800    停顿        —— 完全静止，验证「停顿不产生跳变补采样」
##   800-2200 左移        —— stage_pos.x 递减
##   2200-3400 快速转身    —— facing 在 400ms 内 0 → +1 → -1
##   3400-4600 双手异姿    —— 左手 -0.5 右手 +0.45，验证双手独立
##   4600-5400 换头 + 挂起 —— head_id 变化，hook_slot 0
##   5400-6600 灯位推拉    —— distance 递减（灯变近）
##   6600-8000 收势停顿    —— 回到静止
##
## 刻意不包含的动作：完整的一次「做对了」动作判定。
## 因为本记录只用于回放验收，而 CPerformanceRecord 的忠实性规则要求
## cue_miss 必须有同 cue_id 的 cue_fire（除非 reason 为 missed_outright）。
## 这里不放 cue_hit，避免造出「合上了却没做」的假记录。
const ACT_SEGMENTS: Array = [
	{"name": "停顿", "start_ms": 0, "end_ms": 800},
	{"name": "左移", "start_ms": 800, "end_ms": 2200},
	{"name": "快速转身", "start_ms": 2200, "end_ms": 3400},
	{"name": "双手异姿", "start_ms": 3400, "end_ms": 4600},
	{"name": "换头挂起", "start_ms": 4600, "end_ms": 5400},
	{"name": "灯位推拉", "start_ms": 5400, "end_ms": 6600},
	{"name": "收势停顿", "start_ms": 6600, "end_ms": 8000},
]

## 换头与挂起发生的时刻。取段内偏后，留出「先到位再换」的视觉顺序。
const HEAD_SWAP_MS: int = 5000
const HOOK_ON_MS: int = 5200

## 两次错拍（cue_fire + cue_miss 并存）的 cue_id 与时刻。
## 放在左移段与灯位段内，错在动作做得到但不合拍的拍点上。
const WRONG_CUES: Array = [
	{"cue_id": "mock_c0_wrong", "beat_ms": 1600, "object_id": 0, "action": "move_left", "offset_ms": 210},
	{"cue_id": "mock_c1_wrong", "beat_ms": 6200, "object_id": 1, "action": "move_right", "offset_ms": -240},
]

## 一次漏做（reason = missed_outright，无 cue_fire）。
## 放在快速转身段内，验证记录里「没做」这件事也留得下痕迹。
const MISSED_CUE: Dictionary = {
	"cue_id": "mock_c2_missed", "beat_ms": 3000, "object_id": 0,
	"action": "stand_up", "offset_ms": 750, "tolerance_ms": 250,
}

## 三幕与掌声。TECH_DESIGN 第 4 节末段的验收要求比对「掌声」，而 21 个事件
## kind 里没有掌声这一种——掌声在记录里由 **acts** 承载（append_act 的
## has_applause），结果页据此判两档结局。故要验收「掌声」就必须写下 acts。
##
## 模式 true/true/false → 有掌声的幕段为 2，正好跨过
## CResultFlow.APPLAUSE_THRESHOLD(=2)，用于验收「结局不变」。
const ACT_APPLAUSE_PATTERN: Array = [true, true, false]


## 生成一场模拟演出的完整记录。
##
## p_stage_id       关卡号。默认第一关；验收「第 5 关两档结局」时传 5。
## p_with_applause  是否写入三幕掌声段，**默认关闭**。
##
## 默认关闭是有意的：切片 6 的结果页测试用「自己 append_act 造出恰好 n 段掌声」
## 的方式构造输入，若本函数也默认写 acts，同一条记录会被叠加两套掌声，
## 那些测试的期望段数全部偏移。验收第 5 关时显式传 true。
##
## 返回 CPerformanceRecord，调用方负责 finish() 与后续释放。
func build(p_stage_id: int = STAGE_ID, p_with_applause: bool = false) -> Variant:
	var record: Variant = CPerformanceRecordScript.new(p_stage_id, DURATION_MS)
	if p_with_applause:
		_append_acts(record)
	_append_events(record, p_stage_id)
	_append_snapshots(record)
	record.finish(DURATION_MS)
	return record


## 三幕与各自的掌声。段落首尾相接覆盖全时长，与 ACT_SEGMENTS 的时间轴无关——
## 幕是「场」的单位，动作段是「动作」的单位，两者不是同一套划分。
func _append_acts(record: Variant) -> void:
	var act_count: int = ACT_APPLAUSE_PATTERN.size()
	var span: int = DURATION_MS / act_count
	for i in act_count:
		var start_ms: int = span * i
		# 末幕延伸到时长的整数末端，避免整除余数在末尾留下空隙。
		var end_ms: int = DURATION_MS if i == act_count - 1 else span * (i + 1)
		record.append_act(i, bool(ACT_APPLAUSE_PATTERN[i]), start_ms, end_ms)


## 事件流。
##
## **必须按 time_ms 升序追加**，这不是风格问题而是正确性问题：
## CPerformanceRecord 在 append_event 里才分配 seq，而 _insert_event_sorted
## 对尚未分配 seq 的事件按 seq=0 参与比较。若这里乱序追加，早插的事件会被
## 后插的更早事件挤到后面，seq 与实际时间轴脱序，validate_invariants
## 会报「events seq 不连续」。因此先收集成 spec 再排序追加。
##
## 同一时刻多条时，按下面的书写顺序追加——cue_fire 必须早于 cue_hit/miss，
## 这条因果顺序靠追加次序保证。
func _append_events(record: Variant, p_stage_id: int = STAGE_ID) -> void:
	var specs: Array = []
	specs.append(_spec(0, &"stage_start", CTimedEventScript.OBJECT_ID_NONE, "",
		{"stage_id": p_stage_id, "duration_ms": DURATION_MS}))

	# 每个动作段起始发一条事件，标明「从这一段开始该动作了」。
	# kind 沿用 A 端已冻结的 21 个里的对应值，不新造 kind。
	specs.append(_spec(800, &"pose_stance", 0, "", {"segment": "左移"}))
	specs.append(_spec(2200, &"facing_turn", 0, "",
		{"from": 0.0, "to": 1.0, "turn_progress": 0.0}))
	specs.append(_spec(2550, &"facing_turn", 0, "",
		{"from": 1.0, "to": -1.0, "turn_progress": 1.0}))
	specs.append(_spec(3400, &"hand_motion", 0, "",
		{"left": -0.5, "right": 0.45}))
	specs.append(_spec(HEAD_SWAP_MS, &"drag_end", 0, "", {"reason": "head_swap"}))
	specs.append(_spec(HOOK_ON_MS, &"drag_begin", 0, "", {"hook_slot": 0}))

	# 灯位推拉：字段名与 A 端 LampState.changed_fields 一致。
	specs.append(_spec(5400, &"lamp_input_changed", "lamp_main", "",
		{"field": "distance", "to": 0.2}))
	specs.append(_spec(6600, &"lamp_input_changed", "lamp_main", "",
		{"field": "distance", "to": 0.8}))

	# 两次错拍：cue_fire 与 cue_miss 并存，payload 不带 missed_outright。
	# 这是 PRD 5.2.3 的忠实性要求——错拍时动作照常发生，
	# 回放要能看到「动作确实做了」这个事实。
	for cue in WRONG_CUES:
		var cue_id: String = str(cue["cue_id"])
		var beat_ms: int = int(cue["beat_ms"])
		var object_id: int = int(cue["object_id"])
		var action: String = str(cue["action"])
		specs.append(_spec(beat_ms - 300, &"cue_hint", object_id, cue_id,
			{"hint_kind": "action", "action": action, "demo_action": action,
			 "target_range": {}, "beat_time_ms": beat_ms}))
		specs.append(_spec(beat_ms - 20, &"cue_fire", object_id, cue_id,
			{"action": action, "metric": 0.0,
			 "window_start_ms": beat_ms - 250, "window_end_ms": beat_ms + 250}))
		specs.append(_spec(beat_ms + int(cue["offset_ms"]), &"cue_miss", object_id, cue_id,
			{"action": action, "offset_ms": int(cue["offset_ms"]),
			 "tolerance_ms": 250, "metric": 0.0}))

	# 一次漏做：只有 cue_miss，且 reason 为 missed_outright。
	# 判别键是 payload.reason——A 端只把 reason 下发到 payload，
	# missed_outright 布尔值留在它内部的 _outcomes 里。
	var missed_beat: int = int(MISSED_CUE["beat_ms"])
	specs.append(_spec(missed_beat - 300, &"cue_hint", int(MISSED_CUE["object_id"]),
		str(MISSED_CUE["cue_id"]),
		{"hint_kind": "action", "action": str(MISSED_CUE["action"]),
		 "demo_action": str(MISSED_CUE["action"]), "target_range": {},
		 "beat_time_ms": missed_beat}))
	specs.append(_spec(missed_beat + int(MISSED_CUE["offset_ms"]), &"cue_miss",
		int(MISSED_CUE["object_id"]), str(MISSED_CUE["cue_id"]),
		{"action": str(MISSED_CUE["action"]), "offset_ms": int(MISSED_CUE["offset_ms"]),
		 "tolerance_ms": int(MISSED_CUE["tolerance_ms"]), "metric": NAN,
		 "reason": "missed_outright"}))

	specs.append(_spec(DURATION_MS, &"stage_end", CTimedEventScript.OBJECT_ID_NONE, "",
		{"song_time_ms": DURATION_MS}))

	# 稳定排序：相同 time_ms 保持书写顺序（Array.sort_custom 不保证稳定，
	# 故用带原始下标的键显式兜住）。
	for i in specs.size():
		specs[i]["_order"] = i
	specs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["time_ms"]) != int(b["time_ms"]):
			return int(a["time_ms"]) < int(b["time_ms"])
		return int(a["_order"]) < int(b["_order"]))

	for spec in specs:
		record.append_event(_event(int(spec["time_ms"]), spec["kind"], spec["object_id"],
			str(spec["cue_id"]), spec["payload"]))


## 一条待写入事件的描述。追加前先排序，seq 由记录分配。
func _spec(time_ms: int, kind: StringName, object_id: Variant, cue_id: String,
		payload: Dictionary) -> Dictionary:
	return {
		"time_ms": time_ms,
		"kind": kind,
		"object_id": object_id,
		"cue_id": cue_id,
		"payload": payload,
	}


## 连续状态。按 STEP_MS 逐帧写入，覆盖 ACT_SEGMENTS 定义的全部动作。
##
## 走 append_snapshot 而非直接操作数组：相位推进、同一时刻去重都在
## CPerformanceRecord 内部，走它的公开入口才是与实战一致的路径。
##
## 末帧处理：8000 不能被 17 整除，逐帧推进会停在 7990，画面上就少了最后 10ms。
## 1:1 回放要求覆盖到时长末端，因此补一帧正好落在 DURATION_MS 上。
func _append_snapshots(record: Variant) -> void:
	var t: int = 0
	while t < DURATION_MS:
		record.append_snapshot(CSnapshotScript.from_views(t, _puppet_views(t), _lamp_view(t)))
		t += STEP_MS
	record.append_snapshot(CSnapshotScript.from_views(
		DURATION_MS, _puppet_views(DURATION_MS), _lamp_view(DURATION_MS)))


## 三具影人的状态视图。字段形状严格照 A 端 PuppetState.to_dict()。
func _puppet_views(now_ms: int) -> Array:
	var out: Array = []
	for i in PUPPET_COUNT:
		out.append(_puppet_view(i, now_ms))
	return out


func _puppet_view(index: int, now_ms: int) -> Dictionary:
	var view: Dictionary = _base_puppet(index)
	# 只有 0 号影人做动作。另两具是**静止布景**——这不是偷懒，而是照第一关的真实编排：
	# 许仙举伞等在那儿、小青站桩当折返点，两人整关一动不动（见 PUPPET_HOME_X 的说明）。
	# 保留「一具动、两具静」同时也有验收价值：回放时能直接看出**动态量被重演、
	# 静态量没有被错误地搅动**（若回放把静止的影人也插值出位移，这里会立刻显形）。
	if index != 0:
		return view

	var segment: Dictionary = _segment_at(now_ms)
	var name: String = str(segment.get("name", ""))
	match name:
		"左移":
			view["stage_pos"] = {"x": _ramp(now_ms, 800, 2200, PUPPET_HOME_X[0], 0.2), "y": GROUND_Y}
		"快速转身":
			# 400ms 内 0 → +1 → -1，是刻意造的「快速转身」。
			# turn_progress 由 facing 绝对值派生，与 A 端 clamp_continuous 一致。
			var phase: float = _phase(now_ms, 2200, 3400)
			var facing: float = 1.0 if phase < 0.5 else -1.0
			view["facing"] = facing
			view["turn_progress"] = absf(facing)
			view["stage_pos"] = {"x": 0.2, "y": GROUND_Y}
		"双手异姿":
			view["hand_angle"] = {"left": -0.5, "right": 0.45}
			view["stage_pos"] = {"x": 0.2, "y": GROUND_Y}
		"换头挂起":
			view["stage_pos"] = {"x": 0.2, "y": GROUND_Y}
		"灯位推拉":
			view["stage_pos"] = {"x": _ramp(now_ms, 5400, 6600, 0.2, 0.8), "y": GROUND_Y}
		"收势停顿":
			# 回到中位站定。
			view["stage_pos"] = {"x": 0.8, "y": GROUND_Y}

	# 换头与挂起是**道具归属**，一旦发生就保持到演出结束。
	#
	# 必须放在 match 之外按时间判断：本函数每帧都从 _base_puppet 重算，
	# 若在各段分支里分别设置，头与钩会在未设置它们的段（灯位推拉）
	# 悄悄回到 -1，下一段再设回来——记录里于是多出两次
	# 「摘头取钩再装回」的假跳变，与「收势不该把东西收回去」的设计意图相悖，
	# 也让换头/挂起在回放里变得不清晰。放在这里，跳变恰好各发生一次。
	if now_ms >= HEAD_SWAP_MS:
		view["head_id"] = 3            # 三个备用头之一
	if now_ms >= HOOK_ON_MS:
		view["hook_slot"] = 0
	return view


## 三具影人的基准视图：未被动作段覆盖前的起始值。
##
## 站位与静态手角**逐具取值**，照 A 端第一关的真实布局（见 PUPPET_HOME_X 的说明）。
## 手角必须 duplicate：常量里的字典是共享引用，直接塞进返回字典会让后续
## 对 0 号手角的写入污染到常量本身，第二次 build() 就生成不出同一份记录了
## （`_test_14_deterministic` 会立刻抓到）。
func _base_puppet(index: int) -> Dictionary:
	var home_hand: Dictionary = PUPPET_HOME_HAND[index]
	return {
		"puppet_id": index,
		"stage_pos": {"x": PUPPET_HOME_X[index], "y": GROUND_Y},
		"stance": 0.0,               # 0.0 = 完全站立（A 端语义，B 已确认）
		"facing": 0.0,
		"turn_progress": 0.0,
		"hand_angle": home_hand.duplicate(true),
		"head_id": -1,               # -1 = 未分配
		"hook_slot": PUPPET_HOME_HOOK[index],  # -1 = 未挂起；1/2 号开局即占满两个挂钩
		"is_controlled": index == 0,
	}


## 油灯状态。四字段语义与 A 端 LampState 一致，B 侧已确认。
func _lamp_view(now_ms: int) -> Dictionary:
	# oil 只随时间单调下降，不可回升——A 端就是这个约束，B 侧照此表现。
	var consumed: float = float(now_ms) / float(DURATION_MS)
	var oil: float = maxf(1.0 - consumed * 0.8, 0.0)
	# distance 越大 = 灯离影人越近（B 已确认这条方向，容易搞反）。
	var distance: float = 0.5
	var segment_name: String = str(_segment_at(now_ms).get("name", ""))
	if segment_name == "灯位推拉":
		distance = _ramp(now_ms, 5400, 6600, 0.5, 0.2)
	elif segment_name == "收势停顿":
		distance = 0.2
	return {
		"distance": distance,
		"exposure": 0.5,
		"oil": oil,
		"flame_feedback": 0.5,
	}


## 构造一条 CTimedEvent。object_id 原样透传：
## 影人事件用 int 0-2，油灯事件用 String "lamp_main"，无对象用 0。
func _event(time_ms: int, kind: StringName, object_id: Variant, cue_id: String,
		payload: Dictionary) -> Variant:
	return CTimedEventScript.new(time_ms, kind, object_id, cue_id, payload)


func _segment_at(now_ms: int) -> Dictionary:
	for seg in ACT_SEGMENTS:
		if now_ms >= int(seg["start_ms"]) and now_ms <= int(seg["end_ms"]):
			return seg
	return {"name": "", "start_ms": 0, "end_ms": 0}


## 归一化进度 0.0-1.0。超出区间会被 clamp，端点处恰为 0 或 1。
func _phase(now_ms: int, start_ms: int, end_ms: int) -> float:
	if end_ms <= start_ms:
		return 1.0
	return clampf(float(now_ms - start_ms) / float(end_ms - start_ms), 0.0, 1.0)


## 线性插值出 from → to。用于位移与灯距这类连续量。
func _ramp(now_ms: int, start_ms: int, end_ms: int, from: float, to: float) -> float:
	return lerpf(from, to, _phase(now_ms, start_ms, end_ms))


## 供测试与文档核对的分段摘要。返回 [{name, start_ms, end_ms}]。
static func segment_plan() -> Array:
	var out: Array = []
	for seg in ACT_SEGMENTS:
		out.append(seg.duplicate(true))
	return out


## 本场可覆盖的验收要素。回放验收脚本据此逐项检查，避免漏掉某一项。
##
## 「掌声」需 build(stage_id, true) 才写入：切片 6 的结果页测试自己构造掌声段，
## 本类默认不写 acts，以免同一条记录被叠加两套掌声（见 build 的说明）。
static func covered_features() -> Array[String]:
	return [
		"停顿", "横向移动", "快速转身", "双手不同姿势",
		"换头", "挂起", "灯位变化", "错拍", "漏做", "掌声",
	]
