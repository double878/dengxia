extends Node2D
## 独立开发验收；正常 GameFlow 不引用本场景。状态样例不冒充真实演出记录。

const Surface := preload("res://scripts/b/stage_surface.gd")
const Backdrop := preload("res://scripts/b/stage_backdrop.gd")
const PuppetView := preload("res://scripts/a_test/placeholder_puppet.gd")
const LampView := preload("res://scripts/a_test/placeholder_lamp.gd")
const PropView := preload("res://scripts/b/umbrella_visual.gd")
const CASES: Array[String] = ["normal", "near", "far", "low", "overlap", "head", "turn", "offscreen", "lifted"]
var surface: StageSurface
var backdrop: StageBackdrop
var lamp_view: PlaceholderLamp
var entities: Array[PlaceholderPuppet] = []
var prop: UmbrellaVisual
var states: Array = []
var lamp := LampState.new()
var umbrella := UmbrellaController.new()
var front: bool = true
var paused: bool = true
var case_name: String = "normal"
var visual_ms: float = 1250.0


func _ready() -> void:
	backdrop = Backdrop.new()
	backdrop.z_index = -2
	add_child(backdrop)
	surface = Surface.new()
	surface.z_index = -1
	add_child(surface)
	surface.configure(backdrop.cloth)
	for id in range(3):
		var view: PlaceholderPuppet = PuppetView.new()
		view.render_mode = PlaceholderPuppet.RenderMode.ENTITY
		view.z_index = 20
		add_child(view)
		entities.append(view)
	prop = PropView.new()
	prop.views = entities
	prop.z_index = 18
	var back_material := ShaderMaterial.new()
	back_material.shader = preload("res://shaders/puppet_back.gdshader")
	prop.material = back_material
	add_child(prop)
	lamp_view = LampView.new()
	lamp_view.z_index = 30
	add_child(lamp_view)
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	front = not args.has("back")
	for arg: String in args:
		if arg.begins_with("case="):
			case_name = arg.trim_prefix("case=")
	set_case(case_name)


func set_case(value: String) -> void:
	case_name = value if CASES.has(value) else "normal"
	states.clear()
	for id in range(3):
		var state := PuppetState.new(id)
		state.head_id = id
		state.stage_pos = Vector2([0.28, 0.51, 0.76][id], 0.55)
		state.hand_angle = [Vector2(PI * 0.62, PI * 0.12), Vector2(PI * 0.05, PI * 0.5), Vector2(PI * 0.78, PI * 0.28)][id]
		state.facing = -1.0 if id == 0 else 1.0
		state.is_controlled = id == 0
		state.hook_slot = id - 1 if id > 0 else -1
		states.append(state)
	lamp.distance = 0.5
	lamp.exposure = 1.0
	lamp.oil = 1.0
	lamp.flame_feedback = 0.8
	surface.extra_softness = 0.0
	surface.extra_projection_scale = 1.0
	match case_name:
		"near": lamp.distance = 1.0
		"far": lamp.distance = 0.0
		"low":
			lamp.oil = 0.0
			lamp.exposure = 0.0
			lamp.flame_feedback = 0.0
		"overlap":
			states[0].stage_pos.x = 0.49
			states[2].stage_pos.x = 0.505
			states[1].stage_pos.x = 0.77
		"head":
			states[0].head_id = 2
			states[2].head_id = 0
		"turn": states[0].turn_progress = 0.5
		"offscreen":
			states[0].stage_pos = Vector2(0.025, 0.23)
			states[2].stage_pos = Vector2(0.98, 0.15)
		"lifted":
			surface.extra_softness = 3.5
			surface.extra_projection_scale = 1.08
	umbrella.setup(StageDef.make_level1(), states)
	prop.umbrella = umbrella
	refresh()


func refresh() -> void:
	surface.front_view = front
	surface.update_light(lamp, int(visual_ms), int(visual_ms), 96.0)
	surface.sync_puppets(states, [0, 1, 2], umbrella)
	for id in range(entities.size()):
		var view: PlaceholderPuppet = entities[id]
		view.puppet_state = states[id]
		view.lamp_state = lamp
		view.visible = not front
		view._held_prop_hand = umbrella.holder_hand_of() if umbrella.holder_id_of() == id else ""
	lamp_view.lamp = lamp
	lamp_view.set_visual_time(int(visual_ms), int(visual_ms), 96.0)
	lamp_view.visible = not front
	prop.visible = not front
	(prop.material as ShaderMaterial).set_shader_parameter("environment", 0.58 + 0.42 * lamp.oil)
	prop.queue_redraw()
	backdrop.oil = lamp.oil
	backdrop.queue_redraw()
	queue_redraw()


func _process(delta: float) -> void:
	if not paused:
		visual_ms += delta * 1000.0
		states[0].hand_angle.y = PI * (0.35 + 0.32 * sin(visual_ms * 0.0018))
	refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_TAB: front = not front
		KEY_SPACE: paused = not paused
		KEY_RIGHT: set_case(CASES[(CASES.find(case_name) + 1) % CASES.size()])
		KEY_LEFT: set_case(CASES[posmod(CASES.find(case_name) - 1, CASES.size())])
	refresh()


func _draw() -> void:
	# 幕前不出现幕后桌面、实体灯和操作者。保留相同幕面与木框以便对照。
	if front:
		draw_rect(Rect2(0, 712, 1920, 368), Color("#171a17"))
	draw_rect(Rect2(0, 0, 1920, 58), Color("#171a17"))
	draw_string(ThemeDB.fallback_font, Vector2(76, 40), "开发验收 · %s · %s" % ["幕前" if front else "幕后", case_name], HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color("#d7c7a6"))
	draw_string(ThemeDB.fallback_font, Vector2(76, 1040), "Tab 两面切换    ← → 样例    空格 %s    固定样例，不是演出回放" % ["播放" if paused else "暂停"], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("#a5977b"))
