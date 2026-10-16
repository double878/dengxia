extends RefCounted
## 仙翁与双童自动搭戏；白素贞的走位、手姿和谢礼由玩家操演。
const GROUND: float = 642.0 / 1080.0
const MOUNTAIN_LEFT: float = (
	CSceneryDef.LEVEL3_MOUNTAIN_X - 747.0 * CSceneryDef.LEVEL3_MOUNTAIN_SCALE / 1920.0
)
const ELDER_X: float = .53
const CRANE_X: float = .63
const DEER_X: float = .73
const FOREGROUND_EDGE: float = .76
var config: Dictionary = {}
var elder := PuppetState.new(3)
var active: bool = false
var phase: String = "waiting"
var elder_behind: bool = false
var deer_behind: bool = false
var herb_owner: int = -1
var gift_progress: float = 0.0


func setup(score: Dictionary) -> void:
	config = score.get("finale", {}).duplicate(true)
	elder.stage_pos = Vector2(.92, GROUND)
	elder.facing = -1
	elder.hand_angle = Vector2(.5, .4)
	elder.elbow_angle = Vector2(.3, .25)


func update(delta: float, song_ms: int, actors: PuppetController, on_stage: Array[int]) -> void:
	if config.is_empty() or song_ms < int(config.start_ms):
		return
	var white: PuppetState = actors.get_puppet(0)
	if not active:
		active = true
	phase = "arrival"
	# 固定山脚前景站位；玩家自行把白素贞移到最左，不追着玩家改变构图。
	_move(elder, ELDER_X, 250, delta)
	elder_behind = elder.stage_pos.x > MOUNTAIN_LEFT
	elder.facing = -1.0 if white.stage_pos.x < elder.stage_pos.x else 1.0
	elder.head_tilt = .04
	if song_ms < int(config.stop_ms):
		return
	phase = "ceasefire"
	var crane: PuppetState = actors.get_puppet(2)
	if not on_stage.has(2):
		on_stage.append(2)
	_settle(crane, CRANE_X, white.stage_pos.x, delta)
	if song_ms >= int(config.gather_ms):
		phase = "gathering"
		var deer: PuppetState = actors.get_puppet(1)
		if not on_stage.has(1):
			deer.stage_pos = Vector2(.93, GROUND)
			on_stage.append(1)
		_settle(deer, DEER_X, white.stage_pos.x, delta)
		deer_behind = deer.stage_pos.x > FOREGROUND_EDGE
	on_stage.sort()
	if song_ms < int(config.gift_ms):
		return
	phase = "advice"
	# 只保留说话和指路手势；兼容记录字段保持无草状态，不再递交道具。
	var age: float = float(song_ms - int(config.gift_ms)) / 1000.0
	var gesture: float = sin(clampf(age / 3.0, 0.0, 1.0) * PI)
	if song_ms >= int(config.advice_ms):
		age = float(song_ms - int(config.advice_ms)) / 1000.0
		gesture = sin(clampf(age / 3.2, 0.0, 1.0) * PI)
	elder.hand_angle.x = .4 - gesture * 1.6
	elder.elbow_angle.x = .35 + gesture * .25
	if song_ms >= int(config.farewell_ms):
		phase = "farewell"
		elder.hand_angle.x = .6
	if song_ms >= int(config.end_ms):
		phase = "finished"


func _settle(actor: PuppetState, x: float, white_x: float, delta: float) -> void:
	_move(actor, x, 320, delta)
	actor.hand_angle = Vector2(.45, .45)
	actor.elbow_angle = Vector2(.35, .4)
	actor.torso_lean = .08
	actor.head_tilt = .12
	actor.stance = .08
	actor.facing = -1 if white_x < actor.stage_pos.x else 1
	actor.turn_progress = 1
	actor.air_height = 0
	actor.leg_spread = 0
	actor.body_angle = 0


func _move(actor: PuppetState, x: float, speed: float, delta: float) -> void:
	var previous: float = actor.stage_pos.x
	actor.stage_pos.x = move_toward(previous, x, speed * delta / 1920.0)
	actor.stage_pos.y = GROUND
	var distance: float = absf(actor.stage_pos.x - previous) * 1920
	actor.walk_amount = minf(distance / maxf(speed * delta, .001), 1.0)
	actor.walk_phase += distance * TAU / 96.0


func recorded_view() -> Dictionary:
	return {
		"active": active,
		"phase": phase,
		"elder_visible": active,
		"elder_behind": elder_behind,
		"deer_behind": deer_behind,
		"elder": elder.to_dict(),
		"herb_owner": herb_owner,
		"gift_progress": gift_progress,
	}
