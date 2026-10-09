extends RefCounted
class_name CTestEvent
## 切片 1/2 行为测试：CTimedEvent —— 离散事件契约。
##
## 重点覆盖切片 2 的新契约：
##   - object_id 是 Variant，影人 int 0-2 / 油灯 String "lamp_main" 两个命名空间
##   - KNOWN_KINDS 补齐到 17 个（含 5 个 lamp_* kind）
## 依赖一律用 preload 常量。

const CTimedEventScript := preload("res://scripts/c/c_timed_event.gd")


func run_all() -> Dictionary:
	var t: Variant = preload("res://tests/c/c_test_base.gd").new()
	_test_01_known_kinds_count(t)
	_test_01b_new_kinds_present(t)
	_test_02_all_lamp_kinds_present(t)
	_test_03_puppet_event_int_object_id(t)
	_test_04_lamp_event_string_object_id(t)
	_test_05_puppet_object_id_out_of_range(t)
	_test_06_unknown_lamp_object_id(t)
	_test_07_unsupported_object_id_type(t)
	_test_08_negative_time_rejected(t)
	_test_09_unknown_kind_rejected(t)
	_test_10_valid_event_passes(t)
	_test_11_payload_contains_kind(t)
	_test_12_compare_order(t)
	_test_13_to_dict_shape(t)
	_test_14_describe_handles_string_object_id(t)
	return t.report()


func _mk(time_ms: int, kind: StringName, object_id: Variant = 0,
		cue_id: String = "", payload: Dictionary = {}) -> Variant:
	return CTimedEventScript.new(time_ms, kind, object_id, cue_id, payload)


func _test_01_known_kinds_count(t: Variant) -> void:
	t.begin("KNOWN_KINDS：A 端共 25 个事件 kind")
	# 权威口径（实测自 A 端代码，非推算）：
	#   puppet_controller 5：drag_begin/drag_end/pose_stance/facing_turn/hand_motion
	#   performance_system 4：cue_hint/cue_fire/cue_hit/cue_miss
	#   remedy_system 5：remedy_open/remedy_success/remedy_timeout/remedy_show/remedy_hide
	#   stage_director 4：stage_start/stage_end + remedy_freeze_begin/remedy_freeze_end
	#   umbrella_controller 2：umbrella_take/umbrella_return
	#   lamp_controller 5：lamp_state_changed/lamp_input_changed/lamp_oil_changed/
	#                      lamp_feedback_changed/lamp_finished
	# 注意 cue_hint.gd 的 stance/hand/move/reach 是线索动作名，不是事件 kind，不计入。
	#
	# 2026-10-05 由 21 改为 25：真 runtime 录制实测暴露 remedy_freeze_begin/end 与
	# umbrella_take/return 被 append_event 静默拒写（白名单外）。这两组的归属有据：
	# stage_director.gd:13 写明冻结区间「供 B 提示、C 记录回放节奏」，
	# umbrella_controller.gd:38-39 定义借伞/还伞且 A-to-B 交接文档 §5 已列。
	t.check_eq(CTimedEventScript.KNOWN_KINDS.size(), 25, "kind 全集应为 25 个")
	t.finish("kind 数量对齐 A 端")


func _test_01b_new_kinds_present(t: Variant) -> void:
	t.begin("KNOWN_KINDS：2026-10-05 新增的 4 个 kind 已补齐")
	var expected: Array = [
		&"remedy_freeze_begin", &"remedy_freeze_end",
		&"umbrella_take", &"umbrella_return",
	]
	for k in expected:
		t.check(CTimedEventScript.KNOWN_KINDS.has(k), "含 %s" % k)
	# 反向：这 4 个必须能通过 validate()，否则等于白名单补了也写不进记录。
	for k in expected:
		var ev: Variant = _mk(1000, k, 0)
		t.check_eq(ev.validate().size(), 0, "%s 通过校验" % k)
	t.finish("新增 kind 可写入记录")


func _test_02_all_lamp_kinds_present(t: Variant) -> void:
	t.begin("KNOWN_KINDS：5 个 lamp_* kind 已补齐")
	var expected: Array = [
		&"lamp_state_changed", &"lamp_input_changed", &"lamp_oil_changed",
		&"lamp_feedback_changed", &"lamp_finished",
	]
	for k in expected:
		t.check(CTimedEventScript.KNOWN_KINDS.has(k), "含 %s" % k)
	t.finish("灯事件 kind 齐全")


func _test_03_puppet_event_int_object_id(t: Variant) -> void:
	t.begin("影人事件：object_id 是 int 0-2")
	for i in 3:
		var ev: Variant = _mk(100, &"pose_stance", i)
		t.check_eq(ev.validate().size(), 0, "影人 object_id=%d 通过校验" % i)
	t.finish("影人 int 命名空间正常")


func _test_04_lamp_event_string_object_id(t: Variant) -> void:
	t.begin("油灯事件：object_id 是 String \"lamp_main\"")
	var ev: Variant = _mk(100, &"lamp_oil_changed", "lamp_main")
	t.check_eq(ev.validate().size(), 0, "灯事件 String object_id 通过校验")
	t.check_eq(typeof(ev.object_id), TYPE_STRING, "object_id 保持 String 类型")
	t.finish("灯 String 命名空间正常")


func _test_05_puppet_object_id_out_of_range(t: Variant) -> void:
	t.begin("影人事件：object_id 越界被拒")
	var hi: Variant = _mk(100, &"pose_stance", 3)
	t.check(hi.validate().size() > 0, "object_id=3 越界（上限 2）")
	var neg: Variant = _mk(100, &"pose_stance", -1)
	t.check(neg.validate().size() > 0, "object_id=-1 越界")
	t.finish("影人越界拦截正确")


func _test_06_unknown_lamp_object_id(t: Variant) -> void:
	t.begin("油灯事件：未知灯对象名被拒")
	var ev: Variant = _mk(100, &"lamp_oil_changed", "lamp_other")
	t.check(ev.validate().size() > 0, "lamp_other 不是合法灯对象")
	var ok: Variant = _mk(100, &"lamp_oil_changed", "lamp_main")
	t.check_eq(ok.validate().size(), 0, "lamp_main 合法")
	t.finish("灯对象名校验正确")


func _test_07_unsupported_object_id_type(t: Variant) -> void:
	t.begin("object_id：不支持的类型被拒（如 float）")
	var ev: Variant = _mk(100, &"pose_stance", 1.5)
	t.check(ev.validate().size() > 0, "float object_id 应被拒绝")
	var arr_ev: Variant = _mk(100, &"pose_stance", [1])
	t.check(arr_ev.validate().size() > 0, "Array object_id 应被拒绝")
	t.finish("非法类型拦截正确")


func _test_08_negative_time_rejected(t: Variant) -> void:
	t.begin("time_ms 为负被拒")
	var ev: Variant = _mk(-1, &"cue_fire", 0, "cue_01")
	t.check(ev.validate().size() > 0, "负时间应被拒绝")
	t.finish("负时间拦截正确")


func _test_09_unknown_kind_rejected(t: Variant) -> void:
	t.begin("未知 kind 被拒")
	var ev: Variant = _mk(100, &"not_a_real_kind", 0)
	t.check(ev.validate().size() > 0, "集合外 kind 应被拒绝")
	t.finish("未知 kind 拦截正确")


func _test_10_valid_event_passes(t: Variant) -> void:
	t.begin("合法事件通过校验")
	var ev: Variant = _mk(250, &"cue_hit", 1, "cue_01", {"accuracy": 0.9})
	t.check_eq(ev.validate().size(), 0, "合法事件应无问题")
	t.finish("合法事件通过")


func _test_11_payload_contains_kind(t: Variant) -> void:
	t.begin("payload 自动含 kind，便于 JSON 化自解释")
	var ev: Variant = _mk(100, &"cue_fire", 0, "cue_01")
	t.check_eq(str(ev.payload.get("kind", "")), "cue_fire", "payload.kind 与顶层同值")
	t.finish("payload 自解释")


func _test_12_compare_order(t: Variant) -> void:
	t.begin("排序：先比 time_ms，同刻比 seq")
	var a: Variant = _mk(100, &"cue_fire", 0, "c1")
	var b: Variant = _mk(200, &"cue_fire", 0, "c2")
	t.check(a.compare_order(b) < 0, "100ms 在 200ms 之前")
	a.assign_seq(1)
	b.assign_seq(2)
	var c: Variant = _mk(100, &"cue_hit", 0, "c1")
	c.assign_seq(2)
	t.check(a.compare_order(c) < 0, "同刻按 seq：1 在 2 之前")
	t.finish("排序规则正确")


func _test_13_to_dict_shape(t: Variant) -> void:
	t.begin("to_dict 顶层字段齐全")
	var ev: Variant = _mk(100, &"cue_fire", 0, "cue_01")
	ev.assign_seq(7)
	var d: Dictionary = ev.to_dict()
	for key in ["time_ms", "kind", "object_id", "cue_id", "payload", "seq"]:
		t.check(d.has(key), "to_dict 含 %s" % key)
	t.check_eq(int(d["seq"]), 7, "seq 透传")
	t.finish("to_dict 结构正确")


func _test_14_describe_handles_string_object_id(t: Variant) -> void:
	t.begin("describe：String object_id 不崩（%d 会报错）")
	var ev: Variant = _mk(100, &"lamp_oil_changed", "lamp_main")
	var desc: String = ev.describe()
	t.check(desc.find("lamp_main") >= 0, "describe 里出现 lamp_main")
	t.finish("describe 兼容 Variant")
