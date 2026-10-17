extends SceneTree
## 正式入口的桥面与距离驱动步态回归。

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)


func _run() -> void:
	var game: Node = load("res://scenes/game_flow.tscn").instantiate()
	root.add_child(game)
	game._intro_finished()  # 此用例从实际操演开始。
	var level: Node = game.get("_level")
	level.set_process(false)
	var harness: Level1Harness = level.get("_harness")
	harness.set_paused(true)
	check(level.has_node("CStageBinding"), "正式入口缺少布景绑定")
	var controller: PuppetController = harness.runtime.puppet_controller
	var bai: PuppetState = controller.get_puppet(0)
	var qing: PuppetState = controller.get_puppet(2)
	check(bai.stage_pos.y < 0.45, "白素贞开场未在桥面")
	check(qing.stage_pos.y < 0.48, "小青开场未在桥面")
	await capture(level, "opening")
	if not ResourceLoader.exists("res://scripts/a/stage_walk_path.gd"):
		check(false, "缺少桥面路径")
	else:
		var path: RefCounted = load("res://scripts/a/stage_walk_path.gd").new()
		var shore: float = path.height_at(0.23)
		check(is_equal_approx(shore, 0.5), "接伞岸边高度不正确")
		check(path.height_at(0.73) < path.height_at(0.80), "桥顶与下坡高度颠倒")
		for x in [0.529, 0.530, 0.531, 0.73, 0.80, 0.86, 0.93]:
			check(absf(path.height_at(x + 0.0001) - path.height_at(x)) < 0.001, "桥面不连续")
		check(is_equal_approx(bai.stage_pos.y, path.height_at(bai.stage_pos.x)), "白素贞脚点偏离桥面")
		check(is_equal_approx(qing.stage_pos.y, path.height_at(qing.stage_pos.x)), "小青脚点偏离桥面")
	if bai.get("walk_phase") == null:
		check(false, "影人缺少可记录步态")
	else:
		var hands := bai.hand_angle
		check(
			controller.begin_drag(0, Vector2(bai.stage_pos.x * 1920, bai.stage_pos.y * 1080 - 45)),
			"桥上胸签无法拖动"
		)
		controller.drag_to(Vector2(-18, 0))
		controller.tick(1.0 / 60.0)
		check(bai.walk_amount > 0.0 and bai.walk_phase > 0.0, "横向拖动没有迈步")
		check(bai.hand_angle == hands, "走路修改了手角")
		await capture(level, "walking")
		var phase: float = bai.walk_phase
		controller.tick(1.0 / 60.0)
		check(bai.walk_amount == 0.0 and bai.walk_phase == phase, "站定没有收脚")
		controller.drag_to(Vector2((0.23 - bai.stage_pos.x) * 1920, 0))
		controller.end_drag()
		check(is_equal_approx(bai.stage_pos.y, 0.5), "下桥没有到岸边")
		controller.begin_drag(0, Vector2(bai.stage_pos.x * 1920, bai.stage_pos.y * 1080 - 45))
		controller.drag_to(Vector2((0.80 - bai.stage_pos.x) * 1920, 0))
		controller.end_drag()
		check(bai.stage_pos.y < 0.45, "返回没有上桥")
		check(bai.to_dict().has("walk_phase"), "步态未进入数据视图")
		check(qing.get("walk_amount") == 0.0, "未移动的小青在走路")
	harness.shutdown()
	game.queue_free()
	await process_frame
	print("STAGE_WALK checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func capture(level: Node, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	level._refresh_ui()
	for _i in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/stage-walk")
	check(
		root.get_texture().get_image().save_png("res://builds/stage-walk/%s.png" % label) == OK,
		"截图保存失败"
	)
