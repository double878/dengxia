extends SceneTree

func _initialize() -> void:
	var result: Dictionary = preload("res://tests/a/test_act1_opera.gd").new().run_all()
	quit(result.exit_code)
