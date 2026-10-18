extends SceneTree
## 连续打戏的行为回归：旧片不收场、自动拔剑、双童接战、不接管白素贞。
const Story := preload("res://tests/c/run_act3_story.gd")
const Helper := preload("res://tests/c/run_act2_actions.gd")
const Fight := preload("res://scripts/act3/fight_choreography.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ACT3_FIGHT: " + label)


func _run() -> void:
	var host: Node = load("res://scenes/act3/opening.tscn").instantiate()
	root.add_child(host)
	host.set_process(false)
	host.start_scene()
	host.audio.player.stop()
	host.clock.set_player(null)
	Helper.key(host, KEY_1)
	Story.move_to(host, 0, .56)
	Story.advance(host, 2)
	Story.advance(host, 102)
	check(host.actions.phase != "finished", "旧片结束不收场或回放")
	check(host.audio.config.duration_ms > 139000, "新片与旧片共用连续原声")
	check(host.controller.puppets.size() == 3, "鹿童与鹤童均有真实姿态槽位")
	var fight: Variant = host.get("fight")
	check(fight != null, "双童配合演出已接入宿主")
	if fight != null:
		await exercise(host)
		check_moves(host.audio.config)
		check_crane_space()
	host.queue_free()
	await process_frame
	print("ACT3_FIGHT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func exercise(host: Node) -> void:
	var white: PuppetState = host.controller.get_puppet(0)
	var progress: Array = host.fight.sword_progress()
	check(progress[0] == 1.0, "到唱词自动拔剑，无需按键")
	check(host.on_stage.has(1) and not host.on_stage.has(2), "先由鹿童接战")
	Helper.key(host, KEY_SPACE)
	check(host.controller.controlled_id == 0, "交手期间空格只接白素贞")
	white.hand_angle = Vector2(.45, 1.25)
	white.elbow_angle = Vector2(.15, .55)
	white.torso_lean = .25
	var position: Vector2 = white.stage_pos
	Story.advance(host, 1)
	check(white.stage_pos == position, "自动配合不移动白素贞")
	check(white.hand_angle == Vector2(.45, 1.25), "自动配合不替玩家挥剑")
	check(white.torso_lean == .25, "自动配合不替玩家前倾")
	check_sword(host)
	check_jump_cut(host)
	check_contacts(host)
	Helper.right(host, 1)
	check(host.on_stage.has(1), "搭戏期间不能误收走自动演员")
	Helper.key(host, KEY_ESCAPE)
	var before: Dictionary = host.controller.get_puppet(1).to_dict()
	var song: int = host.clock.get_song_time_ms()
	Story.advance(host, 2)
	check(host.controller.get_puppet(1).to_dict() == before, "暂停保持对手进攻姿态")
	check(host.clock.get_song_time_ms() == song, "暂停冻结剧情歌曲时间")
	Helper.key(host, KEY_ESCAPE)
	Story.advance(host, 14)
	check(not host.on_stage.has(1), "鹿童按原声败退")
	Story.advance(host, 5)
	check(host.on_stage.has(2), "鹤童自动接战")
	var old_x: float = host.controller.get_puppet(2).stage_pos.x
	Story.move_to(host, 0, .20)
	Story.advance(host, 4)
	check(host.controller.get_puppet(2).stage_pos.x < old_x, "对手随玩家移动调整接战距离")
	check(white.hand_angle == Vector2(.45, 1.25), "换对手不重置玩家手姿")
	Story.advance(host, 15)
	check(white.stage_pos.y == position.y and white.torso_lean == .25, "跌倒唱词不强制白素贞倒地")
	check(host.actions.phase == "free_performance" and host.finale.active, "原打戏片尾接仙翁，保持同场操演")
	check(not host.get("_emitted"), "未完成整关不发收场信号")
	Story.move_to(host, 0, .32)
	check(absf(white.stage_pos.x - .32) < .01, "仙翁段仍能自由操演")
	check(host.capture.record.validate_invariants().is_empty(), "三人连续记录合法")
	var crane_mask_recorded: bool = false
	for snapshot: CSnapshot in host.capture.record.snapshots:
		if snapshot.performance.get("crane_behind_mountain", false):
			crane_mask_recorded = true
			break
	check(crane_mask_recorded, "鹤童出山保留实际山后遮挡")
	check(host.capture.finish(), "三人记录可供真实回放读取")
	var flow := CResultFlow.new()
	check(flow.offer_replay(host.capture.record, 3), "同场连续录放可载入")
	flow.choose_replay(true)
	var replay: Node = load("res://scripts/b/performance_replay.gd").new()
	replay.flow = flow
	replay.stage_id = 3
	root.add_child(replay)
	replay.set_process(false)
	var player: CReplayPlayer = flow.get_player()
	var saw_crane: bool = false
	for snapshot: CSnapshot in host.capture.record.snapshots:
		if snapshot.performance.get("on_stage", []).has(2):
			var frame: Dictionary = player.sample(snapshot.time_ms)
			frame.state = &"playing"
			replay.apply_frame(frame)
			check(replay._surface.projection_views[2].skin_override == 6, "回放使用鹤童素材")
			check(replay._act3_view.swords[0].draw_progress == 1.0, "回放保留白素贞已拔剑")
			check(replay._surface.projection_views[0]._held_prop_hand == "left", "回放白素贞使用换手后的持剑绑定")
			check(
				(
					replay._act3_view.swords[0].geometry().wrist.distance_to(
						replay._surface.projection_views[0].hand_screen_position("left")
					)
					< .001
				),
				"回放剑柄跟随另一只手的实际腕点"
			)
			check(replay._act3_view.swords[2].on_stage.has(2), "回放鹤童持剑随实际手腕")
			saw_crane = true
			break
	check(saw_crane, "录制包含真实鹤童接战")
	replay.stop()
	replay.queue_free()
	await process_frame


func check_sword(host: Node) -> void:
	var white: PuppetState = host.controller.get_puppet(0)
	var facing: float = white.facing
	var lean: float = white.torso_lean
	white.torso_lean = 0.0
	for direction: float in [-1.0, 1.0]:
		white.facing = direction
		var sheath: Dictionary = host._swords[0].sheath_geometry()
		check((sheath.mouth.x - sheath.tail.x) * direction > 0, "鞘口和剑柄朝向身前")
		check(sheath.mouth.y < sheath.tail.y, "鞘尾斜向身后下方")
		var sword: Dictionary = host._swords[0].geometry()
		check(
			sword.wrist.distance_to(host._views[0].hand_screen_position("left")) < .001,
			"翻面前后剑柄均绑定另一只手的实际腕点"
		)
	white.facing = facing
	white.torso_lean = lean
	for id in [1, 2]:
		check(
			(
				host._swords[id].geometry().wrist.distance_to(
					host._views[id].hand_screen_position("right")
				)
				< .001
			),
			"换手仅作用于白素贞，不影响双童 " + str(id)
		)


func check_moves(score: Dictionary) -> void:
	var actors := PuppetController.new()
	actors.setup()
	var white: PuppetState = actors.get_puppet(0)
	white.stage_pos = Vector2(.45, 642.0 / 1080.0)
	var fight := Fight.new()
	fight.setup(score, actors)
	white.hand_angle = Vector2(.4, 1.2)
	white.elbow_angle = Vector2(.2, .5)
	fight._draw_sword(white, int(score.fight.draw_ms) - 1)
	check(white.hand_angle == Vector2(.4, 1.2), "唱词之前不接管持剑手")
	fight._draw_sword(white, int(score.fight.draw_ms) + 300)
	check(white.hand_angle.x != .4 and white.elbow_angle.x != .2, "拔剑动作改用另一只手")
	check(
		is_equal_approx(white.hand_angle.y, 1.2) and is_equal_approx(white.elbow_angle.y, .5),
		"拔剑不改动空手姿势"
	)
	white.hand_angle.x = .7
	white.elbow_angle.x = .3
	fight._draw_sword(white, int(score.fight.draw_ms) + 600)
	check(
		is_equal_approx(white.hand_angle.x, .7) and is_equal_approx(white.elbow_angle.x, .3),
		"拔剑后新持剑手交还玩家"
	)
	for id in [1, 2]:
		var actor: PuppetState = actors.get_puppet(id)
		actor.stage_pos = Vector2(.68, 642.0 / 1080.0)
		actor.facing = -1
		var names: Dictionary = {}
		var peak: float = 0.0
		var spread: float = 0.0
		var tilt: float = 0.0
		var low: float = 10.0
		var high: float = -10.0
		fight._cycle = -1
		for tick in range(610):
			fight._duel(actor, white, tick * 17, .017, true)
			names[fight.move_name] = true
			peak = maxf(peak, actor.air_height * 1080)
			spread = maxf(spread, actor.leg_spread)
			tilt = maxf(tilt, absf(actor.body_angle))
			low = minf(low, actor.hand_angle.y + actor.elbow_angle.y)
			high = maxf(high, actor.hand_angle.y + actor.elbow_angle.y)
		check(names.size() == 3, "双童各有三套不同组合 " + str(id))
		check(peak > 125 and spread > .98, "搭戏包含明显腾空与张腿 " + str(id))
		check(tilt > .6 and high - low > 1.5, "整身与剑路都有高低变化 " + str(id))
		var held: Dictionary = white.to_dict()
		fight._cycle = -1
		fight._duel(actor, white, 400, .017, true)
		var locked: float = fight._attack_facing
		white.stage_pos.x = .95 if locked > 0 else .05
		fight._duel(actor, white, 900, .017, true)
		check(fight._attack_facing == locked, "进剑之后不追踪玩家改变方向 " + str(id))
		white.stage_pos.x = held.stage_pos.x
		check(white.to_dict() == held, "招式演出不接管玩家 " + str(id))
	var on_stage: Array[int] = [0, 1, 2]
	fight.update(.017, int(score.duration_ms), on_stage)
	check(
		actors.get_puppet(2).air_height == 0 and actors.get_puppet(2).body_angle == 0,
		"片尾自动演员回地面，不留悬空"
	)


func check_jump_cut(host: Node) -> void:
	var white: PuppetState = host.controller.get_puppet(0)
	var before: Dictionary = white.to_dict()
	var hands: Vector2 = white.hand_angle
	var elbows: Vector2 = white.elbow_angle
	Helper.key(host, KEY_W)
	Story.advance(host, .14)
	var raised: Vector2 = host._swords[0].geometry().direction
	check(raised.y < -.7, "W 起跳自动提起持剑手")
	Story.advance(host, .17)
	var lowered: Vector2 = host._swords[0].geometry().direction
	check(lowered.y > .4, "腾空下降阶段自动向下劈剑")
	check(lowered.y - raised.y > 1.0, "跳劈剑路具有清楚的向下变化")
	check(white.stage_pos == Vector2(before.stage_pos.x, before.stage_pos.y), "跳劈仍原地锁身")
	check(
		(
			is_equal_approx(white.hand_angle.y, hands.y)
			and is_equal_approx(white.elbow_angle.y, elbows.y)
		),
		"跳劈不改动空手"
	)
	Story.advance(host, .2)
	check(white.air_height == 0 and not host.controller.motion.active(), "跳劈沿用短跳落地时长")
	check(white.hand_angle == hands and white.elbow_angle == elbows, "跳劈落地恢复玩家此前手姿")
	Helper.key(host, KEY_W)
	Story.advance(host, .14)
	check(host._swords[0].geometry().direction.y < -.7, "落地后可再次按 W 跳劈")
	host._release_control()
	Story.advance(host, .02)
	check(white.hand_angle == hands and white.elbow_angle == elbows, "取消短跳也恢复此前持剑手姿")
	Helper.key(host, KEY_SPACE)


func check_crane_space() -> void:
	var actors := PuppetController.new()
	actors.setup()
	var fight := Fight.new()
	fight.controller = actors
	var white: PuppetState = actors.get_puppet(0)
	var crane: PuppetState = actors.get_puppet(2)
	for placement: Vector2 in [
		Vector2(.20, 1), Vector2(.56, 1), Vector2(.80, 1), Vector2(.20, -1), Vector2(.56, -1)
	]:
		var x: float = placement.x
		var side: float = placement.y
		white.stage_pos.x = x
		crane.stage_pos.x = clampf(x + side * 340.0 / 1920, .09, .87)
		fight._cycle = -1
		var minimum: float = INF
		var maximum: float = 0.0
		for tick in range(1030):
			fight._duel(crane, white, roundi(tick * 1000.0 / 60), 1.0 / 60, true)
			var gap: float = (crane.stage_pos.x - x) * side * 1920
			minimum = minf(minimum, gap)
			maximum = maxf(maximum, gap)
		var room: float = (.87 - x if side > 0 else x - .09) * 1920
		check(maximum <= 340.1, "鹤童腾挪保持搭戏范围 " + str(placement))
		check(minimum >= minf(200, room) - .1, "鹤童不穿过玩家或挤近身体 " + str(placement))


func check_contacts(host: Node) -> void:
	var white: PuppetState = host.controller.get_puppet(0)
	var deer: PuppetState = host.controller.get_puppet(1)
	var old_white: Vector2 = white.hand_angle
	var old_elbow: Vector2 = white.elbow_angle
	var old_deer: Vector2 = deer.stage_pos
	white.hand_angle.x = .75
	white.elbow_angle.x = 0.0
	deer.hand_angle.y = 1.0
	deer.elbow_angle.y = 0.0
	deer.stage_pos.x = .95
	host.fight.flash_until_ms = -1
	host._update_contacts()
	check(host.fight.flash_strength(host.clock.get_song_time_ms()) == 0.0, "剑未接触时没有虚构格挡")
	var left: Dictionary = host._swords[0].geometry()
	var right: Dictionary = host._swords[1].geometry()
	var offset: Vector2 = (left.wrist + left.tip - right.wrist - right.tip) * .5
	deer.stage_pos += offset / Vector2(1920, 1080)
	host._update_contacts()
	check(host.fight.flash_strength(host.clock.get_song_time_ms()) > 0.0, "真实剑身相交产生短暂反馈")
	white.hand_angle = old_white
	white.elbow_angle = old_elbow
	deer.stage_pos = old_deer
