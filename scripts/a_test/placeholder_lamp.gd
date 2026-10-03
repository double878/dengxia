extends Node2D
class_name PlaceholderLamp
## 占位油灯：只用 Godot 内置绘制表现 LampState，不依赖 B 的任何美术素材。
## 它同时充当「模拟 B 的显示端」：只读 LampState，从不写。
##
## 可见要素对应 PRD 第 4.3 节的三件事：
## - 灯距 distance：灯与影人（画面中心）的远近，直接影响光锥宽度
## - 显露度 exposure：灯锥投射到幕布上的亮度
## - 灯油 oil：灯体本身的明暗（环境亮度下限仍可辨认）
## - flame_feedback：火苗的稳定程度与抖动

const LampStateScript := preload("res://scripts/a/lamp_state.gd")

## 灯位摆放区域（屏幕像素）。
@export var anchor: Vector2 = Vector2(1620.0, 880.0)
@export var travel_px: float = 420.0          ## distance 0→1 对应灯移动的距离

const FLAME_RADIUS: float = 16.0
const BODY_RADIUS: float = 42.0

var lamp: LampState = null


func _process(_delta: float) -> void:
	queue_redraw()


func lamp_position() -> Vector2:
	if lamp == null:
		return anchor
	# distance 越大表示灯越靠近影人（画面中心方向）
	return anchor - Vector2(travel_px, travel_px * 0.35) * clampf(lamp.distance, 0.0, 1.0)


func _draw() -> void:
	if lamp == null:
		return
	var centre: Vector2 = lamp_position()
	var oil: float = clampf(lamp.oil, 0.0, 1.0)
	var exposure: float = clampf(lamp.exposure, 0.0, 1.0)
	var feedback: float = clampf(lamp.flame_feedback, 0.0, 1.0)

	# 灯油决定灯体亮度；最低仍保留可辨认的亮度下限（PRD 第 8 节）
	var body_bright: float = 0.25 + 0.75 * oil
	var body_color := Color(0.55 * body_bright, 0.36 * body_bright, 0.16 * body_bright)

	# 光锥：宽度由灯距决定，亮度由显露度决定
	var cone_alpha: float = 0.06 + 0.24 * exposure
	var spread: float = 520.0 - 260.0 * clampf(lamp.distance, 0.0, 1.0)
	var target: Vector2 = Vector2(centre.x - travel_px - 200.0, centre.y - 260.0)
	var cone := PackedVector2Array([
		centre,
		target + Vector2(-spread * 0.5, spread),
		target + Vector2(spread * 0.5, spread),
	])
	draw_colored_polygon(cone, Color(1.0, 0.82, 0.45, cone_alpha))

	# 灯体
	draw_circle(centre, BODY_RADIUS, body_color)
	draw_arc(centre, BODY_RADIUS, 0.0, TAU, 40, Color(0.18, 0.12, 0.07), 3.0)

	# 火苗：位置随 feedback 抖动，高度随 feedback 变化 —— 这就是「火苗稳定程度」
	var jitter: float = (1.0 - feedback) * sin(float(Time.get_ticks_msec()) * 0.045) * 14.0
	var flame_h: float = FLAME_RADIUS * (0.6 + 1.5 * feedback)
	var flame_centre := centre + Vector2(jitter, -BODY_RADIUS - flame_h * 0.6)
	var flame_color := Color(1.0, 0.72 + 0.2 * feedback, 0.25, 0.85)
	var flame := PackedVector2Array([
		flame_centre + Vector2(0.0, -flame_h),
		flame_centre + Vector2(FLAME_RADIUS * 0.7, flame_h * 0.4),
		flame_centre + Vector2(-FLAME_RADIUS * 0.7, flame_h * 0.4),
	])
	draw_colored_polygon(flame, flame_color)

	# 灯座与到影人的连线：直观看出「灯距」
	draw_line(centre, Vector2(centre.x - travel_px, centre.y - travel_px * 0.35),
		Color(0.65, 0.55, 0.35, 0.5), 2.0)

	# 自检：任何读数越界都在画面上标红，避免「看起来正常其实越界」
	var out_of_range: bool = not (lamp.is_in_range())
	draw_string(ThemeDB.fallback_font, centre + Vector2(-70.0, BODY_RADIUS + 34.0),
		"灯油 %d%%%s" % [int(round(oil * 100.0)),
			"  越界！" if out_of_range else ""],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
		Color(0.95, 0.35, 0.35) if out_of_range else Color(0.92, 0.86, 0.72))
