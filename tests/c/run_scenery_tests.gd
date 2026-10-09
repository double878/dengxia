extends SceneTree
## C 侧布景测试入口（与 A 的 run_tests.gd 同一套退出码约定）。
## 运行：
##   godot.exe --headless --path . --script res://tests/c/run_scenery_tests.gd
## 全部通过退出码 0，任一断言失败退出码 1。
##
## 命名说明：不叫 run_tests_c.gd——那个名字属于 feat-replay-from-a 分支的 C 录制回放
## 测试套件，本分支提前占用会在将来合并时撞名。

const TestSceneryScript := preload("res://tests/c/c_test_scenery.gd")


func _initialize() -> void:
	print("《灯下》C 侧布景测试")
	print("Godot %s" % Engine.get_version_info().get("string", "unknown"))
	print("")

	# 用 preload 常量构造、不写 CTestScenery 类型标注：--script 模式对「新建后未重新
	# import 过的类名」解析不可靠，preload 是稳的。
	var suite = TestSceneryScript.new()
	var result: Dictionary = suite.run_all()

	quit(int(result["exit_code"]))
