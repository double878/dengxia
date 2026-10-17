extends SceneTree
## 厅堂修订的可见行为：双人直接开唱，宽容取杯，头旁短暂停留饮酒。

const Helper := preload("res://tests/c/run_act2_actions.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("HALL_REFINEMENT: " + label)


func _run() -> void:
	var hall: Node = load("res://scenes/act2/hall.tscn").instantiate()
	root.add_child(hall)
	hall.set_process(false)
	await process_frame
	check(hall.audio.problem.is_empty() and hall.music_cues.hit != null, "厅堂与惊叫音源完整初始化")
	check(hall.actions.phase == "duet" and hall.on_stage == [0, 1], "厅堂只有许仙与白素贞，直接对唱")
	Helper.key(hall, KEY_3)
	check(not hall.on_stage.has(2), "小青不再串场或参与接手")
	if failures:
		hall.queue_free()
		await process_frame
		quit(1)
		return
	Helper.deterministic_clock(hall)
	hall.clock.advance_to_ms(int(hall.audio.config.duet_gate_ms))
	Helper.advance(hall, .02)
	Helper.take(hall, 1)
	var target: Vector2 = hall.actions.CUP_POSITION + Vector2(40, -5)
	Helper.drag(
		hall,
		hall._views[1].hand_screen_position("right"),
		target - hall._views[1].hand_screen_position("right")
	)
	var wrist: Vector2 = hall._views[1].hand_screen_position("right")
	check(wrist.distance_to(hall.actions.CUP_POSITION) > 26, "样本确实处于旧取杯范围外")
	check(hall.actions.cup_owner == 1, "手靠近杯子即取到，不需精确瞄准杯心")
	Helper.drag(hall, hall._views[1].torso_screen_position(), Vector2(-152, 0))
	Helper.advance(hall, .2)
	Helper.take(hall, 0)
	var offered: Vector2 = hall._views[1].hand_screen_position(hall.actions.cup_hand)
	Helper.drag(
		hall,
		hall._views[0].hand_screen_position("left"),
		offered - hall._views[0].hand_screen_position("left")
	)
	check(hall.actions.cup_owner == 0, "递杯仍需双方实际手腕靠近")
	if hall.actions.cup_owner == 0:
		target = hall._views[0].head_screen_position() + Vector2(40, -30)
		Helper.drag(
			hall,
			hall._views[0].hand_screen_position(hall.actions.cup_hand),
			target - hall._views[0].hand_screen_position(hall.actions.cup_hand)
		)
		wrist = hall._views[0].hand_screen_position(hall.actions.cup_hand)
		check(wrist.distance_to(hall._views[0].mouth_screen_position()) > 24, "饮酒样本在旧嘴部范围外")
		Helper.advance(hall, .3)
		check(not hall.actions.drunk, "靠近头部仍须停留，不能立即饮完")
		Helper.key(hall, KEY_ESCAPE)
		Helper.advance(hall, 2)
		check(not hall.actions.drunk, "菜单暂停不累计饮酒停留")
		Helper.key(hall, KEY_ESCAPE)
		Helper.advance(hall, .35)
		check(hall.actions.drunk and hall.actions.phase == "bend", "头旁停留半秒可饮下，不要求送到嘴边")
	hall.queue_free()
	await process_frame
	print("HALL_REFINEMENT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
