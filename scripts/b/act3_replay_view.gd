extends Node
## 第三幕回放：只读实际四人、出鞘、交锋与原声，不重新编排。
const Sword := preload("res://scripts/act3/sword_view.gd")
const GuardEntrance := preload("res://scripts/act3/guard_entrance.gd")
const FinaleView := preload("res://scripts/act3/finale_view.gd")
var entrance := GuardEntrance.new()
var surface: StageSurface
var sword: Node2D
var swords: Array[Node2D] = []
var binding: CStageBinding
var player: AudioStreamPlayer
var config: Dictionary = {}
var _active: bool = false
var finale_view: Node2D


func setup(stage_surface: StageSurface) -> void:
	surface = stage_surface
	entrance.setup(CStageBinding.CLOTH)
	for id in range(3):
		var puppet: PlaceholderPuppet = surface.projection_views[id]
		puppet.skin_override = [0, 5, 6][id]
		puppet.figure_height = 310.0
	binding = CStageBinding.new()
	binding.stage_id = 3
	binding.enable_rain = false
	binding.z_index = -16
	surface.projection_viewport.add_child(binding)
	for id in range(3):
		var item: Node2D = Sword.new()
		item.actor_id = id
		item.views = surface.projection_views
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/puppet_transmission.gdshader")
		item.material = material
		surface.projection_viewport.add_child(item)
		swords.append(item)
	sword = swords[1]
	finale_view = FinaleView.new()
	surface.projection_viewport.add_child(finale_view)
	finale_view.setup(surface.projection_views, true)
	finale_view.mask = entrance.mask
	config = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/audio/act3-mountain/score.json")
	)
	if bool(config.get("audio_available", false)):
		player = AudioStreamPlayer.new()
		player.stream = load(str(config.main_path)) as AudioStreamWAV
		add_child(player)


func sync(view: Dictionary, paused: bool) -> void:
	var finale: Dictionary = view.get("finale", {})
	var progress: Array = view.get("sword_progress", [0.0, 1.0, 1.0])
	var point: Dictionary = view.get("clash_point", {"x": 0.0, "y": 0.0})
	for id in range(3):
		swords[id].on_stage.assign(view.get("on_stage", []))
		swords[id].transform = surface.projection_views[id].transform
		swords[id].draw_progress = float(progress[id])
		swords[id].flash = float(view.get("clash_strength", 0.0))
		swords[id].flash_point = Vector2(float(point.x), float(point.y))
		surface.projection_views[id]._held_prop_hand = (
			Sword.holding_hand(id) if float(progress[id]) > .01 else ""
		)
	finale_view.transform = surface.projection_views[0].transform
	finale_view.sync(finale, surface.projection_views[0].lamp_state)
	entrance.apply_mask(
		surface.projection_views, sword, bool(view.get("guard_behind_mountain", false))
	)
	entrance.apply_mask(
		surface.projection_views, swords[2], bool(view.get("crane_behind_mountain", false)), 2
	)
	binding.set_visual_time(int(view.get("scene_real_ms", 0)))
	if player == null:
		return
	var state: Dictionary = view.get("audio", {}).get("main", {})
	if not bool(state.get("playing", false)):
		stop()
		return
	var at: float = float(state.get("position_ms", 0)) / 1000.0
	var hold: bool = paused or bool(state.get("paused", false))
	if (
		not _active
		or (player.stream_paused and not hold)
		or absf(player.get_playback_position() - at) > .15
	):
		player.stream_paused = false
		player.play(at)
		_active = true
	player.stream_paused = hold


func stop() -> void:
	if player != null:
		player.stream_paused = false
		player.stop()
	_active = false


func _exit_tree() -> void:
	stop()
	if player != null:
		player.stream = null
