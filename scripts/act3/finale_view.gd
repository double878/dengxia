extends Node2D
## 同一视图显示真实仙翁状态；现场与幕前回放复用，不显示灵芝道具。
## 仙翁头身原稿的外轮廓略高，290 对齐双童 310 的实际可见高度。
const FIGURE_HEIGHT: float = 290.0
var elder := PuppetState.new(3)
var puppet: PlaceholderPuppet
var views: Array[PlaceholderPuppet] = []
var data: Dictionary = {}
var mask: Texture2D


func setup(actor_views: Array[PlaceholderPuppet], projection: bool) -> void:
	views = actor_views
	puppet = PlaceholderPuppet.new()
	puppet.name = "Xianweng"
	puppet.skin_override = 4
	puppet.figure_height = FIGURE_HEIGHT
	puppet.hand_anchor = Vector2(960, 856)
	puppet.render_mode = (
		PlaceholderPuppet.RenderMode.PROJECTION
		if projection
		else PlaceholderPuppet.RenderMode.ENTITY
	)
	puppet.puppet_state = elder
	puppet.z_index = -1
	add_child(puppet)
	var prop_material := ShaderMaterial.new()
	prop_material.shader = (
		preload("res://shaders/puppet_transmission.gdshader")
		if projection
		else preload("res://shaders/puppet_back.gdshader")
	)
	material = prop_material
	visible = false


func sync(view: Dictionary, lamp: LampState) -> void:
	data = view
	visible = bool(data.get("active", false))
	puppet.visible = bool(data.get("elder_visible", false))
	if not visible:
		return
	var state: Dictionary = data.elder
	elder.stage_pos = Vector2(float(state.stage_pos.x), float(state.stage_pos.y))
	elder.hand_angle = Vector2(float(state.hand_angle.left), float(state.hand_angle.right))
	elder.elbow_angle = Vector2(float(state.elbow_angle.left), float(state.elbow_angle.right))
	for field: String in [
		"facing",
		"turn_progress",
		"stance",
		"head_tilt",
		"torso_lean",
		"walk_phase",
		"walk_amount",
		"air_height",
		"leg_spread",
		"body_angle"
	]:
		elder.set(field, state.get(field, 0.0))
	puppet.lamp_state = lamp
	puppet.entrance_mask = mask if bool(data.get("elder_behind", false)) else null
	material.set_shader_parameter("entrance_active", puppet.entrance_mask != null)
	material.set_shader_parameter("entrance_mask", puppet.entrance_mask)
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	# 仙翁拄杖随右腕移动，保持竖直。
	var grip: Vector2 = puppet.hand_screen_position("right")
	var foot: Vector2 = puppet.stage_to_screen(elder.stage_pos)
	var height: float = puppet.figure_px_height()
	var top: Vector2 = grip - Vector2(0, height * .32)
	var crook := PackedVector2Array(
		[
			Vector2(grip.x, foot.y),
			grip,
			top,
			top + Vector2(elder.facing * 4, -8),
			top + Vector2(elder.facing * 13, -11),
			top + Vector2(elder.facing * 19, -6),
		]
	)
	draw_polyline(crook, Color("#503824"), 6, true)
	draw_polyline(crook, Color("#b69558"), 2, true)
