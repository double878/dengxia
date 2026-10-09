extends RefCounted
class_name CTestRecorder
## 切片 2 行为测试：CRecorder 接真实数据源。
##
## 数据源不再是 stub，而是一个内联的假 runtime，其字段路径与 A 端
## Level1Runtime 完全一致（puppet_controller.puppets / lamp_controller.lamp /
## clock.get_song_time_ms / take_events）。字段名照 A 端真实接口，不另立契约。
##
## 依赖一律用 preload 常量：--headless --script 不读全局类名缓存。

const CRecorderScript := preload("res://scripts/c/c_recorder.gd")


## 假时钟：只暴露 get_song_time_ms()，可暂停（读数冻结）。
class FakeClock:
	var now_ms: int = 0
	var paused: bool = false
	func get_song_time_ms() -> int:
		return now_ms
	func advance(ms: int) -> void:
		if not paused:
			now_ms += ms


## 会补救冻结的假时钟。语义照抄 A 端 MusicClock（music_clock.gd:84-95）：
## 冻结时 `get_song_time_ms()` **停住**，而 `get_real_time_ms()` 照常前进。
## 这是 2026-10-07 用户要求「补救过程也要录像」时暴露的缺陷根源——
## 只读歌曲时间会把整段补救钉在同一毫秒上，回放即闪现。
class FreezeClock:
	var song_ms: int = 0
	var real_ms: int = 0
	var frozen: bool = false
	func get_song_time_ms() -> int:
		return song_ms
	func get_real_time_ms() -> int:
		return real_ms
	func advance(ms: int) -> void:
		real_ms += ms
		if not frozen:
			song_ms += ms
	func set_frozen(value: bool) -> void:
		frozen = value


## 假影人状态：to_dict() 字段形状与 A 端 PuppetState 一致。
class FakePuppet:
	var _id: int = 0
	func _init(id: int) -> void:
		_id = id
	func to_dict() -> Dictionary:
		return {
			"puppet_id": _id,
			"stage_pos": {"x": 0.5, "y": 0.0},
			"stance": 0.0, "facing": 0.0, "turn_progress": 0.0,
			"hand_angle": {"left": 0.0, "right": 0.0},
			"head_id": -1, "hook_slot": -1, "is_controlled": false,
		}


## 假灯态：to_dict() 字段与 A 端 LampState 一致。
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


## 假 runtime：字段路径与 A 端 Level1Runtime 一致。
class FakeRuntime:
	var clock: Variant = null
	var puppet_controller: Variant = null
	var lamp_controller: Variant = null
	var events: Array = []
	func _init() -> void:
		clock = FakeClock.new()
		puppet_controller = FakePuppetController.new()
		lamp_controller = FakeLampController.new()
	func take_events() -> Array:
		var out: Array = events.duplicate(true)
		events.clear()
		return out


## 同 FakeRuntime，但时钟换成 FreezeClock（用于补救冻结用例）。
class FreezeRuntime:
	var clock: Variant = null
	var puppet_controller: Variant = null
	var lamp_controller: Variant = null
	var events: Array = []
	func _init() -> void:
		clock = FreezeClock.new()
		puppet_controller = FakePuppetController.new()
		lamp_controller = FakeLampController.new()
	func take_events() -> Array:
		var out: Array = events.duplicate(true)
		events.clear()
		return out


func run_all() -> Dictionary:
	var t: Variant = preload("res://tests/c/c_test_base.gd").new()
	_test_01_begin_creates_record(t)
	_test_02_capture_states_reads_runtime(t)
	_test_03_capture_states_uses_clock(t)
	_test_04_capture_events_writes_seq(t)
	_test_05_take_events_cleared(t)
	_test_06_lamp_event_string_object_id(t)
	_test_07_puppet_event_int_object_id(t)
	_test_08_lamp_oil_every_frame_no_throttle(t)
	_test_09_distance_recorded_verbatim(t)
	_test_10_paused_clock_no_append(t)
	_test_11_backwards_clock_detected(t)
	_test_12_jump_triggers_extra_sample(t)
	_test_13_finish_uses_duration(t)
	_test_14_no_begin_safe(t)
	_test_15_stats(t)
	_test_16_last_frame_clamped(t)
	_test_17_freeze_snapshots_keep_moving(t)
	_test_18_freeze_unfreeze_monotonic(t)
	_test_19_freeze_events_share_timeline(t)
	_test_20_freeze_overrun_clamped(t)
	_test_21_late_events_clamped_after_compensation(t)
	return t.report()


func _test_01_begin_creates_record(t: Variant) -> void:
	t.begin("begin 创建记录")
	var rec: Variant = CRecorderScript.new()
	var r: Variant = rec.begin(1, 35000)
	t.check(r != null, "返回记录对象")
	t.check_eq(r.duration_ms, 35000, "时长透传")
	t.check_eq(rec.get_record(), r, "get_record 一致")
	t.finish("begin 正确")


func _test_02_capture_states_reads_runtime(t: Variant) -> void:
	t.begin("capture_states 从 runtime 读三影人视图")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rec.begin(1, 35000)
	var ok: bool = rec.capture_states(rt)
	t.check(ok, "首帧写入成功")
	var r: Variant = rec.get_record()
	t.check_eq(r.snapshots.size(), 1, "快照数 1")
	t.check_eq(r.snapshots[0].puppets.size(), 3, "puppets 定长 3")
	t.check_eq(int(r.snapshots[0].puppets[2]["puppet_id"]), 2, "下标对齐")
	t.finish("状态采集正确")


func _test_03_capture_states_uses_clock(t: Variant) -> void:
	t.begin("capture_states 用 clock 读歌曲时间，不用墙钟")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rec.begin(1, 35000)
	rt.clock.advance(1000)
	rec.capture_states(rt)
	t.check_eq(rec.get_record().snapshots[0].time_ms, 1000, "time_ms 来自 clock")
	# 推进到跨越 33333μs 定频相位点（下一次采样整点约在 1033ms 之后），
	# 只推进 33ms 会差约 1μs 落在网格外，故推进到 1100ms 确保越过。
	rt.clock.advance(100)
	rec.capture_states(rt)
	t.check_eq(rec.get_record().snapshots.size(), 2, "第二帧写入")
	t.check_eq(rec.get_record().snapshots[1].time_ms, 1100, "第二帧时间来自 clock")
	t.finish("时钟来源正确")


func _test_04_capture_events_writes_seq(t: Variant) -> void:
	t.begin("capture_events 写入并分配 seq")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rec.begin(1, 35000)
	rt.events = [
		{"time_ms": 100, "kind": "cue_fire", "object_id": 0, "cue_id": "c1", "payload": {"kind": "cue_fire"}},
		{"time_ms": 200, "kind": "cue_hit", "object_id": 0, "cue_id": "c1", "payload": {"kind": "cue_hit"}},
	]
	var n: int = rec.capture_events(rt)
	t.check_eq(n, 2, "两条写入")
	t.check_eq(int(rec.get_record().events[0].seq), 1, "seq 从 1")
	t.check_eq(int(rec.get_record().events[1].seq), 2, "seq 递增")
	t.finish("事件采集正确")


func _test_05_take_events_cleared(t: Variant) -> void:
	t.begin("事件取走即清空，不重复记录")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rec.begin(1, 35000)
	rt.events = [{"time_ms": 100, "kind": "cue_fire", "object_id": 0, "cue_id": "c1", "payload": {}}]
	rec.capture_events(rt)
	var n2: int = rec.capture_events(rt)
	t.check_eq(n2, 0, "第二帧取到 0 条")
	t.check_eq(rec.get_record().events.size(), 1, "记录里仍只有 1 条")
	t.finish("取走即清空生效")


func _test_06_lamp_event_string_object_id(t: Variant) -> void:
	t.begin("灯事件：String object_id 原样透传不转 int")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rec.begin(1, 35000)
	rt.events = [{
		"time_ms": 50, "kind": "lamp_oil_changed",
		"object_id": "lamp_main", "cue_id": "", "payload": {"kind": "lamp_oil_changed"},
	}]
	var n: int = rec.capture_events(rt)
	t.check_eq(n, 1, "灯事件成功写入（未被 int 强转毁掉）")
	t.check_eq(typeof(rec.get_record().events[0].object_id), TYPE_STRING, "object_id 仍是 String")
	t.check_eq(str(rec.get_record().events[0].object_id), "lamp_main", "值保持 lamp_main")
	t.finish("灯事件命名空间保真")


func _test_07_puppet_event_int_object_id(t: Variant) -> void:
	t.begin("影人事件：int object_id 正常")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rec.begin(1, 35000)
	rt.events = [{"time_ms": 100, "kind": "pose_stance", "object_id": 1, "cue_id": "", "payload": {}}]
	var n: int = rec.capture_events(rt)
	t.check_eq(n, 1, "影人事件写入")
	t.check_eq(int(rec.get_record().events[0].object_id), 1, "object_id 为 1")
	t.finish("影人命名空间正常")


func _test_08_lamp_oil_every_frame_no_throttle(t: Variant) -> void:
	t.begin("lamp_oil_changed 每帧一条，不节流")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rec.begin(1, 35000)
	for i in 10:
		rt.events = [{
			"time_ms": 100 + i * 33, "kind": "lamp_oil_changed",
			"object_id": "lamp_main", "cue_id": "", "payload": {},
		}]
		rec.capture_events(rt)
	t.check_eq(rec.get_record().events.size(), 10, "10 帧全量记录 10 条，无节流")
	t.finish("灯油事件不节流")


func _test_09_distance_recorded_verbatim(t: Variant) -> void:
	t.begin("distance 原样记录（越大=灯越近的语义由数值承载）")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rec.begin(1, 35000)
	rt.lamp_controller.lamp.distance = 0.9
	rec.capture_states(rt)
	t.check_approx(float(rec.get_record().snapshots[0].lamp["distance"]), 0.9, 1e-9,
		"distance 原样落盘，不做方向换算")
	t.finish("distance 保真")


func _test_10_paused_clock_no_append(t: Variant) -> void:
	t.begin("暂停冻结：时钟不动则不追加")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rec.begin(1, 35000)
	rec.capture_states(rt)
	var n1: int = rec.get_record().snapshots.size()
	rt.clock.paused = true
	rt.clock.advance(1000)  # 暂停时不推进
	rec.capture_states(rt)
	var n2: int = rec.get_record().snapshots.size()
	t.check_eq(n2, n1, "暂停期间不追加新快照")
	t.finish("暂停冻结正确")


func _test_11_backwards_clock_detected(t: Variant) -> void:
	t.begin("时钟倒退被计数")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rec.begin(1, 35000)
	rt.clock.advance(1000)
	rec.capture_states(rt)
	rt.clock.now_ms = 500  # 人为倒退
	rec.capture_states(rt)
	t.check_eq(int(rec.get_stats().get("backwards_clock_count", -1)), 1, "记到 1 次倒退")
	t.finish("倒退检测生效")


func _test_12_jump_triggers_extra_sample(t: Variant) -> void:
	t.begin("跳变补采样：字段变化当帧追加")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rec.begin(1, 35000)
	rec.capture_states(rt)  # t=0
	rt.clock.advance(10)    # 不到 33ms 定频点
	rt.lamp_controller.lamp.flame_feedback = 0.99  # 触发跳变
	var ok: bool = rec.capture_states(rt)
	t.check(ok, "跳变帧被写入（虽未到定频点）")
	t.check_eq(rec.get_record().snapshots.size(), 2, "共 2 帧")
	t.finish("跳变补采样生效")


func _test_13_finish_uses_duration(t: Variant) -> void:
	t.begin("finish 时长以 duration_ms 为准")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rec.begin(1, 35000)
	rec.capture_states(rt)
	rec.finish(34990)
	t.check_eq(rec.get_record().get_replay_duration_ms(), 35000, "用 35000 而非末帧时间")
	t.finish("时长口径正确")


func _test_14_no_begin_safe(t: Variant) -> void:
	t.begin("未 begin 时调用安全不崩")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	t.check(not rec.capture_states(rt), "capture_states 返回 false")
	t.check_eq(rec.capture_events(rt), 0, "capture_events 返回 0")
	t.finish("未初始化安全降级")


func _test_15_stats(t: Variant) -> void:
	t.begin("统计信息")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rec.begin(1, 35000)
	rec.capture_states(rt)
	rt.events = [{"time_ms": 100, "kind": "stage_start", "object_id": 0, "cue_id": "", "payload": {}}]
	rec.capture_events(rt)
	var s: Dictionary = rec.get_stats()
	t.check_eq(int(s.get("snapshot_count", -1)), 1, "快照数")
	t.check_eq(int(s.get("event_count", -1)), 1, "事件数")
	t.check_eq(bool(s.get("stage_started", false)), true, "stage_start 已记录")
	t.finish("统计正确")


## 2026-10-05 实测真 runtime 暴露的收尾缺陷的回归测试。
##
## A 的 MusicClock 是**不钳制的自由秒表**（get_song_time_ms 直接返回 max(_free_s,0)），
## 而末帧的推进步长除不尽（35000 不是 16.67ms 的整数倍），所以收尾帧常读到 35007。
## A 自己对**事件**时间做了钳制（level1_runtime.gd:114），对时钟读数没有。
## 不钳的话 snapshot.time_ms 越界 → 整份记录被 validate_invariants 判非法 →
## 准入闸门关闭 → **回放直接进不去**（第一次真 runtime 录制就是这样挂的）。
func _test_16_last_frame_clamped(t: Variant) -> void:
	t.begin("收尾帧时间钳制：时钟越过本关时长时钳到 duration_ms")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FakeRuntime.new()
	rec.begin(1, 35000)
	rt.clock.now_ms = 34990
	rec.capture_states(rt)
	t.check_eq(int(rec.get_record().snapshots[0].time_ms), 34990, "未越界的帧原样记录")

	rt.clock.now_ms = 35007  # 收尾帧：越过 duration_ms
	rt.lamp_controller.lamp.oil = 0.5  # 制造跳变，确保这一帧会被采样
	rec.capture_states(rt)
	t.check_eq(rec.get_record().snapshots.size(), 2, "收尾帧写入")
	t.check_eq(int(rec.get_record().snapshots[1].time_ms), 35000, "越界值被钳到 35000")
	t.check(rec.get_record().validate_invariants().is_empty(),
		"整份记录通过不变量自检（回放准入闸门据此放行）")

	# 同一时刻不得写出第二条，否则 time_ms 非递增同样会被判非法。
	rec.capture_states(rt)
	t.check_eq(rec.get_record().snapshots.size(), 2, "同一时刻不重复追加")
	t.finish("末帧钳制生效")


## 2026-10-07 用户要求「补救过程也要录像」的回归测试。
##
## 缺陷根因：A 端 MusicClock 在补救冻结时 `return false`（music_clock.gd:89-95），
## **歌曲时间停住、真实时间照走**。CRecorder 原本只读 get_song_time_ms()，
## 于是冻结期里 runtime 仍在推进（灯油每帧消耗、补救动作演出），
## 可所有快照都被钉在同一个 time_ms —— 回放时整段补救压进一帧，观感就是闪现。
## 探针指纹：「快照数不变、事件数持续递增」（用户日志 t=1503ms 快照 81 / 事件 170→260）。
func _test_17_freeze_snapshots_keep_moving(t: Variant) -> void:
	t.begin("补救冻结期快照按真实时长继续推进")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FreezeRuntime.new()
	rec.begin(0, 35000)

	# 正常演出 1 秒。
	for i in 10:
		rt.clock.advance(100)
		rt.lamp_controller.lamp.oil = 1.0 - float(i) * 0.01  # 每帧跳变，确保被采样
		rec.capture_states(rt)
	var before_freeze: int = rec.get_record().snapshots.size()
	t.check(before_freeze > 0, "冻结前已采到快照（%d 帧）" % before_freeze)

	# 冻结 1 秒：歌曲时间停住，真实时间走 10 帧。
	rt.clock.set_frozen(true)
	for i in 10:
		rt.clock.advance(100)
		rt.lamp_controller.lamp.oil = 0.5 - float(i) * 0.01
		rec.capture_states(rt)

	var snaps: Array = rec.get_record().snapshots
	t.check_eq(rt.clock.get_song_time_ms(), 1000, "冻结期歌曲时间确实停住（本用例的前提）")
	t.check(snaps.size() > before_freeze,
		"冻结期快照继续追加（%d → %d），不再被钉在同一时刻" % [before_freeze, snaps.size()])

	# 关键断言：冻结段的最后一个时间戳必须大于冻结前最后一个，
	# 否则说明补救过程被压成零长度，回放仍会闪现。
	var last_before: int = int(snaps[before_freeze - 1].time_ms)
	var last_after: int = int(snaps[snaps.size() - 1].time_ms)
	t.check(last_after > last_before,
		"冻结段占住了真实时长（%dms → %dms，差 %dms）" % [last_before, last_after, last_after - last_before])
	t.finish("补救过程已录进记录")


## 解冻后时间轴必须继续单调不减，且不依赖任何「重基」技巧。
##
## 曾经的实现是「冻结期读真实时间 + 解冻时把歌曲时间顶到 last+1」。
## 探针实测它在**第二次**冻结时就失效：歌曲时间（1533ms）远小于
## 第一段冻结已推进到的 last（9501ms），报「snapshot time_ms 非递增」。
## 现实现改为「歌曲时间 + (真实时间 - 歌曲时间)」——差值是累加量，
## 逐段叠加，结构上不可能回落。本用例锁住这个性质。
func _test_18_freeze_unfreeze_monotonic(t: Variant) -> void:
	t.begin("多次冻结/解冻后时间轴严格单调不减")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FreezeRuntime.new()
	rec.begin(0, 35000)

	# 三轮「正常 500ms → 冻结 500ms」，模拟空演时反复漏拍开补救窗。
	for round_i in 3:
		for i in 5:
			rt.clock.advance(100)
			rt.lamp_controller.lamp.oil = 1.0 - float(round_i * 10 + i) * 0.005
			rec.capture_states(rt)
		rt.clock.set_frozen(true)
		for i in 5:
			rt.clock.advance(100)
			rt.lamp_controller.lamp.oil = 0.6 - float(round_i * 10 + i) * 0.005
			rec.capture_states(rt)
		rt.clock.set_frozen(false)
	for i in 5:
		rt.clock.advance(100)
		rt.lamp_controller.lamp.oil = 0.2 - float(i) * 0.005
		rec.capture_states(rt)

	var snaps: Array = rec.get_record().snapshots
	var strictly_up: bool = true
	var backwards_at: int = -1
	for i in range(1, snaps.size()):
		if int(snaps[i].time_ms) <= int(snaps[i - 1].time_ms):
			strictly_up = false
			backwards_at = int(snaps[i].time_ms)
			break
	t.check(strictly_up, "全部快照 time_ms 严格递增（第 %d 帧出现倒退/停滞）" % backwards_at)
	t.check_eq(int(rec.get_stats().get("backwards_clock_count", -1)), 0,
		"Recorder 自己没报时钟倒退")

	# 三轮冻结累计 1500ms 真实时间，末帧应至少 song(2000) + frozen(1500) 之上。
	var stats: Dictionary = rec.get_stats()
	var frozen_total: int = int(stats.get("frozen_accum_ms", 0))
	t.check(frozen_total >= 1400,
		"累计冻结时长被完整吸收（%dms，三轮各 500ms）" % frozen_total)
	t.check(rec.get_record().validate_invariants().is_empty(),
		"整份记录通过不变量自检（回放准入闸门据此放行）")
	t.finish("多次冻结后时间轴仍然单调")


## 快照与事件必须落在**同一条时间轴**上。
##
## A 端给的事件 time_ms 是歌曲时间（level1_runtime.gd:114），
## 冻结期它同样停住 —— 探针实测 6 条 remedy_* 事件全挤在 t=1517ms，
## 回放时补救提示等于消失。现实现给事件加与快照同一个补偿量。
## 这正是 A 侧 stage_director.gd:13 写明「供 C 记录回放节奏」的本意。
func _test_19_freeze_events_share_timeline(t: Variant) -> void:
	t.begin("补救事件与快照共用同一条时间轴")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FreezeRuntime.new()
	rec.begin(0, 35000)

	for i in 10:
		rt.clock.advance(100)
		rt.lamp_controller.lamp.oil = 1.0 - float(i) * 0.01
		rec.capture_states(rt)

	# 冻结开始：A 端在歌曲时间 1000ms 处吐出 remedy_open / freeze_begin。
	rt.clock.set_frozen(true)
	rt.clock.advance(100)
	rt.events = [
		{"time_ms": rt.clock.get_song_time_ms(), "kind": "remedy_open",
			"object_id": 0, "cue_id": "", "payload": {}},
		{"time_ms": rt.clock.get_song_time_ms(), "kind": "remedy_freeze_begin",
			"object_id": 0, "cue_id": "", "payload": {}},
	]
	rec.capture_events(rt)

	# 冻结中段：灯油继续消耗，快照继续推进。
	for i in 8:
		rt.clock.advance(100)
		rt.lamp_controller.lamp.oil = 0.5 - float(i) * 0.01
		rec.capture_states(rt)

	# 冻结结束：remedy_freeze_end 发生在歌曲时间仍然停住的时刻。
	rt.events = [
		{"time_ms": rt.clock.get_song_time_ms(), "kind": "remedy_freeze_end",
			"object_id": 0, "cue_id": "", "payload": {}},
	]
	rec.capture_events(rt)
	rt.clock.set_frozen(false)

	var rec_obj: Variant = rec.get_record()
	var open_at: int = -1
	var end_at: int = -1
	for e in rec_obj.events:
		if String(e.kind) == "remedy_freeze_begin":
			open_at = int(e.time_ms)
		elif String(e.kind) == "remedy_freeze_end":
			end_at = int(e.time_ms)
	t.check(open_at >= 0 and end_at >= 0, "两条冻结边界事件都已记录")
	t.check(end_at - open_at >= 700,
		"冻结区间在时间轴上铺开 %dms（改前两者同刻、差 0）" % [end_at - open_at])

	# 事件不得晚于它之后写入的快照太多：同一帧的事件与快照必须共轴。
	var first_after_freeze: int = -1
	for s in rec_obj.snapshots:
		if int(s.time_ms) > open_at:
			first_after_freeze = int(s.time_ms)
			break
	t.check(first_after_freeze >= open_at,
		"冻结期快照与事件同轴（首个冻结后快照 %dms ≥ 冻结起点 %dms）"
		% [first_after_freeze, open_at])
	t.check(rec_obj.validate_invariants().is_empty(), "记录仍然合法")
	t.finish("事件与快照共轴")


## 冻结把时间轴推过 duration_ms 时必须钳制，不能让不变量爆掉。
##
## 实测（真 runtime 空演 40 秒）：累计冻结约 5 秒，末帧真实时间到 40133ms，
## 308 帧越过 35000。若不钳，validate_invariants 直接判非法、
## **准入闸门关闭、回放根本进不去**——比闪现更糟。
func _test_20_freeze_overrun_clamped(t: Variant) -> void:
	t.begin("冻结导致的越过时长被钳制，记录仍然合法")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FreezeRuntime.new()
	rec.begin(0, 35000)

	# 先把歌曲时间推到 34900ms（贴近时长末端），全程每帧跳变确保被采样。
	for i in 34:
		rt.clock.advance(1000)
		rt.lamp_controller.lamp.oil = 1.0 - float(i) * 0.005
		rec.capture_states(rt)
	for i in 9:
		rt.clock.advance(100)
		rt.lamp_controller.lamp.oil = 0.8 - float(i) * 0.005
		rec.capture_states(rt)
	t.check_eq(rt.clock.get_song_time_ms(), 34900, "歌曲时间已贴近时长末端（本用例的前提）")

	# 冻结 2 秒：歌曲时间停在 34900ms，真实时间走到 36900ms。
	# 补偿后的记录时间 = 34900 + 2000 = 36900，**越过 35000**。
	rt.clock.set_frozen(true)
	for i in 20:
		rt.clock.advance(100)
		rt.lamp_controller.lamp.oil = 0.5 - float(i) * 0.01
		rec.capture_states(rt)
	rt.clock.set_frozen(false)
	# 解冻后再跑 1 秒，验证越界之后仍能继续采样且不崩。
	for i in 10:
		rt.clock.advance(100)
		rt.lamp_controller.lamp.oil = 0.2 - float(i) * 0.005
		rec.capture_states(rt)

	var rec_obj: Variant = rec.get_record()
	var over: int = 0
	for s in rec_obj.snapshots:
		if int(s.time_ms) > 35000:
			over += 1
	t.check_eq(over, 0, "没有任何快照越过本关时长 35000")
	t.check_eq(int(rec_obj.snapshots[rec_obj.snapshots.size() - 1].time_ms), 35000,
		"末帧被钳到 35000")
	t.check(rec_obj.validate_invariants().is_empty(),
		"不变量自检通过（钳制的意义就在这里：宁可丢尾帧也不能让记录非法）")
	t.finish("越界钳制生效")


## 事件侧必须与快照侧同样钳到duration_ms，且钳制顺序是「先补偿、后钳制」。
##
## 早先 `_to_timed_event` 写成「先把歌曲时间钳到 duration_ms、再加补偿」，
## 补偿会把刚钳好的值重新推出边界，最终事件时间 > duration_ms，
## 被 append_event 与 validate_invariants 拒绝——症状是补救末段的
## `remedy_freeze_end` 悄悄丢失，快照在放补救画面而事件流里没有对应提示。
## 本用例把末尾那一格钉住：越界时刻发出的事件也必须进得了记录、且时间合法。
func _test_21_late_events_clamped_after_compensation(t: Variant) -> void:
	t.begin("补偿后越界的事件同样被钳到 duration_ms")
	var rec: Variant = CRecorderScript.new()
	var rt: Variant = FreezeRuntime.new()
	rec.begin(0, 35000)

	# 歌曲时间先贴近时长末端。
	for i in 35:
		rt.clock.advance(1000)
		rt.lamp_controller.lamp.oil = 1.0 - float(i) * 0.005
		rec.capture_states(rt)
	t.check_eq(rt.clock.get_song_time_ms(), 35000, "歌曲时间已到时长末端（本用例前提）")

	# 冻结 2 秒：歌曲时间停住，真实时间走 2000ms。
	# 事件 time_ms 由 A 端给歌曲时间（= 35000），补偿后应为 37000 > 35000。
	rt.clock.set_frozen(true)
	rt.clock.advance(2000)
	rt.lamp_controller.lamp.oil = 0.4
	rec.capture_states(rt)
	rt.events = [
		{"time_ms": rt.clock.get_song_time_ms(), "kind": "remedy_freeze_end",
			"object_id": 0, "cue_id": "", "payload": {}},
	]
	rec.capture_events(rt)
	rt.clock.set_frozen(false)

	var rec_obj: Variant = rec.get_record()
	t.check_eq(rec_obj.events.size(), 1, "越界时刻的事件确实写进了记录（未被静默拒写）")
	var ev_time: int = int(rec_obj.events[0].time_ms)
	t.check_eq(ev_time, 35000, "事件时间被钳到 duration_ms（实际 %d）" % ev_time)
	t.check(rec_obj.validate_invariants().is_empty(),
		"快照与事件同时合法（钳制顺序修正后成立）")
	t.finish("事件侧钳制生效")
