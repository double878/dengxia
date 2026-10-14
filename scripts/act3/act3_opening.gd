extends Node2D
## 正式第三关入口；后续盗草操演从此场景继续，不加载旧教学第三关。


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.size = Vector2(1920, 1080)
	backdrop.color = Color("#1d2422")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var title := Label.new()
	title.text = "第三关 · 盗仙草"
	title.position = Vector2(200, 310)
	title.size = Vector2(1520, 100)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color("#e7c590"))
	add_child(title)
	var detail := Label.new()
	detail.text = "为救官人，白素贞奔赴仙山。\n\n本关演出尚未制作。"
	detail.position = Vector2(200, 455)
	detail.size = Vector2(1520, 220)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 30)
	add_child(detail)
