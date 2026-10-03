extends SceneTree
## A 范围无头行为测试入口。
## 运行：
##   godot.exe --headless --path . --script res://tests/a/run_tests.gd
## 全部通过退出码为 0，任一断言失败退出码为 1。

const TestPuppetControlsScript := preload("res://tests/a/test_puppet_controls.gd")


func _initialize() -> void:
	print("《灯下》A 范围行为测试")
	print("Godot %s" % Engine.get_version_info().get("string", "unknown"))
	print("")

	var suite: TestPuppetControls = TestPuppetControlsScript.new()
	var result: Dictionary = suite.run_all()
	quit(int(result["exit_code"]))
