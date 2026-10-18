extends SceneTree
## 第三关山景回归：正式入口、原始贴图、构图与幕布裁剪；图形模式保存实际画面。

const OPENING := preload("res://scenes/act3/opening.tscn")
const GAME := preload("res://scenes/game_flow.tscn")
const MOUNTAIN_PATH := "res://assets/scenery/level3/mountain.png"
const CLOTH := Rect2(66, 92, 1788, 588)

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ACT3_MOUNTAIN: " + label)


func _run() -> void:
	var opening: Node = OPENING.instantiate()
	root.add_child(opening)
	await process_frame
	check(opening.get_node_or_null("StageBackdrop") is StageBackdrop, "没有沿用幕后舞台")
	var surface := opening.get_node_or_null("StageSurface") as StageSurface
	check(surface != null, "没有挂载幕布")
	if surface != null:
		check(surface.cloth == CLOTH and not surface.front_view, "幕布尺寸或幕后视角不符")
	var binding := opening.get_node_or_null("CStageBinding") as CStageBinding
	check(binding != null, "第三关入口没有接入山景")
	if binding != null:
		check(binding.stage_id == 3, "没有取第三关布景")
		check(not binding.enable_rain and binding.get("_rain") == null, "山景误加载游湖雨幕")
		var scenery := binding.get("_scenery") as CSceneryView
		check(scenery != null, "布景绑定未实际创建山景")
		if scenery != null:
			check(scenery.clip_rect == CLOTH, "山景没有裁在幕布内")
			check(scenery.z_index > surface.z_index, "山景被幕布盖住")
			var data: CSceneryDef = scenery.get("_def")
			check(data.stage_id == 3 and data.items.size() == 1, "山景件数或场次不符")
			var item: Dictionary = data.items[0]
			check(item["id"] == "mountain" and item["texture"] == MOUNTAIN_PATH, "没有使用队友的山")
			var texture: Texture2D = scenery._get_texture(MOUNTAIN_PATH)
			check(texture != null, "山体贴图无法加载")
			if texture != null:
				var scale: float = item["texture_scale_px"]
				var foot: Vector2 = item["texture_foot_px"]
				var anchor := Vector2(item["anchor_x"], item["anchor_y"]) * scenery.stage_size
				var bounds := Rect2(anchor - foot * scale, texture.get_size() * scale)
				check(absf(bounds.position.y - CLOTH.position.y) < 1.0, "山顶未贴幕布上沿")
				check(absf(bounds.end.y - CLOTH.end.y) < 1.0, "山脚未贴幕布下沿")
				check(absf(bounds.end.x - (CLOTH.end.x - 20.0)) < 1.0, "山体未靠右留边")
				check(bounds.position.x > 1300.0, "山体侵占左侧表演区")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var output := "res://builds/act3-mountain"
		check(DirAccess.make_dir_recursive_absolute(output) == OK, "无法创建截图目录")
		check(root.get_texture().get_image().save_png(output + "/backstage.png") == OK, "截图失败")
	opening.queue_free()
	await process_frame
	var game: Node = GAME.instantiate()
	game.set("_stage_id", 3)
	root.add_child(game)
	await process_frame
	var level: Node = game.get("_level")
	check(level != null and level.scene_file_path == "res://scenes/act3/opening.tscn", "正式流程未加载第三关")
	check(level.get_node_or_null("CStageBinding") != null, "正式流程进入后没有山景")
	game.queue_free()
	await process_frame
	print("ACT3_MOUNTAIN checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
