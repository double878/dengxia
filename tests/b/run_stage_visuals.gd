extends SceneTree

const VisualTests := preload("res://tests/b/test_stage_visuals.gd")


func _initialize() -> void:
	var result: Dictionary = VisualTests.new().run_all()
	quit(int(result["exit_code"]))
