extends Node2D
## 按演员绑定的持剑/出鞘。交锋检测、实体与透射共用同一腕点几何。
var views: Array[PlaceholderPuppet] = []
var on_stage: Array[int] = []
var actor_id: int = 1
var draw_progress: float = 1.0
var flash_point := Vector2.ZERO
var flash: float = 0.0


static func holding_hand(for_actor: int) -> String:
	return "left" if for_actor == 0 else "right"


func geometry() -> Dictionary:
	if actor_id < 0 or actor_id >= views.size() or views[actor_id].puppet_state == null:
		return {}
	var view: PlaceholderPuppet = views[actor_id]
	var state: PuppetState = view.puppet_state
	var height: float = view.figure_px_height()
	var ground: Vector2 = view.stage_to_screen(state.stage_pos)
	var hand: String = holding_hand(actor_id)
	var right_side: bool = hand == "right"
	var shoulder := (
		ground
		+ Vector2(
			view.shoulder_half_width_px(height, 1.0) * (1.0 if right_side else -1.0),
			-height * view.SHOULDER_RATIO + view.walk_body_offset(height)
		)
	)
	var points: Dictionary = UpperBodyPose.arm_points(
		shoulder,
		state.hand_angle.y if right_side else state.hand_angle.x,
		state.elbow_angle.y if right_side else state.elbow_angle.x,
		right_side,
		height
	)
	var matrix: Transform2D = view._skin_figure_transform(ground) * view.upper_transform()
	var wrist: Vector2 = view.hand_screen_position(hand)
	var direction: Vector2 = (wrist - matrix * points.elbow).normalized()
	return {
		"wrist": wrist,
		"tip": wrist + direction * height * 0.60 * draw_progress,
		"direction": direction,
		"height": height
	}


func sheath_geometry() -> Dictionary:
	if actor_id != 0 or views.is_empty() or views[0].puppet_state == null:
		return {}
	var view: PlaceholderPuppet = views[0]
	var height: float = view.figure_px_height()
	var ground: Vector2 = view.stage_to_screen(view.puppet_state.stage_pos)
	var matrix: Transform2D = view._skin_figure_transform(ground) * view.upper_transform()
	var hip := ground + Vector2(0.0, -height * view.HIP_RATIO + view.walk_body_offset(height))
	var reference: float = view.pose_reference_facing()
	return {
		"mouth": matrix * (hip + Vector2(reference * height * .10, -height * .11)),
		"tail": matrix * (hip + Vector2(-reference * height * .38, height * .24)),
	}


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not on_stage.has(actor_id):
		return
	if actor_id != 0 and draw_progress <= .01:
		return
	var data: Dictionary = geometry()
	if data.is_empty():
		return
	var wrist: Vector2 = data.wrist
	var tip: Vector2 = data.tip
	var direction: Vector2 = data.direction
	var side := direction.orthogonal()
	if actor_id == 0:
		var sheath: Dictionary = sheath_geometry()
		var sheath_top: Vector2 = sheath.mouth
		var sheath_end: Vector2 = sheath.tail
		draw_line(sheath_top, sheath_end, Color("#65513b"), 8.0, true)
		draw_line(sheath_top, sheath_end, Color("#ab8546"), 2.0, true)
		if draw_progress <= .01:
			var axis: Vector2 = (sheath_top - sheath_end).normalized()
			var cross := axis.orthogonal() * 13.0
			draw_line(sheath_top - cross, sheath_top + cross, Color("#aa7534"), 5.0, true)
			draw_line(sheath_top, sheath_top + axis * 28.0, Color("#77482a"), 9.0, true)
			draw_circle(sheath_top + axis * 28.0, 6, Color("#b6934d"))
			return
	var base: Vector2 = wrist + direction * 17.0
	var blade := PackedVector2Array([base - side * 6.0, tip, base + side * 6.0])
	draw_colored_polygon(blade, Color("#c6b687"))
	draw_polyline(blade + PackedVector2Array([blade[0]]), Color("#59442b"), 2.0, true)
	draw_line(base, tip - direction * 12.0, Color("#ece0b5"), 1.5, true)
	draw_line(base - side * 18.0, base + side * 18.0, Color("#aa7534"), 6.0, true)
	draw_line(wrist - direction * 20.0, base, Color("#77482a"), 9.0, true)
	draw_circle(wrist - direction * 20.0, 6.0, Color("#b6934d"))
	if actor_id == 0 and flash > 0.0:
		for angle in [0.0, PI / 3.0, PI * 2.0 / 3.0]:
			var ray := Vector2.from_angle(angle) * 15.0 * flash
			draw_line(flash_point - ray, flash_point + ray, Color("#d3973c"), 2.5, true)
