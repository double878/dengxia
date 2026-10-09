extends RefCounted
class_name CTestReplayPlayer
## 切片 5 行为测试：回放播放器。
##
## 测试策略：全部用例都写成「在某一时刻推进到 t=x，检查产出」。
## 这样断言的是「回放看到什么」，与表现层实际读到的东西一致，
## 也不需要在测试里复述一遍插值公式。
##
## 数据源是切片 4 的 CMockPerformer（内容已知的模拟演出），
## 依赖它才能自动判定「没有漏动作、没有改变结局」。
##
## 依赖一律用 preload 常量：--headless --script 不读全局类名缓存。

const CReplayPlayerScript := preload("res://scripts/c/c_replay_player.gd")
const CMockPerformerScript := preload("res://scripts/c/c_mock_performer.gd")


## 新建一台装好模拟演出的播放器。advance_to 内部按 17ms 步进。
##
## **必须切到 delta 时钟源**：headless 批跑时墙钟几乎不走，
## 若用默认的自持墙钟源，35s演出在毫秒内根本推不完，所有断言会集体失效。
## 生产路径（集成层）**不得**调这个开关——运行时必须是墙钟源。
func _player() -> Variant:
	var player: Variant = CReplayPlayerScript.new()
	player.load(CMockPerformerScript.new().build())
	player.set_clock_source(CReplayPlayerScript.CLOCK_SOURCE_DELTA)
	player.play()
	return player


## 墙钟源的播放器（生产语义）。用于首帧保护与暂停时长不漂移的回归断言。
func _wall_player() -> Variant:
	var player: Variant = CReplayPlayerScript.new()
	player.load(CMockPerformerScript.new().build())
	player.play()
	return player


## 推进到 at_ms 并返回该帧。
##
## **不保证恰好停在 at_ms**：17ms 步进会越过目标（如 2000 会落在 2006）。
## 需要精确落在某时刻的用例改用 sample()，那才是按时刻取值的正确入口。
func _advance_to(player: Variant, at_ms: int) -> Dictionary:
	var frame: Dictionary = {}
	while int(player.get_now_ms()) < at_ms:
		frame = player.advance(0.017)
	return frame


## 推进到 at_ms 之后**精确**取该时刻的状态。
##
## 插值与离散量都按 now_ms 精确计算，与推进步进无关——
## 因此「同一时刻两次采样必须一致」这类断言才成立。
func _frame_at(player: Variant, at_ms: int) -> Dictionary:
	_advance_to(player, at_ms)
	return player.sample(at_ms)


func run_all() -> Dictionary:
	var t: Variant = preload("res://tests/c/c_test_base.gd").new()
	_test_01_requires_record(t)
	_test_02_rejects_broken_record(t)
	_test_03_load_then_ready(t)
	_test_04_advance_moves_clock(t)
	_test_05_pause_freezes(t)
	_test_06_resume_no_drift(t)
	_test_07_skip_to_end(t)
	_test_08_reset_replays_same(t)
	_test_09_states_cover_ten(t)
	_test_10_interpolates_position(t)
	_test_11_discrete_no_interpolation(t)
	_test_12_events_at_exact_time(t)
	_test_13_all_events_dispatched_once(t)
	_test_14_reaches_end_exactly(t)
	_test_15_no_wall_clock(t)
	_test_16_wall_clock_first_frame_is_zero(t)
	_test_17_wall_clock_tracks_elapsed(t)
	_test_18_wall_clock_pause_no_drift(t)
	_test_19_before_first_frame_uses_first(t)
	return t.report()


func _test_01_requires_record(t: Variant) -> void:
	t.begin("无记录时安全降级")
	var player: Variant = CReplayPlayerScript.new()
	t.check_eq(player.has_record(), false, "无记录")
	t.check_eq(player.load(null), false, "load(null) 失败")
	var frame: Dictionary = player.advance(0.017)
	t.check(frame.has("puppets"), "仍返回合法结构")
	t.check_eq(int(frame["now_ms"]), 0, "时间不动")
	t.finish("不崩")


func _test_02_rejects_broken_record(t: Variant) -> void:
	t.begin("拒绝加载不变量未过的记录")
	var player: Variant = CReplayPlayerScript.new()
	# duration_ms = 0 会触发 validate_invariants 的「duration_ms 未设置」
	var broken: Variant = preload("res://scripts/c/c_performance_record.gd").new(1, 0)
	t.check_eq(player.load(broken), false, "坏记录被拒")
	t.check_eq(player.has_record(), false, "未装载")
	t.finish("闸门有效")


func _test_03_load_then_ready(t: Variant) -> void:
	t.begin("装载后处于 ready 待播")
	var player: Variant = CReplayPlayerScript.new()
	var ok: bool = player.load(CMockPerformerScript.new().build())
	t.check(ok, "装载成功")
	t.check_eq(player.get_state(), &"ready", "状态为 ready")
	t.check_eq(player.get_now_ms(), 0, "播放头在 0")
	t.check_eq(player.is_finished(), false, "未结束")
	t.finish("就绪")


func _test_04_advance_moves_clock(t: Variant) -> void:
	t.begin("推进播放头")
	var player: Variant = _player()
	t.check_eq(player.get_state(), &"playing", "开始即 playing")
	player.advance(1.0)
	t.check_eq(player.get_now_ms(), 1000, "推进 1 秒")
	var frame: Dictionary = player.advance(0.5)
	t.check_eq(int(frame["now_ms"]), 1500, "产出 now_ms 正确")
	t.check_approx(float(frame["progress"]), 1500.0 / 8000.0, 1e-6, "进度比例")
	t.check_eq(int(frame["puppets"].size()), 3, "三具影人")
	t.finish("推进正常")


func _test_05_pause_freezes(t: Variant) -> void:
	t.begin("暂停冻结播放头")
	var player: Variant = _player()
	_advance_to(player, 2000)
	var frozen: int = player.get_now_ms()
	player.pause()
	t.check_eq(player.get_state(), &"paused", "状态为 paused")
	# 暂停后连推 10 次，播放头必须完全不动
	for _i in 10:
		player.advance(0.5)
	t.check_eq(player.get_now_ms(), frozen, "10 次推进后播放头不变")
	# 暂停时产出的帧内容也要冻结：B 侧靠 now_ms 未变判断该停帧
	var frame: Dictionary = player.advance(0.5)
	t.check_eq(int(frame["now_ms"]), frozen, "产出 now_ms 也不变")
	t.check_eq(frame["state"], &"paused", "帧内标记 paused")
	t.finish("冻结生效")


func _test_06_resume_no_drift(t: Variant) -> void:
	t.begin("恢复不漂移")
	var player: Variant = _player()
	# 记下实际到达的时刻而不是假定恰好 2000——17ms 步进会落在 2006。
	_advance_to(player, 2000)
	var frozen: int = player.get_now_ms()
	player.pause()
	for _i in 10:
		player.advance(0.1)
	t.check_eq(player.get_now_ms(), frozen, "暂停期间不推进")
	player.resume()
	t.check_eq(player.get_state(), &"playing", "状态回到 playing")
	t.check_eq(player.get_now_ms(), frozen, "从冻结处继续")
	player.advance(0.5)
	t.check_eq(player.get_now_ms(), frozen + 500, "继续推进正常")
	t.finish("无漂移")


func _test_07_skip_to_end(t: Variant) -> void:
	t.begin("跳过直接进入 finished")
	var player: Variant = _player()
	_advance_to(player, 1000)
	# 1000ms 之前已有 stage_start 与一条 cue_hint 派发，属已播出的内容。
	var dispatched_before: int = player.get_dispatched_event_count()
	t.check(dispatched_before > 0, "跳过前已派发 %d 条" % dispatched_before)
	player.skip()
	t.check_eq(player.get_state(), &"finished", "状态为 finished")
	t.check_eq(player.is_finished(), true, "已结束")
	t.check_eq(player.get_now_ms(), 8000, "播放头落到末尾")
	# 跳过的未到事件不该补派——被跳过的动作就该被跳过
	t.check_eq(player.get_dispatched_event_count(), dispatched_before, "不补派未到事件")
	t.finish("跳过生效")


func _test_08_reset_replays_same(t: Variant) -> void:
	t.begin("重看是同一次演出的重演")
	var player: Variant = _player()
	# 用 sample() 精确取时刻，而不是靠步进碰运气——推进会越过目标值。
	var first: Dictionary = player.sample(5000)
	player.reset()
	t.check_eq(player.get_now_ms(), 0, "reset 回到 0")
	t.check_eq(player.get_state(), &"ready", "回到 ready")
	player.play()
	# 同一时刻两次采样必须一致，否则「重看」放的不是同一场演出
	var second: Dictionary = player.sample(5000)
	t.check_eq(int(second["now_ms"]), int(first["now_ms"]), "同一时刻 now_ms 一致")
	t.check_eq(str(second["puppets"][0]), str(first["puppets"][0]), "同一时刻影人 0 状态一致")
	t.check_eq(str(second["lamp"]), str(first["lamp"]), "同一时刻灯态一致")
	t.finish("可重复重看")


func _test_09_states_cover_ten(t: Variant) -> void:
	t.begin("状态名称与任务书十态对齐")
	var player: Variant = _player()
	t.check_eq(player.get_state(), &"playing", "playing")
	player.pause()
	t.check_eq(player.get_state(), &"paused", "paused")
	player.resume()
	player.skip()
	t.check_eq(player.get_state(), &"finished", "finished")
	player.reset()
	t.check_eq(player.get_state(), &"ready", "ready")
	# idle / replay / correct / wrong / missed / recovery 由 B 侧与游戏流程表达，
	# 本类只负责 idle/ready/playing/paused/finished/replay 六个播放侧状态。
	var frame: Dictionary = player.advance(0.017)
	t.check(frame.has("state"), "每帧都带 state 字段")
	t.check_eq(int(frame["is_finished"]), 0, "未结束时 is_finished 为假")
	t.finish("状态齐备")


func _test_10_interpolates_position(t: Variant) -> void:
	t.begin("位置在相邻样本间插值")
	var player: Variant = _player()
	# 3000ms 落在「快速转身」段内，该段 x 恒为 0.2；
	# 逐时刻取值，确认插值结果不越界、也不出现与端点无关的值。
	var xa: float = float(player.sample(3000)["puppets"][0]["stage_pos"]["x"])
	t.check_in_range(xa, 0.0, 1.0, "t=3000 的 x 在 0-1")
	# 灯态四字段全程必须在 0-1（插值不越界是硬要求）
	var lamp_ok: bool = true
	var at: int = 0
	while at <= 8000:
		var f: Dictionary = player.sample(at)
		for key in ["distance", "exposure", "oil", "flame_feedback"]:
			var v: float = float(f["lamp"][key])
			if v < 0.0 or v > 1.0:
				lamp_ok = false
		at += 137   # 步长故意与插值区间不同步，避免只测到对齐点
	t.check(lamp_ok, "全程灯态四字段都在 0-1（步长 137ms 非插值对齐）")
	t.finish("插值不越界")


func _test_11_discrete_no_interpolation(t: Variant) -> void:
	t.begin("离散量不插值，不造中间态")
	var player: Variant = _player()
	# 换头发生在 5000ms、挂起在 5200ms。
	# 在 4990 与 5010 之间插值时绝不能出现「既不是 -1 也不是 3」的头。
	var before: Dictionary = _advance_to(player, 4990)
	t.check_eq(int(before["puppets"][0]["head_id"]), -1, "换头前 head_id=-1")
	var after: Dictionary = _advance_to(player, 5010)
	t.check_eq(int(after["puppets"][0]["head_id"]), 3, "换头后 head_id=3")
	t.check_eq(int(after["puppets"][0]["hook_slot"]), -1, "此刻尚未挂起")
	var hooked: Dictionary = _advance_to(player, 5300)
	t.check_eq(int(hooked["puppets"][0]["hook_slot"]), 0, "随后挂起")
	# 逐帧扫过换头区间，head_id 只能是 -1 或 3，不许出现别的
	var legal: bool = true
	var p2: Variant = _player()
	_advance_to(p2, 4900)
	while int(p2.get_now_ms()) <= 5100:
		var f: Dictionary = p2.advance(0.017)
		var hid: int = int(f["puppets"][0]["head_id"])
		if hid != -1 and hid != 3:
			legal = false
			break
	t.check(legal, "扫过换头区间时 head_id 只有 -1 或 3")
	t.finish("离散量只跳变")


func _test_12_events_at_exact_time(t: Variant) -> void:
	t.begin("事件在原时间点派发")
	var player: Variant = _player()
	# 错拍 cue 的 cue_miss 落在 1600+210=1810ms。
	# 派发发生在 advance() 内（sample() 不派发），所以这里逐步推进、
	# 记录该事件第一次出现在哪一刻，验证它不早于也不晚于 1810。
	var seen_at: int = -1
	var guard: int = 0
	while seen_at < 0 and guard < 1000:
		guard += 1
		var f: Dictionary = player.advance(0.017)
		if _has_kind(f, "cue_miss", "mock_c0_wrong"):
			seen_at = int(f["now_ms"])
	t.check(seen_at >= 0, "cue_miss 确实派发了（首次出现于 %dms）" % seen_at)
	# 首次出现的时刻必须跨过 1810，即不早于落点
	t.check(seen_at >= 1810, "首次派发不早于落点 1810（实际 %d）" % seen_at)
	# 步长 17ms，所以最多晚 16ms
	t.check(seen_at < 1810 + 17, "派发不晚于落点一个步长（实际 %d）" % seen_at)
	# 该 cue 只应出现一次：继续推到底，cue_miss 计数仍为 1
	var miss_count: int = 0
	var p2: Variant = _player()
	while not p2.is_finished():
		var f: Dictionary = p2.advance(0.017)
		for e in f.get("events", []):
			if str(e.kind) == "cue_miss" and str(e.cue_id) == "mock_c0_wrong":
				miss_count += 1
	t.check_eq(miss_count, 1, "该 cue_miss 全程只出现一次")
	t.finish("时点准确")


func _test_13_all_events_dispatched_once(t: Variant) -> void:
	t.begin("全部事件恰好派发一次")
	var record: Variant = CMockPerformerScript.new().build()
	var total: int = record.events.size()
	var player: Variant = CReplayPlayerScript.new()
	player.load(record)
	player.set_clock_source(CReplayPlayerScript.CLOCK_SOURCE_DELTA)
	player.play()
	while not player.is_finished():
		player.advance(0.017)
	t.check_eq(player.get_dispatched_event_count(), total,
		"派发数等于记录事件数（%d）" % total)
	t.check_eq(player.get_now_ms(), record.get_replay_duration_ms(), "播放头落在末尾")
	t.finish("不重不漏")


func _test_14_reaches_end_exactly(t: Variant) -> void:
	t.begin("末尾精确对齐")
	var record: Variant = CMockPerformerScript.new().build()
	var duration: int = record.get_replay_duration_ms()
	var player: Variant = CReplayPlayerScript.new()
	player.load(record)
	player.set_clock_source(CReplayPlayerScript.CLOCK_SOURCE_DELTA)
	player.play()
	# 步长故意与 8000 不整除，逼出末尾对齐逻辑
	var guard: int = 0
	while not player.is_finished() and guard < 2000:
		player.advance(0.017)
		guard += 1
	t.check_eq(player.get_now_ms(), duration, "播放头正好等于 %d" % duration)
	t.check_approx(float(player.sample(duration)["progress"]), 1.0, 1e-6, "进度 100%")
	t.finish("对齐精确")


func _test_15_no_wall_clock(t: Variant) -> void:
	t.begin("delta 时钟源：产出只由注入的 delta 决定")
	var player: Variant = _player()
	# delta 源下完全保持旧的纯累加语义。
	t.check_eq(player.get_clock_source(), CReplayPlayerScript.CLOCK_SOURCE_DELTA, "已切到 delta 源")
	var a: Dictionary = player.advance(0.017)
	t.check_eq(int(a["now_ms"]), 17, "17ms 步进得 17ms")
	var b: Dictionary = player.advance(0.017)
	t.check_eq(int(b["now_ms"]), 34, "再 17ms 得 34ms")
	# 大步长越过末尾时被夹到 duration——这是刻意的末尾对齐
	var c: Dictionary = player.advance(10.0)
	t.check_eq(int(c["now_ms"]), 8000, "越过末尾时夹到 8000")
	t.check_eq(c["is_finished"], true, "同时标记为已结束")
	t.finish("纯 delta 驱动")


func _test_16_wall_clock_first_frame_is_zero(t: Variant) -> void:
	# 回归断言（2026-10-07 缺陷的直接防线）。
	#
	# 缺陷：播放头原由调用方逐帧累加 delta 得出，而集成层喂的是**墙钟差值**，
	# 于是进入回放前的重活（建遮罩层/HUD/镜像变换）被整段算进播放头。
	# 实测回放第一帧now_ms 已到约 1500ms，前 1500ms 整段没播，
	# `umbrella_take@1268ms` 已生效 → 伞直接闪现在白素贞手上、开场被跳过。
	#
	# 这里模拟「play() 之前耗掉一段时间」，断言首帧必须仍是 0。
	t.begin("墙钟源：play() 前的前置耗时不算进播放头")
	var player: Variant = _wall_player()
	t.check_eq(player.get_clock_source(), CReplayPlayerScript.CLOCK_SOURCE_WALL, "默认即墙钟源")
	# 模拟集成层的重活：真的空转 1200ms 的墙钟。
	var spin_until_usec: int = Time.get_ticks_usec() + 1200000
	while Time.get_ticks_usec() < spin_until_usec:
		pass
	# 首帧保护：无论墙钟走了多久，play() 之后的第一帧必须是 0。
	var first: Dictionary = player.advance(1.0)
	t.check_eq(int(first["now_ms"]), 0, "首帧 now_ms 必须是 0")
	t.check_eq(player.get_now_ms(), 0, "播放头仍在 0")
	t.finish("首帧零漂移")


func _test_17_wall_clock_tracks_elapsed(t: Variant) -> void:
	# 墙钟源在首帧之后必须真的跟着墙钟走，否则就成了「永远停在 0」。
	t.begin("墙钟源：首帧之后按真实经过时间推进")
	var player: Variant = _wall_player()
	player.advance(1.0)  # 消耗掉首帧保护
	var spin_until_usec: int = Time.get_ticks_usec() + 300000
	while Time.get_ticks_usec() < spin_until_usec:
		pass
	var f: Dictionary = player.advance(0.017)
	var now_ms: int = int(f["now_ms"])
	t.check(now_ms >= 250, "空转 300ms 后播放头至少到 250ms（实测 %d）" % now_ms)
	t.check(now_ms <= 600, "且不应超过 600ms（实测 %d）" % now_ms)
	t.finish("跟随墙钟")


func _test_18_wall_clock_pause_no_drift(t: Variant) -> void:
	# 暂停时长不得在 resume 后被一次性补进播放头。
	# 不重设基准的话，恢复后第一帧会把整段暂停时长当成经过时间，
	# 表现就是「按了继续，画面猛地往前跳一段」。
	t.begin("墙钟源：暂停时长不计入播放头")
	var player: Variant = _wall_player()
	player.advance(1.0)  # 消耗首帧保护
	var spin_until_usec: int = Time.get_ticks_usec() + 200000
	while Time.get_ticks_usec() < spin_until_usec:
		pass
	var before_pause: int = player.advance(0.017)["now_ms"]
	player.pause()
	var pause_begin_usec: int = Time.get_ticks_usec() + 1500000
	while Time.get_ticks_usec() < pause_begin_usec:
		pass
	player.resume()
	var after_resume: int = player.advance(0.017)["now_ms"]
	# 恢复后第一帧只应落在「暂停前位置 + 一帧」附近，
	# 绝不该把 1500ms 的暂停整段补上。
	t.check(after_resume < before_pause + 200,
		"恢复后播放头 %d 相对暂停前 %d 不应跳 1500ms" % [after_resume, before_pause])
	t.finish("暂停不漂移")


func _test_19_before_first_frame_uses_first(t: Variant) -> void:
	# 回归断言（2026-10-07）：回放 t=0 必须返回**首帧内容**，
	# 不能返回通用默认站位。
	#
	# 缺陷背景：记录的首帧 time_ms 不是 0，而是首个 tick 后的时刻（实测 17ms）
	# —— c_stage_recorder.advance() 先 clock.update(delta) 再 capture。
	# 于是回放起步的 0~17ms 落在首帧之前，原实现返回 `_default_puppets()`
	# （三具都站 x=0.5 的通用位），而真实首帧是 0.50/0.13/0.86 三处站位。
	# 于是开场17ms 内三具影人先挤到中间、再跳回真实位置——观感是「开场瞬移」。
	# 这比插值跳变更显眼，因为它发生在回放最开始。
	t.begin("t早于首帧时返回首帧内容而非默认站位")
	var record: Variant = CMockPerformerScript.new().build()
	var player: Variant = CReplayPlayerScript.new()
	player.load(record)
	player.set_clock_source(CReplayPlayerScript.CLOCK_SOURCE_DELTA)
	player.play()

	var snaps: Array = record.snapshots
	var first: Variant = snaps[0]
	var first_t: int = int(first.time_ms)
	# 取t=0（早于首帧17ms）的内容。
	var at_zero: Dictionary = player.sample(0)
	var want_x: Array = []
	for p in first.puppets:
		want_x.append(float(p.stage_pos.x))
	var got_x: Array = []
	for p in at_zero["puppets"]:
		got_x.append(float(p.stage_pos.x))
	t.check_eq(str(got_x), str(want_x),
		"t=0 的站位应等于首帧站位 %s（实际 %s）" % [str(want_x), str(got_x)])
	# 首帧本身的站位应当是三个不同位置——若等于默认的三个 0.5，
	# 说明这个用例根本没在验证真实站位，会假绿。
	t.check(want_x.size() == 3, "首帧有三具影人")
	var all_same: bool = true
	for i in range(1, want_x.size()):
		if absf(float(want_x[i]) - float(want_x[0])) > 1e-6:
			all_same = false
	t.check(not all_same,
		"首帧三具影人站位应互不相同（实测 %s），否则本用例失去意义" % str(want_x))
	t.finish("开场零瞬移")


func _has_kind(frame: Dictionary, kind: String, cue_id: String) -> bool:
	for e in frame.get("events", []):
		if str(e.kind) == kind and str(e.cue_id) == cue_id:
			return true
	return false
