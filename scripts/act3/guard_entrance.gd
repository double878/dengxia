extends RefCounted
## 靠山后等前奏末尾重音出山；写真实位置与关节，由现有录放原样记录。
const MOUNTAIN := preload("res://assets/scenery/level3/mountain.png")
const CANVAS := Vector2(1920, 1080)
const GROUND_Y: float = 642.0
const FLIGHT_S: float = .72
const LAND_S: float = .22
const JUMP_HEIGHT: float = 100.0
const RIGHT_EDGE: float = 1804.8  # 画布的 .94，给最右侧玩家留出落脚空间。
const SAFE_GAP: float = 160.0

var triggered: bool = false
var active: bool = false
var behind_mountain: bool = false
var mask: Texture2D
var _elapsed: float = 0.0
var _start_x: float = 0.0
var _land_x: float = 0.0
var _edge_x: float = 0.0


func setup(cloth: Rect2) -> void:
	var scale_px: float = CSceneryDef.LEVEL3_MOUNTAIN_SCALE
	var origin := Vector2(
		CSceneryDef.LEVEL3_MOUNTAIN_X * CANVAS.x - 747.0 * scale_px,
		CSceneryDef.LEVEL3_GROUND_Y * CANVAS.y - 1754.0 * scale_px
	)
	_edge_x = origin.x
	var source: Image = MOUNTAIN.get_image()
	if source.is_compressed():
		var error: Error = source.decompress()
		assert(error == OK, "第三关山景遮罩解压失败")
	source.resize(roundi(1494 * scale_px), roundi(1754 * scale_px))
	var image := Image.create(1920, 1080, false, Image.FORMAT_R8)
	image.fill(Color.BLACK)
	for y in range(source.get_height()):
		var left: int = 0
		var right: int = source.get_width() - 1
		while left <= right and source.get_pixel(left, y).a < .08:
			left += 1
		while right >= left and source.get_pixel(right, y).a < .08:
			right -= 1
		if left > right:
			continue
		var row: int = roundi(origin.y) + y
		var from_x: int = maxi(roundi(origin.x) + left, int(cloth.position.x))
		var to_x: int = mini(roundi(origin.x) + right + 1, int(cloth.end.x))
		if row >= int(cloth.position.y) and row < int(cloth.end.y) and to_x > from_x:
			image.fill_rect(Rect2i(from_x, row, to_x - from_x, 1), Color.WHITE)
	mask = ImageTexture.create_from_image(image)


func update(
	delta: float, controller: PuppetController, on_stage: Array[int], song_ms: int, cue_ms: int
) -> void:
	var white: PuppetState = controller.get_puppet(0)
	var guard: PuppetState = controller.get_puppet(1)
	if not triggered:
		if (
			song_ms < cue_ms
			or not on_stage.has(0)
			or white.stage_pos.x * CANVAS.x < _edge_x - 280.0
			or absf(white.stage_pos.y * CANVAS.y - GROUND_Y) > 25.0
			or white.facing < 0
			or white.turn_progress < .99
		):
			return
		triggered = true
		active = true
		behind_mountain = true
		_start_x = CSceneryDef.LEVEL3_MOUNTAIN_X * CANVAS.x - 25.0
		# 留在白素贞右边；贴近山脚时缩短跳距，不越过玩家。
		var white_x: float = white.stage_pos.x * CANVAS.x
		_land_x = clampf(maxf(_edge_x - 110.0, white_x + SAFE_GAP), white_x, RIGHT_EDGE)
		_start_x = minf(maxf(_start_x, _land_x + 40.0), RIGHT_EDGE)
		guard.facing = -1.0
		guard.turn_progress = 1.0
		on_stage.append(1)
		on_stage.sort()
	if not active:
		return
	# 起跳后玩家继续右移时，只收短鹿童的路径，不写玩家位置。
	var right_min: float = minf(white.stage_pos.x * CANVAS.x + SAFE_GAP, RIGHT_EDGE)
	_land_x = maxf(_land_x, right_min)
	_elapsed += maxf(delta, 0.0)
	var x: float = _start_x
	var y: float = GROUND_Y
	if _elapsed < FLIGHT_S:
		var t: float = _elapsed / FLIGHT_S
		x = lerpf(_start_x, _land_x, t)
		y -= 4.0 * JUMP_HEIGHT * t * (1.0 - t)
		guard.stance = .12
	else:
		x = _land_x
		var t: float = clampf((_elapsed - FLIGHT_S) / LAND_S, 0.0, 1.0)
		guard.stance = .25 * (1.0 - t)
		behind_mountain = false
		if t >= 1.0:
			active = false
	guard.stage_pos = Vector2(maxf(x, right_min), y) / CANVAS
	guard.hand_angle = Vector2(.9, 1.05)
	guard.elbow_angle = Vector2(.55, 1.15)
	guard.torso_lean = 0.0
	guard.walk_amount = 0.0


func apply_mask(
	views: Array[PlaceholderPuppet], sword: Node2D, behind: bool, actor_id: int = 1
) -> void:
	var texture: Texture2D = mask if behind else null
	views[actor_id].entrance_mask = texture
	if sword.material is ShaderMaterial:
		sword.material.set_shader_parameter("entrance_active", behind)
		sword.material.set_shader_parameter("entrance_mask", texture)
