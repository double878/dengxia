extends RefCounted
class_name CTestScenery
## 布景数据的行为测试：把「景物只能左右平移」「接地线对齐影人」两条用户定案
## 钉成自动断言，防止以后改数据时悄悄破约。
##
## 运行入口：res://tests/c/run_scenery_tests.gd（--headless --script，退出码 0 = 全过）。
##
## 断言依据（用户 2026-10-08 逐条定案）：
##   ① 第一关布景只有柳树 + 拱桥（无花草、无边界线）
##   ② 柳树树干 x = 0.08；拱桥起点 x = 0.72
##   ③ 接地线对齐：anchor_y ∈ [0.47, 0.53]（人影脚在 y=0.5，浮动 ≤0.03）
##   ④ 景物只能左右平移：位置相关字段**只有** anchor_x / anchor_y / pan_x，
##      不得出现 y 位移、缩放、旋转（数据结构层面就没有）
##   ⑤ 小青位置**不在**本文件管辖内（那是 A 侧 stage_def 的事；本测试不碰 A 数据）

const ATestBaseScript := preload("res://tests/a/a_test_base.gd")
const DefScript := preload("res://scripts/c/c_scenery_def.gd")


func run_all() -> Dictionary:
	var t = ATestBaseScript.new()

	_level1_shape(t)
	_ground_line_alignment(t)
	_pan_only_constraint(t)
	_empty_stage_fallback(t)
	_constants_consistency(t)

	t.finish("布景数据契约（第一关 + 通用约束）")
	return {"passed": t.passed, "failed": t.failed, "exit_code": t.report()}


## 第一关的布景内容与定位
func _level1_shape(t: RefCounted) -> void:
	t.begin("第一关布景内容")
	var def: CSceneryDef = DefScript.make_level1()

	t.check(def.items.size() >= 2, "第一关至少有柳树与拱桥两个元素（实际 %d）" % def.items.size())

	var ids: Array[String] = []
	for item in def.items:
		ids.append(str(item.get("id", "")))
	t.check(ids.size() == _unique_count(ids), "元素 id 不得重复（实际 %s）" % [str(ids)])

	var kinds: Array[String] = []
	for item in def.items:
		kinds.append(str(item.get("kind", "")))
	t.check(kinds.has(DefScript.KIND_WILLOW), "有柳树（kind=%s）" % DefScript.KIND_WILLOW)
	t.check(kinds.has(DefScript.KIND_ARCH_BRIDGE), "有拱桥（kind=%s）" % DefScript.KIND_ARCH_BRIDGE)
	t.check(not kinds.has("flora"), "第一关不画花草（用户 2026-10-08：暂时不画）")

	var willow: Dictionary = _find(def, "willow_left")
	var bridge: Dictionary = _find(def, "bridge_right")
	t.check(not willow.is_empty(), "柳树元素存在（id=willow_left）")
	t.check(not bridge.is_empty(), "拱桥元素存在（id=bridge_right）")

	# 定位：柳树 0.08 / 桥起 0.72（用户 2026-10-08 定案；先 0.85 后修正）
	if not willow.is_empty():
		t.check_approx(float(willow.get("anchor_x", -1.0)), DefScript.LEVEL1_WILLOW_X, 1e-6,
			"柳树 anchor_x = LEVEL1_WILLOW_X")
	if not bridge.is_empty():
		t.check_approx(float(bridge.get("anchor_x", -1.0)), DefScript.LEVEL1_BRIDGE_START_X, 1e-6,
			"拱桥 anchor_x = LEVEL1_BRIDGE_START_X")

	# 锚点一律在舞台内
	for item in def.items:
		t.check_in_range(float(item.get("anchor_x", -1.0)), 0.0, 1.0,
			"%s 的 anchor_x ∈ [0,1]" % str(item.get("id", "")))


## 接地线对齐（用户 2026-10-08：「纵轴线要跟人物水平对齐，上下浮动不能超过 0.03」）
func _ground_line_alignment(t: RefCounted) -> void:
	t.begin("接地线对齐")
	var def: CSceneryDef = DefScript.make_level1()
	for item in def.items:
		t.check_in_range(float(item.get("anchor_y", -1.0)), DefScript.Y_MIN, DefScript.Y_MAX,
			"%s 的 anchor_y ∈ [%.2f, %.2f]（影人脚在 %.2f）"
			% [str(item.get("id", "")), DefScript.Y_MIN, DefScript.Y_MAX, DefScript.ANCHOR_Y])
	# 容差本身自洽：Y_MIN/Y_MAX 必须对称落在 ANCHOR_Y ± Y_TOLERANCE
	t.check_approx(DefScript.Y_MIN, DefScript.ANCHOR_Y - DefScript.Y_TOLERANCE, 1e-9,
		"Y_MIN = ANCHOR_Y - Y_TOLERANCE")
	t.check_approx(DefScript.Y_MAX, DefScript.ANCHOR_Y + DefScript.Y_TOLERANCE, 1e-9,
		"Y_MAX = ANCHOR_Y + Y_TOLERANCE")
	# 影人接地点口径：A 侧第一关 initial 三具全部 y=0.5。这里只核对常量本身，
	# 不 preload A 的 stage_def（C 不引用 A 的关卡数据做判定，避免双向依赖）。
	t.check_approx(DefScript.ANCHOR_Y, 0.5, 1e-9, "ANCHOR_Y 与影人接地点 0.5 同一条线")


## 「景物只能左右平移」：位置相关字段白名单之外不得出现任何位移/形变字段
func _pan_only_constraint(t: RefCounted) -> void:
	t.begin("只能左右平移")
	var def: CSceneryDef = DefScript.make_level1()
	# 顶层字段白名单：除 params 外，只允许 id/kind + POSITION_KEYS 三个位置字段
	var allowed := {"id": true, "kind": true}
	for key in DefScript.POSITION_KEYS:
		allowed[key] = true
	for item in def.items:
		for key in item.keys():
			if key == "params":
				continue
			t.check(allowed.has(str(key)),
				"%s 的字段 %s 在白名单内（禁止 y 位移/缩放/旋转）" % [str(item.get("id", "")), str(key)])
		# params 是形状参数（树冠半径、拱高等），不是位姿字段——但里面也不许出现
		# 位移/缩放/旋转语义的键，防止有人把「可以动」从后门塞回来。
		var params: Dictionary = item.get("params", {})
		for key in params.keys():
			var k := str(key)
			var banned := k.contains("scale") or k.contains("rotate") or k.contains("rotation") \
				or k.contains("pos_y") or k.contains("y_offset") or k == "y"
			t.check(not banned, "%s.params.%s 不是位移/缩放/旋转字段" % [str(item.get("id", "")), k])
		# pan_x 初始必须为 0（第 1 关布景静止；pan 能力是留给以后演出调度的）
		t.check_approx(float(item.get("pan_x", -1.0)), 0.0, 1e-9,
			"%s 的 pan_x 初始为 0" % str(item.get("id", "")))


## 未知关卡返回空布景，而不是静默顶替成第一关的
func _empty_stage_fallback(t: RefCounted) -> void:
	t.begin("未知关卡返回空布景")
	var empty: CSceneryDef = DefScript.make_stage(2)
	t.check(empty.items.is_empty(), "第 2 关布景为空（未实现就是未实现，不拿第一关顶替）")
	t.check_eq(empty.stage_id, 2, "空布景仍携带 stage_id 供显示端报错用")
	t.check(DefScript.make_stage(1).items.size() > 0, "第 1 关布景非空")


## 常量与数据同源：改常量忘改数据（或反过来）必须被测试抓住
func _constants_consistency(t: RefCounted) -> void:
	t.begin("常量与数据同源")
	var def: CSceneryDef = DefScript.make_level1()
	var willow: Dictionary = _find(def, "willow_left")
	var bridge: Dictionary = _find(def, "bridge_right")
	t.check_approx(float(willow.get("anchor_x", 0.0)), 0.08, 1e-6,
		"LEVEL1_WILLOW_X 常量值 = 0.08（用户定案）")
	t.check_approx(float(bridge.get("anchor_x", 0.0)), 0.72, 1e-6,
		"LEVEL1_BRIDGE_START_X 常量值 = 0.72（用户定案）")
	# 接地线（用户二次定案：0.50 → 0.53）
	t.check_approx(DefScript.LEVEL1_GROUND_Y, 0.53, 1e-6,
		"LEVEL1_GROUND_Y = 0.53（用户定案「再往下移动 0.03」）")
	t.check_approx(float(willow.get("anchor_y", 0.0)), DefScript.LEVEL1_GROUND_Y, 1e-6,
		"柳树 anchor_y = LEVEL1_GROUND_Y")
	t.check_approx(float(bridge.get("anchor_y", 0.0)), DefScript.LEVEL1_GROUND_Y, 1e-6,
		"拱桥 anchor_y = LEVEL1_GROUND_Y")
	# 形状参数（用户二次定案）
	t.check_approx(float(willow.get("params", {}).get("trunk_height", 0.0)), 0.25, 1e-6,
		"树干高 0.25（用户定案「更高 0.05」）")
	t.check_approx(float(bridge.get("params", {}).get("deck_thickness", 0.0)), 0.048, 1e-6,
		"桥身厚 0.048（用户定案「厚度增加 0.03」）")


func _find(def: CSceneryDef, id: String) -> Dictionary:
	for item in def.items:
		if str(item.get("id", "")) == id:
			return item
	return {}


func _unique_count(arr: Array[String]) -> int:
	var seen := {}
	for v in arr:
		seen[v] = true
	return seen.size()
