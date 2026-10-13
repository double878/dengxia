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


static func key(hall: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	hall._input(event)


static func drag(hall: Node, at: Vector2, delta: Vector2, alt: bool = false) -> void:
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
		check(
			hall.controller.get_puppet(2).stage_pos.x < hall.controller.get_puppet(0).stage_pos.x,
			"小青在白素贞后侧"
		)
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
	await drama()
	check(ResourceLoader.exists("res://scripts/act2/snake_pose.gd"), "完整白蛇应有分节操控")
	if ResourceLoader.exists("res://scripts/act2/snake_pose.gd"):
		snake_contract()
	print("ACT2_ACTIONS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


static func advance(hall: Node, seconds: float) -> void:
	for _i in range(int(ceil(seconds * 60.0))):
		hall._process(1.0 / 60.0)


static func right(hall: Node, id: int) -> void:
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_RIGHT
	button.pressed = true
	button.position = (
		hall.snake.body_position() if id == 3 else hall._views[id].head_screen_position()
	)
	hall._input(button)


static func take(hall: Node, id: int) -> void:
	for _i in range(4):
		if hall.controller.controlled_id == id:
			return
		key(hall, KEY_SPACE)


static func hold(hall: Node, code: Key, seconds: float) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	advance(hall, seconds)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()


func snake_contract() -> void:
	var pose: RefCounted = load("res://scripts/act2/snake_pose.gd").new()
	pose.setup(Vector2(768, 640))
	var before: PackedVector2Array = pose.points.duplicate()
	check(pose.drag_head(pose.head_position() + Vector2(35, -20)), "蛇头可拖动")
	check(pose.points != before, "拖蛇头应带动相邻身体弯曲")
	for i in range(before.size() - 1):
		check(
			(
				absf(
					(
						pose.points[i].distance_to(pose.points[i + 1])
						- before[i].distance_to(before[i + 1])
					)
				)
				< 0.01
			),
			"分节长度保持 %d" % i
		)
	var bent: PackedVector2Array = pose.points.duplicate()
	pose.move(Vector2(70, 0))
	pose.tick(0.2)
	check(pose.position.x == 838 and pose.points == bent, "整移不改变弯曲姿态")
	var saved: PackedVector2Array = pose.points.duplicate()
	check(not pose.drag_head(Vector2(NAN, 0)) and pose.points == saved, "非法目标保留上一姿态")
	pose.drag_head(Vector2(100000, -100000))
	for point: Vector2 in pose.points:
		check(point.is_finite(), "超范围拖头不产生非有限坐标")


func drama() -> void:
	var hall: Node = HALL.instantiate()
	root.add_child(hall)
	hall.set_process(false)
	await process_frame
	advance(hall, 20.0)
	var actions: Variant = hall.get("actions")
	check(actions != null, "普通字幕结束后应等待小青实际离场")
	if actions == null:
		hall.queue_free()
		await process_frame
		return
	check(actions.phase == "qing_exit", "字幕不得跳过小青离场")
	var frozen_song: int = hall.clock.get_song_time_ms()
	advance(hall, 30.0)
	check(
		actions.phase == "qing_exit" and hall.clock.get_song_time_ms() == frozen_song,
		"等待无超时，歌曲时钟冻结"
	)
	right(hall, 2)
	check(actions.phase == "qing_exit" and not actions.qing_departed, "当前位置误退场不算买酒菜")
	key(hall, KEY_3)
	take(hall, 2)
	drag(hall, hall._views[2].torso_screen_position(), Vector2(-430, 0))
	right(hall, 2)
	check(actions.qing_departed and not hall.on_stage.has(2), "走到左台边后小青正式离场")
	key(hall, KEY_3)
	check(not hall.on_stage.has(2), "已去买菜的小青不可重新串场")
	advance(hall, 4.0)
	check(actions.phase == "cup", "小青离场后等待真实递酒")
	check(actions.cup_owner == -1, "没有取杯动作时杯仍在桌上")
	take(hall, 1)
	drag(
		hall,
		hall._views[1].hand_screen_position("right"),
		Vector2(1035, 415) - hall._views[1].hand_screen_position("right")
	)
	check(actions.cup_owner == 1, "许仙腕点到桌杯后取杯")
	right(hall, 1)
	check(actions.cup_owner == 1, "持杯误退场不丢失杯归属")
	key(hall, KEY_2)
	take(hall, 1)
	drag(hall, hall._views[1].torso_screen_position(), Vector2(-152, 0))
	advance(hall, 0.2)
	take(hall, 0)
	var offered: Vector2 = hall._views[1].hand_screen_position(actions.cup_hand)
	drag(
		hall,
		hall._views[0].hand_screen_position("left"),
		offered - hall._views[0].hand_screen_position("left")
	)
	check(actions.cup_owner == 0 and actions.phase == "drink", "两人手实际靠近后转移唯一酒杯")
	advance(hall, 3.0)
	check(not actions.drunk, "接杯后没有送到嘴边不能喝完")
	drag(
		hall,
		hall._views[0].hand_screen_position("left"),
		hall._views[0].mouth_screen_position() - hall._views[0].hand_screen_position("left")
	)
	key(hall, KEY_ESCAPE)
	advance(hall, 3.0)
	check(not actions.drunk, "暂停时饮酒保持不计时")
	key(hall, KEY_ESCAPE)
	advance(hall, 0.8)
	check(actions.drunk, "杯送到嘴边并保持后饮酒完成")
	advance(hall, 8.0)
	check(actions.phase == "medicine_exit", "不适身段自由，字幕后等待许仙取药离场")
	right(hall, 1)
	check(not actions.medicine_departed, "当前位置误退场不算取药")
	key(hall, KEY_2)
	take(hall, 1)
	drag(hall, hall._views[1].torso_screen_position(), Vector2(740, 0))
	right(hall, 1)
	check(actions.medicine_departed and actions.phase == "darken", "取药必须从右台边离场")
	check(not actions.can_enter_snake(), "亮灯时不允许上白蛇")
	key(hall, KEY_4)
	check(not hall.on_stage.has(3), "未压暗换身不得出现白蛇")
	hall.lamp_controller.lamp.exposure = 0.10
	advance(hall, 0.1)
	check(actions.phase == "replace", "压暗后等待玩家收走白素贞")
	key(hall, KEY_4)
	check(not hall.on_stage.has(3), "白素贞在场时不能同时上蛇")
	right(hall, 0)
	check(actions.white_removed and not hall.on_stage.has(0), "暗场实际收白素贞")
	key(hall, KEY_4)
	check(hall.on_stage.has(3), "饮酒和取药离场完成后允许上完整白蛇")
	if hall.on_stage.has(3):
		key(hall, KEY_1)
		check(not hall.on_stage.has(0), "人身和蛇身互斥")
		key(hall, KEY_2)
		check(not hall.on_stage.has(1), "未显形时许仙不能提前返回")
		hall.lamp_controller.lamp.exposure = 0.80
		advance(hall, 0.1)
		check(actions.phase == "return" and actions.collapse_progress == 0.0, "许仙离场时显形不能惊倒")
		var snake_before: Vector2 = hall.snake.position
		var snake_points: PackedVector2Array = hall.snake.points.duplicate()
		right(hall, 3)
		check(not hall.on_stage.has(3) and actions.phase == "return", "白蛇误退场保留显形进度")
		key(hall, KEY_4)
		check(
			(
				hall.on_stage.has(3)
				and hall.snake.position == snake_before
				and hall.snake.points == snake_points
			),
			"白蛇恢复不重置姿态"
		)
		key(hall, KEY_2)
		check(hall.controller.get_puppet(1).stage_pos.x >= 0.90, "许仙从取药的右侧返回")
		var return_pos: Vector2 = hall.controller.get_puppet(1).stage_pos
		right(hall, 1)
		key(hall, KEY_2)
		check(
			(
				hall.on_stage.has(1)
				and hall.controller.get_puppet(1).stage_pos == return_pos
				and actions.phase == "return"
			),
			"返回后误退许仙可恢复且不重置走位"
		)
		advance(hall, 5.0)
		check(actions.phase == "return", "许仙站在远处不能提前惊倒")
		take(hall, 1)
		drag(hall, hall._views[1].torso_screen_position(), Vector2(-690, 0))
		advance(hall, 0.2)
		check(actions.phase == "startled", "许仙回场走近显形白蛇后惊退")
		key(hall, KEY_ESCAPE)
		var progress: float = actions.collapse_progress
		advance(hall, 2.0)
		check(actions.collapse_progress == progress, "暂停冻结惊倒")
		key(hall, KEY_ESCAPE)
		advance(hall, 2.0)
		check(actions.phase == "finished" and hall._views[1].fall_angle > 1.4, "惊倒结束保持倒地")
		check(
			(
				hall._views[1].hand_screen_position("left").y <= 690
				and hall._views[1].hand_screen_position("right").y <= 690
			),
			"倒地收势双手留在舞台内"
		)
		check(
			(
				hall.controller.get_puppet(1).turn_progress >= 0.99
				and hall.controller.get_puppet(1).facing == -1.0
			),
			"许仙完整面对白蛇后惊倒，倒地不冻结在翻面中途"
		)
		var dead_pos: Vector2 = hall.controller.get_puppet(1).stage_pos
		key(hall, KEY_R)
		key(hall, KEY_2)
		advance(hall, 3.0)
		check(
			hall.controller.get_puppet(1).stage_pos == dead_pos and hall._views[1].fall_angle > 1.4,
			"结尾不复活、不重复惊倒"
		)
	hall.queue_free()
	await process_frame
