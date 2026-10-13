extends SceneTree
## 正式厅堂的动作回归：通过真实宿主输入操作，防止空场、坐姿误起身和串拖动。

const HALL := preload("res://scenes/act2/hall.tscn")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ACT2_ACTIONS: " + label)


func key(hall: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	hall._input(event)


func drag(hall: Node, at: Vector2, delta: Vector2, alt: bool = false) -> void:
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = true
	button.position = at
	button.alt_pressed = alt
	hall._input(button)
	var motion := InputEventMouseMotion.new()
	motion.position = at + delta
	motion.relative = delta
	motion.alt_pressed = alt
	hall._input(motion)
	button.position = motion.position
	button.pressed = false
	hall._input(button)
	hall._process(1.0 / 60.0)


func _run() -> void:
	var hall: Node = HALL.instantiate()
	root.add_child(hall)
	hall.set_process(false)
	await process_frame
	var complete: bool = true
	for name: String in ["Baisuzhen", "Xuxian", "Xiaoqing"]:
		var exists: bool = hall.get_node_or_null(name) != null
		check(exists, "正式开场缺少 " + name)
		complete = complete and exists
	if complete:
		check(hall.on_stage == [0, 1, 2], "开场三人应已在场")
		check(hall.seated == [true, true, false], "两人坐好，小青站立服侍")
		check(hall.controller.get_puppet(0).facing == 1.0, "白素贞面向许仙")
		check(hall.controller.get_puppet(1).facing == -1.0, "许仙面向白素贞")
		check(hall.controller.get_puppet(2).stage_pos.x < hall.controller.get_puppet(0).stage_pos.x, "小青在白素贞后侧")
		key(hall, KEY_SPACE)
		check(hall.controller.controlled_id == 0, "空格先接手白素贞")
		var view: PlaceholderPuppet = hall._views[0]
		var before: Vector2 = hall.controller.get_puppet(0).stage_pos
		drag(hall, view.hand_screen_position("right"), Vector2(20, -20))
		check(hall.controller.get_puppet(0).elbow_angle.y > 0.01, "正式拖手产生弯肘")
		check(hall.seated[0] and hall.controller.get_puppet(0).stage_pos == before, "拖手保留坐姿和座位")
		key(hall, KEY_R)
		drag(hall, view.torso_screen_position(), Vector2(-100, 0))
		check(not hall.seated[0], "拖离凳子应自动起身")
		check(hall.controller.get_puppet(0).stage_pos.x < before.x - 0.04, "拖胸签真实走位")
		check(not hall._surface.projection_views[0].seated, "投影同步起身")
		key(hall, KEY_SPACE)
		check(hall.controller.controlled_id == 1, "空格换到许仙")
		key(hall, KEY_ESCAPE)
		var paused_pos: Vector2 = hall.controller.get_puppet(1).stage_pos
		drag(hall, hall._views[1].torso_screen_position(), Vector2(200, 0))
		check(hall.controller.get_puppet(1).stage_pos == paused_pos, "暂停拒绝人物拖动")
		key(hall, KEY_ESCAPE)
		check(not hall._puppet_input.is_drag_active(), "恢复暂停不继承旧拖动")
	hall.queue_free()
	await process_frame
	print("ACT2_ACTIONS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
