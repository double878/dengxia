extends Node2D
class_name StageBackdrop

const WOOD: Texture2D = preload("res://assets/stage/wood_grain.png")
var cloth := Rect2(66, 92, 1788, 588)
var frame := Rect2(50, 76, 1820, 620)
var table := Rect2(0, 696, 1920, 288)
var oil: float = 1.0


func _draw() -> void:
	draw_stage(self, cloth, frame, table, oil)


static func wood_band(canvas: Node2D, rect: Rect2, tint: Color) -> void:
	if rect.size.y > rect.size.x * 2.0:
		canvas.draw_set_transform(rect.position + Vector2(rect.size.x, 0), PI * 0.5)
		canvas.draw_texture_rect(WOOD, Rect2(Vector2.ZERO, Vector2(rect.size.y, rect.size.x)), true, tint)
		canvas.draw_set_transform(Vector2.ZERO)
	else:
		canvas.draw_texture_rect(WOOD, rect, true, tint)
	canvas.draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color(0.67, 0.49, 0.28, 0.42), 1.5)
	canvas.draw_line(Vector2(rect.position.x, rect.end.y), rect.end, Color(0.06, 0.04, 0.025, 0.8), 3.0)


static func draw_stage(canvas: Node2D, screen: Rect2, border: Rect2, desk: Rect2, fuel: float) -> void:
	var brightness: float = 0.65 + 0.35 * StageLight.unit(fuel)
	canvas.draw_rect(Rect2(0, 0, 1920, 1080), Color("#171a17"))
	# 立柱与斜撑：只在幕面之外露出，观众不会透过布看见后台。
	for x: float in [36.0, 1852.0]:
		wood_band(canvas, Rect2(x, 64, 32, 875), Color(0.53, 0.49, 0.42) * brightness)
		canvas.draw_line(Vector2(x + 16, 710), Vector2(x + 124 if x < 100 else x - 110, 948), Color("#392d20"), 22.0)
	canvas.draw_rect(border.grow(14), Color("#251c13"))
	wood_band(canvas, Rect2(border.position.x - 10, border.position.y - 10, border.size.x + 20, 26), Color(0.94, 0.83, 0.69) * brightness)
	wood_band(canvas, Rect2(border.position.x - 10, screen.end.y, border.size.x + 20, 30), Color(0.83, 0.72, 0.57) * brightness)
	for x: float in [border.position.x - 10, screen.end.x]:
		wood_band(canvas, Rect2(x, screen.position.y, 26, screen.size.y), Color(0.88, 0.77, 0.63) * brightness)
	# 拼接斜缝、木销与绷布绳结。
	for corner: Vector2 in [screen.position, Vector2(screen.end.x, screen.position.y), screen.end, Vector2(screen.position.x, screen.end.y)]:
		var sx: float = -1.0 if corner.x < 960 else 1.0
		var sy: float = -1.0 if corner.y < 400 else 1.0
		canvas.draw_line(corner, corner + Vector2(sx * 16, sy * 16), Color("#342319"), 2.0)
		canvas.draw_circle(corner + Vector2(sx * 8, sy * 8), 2.5, Color("#261c13"))
	for x in range(98, 1840, 116):
		for y: float in [screen.position.y - 5, screen.end.y + 5]:
			canvas.draw_line(Vector2(x - 3, y - 6), Vector2(x + 3, y + 6), Color("#b5a27c"), 2.0, true)
			canvas.draw_circle(Vector2(x, y), 2.0, Color("#776344"))
	wood_band(canvas, desk, Color(0.43, 0.40, 0.34) * brightness)
	for y: float in [742.0, 807.0, 874.0, 945.0]:
		canvas.draw_line(Vector2(0, y), Vector2(1920, y), Color(0.08, 0.06, 0.04, 0.6), 2.0)
	for i in range(22):
		var at := Vector2(78.0 + fposmod(i * 137.0, 1790.0), 711.0 + fposmod(i * 53.0, 242.0))
		canvas.draw_line(at, at + Vector2(13 + i % 9, 0.7), Color(0.65, 0.48, 0.28, 0.10), 1.0)
	canvas.draw_rect(Rect2(0, desk.end.y - 22, 1920, 22), Color("#211911"))
	canvas.draw_line(Vector2(0, desk.position.y + 3), Vector2(1920, desk.position.y + 3), Color(0.58, 0.41, 0.23, 0.65), 3.0)
