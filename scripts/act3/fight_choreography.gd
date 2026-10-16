extends RefCounted
## 一条原声上的搭戏；白素贞在自动出鞘及玩家触发跳劈时短暂使用持剑手。
const Moves := preload("res://scripts/act3/fight_moves.gd")
const GROUND: float = 642.0 / 1080.0
const WIDTH: float = 1920.0
const ENTRANCE_S: float = 1.1
const CRANE_STAND_PX: float = 280.0
const CRANE_NEAR_PX: float = 200.0
const CRANE_FAR_PX: float = 340.0
var config: Dictionary = {}
var controller: PuppetController
var active: bool = false
var active_actor: int = -1
var phase: String = "waiting"
var move_name: String = ""
var draw_progress: float = 0.0
var crane_behind_mountain: bool = false
var flash_point := Vector2.ZERO
var flash_until_ms: int = -1
var _cycle: int = -1
var _attack_origin: float = 0.0
var _attack_target: float = 0.0
var _attack_facing: float = -1.0
var _exchange_x: float = 0.0
var _last_contact_ms: int = -1000
var _draw_start := Vector2.ZERO
var _draw_started: bool = false
var _jump_cut: bool = false
var _jump_hand := Vector2.ZERO
var _has_finale: bool = false


func setup(score: Dictionary, actors: PuppetController) -> void:
	config = score.get("fight", {}).duplicate(true)
	if not config.is_empty():
		_has_finale = not score.get("finale", {}).is_empty()
		config.end_ms = int(score.finale.stop_ms) if _has_finale else int(score.duration_ms)
	controller = actors


func update(delta: float, song_ms: int, on_stage: Array[int]) -> void:
	if config.is_empty() or song_ms < int(config.start_ms):
		return
	active = true
	var white: PuppetState = controller.get_puppet(0)
	_draw_sword(white, song_ms)
	_jump_sword(white)
	if song_ms >= int(config.end_ms):
		phase = "stopped" if _has_finale else "awaiting_material"
		if _has_finale:
			draw_progress = 1.0 - clampf(float(song_ms - int(config.end_ms)) / 650.0, 0.0, 1.0)
		active_actor = -1
		flash_until_ms = -1
		for id in [1, 2]:
			_ground(controller.get_puppet(id))
		return
	if song_ms >= int(config.crane_ms):
		on_stage.erase(1)
		var crane: PuppetState = controller.get_puppet(2)
		if phase not in ["crane_entrance", "crane_duel", "awaiting_material"]:
			crane.stage_pos = Vector2(.87, GROUND)
			crane.facing = -1.0
			crane.turn_progress = 1.0
			_cycle = -1
		if not on_stage.has(2):
			on_stage.append(2)
		active_actor = 2
		if song_ms < int(config.duel_ms):
			phase = "crane_entrance"
			var age: float = float(song_ms - int(config.crane_ms)) / 1000.0
			crane_behind_mountain = age < ENTRANCE_S
			var t: float = clampf(age / ENTRANCE_S, 0.0, 1.0)
			_ground(crane)
			_move(crane, _stand_x(white, crane), 235.0, delta)
			crane.stage_pos.y = GROUND - sin(t * PI) * 85.0 / 1080.0
			_face(crane, white.stage_pos.x - crane.stage_pos.x, delta)
			_pose(crane, 1.0, 1.1, .12)
		else:
			crane_behind_mountain = false
			phase = "crane_duel"
			_duel(crane, white, song_ms - int(config.duel_ms), delta, on_stage.has(0))
	elif song_ms >= int(config.retreat_ms):
		phase = "deer_retreat"
		active_actor = -1
		var deer: PuppetState = controller.get_puppet(1)
		_ground(deer)
		_face(deer, 1.0, delta)
		_move(deer, .92, 370.0, delta)
		_pose(deer, .25, .6, .3)
		if song_ms - int(config.retreat_ms) > 1700:
			on_stage.erase(1)
	elif song_ms >= int(config.defeat_ms):
		phase = "deer_recoil"
		active_actor = -1
		var deer: PuppetState = controller.get_puppet(1)
		_ground(deer)
		var away: float = signf(deer.stage_pos.x - white.stage_pos.x)
		_move(deer, clampf(white.stage_pos.x + away * .23, .09, .87), 140.0, delta)
		_pose(deer, .7, .5, .35)
	else:
		phase = "deer_duel"
		active_actor = 1
		if not on_stage.has(1):
			on_stage.append(1)
		_duel(
			controller.get_puppet(1), white, song_ms - int(config.start_ms), delta, on_stage.has(0)
		)
	on_stage.sort()


func _draw_sword(white: PuppetState, song_ms: int) -> void:
	var t: float = clampf(float(song_ms - int(config.draw_ms)) / 550.0, 0.0, 1.0)
	draw_progress = smoothstep(.18, 1.0, t)
	if song_ms < int(config.draw_ms) or t >= 1.0 or controller.motion.active():
		return
	if not _draw_started:
		_draw_started = true
		_draw_start = Vector2(white.hand_angle.x, white.elbow_angle.x)
	# 按用户截图换到另一只手；仅在出鞘的半秒里探向鞘口，再提剑至身前。
	var grip := Vector2(-.60, 1.30)
	var guard := Vector2(2.10, .30)
	var pose: Vector2 = (
		_draw_start.lerp(grip, smoothstep(0, .18, t))
		if t < .18
		else grip.lerp(guard, smoothstep(.18, 1.0, t))
	)
	white.hand_angle.x = pose.x
	white.elbow_angle.x = pose.y


func begin_jump_cut() -> void:
	if (
		_jump_cut
		or draw_progress < .99
		or controller.controlled_id != 0
		or controller.motion.kind != "jump"
		or not controller.motion.active()
	):
		return
	var white: PuppetState = controller.get_puppet(0)
	_jump_hand = Vector2(white.hand_angle.x, white.elbow_angle.x)
	_jump_cut = true


func _jump_sword(white: PuppetState) -> void:
	if not _jump_cut:
		return
	var pose: Vector2 = _jump_hand
	if (
		controller.motion.active()
		and controller.motion.puppet_id == 0
		and controller.motion.kind == "jump"
	):
		var age: float = controller.motion.elapsed
		var raised := Vector2(2.55, .25)
		var lowered := Vector2(.55, .10)
		if age < .14:
			pose = _jump_hand.lerp(raised, smoothstep(0, .14, age))
		elif age < .32:
			pose = raised.lerp(lowered, smoothstep(.14, .30, age))
		else:
			pose = lowered.lerp(_jump_hand, smoothstep(.32, .46, age))
	else:
		_jump_cut = false
	white.hand_angle.x = pose.x
	white.elbow_angle.x = pose.y


func _stand_x(white: PuppetState, actor: PuppetState) -> float:
	var side: float = 1.0 if actor.stage_pos.x >= white.stage_pos.x else -1.0
	if actor.puppet_id == 2:
		# 鹤童沿当前侧搭戏；靠边也不穿过玩家去强制换边。
		return clampf(white.stage_pos.x + side * CRANE_STAND_PX / WIDTH, .09, .87)
	if white.stage_pos.x > .73:
		side = -1.0
	elif white.stage_pos.x < .27:
		side = 1.0
	return clampf(white.stage_pos.x + side * 340.0 / WIDTH, .09, .87)


func _duel(
	actor: PuppetState, white: PuppetState, elapsed_ms: int, delta: float, present: bool
) -> void:
	_ground(actor)
	if not present:
		_pose(actor, .9, 1.1, .0)
		return
	var selected: Dictionary = Moves.at_time(actor.puppet_id, float(elapsed_ms) / 1000.0)
	var move: Dictionary = selected.move
	var t: float = selected.progress
	move_name = move.name
	if int(selected.cycle) != _cycle:
		_cycle = int(selected.cycle)
		_attack_origin = actor.stage_pos.x
		_attack_target = actor.stage_pos.x
	var pose: Dictionary = Moves.sample(move, t)
	# 每招前约半秒亮相、找距离；出招后锁定整套步幅，玩家可真实跳开或后撤。
	if t < .20:
		_move(actor, _stand_x(white, actor), 240.0, delta)
		_face(actor, white.stage_pos.x - actor.stage_pos.x, delta)
		_attack_origin = actor.stage_pos.x
		_attack_facing = -1.0 if white.stage_pos.x < actor.stage_pos.x else 1.0
		_exchange_x = white.stage_pos.x
	else:
		_attack_target = clampf(
			_attack_origin + _attack_facing * float(move.reach) * float(pose.travel) / WIDTH,
			.09,
			.87
		)
		if actor.puppet_id == 2:
			# 只读蓄势时的玩家位置，限制腾挪/冲刺距离，出招后不追踪玩家。
			var near_x: float = _exchange_x - _attack_facing * CRANE_NEAR_PX / WIDTH
			var far_x: float = _exchange_x - _attack_facing * CRANE_FAR_PX / WIDTH
			_attack_target = clampf(
				clampf(_attack_target, minf(near_x, far_x), maxf(near_x, far_x)), .09, .87
			)
		_move(actor, _attack_target, 900.0, delta)
		var turning: bool = (
			(actor.puppet_id == 1 and int(selected.index) == 2 and t > .56 and t < .72)
			or (actor.puppet_id == 2 and int(selected.index) == 1 and t > .38 and t < .56)
		)
		_face(actor, -_attack_facing if turning else _attack_facing, delta)
	_pose(actor, pose.shoulder, pose.elbow, pose.crouch)
	actor.hand_angle.x = pose.free_arm
	actor.elbow_angle.x = .3 + .35 * float(pose.spread)
	actor.torso_lean = .08 + .2 * float(pose.crouch)
	actor.head_tilt = -.08 + .13 * float(pose.tilt)
	actor.air_height = float(move.height) * float(pose.air) / 1080.0
	actor.leg_spread = pose.spread
	actor.body_angle = _attack_facing * float(pose.tilt)
	if actor.air_height > .001:
		actor.walk_amount = 0.0
	actor.clamp_continuous()


func _ground(actor: PuppetState) -> void:
	actor.stage_pos.y = GROUND
	actor.air_height = 0.0
	actor.leg_spread = 0.0
	actor.body_angle = 0.0


func _move(actor: PuppetState, x: float, pixels_per_s: float, delta: float) -> void:
	var old_x: float = actor.stage_pos.x
	actor.stage_pos.x = move_toward(old_x, x, pixels_per_s / WIDTH * delta)
	var moved: float = absf(actor.stage_pos.x - old_x) * WIDTH
	actor.walk_amount = minf(moved / maxf(pixels_per_s * delta, .001), 1.0)
	actor.walk_phase += moved * TAU / 96.0


func _face(actor: PuppetState, dx: float, delta: float) -> void:
	var direction: float = -1.0 if dx < 0.0 else 1.0
	if actor.facing != direction and actor.turn_progress >= .99:
		actor.turn_progress = 0.0
	actor.turn_progress = minf(actor.turn_progress + delta * 10.0, 1.0)
	if actor.turn_progress >= .5:
		actor.facing = direction


func _pose(actor: PuppetState, shoulder: float, elbow: float, crouch: float) -> void:
	actor.hand_angle = Vector2(.65, shoulder)
	actor.elbow_angle = Vector2(.5, elbow)
	actor.stance = crouch
	actor.torso_lean = .12
	actor.head_tilt = -.04


func sword_progress() -> Array[float]:
	var guard_progress: float = 0.0 if phase == "stopped" else 1.0
	return [draw_progress, guard_progress, guard_progress]


func contact(point: Vector2, song_ms: int) -> void:
	if song_ms - _last_contact_ms < 300:
		return
	_last_contact_ms = song_ms
	flash_point = point
	flash_until_ms = song_ms + 140


func flash_strength(song_ms: int) -> float:
	return clampf(float(flash_until_ms - song_ms) / 140.0, 0.0, 1.0)
