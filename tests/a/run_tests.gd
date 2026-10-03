extends SceneTree
## A 范围无头行为测试入口。
## 运行：
##   godot.exe --headless --path . --script res://tests/a/run_tests.gd
## 全部通过退出码为 0，任一断言失败退出码为 1。

const TestPuppetControlsScript := preload("res://tests/a/test_puppet_controls.gd")
const TestMusicClockScript := preload("res://tests/a/test_music_clock.gd")
const TestLevel1CuesScript := preload("res://tests/a/test_level1_cues.gd")


func _initialize() -> void:
	print("《灯下》A 范围行为测试")
	print("Godot %s" % Engine.get_version_info().get("string", "unknown"))

	var total_passed: int = 0
	var total_failed: int = 0
	var exit_code: int = 0

	print("")
	print("---- 切片 1：操控 ----")
	var controls: TestPuppetControls = TestPuppetControlsScript.new()
	var controls_result: Dictionary = controls.run_all()
	total_passed += int(controls_result["passed"])
	total_failed += int(controls_result["failed"])
	exit_code = maxi(exit_code, int(controls_result["exit_code"]))

	print("")
	print("---- 切片 2：音乐时钟与关卡时长 ----")
	var music: TestMusicClock = TestMusicClockScript.new()
	var music_result: Dictionary = music.run_all()
	total_passed += int(music_result["passed"])
	total_failed += int(music_result["failed"])
	exit_code = maxi(exit_code, int(music_result["exit_code"]))

	print("")
	print("---- 切片 3：第一关关键动作判定 ----")
	var cues: TestLevel1Cues = TestLevel1CuesScript.new()
	var cues_result: Dictionary = cues.run_all()
	total_passed += int(cues_result["passed"])
	total_failed += int(cues_result["failed"])
	exit_code = maxi(exit_code, int(cues_result["exit_code"]))

	print("")
	print("========================================")
	print("A 范围测试总计：%d 条断言通过，%d 条失败" % [total_passed, total_failed])
	print("========================================")
	quit(exit_code)
