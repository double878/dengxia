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


## 沿用旧判定的归一化高度原点；实际弯肘、前倾和站蹲进入同一几何。
static func hand_height(state: PuppetState, hand: String) -> float:
	var right: bool = hand != "left"
	var height: float = 1.0 - 0.32 * state.stance
	var angle: float = state.hand_angle.y if right else state.hand_angle.x
	var bend: float = state.elbow_angle.y if right else state.elbow_angle.x
	var shoulder := Vector2(0.0, -height * SHOULDER_RATIO)
	var wrist: Vector2 = arm_points(shoulder, angle, bend, right, height).wrist
	var hip := Vector2(0.0, -height * HIP_RATIO)
	wrist = torso_transform(hip, state.torso_lean) * wrist
	return 1.0 - 0.12 * state.stance - height * SHOULDER_RATIO - wrist.y
