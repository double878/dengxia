extends RefCounted
class_name ATestBase
## A 范围无头行为测试的最小断言与结果收集工具。
## 不引入第三方测试插件：AGENTS.md 要求复用项目现有能力，Godot 已提供
## SceneTree 脚本入口（--headless --script），足够跑退出码驱动的回归测试。

var passed: int = 0
var failed: int = 0
var failures: Array[String] = []
var _current: String = ""
var _failed_at_test_start: int = 0


func begin(test_name: String) -> void:
	_current = test_name
	_failed_at_test_start = failed
	print("TEST %s" % test_name)


func check(condition: bool, message: String) -> bool:
	if condition:
		passed += 1
		return true
	failed += 1
	var line: String = "%s → %s" % [_current, message]
	failures.append(line)
	return false


func check_eq(actual: Variant, expected: Variant, message: String) -> bool:
	return check(actual == expected,
		"%s（期望 %s，实际 %s）" % [message, str(expected), str(actual)])


func check_approx(actual: float, expected: float, tolerance: float, message: String) -> bool:
	return check(absf(actual - expected) <= tolerance,
		"%s（期望 %.6f±%.6f，实际 %.6f）" % [message, expected, tolerance, actual])


func check_in_range(value: float, low: float, high: float, message: String) -> bool:
	return check(value >= low and value <= high,
		"%s（应在 [%.4f, %.4f]，实际 %.6f）" % [message, low, high, value])


func check_finite(value: float, message: String) -> bool:
	return check(is_finite(value), "%s（实际 %s）" % [message, str(value)])


## 单条测试的收尾：打印一行可读结论。
func finish(summary: String) -> void:
	var status: String = "PASS" if failed == _failed_at_test_start else "FAIL"
	print("  [%s] %s" % [status, summary])


## 全部测试的收尾：打印失败明细与汇总。返回退出码。
func report() -> int:
	print("")
	print("========================================")
	if failed == 0:
		print("A 范围测试全部通过：%d 条断言" % passed)
		print("========================================")
		return 0
	print("A 范围测试失败：%d 条断言通过，%d 条失败" % [passed, failed])
	for line in failures:
		print("  FAIL %s" % line)
	print("========================================")
	return 1
