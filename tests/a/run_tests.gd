extends SceneTree
## A 范围无头行为测试入口。
## 运行：
##   godot.exe --headless --path . --script res://tests/a/run_tests.gd
## 全部通过退出码为 0，任一断言失败退出码为 1。

const TestPuppetControlsScript := preload("res://tests/a/test_puppet_controls.gd")
const TestMusicClockScript := preload("res://tests/a/test_music_clock.gd")
const TestLevel1CuesScript := preload("res://tests/a/test_level1_cues.gd")
const TestRemedyScript := preload("res://tests/a/test_remedy.gd")
const TestLampScript := preload("res://tests/a/test_lamp.gd")
const TestLevel1RuntimeScript := preload("res://tests/a/test_level1_runtime.gd")
const TestLevel1AudioScript := preload("res://tests/a/test_level1_audio.gd")


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
	print("---- 切片 4：8 秒补救与结束 ----")
	var remedy: TestRemedy = TestRemedyScript.new()
	var remedy_result: Dictionary = remedy.run_all()
	total_passed += int(remedy_result["passed"])
	total_failed += int(remedy_result["failed"])
	exit_code = maxi(exit_code, int(remedy_result["exit_code"]))

	print("")
	print("---- 切片 5：油灯状态与油量控制 ----")
	var lamp: TestLamp = TestLampScript.new()
	var lamp_result: Dictionary = lamp.run_all()
	total_passed += int(lamp_result["passed"])
	total_failed += int(lamp_result["failed"])
	exit_code = maxi(exit_code, int(lamp_result["exit_code"]))

	print("")
	print("---- 切片 6：第一关 A 侧运行编排 ----")
	var runtime := TestLevel1RuntimeScript.new()
	var runtime_result: Dictionary = runtime.run_all()
	total_passed += int(runtime_result["passed"])
	total_failed += int(runtime_result["failed"])
	exit_code = maxi(exit_code, int(runtime_result["exit_code"]))

	print("")
	print("---- 第一关临时音轨 ----")
	var audio := TestLevel1AudioScript.new()
	var audio_result: Dictionary = audio.run_all()
	total_passed += int(audio_result["passed"])
	total_failed += int(audio_result["failed"])
	exit_code = maxi(exit_code, int(audio_result["exit_code"]))

	print("")
	print("========================================")
	print("A 范围测试总计：%d 条断言通过，%d 条失败" % [total_passed, total_failed])
	print("========================================")
	quit(exit_code)
