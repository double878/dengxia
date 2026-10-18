extends SceneTree
## 正式第三幕第一场应有独立开演、真实动作许可与原声状态。
const SCENE := preload("res://scenes/act3/opening.tscn")
const GAME := preload("res://scenes/game_flow.tscn")
const Helper := preload("res://tests/c/run_act2_actions.gd")
var checks: int = 0
var failures: int = 0
var screenshots: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ACT3_STORY: " + label)


func _run() -> void:
	var game: Node = GAME.instantiate()
	game.set("_stage_id", 3)
	root.add_child(game)
	var host: Node = game.get("_level")
	host.set_process(false)
	check(host.has_method("start_scene"), "戏单确认后才独立开演")
	check(host.get("actions") != null, "空山入口尚未成为可操演场次")
	if host.get("actions") == null:
		game.queue_free()
		quit(1)
		return
	check(host.on_stage.is_empty(), "戏单不能提前上演员")
	advance(host, 3)
	check(
		host.clock.get_real_time_ms() == 0 and host.capture.record.snapshots.is_empty(), "戏单时间不计入演出"
	)
	await shot("playbill")
	host.start_scene()
	# 完整动作回归加速时使用自由时钟；原声播放另作真实时间检查。
	if host.audio.player != null:
		host.audio.player.stop()
		host.clock.set_player(null)
	else:
		check(
			not host.audio.config.audio_available and host.audio.config.main_path.is_empty(),
			"无声排练不能伪造原声"
		)
	check(host.capture.record.snapshots[0].time_ms == 0, "开演记录须从零开始")
	Helper.key(host, KEY_2)
	check(host.on_stage.is_empty(), "鹿童不能早于白素贞上场")
	advance(host, 28)
	check(host.actions.wait_step == "entrance", "等待真实上山，不自动上场")
	var song: int = host.clock.get_song_time_ms()
	var real: int = host.clock.get_real_time_ms()
	advance(host, 8.2)
	check(host.actions.remedy.has_open_windows(), "等待后出现师父手补救")
	check(
		host.clock.get_song_time_ms() == song and host.clock.get_real_time_ms() > real + 8000,
		"等待冻结歌曲、真实时间继续"
	)
	await shot("waiting")
	Helper.key(host, KEY_ESCAPE)
	real = host.clock.get_real_time_ms()
	var count: int = host.capture.record.snapshots.size()
	advance(host, 3)
	Helper.key(host, KEY_1)
	check(
		(
			host.clock.get_real_time_ms() == real
			and host.capture.record.snapshots.size() == count
			and host.on_stage.is_empty()
		),
		"菜单暂停冻结双时钟、输入和记录"
	)
	Helper.key(host, KEY_ESCAPE)
	advance(host, 8.2)
	check(not host.actions.remedy.has_open_windows() and host.actions.index == 0, "补救超时仍不代演")
	Helper.key(host, KEY_1)
	Helper.key(host, KEY_SPACE)
	move(host, 0, 310)
	check(host.actions.index == 1, "真实移步许可上山")
	Helper.key(host, KEY_1)
	check(host.controller.get_puppet(0).stage_pos.x > .29, "重复上场保留姿势和位置")
	check(await until_wait(host, "challenge"), "拦路字头前等待实际走近山脚")
	Helper.key(host, KEY_2)
	check(not host.on_stage.has(1), "鹿童须在近山后自动出场")
	move_to(host, 0, .56)
	check(host.on_stage.has(1) and host.guard_entrance.active, "近山自动触发鹿童出山")
	advance(host, 1.2)
	check(host.actions.phase == "free_performance", "鹿童跳出后进入自由操演")
	await shot("challenge")
	song = host.clock.get_song_time_ms()
	advance(host, 12)
	check(host.clock.get_song_time_ms() >= song + 11900, "不做退步抬掌仍唱过原关键动作点")
	check(not host.actions.waiting and not host.actions.remedy.has_open_windows(), "自由操演没有动作等待与补救")
	# 玩家可自由走位、摆手和前倾，声音不依赖这些姿态。
	move(host, 0, -90)
	raise_hand(host, 0, Vector2(100, -260))
	Helper.take(host, 0)
	Helper.drag(
		host,
		host._views[0].torso_screen_position(),
		Vector2(45 * host.controller.get_puppet(0).facing, 0),
		true
	)
	check(host.controller.get_puppet(0).torso_lean > .18, "自由操演仍可摆上身")
	await shot("plead")
	Helper.right(host, 1)
	advance(host, .2)
	song = host.clock.get_song_time_ms()
	advance(host, 10)
	check(host.clock.get_song_time_ms() >= song + 9900, "收走鹿童仍连续唱腔")
	Helper.key(host, KEY_2)
	check(not host.guard_entrance.active, "恢复鹿童不重演出山")
	host.lamp_controller.lamp.exposure = .1
	song = host.clock.get_song_time_ms()
	advance(host, 25)
	check(host.clock.get_song_time_ms() >= song + 24900, "压暗和不做作揖仍持续唱腔")
	host.lamp_controller.lamp.exposure = .7
	raise_hand(host, 1, Vector2(-75, -260))
	move(host, 1, -110)
	await shot("lunge")
	check(not host.actions.waiting, "自由摆剑不受进剑避让门槛限制")
	var record: CPerformanceRecord = host.capture.record
	var scene_duration: int = host.audio.config.duration_ms
	advance(host, (scene_duration - host.clock.get_song_time_ms()) / 1000.0 + 1.5)
	check(host.actions.phase == "awaiting_exit", "整轨结束后保留舞台等待谢别离场")
	Helper.take(host, 0)
	Helper.key(host, KEY_W)
	advance(host, .2)
	Helper.right(host, 0)
	advance(host, 1.5)
	await process_frame
	check(game.get("_level") == null, "完整原声与收势结束后释放操演宿主")
	check(game.get("_flow") != null, "仙翁谢别后正式提供回放选择")
	var flow: CResultFlow = game.get("_flow")
	check(record.validate_invariants().is_empty(), "演出记录必须完整")
	check(record.duration_ms > scene_duration + 18000, "实际等待不能从回放中删掉")
	check(record.events.any(func(e: Variant) -> bool: return e.kind == &"remedy_timeout"), "原失误保留")
	if flow != null:
		game._choose_replay(true)
		var replay: Node = game.get("_replay")
		replay.set_process(false)
		check(
			replay.get("_act3_view") != null and replay.get("_metronome") == null,
			"第三幕回放使用原场素材，不添加节拍器"
		)
		var player: CReplayPlayer = flow.get_player()
		for snapshot: CSnapshot in record.snapshots:
			if (
				snapshot.performance.get("guard_behind_mountain", false)
				and snapshot.puppets[1].stage_pos.y < .57
			):
				var airborne: Dictionary = player.sample(snapshot.time_ms)
				airborne.state = &"playing"
				replay.apply_frame(airborne)
				check(replay._surface.projection_views[1].entrance_mask != null, "幕前重建鹿童腾空时的山后遮挡")
				check(
					replay._surface.projection_views[1].puppet_state.stage_pos.y < .57, "幕前保留真实腾空高度"
				)
				await shot("replay-jump")
				break
		var matches: Callable = func(s: Variant) -> bool:
			var frame: Dictionary = player.sample(s.time_ms)
			return (
				frame.puppets == s.puppets
				and frame.performance == s.performance
				and frame.lamp == s.lamp
			)
		check(record.snapshots.all(matches), "逐采样点动作、字幕、等待与灯态一致")
		for s: CSnapshot in record.snapshots:
			if (
				s.performance.phase == "free_performance"
				and s.performance.song_ms > 70000
				and not s.performance.frozen
			):
				var frame: Dictionary = player.sample(s.time_ms)
				frame.state = &"playing"
				replay.apply_frame(frame)
				check(
					(
						replay._surface.front_view
						and replay._surface.projection_views[1].skin_override == 5
					),
					"幕前显示鹿童分件"
				)
				check(replay._act3_view.sword.on_stage.has(1), "幕前剑跟随鹿童手")
				await shot("replay")
				break
		replay.toggle_pause()
		check(flow.get_player().get_state() == &"paused", "回放可暂停")
		replay.toggle_pause()
		game._skip_replay()
		check(flow.get_flow_state() == &"result", "跳过回放进入收场")
		await shot("intermission")
		game._restart()
		check(game.get("_level").actions.phase == "ready", "重排从戏单重新开始")
	game.queue_free()
	await process_frame
	var entry: Node = load("res://scenes/act3/rehearsal.tscn").instantiate()
	root.add_child(entry)
	check(
		entry.get("_stage_id") == 3 and entry.get("_level").actions.phase == "ready",
		"专用入口直接开始第三幕戏单"
	)
	entry.queue_free()
	await process_frame
	# 山前相对站位许可；玩家不必猜某个不可见的精确横坐标。
	var alternative: Node = SCENE.instantiate()
	root.add_child(alternative)
	alternative.set_process(false)
	alternative.start_scene()
	if alternative.audio.player != null:
		alternative.audio.player.stop()
		alternative.clock.set_player(null)
	Helper.key(alternative, KEY_1)
	move_to(alternative, 0, .635)
	advance(alternative, 13.2)
	advance(alternative, 1.2)
	advance(alternative, 17)
	check(
		alternative.guard_entrance.triggered and alternative.actions.phase == "free_performance",
		"不同山前站位均自动跳出并进入自由操演"
	)
	alternative.queue_free()
	await process_frame
	if OS.get_cmdline_user_args().has("--act3-rehearsal"):
		var command_entry: Node = GAME.instantiate()
		root.add_child(command_entry)
		check(command_entry.get("_stage_id") == 3, "导出启动参数直接进入第三幕")
		command_entry.queue_free()
		await process_frame
	print("ACT3_STORY checks=%d failures=%d" % [checks, failures])
	if DisplayServer.get_name() != "headless":
		var output := FileAccess.open("res://builds/act3-story/verification.json", FileAccess.WRITE)
		output.store_string(
			JSON.stringify(
				{
					"checks": checks,
					"failures": failures,
					"screenshots": screenshots,
					"original_audio_playback_verified": false
				},
				"\t"
			)
		)
	quit(1 if failures else 0)


static func advance(host: Node, seconds: float) -> void:
	for _i in range(int(ceil(seconds * 60.0))):
		host._process(1.0 / 60.0)


func until_wait(host: Node, step: String, limit_s: float = 60) -> bool:
	for _i in range(int(ceil(limit_s * 60.0))):
		if host.actions.wait_step == step:
			return true
		host._process(1.0 / 60.0)
	return host.actions.wait_step == step


static func move(host: Node, id: int, dx: float) -> void:
	Helper.take(host, id)
	Helper.drag(host, host.HAND_ANCHOR, Vector2(dx, 0))
	advance(host, .15)


static func move_to(host: Node, id: int, x: float) -> void:
	move(host, id, (x - host.controller.get_puppet(id).stage_pos.x) * 1920.0)


static func raise_hand(host: Node, id: int, offset: Vector2) -> void:
	Helper.take(host, id)
	var view: PlaceholderPuppet = host._views[id]
	var foot: Vector2 = view.stage_to_screen(host.controller.get_puppet(id).stage_pos)
	var wrist: Vector2 = view.hand_screen_position("right")
	Helper.drag(host, wrist, foot + offset - wrist)
	advance(host, .05)


func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/act3-story")
	check(
		root.get_texture().get_image().save_png("res://builds/act3-story/" + name + ".png") == OK,
		"图形截图：" + name
	)
	screenshots.append(name)
