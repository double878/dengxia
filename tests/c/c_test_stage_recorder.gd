extends RefCounted
class_name CTestStageRecorder
## 切片 3 行为测试：CStageRecorder 接线层。
##
## 本套件验证的是**顺序与生命周期**，不是采样算法本身——
## 后者由 c_test_recorder.gd 与 c_test_record.gd 各自负责。
## 接线层唯一需要证明的正确性是：tick 一定在 capture 之前、
## begin/finish 各只生效一次、暂停时冻结、结束后不再追加。
##
## 数据源是内联假 runtime，字段路径与 A 端 Level1Runtime 一致。
## 依赖一律用 preload 常量：--headless --script 不读全局类名缓存。

const CStageRecorderScript := preload("res://scripts/c/c_stage_recorder.gd")


## 假时钟：暴露 get_song_time_ms() 与 update()，可暂停（读数冻结），可倒退（测异常检测）。
class FakeClock:
	var now_ms: int = 0
	var paused: bool = false
	## update() 调用次数。接线层必须调它，否则时间永不前进
	## ——真实 A 端的 MusicClock 也是只在 update() 里推进。
	var update_count: int = 0
	## 测试专用：置 true 后 update() 不再推进时间，用于构造时钟倒退。
	var freeze: bool = false
	func get_song_time_ms() -> int:
		return now_ms
	func update(delta: float) -> void:
		update_count += 1
		if freeze:
			return
		advance(float(delta) * 1000.0)
	func advance(ms: float) -> void:
		if not paused:
			now_ms += int(ms)


class FakePuppet:
	var _id: int = 0
	## 每次 tick 变化的字段名，让状态可被跳变检测捕获。
	var stance: float = 0.0
	func _init(id: int) -> void:
		_id = id
	func to_dict() -> Dictionary:
		return {
			"puppet_id": _id,
			"stage_pos": {"x": 0.5, "y": 0.0},
			"stance": stance, "facing": 0.0, "turn_progress": 0.0,
			"hand_angle": {"left": 0.0, "right": 0.0},
			"head_id": -1, "hook_slot": -1, "is_controlled": false,
		}


class FakeLamp:
	var distance: float = 0.5
	var exposure: float = 0.5
	var oil: float = 1.0
	var flame_feedback: float = 0.5
	func to_dict() -> Dictionary:
		return {
			"distance": distance, "exposure": exposure,
			"oil": oil, "flame_feedback": flame_feedback,
		}


class FakePuppetController:
	var puppets: Array = []
	func _init() -> void:
		for i in 3:
			puppets.append(FakePuppet.new(i))


class FakeLampController:
	var lamp: Variant = null
	func _init() -> void:
		lamp = FakeLamp.new()


## 假 runtime：字段与行为对齐 A 端 Level1Runtime。
## tick() 内部模拟真实顺序：先推进时钟与状态，再吐出本帧事件。
class FakeRuntime:
	var clock: Variant = null
	var puppet_controller: Variant = null
	var lamp_controller: Variant = null
	var events: Array = []
	## 事件在每次 tick 后自动补一条 oil_changed，模拟 A 端 lamp 的高频行为。
	var auto_event: bool = false
	var over: bool = false
	## tick 调用计数，用于验证顺序。
	var tick_count: int = 0
	## 每次 tick 递增，用于让状态产生跳变。
	var _t: int = 0

	func _init() -> void:
		clock = FakeClock.new()
		puppet_controller = FakePuppetController.new()
		lamp_controller = FakeLampController.new()

	func is_over() -> bool:
		return over

	func tick(delta: float) -> void:
		tick_count += 1
		# 时钟由 clock.update() 推进（接线层负责调用），tick 只管状态与事件——
		# 分工照抄真实 A 端：MusicClock.update 推进时间，runtime.tick 消费时间。
		if clock.paused:
			return
		_t += 1
		# 状态随 tick 变化 → 触发跳变补采样，贴近真实演出。
		for p in puppet_controller.puppets:
			p.stance = float(_t) * 0.001
		lamp_controller.lamp.oil = maxf(0.0, 1.0 - float(_t) * 0.0005)
		if auto_event:
			events.append({
				"time_ms": clock.now_ms, "kind": "lamp_oil_changed",
				"object_id": "lamp_main", "cue_id": "",
				"payload": {"oil": lamp_controller.lamp.oil},
			})

	func take_events() -> Array:
		var out: Array = events.duplicate(true)
		events.clear()
		return out


func run_all() -> Dictionary:
	var t: Variant = preload("res://tests/c/c_test_base.gd").new()
	_test_01_advance_without_begin_is_safe(t)
	_test_02_begin_then_advance_records(t)
	_test_03_tick_before_capture(t)
	_test_04_events_captured_each_frame(t)
	_test_05_paused_no_append(t)
	_test_06_finish_freezes(t)
	_test_07_finish_idempotent(t)
	_test_08_is_over_auto_finish(t)
	_test_09_record_readable_after_finish(t)
	_test_10_discard_releases(t)
	_test_11_validate_gate(t)
	_test_12_stats(t)
	_test_13_null_runtime_safe(t)
	_test_14_backwards_clock_counted(t)
	return t.report()


func _test_01_advance_without_begin_is_safe(t: Variant) -> void:
	t.begin("未 begin 就 advance 安全降级")
	var sr: Variant = CStageRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	var wrote: int = sr.advance(rt, 0.017)
	t.check_eq(wrote, 0, "不写入任何快照")
	t.check_eq(rt.tick_count, 0, "也不会调 A 端 tick")
	t.check_eq(sr.get_record(), null, "get_record 为 null")
	t.check_eq(sr.is_begun(), false, "is_begun 为假")
	t.finish("未 begin 不会静默丢数据之外的行为")


func _test_02_begin_then_advance_records(t: Variant) -> void:
	t.begin("begin 后 advance 正常录制")
	var sr: Variant = CStageRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	sr.begin(1, 35000)
	t.check(sr.get_record() != null, "begin 后有记录")
	var wrote: int = sr.advance(rt, 0.017)
	t.check_eq(wrote, 1, "首帧写入一个快照")
	t.check_eq(rt.tick_count, 1, "tick 被调用一次")
	# 接线层必须自己推进时钟：漏掉 clock.update() 时，
	# MusicClock 的歌曲时间停在 0，表现为「跑满帧数但末帧 t=0」。
	t.check_eq(rt.clock.update_count, 1, "时钟被推进一次")
	t.check_eq(sr.get_stats().get("frame_count"), 1, "帧计数 1")
	t.finish("正常录制")


func _test_03_tick_before_capture(t: Variant) -> void:
	t.begin("tick 必须先于 capture（核心顺序约束）")
	var sr: Variant = CStageRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	sr.begin(1, 35000)
	sr.advance(rt, 0.017)
	var rec: Variant = sr.get_record()
	# 接线层每帧推进时钟 17ms，tick 再改变 stance。
	# 若 capture 早于 tick，快照的 time_ms 会是 0、stance 会是初始值。
	t.check_eq(rec.snapshots[0].time_ms, 17, "快照时间是 tick 后的 17ms 而非 0")
	t.check(rec.snapshots[0].puppets[0].stance > 0.0, "影人状态是 tick 后的新值")
	t.finish("顺序正确：先 tick 再采")


func _test_04_events_captured_each_frame(t: Variant) -> void:
	t.begin("每帧取一次事件，不重不漏")
	var sr: Variant = CStageRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rt.auto_event = true
	sr.begin(1, 35000)
	for _i in 5:
		sr.advance(rt, 0.017)
	var rec: Variant = sr.get_record()
	t.check_eq(rec.events.size(), 5, "5 帧各一条事件")
	t.check_eq(rec.events[0].kind, "lamp_oil_changed", "kind 正确")
	t.check_eq(rec.events[0].object_id, "lamp_main", "灯事件 object_id 为字符串命名空间")
	t.check_eq(rec.events[0].seq, 1, "seq 从 1 开始")
	t.check_eq(rec.events[4].seq, 5, "seq 连续到 5")
	t.finish("事件流完整")


func _test_05_paused_no_append(t: Variant) -> void:
	t.begin("暂停冻结：不追加")
	var sr: Variant = CStageRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rt.auto_event = true
	sr.begin(1, 35000)
	for _i in 3:
		sr.advance(rt, 0.017)
	rt.clock.paused = true
	var before_snaps: int = sr.get_record().snapshots.size()
	var before_events: int = sr.get_record().events.size()
	for _i in 10:
		sr.advance(rt, 0.017)
	var rec: Variant = sr.get_record()
	t.check_eq(rec.snapshots.size(), before_snaps, "暂停期间快照不增加")
	t.check_eq(rec.events.size(), before_events, "暂停期间事件不增加")
	t.finish("暂停冻结")


func _test_06_finish_freezes(t: Variant) -> void:
	t.begin("finish 后冻结")
	var sr: Variant = CStageRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rt.auto_event = true
	sr.begin(1, 35000)
	sr.advance(rt, 0.017)
	sr.finish()
	t.check_eq(sr.is_finished(), true, "已收尾")
	t.check_eq(sr.get_record()._finished, true, "底层记录已冻结")
	# finish 之后继续 advance：应报错且不追加
	for _i in 3:
		sr.advance(rt, 0.017)
	t.check_eq(sr.get_record().events.size(), 1, "收尾后事件不再追加")
	t.finish("冻结生效")


func _test_07_finish_idempotent(t: Variant) -> void:
	t.begin("重复 finish 幂等")
	var sr: Variant = CStageRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	sr.begin(1, 35000)
	sr.advance(rt, 0.017)
	sr.finish()
	sr.finish()
	sr.finish(12000)
	t.check_eq(sr.is_finished(), true, "仍是收尾态")
	t.check_eq(sr.get_record().snapshots.size(), 1, "快照数不受影响")
	t.finish("幂等")


func _test_08_is_over_auto_finish(t: Variant) -> void:
	t.begin("runtime 报告结束时自动 finish")
	var sr: Variant = CStageRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rt.auto_event = true
	sr.begin(1, 35000)
	sr.advance(rt, 0.017)
	t.check_eq(sr.is_finished(), false, "尚未结束")
	rt.over = true
	# 结束当帧仍要采到数据（stage_end 与末帧都在这一帧产生），
	# 因此本帧写入 0 条新增，但事件应被收下。
	sr.advance(rt, 0.017)
	t.check_eq(sr.is_finished(), true, "is_over 后自动收尾")
	t.check_eq(sr.get_record().events.size(), 2, "收尾当帧的事件已记下")
	t.finish("自动收尾且不丢最后一帧")


func _test_09_record_readable_after_finish(t: Variant) -> void:
	t.begin("finish 后记录仍可读（回放端需要）")
	var sr: Variant = CStageRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	sr.begin(1, 35000)
	sr.advance(rt, 0.017)
	sr.finish()
	var rec: Variant = sr.get_record()
	t.check(rec != null, "finish 不释放记录")
	t.check_eq(rec.snapshots.size(), 1, "快照仍可读")
	t.check_eq(rec.get_replay_duration_ms(), 35000, "回放时长仍可取")
	t.finish("回放端能拿到数据")


func _test_10_discard_releases(t: Variant) -> void:
	t.begin("discard 释放记录")
	var sr: Variant = CStageRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	sr.begin(1, 35000)
	sr.advance(rt, 0.017)
	sr.finish()
	sr.discard()
	t.check_eq(sr.get_record(), null, "记录已释放")
	t.check_eq(sr.is_begun(), false, "回到未开始态")
	t.check_eq(sr.get_stats().size(), 0, "统计已清空")
	# 释放后应可重新 begin 一关
	sr.begin(2, 35000)
	t.check(sr.get_record() != null, "可开始新的一关")
	t.finish("生命周期完整")


func _test_11_validate_gate(t: Variant) -> void:
	t.begin("回放准入闸门")
	var sr: Variant = CStageRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	sr.begin(1, 35000)
	t.check_eq(sr.is_ready_for_replay(), false, "未收尾不可回放")
	sr.advance(rt, 0.017)
	sr.finish()
	t.check_eq(sr.is_ready_for_replay(), true, "收尾且不变量通过即可回放")
	t.check_eq((sr.validate() as Array).size(), 0, "不变量自检为空")
	# 破坏时长后应被闸门拦住
	var broken: Variant = CStageRecorderScript.new()
	broken.begin(1, 0)
	broken.advance(FakeRuntime.new(), 0.017)
	broken.finish()
	t.check_eq(broken.is_ready_for_replay(), false, "不变量不通过时拦住回放")
	t.check((broken.validate() as Array).size() > 0, "给出具体问题")
	t.finish("闸门有效")


func _test_12_stats(t: Variant) -> void:
	t.begin("统计信息")
	var sr: Variant = CStageRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rt.auto_event = true
	sr.begin(1, 35000)
	for _i in 4:
		sr.advance(rt, 0.017)
	sr.finish()
	var s: Dictionary = sr.get_stats()
	t.check_eq(s.get("stage_id"), 1, "关卡号透传")
	t.check_eq(s.get("duration_ms"), 35000, "时长透传")
	t.check_eq(s.get("frame_count"), 4, "帧计数 4")
	t.check_eq(s.get("finished"), true, "收尾标志")
	t.check(s.get("snapshot_bytes_estimate") > 0, "给出量级估计")
	t.check(s.has("backwards_clock_count"), "含时钟倒退计数")
	t.finish("统计完整")


func _test_13_null_runtime_safe(t: Variant) -> void:
	t.begin("null runtime 安全降级")
	var sr: Variant = CStageRecorderScript.new()
	sr.begin(1, 35000)
	var wrote: int = sr.advance(null, 0.017)
	t.check_eq(wrote, 0, "不写入")
	t.check_eq(sr.get_record().snapshots.size(), 0, "快照数仍为 0")
	t.finish("空数据源不崩")


func _test_14_backwards_clock_counted(t: Variant) -> void:
	t.begin("时钟倒退被计入统计")
	var sr: Variant = CStageRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	sr.begin(1, 35000)
	sr.advance(rt, 0.017)
	# 让本次 update 不推进时钟（模拟上游把 song_time 拨回），
	# 再把读数改小。必须在 advance() 之前设置，因为
	# 接线层每帧都会调 clock.update()，advance() 之后的改动会被下一次调用抹平。
	rt.clock.freeze = true
	rt.clock.now_ms = 5
	sr.advance(rt, 0.017)
	t.check_eq(sr.get_stats().get("backwards_clock_count"), 1, "倒退被记录")
	t.finish("异常可观测")
