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
	var level: Node = game.get("_level")
	level.set_process(false)
	var harness: Level1Harness = level.get("_harness")
	harness.set_paused(true)
	check(level.has_node("CStageBinding"), "正式入口缺少布景绑定")
	var controller: PuppetController = harness.runtime.puppet_controller
	var bai: PuppetState = controller.get_puppet(0)
	var qing: PuppetState = controller.get_puppet(2)
	var xuxian: PuppetState = controller.get_puppet(1)
	# 开局三具影人**都不在桥上**：2026-10-16 定案把两位娘子放在柳树下（0.26 / 0.32）、
	# 许仙放在桥头（0.5285，正是桥跨左缘 0.52853）。脚点因此落在**各自的落地线**上：
	# 许仙 0.587963（635px）、两位娘子 0.597222（645px）——都在 `scripts/a/stage_def.gd`
	# 的 `initial.positions` 里，这里**与它同源取数**（不另写一份数字，站位改了自动跟随）。
	#
	# 🔴 2026-10-16 口径改动（用户看游戏后报「人物站位太高」）：旧版锁的是
	#    「三具影人 y 全部 == 0.5」。那是 `set_walk_path()` 对所有影人一律写 `height_at(x)`、
	#    而它在桥跨之外的兜底是 0.5 造成的：三具影人开局正好全在桥跨外，脚点被统一抬到
	#    540px，关卡数据里的 635/645px 从未生效。现在**桥外回各自的落地线**。
	var lines: Dictionary = StageDef.make_level1().initial["positions"]
	var bai_ground: float = controller.ground_y(0)
	for state: PuppetState in [bai, xuxian, qing]:
		var line: float = float(lines[state.puppet_id][1])
		check(
			is_equal_approx(state.stage_pos.y, line),
			(
				"影人 %d 开场脚点不是自己的落地线（y=%.6f，落地线 %.6f）"
				% [state.puppet_id, state.stage_pos.y, line]
			)
		)
	await capture(level, "opening")
	var path: RefCounted = null
	if not ResourceLoader.exists("res://scripts/a/stage_walk_path.gd"):
		check(false, "缺少桥面路径")
	else:
		path = load("res://scripts/a/stage_walk_path.gd").new()
		check(not path.is_on_deck(0.23), "0.23 不在桥跨内，却算成了桥面")
		check(path.is_on_deck(0.73), "桥心 0.73 必须落在桥跨内")
		check(not path.is_on_deck(xuxian.stage_pos.x), "桥头 0.5285 不该算在桥跨内")
		var shore: float = path.height_at(0.23, bai_ground)
		check(is_equal_approx(shore, bai_ground), "接伞岸边的高度不是落地线")
		check(path.height_at(0.73) < path.height_at(0.80), "桥顶与下坡高度颠倒")
		for x in [0.529, 0.530, 0.531, 0.73, 0.80, 0.86, 0.93]:
			check(absf(path.height_at(x + 0.0001) - path.height_at(x)) < 0.001, "桥面不连续")
		check(
			is_equal_approx(bai.stage_pos.y, path.height_at(bai.stage_pos.x, bai_ground)),
			"白素贞脚点偏离落地线"
		)
		check(
			is_equal_approx(qing.stage_pos.y, path.height_at(qing.stage_pos.x, controller.ground_y(2))),
			"小青脚点偏离落地线"
		)
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
		# 走到桥跨左端之外（0.23）→ 脚点必须回**她自己的**落地线，而不是任何固定常数。
		check(
			is_equal_approx(bai.stage_pos.y, bai_ground),
			"下桥没回到自己的落地线（y=%.6f，落地线 %.6f）" % [bai.stage_pos.y, bai_ground]
		)
		controller.begin_drag(0, Vector2(bai.stage_pos.x * 1920, bai.stage_pos.y * 1080 - 45))
		controller.drag_to(Vector2((0.80 - bai.stage_pos.x) * 1920, 0))
		controller.end_drag()
		# 走回 0.80（桥面下坡段）后脚点必须跟着桥面抬高、明显高于落地线。
		# 🔴 阈值不写死：直接与路径自己的读数、以及她自己的落地线比。旧写法是 `y < 0.45`，
		#    而景物整体下移 90px（`LEVEL1_Y_DOWN`）之后桥面 0.80 处是 **0.4503**——只差
		#    0.3px 就误报，这种「擦边阈值」在下一次挪动布景时必然再炸一次。
		if path != null:
			var deck: float = path.height_at(0.80, bai_ground)
			check(is_equal_approx(bai.stage_pos.y, deck), "返回后的脚点偏离桥面")
			check(deck < bai_ground - 0.02, "桥面 0.80 处没有明显高于落地线（%.4f）" % deck)
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
