extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var result: Dictionary = preload("res://tests/b/test_performance_audio.gd").new().run_all()
	# 等混音线程释放本轮已停止的同步流，避免退出与清理音频资源争用。
	await create_timer(0.15).timeout
	quit(result["exit_code"])
