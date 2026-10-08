extends Node2D
class_name UmbrellaVisual
## 实体与透射复用一套几何，各自读取相应显示节点的腕点。

const LIFT: float = 0.44
const RADIUS: float = 0.45
const DROP: float = 0.20
var views: Array = []
var umbrella: UmbrellaController = null


func _view(id: int) -> PlaceholderPuppet:
	if id < 0 or id >= views.size():
		return null
	var view: PlaceholderPuppet = views[id]
	return view if view.visible and view.puppet_state != null else null


func geometry() -> Dictionary:
	if umbrella == null:
		return {}
	var holder: PlaceholderPuppet = _view(umbrella.holder_id_of())
	if holder == null:
		return {}
	var hand: Vector2 = holder.hand_screen_position(umbrella.holder_hand_of())
	var height: float = holder.figure_px_height()
	var flip: float = holder.flip_width_ratio()
	if umbrella.handing_off:
		var previous: PlaceholderPuppet = _view(umbrella.handoff_from_id())
		if previous != null:
			var blend: float = umbrella.handoff_blend()
			hand = previous.hand_screen_position(umbrella.handoff_from_hand()).lerp(hand, blend)
			height = lerpf(previous.figure_px_height(), height, blend)
			flip = lerpf(previous.flip_width_ratio(), flip, blend)
	return {"hand": hand, "height": height, "flip": flip}


func _draw() -> void:
	var data: Dictionary = geometry()
	if data.is_empty():
		return
	var hand: Vector2 = data["hand"]
	var height: float = data["height"]
	var flip: float = data["flip"]
	var canopy: Vector2 = hand + Vector2(0, -height * LIFT)
	var radius: float = height * RADIUS * flip
	var drop: float = height * DROP
	var wood := Color("#8a5a2b")
	var edge := Color("#3a2a18")
	draw_line(hand, canopy, edge, height * 0.034 * maxf(flip, 0.25), true)
	draw_line(hand, canopy, wood, height * 0.021 * maxf(flip, 0.25), true)
	var rim := PackedVector2Array([
		canopy + Vector2(-radius, drop * 0.68), canopy + Vector2(-radius * 0.5, drop * 0.92),
		canopy + Vector2(0, drop), canopy + Vector2(radius * 0.5, drop * 0.92), canopy + Vector2(radius, drop * 0.68),
	])
	var face := PackedVector2Array([canopy])
	face.append_array(rim)
	draw_colored_polygon(face, Color(0.87, 0.79, 0.62, 0.92))
	for point: Vector2 in rim:
		draw_line(canopy, point, Color(edge.r, edge.g, edge.b, 0.45), 2.0, true)
	draw_polyline(rim, edge, 3.0, true)
