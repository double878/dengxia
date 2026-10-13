extends RefCounted
class_name UpperBodyPose
## 固定两段的平面皮影关节；显示、命中和道具判定共用。

const UPPER_ARM_RATIO: float = 0.16
const LOWER_ARM_RATIO: float = 0.15
const SHOULDER_RATIO: float = 0.80
const HIP_RATIO: float = 0.44
const HEAD_CENTRE_RATIO: float = 0.115
const ELBOW_MAX: float = PI * 5.0 / 6.0
const HEAD_LIMIT: float = PI / 6.0
const LEAN_MAX: float = PI / 4.0
const SKIN_MANIFEST := preload("res://assets/puppets/puppet_assets.json")


static func direction(angle: float, right_side: bool) -> Vector2:
	return Vector2.DOWN.rotated(-angle if right_side else angle)


static func arm_points(
	shoulder: Vector2, angle: float, bend: float, right_side: bool, height: float
) -> Dictionary:
	var elbow: Vector2 = shoulder + direction(angle, right_side) * height * UPPER_ARM_RATIO
	var forearm: Vector2 = direction(angle + bend, right_side)
	return {
		"shoulder": shoulder,
		"elbow": elbow,
		"wrist": elbow + forearm * height * LOWER_ARM_RATIO,
		"direction": forearm,
	}


static func solve_arm(offset: Vector2, right_side: bool, height: float) -> Vector2:
	if not offset.is_finite() or not is_finite(height) or height <= 0.0:
		push_error("UpperBodyPose：非法手目标 %s / 身高 %s" % [offset, height])
		return Vector2.ZERO
	var upper: float = height * UPPER_ARM_RATIO
	var lower: float = height * LOWER_ARM_RATIO
	var minimum: float = sqrt(upper * upper + lower * lower + 2.0 * upper * lower * cos(ELBOW_MAX))
	var radius: float = clampf(offset.length(), minimum, upper + lower)
	var target: Vector2 = (
		offset.normalized() if offset.length_squared() > 0.000001 else Vector2.DOWN
	)
	target.x *= 1.0 if right_side else -1.0
	var bend: float = acos(
		clampf((radius * radius - upper * upper - lower * lower) / (2.0 * upper * lower), -1.0, 1.0)
	)
	var correction: float = acos(
		clampf(
			(upper * upper + radius * radius - lower * lower) / (2.0 * upper * radius), -1.0, 1.0
		)
	)
	var angle: float = wrapf(PI * 0.5 - target.angle() - correction, -PI * 0.5, PI * 1.5)
	if angle > PI * 1.25:
		angle = -PI * 0.5
	return Vector2(clampf(angle, -PI * 0.5, PI), clampf(bend, 0.0, ELBOW_MAX))


static func torso_transform(hip: Vector2, lean: float) -> Transform2D:
	var rotation := Transform2D(lean, Vector2.ZERO)
	rotation.origin = hip - rotation * hip
	return rotation


## 接地点上方腕高 / 站立身高；与显示端相同的身体宽度、朝向和步态。
static func hand_height(state: PuppetState, hand: String) -> float:
	return -hand_offset(state, hand).y


static func hand_offset(state: PuppetState, hand: String) -> Vector2:
	var right: bool = hand != "left"
	var height: float = 1.0 - 0.32 * state.stance
	var angle: float = state.hand_angle.y if right else state.hand_angle.x
	var bend: float = state.elbow_angle.y if right else state.elbow_angle.x
	var skin: Dictionary = {}
	for candidate: Dictionary in SKIN_MANIFEST.data.characters.values():
		if int(candidate.get("skin_id", candidate.get("puppet_id", -1))) == state.puppet_id:
			skin = candidate
			break
	var reference: float = float(skin.get("reference_facing", 1.0))
	var width: float = float(skin.get("shoulder_half_width_ratio", 0.105)) * height
	var bob: float = -absf(sin(state.walk_phase)) * height * 0.008 * state.walk_amount
	var shoulder := Vector2(width if right else -width, -height * SHOULDER_RATIO + bob)
	var wrist: Vector2 = arm_points(shoulder, angle, bend, right, height).wrist
	var hip := Vector2(0.0, -height * HIP_RATIO + bob)
	return torso_transform(hip, state.torso_lean * reference) * wrist


## 保留原 Cue 的角度单位；有弯肘/前倾时以实际腕高换算等效抬手角。
static func hand_elevation(state: PuppetState, hand: String) -> float:
	var right: bool = hand != "left"
	var angle: float = state.hand_angle.y if right else state.hand_angle.x
	var bend: float = state.elbow_angle.y if right else state.elbow_angle.x
	if is_zero_approx(bend) and is_zero_approx(state.torso_lean):
		return angle
	var height: float = 1.0 - 0.32 * state.stance
	var bob: float = -absf(sin(state.walk_phase)) * height * 0.008 * state.walk_amount
	var drop: float = hand_offset(state, hand).y + height * SHOULDER_RATIO - bob
	return acos(clampf(drop / (height * (UPPER_ARM_RATIO + LOWER_ARM_RATIO)), -1.0, 1.0))
