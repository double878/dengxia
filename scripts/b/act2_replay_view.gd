extends Node
## 幕前第二关的场次表现；只读已录状态，复用原操演的影件与道具视图。
const Entrance := preload("res://scripts/act2/act2_entrance.gd")
const Cup := preload("res://scripts/act2/wine_cup_view.gd")
const SnakeView := preload("res://scripts/act2/snake_view.gd")
var surface: StageSurface
var scene_id: int = 0
var binding: CStageBinding
var cup_data := preload("res://scripts/act2/act2_hall_actions.gd").new()
var snake := preload("res://scripts/act2/snake_pose.gd").new()
var cup: Node2D
var snake_view: Node2D
var entrance := Entrance.new()
var dark: ColorRect
var transition_title: Label


func setup(stage_surface: StageSurface) -> void:
	surface = stage_surface
	entrance.setup(surface.cloth)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/puppet_transmission.gdshader")
	cup = Cup.new()
	cup.actions = cup_data
	cup.views = surface.projection_views
	cup.material = material
	surface.projection_viewport.add_child(cup)
	snake_view = SnakeView.new()
	snake_view.pose = snake
	snake_view.projection = true
	snake_view.material = material
	surface.projection_viewport.add_child(snake_view)
	dark = ColorRect.new()
	dark.position = surface.cloth.position
	dark.size = surface.cloth.size
	dark.color = Color(0, 0, 0, 0)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dark.z_index = 3
	surface.add_child(dark)
	transition_title = Label.new()
	transition_title.text = "端阳"
	transition_title.position = Vector2(460, 280)
	transition_title.size = Vector2(1000, 160)
	transition_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	transition_title.add_theme_font_size_override("font_size", 56)
	transition_title.z_index = 4
	surface.add_child(transition_title)


func prepare(view: Dictionary) -> void:
	var scene: int = int(view.get("scene_id", 2))
	if scene != scene_id:
		if binding != null:
			binding.hide()
			binding.queue_free()
		scene_id = scene
		binding = CStageBinding.new()
		binding.stage_id = scene
		binding.enable_rain = false
		binding.z_index = -16
		surface.projection_viewport.add_child(binding)
	for id in range(3):
		var puppet: PlaceholderPuppet = surface.projection_views[id]
		puppet.skin_override = 3 if scene == 2 and id == 0 else -1
		puppet.figure_height = 200.0 if scene == 2 else 340.0
		puppet.seated = bool(view.get("seated", [false, false, false])[id])
		puppet.seat_y = 525.4
		puppet.fall_angle = float(view.get("fall_angle", 0)) if id == 1 else 0.0
		puppet.entrance_mask = (
			entrance.masks[id]
			if scene == 2 and id < 2 and not view.get("entrance_complete", [true, true])[id]
			else null
		)
	var prop: Dictionary = view.get("cup", {})
	cup_data.cup_owner = int(prop.get("owner", -1))
	cup_data.cup_hand = str(prop.get("hand", ""))
	cup.on_stage.assign(view.get("on_stage", []))
	cup.visible = scene == 22
	snake_view.visible = scene == 22 and view.get("on_stage", []).has(3)
	if scene == 22:
		snake.apply_recorded_view(view.get("snake", {}))
		binding.get("_scenery").set_item_visible("wine_cup_red", cup_data.cup_owner < 0)
	dark.color.a = float(view.get("fade", 0))
	transition_title.visible = bool(view.get("transition_title", false))


func sync(lamp: LampState, real_ms: int) -> void:
	cup.transform = surface.projection_views[0].transform
	snake_view.transform = surface.projection_views[0].transform
	snake_view.lamp = lamp
	binding.set_visual_time(real_ms)
