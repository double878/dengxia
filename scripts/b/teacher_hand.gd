extends RefCounted
## 第一关和第二幕共用同一师父手形。仅读位置，不操作影人。


static func draw_on(canvas: CanvasItem, centre: Vector2, outlined: bool, alpha: float) -> void:
	var edge := Color(0.44, 0.25, 0.15, alpha)
	var fill := Color(0.90, 0.73, 0.51, alpha)
	for i in 4:
		var base := Vector2(centre.x - 25.0 + float(i) * 17.0, centre.y - 14.0)
		var tip := Vector2(base.x - 2.0, centre.y - 70.0 - float(i % 2) * 12.0)
		if not outlined:
			canvas.draw_line(base, tip, fill, 11.0)
		canvas.draw_line(base, tip, edge, 3.0)
	var thumb_root: Vector2 = centre + Vector2(-25.0, 16.0)
	var thumb_tip: Vector2 = centre + Vector2(-62.0, -19.0)
	if not outlined:
		canvas.draw_line(thumb_root, thumb_tip, fill, 14.0)
	canvas.draw_line(thumb_root, thumb_tip, edge, 3.0)
	if outlined:
		canvas.draw_arc(centre, 36.0, 0.0, TAU, 32, edge, 4.0)
	else:
		canvas.draw_circle(centre, 36.0, fill)
		canvas.draw_arc(centre, 36.0, 0.0, TAU, 36, edge, 3.0)
