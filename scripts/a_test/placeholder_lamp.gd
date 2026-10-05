extends Node2D
class_name PlaceholderLamp
## 占位油灯：只用 Godot 内置绘制表现 LampState，**不依赖 B 的任何美术**。
## 它同时充当「模拟 B 的显示端」：只读 LampState，从不写。
##
## ⚠️ 这是**占位表现**，不是定案：正式灯影表现属 B（TECH_DESIGN.md 第 3.2 节——
## 正式做法是把灯距映射成一组统一的影子缩放/偏移/斜切，作用于所有在场影人）。
##
## 画法取「灯在左下手边、暖光铺满幕布」，刻意**不画聚光灯光柱**：
## 灯是摆在签手身前矮处的一盏油灯，它照亮的是整块幕布，不是朝某个角落打一束光。
## 三个量对应 PRD 第 4.3 节：
## - distance 灯距：灯体朝幕布方向推近，暖光收拢变亮（滚轮推拉）
## - exposure 显露度：整块幕布的照度（Q/E 倾灯）
## - oil 灯油：灯体与光的整体亮度，最暗时仍留可辨认下限（PRD 第 8 节）
## - flame_feedback：火苗的**稳定程度**——接近中性几乎不动，偏离越远晃得越明显

const LampStateScript := preload("res://scripts/a/lamp_state.gd")

## 灯体支点（屏幕像素）：示意图「你的手边 · 身前矮处」的左侧。
@export var anchor: Vector2 = Vector2(268.0, 868.0)
## 需要被照亮的幕布区域。为空表示本场景没有幕布（例如纯油灯测试场景），
## 此时只画灯体与火苗，不铺洗光。
@export var cloth_rect: Rect2 = Rect2()
## distance 0→1 时灯体朝幕布推近的像素距离
@export var travel_px: float = 86.0
@export var show_debug_stats: bool = false

const BODY_RADIUS: float = 44.0
const FLAME_RADIUS: float = 15.0
## 幕布洗光的条带数（自上而下由暗到亮）
const WASH_BANDS: int = 20
## 火苗光晕的扇形分段数
const GLOW_SEGMENTS: int = 32
## 火苗抖动：中性附近几乎不动，偏离越远晃幅越大
const FLAME_SHAKE_MAX_PX: float = 11.0
const FLAME_SHAKE_SPEED: float = 0.012

var lamp: LampState = null


func _process(_delta: float) -> void:
	queue_redraw()


func _unit(field: String) -> float:
	if lamp == null:
		return 0.0
	match field:
		"distance": return clampf(lamp.distance, 0.0, 1.0)
		"exposure": return clampf(lamp.exposure, 0.0, 1.0)
		"oil": return clampf(lamp.oil, 0.0, 1.0)
		_: return clampf(lamp.flame_feedback, 0.0, 1.0)


## 灯体位置：distance 越大表示灯越靠近幕布上的影人。
func lamp_position() -> Vector2:
	return anchor + Vector2(0.42, -0.91) * travel_px * _unit("distance")


func _draw() -> void:
	if lamp == null:
		return
	_draw_cloth_wash()
	_draw_flame_glow()
	_draw_lamp_body()


## 铺满幕布的暖光：**自上而下**的照度梯度——灯摆在签手身前矮处，
## 所以幕布下缘近灯更亮、上缘更远更暗。
##
## 刻意只用上下梯度，不用以光心为原点的径向渐变：径向渐变在矩形幕布上会切出
## 一道斜向的明暗分界，看起来像灯在朝某个角落打光，而油灯照亮的是整块幕布。
func _draw_cloth_wash() -> void:
	if cloth_rect.size.x <= 1.0 or cloth_rect.size.y <= 1.0:
		return
	var exposure: float = _unit("exposure")
	var oil: float = _unit("oil")
	var distance: float = _unit("distance")
	var dim: float = (0.40 + 0.60 * oil) * (0.85 + 0.30 * distance)
	var bottom: float = (0.10 + 0.75 * exposure) * dim
	var top: float = bottom * 0.45
	var tint := Color(1.0, 0.86, 0.58)
	for i in WASH_BANDS:
		var t0: float = float(i) / float(WASH_BANDS)
		var t1: float = float(i + 1) / float(WASH_BANDS)
		var y0: float = lerpf(cloth_rect.end.y, cloth_rect.position.y, t0)
		var y1: float = lerpf(cloth_rect.end.y, cloth_rect.position.y, t1)
		var c0 := Color(tint.r, tint.g, tint.b, lerpf(bottom, top, t0))
		var c1 := Color(tint.r, tint.g, tint.b, lerpf(bottom, top, t1))
		draw_polygon(PackedVector2Array([
			Vector2(cloth_rect.position.x, y0), Vector2(cloth_rect.end.x, y0),
			Vector2(cloth_rect.end.x, y1), Vector2(cloth_rect.position.x, y1),
		]), PackedColorArray([c0, c0, c1, c1]))


## 火苗周围的一小圈光晕。灯体本身不发光柱，让"灯在哪"靠灯体位置表达。
func _draw_flame_glow() -> void:
	var exposure: float = _unit("exposure")
	var oil: float = _unit("oil")
	var centre: Vector2 = lamp_position() + Vector2(0.0, -BODY_RADIUS * 1.25)
	var radius: float = 150.0 - 60.0 * _unit("distance")
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	points.append(centre)
	colors.append(Color(1.0, 0.82, 0.46, 0.10 + 0.30 * exposure * (0.35 + 0.65 * oil)))
	for i in GLOW_SEGMENTS + 1:
		var angle: float = TAU * float(i) / float(GLOW_SEGMENTS)
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
		colors.append(Color(1.0, 0.72, 0.30, 0.0))
	draw_polygon(points, colors)


func _draw_lamp_body() -> void:
	var centre: Vector2 = lamp_position()
	var oil: float = _unit("oil")
	var exposure: float = _unit("exposure")
	var feedback: float = _unit("flame_feedback")

	# 灯油决定灯体亮度；最低仍保留可辨认的亮度下限（PRD 第 8 节）
	var bright: float = (0.30 + 0.70 * oil) * (0.55 + 0.45 * exposure)
	var bowl := Color(0.55 * bright, 0.37 * bright, 0.17 * bright)
	var rim := Color(0.20, 0.13, 0.07)

	# 灯座与灯身
	draw_rect(Rect2(centre.x - BODY_RADIUS * 0.55, centre.y + BODY_RADIUS * 0.72,
		BODY_RADIUS * 1.10, 14.0), rim)
	draw_circle(centre, BODY_RADIUS, bowl)
	draw_arc(centre, BODY_RADIUS, 0.0, TAU, 40, rim, 3.0)
	# 灯口朝上的浅口，让"油灯"这个物件读得出来
	draw_arc(centre + Vector2(0.0, -BODY_RADIUS * 0.55), BODY_RADIUS * 0.62,
		PI, TAU, 24, Color(1.0, 0.90, 0.62, 0.35 + 0.45 * exposure), 6.0)

	# 火苗：接近中性基本静止，偏离越远晃得越厉害；高度随反馈增大
	var deviation: float = absf(feedback - 0.5) * 2.0
	var shake_px: float = FLAME_SHAKE_MAX_PX * deviation
	var jitter: float = sin(float(Time.get_ticks_msec()) * FLAME_SHAKE_SPEED) * shake_px
	var flame_h: float = FLAME_RADIUS * (0.8 + 1.4 * feedback) * (0.6 + 0.4 * exposure)
	var flame_centre := centre + Vector2(jitter, -BODY_RADIUS - flame_h * 0.55)
	var flame := PackedVector2Array([
		flame_centre + Vector2(0.0, -flame_h),
		flame_centre + Vector2(FLAME_RADIUS * 0.72, flame_h * 0.45),
		flame_centre + Vector2(-FLAME_RADIUS * 0.72, flame_h * 0.45),
	])
	draw_colored_polygon(flame, Color(1.0, 0.74 + 0.20 * feedback, 0.26, 0.90))

	if show_debug_stats:
		draw_string(ThemeDB.fallback_font, centre + Vector2(-76.0, BODY_RADIUS + 38.0),
			"oil %d%%" % int(round(oil * 100.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
			Color(0.92, 0.86, 0.72))
