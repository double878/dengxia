extends RefCounted
## 补救只画手、方向和目标，位置由正式场景的真实几何提供。

const TeacherHand := preload("res://scripts/b/teacher_hand.gd")


static func draw_on(
	canvas: CanvasItem, cloth: Rect2, start: Vector2, target: Vector2, label: String, real_s: float
) -> void:
	canvas.draw_rect(cloth, Color(0.06, 0.04, 0.02, 0.16))
	canvas.draw_rect(cloth, Color(0.98, 0.72, 0.25, 0.80), false, 6.0)
	var color := Color("#f7ce76")
	var direction: Vector2 = target - start
	canvas.draw_arc(target, 24.0, 0, TAU, 32, color, 3.0)
	if direction.length() > 45.0:
		canvas.draw_line(start, target, color, 2.0)
		var unit: Vector2 = direction.normalized()
		canvas.draw_line(target, target - unit.rotated(0.5) * 20.0, color, 3.0)
		canvas.draw_line(target, target - unit.rotated(-0.5) * 20.0, color, 3.0)
	var progress: float = (sin(real_s * 3.5) + 1.0) * 0.5
	var base: Vector2 = start.lerp(target, progress) + Vector2(0, 85)
	canvas.draw_arc(base, 46.0, 0, TAU, 40, Color(1.0, 0.85, 0.5, 0.35), 5.0)
	TeacherHand.draw_on(canvas, base, false, 0.95)
	canvas.draw_string(
		ThemeDB.fallback_font,
		Vector2(clampf(target.x + 30, 95, 1450), clampf(target.y - 20, 140, 940)),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		22,
		color
	)
