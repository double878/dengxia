extends RefCounted
class_name CTestRecord
## 切片 1 行为测试：CPerformanceRecord —— 记录容器与排序不变量。
##
## 重点覆盖 PRD 5.2.3 的两条忠实性约束与 30Hz 微秒相位采样。
## 依赖一律用 preload 常量。

const CSnapshotScript := preload("res://scripts/c/c_snapshot.gd")
const CTimedEventScript := preload("res://scripts/c/c_timed_event.gd")
const CPerformanceRecordScript := preload("res://scripts/c/c_performance_record.gd")


func run_all() -> Dictionary:
	var t: Variant = preload("res://tests/c/c_test_base.gd").new()
	_test_01_record_init(t)
	_test_02_append_snapshot(t)
	_test_03_append_event_assigns_seq(t)
	_test_04_rejected_event_no_seq(t)
	_test_05_same_time_single_snapshot(t)
	_test_06_30hz_phase_35s(t)
	_test_07_30hz_phase_110s(t)
	_test_08_remedy_does_not_erase_miss(t)
	_test_09_cue_miss_requires_cue_fire(t)
	_test_10_sort_by_time_then_seq(t)
	_test_11_finish_uses_duration(t)
	_test_12_stats(t)
	return t.report()


func _mk_snap(time_ms: int) -> Variant:
	return CSnapshotScript.new(time_ms)


func _mk_event(time_ms: int, kind: StringName, object_id: Variant = 0,
		cue_id: String = "", payload: Dictionary = {}) -> Variant:
	return CTimedEventScript.new(time_ms, kind, object_id, cue_id, payload)


func _test_01_record_init(t: Variant) -> void:
	t.begin("记录初始化：时长与容器")
	var r: Variant = CPerformanceRecordScript.new(1, 35000)
	t.check_eq(r.stage_id, 1, "stage_id")
	t.check_eq(r.duration_ms, 35000, "duration_ms 用关卡固定时长")
	t.check_eq(r.snapshots.size(), 0, "初始无快照")
	t.check_eq(r.events.size(), 0, "初始无事件")
	t.finish("初始化正确")


func _test_02_append_snapshot(t: Variant) -> void:
	t.begin("追加快照")
	var r: Variant = CPerformanceRecordScript.new(1, 35000)
	t.check(r.append_snapshot(_mk_snap(0)), "首帧写入成功")
	t.check(r.append_snapshot(_mk_snap(33)), "第二帧写入成功")
	t.check_eq(r.snapshots.size(), 2, "快照数 2")
	t.finish("快照追加正确")


func _test_03_append_event_assigns_seq(t: Variant) -> void:
	t.begin("事件 seq 从 1 连续递增")
	var r: Variant = CPerformanceRecordScript.new(1, 35000)
	var e1: Variant = _mk_event(100, &"cue_fire", 0, "c1")
	var e2: Variant = _mk_event(200, &"cue_hit", 0, "c1")
	t.check(r.append_event(e1), "事件 1 写入")
	t.check(r.append_event(e2), "事件 2 写入")
	t.check_eq(int(e1.seq), 1, "首个 seq = 1")
	t.check_eq(int(e2.seq), 2, "次个 seq = 2")
	t.finish("seq 分配正确")


func _test_04_rejected_event_no_seq(t: Variant) -> void:
	t.begin("被拒事件不消耗 seq（号段无空洞）")
	var r: Variant = CPerformanceRecordScript.new(1, 35000)
	var bad: Variant = _mk_event(100, &"unknown_kind", 0)
	t.check(not r.append_event(bad), "非法事件被拒")
	t.check_eq(int(bad.seq), -1, "被拒事件 seq 仍为 -1")
	var good: Variant = _mk_event(200, &"cue_fire", 0, "c1")
	t.check(r.append_event(good), "后续合法事件写入")
	t.check_eq(int(good.seq), 1, "seq 从 1 开始，未被坏事件吃掉")
	t.finish("seq 号段连续")


func _test_05_same_time_single_snapshot(t: Variant) -> void:
	t.begin("同一时刻只保留一条快照")
	var r: Variant = CPerformanceRecordScript.new(1, 35000)
	t.check(r.append_snapshot(_mk_snap(100)), "首条写入")
	t.check(r.append_snapshot(_mk_snap(100)), "同刻第二条被接受但不追加")
	t.check_eq(r.snapshots.size(), 1, "同刻只留一条")
	t.finish("同刻去重正确")


func _test_06_30hz_phase_35s(t: Variant) -> void:
	t.begin("30Hz 微秒相位：35 秒采 1051 帧")
	var r: Variant = CPerformanceRecordScript.new(1, 35000)
	r._reset_cursors(0)
	var count: int = 0
	var ms: int = 0
	while ms <= 35000:
		# 模拟真实调用：should_sample 决定是否该采
		if r.is_due_for_sampling(ms) or ms == 0:
			if r.append_snapshot(_mk_snap(ms)):
				count += 1
		ms += 1
	# 期望约 1051 帧（35000/33.333 + 1），允许 ±2 帧余量
	t.check(count >= 1049 and count <= 1053, "35 秒采样帧数约 1051，实际 %d" % count)
	var last: Variant = r.snapshots[r.snapshots.size() - 1]
	t.check(last.time_ms <= 35000, "末帧不超过 35000")
	t.finish("35 秒相位采样正确")


func _test_07_30hz_phase_110s(t: Variant) -> void:
	t.begin("30Hz 微秒相位：110 秒采 3301 帧")
	var r: Variant = CPerformanceRecordScript.new(5, 110000)
	r._reset_cursors(0)
	var count: int = 0
	var ms: int = 0
	while ms <= 110000:
		if r.is_due_for_sampling(ms) or ms == 0:
			if r.append_snapshot(_mk_snap(ms)):
				count += 1
		ms += 1
	t.check(count >= 3298 and count <= 3304, "110 秒采样帧数约 3301，实际 %d" % count)
	t.finish("110 秒相位采样正确")


func _test_08_remedy_does_not_erase_miss(t: Variant) -> void:
	t.begin("忠实性：补救成功不抹除原 cue_miss")
	var r: Variant = CPerformanceRecordScript.new(1, 35000)
	var miss: Variant = _mk_event(1000, &"cue_miss", 0, "c1")
	var fix: Variant = _mk_event(2000, &"remedy_success", 0, "c1", {"still_missed": true})
	t.check(r.append_event(miss), "cue_miss 写入")
	t.check(r.append_event(fix), "remedy_success 写入")
	t.check_eq(r.events.size(), 2, "两条并存，原失误未被删除")
	t.finish("补救不抹失误")


func _test_09_cue_miss_requires_cue_fire(t: Variant) -> void:
	t.begin("忠实性：cue_miss 必须有对应 cue_fire")
	var bad: Variant = CPerformanceRecordScript.new(1, 35000)
	bad.append_event(_mk_event(1000, &"cue_miss", 0, "c1"))
	var bad_problems: Array = bad.validate_invariants()
	t.check(bad_problems.size() > 0, "孤立 cue_miss 被检出")

	var good: Variant = CPerformanceRecordScript.new(1, 35000)
	good.append_event(_mk_event(900, &"cue_fire", 0, "c1"))
	good.append_event(_mk_event(1000, &"cue_miss", 0, "c1"))
	var good_problems: Array = good.validate_invariants()
	t.check_eq(good_problems.size(), 0, "配对后无问题")
	t.finish("cue_fire/cue_miss 并存约束成立")


func _test_10_sort_by_time_then_seq(t: Variant) -> void:
	t.begin("事件按 (time_ms, seq) 有序插入")
	var r: Variant = CPerformanceRecordScript.new(1, 35000)
	# 乱序写入，应按时间排好
	r.append_event(_mk_event(300, &"cue_hit", 0, "c2"))
	r.append_event(_mk_event(100, &"cue_fire", 0, "c1"))
	r.append_event(_mk_event(200, &"cue_miss", 0, "c1"))
	var ok: bool = true
	for i in range(1, r.events.size()):
		if r.events[i - 1].time_ms > r.events[i].time_ms:
			ok = false
	t.check(ok, "插入后按 time_ms 升序")
	t.check_eq(int(r.events[0].time_ms), 100, "最早事件在前")
	t.finish("有序插入正确")


func _test_11_finish_uses_duration(t: Variant) -> void:
	t.begin("结束：时长以 duration_ms 为准")
	var r: Variant = CPerformanceRecordScript.new(1, 35000)
	r.append_snapshot(_mk_snap(0))
	r.finish(34983)
	t.check_eq(r.get_replay_duration_ms(), 35000, "回放时长用 35000 而非末帧 34983")
	t.finish("时长口径正确")


func _test_12_stats(t: Variant) -> void:
	t.begin("统计信息")
	var r: Variant = CPerformanceRecordScript.new(1, 35000)
	r.append_snapshot(_mk_snap(0))
	r.append_snapshot(_mk_snap(33))
	r.append_event(_mk_event(100, &"cue_fire", 0, "c1"))
	var s: Dictionary = r.get_stats()
	t.check_eq(int(s.get("snapshot_count", -1)), 2, "快照数")
	t.check_eq(int(s.get("event_count", -1)), 1, "事件数")
	t.finish("统计正确")
