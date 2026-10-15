extends RefCounted
class_name CTestScenery
## 布景数据的行为测试：把「景物只能左右平移」「接地线对齐影人」两条用户定案
## 钉成自动断言，防止以后改数据时悄悄破约。
##
## 运行入口：res://tests/c/run_scenery_tests.gd（--headless --script，退出码 0 = 全过）。
##
## 断言依据（用户 2026-10-08 逐条定案）：
##   ① 第一关布景只有柳树 + 拱桥（无花草、无边界线）
##   ② 柳树树干 anchor_x ≈ 0.12485374、anchor_y ≈ 0.61346776、缩放 0.25482124
##      —— 三个都是**派生式**，只依赖「树高 470.4px = 0.8 × 幕布高」这一个定案数；
##      2026-10-15 用户「下移 95」后又「上移 5」→ 净下移 90px，底缘 572.8 → 662.8px；
##      同日再定「树高 0.8 × 幕布高」⇒ 树高 416 → 441 → **470.4px**（底缘不动、左缘不动，
##      树顶由 246.8 升到 192.4px、右缘由 419.2 长到 461.92px）；
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
	_pan_only_all_stages(t)
	_texture_contract(t)
	_view_scripts_load(t)
	_empty_stage_fallback(t)
	_level2_geometry(t)
	_level2_two_acts_separate(t)
	_level2_act2_geometry(t)
	_level3_geometry(t)
	_geometry_on_canvas(t)
	_constants_consistency(t)

	t.finish("布景数据契约（三关 + 第二关两幕 + 通用约束）")
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
		t.check_approx(
			float(willow.get("anchor_x", -1.0)),
			DefScript.LEVEL1_WILLOW_X,
			1e-6,
			"柳树 anchor_x = LEVEL1_WILLOW_X"
		)
	if not bridge.is_empty():
		t.check_approx(
			float(bridge.get("anchor_x", -1.0)),
			DefScript.LEVEL1_BRIDGE_CENTER_X,
			1e-6,
			"拱桥 anchor_x = LEVEL1_BRIDGE_CENTER_X"
		)

	# 锚点一律在舞台内
	for item in def.items:
		t.check_in_range(
			float(item.get("anchor_x", -1.0)),
			0.0,
			1.0,
			"%s 的 anchor_x ∈ [0,1]" % str(item.get("id", ""))
		)


## 纵轴容差口径（用户 2026-10-08 三次定案：0.03 → **放宽至 0.5**）
## 这里校验的是「容差常量自洽 + 覆盖整个舞台高度」，而**不是**「每条布景都必须贴在影人脚上」——
## 放宽之后允许布景离开 0.5，所以不再逐条断言 anchor_y 贴近 0.5（那会与新口径自相矛盾）。
func _ground_line_alignment(t: RefCounted) -> void:
	t.begin("纵轴容差口径")
	var def: CSceneryDef = DefScript.make_level1()

	# ① 容差本身：用户定案 0.5
	t.check_approx(DefScript.Y_TOLERANCE, 0.5, 1e-9, "Y_TOLERANCE = 0.5（用户 2026-10-08 定案「放宽至 0.5」）")
	# ② Y_MIN/Y_MAX 必须仍对称落在 ANCHOR_Y ± Y_TOLERANCE（改一处忘另一处要被抓住）
	t.check_approx(
		DefScript.Y_MIN,
		DefScript.ANCHOR_Y - DefScript.Y_TOLERANCE,
		1e-9,
		"Y_MIN = ANCHOR_Y - Y_TOLERANCE"
	)
	t.check_approx(
		DefScript.Y_MAX,
		DefScript.ANCHOR_Y + DefScript.Y_TOLERANCE,
		1e-9,
		"Y_MAX = ANCHOR_Y + Y_TOLERANCE"
	)
	# ③ 放宽后 [Y_MIN, Y_MAX] 应撑满整个舞台高度（这是「放宽至 0.5」的直接效果）
	t.check_approx(DefScript.Y_MIN, 0.0, 1e-9, "Y_MIN = 0.0（布景可下移到画布底）")
	t.check_approx(DefScript.Y_MAX, 1.0, 1e-9, "Y_MAX = 1.0（布景可上移到画布顶）")
	# ④ 基准线口径未变：影人接地点仍是 0.5（放宽的是布景的移动自由，不是影人的位置）
	t.check_approx(DefScript.ANCHOR_Y, 0.5, 1e-9, "ANCHOR_Y 与影人接地点 0.5 同一条线")
	# ⑤ 每条布景的 anchor_y 仍必须落在（已放宽的）合法区间内，且是有限数
	for item in def.items:
		var ay: float = float(item.get("anchor_y", -1.0))
		t.check_finite(ay, "%s 的 anchor_y 是有限数" % str(item.get("id", "")))
		t.check_in_range(
			ay,
			DefScript.Y_MIN,
			DefScript.Y_MAX,
			(
				"%s 的 anchor_y ∈ [%.2f, %.2f]（放宽后）"
				% [str(item.get("id", "")), DefScript.Y_MIN, DefScript.Y_MAX]
			)
		)
	# ⑥ 宽松哨兵：明确记录「布景已不再被强制贴 0.5」。若哪天有人把容差改回 0.03，
	#    这条会失败并指向用户定案，而不是让人对着「影人脚对不齐」猜原因。
	t.check(DefScript.Y_TOLERANCE >= 0.03, "容差不得回退到 0.03 以下（2026-10-08 用户放宽至 0.5）")


## 「景物只能左右平移」：位置相关字段白名单之外不得出现任何位移/形变字段
func _pan_only_constraint(t: RefCounted) -> void:
	t.begin("只能左右平移")
	var def: CSceneryDef = DefScript.make_level1()
	# 顶层字段白名单：除 params 外，只允许 id/kind + POSITION_KEYS 三个位置字段
	# + 贴图件套（texture/texture_foot_px/polygon——描述「画什么、怎么对齐」；
	#   texture_scale_px 是逐资产静态像素比常量，不是运行时形变能力，
	#   柳树与桥素材像素密度不同，全局比例不够用，2026-10-09 柳树接入时加入）
	var allowed := {
		"id": true,
		"kind": true,
		"texture": true,
		"texture_foot_px": true,
		"polygon": true,
		"texture_scale_px": true
	}
	for key in DefScript.POSITION_KEYS:
		allowed[key] = true
	for item in def.items:
		for key in item.keys():
			if key == "params":
				continue
			t.check(
				allowed.has(str(key)),
				"%s 的字段 %s 在白名单内（禁止 y 位移/缩放/旋转）" % [str(item.get("id", "")), str(key)]
			)
		# params 是形状参数（树冠半径、拱高等），不是位姿字段——但里面也不许出现
		# 位移/缩放/旋转语义的键，防止有人把「可以动」从后门塞回来。
		var params: Dictionary = item.get("params", {})
		for key in params.keys():
			var k := str(key)
			var banned := (
				k.contains("scale")
				or k.contains("rotate")
				or k.contains("rotation")
				or k.contains("pos_y")
				or k.contains("y_offset")
				or k == "y"
			)
			t.check(not banned, "%s.params.%s 不是位移/缩放/旋转字段" % [str(item.get("id", "")), k])
		# pan_x 初始必须为 0（第 1 关布景静止；pan 能力是留给以后演出调度的）
		t.check_approx(
			float(item.get("pan_x", -1.0)), 0.0, 1e-9, "%s 的 pan_x 初始为 0" % str(item.get("id", ""))
		)


## 「景物只能左右平移」是**全关卡**的硬约束，不是第一关专属。
## `_pan_only_constraint` 只查第一关（历史原因），这里对**所有已实现关卡**再查一遍
## 字段白名单——第二关两幕与第三关是后加的，最容易从后门塞进 y 位移 / 缩放 / 旋转。
func _pan_only_all_stages(t: RefCounted) -> void:
	t.begin("只能左右平移（全关卡）")
	var allowed := {
		"id": true,
		"kind": true,
		"texture": true,
		"texture_foot_px": true,
		"polygon": true,
		"texture_scale_px": true
	}
	for key in DefScript.POSITION_KEYS:
		allowed[key] = true
	for sid in [1, 2, DefScript.LEVEL2_ACT2_STAGE_ID, 3]:
		var def: CSceneryDef = DefScript.make_stage(sid)
		for item in def.items:
			var label := "%d/%s" % [sid, str(item.get("id", ""))]
			for key in item.keys():
				if str(key) == "params":
					continue
				t.check(allowed.has(str(key)), "%s 的字段 %s 在白名单内（禁止 y 位移/缩放/旋转）" % [label, str(key)])
			var params: Dictionary = item.get("params", {})
			for key in params.keys():
				var k := str(key)
				var banned := (
					k.contains("scale")
					or k.contains("rotate")
					or k.contains("rotation")
					or k.contains("pos_y")
					or k.contains("y_offset")
					or k == "y"
				)
				t.check(not banned, "%s.params.%s 不是位移/缩放/旋转字段" % [label, k])
			t.check_approx(float(item.get("pan_x", -1.0)), 0.0, 1e-9, "%s 的 pan_x 初始为 0" % label)
			var ay: float = float(item.get("anchor_y", -1.0))
			t.check_finite(ay, "%s 的 anchor_y 是有限数" % label)
			t.check_in_range(ay, DefScript.Y_MIN, DefScript.Y_MAX, "%s 的 anchor_y ∈ [%.2f, %.2f]" % [label, DefScript.Y_MIN, DefScript.Y_MAX])


## 贴图契约（用户 2026-10-08：woop 素材接入）——贴图存在、锚点合法、走向白名单
func _texture_contract(t: RefCounted) -> void:
	t.begin("贴图契约")
	t.check(
		FileAccess.file_exists(DefScript.SCENERY_TEX_BRIDGE),
		"拱桥贴图文件存在：%s" % DefScript.SCENERY_TEX_BRIDGE
	)
	# 雨幕贴图（烟雨氛围层用；桥贴图已裁掉烘焙雨丝，雨单一来源）
	t.check(
		FileAccess.file_exists("res://assets/scenery/level1/rain_near.png"),
		"近层雨幕贴图存在（rain_near.png）"
	)
	t.check(
		FileAccess.file_exists("res://assets/scenery/level1/rain_far.png"), "远层雨幕贴图存在（rain_far.png）"
	)
	t.check_approx(
		DefScript.TEXTURE_SCALE_PX,
		0.42,
		1e-9,
		"TEXTURE_SCALE_PX = 0.42（用户拍板选 C 小桥：素材1px→画布0.42px，桥宽约占画布45%）"
	)
	var def: CSceneryDef = DefScript.make_level1()
	var bridge: Dictionary = _find(def, "bridge_right")
	t.check(not bridge.is_empty(), "拱桥元素存在")
	if bridge.is_empty():
		return
	t.check_eq(
		str(bridge.get("texture", "")),
		DefScript.SCENERY_TEX_BRIDGE,
		"拱桥 texture 引用 SCENERY_TEX_BRIDGE 常量"
	)
	var foot: Vector2 = bridge.get("texture_foot_px", Vector2.ZERO)
	t.check_approx(foot.x, 921.0, 1e-6, "贴图锚点 x = 921（完整拱桥基中心：底部 30 行 x 中心 920.8）")
	t.check_approx(foot.y, 714.0, 1e-6, "贴图锚点 y = 714（桥台底边=内容最底行；y>1423 的水雾已裁）")
	var poly: String = str(bridge.get("polygon", ""))
	t.check_eq(poly, DefScript.POLY_ARCH_SPAN, "polygon = arch_span（完整拱跨，2026-10-09「桥完整展现」定案）")
	# 资产裁切契约：arch_bridge.png = **完整拱** 1842×715
	# （woop 桥体 y 707~1423、x 106~1943；顶部雨丝带/底部水雾已裁）
	var img := Image.load_from_file(ProjectSettings.globalize_path(DefScript.SCENERY_TEX_BRIDGE))
	t.check(img != null, "拱桥贴图可读（Image.load_from_file，不依赖导入缓存）")
	if img != null:
		t.check_eq(img.get_width(), 1842, "桥贴图宽 1842（完整拱全跨）")
		t.check_eq(img.get_height(), 715, "桥贴图高 715（桥体全高，雨丝/水雾均已裁）")

	# —— 柳树贴图契约（用户 2026-10-09 柳树.woop 接入）——
	t.check(
		FileAccess.file_exists(DefScript.SCENERY_TEX_WILLOW),
		"柳树贴图文件存在：%s" % DefScript.SCENERY_TEX_WILLOW
	)
	var willow: Dictionary = _find(def, "willow_left")
	t.check(not willow.is_empty(), "柳树元素存在")
	if not willow.is_empty():
		t.check_eq(
			str(willow.get("texture", "")),
			DefScript.SCENERY_TEX_WILLOW,
			"柳树 texture 引用 SCENERY_TEX_WILLOW 常量"
		)
		var wfoot: Vector2 = willow.get("texture_foot_px", Vector2.ZERO)
		t.check_approx(wfoot.x, 564.0, 1e-6, "柳树贴图锚点 x = 564（裁切后最底 10 行树干中心，实测 423~704）")
		t.check_approx(wfoot.y, 1845.0, 1e-6, "柳树贴图锚点 y = 1845（裁切图内容最底行，树干底部贴基线）")
		t.check_approx(
			float(willow.get("texture_scale_px", -1.0)),
			DefScript.LEVEL1_WILLOW_SCALE,
			1e-9,
			"柳树 texture_scale_px = LEVEL1_WILLOW_SCALE（逐资产静态比例）"
		)
		t.check_approx(
			float(willow.get("anchor_y", -1.0)),
			DefScript.LEVEL1_WILLOW_BASE_Y,
			1e-9,
			"柳树 anchor_y = LEVEL1_WILLOW_BASE_Y（前景树基线，与桥接地线解耦）"
		)
		var wimg := Image.load_from_file(
			ProjectSettings.globalize_path(DefScript.SCENERY_TEX_WILLOW)
		)
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


## 贴图在画布上的**实际绘制矩形**（用户 2026-10-09 四条构图要求的可回归断言）。
##
## 为什么必须单独测：前面的断言只检查「数据填得对不对」，检查不了
## 「贴图有没有被幕布裁掉半边」这类**画面级**问题——而用户恰恰是看画面提的需求
## （「桥必须完整显示整张，不能只渲染左半边或右半边」）。
## 断言直接复用 CSceneryView 的摆放公式（target − foot×scale → 整张 size），
## 不做二次实现（复制粘贴公式 = 两处漂移的种子）；公式若改动，这里会同步失效提醒。
##
## 幕布矩形取 `level1_a_scene.gd` 同源版面：Rect2(66, 92, 1788, 588)。
func _geometry_on_canvas(t: RefCounted) -> void:
	t.begin("贴图绘制矩形（完整入幕布 / 底对齐 / 左边距）")
	var cloth := Rect2(66.0, 92.0, 1788.0, 588.0)
	var def: CSceneryDef = DefScript.make_level1()
	var rects: Dictionary = {}
	for item in def.items:
		var img := Image.load_from_file(
			ProjectSettings.globalize_path(str(item.get("texture", "")))
		)
		if img == null:
			t.check(false, "%s 贴图可读（几何断言前置）" % item.get("id", "?"))
			continue
		var scale: float = DefScript.TEXTURE_SCALE_PX
		if item.has("texture_scale_px"):
			scale = float(item["texture_scale_px"])
		var foot: Vector2 = item.get("texture_foot_px", Vector2.ZERO)
		var target := Vector2(
			float(item.get("anchor_x", 0.0)) * 1920.0, float(item.get("anchor_y", 0.0)) * 1080.0
		)
		# 与 CSceneryView._draw_texture_item 同式：左上角 = target − foot×scale
		var r := Rect2(
			target - foot * scale, Vector2(float(img.get_width()), float(img.get_height())) * scale
		)
		rects[str(item.get("id", ""))] = r
		# ① 完整显示：四边都不得越出幕布（越界 = 被 clip_children 裁掉 = 只剩半边）
		var over_l: float = maxf(cloth.position.x - r.position.x, 0.0)
		var over_r: float = maxf(r.end.x - cloth.end.x, 0.0)
		var over_t: float = maxf(cloth.position.y - r.position.y, 0.0)
		var over_b: float = maxf(r.end.y - cloth.end.y, 0.0)
		t.check(
			over_l + over_r + over_t + over_b <= 0.5,
			(
				"%s 贴图完整入幕布（左%.0f 右%.0f 上%.0f 下%.0f 越界，应全为 0）"
				% [item.get("id", "?"), over_l, over_r, over_t, over_b]
			)
		)

	var willow_rect: Rect2 = rects.get("willow_left", Rect2())
	var bridge_rect: Rect2 = rects.get("bridge_right", Rect2())
	if willow_rect.size == Vector2.ZERO or bridge_rect.size == Vector2.ZERO:
		return
	# ② 树底与桥底同一条水平线（用户「树的纵向底部水平线与桥的纵向水平线对齐」）
	t.check_approx(
		willow_rect.end.y,
		bridge_rect.end.y,
		1.0,
		"树底与桥底同线（树%.1f / 桥%.1f，容差 1px）" % [willow_rect.end.y, bridge_rect.end.y]
	)
	# ③ 树左缘贴画布左侧，留「适当内边距」（20~60px，不贴死也不留大片空白）
	var pad: float = willow_rect.position.x - cloth.position.x
	t.check(pad >= 20.0 and pad <= 60.0, "树左缘内边距 = %.0f px（要求 20~60，避免贴死或左侧空白过多）" % pad)
	# ④ 树高（2026-10-15 用户定案：**0.8 × 幕布高 = 470.4px**，由 416 → 441px 两轮上调）与随之的树顶留白。
	#    幕布顶 92 → 景物接地线 662.8 的可用高是 570.8px，减去树高 470.4 ⇒ 留白 100.4px。
	#    树高单独钉一条：只判留白的话，「树高变大 + 接地线下移」这类同向抵消会蒙混过关。
	t.check_approx(
		willow_rect.size.y,
		0.8 * cloth.size.y,
		2.0,
		(
			"树高 = %.1f px ≈ 0.8 × 幕布高（%.1f），占幕布高 %.1f%%"
			% [willow_rect.size.y, 0.8 * cloth.size.y, 100.0 * willow_rect.size.y / cloth.size.y]
		)
	)
	var top_gap: float = willow_rect.position.y - cloth.position.y
	t.check_approx(
		top_gap,
		570.8 - 0.8 * cloth.size.y,
		2.0,
		(
			"树顶留白 = %.1f px ≈ 可用高 570.8 − 树高（%.1f）；树顶边 %.1fpx"
			% [top_gap, 0.8 * cloth.size.y, willow_rect.position.y]
		)
	)
	# ⑤ 树冠/树干比例协调：干基段（素材里树干露出部分）不得被放大到喧宾夺主。
	# 素材实测：干右紧邻枝条最低点 y=1249，素材内容底 y=1843 → 干基段占全高 32.3%。
	# 屏上对应高度应仍在树高的 25%~40% 区间（树下有支撑感、树冠仍是主体）。
	var wimg2 := Image.load_from_file(ProjectSettings.globalize_path(DefScript.SCENERY_TEX_WILLOW))
	if wimg2 != null:
		var trunk_ratio: float = (1843.0 - 1249.0) / 1843.0  # ≈ 0.3225
		var trunk_px: float = trunk_ratio * willow_rect.size.y
		t.check(
			trunk_px >= willow_rect.size.y * 0.25 and trunk_px <= willow_rect.size.y * 0.40,
			"树干露出段 %.0f px = 树高的 %.1f%%（要求 25%%~40%%，树冠仍为主体）" % [trunk_px, 100.0 * trunk_ratio]
		)
	# ⑥ 整关净下移 90px 后的底边落点（用户 2026-10-15 定案）：572.8 + 90 = 662.8px。
	#    ① 只判「越界总量为 0」，这里把具体落点钉住，避免「整体悄悄漂走但仍在幕布内」漏检。
	t.check_approx(
		willow_rect.end.y, 662.8, 1.0, "树底缘 = %.1f ≈ 662.8（原 572.8 + 整关净下移 90）" % willow_rect.end.y
	)
	t.check_approx(
		bridge_rect.end.y, 662.8, 1.0, "桥底缘 = %.1f ≈ 662.8（原 572.8 + 整关净下移 90）" % bridge_rect.end.y
	)


## 未知关卡返回空布景，而不是静默顶替成第一关的
func _empty_stage_fallback(t: RefCounted) -> void:
	t.begin("未知关卡返回空布景")
	# ⚠️ 第 3 关自 2026-10-12 起**已实现**（一座顶天立地的山），
	#    故「未实现」哨兵改用**第 4 关**——「未实现就是未实现」这条口径不变，
	#    只是换了尚未实现的那个编号（换编号而不是删断言，是为了留住这条守护）。
	var empty: CSceneryDef = DefScript.make_stage(4)
	t.check(empty.items.is_empty(), "第 4 关布景为空（未实现就是未实现，不拿别关顶替）")
	t.check_eq(empty.stage_id, 4, "空布景仍携带 stage_id 供显示端报错用")
	t.check(DefScript.make_stage(1).items.size() > 0, "第 1 关布景非空")
	# 第 2 关自 2026-10-11 起有自己的布景（**第一幕**：门楼 + 菊石 + 垂柳树）
	t.check_eq(DefScript.make_stage(2).items.size(), 3, "第 2 关有自己的布景（3 件：门楼 / 菊花石 / 树）")
	# 第 3 关自 2026-10-12 起有自己的布景（一座山）
	t.check_eq(DefScript.make_stage(3).items.size(), 1, "第 3 关有自己的布景（1 件：山）")


## 第二关两幕**必须各占一个编号、互不覆盖**。
## 这是本文件最重要的一条守护：两幕布景完全不同（门外 vs 厅堂），
## 而第二幕一度被写进 `make_level2()` 里——那会**直接顶掉第一幕的门楼**，
## 且 `act2_opening.gd` 还在用编号 2 取第一幕数据。此处把它钉成断言。
func _level2_two_acts_separate(t: RefCounted) -> void:
	t.begin("第二关两幕各占一个编号")
	var act1: CSceneryDef = DefScript.make_stage(2)
	var act2: CSceneryDef = DefScript.make_stage(DefScript.LEVEL2_ACT2_STAGE_ID)
	t.check_eq(DefScript.LEVEL2_ACT2_STAGE_ID, 22, "第二幕编号常量 = 22（第一幕是 2，不得共用）")
	t.check_eq(act1.stage_id, 2, "编号 2 = 第一幕（门楼）")
	t.check_eq(act2.stage_id, 22, "编号 22 = 第二幕（厅堂）")
	t.check(act1.items.size() > 0 and act2.items.size() > 0, "两幕都有布景（各非空）")
	# 两幕的 id 集合必须**不相交**：出现交集就说明有人把一套写进了另一套
	var ids1: Array[String] = []
	for item in act1.items:
		ids1.append(str(item.get("id", "")))
	var overlap: Array[String] = []
	for item in act2.items:
		var id2 := str(item.get("id", ""))
		if ids1.has(id2):
			overlap.append(id2)
	t.check(overlap.is_empty(), "两幕布景 id 不重叠（实际重叠 %s）" % [str(overlap)])
	# 第一幕三件与第二幕十三件都要在（数量漂移立刻可见）
	t.check_eq(act1.items.size(), 3, "第一幕仍是 3 件（门楼 / 菊石 / 树）")
	t.check_eq(act2.items.size(), 13, "第二幕 13 件（柱×2 / 梁×4 / 花盆 / 桌 / 凳×2 / 壶 / 杯×2）")


## 第二关**第二幕**「室内厅堂」布景的几何契约（用户 2026-10-12 定稿，第四轮）。
## 与前两关不同，本幕**六种锚点高度并存**，故逐件按各自的口径断言：
##   桌 / 两凳 653.4（地平线）/ 花盆 **658.8（0.61，比地平线更低）** / 桌上酒具 **432（0.4）**
##   / 立柱 680（贴幕布下沿）/ 横梁 **梁顶 129.6（0.12）、梁底 204.3（= 梁顶 + 梁高）**。
func _level2_act2_geometry(t: RefCounted) -> void:
	t.begin("第二关第二幕厅堂几何（柱 / 梁 / 花盆 / 桌 / 凳 / 酒具）")
	var cloth := Rect2(66.0, 92.0, 1788.0, 588.0)
	var def: CSceneryDef = DefScript.make_stage(DefScript.LEVEL2_ACT2_STAGE_ID)
	t.check_eq(def.stage_id, 22, "第二幕 stage_id = 22")
	t.check_eq(def.items.size(), 13, "共 13 件（柱×2 + 梁×4 + 花盆 + 桌 + 凳×2 + 酒壶 + 酒杯×2）")

	var rects: Dictionary = {}
	for item in def.items:
		var img := Image.load_from_file(
			ProjectSettings.globalize_path(str(item.get("texture", "")))
		)
		if img == null:
			t.check(false, "%s 贴图可读（第二幕几何断言前置）" % item.get("id", "?"))
			continue
		var scale: float = float(item.get("texture_scale_px", DefScript.TEXTURE_SCALE_PX))
		var foot: Vector2 = item.get("texture_foot_px", Vector2.ZERO)
		var target := Vector2(
			float(item.get("anchor_x", 0.0)) * 1920.0, float(item.get("anchor_y", 0.0)) * 1080.0
		)
		var r := Rect2(
			target - foot * scale, Vector2(float(img.get_width()), float(img.get_height())) * scale
		)
		rects[str(item.get("id", ""))] = r
		# ① 每件都必须完整落在幕布里（越界会被渲染器裁掉 = 只剩半边）
		t.check(
			(
				r.position.x >= cloth.position.x - 0.5
				and r.end.x <= cloth.end.x + 0.5
				and r.position.y >= cloth.position.y - 0.5
				and r.end.y <= cloth.end.y + 0.5
			),
			(
				"%s 完整入幕布（x %.0f~%.0f  y %.0f~%.0f）"
				% [item.get("id", "?"), r.position.x, r.end.x, r.position.y, r.end.y]
			)
		)
		# ② 只允许水平平移（第二幕同样受这条硬约束）
		t.check(item.has("pan_x"), "%s 有 pan_x 字段（水平平移口）" % item.get("id", "?"))
		t.check_approx(float(item.get("pan_x", -1.0)), 0.0, 1e-9, "%s 的 pan_x 初始为 0" % item.get("id", "?"))

	var col_l: Rect2 = rects.get("column_left", Rect2())
	var col_r: Rect2 = rects.get("column_right", Rect2())
	var table: Rect2 = rects.get("table", Rect2())
	var stool_l: Rect2 = rects.get("stool_left", Rect2())
	var stool_r: Rect2 = rects.get("stool_right", Rect2())
	var pot: Rect2 = rects.get("flowerpot", Rect2())
	var wine_pot: Rect2 = rects.get("wine_pot", Rect2())
	var cup_g: Rect2 = rects.get("wine_cup_green", Rect2())
	var cup_r: Rect2 = rects.get("wine_cup_red", Rect2())

	# ③ 两柱**以幕布中心为轴对称**——按「中心之和 = 2×幕布中心」写，
	#    改幕布尺寸时自动成立，而不是各写死一个数。
	var cloth_center: float = cloth.position.x + cloth.size.x * 0.5
	t.check_approx(
		col_l.get_center().x + col_r.get_center().x,
		cloth_center * 2.0,
		1.0,
		"左右柱关于幕布中心对称（中心 %.1f + %.1f = %.1f，应为 %.1f）"
		% [col_l.get_center().x, col_r.get_center().x, col_l.get_center().x + col_r.get_center().x, cloth_center * 2.0]
	)
	# ④ 右柱是**镜像贴图**：镜像只翻内容、不改几何 → 左右柱同宽同高
	t.check_approx(col_l.size.x, col_r.size.x, 0.5, "左右柱同宽（%.1f / %.1f，镜像不改几何）" % [col_l.size.x, col_r.size.x])
	t.check_approx(col_l.size.y, col_r.size.y, 0.5, "左右柱同高（%.1f / %.1f）" % [col_l.size.y, col_r.size.y])
	# ⑤ 立柱「顶天立地」：**底贴幕布下沿 680**（唯一不随地平线的贴地件），高 = 幕布高 − 21.6
	t.check_approx(col_l.end.y, cloth.end.y, 1.0, "左柱底缘 y=%.1f 贴幕布下沿 %.1f" % [col_l.end.y, cloth.end.y])
	t.check_approx(col_r.end.y, cloth.end.y, 1.0, "右柱底缘 y=%.1f 贴幕布下沿 %.1f" % [col_r.end.y, cloth.end.y])
	t.check_approx(col_l.size.y, 566.4, 1.0, "柱高 566.4px（占幕布高 %.1f%%）" % [100.0 * col_l.size.y / cloth.size.y])
	t.check(col_l.position.y > cloth.position.y, "柱顶 y=%.1f 未越幕布上缘 %.1f" % [col_l.position.y, cloth.position.y])

	# ⑥ 圆桌居中（同时是两凳的对称轴）
	t.check_approx(table.get_center().x, cloth_center, 1.0, "圆桌中心 %.1f = 幕布中心 %.1f（居中）" % [table.get_center().x, cloth_center])
	t.check_approx(table.end.y, 653.4, 1.5, "圆桌落地 y=%.1f（地平线 653.4）" % table.end.y)
	# ⑦ 两凳：**第四轮起各钉在用户给的 0.4 / 0.6 上**，且仍关于桌中心对称。
	t.check_approx(
		stool_l.get_center().x,
		DefScript.LEVEL2_ACT2_STOOL_LEFT_X * 1920.0,
		0.5,
		"左凳心 x=%.1f = LEVEL2_ACT2_STOOL_LEFT_X×1920（%.2f，用户第四轮定案 0.4）"
		% [stool_l.get_center().x, DefScript.LEVEL2_ACT2_STOOL_LEFT_X]
	)
	t.check_approx(
		stool_r.get_center().x,
		DefScript.LEVEL2_ACT2_STOOL_RIGHT_X * 1920.0,
		0.5,
		"右凳心 x=%.1f = LEVEL2_ACT2_STOOL_RIGHT_X×1920（%.2f，对称 0.6）"
		% [stool_r.get_center().x, DefScript.LEVEL2_ACT2_STOOL_RIGHT_X]
	)
	t.check_approx(
		stool_l.get_center().x + stool_r.get_center().x,
		table.get_center().x * 2.0,
		1.0,
		"两凳关于桌中心对称（%.1f + %.1f = %.1f）"
		% [stool_l.get_center().x, stool_r.get_center().x, stool_l.get_center().x + stool_r.get_center().x]
	)
	# ⑦b 凳**压不到桌**——但这条**不能用包围盒判**：
	#     桌贴图 1895×1937 近似正方、四周是背景留白，**包围盒**宽 253px（833.5~1086.5）；
	#     而凳顶（525.4px）以下的桌只剩中柱与腿基——实测该竖直带内桌宽只有 24~116px。
	#     凳心挪到 0.4 / 0.6 后，凳矩形（698~838 / 1082~1222）与桌**包围盒**各相吻 4.5px，
	#     用包围盒判会**误报**「凳压在桌上」（第三轮那两条 `stool.end.x < table.position.x`
	#     就是这么写的，本轮凳一挪就假报）。
	#     故改为：取桌**在凳所在竖直带内的实际不透明像素**横向跨度，再判两者不相交——
	#     这才是画面上真会重叠的部分。
	var t_img := Image.load_from_file(ProjectSettings.globalize_path(DefScript.SCENERY_TEX_TABLE))
	t.check(t_img != null, "桌贴图可读（⑦b 判「凳不压桌」的前置）")
	if t_img != null:
		t_img.convert(Image.FORMAT_RGBA8)
		var t_scale: float = DefScript.LEVEL2_ACT2_TABLE_SCALE
		var t_anch: Vector2 = Vector2(
			DefScript.LEVEL2_ACT2_TABLE_X * 1920.0, DefScript.LEVEL2_ACT2_TABLE_TOP_Y * 1080.0
		)
		var t_foot: Vector2 = _find(def, "table").get("texture_foot_px", Vector2.ZERO)
		var band_y0: float = minf(stool_l.position.y, stool_r.position.y)
		var band_y1: float = maxf(stool_l.end.y, stool_r.end.y)
		var row_a: int = maxi(0, int((band_y0 - t_anch.y) / t_scale))
		var row_b: int = mini(t_img.get_height() - 1, int((band_y1 - t_anch.y) / t_scale))
		var span_l: float = INF
		var span_r: float = -INF
		for ry in range(row_a, row_b + 1, 6):
			for rx in range(0, t_img.get_width(), 4):
				if t_img.get_pixel(rx, ry).a > 0.15:
					var cx: float = t_anch.x + (float(rx) - t_foot.x) * t_scale
					span_l = minf(span_l, cx)
					span_r = maxf(span_r, cx)
		t.check(
			span_r > span_l,
			"桌在凳高度带（%.1f~%.1f）内有实像素（x %.1f~%.1f）" % [band_y0, band_y1, span_l, span_r]
		)
		t.check(
			stool_l.end.x <= span_l + 0.5,
			"左凳右缘 %.1f ≤ 桌在该带内的**实际**左缘 %.1f（不压桌；桌包围盒 %.1f 不算数）"
			% [stool_l.end.x, span_l, table.position.x]
		)
		t.check(
			stool_r.position.x >= span_r - 0.5,
			"右凳左缘 %.1f ≥ 桌在该带内的**实际**右缘 %.1f（不压桌）" % [stool_r.position.x, span_r]
		)
	t.check_approx(stool_l.end.y, 653.4, 1.5, "左凳落地 y=%.1f" % stool_l.end.y)
	t.check_approx(stool_r.end.y, 653.4, 1.5, "右凳落地 y=%.1f" % stool_r.end.y)

	# ⑧ 花盆：**最下水平线 0.61（658.8px，比地平线更低）+ 放大 5%**，最左缘仍 0.15（第四轮）。
	t.check_approx(
		pot.end.y,
		DefScript.LEVEL2_ACT2_FLOWERPOT_BASE_Y * 1080.0,
		0.5,
		"花盆最下水平线 y=%.1f = LEVEL2_ACT2_FLOWERPOT_BASE_Y×1080（%.2f，用户第四轮定案）"
		% [pot.end.y, DefScript.LEVEL2_ACT2_FLOWERPOT_BASE_Y]
	)
	#    🔴 反向断言：花盆从第四轮起**不再走地平线**（它是唯一「更靠前」的贴地件）——
	#    防有人照旧口径把它改回 653.4。
	t.check(
		pot.end.y > DefScript.LEVEL2_ACT2_GROUND_Y * 1080.0 + 0.5,
		(
			"花盆落线 %.1f 在地平线 %.1f **之下**（第四轮起花盆不走地平线，别再改回）"
			% [pot.end.y, DefScript.LEVEL2_ACT2_GROUND_Y * 1080.0]
		)
	)
	t.check_approx(
		pot.size.y,
		1848.0 * DefScript.LEVEL2_ACT2_FLOWERPOT_SCALE,
		0.5,
		(
			"花盆高 %.1f = 贴图高 × SCALE（= 基础比例 %.5f × ZOOM %.2f）"
			% [
				pot.size.y,
				DefScript.LEVEL2_ACT2_FLOWERPOT_SCALE_BASE,
				DefScript.LEVEL2_ACT2_FLOWERPOT_ZOOM
			]
		)
	)
	t.check_approx(
		pot.size.y,
		354.4,
		1.0,
		"花盆高 354.4px（原 337.5px，第四轮「稍微放大一点点」= ZOOM 1.05）"
	)
	#    🔴 用户 2026-10-12 第三轮：「花盆**最左侧**移动到 0.15」→ 288px。
	#    「最左侧」= 贴图内容左缘 = 绘制矩形左缘（贴图已裁到内容框，内容自贴图 x=0 起）。
	#    锚点写成了「左缘 + foot x × scale」的表达式，这条断言同时守住常量与几何；
	#    第四轮放大时**只向右长**、左缘仍钉在这里。
	t.check_approx(
		pot.position.x,
		DefScript.LEVEL2_ACT2_FLOWERPOT_LEFT_X * 1920.0,
		0.5,
		"花盆最左缘 x=%.1f = LEVEL2_ACT2_FLOWERPOT_LEFT_X×1920（%.2f）" % [pot.position.x, DefScript.LEVEL2_ACT2_FLOWERPOT_LEFT_X]
	)
	t.check(pot.position.x > col_l.end.x, "花盆左缘 %.1f > 左柱右缘 %.1f（不压柱）" % [pot.position.x, col_l.end.x])
	t.check(pot.end.x < table.position.x, "花盆右缘 %.1f < 桌左缘 %.1f（不碰桌）" % [pot.end.x, table.position.x])
	t.check(pot.end.y > table.end.y - table.size.y, "花盆高 %.0f 高于桌（%.0f）——用户定案「花盆比桌子高一点」" % [pot.size.y, table.size.y])

	# ⑨ 酒具三件的**最低水平面 = 0.4（432px）**（用户 2026-10-12 第三轮：「酒具对齐 0.4」）。
	#    桌面可见面 = 后沿 394.7（= LEVEL2_ACT2_TABLE_TOP_Y）~ 前沿 ≈446.2（椭圆近边），
	#    432 落在**中前部** → 「站在桌面上」；而上一版引用的 394.7 是后沿（悬在桌缘上）。
	#    ⚠️ 底边（432）落在**桌子绘制矩形之内**，所以「图层在上」不是可选项（见 ⑨b）。
	var wine_line: float = DefScript.LEVEL2_ACT2_WINE_BASE_Y * 1080.0
	t.check_approx(
		wine_line,
		432.0,
		0.5,
		"酒具落线 = %.1fpx（LEVEL2_ACT2_WINE_BASE_Y = %.2f）" % [wine_line, DefScript.LEVEL2_ACT2_WINE_BASE_Y]
	)
	for pair in [["酒壶", wine_pot], ["绿釉杯", cup_g], ["朱红杯", cup_r]]:
		var label: String = str(pair[0])
		var rect: Rect2 = pair[1]
		t.check_approx(
			rect.end.y,
			wine_line,
			0.5,
			(
				"%s 的最低水平面 y=%.1f 对齐酒具落线 %.1f"
				% [label, rect.end.y, wine_line]
			)
		)
		t.check(
			rect.position.x >= table.position.x - 0.5 and rect.end.x <= table.end.x + 0.5,
			"%s 横向落在桌面内（%.1f~%.1f ⊂ %.1f~%.1f）" % [label, rect.position.x, rect.end.x, table.position.x, table.end.x]
		)
		t.check(
			rect.end.y > table.position.y + 0.5,
			"%s 底边 %.1f 低于桌面最高面 %.1f（落在桌面之内 → 必须压在桌子之上）" % [label, rect.end.y, table.position.y]
		)
	# 壶在左、两杯在右（用户手绘图的排序）
	t.check(wine_pot.end.x <= cup_g.position.x + 0.5, "酒壶在绿釉杯左侧（壶右缘 %.1f ≤ 杯左缘 %.1f）" % [wine_pot.end.x, cup_g.position.x])
	t.check(cup_g.end.x <= cup_r.position.x + 0.5, "绿釉杯在朱红杯左侧（%.1f ≤ %.1f）" % [cup_g.end.x, cup_r.position.x])

	# ⑨b **图层在上**：绘制顺序 = `items` 数组顺序（`CSceneryView._draw_items` 逐件直绘，
	#     没有逐件 z_index），后画者在上。酒具底边落在桌子矩形之内，若排在桌子之前就会被
	#     桌面盖住——用户原话「且图层在上，不要被桌子遮住」。这条断言钉住顺序，防随手调序。
	var draw_index: Dictionary = {}
	for i in def.items.size():
		draw_index[str(def.items[i].get("id", ""))] = i
	for wid in ["wine_pot", "wine_cup_green", "wine_cup_red"]:
		t.check(
			int(draw_index.get("table", -1)) < int(draw_index.get(wid, -1)),
			(
				"%s 排在 table 之后（索引 %d > %d）→ 绘制时压在桌子之上，不被遮住"
				% [wid, int(draw_index.get(wid, -1)), int(draw_index.get("table", -1))]
			)
		)

	# ⑩ 立柱改用**剪掉内侧**的贴图（用户 2026-10-12 第二轮：「把立柱靠内侧的那一边部分剪掉」）。
	#    贴图契约：604×1893（原 984×1893，内侧雀替臂整条剪掉）。
	for pair in [
		["左", DefScript.SCENERY_TEX_COLUMN_CUT], ["右", DefScript.SCENERY_TEX_COLUMN_MIRROR_CUT]
	]:
		var cimg := Image.load_from_file(ProjectSettings.globalize_path(str(pair[1])))
		t.check(cimg != null, "%s柱贴图可读：%s" % [str(pair[0]), str(pair[1])])
		if cimg != null:
			t.check_eq(cimg.get_width(), 604, "%s柱贴图宽 604（剪掉内侧臂后的宽度）" % str(pair[0]))
			t.check_eq(cimg.get_height(), 1893, "%s柱贴图高 1893（与素材同高）" % str(pair[0]))
	t.check_eq(
		str(_find(def, "column_left").get("texture", "")),
		DefScript.SCENERY_TEX_COLUMN_CUT,
		"左柱引用 SCENERY_TEX_COLUMN_CUT（不是未剪的 column.png）"
	)
	t.check_eq(
		str(_find(def, "column_right").get("texture", "")),
		DefScript.SCENERY_TEX_COLUMN_MIRROR_CUT,
		"右柱引用 SCENERY_TEX_COLUMN_MIRROR_CUT（镜像 + 剪内侧）"
	)

	# ⑪ 横梁四根**在位**且**正好铺满柱间净宽**（用户 2026-10-12 第二轮：「四个横梁保留」）。
	#    上一版误把参考图上「剪柱内侧」的批注读成「删横梁」，整套删掉了 9 件版；
	#    这里钉住「四根 / 等宽 / 首尾相接 / 两端正好接柱内侧缘」，以后改柱宽忘改梁宽立刻报错。
	var beam_ids: Array[String] = []
	for item in def.items:
		if str(item.get("id", "")).begins_with("beam"):
			beam_ids.append(str(item.get("id", "")))
	t.check_eq(beam_ids.size(), 4, "横梁四根在位（实际 %s）" % [str(beam_ids)])
	if beam_ids.size() == 4:
		var beam_rects: Array[Rect2] = []
		for bid in ["beam_0", "beam_1", "beam_2", "beam_3"]:
			beam_rects.append(rects.get(bid, Rect2()))
		for i in range(1, 4):
			t.check_approx(
				beam_rects[i].size.x,
				beam_rects[0].size.x,
				0.5,
				"beam_%d 与 beam_0 等宽（%.1f / %.1f）" % [i, beam_rects[i].size.x, beam_rects[0].size.x]
			)
		for i in range(3):
			t.check_approx(
				beam_rects[i].end.x,
				beam_rects[i + 1].position.x,
				0.5,
				"beam_%d 右缘 %.1f 与 beam_%d 左缘 %.1f 相接（四根连成一条楣子）"
				% [i, beam_rects[i].end.x, i + 1, beam_rects[i + 1].position.x]
			)
		t.check_approx(
			beam_rects[0].position.x,
			col_l.end.x,
			0.5,
			"横梁左端 %.1f 接左柱内侧缘 %.1f（柱剪内侧后梁正好铺满柱间净宽）" % [beam_rects[0].position.x, col_l.end.x]
		)
		t.check_approx(
			beam_rects[3].end.x,
			col_r.position.x,
			0.5,
			"横梁右端 %.1f 接右柱内侧缘 %.1f" % [beam_rects[3].end.x, col_r.position.x]
		)
		# 🔴 第三轮起以**梁顶**定高、梁底由梁高推出；第四轮把梁顶由 0.15 上抬到 **0.12**。
		#    写成常量表达式 → 换贴图/改梁宽时底边自动跟随，这里同时守顶与底两端。
		var beam_top: float = DefScript.LEVEL2_BEAM_TOP_Y * 1080.0
		var beam_bottom: float = DefScript.LEVEL2_BEAM_Y * 1080.0
		t.check_approx(
			beam_top,
			129.6,
			0.5,
			"梁顶常量 = %.1fpx（LEVEL2_BEAM_TOP_Y = %.2f，用户第四轮定案 0.12）"
			% [beam_top, DefScript.LEVEL2_BEAM_TOP_Y]
		)
		t.check_approx(
			beam_bottom,
			204.3,
			0.5,
			"梁底常量 = 梁顶 + 梁高 = %.1fpx（梁高 = 369×0.202406 = 74.7px）" % beam_bottom
		)
		# 反向约束：梁既不能越出幕布上缘，也要**整段落在立柱的竖向范围之内**——
		# 横向正好卡在两柱之间（两端接柱内侧缘，见上），纵向贴着柱身上部，
		# 看着才像「梁架在柱头上」。
		# ⚠️ 别写成「梁底要在柱顶之上」：y 越大越靠下，梁底 204.3 本就在柱顶 113.6 **之下**，
		#    那正是要的效果（梁顶 129.6 距柱顶仅 16px，与参考图的挂落位置一致）。
		t.check(beam_top >= cloth.position.y, "梁顶 %.1f 未越幕布上缘 %.1f" % [beam_top, cloth.position.y])
		t.check(
			beam_top > col_l.position.y and beam_bottom < col_l.end.y,
			"横梁竖向 %.1f~%.1f 落在立柱竖向范围（柱顶 %.1f ~ 柱底 %.1f）之内"
			% [beam_top, beam_bottom, col_l.position.y, col_l.end.y]
		)
		for i in 4:
			t.check_approx(
				beam_rects[i].position.y,
				beam_top,
				1.0,
				"beam_%d 梁顶 y=%.1f（= 用户第四轮给的 0.12 那条线）" % [i, beam_rects[i].position.y]
			)
			t.check_approx(
				beam_rects[i].end.y,
				beam_bottom,
				1.0,
				"beam_%d 梁底 y=%.1f（= 梁顶 + 梁高）" % [i, beam_rects[i].end.y]
			)


## 第三关《盗仙草》布景几何：**一座山，顶天立地、紧靠最右侧**（用户 2026-10-12 定案）。
func _level3_geometry(t: RefCounted) -> void:
	t.begin("第三关布景几何（一座山）")
	var cloth := Rect2(66.0, 92.0, 1788.0, 588.0)
	var def: CSceneryDef = DefScript.make_stage(3)
	t.check_eq(def.stage_id, 3, "第 3 关 stage_id = 3")
	t.check_eq(def.items.size(), 1, "只有 1 件布景（贴图内已含云 / 松 / 峰顶殿宇，一件顶三件）")
	var item: Dictionary = def.items[0]
	t.check_eq(str(item.get("id", "")), "mountain", "元素 id = mountain")

	var img := Image.load_from_file(
		ProjectSettings.globalize_path(str(item.get("texture", "")))
	)
	t.check(img != null, "山贴图可读（不依赖导入缓存）")
	if img == null:
		return
	t.check_eq(img.get_width(), 1494, "山贴图宽 1494")
	t.check_eq(img.get_height(), 1754, "山贴图高 1754")
	var scale: float = float(item.get("texture_scale_px", DefScript.TEXTURE_SCALE_PX))
	var foot: Vector2 = item.get("texture_foot_px", Vector2.ZERO)
	var target := Vector2(
		float(item.get("anchor_x", 0.0)) * 1920.0, float(item.get("anchor_y", 0.0)) * 1080.0
	)
	var r := Rect2(target - foot * scale, Vector2(float(img.get_width()), float(img.get_height())) * scale)

	# ① 完整入幕布
	t.check(
		(
			r.position.x >= cloth.position.x - 0.5
			and r.end.x <= cloth.end.x + 0.5
			and r.position.y >= cloth.position.y - 0.5
			and r.end.y <= cloth.end.y + 0.5
		),
		"山完整入幕布（x %.0f~%.0f  y %.0f~%.0f）" % [r.position.x, r.end.x, r.position.y, r.end.y]
	)
	# ② 顶天立地：山高 = 幕布高，山顶贴幕布顶、山脚贴幕布底
	t.check_approx(r.size.y, cloth.size.y, 1.0, "山高 %.1f = 幕布高 %.1f（顶天立地）" % [r.size.y, cloth.size.y])
	t.check_approx(r.position.y, cloth.position.y, 1.0, "山顶 y=%.1f 贴幕布顶 %.1f" % [r.position.y, cloth.position.y])
	t.check_approx(r.end.y, cloth.end.y, 1.0, "山脚 y=%.1f 贴幕布底 %.1f" % [r.end.y, cloth.end.y])
	# ③ 紧靠最右侧（右缘内留 20px）
	t.check_approx(cloth.end.x - r.end.x, 20.0, 2.0, "山右缘距幕布右 %.1f（内留 20px）" % (cloth.end.x - r.end.x))
	# ④ 左侧大片留空给影人（用户定案：左侧约 72% 留空）
	var free_ratio: float = (r.position.x - cloth.position.x) / cloth.size.x
	t.check(free_ratio >= 0.65, "山左侧留空 %.0f%%（用户定案约 72%%，给影人活动区）" % (100.0 * free_ratio))
	# ⑤ 只允许水平平移
	t.check(item.has("pan_x"), "山有 pan_x 字段（水平平移口）")


## 第二关布景的几何契约（2026-10-11 用户定案）。
## 三件布景的位置来自用户参考图目测，全部钉成断言防漂移。
func _level2_geometry(t: RefCounted) -> void:
	t.begin("第二关布景几何（门楼 / 菊石 / 垂柳）")
	var cloth := Rect2(66.0, 92.0, 1788.0, 588.0)
	var def: CSceneryDef = DefScript.make_stage(2)
	t.check_eq(def.stage_id, 2, "第 2 关 stage_id = 2")
	t.check_eq(def.items.size(), 3, "共 3 件布景（门楼 / 菊石 / 树；花篮已撤下）")

	# 逐件量出贴图绘制矩形（公式与 CSceneryView._draw_texture_item 一致）
	for item in def.items:
		var img := Image.load_from_file(
			ProjectSettings.globalize_path(str(item.get("texture", "")))
		)
		if img == null:
			t.check(false, "%s 贴图可读（第二关几何断言前置）" % item.get("id", "?"))
			continue
		var scale: float = DefScript.TEXTURE_SCALE_PX
		if item.has("texture_scale_px"):
			scale = float(item["texture_scale_px"])
		var foot: Vector2 = item.get("texture_foot_px", Vector2.ZERO)
		var target := Vector2(
			float(item.get("anchor_x", 0.0)) * 1920.0, float(item.get("anchor_y", 0.0)) * 1080.0
		)
		var r := Rect2(
			target - foot * scale, Vector2(float(img.get_width()), float(img.get_height())) * scale
		)
		# ① 三件都必须完整落在幕布里
		t.check(
			(
				r.position.x >= cloth.position.x - 0.5
				and r.end.x <= cloth.end.x + 0.5
				and r.position.y >= cloth.position.y - 0.5
				and r.end.y <= cloth.end.y + 0.5
			),
			(
				"%s 完整入幕布（x %.0f~%.0f  y %.0f~%.0f）"
				% [item.get("id", "?"), r.position.x, r.end.x, r.position.y, r.end.y]
			)
		)
		# ② 只允许水平平移（第二关同样受这条约束）
		t.check(item.has("pan_x"), "%s 有 pan_x 字段（水平平移口）" % item.get("id", "?"))
	#③ 门楼与菊石「贴地」：底缘应贴近幕布底缘（参考图里它们站在地上）
	var gate_rect: Rect2 = Rect2()
	var chrs_rect: Rect2 = Rect2()
	var basket_rect: Rect2 = Rect2()
	var tree_rect: Rect2 = Rect2()
	for item in def.items:
		var img2 := Image.load_from_file(
			ProjectSettings.globalize_path(str(item.get("texture", "")))
		)
		if img2 == null:
			continue
		var sc: float = float(item.get("texture_scale_px", DefScript.TEXTURE_SCALE_PX))
		var ft: Vector2 = item.get("texture_foot_px", Vector2.ZERO)
		var tg := Vector2(
			float(item.get("anchor_x", 0.0)) * 1920.0, float(item.get("anchor_y", 0.0)) * 1080.0
		)
		var rr := Rect2(
			tg - ft * sc, Vector2(float(img2.get_width()), float(img2.get_height())) * sc
		)
		match str(item.get("id", "")):
			"gate":
				gate_rect = rr
			"chrysanthemum":
				chrs_rect = rr
			"flower_basket":
				basket_rect = rr
			"willow_branch":
				tree_rect = rr
	t.check_approx(gate_rect.end.y, 661.0, 3.0, "门楼底缘 y=661px（贴地，参考图里门楼站在地上）")
	# 门楼：549 → ×2/3=366 → **×1.25=458px**（用户 2026-10-11 三次调整）
	t.check_approx(gate_rect.size.y, 458.0, 3.0, "门楼高 458px（549 经 2/3 再 ×1.25）")
	# 菊石与门楼**同一地平线**（用户 2026-10-11 定案；第一版 635 与门楼 661差 26px，已修）
	t.check_approx(chrs_rect.end.y, 661.0, 3.0, "菊石底缘 y=661px（与门楼同地平线）")
	# 菊花：368 → 0.36=132 → **×1.25=165px**
	t.check_approx(chrs_rect.size.y, 165.0, 3.0, "菊花高 165px（132 再 ×1.25）")
	# ④ 树是**右侧贴地的整株**（用户 2026-10-11 从「悬垂柳枝」改为整株，贴地不悬空）
	t.check_approx(tree_rect.end.y, 661.0, 3.0, "树底缘 y=661px（与门楼/菊石同一地平线，贴地）")
	t.check(
		tree_rect.position.x > gate_rect.end.x,
		"树左缘 %.0f > 门楼右缘 %.0f（树在门楼右侧）" % [tree_rect.position.x, gate_rect.end.x]
	)
	# 树靠幕布右边界：右缘距幕布右 30px 左右
	t.check(
		1788.0 + 66.0 - tree_rect.end.x <= 40.0 and 1788.0 + 66.0 - tree_rect.end.x >= 10.0,
		"树右缘 %.0f 距幕布右 %.0f（内边距10~40px，贴边）" % [tree_rect.end.x, 66.0 + 1788.0]
	)
	# ⑤ 树大小与房屋相当：高差不超过 10%
	t.check(
		absf(tree_rect.size.y - gate_rect.size.y) <= gate_rect.size.y * 0.10,
		"树高 %.0f 与门楼高 %.0f 相当（差 ≤10%%）" % [tree_rect.size.y, gate_rect.size.y]
	)
	# ⑥ 菊石从门楼左侧露出（几何上无法完整放到门楼左侧，见 def 注释）
	t.check(
		chrs_rect.position.x < gate_rect.position.x,
		"菊石左缘 %.0f < 门楼左缘 %.0f（菊石在门楼左侧露出）" % [chrs_rect.position.x, gate_rect.position.x]
	)
	var exposed: float = gate_rect.position.x - chrs_rect.position.x
	t.check(exposed >= 20.0 and exposed <= 60.0, "菊石在门楼左侧露出 %.0f px（要求 20~60，能辨认又不喧宾夺主）" % exposed)
	# ⑦ 树右缘必须**贴住幕布右边界**（用户「靠近幕布边界」），
	#    同时不越出幕布——越界会被渲染器裁掉，那不叫「靠边」叫「出界」。
	t.check(
		tree_rect.end.x <= 66.0 + 1788.0 + 0.5,
		"树右缘 %.0f 未越出幕布右缘 %.0f" % [tree_rect.end.x, 66.0 + 1788.0]
	)
	t.check(
		66.0 + 1788.0 - tree_rect.end.x <= 40.0,
		"树右缘距幕布右仅 %.0fpx（贴边，符合「靠近幕布边界」）" % [66.0 + 1788.0 - tree_rect.end.x]
	)

	# ⑧ 花篮已于 2026-10-11 用户定案撤下（加入当天即移除）。
	#    这里留一条**反向断言**：确保它不会被人误加回来——门两侧摆两盆花读起来太满，
	#    且与菊花的陪衬角色重复。若日后确实要复用花篮，先改这条断言再改数据。
	t.check_eq(basket_rect.size, Vector2.ZERO, "花篮已撤下（不在 items 里）")


## 常量与数据同源：改常量忘改数据（或反过来）必须被测试抓住
func _constants_consistency(t: RefCounted) -> void:
	t.begin("常量与数据同源")
	var def: CSceneryDef = DefScript.make_level1()
	var willow: Dictionary = _find(def, "willow_left")
	var bridge: Dictionary = _find(def, "bridge_right")
	t.check_approx(
		float(willow.get("anchor_x", 0.0)),
		0.12485374,
		1e-6,
		(
			"LEVEL1_WILLOW_X ≈ 0.12485374（派生式：贴图左缘恒在 x=96＝幕布左 66 + 内边距 30px，"
			+ "scale 变则本值自动跟着变）"
		)
	)
	t.check_approx(
		float(bridge.get("anchor_x", 0.0)),
		0.73,
		1e-6,
		"LEVEL1_BRIDGE_CENTER_X 常量值 = 0.73（2026-10-09「桥头左移，完整拱」定案）"
	)
	t.check_approx(
		DefScript.LEVEL1_WILLOW_HEIGHT_PX,
		0.8 * 588.0,
		1e-6,
		"LEVEL1_WILLOW_HEIGHT_PX = 470.4（用户 2026-10-15 定案「树高 = 0.8 × 幕布高 588」）"
	)
	t.check_approx(
		DefScript.LEVEL1_WILLOW_SCALE,
		0.25482124,
		1e-6,
		"LEVEL1_WILLOW_SCALE ≈ 0.25482124（派生式：树高 470.4px ÷ 素材高 1846）"
	)
	t.check_approx(
		DefScript.LEVEL1_Y_DOWN,
		90.0 / 1080.0,
		1e-9,
		"LEVEL1_Y_DOWN = 90/1080（用户 2026-10-15「下移 95」再「上移 5」→ 净下移 90px）"
	)
	t.check_approx(
		DefScript.LEVEL1_WILLOW_BASE_Y,
		0.61346776,
		1e-6,
		(
			"LEVEL1_WILLOW_BASE_Y ≈ 0.61346776（派生式：(572.8 + 下移 90 − scale)/1080，"
			+ "贴图底缘恒 662.8px、与桥同线）"
		)
	)
	t.check_approx(
		float(willow.get("anchor_y", 0.0)),
		DefScript.LEVEL1_WILLOW_BASE_Y,
		1e-6,
		"柳树 anchor_y = LEVEL1_WILLOW_BASE_Y（与桥底同线）"
	)
	# 接地线（用户二次定案：0.50 → 0.53；2026-10-15 再整关净下移 90px）
	t.check_approx(
		DefScript.LEVEL1_GROUND_Y,
		0.53 + 90.0 / 1080.0,
		1e-6,
		"LEVEL1_GROUND_Y ≈ 0.613333（用户定案「再往下移动 0.03」+ 2026-10-15 净下移 90）"
	)
	t.check_approx(
		float(bridge.get("anchor_y", 0.0)),
		DefScript.LEVEL1_GROUND_Y,
		1e-6,
		"拱桥 anchor_y = LEVEL1_GROUND_Y"
	)
	# 纵轴容差（用户三次定案：放宽至 0.5）
	t.check_approx(DefScript.Y_TOLERANCE, 0.5, 1e-6, "Y_TOLERANCE = 0.5（用户定案「放宽至 0.5」）")
	# 形状参数（用户二次定案）
	t.check_approx(
		float(willow.get("params", {}).get("trunk_height", 0.0)),
		0.25,
		1e-6,
		"树干高 0.25（用户定案「更高 0.05」）"
	)
	t.check_approx(
		float(bridge.get("params", {}).get("deck_thickness", 0.0)),
		0.048,
		1e-6,
		"桥身厚 0.048（用户定案「厚度增加 0.03」）"
	)
	# 拱顶高（用户三次定案：0.10 → 0.13）
	t.check_approx(
		float(bridge.get("params", {}).get("deck_rise", 0.0)), 0.13, 1e-6, "拱顶高 0.13（用户定案）"
	)


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
