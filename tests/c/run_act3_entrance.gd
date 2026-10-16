extends SceneTree
## 原声开演、山脚触发与自动跳出的端到端回归。
const SCENE := preload("res://scenes/act3/opening.tscn")
const Story := preload("res://tests/c/run_act3_story.gd")
const Helper := preload("res://tests/c/run_act2_actions.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ACT3_ENTRANCE: " + label)


func _run() -> void:
	var host: Node = SCENE.instantiate()
	root.add_child(host)
	host.set_process(false)
	check(host.audio.problem.is_empty(), "有声素材必须能加载")
	check(host.audio.player != null, "新视频须提供真实原声")
	if host.audio.player == null:
		host.queue_free()
		await process_frame
		quit(1)
		return
	check(not host.audio.player.playing, "戏单尚未开演时不播放")
	host.start_scene()
	check(host.audio.player.playing and not host.audio.player.stream_paused, "空山开演即播原声")
	# 加速动作测试使用自由时钟，实际音频线程另在图形环境测量。
	host.audio.player.stop()
	host.clock.set_player(null)
	Story.advance(host, 20)
	check(not host.clock.is_song_frozen(), "无演员的前奏不能等白素贞停乐")
	check(host.clock.get_song_time_ms() >= 19900, "空山前奏应持续前进")
	Helper.key(host, KEY_2)
	check(host.on_stage.is_empty(), "按2不能让鹿童提前上场")
	Helper.key(host, KEY_1)
	Story.move_to(host, 0, .46)
	check(not host.on_stage.has(1), "远离山脚不触发鹿童")
	Story.move_to(host, 0, .56)
	check(not host.on_stage.has(1), "提前靠山必须等到前奏末尾重音，不能立即出山")
	var cue_ms: int = int(host.audio.config.gates[1].at_ms)
	Story.advance(host, (cue_ms - host.clock.get_song_time_ms()) / 1000.0 - .20)
	check(not host.on_stage.has(1), "重音之前鹿童仍在山后")
	Helper.key(host, KEY_ESCAPE)
	Story.advance(host, 2)
	check(not host.on_stage.has(1), "等重音时菜单暂停不能触发出山")
	Helper.key(host, KEY_ESCAPE)
	Story.advance(host, .24)
	check(host.on_stage.has(1), "重音到达后自动请出鹿童")
	if not host.on_stage.has(1):
		host.queue_free()
		await process_frame
		quit(1)
		return
	var guard: PuppetState = host.controller.get_puppet(1)
	check(guard.stage_pos.y * 1080.0 < 642.0, "重音落点直接起跳，不再追加蓄势延迟")
	var start: Vector2 = guard.stage_pos
	Story.advance(host, .35)
	check(guard.stage_pos.x < start.x and guard.stage_pos.y < start.y - .02, "鹿童向左腾空出山")
	check(host._views[1].entrance_mask != null, "腾空时沿山轮廓揭露")
	Helper.key(host, KEY_SPACE)
	check(host.controller.controlled_id != 1, "跳跃期间不能接手鹿童")
	Helper.right(host, 1)
	check(host.on_stage.has(1), "跳跃期间不能收走鹿童")
	Helper.key(host, KEY_ESCAPE)
	var paused_position: Vector2 = guard.stage_pos
	Story.advance(host, 2)
	check(guard.stage_pos == paused_position, "菜单暂停冻结跳跃")
	Helper.key(host, KEY_ESCAPE)
	Story.advance(host, 1)
	check(absf(guard.stage_pos.y * 1080 - 642) < .01, "鹿童落回同一地面")
	check(host._views[1].entrance_mask == null, "落地后在山前完整显形")
	check(guard.facing < 0 and host._sword.geometry().direction.x < 0, "落地面向白素贞持剑")
	var landed: Vector2 = guard.stage_pos
	Story.move_to(host, 0, .46)
	Story.move_to(host, 0, .56)
	check(guard.stage_pos == landed, "反复靠山不重复跳跃")
	Helper.key(host, KEY_SPACE)
	check(host.controller.controlled_id == 1, "落地后空格可接手鹿童")
	var song: int = host.clock.get_song_time_ms()
	Story.advance(host, 20)
	check(host.clock.get_song_time_ms() >= song + 19900, "跳出后不做退步抬掌也连续唱过原关键动作点")
	check(not host.actions.waiting and not host.actions.remedy.has_open_windows(), "自由操演不要求关键动作或补救")
	Helper.right(host, 1)
	host.lamp_controller.lamp.exposure = .1
	song = host.clock.get_song_time_ms()
	Story.advance(host, 10)
	check(host.clock.get_song_time_ms() >= song + 9900, "自由退场和压暗不暂停唱腔")
	Helper.key(host, KEY_2)
	check(host.controller.get_puppet(1).stage_pos == landed, "自由退场后恢复原位置，不重新跳出")
	var record: CPerformanceRecord = host.capture.record
	check(record.validate_invariants().is_empty(), "自动出山录制符合契约")
	var airborne: CSnapshot = null
	for frame: CSnapshot in record.snapshots:
		if (
			frame.performance.get("guard_behind_mountain", false)
			and frame.puppets[1].stage_pos.y < .57
		):
			airborne = frame
			break
	check(airborne != null, "腾空和山后遮挡进入真实记录")
	if airborne != null:
		var player := CReplayPlayer.new()
		player.load(record)
		var sample: Dictionary = player.sample(airborne.time_ms)
		check(sample.puppets == airborne.puppets, "回放保留腾空位置和关节")
		check(sample.performance.guard_behind_mountain, "回放保留山后遮挡")
	host.queue_free()
	await process_frame
	print("ACT3_ENTRANCE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
