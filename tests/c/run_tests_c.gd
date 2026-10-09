extends SceneTree
## C 范围无头行为测试入口。
## 运行：
##   godot.exe --headless --path . --script res://tests/c/run_tests_c.gd
## 全部通过退出码为 0，任一断言失败退出码为 1。
##
## 文件名用 run_tests_c.gd 而非 run_tests.gd：A 端已有 tests/a/run_tests.gd，
## 将来 A 端合入 origin/main 后将由一人在 tests/ 下建统一入口，
## 本文件保持独立命名以免与 A 端冲突。
##
## 全程用 preload 常量 + Variant，不做 class_name 类型标注：
## godot --headless --script 不读全局类名缓存（本机 .godot 写盘被沙箱阻止），
## 任何 class_name 类型标注都会报 "Could not find type"。

const CTestSnapshotScript := preload("res://tests/c/c_test_snapshot.gd")
const CTestEventScript := preload("res://tests/c/c_test_event.gd")
const CTestRecordScript := preload("res://tests/c/c_test_record.gd")
const CTestRecorderScript := preload("res://tests/c/c_test_recorder.gd")
const CTestStageRecorderScript := preload("res://tests/c/c_test_stage_recorder.gd")
const CTestMockPerformerScript := preload("res://tests/c/c_test_mock_performer.gd")
const CTestReplayPlayerScript := preload("res://tests/c/c_test_replay_player.gd")
const CTestResultFlowScript := preload("res://tests/c/c_test_result_flow.gd")
const CTestReplayVerifierScript := preload("res://tests/c/c_test_replay_verifier.gd")


func _initialize() -> void:
	print("《灯下》C 范围行为测试")
	print("Godot %s" % Engine.get_version_info().get("string", "unknown"))

	var total_passed: int = 0
	var total_failed: int = 0
	var exit_code: int = 0

	var suites: Array = [
		{"title": "切片 1：连续状态采样帧（Snapshot）", "script": CTestSnapshotScript},
		{"title": "切片 1/2：离散事件（TimedEvent）", "script": CTestEventScript},
		{"title": "切片 1：演出记录（PerformanceRecord）", "script": CTestRecordScript},
		{"title": "切片 2：录制器接真实数据源（Recorder）", "script": CTestRecorderScript},
		{"title": "切片 3：录制接线层（StageRecorder）", "script": CTestStageRecorderScript},
		{"title": "切片 4：模拟演出生成器（MockPerformer）", "script": CTestMockPerformerScript},
		{"title": "切片 5：回放播放器（ReplayPlayer）", "script": CTestReplayPlayerScript},
		{"title": "切片 6：收场与结果页流程（ResultFlow）", "script": CTestResultFlowScript},
		{"title": "切片 7：回放验收器（ReplayVerifier）", "script": CTestReplayVerifierScript},
	]

	for suite in suites:
		print("")
		print("---- %s ----" % suite["title"])
		var instance: Variant = suite["script"].new()
		var result: Dictionary = instance.run_all()
		total_passed += int(result["passed"])
		total_failed += int(result["failed"])
		exit_code = maxi(exit_code, int(result["exit_code"]))

	print("")
	print("========================================")
	print("C 范围测试总计：%d 条断言通过，%d 条失败" % [total_passed, total_failed])
	print("========================================")
	quit(exit_code)
