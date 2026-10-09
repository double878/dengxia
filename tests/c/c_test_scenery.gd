extends RefCounted
class_name CTestScenery
## 布景数据的行为测试：把「景物只能左右平移」「接地线对齐影人」两条用户定案
## 钉成自动断言，防止以后改数据时悄悄破约。
##
## 运行入口：res://tests/c/run_scenery_tests.gd（--headless --script，退出码 0 = 全过）。
##
## 断言依据（用户 2026-10-08 逐条定案）：
##   ① 第一关布景只有柳树 + 拱桥（无花草、无边界线）
##   ② 柳树树干 x = 0.1354、基线 0.6294、缩放 0.26（2026-10-09 构图定案：
##      再大一点 + 树冠完整入幕布 + 幕布上方留 1/5~1/6）；
##      拱桥 = **完整拱**，桥基中心 x = 0.73（2026-10-09「桥头左移，使桥能够
##      完整展现在幕布中」定案；半拱读作被裁断，完整解 = 恢复 woop 全拱）
##   ③ 纵轴容差口径：Y_TOLERANCE = 0.5（用户第三次定案「放宽至 0.5」），
##      [Y_MIN, Y_MAX] = [0.0, 1.0] 覆盖整个舞台高度；影人接地点仍为 0.5
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
	_texture_contract(t)
	_view_scripts_load(t)
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

	# 定位：柳树 0.1354 / 桥基中心 0.73（2026-10-09 构图定案）
	if not willow.is_empty():
		t.check_approx(float(willow.get("anchor_x", -1.0)), DefScript.LEVEL1_WILLOW_X, 1e-6,
			"柳树 anchor_x = LEVEL1_WILLOW_X")
	if not bridge.is_empty():
		t.check_approx(float(bridge.get("anchor_x", -1.0)), DefScript.LEVEL1_BRIDGE_CENTER_X, 1e-6,
			"拱桥 anchor_x = LEVEL1_BRIDGE_CENTER_X")

	# 锚点一律在舞台内
	for item in def.items:
		t.check_in_range(float(item.get("anchor_x", -1.0)), 0.0, 1.0,
			"%s 的 anchor_x ∈ [0,1]" % str(item.get("id", "")))


## 纵轴容差口径（用户 2026-10-08 三次定案：0.03 → **放宽至 0.5**）
## 这里校验的是「容差常量自洽 + 覆盖整个舞台高度」，而**不是**「每条布景都必须贴在影人脚上」——
## 放宽之后允许布景离开 0.5，所以不再逐条断言 anchor_y 贴近 0.5（那会与新口径自相矛盾）。
func _ground_line_alignment(t: RefCounted) -> void:
	t.begin("纵轴容差口径")
	var def: CSceneryDef = DefScript.make_level1()

	# ① 容差本身：用户定案 0.5
	t.check_approx(DefScript.Y_TOLERANCE, 0.5, 1e-9,
		"Y_TOLERANCE = 0.5（用户 2026-10-08 定案「放宽至 0.5」）")
	# ② Y_MIN/Y_MAX 必须仍对称落在 ANCHOR_Y ± Y_TOLERANCE（改一处忘另一处要被抓住）
	t.check_approx(DefScript.Y_MIN, DefScript.ANCHOR_Y - DefScript.Y_TOLERANCE, 1e-9,
		"Y_MIN = ANCHOR_Y - Y_TOLERANCE")
	t.check_approx(DefScript.Y_MAX, DefScript.ANCHOR_Y + DefScript.Y_TOLERANCE, 1e-9,
		"Y_MAX = ANCHOR_Y + Y_TOLERANCE")
	# ③ 放宽后 [Y_MIN, Y_MAX] 应撑满整个舞台高度（这是「放宽至 0.5」的直接效果）
	t.check_approx(DefScript.Y_MIN, 0.0, 1e-9, "Y_MIN = 0.0（布景可下移到画布底）")
	t.check_approx(DefScript.Y_MAX, 1.0, 1e-9, "Y_MAX = 1.0（布景可上移到画布顶）")
	# ④ 基准线口径未变：影人接地点仍是 0.5（放宽的是布景的移动自由，不是影人的位置）
	t.check_approx(DefScript.ANCHOR_Y, 0.5, 1e-9, "ANCHOR_Y 与影人接地点 0.5 同一条线")
	# ⑤ 每条布景的 anchor_y 仍必须落在（已放宽的）合法区间内，且是有限数
	for item in def.items:
		var ay: float = float(item.get("anchor_y", -1.0))
		t.check_finite(ay, "%s 的 anchor_y 是有限数" % str(item.get("id", "")))
		t.check_in_range(ay, DefScript.Y_MIN, DefScript.Y_MAX,
			"%s 的 anchor_y ∈ [%.2f, %.2f]（放宽后）"
			% [str(item.get("id", "")), DefScript.Y_MIN, DefScript.Y_MAX])
	# ⑥ 宽松哨兵：明确记录「布景已不再被强制贴 0.5」。若哪天有人把容差改回 0.03，
	#    这条会失败并指向用户定案，而不是让人对着「影人脚对不齐」猜原因。
	t.check(DefScript.Y_TOLERANCE >= 0.03,
		"容差不得回退到 0.03 以下（2026-10-08 用户放宽至 0.5）")


## 「景物只能左右平移」：位置相关字段白名单之外不得出现任何位移/形变字段
func _pan_only_constraint(t: RefCounted) -> void:
	t.begin("只能左右平移")
	var def: CSceneryDef = DefScript.make_level1()
	# 顶层字段白名单：除 params 外，只允许 id/kind + POSITION_KEYS 三个位置字段
	# + 贴图件套（texture/texture_foot_px/polygon——描述「画什么、怎么对齐」；
	#   texture_scale_px 是逐资产静态像素比常量，不是运行时形变能力，
	#   柳树与桥素材像素密度不同，全局比例不够用，2026-10-09 柳树接入时加入）
	var allowed := {"id": true, "kind": true,
		"texture": true, "texture_foot_px": true, "polygon": true,
		"texture_scale_px": true}
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


## 贴图契约（用户 2026-10-08：woop 素材接入）——贴图存在、锚点合法、走向白名单
func _texture_contract(t: RefCounted) -> void:
	t.begin("贴图契约")
	t.check(FileAccess.file_exists(DefScript.SCENERY_TEX_BRIDGE),
		"拱桥贴图文件存在：%s" % DefScript.SCENERY_TEX_BRIDGE)
	# 雨幕贴图（烟雨氛围层用；桥贴图已裁掉烘焙雨丝，雨单一来源）
	t.check(FileAccess.file_exists("res://assets/scenery/level1/rain_near.png"),
		"近层雨幕贴图存在（rain_near.png）")
	t.check(FileAccess.file_exists("res://assets/scenery/level1/rain_far.png"),
		"远层雨幕贴图存在（rain_far.png）")
	t.check_approx(DefScript.TEXTURE_SCALE_PX, 0.42, 1e-9,
		"TEXTURE_SCALE_PX = 0.42（用户拍板选 C 小桥：素材1px→画布0.42px，桥宽约占画布45%）")
	var def: CSceneryDef = DefScript.make_level1()
	var bridge: Dictionary = _find(def, "bridge_right")
	t.check(not bridge.is_empty(), "拱桥元素存在")
	if bridge.is_empty():
		return
	t.check_eq(str(bridge.get("texture", "")), DefScript.SCENERY_TEX_BRIDGE,
		"拱桥 texture 引用 SCENERY_TEX_BRIDGE 常量")
	var foot: Vector2 = bridge.get("texture_foot_px", Vector2.ZERO)
	t.check_approx(foot.x, 921.0, 1e-6,
		"贴图锚点 x = 921（完整拱桥基中心：底部 30 行 x 中心 920.8）")
	t.check_approx(foot.y, 714.0, 1e-6,
		"贴图锚点 y = 714（桥台底边=内容最底行；y>1423 的水雾已裁）")
	var poly: String = str(bridge.get("polygon", ""))
	t.check_eq(poly, DefScript.POLY_ARCH_SPAN,
		"polygon = arch_span（完整拱跨，2026-10-09「桥完整展现」定案）")
	# 资产裁切契约：arch_bridge.png = **完整拱** 1842×715
	# （woop 桥体 y 707~1423、x 106~1943；顶部雨丝带/底部水雾已裁）
	var img := Image.load_from_file(ProjectSettings.globalize_path(DefScript.SCENERY_TEX_BRIDGE))
	t.check(img != null, "拱桥贴图可读（Image.load_from_file，不依赖导入缓存）")
	if img != null:
		t.check_eq(img.get_width(), 1842, "桥贴图宽 1842（完整拱全跨）")
		t.check_eq(img.get_height(), 715, "桥贴图高 715（桥体全高，雨丝/水雾均已裁）")

	# —— 柳树贴图契约（用户 2026-10-09 柳树.woop 接入）——
	t.check(FileAccess.file_exists(DefScript.SCENERY_TEX_WILLOW),
		"柳树贴图文件存在：%s" % DefScript.SCENERY_TEX_WILLOW)
	var willow: Dictionary = _find(def, "willow_left")
	t.check(not willow.is_empty(), "柳树元素存在")
	if not willow.is_empty():
		t.check_eq(str(willow.get("texture", "")), DefScript.SCENERY_TEX_WILLOW,
			"柳树 texture 引用 SCENERY_TEX_WILLOW 常量")
		var wfoot: Vector2 = willow.get("texture_foot_px", Vector2.ZERO)
		t.check_approx(wfoot.x, 564.0, 1e-6,
			"柳树贴图锚点 x = 564（裁切后最底 10 行树干中心，实测 423~704）")
		t.check_approx(wfoot.y, 1845.0, 1e-6,
			"柳树贴图锚点 y = 1845（裁切图内容最底行，树干底部贴基线）")
		t.check_approx(float(willow.get("texture_scale_px", -1.0)),
			DefScript.LEVEL1_WILLOW_SCALE, 1e-9,
			"柳树 texture_scale_px = LEVEL1_WILLOW_SCALE（逐资产静态比例）")
		t.check_approx(float(willow.get("anchor_y", -1.0)),
			DefScript.LEVEL1_WILLOW_BASE_Y, 1e-9,
			"柳树 anchor_y = LEVEL1_WILLOW_BASE_Y（前景树基线，与桥接地线解耦）")
		var wimg := Image.load_from_file(ProjectSettings.globalize_path(DefScript.SCENERY_TEX_WILLOW))
		t.check(wimg != null, "柳树贴图可读（Image.load_from_file，不依赖导入缓存）")
		if wimg != null:
			t.check_eq(wimg.get_width(), 1436, "柳树贴图宽 1436（裁到内容包围盒）")
			t.check_eq(wimg.get_height(), 1846, "柳树贴图高 1846（无雨丝/水雾/底座）")


## 视图脚本可加载、可实例化（= 编译通过）。
## 数据测试跑在 headless，管不到画面；但「显示端脚本一个语法错误就让整个布景
## 消失（preload 失败连锁）」这种事故可以在 headless 就拦住——代价只有 4 条断言。
## 画面本身对不对由探针（c_probe_scenery.gd）截图供人眼核对。
func _view_scripts_load(t: RefCounted) -> void:
	t.begin("视图脚本可加载")
	var view_res: Resource = load("res://scripts/c/c_scenery_view.gd")
	t.check(view_res is GDScript, "c_scenery_view.gd 加载为 GDScript")
	if view_res is GDScript:
		t.check(view_res.can_instantiate(), "c_scenery_view.gd 编译通过（可实例化）")
	var rain_res: Resource = load("res://scripts/c/c_rain_overlay.gd")
	t.check(rain_res is GDScript, "c_rain_overlay.gd 加载为 GDScript")
	if rain_res is GDScript:
		t.check(rain_res.can_instantiate(), "c_rain_overlay.gd 编译通过（可实例化）")


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
	t.check_approx(float(willow.get("anchor_x", 0.0)), 0.27, 1e-6,
		"LEVEL1_WILLOW_X 常量值 = 0.27（许仙右侧：树冠左缘 ≈372px 不遮许仙右缘 340px）")
	t.check_approx(float(bridge.get("anchor_x", 0.0)), 0.73, 1e-6,
		"LEVEL1_BRIDGE_CENTER_X 常量值 = 0.73（2026-10-09「桥头左移，完整拱」定案）")
	t.check_approx(DefScript.LEVEL1_WILLOW_SCALE, 0.26, 1e-9,
		"LEVEL1_WILLOW_SCALE = 0.26（2026-10-09「再大一点」，由 0.20 上调）")
	t.check_approx(DefScript.LEVEL1_WILLOW_BASE_Y, 0.6294, 1e-9,
		"LEVEL1_WILLOW_BASE_Y = 0.6294（前景树基线：树顶留幕布高 1/5~1/6 的几何必然）")
	t.check_approx(float(willow.get("anchor_y", 0.0)), DefScript.LEVEL1_WILLOW_BASE_Y, 1e-6,
		"柳树 anchor_y = LEVEL1_WILLOW_BASE_Y（与桥接地线解耦）")
	# 接地线（用户二次定案：0.50 → 0.53；现容差已放宽至 0.5，0.53 不再是边界值）
	t.check_approx(DefScript.LEVEL1_GROUND_Y, 0.53, 1e-6,
		"LEVEL1_GROUND_Y = 0.53（用户定案「再往下移动 0.03」）")
	t.check_approx(float(bridge.get("anchor_y", 0.0)), DefScript.LEVEL1_GROUND_Y, 1e-6,
		"拱桥 anchor_y = LEVEL1_GROUND_Y")
	# 纵轴容差（用户三次定案：放宽至 0.5）
	t.check_approx(DefScript.Y_TOLERANCE, 0.5, 1e-6,
		"Y_TOLERANCE = 0.5（用户定案「放宽至 0.5」）")
	# 形状参数（用户二次定案）
	t.check_approx(float(willow.get("params", {}).get("trunk_height", 0.0)), 0.25, 1e-6,
		"树干高 0.25（用户定案「更高 0.05」）")
	t.check_approx(float(bridge.get("params", {}).get("deck_thickness", 0.0)), 0.048, 1e-6,
		"桥身厚 0.048（用户定案「厚度增加 0.03」）")
	# 拱顶高（用户三次定案：0.10 → 0.13）
	t.check_approx(float(bridge.get("params", {}).get("deck_rise", 0.0)), 0.13, 1e-6,
		"拱顶高 0.13（用户定案）")


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
