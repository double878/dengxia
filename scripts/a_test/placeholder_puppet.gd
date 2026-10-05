extends Node2D
class_name PlaceholderPuppet
## 占位影人（幕后视角）：从背后看过去的皮革躯体，带关节、连到签手的三根竹签。
## 只读 PuppetState / LampState，从不写——它同时充当「模拟 B 的显示端」。
##
## ⚠️ 这是**占位表现**，不是定案：正式影人素材属 B（TECH_DESIGN.md 第 3.2 节）。
## 这里的几何只求三件事在画面上看得懂：
## 1. 这是皮影戏的影人，不是普通剪影——所以有关节铆钉与竹签；
## 2. 滚轮推拉灯会让影子的**尺寸**同步变化（PRD 第 4.3 节）；
## 3. Q/E 倾灯改变影子的**显露程度**，低显露时只剩一点轮廓（同上）。

const PuppetStateScript := preload("res://scripts/a/puppet_state.gd")
const PuppetControllerScript := preload("res://scripts/a/puppet_controller.gd")

## 由场景注入的舞台渲染区域。必须与 PuppetController.STAGE_PIXEL_SIZE 同一坐标系，
## 这样「看到的胸签」与「拖得到的区域」才是同一个位置。
@export var stage_origin: Vector2 = Vector2.ZERO
@export var stage_size: Vector2 = Vector2(1920.0, 1080.0)
## 站立时从接地点到头顶的像素高度
@export var figure_height: float = 230.0
## 三根竹签汇到的手部位置（示意图「你的手边 · 手与三根签」）
@export var hand_anchor: Vector2 = Vector2(960.0, 852.0)
## 画面上画出的胸签热区。前四关允许出现操作图标（PRD 第 3、8 节）。
@export var show_chest_tag: bool = false

var puppet_state: PuppetState = null
var lamp_state: LampState = null

## 灯的推拉把全场影子一起缩放，不能只缩放单个影人（PRD 第 4.3 节）
const SHADOW_SCALE_MIN: float = 0.78
const SHADOW_SCALE_MAX: float = 1.36
## 显露程度的下限仍留一点轮廓：最暗时关键对象仍要可辨认（PRD 第 8 节）
const EXPOSURE_ALPHA_MIN: float = 0.20

## —— 身形几何（全部以「当前屏幕身高」为单位）——
## 这组比例是**唯一的**几何定义：画影人身体用它，回答「手腕在哪」也用它。
## 因此「挂在手上的道具」（第一关的伞）只要问 `hand_screen_position()` 就与画出来的手
## 对齐，不必在别处再算一遍——2026-10-04 之前伞就是因为在别处按另一套公式算，
## 被画到了幕布底部（详见 A→B 交接文档 6.2 节）。
const SHOULDER_RATIO: float = 0.80    ## 肩在接地点上方 0.80 个身高
const HIP_RATIO: float = 0.44         ## 髋在接地点上方 0.44 个身高
const HALF_W_RATIO: float = 0.105     ## 半身宽
const UPPER_ARM_RATIO: float = 0.16   ## 上臂长（与下臂合计 0.31 个身高）
const LOWER_ARM_RATIO: float = 0.15   ## 下臂长
## 站蹲对身高的折减系数：蹲到底矮 32%，与腿部的外张幅度配合。
const STANCE_HEIGHT_DROP: float = 0.32

const LEATHER: Color = Color(0.27, 0.18, 0.11)
const RIM: Color = Color(0.85, 0.62, 0.30)
const JOINT: Color = Color(0.92, 0.75, 0.40)
const STICK: Color = Color(0.78, 0.58, 0.30)

## 六个头（三个初始头 + 三个备用头）各自的头饰形状与点缀色。
## 换头必须能在画面上看出来，所以外形而非仅仅是颜色发生变化。
const HEAD_SHAPES: Array[String] = ["bun_high", "bun_twin", "cap_flat",
	"bun_high", "bun_twin", "cap_flat"]
const HEAD_ACCENTS: Array[Color] = [
	Color(0.86, 0.24, 0.24), Color(0.22, 0.55, 0.62), Color(0.86, 0.62, 0.20),
	Color(0.62, 0.26, 0.62), Color(0.26, 0.66, 0.38), Color(0.36, 0.40, 0.72),
]


func _process(_delta: float) -> void:
	queue_redraw()


## 归一化舞台坐标（0-1）→ 屏幕像素。y=0 在幕布最深处（画面上方），y=1 最靠玩家。
func stage_to_screen(normalized: Vector2) -> Vector2:
	return Vector2(
		stage_origin.x + normalized.x * stage_size.x,
		stage_origin.y + normalized.y * stage_size.y)


## 胸签中心的屏幕位置。与 PuppetController.begin_drag 使用同一公式，
## 保证「看到的圆圈」就是「拖得到的区域」。
func chest_tag_screen() -> Vector2:
	var ground: Vector2 = stage_to_screen(puppet_state.stage_pos)
	return Vector2(ground.x,
		ground.y - PuppetControllerScript.CHEST_TAG_RADIUS_PX * 0.5)


## 滚轮推拉灯 → 全场影子同步缩放的倍率
func shadow_scale() -> float:
	if lamp_state == null:
		return 1.0
	return lerpf(SHADOW_SCALE_MIN, SHADOW_SCALE_MAX,
		clampf(lamp_state.distance, 0.0, 1.0))


## Q/E 倾灯 → 影子显露程度
func exposure_alpha() -> float:
	if lamp_state == null:
		return 1.0
	return lerpf(EXPOSURE_ALPHA_MIN, 1.0, clampf(lamp_state.exposure, 0.0, 1.0))


## 本帧影人的屏幕身高（像素）：站高 × 灯距倍率 × 站蹲折减。
## 身体与两只手都从这一个值推出去，因此影子随灯距变大时，手（和手上的道具）一起变大。
func figure_px_height() -> float:
	var shrink: float = 1.0 - STANCE_HEIGHT_DROP * clampf(puppet_state.stance, 0.0, 1.0)
	return figure_height * shadow_scale() * shrink


## 翻面时的宽度倍率：|2p−1| 在 p=0.5 处压到 0（侧对观众），乘在宽度与手臂粗细上。
func flip_width_ratio() -> float:
	return maxf(absf(2.0 * clampf(puppet_state.turn_progress, 0.0, 1.0) - 1.0), 0.06)


## 半身宽（像素）。翻面压扁时收窄，但不小于 3 px——否则侧对观众那一瞬整个人会消失。
static func half_width_px(height: float, flip_width: float) -> float:
	return maxf(height * HALF_W_RATIO * flip_width, 3.0)


## 手臂方向（单位向量）。手角以「自然垂下」为 0、+π/2 水平前伸、+π 举过头顶；
## 屏幕 y 轴向下，因此右手是 π/2 − 手角、左手是 π/2 + 手角，两侧完全对称。
static func arm_direction(hand_angle: float, right_side: bool) -> Vector2:
	var screen_angle: float = (PI * 0.5 - hand_angle) if right_side else (PI * 0.5 + hand_angle)
	return Vector2(cos(screen_angle), sin(screen_angle))


## 肘点：肩 + 上臂。
static func arm_elbow(shoulder: Vector2, hand_angle: float, right_side: bool,
		height: float) -> Vector2:
	return shoulder + arm_direction(hand_angle, right_side) * height * UPPER_ARM_RATIO


## 腕点（= 手的位置）：肩 → 肘 → 腕走完，与 `_draw_arm` 画的完全同一条链。
static func arm_wrist(shoulder: Vector2, hand_angle: float, right_side: bool,
		height: float) -> Vector2:
	return arm_elbow(shoulder, hand_angle, right_side, height) \
		+ arm_direction(hand_angle, right_side) * height * LOWER_ARM_RATIO


## 某只手此刻画在屏幕上的位置（像素）。**只读状态，不改任何东西。**
## 「挂在手上的道具」按这个点画，就不会与画出来的手错位；灯距变化时也一并跟随。
func hand_screen_position(hand: String) -> Vector2:
	if puppet_state == null:
		return Vector2.ZERO
	var height: float = figure_px_height()
	var half_w: float = half_width_px(height, flip_width_ratio())
	var ground: Vector2 = stage_to_screen(puppet_state.stage_pos)
	var right_side: bool = hand != "left"
	var shoulder := Vector2(ground.x + (half_w if right_side else -half_w),
		ground.y - height * SHOULDER_RATIO)
	var angle: float = puppet_state.hand_angle.y if right_side else puppet_state.hand_angle.x
	return arm_wrist(shoulder, angle, right_side, height)


func _draw() -> void:
	if puppet_state == null:
		return
	var ground: Vector2 = stage_to_screen(puppet_state.stage_pos)
	var alpha: float = exposure_alpha()
	var height: float = figure_px_height()

	_draw_contact_shadow(ground, height, alpha)
	if puppet_state.hook_slot != PuppetStateScript.HOOK_SLOT_NONE:
		_draw_hook_marker(ground, height, alpha)
	_draw_figure(ground, height, alpha)
	if puppet_state.is_controlled:
		_draw_sticks(ground, height, alpha)
	if show_chest_tag or puppet_state.is_controlled:
		_draw_chest_tag()


## 接地点的一小片暗影：让人看出影子是「落在幕布上」的，尺寸随灯距同步变化。
func _draw_contact_shadow(ground: Vector2, height: float, alpha: float) -> void:
	var rx: float = height * 0.30
	var ry: float = height * 0.055
	var segments: int = 24
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	points.append(ground)
	colors.append(Color(0.05, 0.04, 0.03, alpha * 0.45))
	for i in segments + 1:
		var angle: float = TAU * float(i) / float(segments)
		points.append(ground + Vector2(cos(angle) * rx, sin(angle) * ry))
		colors.append(Color(0.05, 0.04, 0.03, 0.0))
	draw_polygon(points, colors)


## 挂起标记：挂在挂钩上的影人不再受控，用一个钩环示意（PRD 第 4.2 节）。
func _draw_hook_marker(ground: Vector2, height: float, alpha: float) -> void:
	var top := Vector2(ground.x, ground.y - height * 1.06)
	draw_arc(top + Vector2(0.0, height * 0.05), height * 0.07, 0.0, PI, 20,
		Color(0.85, 0.66, 0.32, alpha), 4.0)
	draw_line(top + Vector2(0.0, height * 0.12), top + Vector2(0.0, height * 0.2),
		Color(0.85, 0.66, 0.32, alpha), 4.0)


func _draw_figure(ground: Vector2, height: float, alpha: float) -> void:
	var state := puppet_state
	## 翻面表现：turn_progress 0→1 走完一次翻面，宽度倍率 |2p−1| 在 p=0.5 处压到 0，
	## 也就是「侧对观众」的那一瞬——正面/反面正是在这一瞬换过来的（PRD 第 4.1 节：
	## 转身有过渡、不能瞬间翻面）。整段只有 0.1 s。
	var flip_width: float = flip_width_ratio()
	var showing_front: bool = state.facing >= 0.0

	var body := Color(LEATHER.r, LEATHER.g, LEATHER.b, alpha)
	var rim := Color(RIM.r, RIM.g, RIM.b, alpha * 0.75)
	var joint := Color(JOINT.r, JOINT.g, JOINT.b, alpha)

	var hip := Vector2(ground.x, ground.y - height * HIP_RATIO)
	var shoulder := Vector2(ground.x, ground.y - height * SHOULDER_RATIO)
	var half_w: float = half_width_px(height, flip_width)

	# 腿：髋 → 膝 → 脚。蹲下时膝盖外张、重心下沉（stance 越大越蹲）
	var knee_out: float = height * (0.03 + 0.11 * clampf(state.stance, 0.0, 1.0)) * flip_width
	for side in [-1.0, 1.0]:
		var knee := Vector2(hip.x + side * knee_out, ground.y - height * 0.22)
		var foot := Vector2(ground.x + side * half_w * 0.95, ground.y)
		draw_line(hip, knee, body, height * 0.048)
		draw_line(knee, foot, body, height * 0.044)
		draw_circle(knee, height * 0.021, joint)

	# 躯干
	var torso := PackedVector2Array([
		Vector2(hip.x - half_w * 0.82, hip.y),
		Vector2(shoulder.x - half_w, shoulder.y),
		Vector2(shoulder.x + half_w, shoulder.y),
		Vector2(hip.x + half_w * 0.82, hip.y),
	])
	draw_colored_polygon(torso, body)
	draw_polyline(torso + PackedVector2Array([torso[0]]), rim, 2.0)

	# 双臂：肩 → 肘 → 腕。手角 0 = 自然垂下，+π/2 = 水平前伸，+π = 举过头顶
	_left_wrist = _draw_arm(Vector2(shoulder.x - half_w, shoulder.y),
		state.hand_angle.x, false, height, body, joint, flip_width)
	_right_wrist = _draw_arm(Vector2(shoulder.x + half_w, shoulder.y),
		state.hand_angle.y, true, height, body, joint, flip_width)

	# 头：正反两面各有自己的标记，换面因此是可核对的，而不是只靠宽度变化猜
	var head_center := Vector2(shoulder.x, shoulder.y - height * 0.115)
	var head_r: float = maxf(height * 0.105 * maxf(flip_width, 0.35), 4.0)
	_draw_head(head_center, head_r, showing_front, body, rim, alpha)


## 一条手臂。手角以「自然垂下」为 0，向抬手方向为正；屏幕角口径见 `arm_direction()`。
## 几何全部走 `arm_elbow()` / `arm_wrist()`，与 `hand_screen_position()` 共用一条链——
## 手画在哪，问道具落点时就会得到同一个点。
func _draw_arm(shoulder: Vector2, angle: float, right_side: bool,
		height: float, body: Color, joint: Color, flip_width: float) -> Vector2:
	var elbow: Vector2 = arm_elbow(shoulder, angle, right_side, height)
	var wrist: Vector2 = arm_wrist(shoulder, angle, right_side, height)
	# 翻面压扁时手臂同步变细，避免整台只剩两根粗线还挂在外面
	var thickness: float = maxf(flip_width, 0.25)
	draw_line(shoulder, elbow, body, height * 0.042 * thickness)
	draw_line(elbow, wrist, body, height * 0.038 * thickness)
	draw_circle(elbow, height * 0.020 * thickness, joint)
	draw_circle(wrist, height * 0.024 * thickness, Color(0.93, 0.86, 0.70, joint.a))
	return wrist


## 本帧画出的两只手腕位置，供竹签连线取点。
var _left_wrist: Vector2 = Vector2.ZERO
var _right_wrist: Vector2 = Vector2.ZERO


## 头：正面画五官、反面只留一道背缝，两者在灰度下也能区分。
func _draw_head(centre: Vector2, radius: float, showing_front: bool,
		body: Color, rim: Color, alpha: float) -> void:
	draw_circle(centre, radius, body)
	draw_arc(centre, radius, 0.0, TAU, 32, rim, 2.0)

	var head_id: int = puppet_state.head_id
	var index: int = head_id if head_id >= 0 else 0
	if index >= HEAD_SHAPES.size():
		index = index % HEAD_SHAPES.size()
	var accent: Color = HEAD_ACCENTS[index]
	accent.a = alpha

	# 头饰外形按 head_id 变化——换头因此改变的是轮廓，不只是颜色
	match HEAD_SHAPES[index]:
		"bun_high":
			draw_circle(centre + Vector2(0.0, -radius * 1.35), radius * 0.42, accent)
		"bun_twin":
			draw_circle(centre + Vector2(-radius * 0.85, -radius * 0.85), radius * 0.34, accent)
			draw_circle(centre + Vector2(radius * 0.85, -radius * 0.85), radius * 0.34, accent)
		_:
			draw_rect(Rect2(centre.x - radius * 1.15, centre.y - radius * 1.15,
				radius * 2.30, radius * 0.46), accent)

	if showing_front:
		# 正面：两只眼 + 鼻尖楔形
		draw_circle(centre + Vector2(-radius * 0.34, -radius * 0.14), radius * 0.13,
			Color(0.10, 0.07, 0.05, alpha))
		draw_circle(centre + Vector2(radius * 0.30, -radius * 0.14), radius * 0.13,
			Color(0.10, 0.07, 0.05, alpha))
		var nose := PackedVector2Array([
			centre + Vector2(radius * 0.82, -radius * 0.10),
			centre + Vector2(radius * 1.42, radius * 0.40),
			centre + Vector2(radius * 0.82, radius * 0.46),
		])
		draw_colored_polygon(nose, body)
	else:
		# 反面：一道竖背缝 + 缝上的小签钉
		draw_line(centre + Vector2(0.0, -radius * 0.72),
			centre + Vector2(0.0, radius * 0.96), rim, 2.0)
		draw_circle(centre + Vector2(0.0, -radius * 0.72), radius * 0.16, rim)


## 三根竹签：一根连胸签、两根连手，全部汇到签手的手部。
## 这是「借签操演」在画面上唯一的直接证据（PRD 第 4 节）。
func _draw_sticks(ground: Vector2, height: float, alpha: float) -> void:
	var color := Color(STICK.r, STICK.g, STICK.b, alpha * 0.95)
	var chest: Vector2 = Vector2(ground.x, ground.y - height * 0.62)
	draw_line(chest, hand_anchor, color, 4.0)
	draw_line(_left_wrist, hand_anchor, color, 3.0)
	draw_line(_right_wrist, hand_anchor, color, 3.0)


## 胸签热区的可视化。前四关允许出现融入画面的操作图标（PRD 第 3、8 节）。
func _draw_chest_tag() -> void:
	var centre: Vector2 = chest_tag_screen()
	draw_arc(centre, PuppetControllerScript.CHEST_TAG_RADIUS_PX, 0.0, TAU, 40,
		Color(0.95, 0.55, 0.20, 0.75), 3.0)
	draw_circle(centre, 7.0, Color(0.99, 0.80, 0.42, 0.95))
