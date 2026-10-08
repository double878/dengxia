extends Node2D
class_name StageSurface
## 一个透射画布承载所有影人和道具；幕面之外从不复制或模糊。

const PuppetView := preload("res://scripts/a_test/placeholder_puppet.gd")
const ClothShader := preload("res://shaders/stage_cloth.gdshader")
var cloth := Rect2(66, 92, 1788, 588)
var front_view: bool = false
var extra_softness: float = 0.0
## 仅开发离幕样例使用；正常演出保持 1.0，不增加游戏输入。
var extra_projection_scale: float = 1.0
var projection_views: Array[PlaceholderPuppet] = []
var projection_viewport: SubViewport
var cloth_material: ShaderMaterial
var _surface: ColorRect
var _umbrella: UmbrellaVisual


func configure(rect: Rect2) -> void:
	cloth = rect
	projection_viewport = SubViewport.new()
	projection_viewport.name = "Transmission"
	projection_viewport.size = Vector2i(1920, 1080)
	projection_viewport.disable_3d = true
	projection_viewport.world_2d = World2D.new()
	projection_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(projection_viewport)
	var white := ColorRect.new()
	white.size = Vector2(1920, 1080)
	white.color = Color.WHITE
	projection_viewport.add_child(white)
	_umbrella = UmbrellaVisual.new()
	var prop_material := ShaderMaterial.new()
	prop_material.shader = preload("res://shaders/puppet_transmission.gdshader")
	_umbrella.material = prop_material
	projection_viewport.add_child(_umbrella)
	for id in range(3):
		var view: PlaceholderPuppet = PuppetView.new()
		view.name = "Projection%d" % id
		view.render_mode = PlaceholderPuppet.RenderMode.PROJECTION
		projection_viewport.add_child(view)
		projection_views.append(view)
	_umbrella.views = projection_views
	cloth_material = ShaderMaterial.new()
	cloth_material.shader = ClothShader
	cloth_material.set_shader_parameter("weave", preload("res://assets/stage/cotton_weave.png"))
	cloth_material.set_shader_parameter("transmission", projection_viewport.get_texture())
	cloth_material.set_shader_parameter("cloth_origin", cloth.position)
	cloth_material.set_shader_parameter("cloth_size", cloth.size)
	_surface = ColorRect.new()
	_surface.position = cloth.position
	_surface.size = cloth.size
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.material = cloth_material
	add_child(_surface)


func update_light(lamp: LampState, real_ms: int, song_ms: int, bpm: float) -> void:
	var light: Dictionary = StageLight.sample(lamp, real_ms, song_ms, bpm)
	cloth_material.set_shader_parameter("exposure", StageLight.unit(lamp.exposure))
	cloth_material.set_shader_parameter("oil", StageLight.unit(lamp.oil))
	cloth_material.set_shader_parameter("distance", StageLight.unit(lamp.distance))
	cloth_material.set_shader_parameter("flicker", light["cloth_flicker"])
	cloth_material.set_shader_parameter("visual_seconds", light["visual_seconds"])
	cloth_material.set_shader_parameter("softness", lerpf(0.65, 1.65, StageLight.unit(lamp.distance)) + extra_softness)
	cloth_material.set_shader_parameter("front_view", front_view)
	var shear: float = lerpf(-0.008, 0.008, StageLight.unit(lamp.distance))
	var shift := Vector2(shear * -cloth.get_center().y + float(light["tip_x"]) * 0.10, lerpf(1.5, -2.0, StageLight.unit(lamp.distance)))
	var magnification: float = clampf(extra_projection_scale, 1.0, 1.15)
	shift += cloth.get_center() * (1.0 - magnification)
	for view: PlaceholderPuppet in projection_views:
		view.lamp_state = lamp
		view.transform = Transform2D(Vector2(magnification, 0), Vector2(shear * magnification, magnification), shift)
	_umbrella.transform = projection_views[0].transform
	_umbrella.queue_redraw()


func sync_puppets(states: Array, on_stage: Array, umbrella: UmbrellaController = null) -> void:
	_umbrella.umbrella = umbrella
	for id in range(projection_views.size()):
		var view: PlaceholderPuppet = projection_views[id]
		view.puppet_state = states[id] if id < states.size() else null
		view.visible = on_stage.has(id) and view.puppet_state != null
		view._held_prop_hand = umbrella.holder_hand_of() if umbrella != null and umbrella.holder_id_of() == id else ""


func projected_hand_position(id: int, hand: String) -> Vector2:
	if id < 0 or id >= projection_views.size():
		return Vector2.ZERO
	var view: PlaceholderPuppet = projection_views[id]
	if not view.visible or view.puppet_state == null:
		return Vector2.ZERO
	var point: Vector2 = view.transform * view.hand_screen_position(hand)
	if front_view:
		point.x = cloth.get_center().x * 2.0 - point.x
	return point
