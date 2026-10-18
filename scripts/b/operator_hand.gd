extends RefCounted
## 幕后操作手与三根短签，两关共用同一绘制，连接影人的长签由影人视图绘制。


static func draw_on(canvas: CanvasItem, anchor: Vector2, brightness: float) -> void:
	var wood := Color("#c08f4a") * brightness
	var skin := Color("#e0b783") * brightness
	var edge := Color("#6d4224") * brightness
	for i in 3:
		var x: float = anchor.x - 34.0 + float(i) * 34.0
		canvas.draw_line(
			Vector2(x, anchor.y - 122.0), Vector2(x, anchor.y + 6.0), Color("#4a3419"), 11.0
		)
		canvas.draw_line(Vector2(x, anchor.y - 122.0), Vector2(x, anchor.y + 6.0), wood, 7.0)
	canvas.draw_circle(anchor, 40.0, skin)
	canvas.draw_arc(anchor, 40.0, 0.0, TAU, 36, edge, 3.0)
	for i in 4:
		var x: float = anchor.x - 30.0 + float(i) * 20.0
		var top := Vector2(x - 2.0, anchor.y - 74.0 - float(i % 2) * 10.0)
		canvas.draw_line(Vector2(x, anchor.y - 18.0), top, edge, 16.0)
		canvas.draw_line(Vector2(x, anchor.y - 18.0), top, skin, 12.0)
	canvas.draw_line(anchor + Vector2(-30.0, 10.0), anchor + Vector2(-72.0, -26.0), edge, 20.0)
	canvas.draw_line(anchor + Vector2(-30.0, 10.0), anchor + Vector2(-72.0, -26.0), skin, 15.0)
