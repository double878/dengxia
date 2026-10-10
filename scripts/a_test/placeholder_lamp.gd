extends Node2D
class_name PlaceholderLamp
## 小碗式油灯显示端，仅读 LampState；火焰与幕面共享显式视觉时间。

@export var anchor: Vector2 = Vector2(268.0, 868.0)
@export var cloth_rect: Rect2 = Rect2()
@export var travel_px: float = 86.0
@export var show_debug_stats: bool = false
var lamp: LampState = null
var _real_ms: int = 0
var _song_ms: int = 0
var _bpm: float = 96.0


func set_visual_time(real_ms: int, song_ms: int, bpm: float = 96.0) -> void:
	_real_ms = real_ms
	_song_ms = song_ms
	_bpm = bpm
	queue_redraw()


func lighting_sample() -> Dictionary:
	return StageLight.sample(lamp, _real_ms, _song_ms, _bpm)


func _unit(field: String) -> float:
	return StageLight.unit(float(lamp.get(field))) if lamp != null else 0.0


func lamp_position() -> Vector2:
	return anchor + Vector2(0.42, -0.91) * travel_px * _unit("distance")


func _process(_delta: float) -> void:
	queue_redraw()


func _ellipse(centre: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(48):
		var angle: float = TAU * i / 48.0
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)


func _glow(centre: Vector2, radius: Vector2, alpha: float) -> void:
	var points := PackedVector2Array([centre])
	var colors := PackedColorArray([Color(1.0, 0.66, 0.25, alpha)])
	for i in range(49):
		var angle: float = TAU * i / 48.0
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
		colors.append(Color(1.0, 0.57, 0.16, 0.0))
	draw_polygon(points, colors)


func _flame(base: Vector2, width: float, height: float, bend: float, color: Color) -> void:
	var points := PackedVector2Array()
	for side: float in [-1.0, 1.0]:
		for i in range(17):
			var t: float = float(i) / 16.0 if side < 0 else 1.0 - float(i) / 16.0
			var x: float = side * width * pow(sin(PI * t), 0.80) * (1.0 - 0.43 * t) + bend * t * t
			points.append(base + Vector2(x, -height * t))
	draw_colored_polygon(points, color)


func _draw() -> void:
	if lamp == null:
		return
	var light: Dictionary = lighting_sample()
	var centre: Vector2 = lamp_position()
	var bright: float = float(light["environment"])
	_ellipse(centre + Vector2(5, 22), Vector2(63, 18), Color(0.04, 0.025, 0.014, 0.62))
	_glow(centre + Vector2(0, -34), Vector2(155, 126), 0.18 * bright * float(light["glow_flicker"]))
	_glow(centre + Vector2(1, 7), Vector2(98, 42), 0.14 * bright)
	_ellipse(centre + Vector2(0, 20), Vector2(27, 9), Color("#352b21"))
	var bowl := PackedVector2Array([centre + Vector2(-49, -13), centre + Vector2(-40, 10), centre + Vector2(-22, 22), centre + Vector2(23, 22), centre + Vector2(41, 9), centre + Vector2(49, -13)])
	draw_colored_polygon(bowl, Color(0.38, 0.29, 0.18) * bright)
	draw_polyline(bowl, Color("#241d16"), 2.5, true)
	_ellipse(centre + Vector2(0, -13), Vector2(49, 16), Color(0.66, 0.49, 0.27) * bright)
	_ellipse(centre + Vector2(0, -14), Vector2(41, 11), Color("#211c15"))
	draw_arc(centre + Vector2(0, -13), 44, 0.10, PI - 0.10, 32, Color(0.72, 0.56, 0.33, bright), 2.8, true)
	draw_line(centre + Vector2(-26, 2), centre + Vector2(-16, 10), Color(0.84, 0.63, 0.32, 0.25 * bright), 2.0, true)
	for i in range(5):
		draw_line(centre + Vector2(-32 + i * 14, 8 + i % 3), centre + Vector2(-27 + i * 14, 9 + i % 3), Color(0.12, 0.09, 0.05, 0.4), 1.0)
	var wick: Vector2 = centre + Vector2(15, -20)
	draw_line(centre + Vector2(4, -14), wick + Vector2(0, -7), Color("#b6a17e"), 4.0, true)
	draw_line(wick, wick + Vector2(0, -8), Color("#30241c"), 3.0, true)
	var base: Vector2 = wick + Vector2(0, -4)
	var height: float = float(light["flame_height"])
	var width: float = float(light["flame_width"])
	var bend: float = float(light["tip_x"])
	_glow(base + Vector2(bend * 0.4, -height * 0.5), Vector2(38, 55), 0.19 * float(light["glow_flicker"]))
	_flame(base, width + 2.0, height + 2.0, bend, Color(1, 0.37, 0.08, 0.22))
	_flame(base, width, height, bend, Color(1, 0.67, 0.17, 0.86))
	_flame(base + Vector2(0, -1), width * 0.53, height * 0.73, bend * 0.55, Color(1, 0.91, 0.55, 0.96))
	_flame(base + Vector2(0, -2), width * 0.24, height * 0.42, bend * 0.2, Color(1, 0.97, 0.82, 1))
	if show_debug_stats:
		draw_string(ThemeDB.fallback_font, centre + Vector2(-60, 55), "灯距 %.2f / 灯油 %.2f" % [_unit("distance"), _unit("oil")], HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
