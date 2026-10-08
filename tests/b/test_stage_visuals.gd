extends RefCounted
## 防止灯距改变实体挂点、显露度隐藏操作对象，以及火光使用不可重现的墙钟。

const TestBase := preload("res://tests/a/a_test_base.gd")
const PuppetView := preload("res://scripts/a_test/placeholder_puppet.gd")
const LampView := preload("res://scripts/a_test/placeholder_lamp.gd")
const PuppetData := preload("res://scripts/a/puppet_state.gd")
const LampData := preload("res://scripts/a/lamp_state.gd")
const Clock := preload("res://scripts/a/music_clock.gd")


func run_all() -> Dictionary:
	var t: ATestBase = TestBase.new()
	_test_entity_geometry(t)
	_test_projection_geometry(t)
	_test_flame_time_and_feedback(t)
	return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed}


func _view(mode: int) -> PlaceholderPuppet:
	var view: PlaceholderPuppet = PuppetView.new()
	view.puppet_state = PuppetData.new(0)
	view.puppet_state.head_id = 0
	view.puppet_state.stage_pos = Vector2(0.5, 0.5)
	view.puppet_state.hand_angle = Vector2(PI * 0.5, PI * 0.2)
	view.lamp_state = LampData.new()
	view.set("render_mode", mode)
	return view


func _test_entity_geometry(t: ATestBase) -> void:
	t.begin("实体尺寸、手腕和命中不受灯距/显露度影响")
	var view: PlaceholderPuppet = _view(1)
	var before: Dictionary = view.puppet_state.to_dict().duplicate(true)
	view.lamp_state.distance = 0.0
	view.lamp_state.exposure = 0.0
	var height: float = view.figure_px_height()
	var left: Vector2 = view.hand_screen_position("left")
	var right: Vector2 = view.hand_screen_position("right")
	var tag: Vector2 = view.chest_tag_screen()
	view.lamp_state.distance = 1.0
	view.lamp_state.exposure = 1.0
	t.check_approx(view.figure_px_height(), height, 0.001, "移动灯不能改变实体物件尺寸")
	t.check(view.hand_screen_position("left").is_equal_approx(left), "实体左腕不能随灯移动")
	t.check(view.hand_screen_position("right").is_equal_approx(right), "实体右腕不能随灯移动")
	t.check(view.chest_tag_screen().is_equal_approx(tag), "实体命中点应保持原坐标")
	view.lamp_state.exposure = 0.0
	t.check_approx(view.exposure_alpha(), 1.0, 0.001, "低显露仍可辨认并操作实体")
	t.check_eq(view.puppet_state.to_dict(), before, "显示不能改写姿态状态")
	view.free()
	t.finish("灯操作只改变幕影，不改变实体与输入坐标")


func _test_projection_geometry(t: ATestBase) -> void:
	t.begin("全部影人及挂起者的投影响应灯距")
	for id in range(3):
		var view: PlaceholderPuppet = _view(2)
		view.puppet_state.puppet_id = id
		view.puppet_state.head_id = id
		view.puppet_state.hook_slot = 0 if id > 0 else -1
		view.lamp_state.distance = 0.0
		var far_height: float = view.figure_px_height()
		view.lamp_state.distance = 1.0
		t.check(view.figure_px_height() > far_height * 1.5, "滚轮应明显放大全场投影，含挂起者")
		var centre: Vector2 = view.stage_to_screen(view.puppet_state.stage_pos)
		var first: Vector2 = view.hand_screen_position("left")
		view.puppet_state.facing *= -1.0
		var flipped: Vector2 = view.hand_screen_position("left")
		t.check_approx(first.x + flipped.x, centre.x * 2.0, 0.01, "投影的手和身体一起翻面")
		t.check_approx(first.y, flipped.y, 0.01, "翻面保持腕高")
		view.free()
	t.finish("同一灯距作用于所有在场实体的影像")


func _test_flame_time_and_feedback(t: ATestBase) -> void:
	t.begin("火光可重现、暂停冻结且合拍更稳")
	var view: PlaceholderLamp = LampView.new()
	view.lamp = LampData.new()
	if not t.check(view.has_method("set_visual_time"), "油灯须接受统一视觉时间"):
		view.free()
		t.finish("当前油灯还没有可重现的视觉时钟接口")
		return
	var clock: MusicClock = Clock.new()
	clock.start()
	clock.update(0.25)
	view.call("set_visual_time", clock.get_real_time_ms(), clock.get_song_time_ms(), 96.0)
	var sample: Dictionary = view.call("lighting_sample")
	clock.pause()
	clock.update(5.0)
	view.call("set_visual_time", clock.get_real_time_ms(), clock.get_song_time_ms(), 96.0)
	t.check_eq(view.call("lighting_sample"), sample, "暂停五秒也必须保持同一火光样本")
	clock.resume()
	clock.update(0.3)
	view.call("set_visual_time", clock.get_real_time_ms(), clock.get_song_time_ms(), 96.0)
	t.check(view.call("lighting_sample") != sample, "恢复后自然火光应继续变化")
	view.lamp.flame_feedback = 1.0
	var stable: Dictionary = view.call("lighting_sample")
	view.lamp.flame_feedback = 0.0
	var unstable: Dictionary = view.call("lighting_sample")
	t.check(float(stable["shake_amplitude"]) < float(unstable["shake_amplitude"]), "高合拍不能比低合拍更抖")
	var lamp_before: Dictionary = view.lamp.to_dict().duplicate(true)
	for ms in range(0, 10000, 83):
		view.call("set_visual_time", ms, ms, 96.0)
		var frame: Dictionary = view.call("lighting_sample")
		t.check_in_range(float(frame["cloth_flicker"]), 0.96, 1.04, "整块幕亮度波动须受限")
		t.check_finite(float(frame["tip_x"]), "火苗位置必须有限")
	t.check_eq(view.lamp.to_dict(), lamp_before, "自然火光不得扣油或修改反馈")
	view.free()
	t.finish("既有时钟决定画面，反馈只改变稳定程度")
