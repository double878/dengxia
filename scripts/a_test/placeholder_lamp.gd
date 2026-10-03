extends Node2D
class_name PlaceholderLamp
## 占位油灯：只用 Godot 内置绘制表现 LampState，**不依赖 B 的任何美术**。
## 它同时充当「模拟 B 的显示端」：只读 LampState，从不写。
##
## ⚠️ 这是**占位表现**，不是定案：正式灯影表现属 B（TECH_DESIGN.md 第 3.2 节——
## 正式做法是把灯距映射成一组统一的影子缩放/偏移/斜切，作用于所有在场影人，
## 而不是画一盏聚光灯）。这里的几何只求「看得懂 A 的三个量在变什么」。
##
## 可见要素对应 PRD 第 4.3 节的三件事：
## - 灯距 distance：灯离影人越近 → 光锥张角越大、覆盖越宽（滚轮推拉）
## - 显露度 exposure：光锥越亮（Q/E 倾灯）
## - 灯油 oil：灯体本身越暗（环境亮度下限仍可辨认）
## - flame_feedback：火苗**稳定程度**——接近中性时几乎不动，偏离越远晃得越明显

const LampStateScript := preload("res://scripts/a/lamp_state.gd")

## 灯架支点（屏幕像素）。默认摆在影人右后上方：影人默认站位在 (960, 540) 一带，
## 灯口因此**朝左下、照到影人身上**，光锥是「灯口窄、打到影人处宽」的聚光形状；
## 同时避开左侧状态面板与顶部提示行。
@export var anchor: Vector2 = Vector2(1080.0, 110.0)
## 光锥瞄准点。默认是影人默认站位（stage_pos = 0.5, 0.5）那一带。
@export var aim: Vector2 = Vector2(960.0, 560.0)
## distance 0→1 时灯朝影人方向移动的距离（滚轮推拉的可见位移）。
@export var travel_px: float = 150.0

const FLAME_RADIUS: float = 16.0
const BODY_RADIUS: float = 42.0
## 光锥「张角 / 投射距离」比：近 → 窄而集中，远 → 宽而散。
## 取值让光斑在影人处大致覆盖影人宽度，而不是铺满全屏。
const SPREAD_RATIO_MIN: float = 0.34
const SPREAD_RATIO_MAX: float = 0.74
## 光锥至少延伸到这里，保证 distance 两端的覆盖范围都明显可见
const MIN_THROW_PX: float = 460.0
## 火苗抖动：中性附近几乎不动，偏离越远晃幅越大
const FLAME_SHAKE_MAX_PX: float = 10.0
const FLAME_SHAKE_SPEED: float = 0.012

var lamp: LampState = null


func _process(_delta: float) -> void:
	queue_redraw()


## 灯体位置：distance 越大表示灯越靠近影人。
func lamp_position() -> Vector2:
	if lamp == null:
		return anchor
	var d: float = clampf(lamp.distance, 0.0, 1.0)
	return anchor - Vector2(travel_px, travel_px * 0.6) * d


## 光锥顶点：从灯体上方一点往前推，避免锥形把灯体自己盖住。
func cone_apex() -> Vector2:
	return lamp_position() + Vector2(-BODY_RADIUS * 0.9, -BODY_RADIUS * 1.1)


func _draw() -> void:
	if lamp == null:
		return
	var centre: Vector2 = lamp_position()
	var oil: float = clampf(lamp.oil, 0.0, 1.0)
	var exposure: float = clampf(lamp.exposure, 0.0, 1.0)
	var feedback: float = clampf(lamp.flame_feedback, 0.0, 1.0)
	var distance: float = clampf(lamp.distance, 0.0, 1.0)

	var apex: Vector2 = cone_apex()
	# 光锥朝向左下方的影人站位
	var dir: Vector2 = (aim - apex)
	var throw_px: float = maxf(dir.length(), 1.0)
	var unit: Vector2 = dir / throw_px
	var side: Vector2 = Vector2(-unit.y, unit.x)

	# 光锥：灯口窄、打到影人处宽；张角随灯距增大（近窄远宽），亮度由显露度决定
	var ratio: float = lerpf(SPREAD_RATIO_MIN, SPREAD_RATIO_MAX, distance)
	var half_spread: float = maxf(throw_px, MIN_THROW_PX) * ratio * 0.5
	var cone_alpha: float = 0.05 + 0.25 * exposure
	var cone := PackedVector2Array([
		apex,
		apex + unit * throw_px + side * half_spread,
		apex + unit * throw_px - side * half_spread,
	])
	draw_colored_polygon(cone, Color(1.0, 0.82, 0.45, cone_alpha))

	# 灯油决定灯体亮度；最低仍保留可辨认的亮度下限（PRD 第 8 节）
	var body_bright: float = 0.25 + 0.75 * oil
	draw_circle(centre, BODY_RADIUS, Color(0.55 * body_bright, 0.36 * body_bright,
		0.16 * body_bright))
	draw_arc(centre, BODY_RADIUS, 0.0, TAU, 40, Color(0.18, 0.12, 0.07), 3.0)
	# 灯口朝影人一侧，便于看出灯朝哪边
	draw_circle(centre + unit * BODY_RADIUS * 0.8, BODY_RADIUS * 0.45,
		Color(1.0, 0.88, 0.55, 0.55))

	# 火苗：接近中性基本静止，偏离越远晃得越厉害；高度随反馈增大
	var deviation: float = absf(feedback - 0.5) * 2.0
	var shake_px: float = FLAME_SHAKE_MAX_PX * deviation
	var jitter: float = sin(float(Time.get_ticks_msec()) * FLAME_SHAKE_SPEED) * shake_px
	var flame_h: float = FLAME_RADIUS * (0.7 + 1.2 * feedback)
	var flame_centre := centre + Vector2(jitter, -BODY_RADIUS - flame_h * 0.6)
	var flame := PackedVector2Array([
		flame_centre + Vector2(0.0, -flame_h),
		flame_centre + Vector2(FLAME_RADIUS * 0.7, flame_h * 0.4),
		flame_centre + Vector2(-FLAME_RADIUS * 0.7, flame_h * 0.4),
	])
	draw_colored_polygon(flame, Color(1.0, 0.72 + 0.2 * feedback, 0.25, 0.85))

	# 灯架连杆：把灯挂在影人左前上方，直观看出「灯距」
	draw_line(centre, anchor, Color(0.65, 0.55, 0.35, 0.5), 2.0)

	# 自检：任何读数越界都在画面上标红，避免「看起来正常其实越界」
	var out_of_range: bool = not lamp.is_in_range()
	draw_string(ThemeDB.fallback_font, centre + Vector2(-70.0, BODY_RADIUS + 34.0),
		"灯油 %d%%%s" % [int(round(oil * 100.0)),
			"  越界！" if out_of_range else ""],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
		Color(0.95, 0.35, 0.35) if out_of_range else Color(0.92, 0.86, 0.72))
