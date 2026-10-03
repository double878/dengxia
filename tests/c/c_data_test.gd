extends SceneTree
## 临时验证脚本：检查 CPerformanceRecord / CSnapshot / CTimedEvent 的核心契约。
## 验证完成后删除（AGENTS.md「分段验证与测试」）。

var failures: Array = []


func _init() -> void:
	test_snapshot_construction()
	test_changed_fields_detects_discrete_jumps()
	test_event_seq_continuous_and_sorted()
	test_invalid_event_rejected_without_consuming_seq()
	test_fidelity_miss_not_erased_by_remedy_success()
	test_duration_uses_fixed_not_last_snapshot()
	test_pause_does_not_duplicate_snapshot()
	test_jump_sampling_beats_30hz()

	if failures.is_empty():
		print("\n=== C_DATA_CONTRACT: ALL PASS ===")
	else:
		print("\n=== C_DATA_CONTRACT: %d FAILED ===" % failures.size())
		for f in failures:
			print("  FAIL: %s" % f)
	quit(0 if failures.is_empty() else 1)


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok  - %s" % label)
	else:
		failures.append(label)
		print("  ERR - %s" % label)


# A 端 to_dict() 的真实形状，字段名取自 scripts/a/puppet_state.gd
func make_puppet_view(pid: int, x: float, head_id: int, hook: int, controlled: bool) -> Dictionary:
	return {
		"puppet_id": pid,
		"stage_pos": {"x": x, "y": 0.0},
		"stance": 0.0, "facing": 0.0, "turn_progress": 0.0,
		"hand_angle": {"left": 0.0, "right": 0.0},
		"head_id": head_id, "hook_slot": hook, "is_controlled": controlled,
	}


func make_lamp_view(dist: float, exp: float, oil: float, flame: float) -> Dictionary:
	return {"distance": dist, "exposure": exp, "oil": oil, "flame_feedback": flame}


func make_record() -> CPerformanceRecord:
	return CPerformanceRecord.new(0, CPerformanceRecord.STAGE1_DURATION_MS)


func test_snapshot_construction() -> void:
	print("\n[1] Snapshot 从 A 端 to_dict() 构造")
	var views: Array = [
		make_puppet_view(0, 0.3, 0, -1, true),
		make_puppet_view(1, 0.5, 1, 0, false),
		make_puppet_view(2, 0.7, 2, 1, false),
	]
	var snap := CSnapshot.from_views(1000, views, make_lamp_view(0.4, 0.6, 0.9, 0.7))
	check(snap.puppets.size() == 3, "puppets 固定长度 3")
	check(snap.puppets[0]["head_id"] == 0, "head_id 正确读出")
	check(snap.puppets[1]["hook_slot"] == 0, "hook_slot 正确读出（0 号挂钩，非 -1）")
	check(is_equal_approx(float(snap.puppets[2]["stage_pos"]["x"]), 0.7), "stage_pos.x 正确读出")
	check(is_equal_approx(float(snap.lamp["flame_feedback"]), 0.7),
		"lamp 第四字段为 flame_feedback（A 端实际名，不是 flame）")
	check(not snap.lamp.has("flame"), "不存在旧契约里的 flame 字段名")


func test_changed_fields_detects_discrete_jumps() -> void:
	print("\n[2] 跳变检测覆盖离散量")
	var a := CSnapshot.from_views(0, [make_puppet_view(0, 0.5, 0, -1, true), make_puppet_view(1, 0.5, 1, -1, false), make_puppet_view(2, 0.5, 2, -1, false)])
	var b := CSnapshot.from_views(33, [make_puppet_view(0, 0.5, 3, -1, true), make_puppet_view(1, 0.5, 1, 0, false), make_puppet_view(2, 0.5, 2, -1, false)])
	var changed: Array = a.changed_fields(b)
	check(changed.has("puppets[0].head_id"), "换头被检出")
	check(changed.has("puppets[1].hook_slot"), "挂起被检出")
	var c := CSnapshot.from_views(66, [make_puppet_view(0, 0.5, 3, -1, false), make_puppet_view(1, 0.5, 1, 0, false), make_puppet_view(2, 0.5, 2, -1, false)])
	check(a.changed_fields(c).has("puppets[0].is_controlled"), "受控权移交被检出")
	var d := CSnapshot.from_views(99, [make_puppet_view(0, 0.9, 3, -1, false), make_puppet_view(1, 0.5, 1, 0, false), make_puppet_view(2, 0.5, 2, -1, false)])
	check(c.changed_fields(d).has("puppets[0].stage_pos"), "位置平移被检出")
	var e := CSnapshot.from_views(132, [make_puppet_view(0, 0.9, 3, -1, false), make_puppet_view(1, 0.5, 1, 0, false), make_puppet_view(2, 0.5, 2, -1, false)], make_lamp_view(0.8, 0.6, 0.9, 0.7))
	check(d.changed_fields(e).has("lamp.distance"), "灯距变化被检出")
	check(a.changed_fields(a).is_empty(), "与自身对比无变化")


func test_event_seq_continuous_and_sorted() -> void:
	print("\n[3] 事件 seq 连续且按 (time_ms, seq) 排序")
	var rec := make_record()
	var seqs: Array = []
	for i in 8:
		var ev := CTimedEvent.new(i * 100, CTimedEvent.KIND_HAND_MOTION, 0, "", {"hand": "left", "dir": 1})
		rec.append_event(ev)
		seqs.append(ev.seq)
	check(seqs[0] == 1, "seq 从 1 开始")
	check(seqs == [1, 2, 3, 4, 5, 6, 7, 8], "seq 连续无空洞")
	# 乱序插入
	var late := CTimedEvent.new(250, CTimedEvent.KIND_CUE_HIT, 0, "cue_a", {"offset_ms": 30})
	rec.append_event(late)
	check(late.seq == 9, "乱序插入的 seq 仍接续")
	var sorted_ok := true
	for i in range(1, rec.events.size()):
		if rec.events[i - 1].compare_order(rec.events[i]) > 0:
			sorted_ok = false
	check(sorted_ok, "events 按 (time_ms, seq) 升序（250ms 事件插到 200 之后）")
	check(rec.events.size() == 9, "事件数正确")


func test_invalid_event_rejected_without_consuming_seq() -> void:
	print("\n[4] 非法事件被拒绝且不消耗 seq")
	var rec := make_record()
	var ok := CTimedEvent.new(1000, CTimedEvent.KIND_CUE_HIT, 0, "cue_x", {})
	rec.append_event(ok)
	check(ok.seq == 1, "第一条合法事件 seq=1")

	var bad_kind := CTimedEvent.new(1100, &"nonsense_kind", 0, "", {})
	var bad_result := rec.append_event(bad_kind)
	check(not bad_result, "未知 kind 被拒绝")
	var bad_id := CTimedEvent.new(1100, CTimedEvent.KIND_CUE_HIT, 9, "", {})
	check(not rec.append_event(bad_id), "object_id 越界被拒绝")
	var oob := CTimedEvent.new(999999, CTimedEvent.KIND_STAGE_END, 0, "", {})
	check(not rec.append_event(oob), "超出本关时长的 time_ms 被拒绝")
	check(rec.events.size() == 1, "三条非法事件均未写入")

	var next_ok := CTimedEvent.new(1200, CTimedEvent.KIND_STAGE_END, 0, "", {"reason": "completed"})
	rec.append_event(next_ok)
	check(next_ok.seq == 2, "拒绝后 seq 仍为 2（失败不消耗号段，seq 保持连续）")


func test_fidelity_miss_not_erased_by_remedy_success() -> void:
	print("\n[5] 忠实性：补救成功不抹除原 cue_miss（PRD 5.2.3）")
	var rec := make_record()
	rec.append_event(CTimedEvent.new(1000, CTimedEvent.KIND_CUE_HINT, 0, "cue_a", {}))
	rec.append_event(CTimedEvent.new(2000, CTimedEvent.KIND_CUE_FIRE, 0, "cue_a", {"action": "hand_up"}))
	rec.append_event(CTimedEvent.new(2000, CTimedEvent.KIND_CUE_MISS, 0, "cue_a", {"offset_ms": 310, "tolerance_ms": 250}))
	rec.append_event(CTimedEvent.new(2500, CTimedEvent.KIND_REMEDY_OPEN, 0, "cue_a", {"duration_ms": 8000}))
	rec.append_event(CTimedEvent.new(6500, CTimedEvent.KIND_REMEDY_SUCCESS, 0, "cue_a", {"elapsed_ms": 4000, "still_missed": true}))

	var kinds: Array = []
	for e in rec.events:
		kinds.append(e.kind)
	check(kinds.has(CTimedEvent.KIND_CUE_MISS), "remedy_success 之后 cue_miss 仍在事件流里")
	check(kinds.has(CTimedEvent.KIND_CUE_FIRE), "cue_fire 与 cue_miss 并存（错拍时动作确实发生了）")
	var success_ev: CTimedEvent = null
	for e in rec.events:
		if e.kind == CTimedEvent.KIND_REMEDY_SUCCESS:
			success_ev = e
	check(success_ev != null and bool(success_ev.payload.get("still_missed", false)),
		"remedy_success 的 still_missed 为 true")
	check(rec.validate_invariants().is_empty(),
		"整条事件流通过不变量自检（cue_miss 有对应 cue_fire）")


func test_duration_uses_fixed_not_last_snapshot() -> void:
	print("\n[6] 时长口径：duration_ms 用固定值，不受最后一帧影响")
	var rec := make_record()
	var views: Array = [make_puppet_view(0, 0.5, 0, -1, true), make_puppet_view(1, 0.5, 1, -1, false), make_puppet_view(2, 0.5, 2, -1, false)]
	rec.append_snapshot(CSnapshot.from_views(34983, views))
	rec.finish(34983)
	check(rec.get_replay_duration_ms() == 35000, "回放时长为 35000ms")
	check(rec.get_replay_duration_ms() != rec.snapshots[rec.snapshots.size() - 1].time_ms,
		"不使用最后一帧的 34983ms（否则差一帧）")


func test_pause_does_not_duplicate_snapshot() -> void:
	print("\n[7] 暂停：同一时刻不追加重复 Snapshot")
	var rec := make_record()
	var views: Array = [make_puppet_view(0, 0.5, 0, -1, true), make_puppet_view(1, 0.5, 1, -1, false), make_puppet_view(2, 0.5, 2, -1, false)]
	var snap_a := CSnapshot.from_views(5000, views)
	rec.append_snapshot(snap_a)
	# 暂停若干帧，时钟读数不变
	var should := false
	for _i in 3:
		should = rec.should_sample(5000, snap_a)
	check(not should, "时钟未变化时 should_sample 返回 false")
	rec.append_snapshot(CSnapshot.from_views(5000, views))
	check(rec.snapshots.size() == 1, "同一时刻只有一条 Snapshot")
	# 恢复后时间继续推进
	# 恢复后时间继续推进。采样点按相位落在 0/33/67/100…，
	# 5033 不一定是整点，但 5050 之后必有采样点到期。
	var resumed := false
	for probe in range(5033, 5100):
		if rec.should_sample(probe, CSnapshot.from_views(probe, views)):
			resumed = true
			break
	check(resumed, "恢复后继续采样（相位不受暂停影响）")


func test_jump_sampling_beats_30hz() -> void:
	print("\n[8] 跳变补采样优先于 30 Hz")
	var rec := make_record()
	var base: Array = [make_puppet_view(0, 0.5, 0, -1, true), make_puppet_view(1, 0.5, 1, -1, false), make_puppet_view(2, 0.5, 2, -1, false)]
	rec.append_snapshot(CSnapshot.from_views(0, base))
	# 10ms 后发生换头，远未到 33ms 采样点，但必须采样
	var jumped: Array = [make_puppet_view(0, 0.5, 4, -1, true), make_puppet_view(1, 0.5, 1, -1, false), make_puppet_view(2, 0.5, 2, -1, false)]
	var at10 := CSnapshot.from_views(10, jumped)
	check(rec.should_sample(10, at10), "未到 30Hz 采样点但发生跳变，仍需采样")
	rec.append_snapshot(at10)
	check(rec.snapshots.size() == 2, "跳变帧已补录")
	# 同一时刻常规采样也认为到期时，不应追加第二条
	rec.append_snapshot(CSnapshot.from_views(10, jumped))
	check(rec.snapshots.size() == 2, "跳变与常规采样同帧相遇只追加一条")

	# 30 Hz 常规节拍：35 秒应采到约 1050 条（35000 / 33.333 = 1050），
	# 末帧约 34997ms。用微秒累进，误差不随时长放大。
	var rec2 := make_record()
	var v: Array = [make_puppet_view(0, 0.5, 0, -1, true), make_puppet_view(1, 0.5, 1, -1, false), make_puppet_view(2, 0.5, 2, -1, false)]
	var t := 0
	var last2 := 0
	while t <= 35000:
		if rec2.is_due_for_sampling(t):
			rec2.append_snapshot(CSnapshot.from_views(t, v))
			last2 = t
		t += 1
	check(last2 >= 34966 and last2 <= 35000,
		"35 秒末帧落在 34966..35000（微秒累进，误差 < 34ms）；实际 %d" % last2)
	check(rec2.snapshots.size() >= 1049 and rec2.snapshots.size() <= 1051,
		"35 秒采到约 1050 条；实际 %d" % rec2.snapshots.size())
	# 110 秒是全项目最长关卡（PRD 1.1），验证误差不随时长放大
	var rec3 := CPerformanceRecord.new(4, 110000)
	var t3 := 0
	var last3 := 0
	while t3 <= 110000:
		if rec3.is_due_for_sampling(t3):
			rec3.append_snapshot(CSnapshot.from_views(t3, v))
			last3 = t3
		t3 += 1
	check(last3 >= 109966 and last3 <= 109999,
		"110 秒末帧落在 109966..109999（微秒累进，误差 < 34ms）；实际 %d" % last3)
	var count3 := rec3.snapshots.size()
	check(count3 >= 3298 and count3 <= 3302,
		"110 秒采到约 3300 条；实际 %d" % count3)
	check(rec3.validate_invariants().is_empty(), "110 秒全量采样通过不变量自检")
