extends SceneTree
## 上身姿态、输入与录放的定向回归；可单独运行。

const TestBase := preload("res://tests/a/a_test_base.gd")
const State := preload("res://scripts/a/puppet_state.gd")
const View := preload("res://scripts/a_test/placeholder_puppet.gd")


func _initialize() -> void:
	var t := TestBase.new()
	t.begin("上半身共用姿态几何存在")
	if not t.check(FileAccess.file_exists("res://scripts/a/upper_body_pose.gd"), "缺少上身姿态计算"):
		quit(t.report())
		return
	var pose: Variant = load("res://scripts/a/upper_body_pose.gd")
	_test_geometry(t, pose)
	_test_view(t)
	quit(t.report())


func _test_geometry(t: ATestBase, pose: Variant) -> void:
	t.begin("拖手解算保持两段长度，边界与肩点有限")
	for right in [false, true]:
		var side: float = 1.0 if right else -1.0
		for offset in [Vector2(side * 30, -12), Vector2(side * 22, 22), Vector2(0, -62), Vector2(side * 150, -90), Vector2.ZERO]:
			var angles: Vector2 = pose.solve_arm(offset, right, 200.0)
			var points: Dictionary = pose.arm_points(Vector2.ZERO, angles.x, angles.y, right, 200.0)
			t.check(angles.is_finite(), "肩点和越界输入不能产生非有限角度")
			t.check_approx(points.elbow.length(), 32.0, 0.001, "上臂长度固定")
			t.check_approx(points.wrist.distance_to(points.elbow), 30.0, 0.001, "前臂长度固定")
			if offset.length() > 20 and offset.length() < 50:
				t.check(points.wrist.distance_to(offset) < 0.001, "可达手目标必须到位")
			if offset == Vector2(0, -62):
				t.check(points.wrist.distance_to(offset) < 0.001, "举过头顶不能跳到收手边界")
			t.check_in_range(angles.y, 0.0, deg_to_rad(150), "肘部不能反折")
	t.finish("两侧独立弯肘，越界保持长度")


func _test_view(t: ATestBase) -> void:
	t.begin("弯肘和头腰改变上身，保持下半身与只读显示")
	var state := State.new(0)
	state.head_id = 0
	state.is_controlled = true
	state.hand_angle = Vector2(PI * 0.5, PI * 0.5)
	var view := View.new()
	view.render_mode = View.RenderMode.ENTITY
	view.puppet_state = state
	var straight: Vector2 = view.hand_screen_position("right")
	state.set("elbow_angle", Vector2(0, PI * 0.5))
	var bent: Vector2 = view.hand_screen_position("right")
	t.check(bent.distance_to(straight) > 20, "弯肘应改变实际手的位置")
	var lower: Vector2 = state.stage_pos
	state.set("torso_lean", deg_to_rad(30))
	state.set("head_tilt", deg_to_rad(20))
	var before: Dictionary = state.to_dict().duplicate(true)
	t.check(view.hand_screen_position("right").distance_to(bent) > 10, "腰转动应带动手")
	t.check_eq(state.to_dict(), before, "几何查询不能写状态")
	t.check_eq(state.stage_pos, lower, "上身姿态不能移动脚点")
	t.check(before.has("elbow_angle") and before.has("head_tilt") and before.has("torso_lean"), "实际关节须进入录放数据")
	view.free()
	t.finish("实体查询与姿态数据共用同一几何")
