extends RefCounted
## 白蛇有限分节。宿主写入，实体与透射视图共享并只读；长度固定。

const REST := [
	Vector2(0, -48),
	Vector2(30, -98),
	Vector2(64, -156),
	Vector2(100, -214),
	Vector2(98, -268),
	Vector2(63, -293)
]
var position := Vector2(768, 653.4)
var points: PackedVector2Array = PackedVector2Array(REST)
var facing: float = -1.0
var flip_progress: float = 1.0
var _flip_from: float = -1.0
var _flip_to: float = -1.0


func setup(at: Vector2) -> void:
	if not at.is_finite():
		push_error("白蛇初始位置非法")
		return
	position = at
	reset()


func reset() -> void:
	points = PackedVector2Array(REST)
	flip_progress = 1.0
	_flip_from = facing
	_flip_to = facing


func flip_width() -> float:
	return lerpf(_flip_from, _flip_to, flip_progress)


func head_position() -> Vector2:
	var head: Vector2 = points[points.size() - 1]
	return position + Vector2(head.x * flip_width(), head.y)


func body_position() -> Vector2:
	return position + Vector2(0, -65)


func head_angle() -> float:
	return wrapf((points[5] - points[4]).angle() - (REST[5] - REST[4]).angle(), -PI, PI)


func tick(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	flip_progress = minf(1.0, flip_progress + delta / 0.1)
	if flip_progress >= 1.0:
		facing = _flip_to


func move(delta: Vector2) -> bool:
	if not delta.is_finite():
		return false
	position += delta
	position.x = clampf(position.x, 245.0, 1660.0)
	position.y = clampf(position.y, 600.0, 653.4)
	if absf(delta.x) > 2.0:
		var target: float = -signf(delta.x)
		if target != _flip_to:
			_flip_from = flip_width()
			_flip_to = target
			flip_progress = 0.0
	return true


func drag_head(target: Vector2) -> bool:
	if not target.is_finite() or absf(flip_width()) < 0.12:
		return false
	var local: Vector2 = target - position
	local.x /= flip_width()
	var total: float = 0.0
	var lengths: Array[float] = []
	for i in range(REST.size() - 1):
		var length: float = REST[i].distance_to(REST[i + 1])
		lengths.append(length)
		total += length
	var reach: Vector2 = local - REST[0]
	if reach.length() > total:
		local = REST[0] + reach.normalized() * total
	var next: PackedVector2Array = points.duplicate()
	# 有界 forward/backward 解算；每节围绕原方向最多弯 55°，避免反折和零长。
	for _iteration in range(8):
		next[next.size() - 1] = local
		for i in range(next.size() - 2, -1, -1):
			var direction: Vector2 = next[i] - next[i + 1]
			if direction.length_squared() < 0.0001:
				direction = REST[i] - REST[i + 1]
			next[i] = next[i + 1] + direction.normalized() * lengths[i]
		next[0] = REST[0]
		for i in range(next.size() - 1):
			var original: float = (REST[i + 1] - REST[i]).angle()
			var direction: Vector2 = next[i + 1] - next[i]
			var angle: float = (
				direction.angle() if direction.length_squared() > 0.0001 else original
			)
			angle = original + clampf(wrapf(angle - original, -PI, PI), -0.96, 0.96)
			next[i + 1] = next[i] + Vector2.from_angle(angle) * lengths[i]
	for point: Vector2 in next:
		if not point.is_finite():
			return false
	points = next
	return true
