extends RefCounted
## 单次、短促的人形身段。地面位置与腾空高度分开，桥面和回放共用。
const JUMP_S: float = .46
const DODGE_S: float = .42
var kind: String = ""
var elapsed: float = 0.0
var puppet_id: int = -1
var _origin_x: float = 0.0
var _stance: float = 0.0
var _lean: float = 0.0
var _facing: float = 1.0
var _jump_px: float = 115.0


func active() -> bool:
	return not kind.is_empty()


func start(state: PuppetState, action: String, jump_px: float = 115.0) -> bool:
	if active() or state == null or state.hook_slot != -1 or action not in ["jump", "dodge"]:
		return false
	kind = action
	elapsed = 0.0
	puppet_id = state.puppet_id
	_origin_x = state.stage_pos.x
	_stance = state.stance
	_lean = state.torso_lean
	_facing = state.facing
	_jump_px = clampf(jump_px, 0.0, 115.0)
	state.turn_progress = 1.0
	return true


func tick(state: PuppetState, delta: float, path: RefCounted) -> void:
	if not active():
		return
	elapsed += maxf(delta, 0.0)
	state.facing = _facing
	state.turn_progress = 1.0
	if kind == "jump":
		# 50ms 蓄势、320ms 腾空、90ms 收势；一次按下只跳一次。
		var air: float = clampf((elapsed - .05) / .32, 0.0, 1.0)
		var arc: float = maxf(sin(PI * air), 0.0)
		state.air_height = _jump_px / 1080.0 * 4.0 * air * (1.0 - air)
		state.leg_spread = arc ** .55
		var compress: float = (
			sin(PI * elapsed / .05) * .22
			if elapsed < .05
			else (sin(PI * (elapsed - .37) / .09) * .28 if elapsed > .37 else 0.0)
		)
		state.stance = clampf(_stance * (1.0 - arc) + compress, 0.0, 1.0)
		if elapsed >= JUMP_S:
			cancel(state)
	else:
		var t: float = clampf(elapsed / DODGE_S, 0.0, 1.0)
		var duck: float = sin(PI * t)
		state.stage_pos.x = clampf(_origin_x - _facing * 92.0 / 1920.0 * smoothstep(0, 1, t), 0, 1)
		if path != null:
			state.stage_pos.y = path.height_at(state.stage_pos.x)
		state.stance = lerpf(_stance, maxf(_stance, .82), duck)
		state.torso_lean = lerpf(_lean, maxf(_lean, .38), duck)
		if elapsed >= DODGE_S:
			cancel(state)


func cancel(state: PuppetState) -> void:
	if not active():
		return
	if state != null:
		state.air_height = 0.0
		state.leg_spread = 0.0
		state.stance = _stance
		state.torso_lean = _lean
	kind = ""
	puppet_id = -1
