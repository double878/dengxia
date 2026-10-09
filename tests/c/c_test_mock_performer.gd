extends RefCounted
class_name CTestMockPerformer
## 切片 4 行为测试：模拟演出生成器。
##
## 验证思路：不是「再实现一遍生成器的逻辑」，而是从生成的记录里
## 独立按时刻取值核对。回放验收（TECH_DESIGN 第 4 节）要核对的正是
## 「某个时刻画面上该是什么」，所以测试也按这个角度写——
## 给出时刻与期望值，让记录自己回答，测试不替它回答。
##
## 依赖一律用 preload 常量：--headless --script 不读全局类名缓存。

const CMockPerformerScript := preload("res://scripts/c/c_mock_performer.gd")
const CTimedEventScript := preload("res://scripts/c/c_timed_event.gd")


func run_all() -> Dictionary:
	var t: Variant = preload("res://tests/c/c_test_base.gd").new()
	_test_01_build_shape(t)
	_test_02_invariants_pass(t)
	_test_03_segments_all_present(t)
	_test_04_stillness_no_extra_samples(t)
	_test_05_move_left(t)
	_test_06_fast_turn(t)
	_test_07_hands_independent(t)
	_test_08_head_swap_and_hook(t)
	_test_09_lamp_distance_direction(t)
	_test_10_oil_monotonic(t)
	_test_11_wrong_beat_has_cue_fire(t)
	_test_12_missed_has_reason(t)
	_test_13_time_axis_ordered(t)
	_test_14_deterministic(t)
	_test_15_covered_features_declared(t)
	return t.report()


## 从记录里找不超过 now_ms 的最后一帧。找不到返回 null。
func _snap_at(record: Variant, now_ms: int) -> Variant:
	var idx: int = record.find_snapshot_index_at(now_ms)
	if idx < 0:
		return null
	return record.snapshots[idx]


## 0 号影人在 now_ms 的 stage_pos.x。
func _x_at(record: Variant, now_ms: int) -> float:
	var snap: Variant = _snap_at(record, now_ms)
	return float(snap.puppets[0].stage_pos.x)


func _events_of_kind(record: Variant, kind: String) -> Array:
	var out: Array = []
	for e in record.events:
		if str(e.kind) == kind:
			out.append(e)
	return out


func _has_event_at(record: Variant, kind: String, cue_id: String) -> bool:
	for e in record.events:
		if str(e.kind) == kind and str(e.cue_id) == cue_id:
			return true
	return false


func _test_01_build_shape(t: Variant) -> void:
	t.begin("生成记录的基本形状")
	var record: Variant = CMockPerformerScript.new().build()
	t.check(record != null, "返回记录对象")
	t.check_eq(record.stage_id, 1, "关卡号")
	t.check_eq(record.duration_ms, 8000, "时长 8000ms")
	# 8000 / 17 ≈ 471 帧，另加 t=0 与 t=8000 两端
	t.check(record.snapshots.size() >= 470, "快照数约 470（%d）" % record.snapshots.size())
	t.check(record.events.size() > 10, "事件数 %d" % record.events.size())
	t.check_eq(record.get_replay_duration_ms(), 8000, "回放时长")
	t.finish("形状正确")


func _test_02_invariants_pass(t: Variant) -> void:
	t.begin("不变量自检必须通过")
	var record: Variant = CMockPerformerScript.new().build()
	var problems: Array = record.validate_invariants()
	t.check_eq(problems.size(), 0, "不变量全过（%d 项）" % problems.size())
	for p in problems:
		print("    问题：%s" % str(p))
	t.finish("自检通过")


func _test_03_segments_all_present(t: Variant) -> void:
	t.begin("七个动作段全部覆盖")
	var plan: Array = CMockPerformerScript.segment_plan()
	t.check_eq(plan.size(), 7, "定义了 7 段")
	# 段是闭区间，因此相接的条件是 start == prev_end（不是 >）。
	# 用 > 会把正确写法判成重叠。首段的 prev_end 视作 0。
	var contiguous: bool = int(plan[0]["start_ms"]) == 0
	var prev_end: int = int(plan[0]["end_ms"])
	for i in range(1, plan.size()):
		if int(plan[i]["start_ms"]) != prev_end:
			contiguous = false
		prev_end = int(plan[i]["end_ms"])
	t.check(contiguous, "段首尾相接不重叠（闭区间允许端点相等）")
	t.check_eq(int(plan[0]["start_ms"]), 0, "首段从 0 开始")
	t.check_eq(prev_end, 8000, "末段结束于 8000ms")
	t.finish("分段连续")


func _test_04_stillness_no_extra_samples(t: Variant) -> void:
	t.begin("停顿段确实是静止的")
	var record: Variant = CMockPerformerScript.new().build()
	# 停顿段 0-800ms 内影人 0 的姿态不应变化：
	# 取 300ms 与 500ms 两点比较，位置与手部应完全相同。
	var a: Variant = _snap_at(record, 300)
	var b: Variant = _snap_at(record, 500)
	t.check_eq(float(b.puppets[0].stage_pos.x), float(a.puppets[0].stage_pos.x), "位置不变")
	t.check_eq(float(b.puppets[0].hand_angle.left), float(a.puppets[0].hand_angle.left), "左手不变")
	t.check_eq(int(b.puppets[0].head_id), int(a.puppets[0].head_id), "头不变")
	t.finish("停顿成立")


func _test_05_move_left(t: Variant) -> void:
	t.begin("左移段：x 递减")
	var record: Variant = CMockPerformerScript.new().build()
	var x_start: float = _x_at(record, 800)
	var x_mid: float = _x_at(record, 1500)
	var x_end: float = _x_at(record, 2200)
	t.check(x_mid < x_start, "中段比起点靠左（%.4f < %.4f）" % [x_mid, x_start])
	t.check(x_end < x_mid, "末段比中段更靠左（%.4f < %.4f）" % [x_end, x_mid])
	t.check_in_range(x_end, 0.0, 1.0, "仍在 0-1 区间内")
	t.finish("左移成立")


func _test_06_fast_turn(t: Variant) -> void:
	t.begin("快速转身：facing 双向且 turn_progress 同步")
	var record: Variant = CMockPerformerScript.new().build()
	var before: Variant = _snap_at(record, 2100)
	var right: Variant = _snap_at(record, 2400)
	var left: Variant = _snap_at(record, 3000)
	t.check_eq(float(before.puppets[0].facing), 0.0, "转身前 facing=0")
	t.check(float(right.puppets[0].facing) > 0.0, "前半段面向右（%.1f）" % float(right.puppets[0].facing))
	t.check(float(left.puppets[0].facing) < 0.0, "后半段面向左（%.1f）" % float(left.puppets[0].facing))
	# turn_progress 必须等于 abs(facing)，B 侧靠它判转身完成度
	t.check_approx(float(right.puppets[0].turn_progress), absf(float(right.puppets[0].facing)),
		1e-6, "turn_progress 与 |facing| 一致")
	t.finish("转身成立")


func _test_07_hands_independent(t: Variant) -> void:
	t.begin("双手不同姿势")
	var record: Variant = CMockPerformerScript.new().build()
	var s: Variant = _snap_at(record, 4000)
	var left: float = float(s.puppets[0].hand_angle.left)
	var right: float = float(s.puppets[0].hand_angle.right)
	t.check(left < 0.0 and right > 0.0, "一左一右（left=%.3f right=%.3f）" % [left, right])
	t.check(absf(left - right) > 0.5, "两手角度差 > 0.5 弧度")
	# 范围不能超出 A 端契约的 ±0.6
	t.check_in_range(left, -0.6, 0.6, "左手在 ±0.6 内")
	t.check_in_range(right, -0.6, 0.6, "右手在 ±0.6 内")
	t.finish("双手异姿成立")


func _test_08_head_swap_and_hook(t: Variant) -> void:
	t.begin("换头与挂起是两次独立跳变")
	var record: Variant = CMockPerformerScript.new().build()
	var before_swap: Variant = _snap_at(record, 4900)
	var after_swap: Variant = _snap_at(record, 5100)
	var after_hook: Variant = _snap_at(record, 5300)
	t.check_eq(int(before_swap.puppets[0].head_id), -1, "换头前 head_id=-1（无）")
	t.check_eq(int(after_swap.puppets[0].head_id), 3, "换头后 head_id=3")
	t.check_eq(int(after_swap.puppets[0].hook_slot), -1, "此刻尚未挂起")
	t.check_eq(int(after_hook.puppets[0].hook_slot), 0, "随后挂到槽位 0")
	# 两者时刻必须分开，否则回放把顺序压平也看不出来
	t.check(after_swap.time_ms < after_hook.time_ms, "换头早于挂起")
	t.finish("换头挂起成立")


func _test_09_lamp_distance_direction(t: Variant) -> void:
	t.begin("灯位推拉：distance 变小=灯变近")
	var record: Variant = CMockPerformerScript.new().build()
	var before: Variant = _snap_at(record, 5300)
	var during: Variant = _snap_at(record, 6000)
	t.check(float(during.lamp.distance) < float(before.lamp.distance),
		"推拉段 distance 变小（%.4f < %.4f）" % [float(during.lamp.distance), float(before.lamp.distance)])
	# 灯位事件必须带 String 命名空间的 object_id
	var lamp_events: Array = _events_of_kind(record, "lamp_input_changed")
	t.check_eq(lamp_events.size(), 2, "两条灯位事件")
	t.check_eq(lamp_events[0].object_id, "lamp_main", "object_id 为字符串 lamp_main")
	t.check_eq(typeof(lamp_events[0].object_id), TYPE_STRING, "类型确为 String")
	t.finish("灯位成立")


func _test_10_oil_monotonic(t: Variant) -> void:
	t.begin("灯油单调不回升")
	var record: Variant = CMockPerformerScript.new().build()
	var prev: float = 1.0
	var monotonic: bool = true
	var first_drop: int = -1
	for i in record.snapshots.size():
		var v: float = float(record.snapshots[i].lamp.oil)
		if v > prev + 1e-9:
			monotonic = false
			break
		if first_drop < 0 and v < prev - 1e-9:
			first_drop = i
		prev = v
	t.check(monotonic, "全程不回升")
	t.check(first_drop >= 0, "确实在消耗（第 %d 帧开始下降）" % first_drop)
	t.check(prev > 0.0, "末帧仍有油（%.4f）" % prev)
	t.finish("灯油单调")


func _test_11_wrong_beat_has_cue_fire(t: Variant) -> void:
	t.begin("错拍必须 cue_fire 与 cue_miss 并存")
	var record: Variant = CMockPerformerScript.new().build()
	var misses: Array = _events_of_kind(record, "cue_miss")
	# 两次错拍 + 一次漏做 = 3 条 cue_miss
	t.check_eq(misses.size(), 3, "三条 cue_miss（2 错拍 + 1 漏做）")
	var wrong_only: Array = []
	for e in misses:
		if str(e.payload.get("reason", "")) != "missed_outright":
			wrong_only.append(e)
	t.check_eq(wrong_only.size(), 2, "其中 2 条是错拍")
	for e in wrong_only:
		t.check(_has_event_at(record, "cue_fire", str(e.cue_id)),
			"错拍 %s 有配对的 cue_fire" % str(e.cue_id))
	t.finish("忠实性成立")


func _test_12_missed_has_reason(t: Variant) -> void:
	t.begin("漏做的判别键是 payload.reason")
	var record: Variant = CMockPerformerScript.new().build()
	var found: bool = false
	for e in record.events:
		if str(e.kind) == "cue_miss" and str(e.payload.get("reason", "")) == "missed_outright":
			found = true
			# 完全没做 → 本就不该有 cue_fire
			t.check(not _has_event_at(record, "cue_fire", str(e.cue_id)),
				"漏做 %s 没有 cue_fire（正确）" % str(e.cue_id))
			t.check(e.payload.has("offset_ms"), "payload 带 offset_ms")
	t.check(found, "存在 missed_outright 事件")
	t.finish("漏做成立")


func _test_13_time_axis_ordered(t: Variant) -> void:
	t.begin("时间轴单调且不越界")
	var record: Variant = CMockPerformerScript.new().build()
	var prev_t: int = -1
	var ordered: bool = true
	for s in record.snapshots:
		if s.time_ms <= prev_t:
			ordered = false
			break
		prev_t = int(s.time_ms)
	t.check(ordered, "快照 time_ms 严格递增")
	t.check_eq(prev_t, 8000, "末帧正好 8000ms")
	# 事件 seq 连续
	var expected: int = 1
	var seq_ok: bool = true
	for e in record.events:
		if int(e.seq) != expected:
			seq_ok = false
			break
		expected += 1
	t.check(seq_ok, "事件 seq 从 1 连续")
	t.finish("时间轴规范")


func _test_14_deterministic(t: Variant) -> void:
	t.begin("同一份代码两次生成完全一致")
	var a: Variant = CMockPerformerScript.new().build()
	var b: Variant = CMockPerformerScript.new().build()
	t.check_eq(a.snapshots.size(), b.snapshots.size(), "快照数一致")
	t.check_eq(a.events.size(), b.events.size(), "事件数一致")
	# 逐点比对内容，不比对象引用
	var same: bool = true
	for i in mini(a.snapshots.size(), b.snapshots.size()):
		if not a.snapshots[i].same_content_as(b.snapshots[i]):
			same = false
			break
	t.check(same, "全部快照内容一致（回放可断言的前提）")
	t.finish("可重复生成")


func _test_15_covered_features_declared(t: Variant) -> void:
	t.begin("声明覆盖的验收要素")
	var features: Array = CMockPerformerScript.covered_features()
	var required: Array = ["快速转身", "双手不同姿势", "换头", "挂起", "灯位变化", "错拍", "漏做", "停顿", "横向移动"]
	for r in required:
		t.check(features.has(r), "覆盖「%s」" % r)
	t.finish("验收要素齐备")
