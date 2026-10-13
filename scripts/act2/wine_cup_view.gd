extends Node2D
## 唯一动态酒杯，实体和透射仅读同一归属以及各自视图的腕点。

const CUP := preload("res://assets/scenery/level2b/wine_cup_red.png")
var actions: RefCounted
var views: Array[PlaceholderPuppet] = []
var on_stage: Array[int] = []


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if actions == null or actions.cup_owner < 0 or not on_stage.has(actions.cup_owner):
		return
	var wrist: Vector2 = views[actions.cup_owner].hand_screen_position(actions.cup_hand)
	draw_texture_rect(CUP, Rect2(wrist - Vector2(18, 25), Vector2(36, 34)), false)
