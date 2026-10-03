extends Node2D
class_name PlaceholderPuppet
## 占位影人：只用简单几何图形表现 PuppetState，不依赖 B 的美术。
## 它同时充当「模拟 B 的显示端」：只读 PuppetState，从不写。

const PuppetStateScript := preload("res://scripts/a/puppet_state.gd")
const PuppetControllerScript := preload("res://scripts/a/puppet_controller.gd")

## 由测试场景注入的舞台渲染区域，与 STAGE_PIXEL_SIZE 保持同一坐标系
@export var stage_origin: Vector2 = Vector2(0.0, 120.0)
@export var stage_size: Vector2 = Vector2(1920.0, 800.0)

const HEAD_RADIUS: float = 34.0
const TORSO_WIDTH: float = 78.0
const TORSO_HEIGHT: float = 132.0
const ARM_LENGTH: float = 116.0
const ARM_WIDTH: float = 16.0
const CHEST_TAG_RADIUS: float = 34.0

var puppet_state: PuppetState = null


## 归一化舞台坐标（0-1）→ 屏幕像素。y=0 在舞台最深处（画面上方），y=1 最靠幕布（画面下方）。
func stage_to_screen(normalized: Vector2) -> Vector2:
	return Vector2(
		stage_origin.x + normalized.x * stage_size.x,
		stage_origin.y + normalized.y * stage_size.y)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if puppet_state == null:
		return
	var ground: Vector2 = stage_to_screen(puppet_state.stage_pos)

	# 接地点标记：确认影人「站在」哪个归一化位置
	draw_line(ground - Vector2(46.0, 0.0), ground + Vector2(46.0, 0.0),
		Color(0.25, 0.25, 0.30, 0.9), 3.0)

	# 站蹲：躯干顶部离地高度随 stance 下降；同时身体略微下沉
	var top_y: float = ground.y - TORSO_HEIGHT * (1.0 - 0.45 * puppet_state.stance)
	var half_w: float = TORSO_WIDTH * 0.5

	# 转身：facing 用横向挤压与朝向楔形表现，便于肉眼确认「渐进」而非瞬间翻面
	var squeeze: float = 1.0 - 0.55 * puppet_state.turn_progress
	var drawn_half_w: float = maxf(half_w * squeeze, 4.0)
	var facing_sign: float = signf(puppet_state.facing)

	var body_color := Color(0.62, 0.34, 0.28).lerp(Color(0.30, 0.45, 0.40),
		(puppet_state.facing + 1.0) * 0.5)
	var torso := PackedVector2Array([
		Vector2(ground.x - drawn_half_w, top_y),
		Vector2(ground.x + drawn_half_w, top_y),
		Vector2(ground.x + drawn_half_w * 0.78, ground.y),
		Vector2(ground.x - drawn_half_w * 0.78, ground.y),
	])
	draw_colored_polygon(torso, body_color)
	draw_polyline(torso + PackedVector2Array([torso[0]]), Color(0.12, 0.09, 0.07), 3.0)

	# 双肩枢轴与两条手臂：角度直接来自 hand_angle
	var shoulder_y: float = top_y + 22.0
	var left_shoulder := Vector2(ground.x - drawn_half_w, shoulder_y)
	var right_shoulder := Vector2(ground.x + drawn_half_w, shoulder_y)
	_draw_arm(left_shoulder, puppet_state.hand_angle.x, false, Color(0.85, 0.72, 0.35))
	_draw_arm(right_shoulder, puppet_state.hand_angle.y, true, Color(0.85, 0.72, 0.35))

	# 头：位置随转身左右偏移，形成「翻脸」方向的直接可见证据
	var head_center := Vector2(
		ground.x + facing_sign * 22.0 * puppet_state.turn_progress,
		top_y - HEAD_RADIUS * 0.6)
	draw_circle(head_center, HEAD_RADIUS, Color(0.94, 0.88, 0.74))
	draw_arc(head_center, HEAD_RADIUS, 0.0, TAU, 40, Color(0.15, 0.12, 0.10))

	# 鼻尖楔形指出朝向
	if absf(puppet_state.facing) > 0.05:
		var nose := PackedVector2Array([
			head_center + Vector2(facing_sign * HEAD_RADIUS * 0.9, -6.0),
			head_center + Vector2(facing_sign * HEAD_RADIUS * 1.6 * puppet_state.turn_progress, 14.0),
			head_center + Vector2(facing_sign * HEAD_RADIUS * 0.9, 14.0),
		])
		draw_colored_polygon(nose, Color(0.15, 0.12, 0.10))

	# 胸签：与 PuppetController.begin_drag 的命中热区使用同一位置公式，
	# 保证「看到的圆圈」就是「能拖到的热区」。
	var tag_center := Vector2(ground.x,
		ground.y - PuppetControllerScript.CHEST_TAG_RADIUS_PX * 0.5)
	draw_circle(tag_center, PuppetControllerScript.CHEST_TAG_RADIUS_PX,
		Color(0.85, 0.25, 0.55, 0.35))
	draw_arc(tag_center, PuppetControllerScript.CHEST_TAG_RADIUS_PX,
		0.0, TAU, 40, Color(0.95, 0.45, 0.75), 3.0)
	draw_circle(tag_center, 6.0, Color(0.98, 0.75, 0.88))

	# 受控高亮与挂起标记
	if puppet_state.is_controlled:
		draw_arc(ground, 54.0, PI, TAU, 24, Color(0.40, 0.95, 0.65), 4.0)
	if puppet_state.hook_slot != PuppetStateScript.HOOK_SLOT_NONE:
		draw_string(ThemeDB.fallback_font, ground + Vector2(-40.0, -8.0),
			"HOOK %d" % puppet_state.hook_slot, HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
			Color(0.95, 0.85, 0.45))


func _draw_arm(shoulder: Vector2, angle: float, right_side: bool, color: Color) -> void:
	# 技术中性位：手臂斜向外下方；正角度为抬起方向
	var base_angle: float = (PI * 0.62) if right_side else (PI - PI * 0.62)
	var dir := Vector2(cos(base_angle), sin(base_angle))
	dir = dir.rotated(-angle * (1.0 if right_side else -1.0))
	var tip: Vector2 = shoulder + dir * ARM_LENGTH
	draw_line(shoulder, tip, Color(0.12, 0.09, 0.07), ARM_WIDTH + 6.0)
	draw_line(shoulder, tip, color, ARM_WIDTH)
	draw_circle(tip, ARM_WIDTH * 0.85, Color(0.98, 0.92, 0.80))
