extends RefCounted
class_name CTestSnapshot
## 切片 1 行为测试：CSnapshot —— 连续状态采样帧的数据契约。
##
## 断言外部行为与数据契约（字段形状、变化检测、缺省值），不戳私有变量。
## 依赖一律用 preload 常量：--headless --script 不读全局类名缓存。

const CSnapshotScript := preload("res://scripts/c/c_snapshot.gd")


func run_all() -> Dictionary:
	var t: Variant = preload("res://tests/c/c_test_base.gd").new()
	_test_01_frame_shape(t)
	_test_02_default_puppet_dict(t)
	_test_03_from_views_roundtrip(t)
	_test_04_from_views_wrong_length(t)
	_test_05_lamp_fields(t)
	_test_06_changed_fields_detects_stage_pos(t)
	_test_07_changed_fields_detects_head_id(t)
	_test_08_changed_fields_epsilon(t)
	_test_09_same_content_as(t)
	_test_10_no_change_returns_empty(t)
	return t.report()


func _new_frame(time_ms: int = 0) -> Variant:
	return CSnapshotScript.new(time_ms)


func _test_01_frame_shape(t: Variant) -> void:
	t.begin("帧形状：puppets 定长 3，下标即 puppet_id")
	var s: Variant = _new_frame(0)
	t.check_eq(s.puppets.size(), 3, "puppets 长度固定为 3")
	for i in 3:
		t.check_eq(int(s.puppets[i]["puppet_id"]), i, "puppets[%d].puppet_id == %d" % [i, i])
	t.finish("puppets 定长且下标对齐")


func _test_02_default_puppet_dict(t: Variant) -> void:
	t.begin("缺省影人：三态用 -1，位置归一化")
	var s: Variant = _new_frame(0)
	var p: Dictionary = s.puppets[0]
	t.check_eq(int(p["head_id"]), -1, "未分配头用 -1")
	t.check_eq(int(p["hook_slot"]), -1, "未挂起用 -1")
	t.check_eq(bool(p["is_controlled"]), false, "缺省未受控")
	t.check_in_range(float(p["stance"]), 0.0, 1.0, "stance 在 0-1")
	t.check_in_range(float(p["stage_pos"]["x"]), 0.0, 1.0, "stage_pos.x 在 0-1")
	t.finish("缺省值符合契约")


func _test_03_from_views_roundtrip(t: Variant) -> void:
	t.begin("from_views：A 端视图原样落入帧")
	var views: Array = []
	for i in 3:
		views.append({
			"puppet_id": i,
			"stage_pos": {"x": 0.25 + i * 0.1, "y": 0.5},
			"stance": 0.8,
			"facing": -0.5,
			"turn_progress": 0.5,
			"hand_angle": {"left": 0.3, "right": -0.2},
			"head_id": i,
			"hook_slot": -1,
			"is_controlled": true,
		})
	var lamp: Dictionary = {"distance": 0.7, "exposure": 0.3, "oil": 0.9, "flame_feedback": 0.4}
	var s: Variant = CSnapshotScript.from_views(500, views, lamp)
	t.check_eq(s.time_ms, 500, "time_ms 透传")
	t.check_approx(float(s.puppets[1]["stage_pos"]["x"]), 0.35, 1e-6, "puppets[1].stage_pos.x")
	t.check_approx(float(s.puppets[0]["hand_angle"]["left"]), 0.3, 1e-6, "hand_angle.left")
	t.check_eq(int(s.puppets[2]["head_id"]), 2, "head_id 保真")
	t.check_approx(float(s.lamp["distance"]), 0.7, 1e-6, "lamp.distance")
	t.check_approx(float(s.lamp["flame_feedback"]), 0.4, 1e-6, "lamp.flame_feedback")
	t.finish("视图转换保真")


func _test_04_from_views_wrong_length(t: Variant) -> void:
	t.begin("from_views：puppets 长度不符时保留缺省不崩")
	var s: Variant = CSnapshotScript.from_views(0, [{"puppet_id": 0}], {})
	t.check_eq(s.puppets.size(), 3, "长度仍为 3，缺失位置用缺省")
	t.check_eq(int(s.puppets[2]["head_id"]), -1, "缺失影人用缺省值")
	t.finish("长度异常安全降级")


func _test_05_lamp_fields(t: Variant) -> void:
	t.begin("灯态四字段名与 A 端 to_dict 一致")
	var s: Variant = _new_frame(0)
	for key in ["distance", "exposure", "oil", "flame_feedback"]:
		t.check(s.lamp.has(key), "lamp 含字段 %s" % key)
	t.check(not s.lamp.has("flame"), "不叫 flame，叫 flame_feedback")
	t.finish("灯态字段名正确")


func _test_06_changed_fields_detects_stage_pos(t: Variant) -> void:
	t.begin("变化检测：stage_pos 变动被识别")
	var a: Variant = _new_frame(0)
	var b: Variant = _new_frame(33)
	b.puppets[0]["stage_pos"] = {"x": 0.9, "y": 0.0}
	var changed: Array = b.changed_fields(a)
	t.check(changed.has("puppets[0].stage_pos"), "识别出 puppets[0].stage_pos")
	t.check(not changed.has("puppets[1].stage_pos"), "未变的影人不误报")
	t.finish("位移变化检测正确")


func _test_07_changed_fields_detects_head_id(t: Variant) -> void:
	t.begin("变化检测：离散量跳变（换头/挂起）")
	var a: Variant = _new_frame(0)
	var b: Variant = _new_frame(33)
	b.puppets[1]["head_id"] = 5
	b.puppets[2]["hook_slot"] = 0
	var changed: Array = b.changed_fields(a)
	t.check(changed.has("puppets[1].head_id"), "识别 head_id 跳变")
	t.check(changed.has("puppets[2].hook_slot"), "识别 hook_slot 跳变")
	t.finish("离散量跳变被捕捉")


func _test_08_changed_fields_epsilon(t: Variant) -> void:
	t.begin("变化检测：1e-9 绝对误差，微小变化也要触发")
	var a: Variant = _new_frame(0)
	var b: Variant = _new_frame(33)
	b.lamp["flame_feedback"] = float(a.lamp["flame_feedback"]) + 1.0e-6
	var changed: Array = b.changed_fields(a)
	t.check(changed.has("lamp.flame_feedback"),
		"1e-6 量级变化须被识别（is_equal_approx 会漏判）")
	var c: Variant = _new_frame(66)
	c.lamp["flame_feedback"] = float(a.lamp["flame_feedback"]) + 1.0e-12
	var changed2: Array = c.changed_fields(a)
	t.check(not changed2.has("lamp.flame_feedback"), "1e-12 低于阈值不触发")
	t.finish("阈值行为符合 CHANGED_EPSILON")


func _test_09_same_content_as(t: Variant) -> void:
	t.begin("same_content_as：只比内容不比 time_ms")
	var a: Variant = _new_frame(0)
	var b: Variant = _new_frame(999)
	t.check(b.same_content_as(a), "time_ms 不同但内容相同 → true")
	b.puppets[0]["stance"] = 0.77
	t.check(not b.same_content_as(a), "内容变了 → false")
	t.finish("同内容判定正确")


func _test_10_no_change_returns_empty(t: Variant) -> void:
	t.begin("变化检测：完全相同返回空数组")
	var a: Variant = _new_frame(0)
	var b: Variant = _new_frame(33)
	t.check_eq(b.changed_fields(a).size(), 0, "无变化时列表为空")
	t.finish("无变化返回空")
