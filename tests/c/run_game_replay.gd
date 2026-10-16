extends SceneTree
## 从正式入口采集真实状态，验证选择、回放及收场生命周期。

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("GAME_REPLAY: " + label)


func _run() -> void:
	var game: Node = load("res://scenes/game_flow.tscn").instantiate()
	root.add_child(game)
	var level: Node = game.get("_level")
	level.set_process(false)
	var harness: Level1Harness = level.get("_harness")
	check(harness.get("capture") != null, "正式入口没有录制")
	if harness.get("capture") == null:
		harness.shutdown()
		game.queue_free()
		await process_frame
		quit(1)
		return
	# 测试只替换时钟音频来源；Runtime、剧情、录制与正式入口完全共用。
	harness.opera_audio.stop()
	harness.clock.set_player(null)
	var record: CPerformanceRecord = harness.capture.record
	var controller: PuppetController = harness.runtime.puppet_controller
	check(record.snapshots[0].time_ms == 0, "首帧不在 t=0")
	# 首帧的脚点高度必须来自**桥面步态路径**：桥跨以内随桥面、桥跨以外回**各自的落地线**
	# （落地线取自 `StageDef.initial.positions`，由 `set_walk_path()` 在接管路径前逐人记下，
	# 读数走 `PuppetController.ground_y()`，测试不另写一份数字）。
	# 🔴 旧写法是写死的 `y < 0.45`——那是「白素贞开局站在桥上（x=0.80）」时代的判据；
	#    2026-10-16 定案把两位娘子挪到柳树下（0.32 / 0.26，都在桥左侧的空地上），
	#    用户又报过「站位太高」，判据于是改成与数据同源的**机制比对**：
	#    录下来的脚点 == 路径在同一个 x、用她自己的落地线算出的高度。
	var walk: RefCounted = controller.walk_path
	check(walk != null, "第一关没有安装桥面步态路径")
	if walk != null:
		var first: CSnapshot = record.snapshots[0]
		var ground: float = controller.ground_y(0)
		var path_y: float = float(walk.height_at(first.puppets[0].stage_pos.x, ground))
		check(
			absf(first.puppets[0].stage_pos.y - path_y) < 0.001,
			(
				"首帧脚点不是路径按落地线算出的（实际 y=%.6f，路径给出 %.6f，落地线 %.6f）"
				% [first.puppets[0].stage_pos.y, path_y, ground]
			)
		)
	var bai: PuppetState = controller.get_puppet(0)
	controller.begin_drag(0, Vector2(bai.stage_pos.x * 1920, bai.stage_pos.y * 1080 - 45))
	controller.drag_to(Vector2(-18, 0))
	harness.advance_steps(1)
	check(record.snapshots[-1].puppets[0].get("walk_amount", 0.0) > 0, "录制漏掉迈步")
	controller.end_drag()
	controller.swap_head(0)
	harness.advance_steps(1)
	var switched_head: int = bai.head_id
	check(not controller.hook_current(), "开场满钩时不应凭空挂起")
	check(not controller.take_back(0), "手上有人时不应凭空取回")
	controller.swap_head(0)
	harness.advance_steps(1)
	check(record.snapshots[-1].puppets[0].get("walk_amount", 1.0) == 0, "录制漏掉收脚")
	harness.set_paused(true)
	var count: int = record.snapshots.size()
	harness.advance(1)
	check(record.snapshots.size() == count, "菜单暂停仍在录制")
	harness.set_paused(false)
	# 正式第一幕不操作：到位门等待 8 秒，之后前向跳过对白进入收尾。
	var guard: int = 0
	while not harness.runtime.is_over() and guard < 10000:
		harness.advance_steps(1)
		guard += 1
	level._process(0)
	check(guard < 10000, "正式演出无法结束")
	check(record.validate_invariants().is_empty(), "实际记录不合法")
	check(record.snapshots[-1].time_ms == harness.clock.get_real_time_ms(), "末尾等待被截掉")
	check(record.duration_ms == harness.clock.get_real_time_ms(), "实际时长不一致")
	check(
		record.events.any(func(e: Variant) -> bool: return str(e.kind) == "opera_wait_begin"),
		"缺少等待事件"
	)
	check(
		record.events.any(func(e: Variant) -> bool: return str(e.kind) == "opera_score_skipped"),
		"缺少跳段事件"
	)
	check(
		record.events.any(func(e: Variant) -> bool: return str(e.kind) == "dialogue_line_changed"),
		"缺少对白事件"
	)
	for kind: String in ["head_swap"]:
		check(record.events.any(func(e: Variant) -> bool: return str(e.kind) == kind), "缺少 " + kind)
	check(
		record.snapshots.any(
			func(s: Variant) -> bool: return int(s.puppets[0].head_id) == switched_head
		),
		"快照漏掉换头"
	)
	var waits: Array = record.snapshots.filter(
		func(s: Variant) -> bool: return bool(s.performance.get("waiting", false))
	)
	check(waits.size() > 100, "等待没有真实帧")
	check(waits[-1].time_ms - waits[0].time_ms >= 7900, "8 秒等待被压缩")
	check(waits[0].performance.song_ms == waits[-1].performance.song_ms, "等待期间歌曲未冻结")
	check(game.get("_flow").get_flow_state() == &"choice", "演出结束没有询问观看")
	check(not game.get("_flow").is_replaying(), "回放自动开始了")
	await capture("choice")
	game._choose_replay(false)
	check(game.get("_flow").can_rewatch(), "不看后丢失录像")
	await capture("result")
	game._watch_replay()
	check(game.get("_flow").is_replaying(), "结果页无法观看")
	var replay: Node = game.get("_replay")
	replay.set_process(false)
	var flow: CResultFlow = game.get("_flow")
	var player: CReplayPlayer = flow.get_player()
	player.set_clock_source(CReplayPlayer.CLOCK_SOURCE_DELTA)
	var snapshot: CSnapshot = waits[0]
	var frame: Dictionary = player.sample(snapshot.time_ms)
	check(
		frame.performance.waiting and frame.performance.song_ms == snapshot.performance.song_ms,
		"回放未还原等待"
	)
	replay.apply_frame(frame)
	check(replay.get("_surface").front_view, "回放未启用幕前镜像")
	check(
		(
			replay.get("_surface").projection_views[0].puppet_state.stage_pos.y
			== float(frame.puppets[0].stage_pos.y)
		),
		"回放脚点变了"
	)
	check(replay.get("_umbrella").holder_id_of() == 1, "未接伞的回放凭空换手")
	await capture("front-final")
	var matches_snapshot: Callable = func(s: Variant) -> bool:
		var sampled: Dictionary = player.sample(s.time_ms)
		return (
			sampled.puppets == s.puppets
			and sampled.lamp == s.lamp
			and sampled.performance == s.performance
		)
	check(record.snapshots.all(matches_snapshot), "回放在原采样点没有逐字段还原")
	player.play()
	flow.advance(0.25)
	replay.toggle_pause()
	var frozen: int = player.get_now_ms()
	flow.advance(1)
	check(player.get_now_ms() == frozen, "回放暂停仍推进")
	check(replay.get("_audio").is_replay_paused(), "回放音频未暂停")
	replay.apply_frame(flow.player_frame())
	var paused_image: Image = await capture("replay-paused")
	var paused_again: Image = await capture("replay-paused-again")
	if paused_image != null:
		check(paused_image.get_data() == paused_again.get_data(), "暂停画面未逐像素冻结")
	replay.toggle_pause()
	flow.advance(0.25)
	check(player.get_now_ms() > frozen, "回放不能继续")
	game._skip_replay()
	check(flow.get_flow_state() == &"result", "跳过没有回收场")
	game._watch_replay()
	player = flow.get_player()
	player.set_clock_source(CReplayPlayer.CLOCK_SOURCE_DELTA)
	check(player.get_now_ms() == 0, "重看没有从头开始")
	game._replay.set_process(false)
	game._replay._process(float(record.duration_ms) / 1000.0 + 1)
	check(flow.get_flow_state() == &"result", "自然结束没有回收场")
	game._restart()
	check(flow.is_released, "再演没有释放旧记录")
	check(game.get("_level") != null and game.get("_replay") == null, "再演没有回幕后")
	game.queue_free()
	await process_frame
	print(
		(
			"GAME_REPLAY checks=%d failures=%d duration=%d snapshots=%d events=%d"
			% [checks, failures, record.duration_ms, record.snapshots.size(), record.events.size()]
		)
	)
	quit(1 if failures else 0)


func capture(label: String) -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	for _i in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/stage-walk")
	var picture: Image = root.get_texture().get_image()
	check(picture.save_png("res://builds/stage-walk/%s.png" % label) == OK, "保存截图")
	return picture
