extends Node2D
## 同一蛇姿态的实体/透射表现，分件绘制不改姿态。

const HEAD := preload("res://assets/puppets/snake/head.png")
const NECK := preload("res://assets/puppets/snake/neck.png")
const COILS := preload("res://assets/puppets/snake/coils.png")
var pose: RefCounted
var projection: bool = false
var lamp: LampState
var controlled: bool = false
var drag_part: String = ""
const HAND := Vector2(960, 856)


func _process(_delta: float) -> void:
	queue_redraw()


func hit(point: Vector2) -> String:
	if not visible or pose == null:
		return ""
	if point.distance_to(pose.head_position()) < 43.0:
		return "head"
	if Rect2(pose.position - Vector2(155, 150), Vector2(310, 175)).has_point(point):
		return "body"
	return ""


func _draw() -> void:
	if pose == null:
		return
	var magnification: float = (
		lerpf(0.78, 1.36, lamp.distance) if projection and lamp != null else 1.0
	)
	var base := Transform2D(
		Vector2(pose.flip_width() * magnification, 0), Vector2(0, magnification), pose.position
	)
	draw_set_transform_matrix(base)
	draw_texture_rect(COILS, Rect2(-155, -145, 310, 175), false)
	for i in range(pose.points.size() - 1):
		var first: Vector2 = pose.points[i]
		var next: Vector2 = pose.points[i + 1]
		var direction: Vector2 = next - first
		var width: float = lerpf(45.0, 28.0, float(i) / 4.0)
		var piece := Transform2D(direction.angle() - PI * 0.5, first)
		draw_set_transform_matrix(base * piece)
		draw_texture_rect(
			NECK,
			Rect2(-width * 0.5, -width * 0.22, width, direction.length() + width * 0.44),
			false
		)
	draw_set_transform_matrix(base)
	for i in range(1, pose.points.size() - 1):
		draw_circle(pose.points[i], 3.4, Color("#a8813e"))
		draw_arc(pose.points[i], 3.4, 0, TAU, 16, Color("#594522"), 0.8)
	var head := Transform2D(pose.head_angle(), pose.points[pose.points.size() - 1])
	draw_set_transform_matrix(base * head)
	draw_texture_rect(HEAD, Rect2(-34, -39, 68, 78), false)
	draw_set_transform(Vector2.ZERO)
	if not projection and controlled:
		draw_line(HAND - Vector2(7, 0), pose.body_position(), Color("#92774b"), 2.0)
		draw_line(HAND + Vector2(7, 0), pose.head_position(), Color("#92774b"), 2.0)
		if not drag_part.is_empty():
			var point: Vector2 = (
				pose.head_position() if drag_part == "head" else pose.body_position()
			)
			draw_arc(point, 12, 0, TAU, 24, Color("#e7c590"), 2.0)
