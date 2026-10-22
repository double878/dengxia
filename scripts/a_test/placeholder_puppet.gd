extends Node2D
class_name PlaceholderPuppet
## 幕后影人显示端：白素贞、许仙、小青使用参考图分件。
## 只读 PuppetState / LampState，从不写——它同时充当「模拟 B 的显示端」。
##
## 美术只读 A 的状态；分件、手腕和道具共用同一显示变换。保留的几何负责：
## 1. 这是皮影戏的影人，不是普通剪影——所以有关节铆钉与竹签；
## 2. 滚轮推拉灯会让影子的**尺寸**同步变化（PRD 第 4.3 节）；
## 3. Q/E 倾灯改变影子的**显露程度**，低显露时只剩一点轮廓（同上）。

const PuppetStateScript := preload("res://scripts/a/puppet_state.gd")
const PuppetControllerScript := preload("res://scripts/a/puppet_controller.gd")
const UpperPose := preload("res://scripts/a/upper_body_pose.gd")
const SKIN_TEXTURES: Array[Texture2D] = [
	preload("res://assets/puppets/baisuzhen.png"),
	preload("res://assets/puppets/xuxian.png"),
	preload("res://assets/puppets/xiaoqing.png"),
]
## 额外角色只通过显式覆盖使用，不能改变第一关原来六个头的映射。
const EXTRA_SKIN_TEXTURES: Dictionary = {
	3: preload("res://assets/puppets/fahai.png"),
	4: preload("res://assets/puppets/immortals/xianweng.png"),
	5: preload("res://assets/puppets/immortals/bailu.png"),
	6: preload("res://assets/puppets/immortals/baihe.png")
}
const IMMORTAL_MANIFEST: JSON = preload("res://assets/puppets/immortals/immortals-assets.json")
const SKIN_MANIFEST_PATH: String = "res://assets/puppets/puppet_assets.json"
const SKIN_MANIFEST: JSON = preload("res://assets/puppets/puppet_assets.json")
var _skins: Dictionary = _read_skins()
var _skin_canvas_transform: Transform2D = Transform2D.IDENTITY
## 由场景按原有持伞归属更新，仅选择手部贴图，不写操控状态。
var _held_prop_hand: String = ""

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
## 角色外观与运行影人编号分开。第二关的 0 号影人使用法海（3），不改第一关资产。
@export var skin_override: int = -1
## 旧 A 测试保留 0；游戏实体使用 1；幕面离屏透射使用 2。
enum RenderMode { LEGACY, ENTITY, PROJECTION }
@export var render_mode: RenderMode = RenderMode.LEGACY
var _view_material: ShaderMaterial = null
var _last_draw_state: Array = []
## 仅第二关首次出场遮挡使用；空值不影响其余场景或第一关回放。
var entrance_mask: Texture2D = null
var show_upper_controls: bool = false
var upper_hover_part: String = ""
var upper_drag_part: String = ""
var _hit_mask_texture: Texture2D = null
var _hit_mask_image: Image = null
## 第二幕坐姿/惊倒，默认关闭；宿主向实体/投影视图提供同一参数。
var seated: bool = false
var seat_y: float = 0.0
var fall_angle: float = 0.0

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
const SHOULDER_RATIO: float = 0.80  ## 肩在接地点上方 0.80 个身高
const HIP_RATIO: float = 0.44  ## 髋在接地点上方 0.44 个身高
const HALF_W_RATIO: float = 0.105  ## 半身宽
const UPPER_ARM_RATIO: float = 0.16  ## 上臂长（与下臂合计 0.31 个身高）
const LOWER_ARM_RATIO: float = 0.15  ## 下臂长
## 头：中心在肩上方 0.115 个身高、半径 0.105 个身高。
## 抽成常量是因为**伞面要罩住头**（用户 2026-10-05）：伞的定位读
## `head_top_screen_position()`，与这里画出来的头共用同一套数，不会各算一套。
const HEAD_CENTRE_RATIO: float = 0.115
const HEAD_RADIUS_RATIO: float = 0.105
## 站蹲对身高的折减系数：蹲到底矮 32%，与腿部的外张幅度配合。
const STANCE_HEIGHT_DROP: float = 0.32

const LEATHER: Color = Color(0.27, 0.18, 0.11)
const RIM: Color = Color(0.85, 0.62, 0.30)
const JOINT: Color = Color(0.92, 0.75, 0.40)
const STICK: Color = Color(0.78, 0.58, 0.30)

## 六个头（三个初始头 + 三个备用头）各自的头饰形状与点缀色。
## 换头必须能在画面上看出来，所以外形而非仅仅是颜色发生变化。
const HEAD_SHAPES: Array[String] = [
	"bun_high", "bun_twin", "cap_flat", "bun_high", "bun_twin", "cap_flat"
]
const HEAD_ACCENTS: Array[Color] = [
	Color(0.86, 0.24, 0.24),
	Color(0.22, 0.55, 0.62),
	Color(0.86, 0.62, 0.20),
	Color(0.62, 0.26, 0.62),
	Color(0.26, 0.66, 0.38),
	Color(0.36, 0.40, 0.72),
]


func _process(_delta: float) -> void:
	_update_view_material()
	if puppet_state == null:
		if not _last_draw_state.is_empty():
			_last_draw_state.clear()
			queue_redraw()
		return
	# 自定义绘制命令由 Godot 保留；灯晃动可直接改节点变换/材质，不重建静止分件。
	var draw_state: Array = [
		render_mode,
		puppet_state.stage_pos,
		puppet_state.stance,
		puppet_state.facing,
		puppet_state.turn_progress,
		puppet_state.hand_angle,
		puppet_state.elbow_angle,
		puppet_state.head_tilt,
		puppet_state.torso_lean,
		puppet_state.air_height,
		puppet_state.leg_spread,
		puppet_state.body_angle,
		puppet_state.head_id,
		puppet_state.hook_slot,
		puppet_state.is_controlled,
		puppet_state.puppet_id,
		skin_override,
		stage_origin,
		stage_size,
		figure_height,
		hand_anchor,
		show_chest_tag,
		_held_prop_hand,
		puppet_state.walk_phase,
		puppet_state.walk_amount
	]
	draw_state.append_array(
		[show_upper_controls, upper_hover_part, upper_drag_part, seated, seat_y, fall_angle]
	)
	if render_mode != RenderMode.ENTITY and lamp_state != null:
		draw_state.append(lamp_state.distance)
	if render_mode == RenderMode.LEGACY and lamp_state != null:
		draw_state.append(lamp_state.exposure)
	if draw_state != _last_draw_state:
		_last_draw_state = draw_state
		queue_redraw()


func _update_view_material() -> void:
	if render_mode == RenderMode.LEGACY:
		material = null
		return
	var shader: Shader = (
		preload("res://shaders/puppet_back.gdshader")
		if render_mode == RenderMode.ENTITY
		else preload("res://shaders/puppet_transmission.gdshader")
	)
	if _view_material == null or _view_material.shader != shader:
		_view_material = ShaderMaterial.new()
		_view_material.shader = shader
	material = _view_material
	_view_material.set_shader_parameter("entrance_active", entrance_mask != null)
	_view_material.set_shader_parameter("entrance_mask", entrance_mask)
	if render_mode == RenderMode.ENTITY:
		_view_material.set_shader_parameter(
			"environment",
			0.58 + 0.42 * StageLight.unit(lamp_state.oil) if lamp_state != null else 1.0
		)


## 归一化舞台坐标（0-1）→ 屏幕像素。y=0 在幕布最深处（画面上方），y=1 最靠玩家。
func stage_to_screen(normalized: Vector2) -> Vector2:
	return Vector2(
		stage_origin.x + normalized.x * stage_size.x, stage_origin.y + normalized.y * stage_size.y
	)


## 胸签中心的屏幕位置。与 PuppetController.begin_drag 使用同一公式，
## 保证「看到的圆圈」就是「拖得到的区域」。
func chest_tag_screen() -> Vector2:
	var ground: Vector2 = stage_to_screen(puppet_state.stage_pos)
	return Vector2(ground.x, ground.y - PuppetControllerScript.CHEST_TAG_RADIUS_PX * 0.5)


## 滚轮推拉灯 → 全场影子同步缩放的倍率
func shadow_scale() -> float:
	if lamp_state == null:
		return 1.0
	return lerpf(SHADOW_SCALE_MIN, SHADOW_SCALE_MAX, clampf(lamp_state.distance, 0.0, 1.0))


## Q/E 倾灯 → 影子显露程度
func exposure_alpha() -> float:
	# 投影显露在幕面合成时控制一次；实体始终保持不透明。
	if render_mode != RenderMode.LEGACY:
		return 1.0
	if lamp_state == null:
		return 1.0
	return lerpf(EXPOSURE_ALPHA_MIN, 1.0, clampf(lamp_state.exposure, 0.0, 1.0))


## 本帧影人的屏幕身高（像素）：站高 × 灯距倍率 × 站蹲折减。
## 身体与两只手都从这一个值推出去，因此影子随灯距变大时，手（和手上的道具）一起变大。
func figure_px_height() -> float:
	var shrink: float = 1.0 - STANCE_HEIGHT_DROP * clampf(puppet_state.stance, 0.0, 1.0)
	return figure_height * (1.0 if render_mode == RenderMode.ENTITY else shadow_scale()) * shrink


## 翻面时的宽度倍率：|2p−1| 在 p=0.5 处压到 0（侧对观众），乘在宽度与手臂粗细上。
func flip_width_ratio() -> float:
	return maxf(absf(2.0 * clampf(puppet_state.turn_progress, 0.0, 1.0) - 1.0), 0.06)


## 半身宽（像素）。翻面压扁时收窄，但不小于 3 px——否则侧对观众那一瞬整个人会消失。
static func half_width_px(height: float, flip_width: float) -> float:
	return maxf(height * HALF_W_RATIO * flip_width, 3.0)


## 肩间距属于身体美术，不随换头改变；腕点查询与绘制共用，腿部沿用原身宽。
func shoulder_half_width_px(height: float, flip_width: float) -> float:
	if not _has_body_skin():
		return half_width_px(height, flip_width)
	var skin: Dictionary = _skins[str(_body_skin_id())]
	return maxf(
		height * float(skin.get("shoulder_half_width_ratio", HALF_W_RATIO)) * flip_width, 3.0
	)


## 手臂方向（单位向量）。手角以「自然垂下」为 0、+π/2 水平前伸、+π 举过头顶；
## 屏幕 y 轴向下，因此右手是 π/2 − 手角、左手是 π/2 + 手角，两侧完全对称。
static func arm_direction(hand_angle: float, right_side: bool) -> Vector2:
	var screen_angle: float = (PI * 0.5 - hand_angle) if right_side else (PI * 0.5 + hand_angle)
	return Vector2(cos(screen_angle), sin(screen_angle))


## 肘点：肩 + 上臂。
static func arm_elbow(
	shoulder: Vector2, hand_angle: float, right_side: bool, height: float
) -> Vector2:
	return shoulder + arm_direction(hand_angle, right_side) * height * UPPER_ARM_RATIO


## 腕点（= 手的位置）：肩 → 肘 → 腕走完，与 `_draw_arm` 画的完全同一条链。
static func arm_wrist(
	shoulder: Vector2, hand_angle: float, right_side: bool, height: float
) -> Vector2:
	return (
		arm_elbow(shoulder, hand_angle, right_side, height)
		+ arm_direction(hand_angle, right_side) * height * LOWER_ARM_RATIO
	)


## 某只手此刻画在屏幕上的位置（像素）。**只读状态，不改任何东西。**
## 「挂在手上的道具」按这个点画，就不会与画出来的手错位；灯距变化时也一并跟随。
func hand_screen_position(hand: String) -> Vector2:
	if puppet_state == null:
		return Vector2.ZERO
	var height: float = figure_px_height()
	var half_w: float = shoulder_half_width_px(
		height, 1.0 if _has_body_skin() else flip_width_ratio()
	)
	var ground: Vector2 = stage_to_screen(puppet_state.stage_pos)
	var right_side: bool = hand != "left"
	var shoulder := Vector2(
		ground.x + (half_w if right_side else -half_w),
		ground.y - height * SHOULDER_RATIO + walk_body_offset(height)
	)
	var angle: float = puppet_state.hand_angle.y if right_side else puppet_state.hand_angle.x
	var bend: float = puppet_state.elbow_angle.y if right_side else puppet_state.elbow_angle.x
	var wrist: Vector2 = UpperPose.arm_points(shoulder, angle, bend, right_side, height).wrist
	return _skin_figure_transform(ground) * upper_transform() * wrist


func upper_transform() -> Transform2D:
	var ground: Vector2 = stage_to_screen(puppet_state.stage_pos)
	var height: float = figure_px_height()
	var hip := ground + Vector2(0, -height * HIP_RATIO + walk_body_offset(height))
	return UpperPose.torso_transform(hip, puppet_state.torso_lean * pose_reference_facing())


func pose_reference_facing() -> float:
	return float(_skins[str(_body_skin_id())]["reference_facing"]) if _has_body_skin() else 1.0


func torso_screen_position() -> Vector2:
	var ground: Vector2 = stage_to_screen(puppet_state.stage_pos)
	var height: float = figure_px_height()
	var centre := (
		ground + Vector2(0, -height * (SHOULDER_RATIO + HIP_RATIO) * 0.5 + walk_body_offset(height))
	)
	return _skin_figure_transform(ground) * upper_transform() * centre


func hand_target_offset(point: Vector2, hand: String) -> Vector2:
	var ground: Vector2 = stage_to_screen(puppet_state.stage_pos)
	var matrix: Transform2D = _skin_figure_transform(ground) * upper_transform()
	var height: float = figure_px_height()
	var right: bool = hand == "right"
	var shoulder := (
		ground
		+ Vector2(
			shoulder_half_width_px(height, 1.0) * (1.0 if right else -1.0),
			-height * SHOULDER_RATIO + walk_body_offset(height)
		)
	)
	return matrix.affine_inverse() * point - shoulder


func hit_upper_body(point: Vector2, alt: bool) -> String:
	if puppet_state == null or not puppet_state.is_controlled or not visible:
		return ""
	if entrance_mask != _hit_mask_texture:
		_hit_mask_texture = entrance_mask
		_hit_mask_image = entrance_mask.get_image() if entrance_mask != null else null
	if (
		_hit_mask_image != null
		and Rect2(Vector2.ZERO, Vector2(_hit_mask_image.get_size())).has_point(point)
	):
		if _hit_mask_image.get_pixel(int(point.x), int(point.y)).r > 0.5:
			return ""
	var height: float = figure_px_height()
	if alt and point.distance_to(torso_screen_position()) <= height * 0.23:
		return "torso"
	var left_distance: float = point.distance_to(hand_screen_position("left"))
	var right_distance: float = point.distance_to(hand_screen_position("right"))
	if minf(left_distance, right_distance) <= maxf(height * 0.10, 16.0):
		return "left" if left_distance < right_distance else "right"
	if point.distance_to(head_screen_position()) <= maxf(height * 0.16, 20.0):
		return "head"
	return ""


func head_screen_position() -> Vector2:
	var ground: Vector2 = stage_to_screen(puppet_state.stage_pos)
	var height: float = figure_px_height()
	var shoulder := ground + Vector2(0, -height * SHOULDER_RATIO + walk_body_offset(height))
	return (
		_skin_figure_transform(ground)
		* upper_transform()
		* _head_centre_local(shoulder, height)
	)


## 头和衣领使用同一源图颈根对接；查询与绘制共用此链，伞与拖头不偏移。
func _head_centre_local(shoulder: Vector2, height: float) -> Vector2:
	var skin_id: int = skin_override if skin_override >= 0 else puppet_state.head_id
	if _has_body_skin() and skin_id == _body_skin_id():
		var skin: Dictionary = _skins[str(skin_id)]
		if skin.has("neck_attachment_ratio") and skin.has("head_neck_offset_ratio"):
			var attachment: Array = skin["neck_attachment_ratio"]
			var offset: Array = skin["head_neck_offset_ratio"]
			return (shoulder + Vector2(attachment[0], attachment[1]) * height
				- (Vector2(offset[0], offset[1]) * height).rotated(puppet_state.head_tilt))
	var neck := shoulder + Vector2(0, -height * .04)
	return neck + Vector2(0, -height * (HEAD_CENTRE_RATIO - .04)).rotated(puppet_state.head_tilt)


## 固定枢轴上完成整个人的水平翻面；宽度压缩也作用于肩、手和伞的挂点。
## 参考朝向定义分件原稿的那一面，三具影人使用同一显示变换。
func _skin_figure_transform(ground: Vector2) -> Transform2D:
	var width: float = 1.0
	if _has_body_skin():
		var skin: Dictionary = _skins[str(_body_skin_id())]
		width = flip_width_ratio() * puppet_state.facing / float(skin["reference_facing"])
	var mirror := Transform2D(
		Vector2(width, 0.0), Vector2(0.0, 1.0), Vector2(ground.x * (1.0 - width), 0.0)
	)
	var offset := Vector2.ZERO
	if seated:
		offset.y = seat_y - (ground.y - figure_px_height() * HIP_RATIO)
	var fall := Transform2D(fall_angle, Vector2.ZERO)
	fall.origin = ground - fall * ground + fall * offset
	var pivot := ground - Vector2(0.0, figure_px_height() * HIP_RATIO)
	var motion_transform := Transform2D(puppet_state.body_angle, Vector2.ZERO)
	motion_transform.origin = (
		pivot - motion_transform * pivot - Vector2(0, puppet_state.air_height * stage_size.y)
	)
	return motion_transform * fall * mirror


func mouth_screen_position() -> Vector2:
	return (
		head_screen_position()
		+ Vector2(puppet_state.facing * figure_px_height() * 0.04, figure_px_height() * 0.035)
	)


## 头半径（像素）。翻面压扁时头也收窄，但不小于 4 px——侧对观众那一瞬头不能消失。
func head_radius_px(height: float) -> float:
	return maxf(height * HEAD_RADIUS_RATIO * maxf(flip_width_ratio(), 0.35), 4.0)


## 头顶在屏幕上的位置（像素）。**只读状态，不改任何东西。**
## 「要罩住头的东西」（第一关的伞面）按这个点定位，就不会与画出来的头错位；
## 灯距变化、翻面压扁时也一并跟随。
func head_top_screen_position() -> Vector2:
	if puppet_state == null:
		return Vector2.ZERO
	var height: float = figure_px_height()
	var centre: Vector2 = head_screen_position()
	return Vector2(centre.x, centre.y - head_radius_px(height))


func walk_body_offset(height: float) -> float:
	return -absf(sin(puppet_state.walk_phase)) * height * 0.008 * puppet_state.walk_amount


## 上半周期离地向前送脚，下半周期落地向后蹬；局部方向遵循贴图原朝向。
func walk_step_offset(side: float, height: float) -> Vector2:
	var phase: float = fposmod(puppet_state.walk_phase + (PI if side < 0.0 else 0.0), TAU)
	var forward: float = -cos(phase) if phase < PI else 1.0 - 2.0 * (phase - PI) / PI
	return Vector2(
		forward * height * .065 * pose_reference_facing(),
		-maxf(sin(phase), 0.0) * height * .035
	) * puppet_state.walk_amount


func _draw() -> void:
	if puppet_state == null:
		return
	var ground: Vector2 = stage_to_screen(puppet_state.stage_pos)
	var alpha: float = exposure_alpha()
	var height: float = figure_px_height()

	if render_mode == RenderMode.LEGACY:
		_draw_contact_shadow(ground, height, alpha)
	if (
		render_mode != RenderMode.PROJECTION
		and puppet_state.hook_slot != PuppetStateScript.HOOK_SLOT_NONE
	):
		_draw_hook_marker(ground, height, alpha)
	_draw_figure(ground, height, alpha)
	if render_mode != RenderMode.PROJECTION and puppet_state.is_controlled:
		_draw_sticks(ground, height, alpha)
	if render_mode != RenderMode.PROJECTION and (show_chest_tag or puppet_state.is_controlled):
		_draw_chest_tag()
	if show_upper_controls and render_mode != RenderMode.PROJECTION and puppet_state.is_controlled:
		_draw_upper_hint()


func _draw_upper_hint() -> void:
	var part: String = upper_drag_part if not upper_drag_part.is_empty() else upper_hover_part
	if part.is_empty():
		return
	var point: Vector2 = torso_screen_position() if part == "torso" else head_screen_position()
	if part in ["left", "right"]:
		point = hand_screen_position(part)
	var radius: float = 10.0 if upper_drag_part.is_empty() else 13.0
	draw_circle(point, radius + 3, Color(0.10, 0.08, 0.05, 0.75))
	draw_arc(point, radius, 0, TAU, 32, Color("#eac973"), 2.0, true)
	var label: String = (
		"Alt · 前倾" if part == "torso" else ("拖动 · 俯仰" if part == "head" else "拖动 · 手签")
	)
	draw_string(
		ThemeDB.fallback_font,
		point + Vector2(18, -8),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		Color("#f7e9c7")
	)


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
	draw_arc(
		top + Vector2(0.0, height * 0.05),
		height * 0.07,
		0.0,
		PI,
		20,
		Color(0.85, 0.66, 0.32, alpha),
		4.0
	)
	draw_line(
		top + Vector2(0.0, height * 0.12),
		top + Vector2(0.0, height * 0.2),
		Color(0.85, 0.66, 0.32, alpha),
		4.0
	)


func _draw_figure(ground: Vector2, height: float, alpha: float) -> void:
	var state := puppet_state
	## 翻面表现：turn_progress 0→1 走完一次翻面，宽度倍率 |2p−1| 在 p=0.5 处压到 0，
	## 也就是「侧对观众」的那一瞬——正面/反面正是在这一瞬换过来的（PRD 第 4.1 节：
	## 转身有过渡、不能瞬间翻面）。整段只有 0.1 s。
	_skin_canvas_transform = _skin_figure_transform(ground)
	var flip_width: float = 1.0 if _has_body_skin() else flip_width_ratio()
	var showing_front: bool = state.facing >= 0.0

	var body := Color(LEATHER.r, LEATHER.g, LEATHER.b, alpha)
	var rim := Color(RIM.r, RIM.g, RIM.b, alpha * 0.75)
	var joint := Color(JOINT.r, JOINT.g, JOINT.b, alpha)

	var bob: float = walk_body_offset(height)
	var hip := Vector2(ground.x, ground.y - height * HIP_RATIO + bob)
	var shoulder := Vector2(ground.x, ground.y - height * SHOULDER_RATIO + bob)
	var half_w: float = half_width_px(height, flip_width)
	var shoulder_half_w: float = shoulder_half_width_px(height, flip_width)

	# 完整袍摆保留原图轮廓；其余影人沿用髋 → 膝 → 脚的分件链。
	var knee_out: float = height * (0.03 + 0.11 * clampf(state.stance, 0.0, 1.0)) * flip_width
	var continuous_lower: bool = (
		_has_body_skin() and _skins[str(_body_skin_id())]["parts"].has("lower_body")
		and state.leg_spread <= .01 and not seated
	)
	if continuous_lower:
		_draw_walking_robe(hip, height, alpha)
	for side in [-1.0, 1.0]:
		if continuous_lower:
			continue
		var step: Vector2 = walk_step_offset(side, height)
		var knee := Vector2(
			hip.x + side * knee_out + step.x * .69, ground.y - height * 0.22 + step.y * .5
		)
		var foot := Vector2(
			ground.x + side * half_w * 0.95 + step.x, ground.y + step.y
		)
		if state.leg_spread > 0.0:
			var spread: float = state.leg_spread
			knee = hip + Vector2(side * height * lerpf(.04, .23, spread), height * .15)
			foot = hip + Vector2(side * height * lerpf(.10, .40, spread), height * lerpf(.44, .20, spread))
		if seated:
			knee = hip + Vector2(pose_reference_facing() * height * 0.22, side * height * 0.012)
			foot = knee + Vector2(pose_reference_facing() * height * 0.025, height * 0.22)
		if _has_body_skin():
			var leg: String = "left" if side < 0.0 else "right"
			_draw_skin_segment(leg + "_thigh", hip, knee, flip_width, alpha)
			_draw_skin_segment(leg + "_calf", knee, foot, flip_width, alpha)
			_draw_skin_joint(knee, height * 0.021, alpha)
		else:
			draw_line(hip, knee, body, height * 0.048)
			draw_line(knee, foot, body, height * 0.044)
			draw_circle(knee, height * 0.021, joint)

	# 躯干
	_skin_canvas_transform = _skin_figure_transform(ground) * upper_transform()
	_draw_skin_accessories(ground, height, alpha)
	var torso := PackedVector2Array(
		[
			Vector2(hip.x - half_w * 0.82, hip.y),
			Vector2(shoulder.x - half_w, shoulder.y),
			Vector2(shoulder.x + half_w, shoulder.y),
			Vector2(hip.x + half_w * 0.82, hip.y),
		]
	)
	if _has_body_skin():
		_draw_skin_segment("torso", shoulder, hip, flip_width, alpha)
	else:
		draw_colored_polygon(torso, body)
		draw_polyline(torso + PackedVector2Array([torso[0]]), rim, 2.0)

	# 双臂：肩 → 肘 → 腕。手角 0 = 自然垂下，+π/2 = 水平前伸，+π = 举过头顶
	_left_wrist = _draw_arm(
		Vector2(shoulder.x - shoulder_half_w, shoulder.y),
		state.hand_angle.x,
		false,
		height,
		body,
		joint,
		flip_width
	)
	_right_wrist = _draw_arm(
		Vector2(shoulder.x + shoulder_half_w, shoulder.y),
		state.hand_angle.y,
		true,
		height,
		body,
		joint,
		flip_width
	)

	# 头：正反两面各有自己的标记，换面因此是可核对的，而不是只靠宽度变化猜
	var head_center: Vector2 = _head_centre_local(shoulder, height)
	var head_r: float = height * HEAD_RADIUS_RATIO if _has_body_skin() else head_radius_px(height)
	draw_set_transform_matrix(_skin_canvas_transform)
	_draw_head(head_center, head_r, showing_front, body, rim, alpha)
	draw_set_transform(Vector2.ZERO)
	_skin_canvas_transform = Transform2D.IDENTITY


## 同一张完整袍摆从静止过渡到迈步，腰线固定、下摆两侧反相；不切换站姿贴图。
func _draw_walking_robe(hip: Vector2, height: float, alpha: float) -> void:
	var id: int = _body_skin_id()
	var skin: Dictionary = _skins[str(id)]
	var ratios: Array = skin["lower_body_size_ratio"]
	var size := Vector2(float(ratios[0]), float(ratios[1])) * height
	if puppet_state.walk_amount <= 0.0:
		_draw_skin_tile(id, "lower_body", hip, 0.0, size, alpha)
		return
	var part: Dictionary = skin["parts"]["lower_body"]
	var rect: Array = part["rect"]
	var pivot := Vector2(part["pivot"][0], part["pivot"][1]) / 512.0
	var texture: Texture2D = SKIN_TEXTURES[id] if id < SKIN_TEXTURES.size() else EXTRA_SKIN_TEXTURES[id]
	var texture_size := Vector2(texture.get_size())
	var left_step: Vector2 = walk_step_offset(-1, height)
	var right_step: Vector2 = walk_step_offset(1, height)
	draw_set_transform_matrix(_skin_canvas_transform)
	# 8×4 小网格足以表达袍摆/鞋的交替位移，共享边顶点避免缝隙。
	for row in range(4):
		for column in range(8):
			var points := PackedVector2Array()
			var uvs := PackedVector2Array()
			for corner: Vector2 in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
				var uv := Vector2((column + corner.x) / 8.0, (row + corner.y) / 4.0)
				var point: Vector2 = hip + (uv - pivot) * size
				var depth: float = clampf((point.y - hip.y) / (height * HIP_RATIO), 0.0, 1.0)
				var side_blend: float = smoothstep(-height * .12, height * .12, point.x - hip.x)
				var step: Vector2 = left_step.lerp(right_step, side_blend)
				points.append(point + step * depth * depth)
				uvs.append((Vector2(rect[0],rect[1]) + uv * Vector2(rect[2],rect[3])) / texture_size)
			draw_polygon(points, PackedColorArray([Color(1,1,1,alpha)]), uvs, texture)
	draw_set_transform(Vector2.ZERO)


## 一条手臂。手角以「自然垂下」为 0，向抬手方向为正；屏幕角口径见 `arm_direction()`。
## 几何全部走 `arm_elbow()` / `arm_wrist()`，与 `hand_screen_position()` 共用一条链——
## 手画在哪，问道具落点时就会得到同一个点。
func _draw_arm(
	shoulder: Vector2,
	angle: float,
	right_side: bool,
	height: float,
	body: Color,
	joint: Color,
	flip_width: float
) -> Vector2:
	var bend: float = puppet_state.elbow_angle.y if right_side else puppet_state.elbow_angle.x
	var points: Dictionary = UpperPose.arm_points(shoulder, angle, bend, right_side, height)
	var elbow: Vector2 = points.elbow
	var wrist: Vector2 = points.wrist
	# 翻面压扁时手臂同步变细，避免整台只剩两根粗线还挂在外面
	var thickness: float = maxf(flip_width, 0.25)
	if _has_body_skin():
		var side: String = "right" if right_side else "left"
		_draw_skin_segment(side + "_upper_arm", shoulder, elbow, thickness, body.a)
		_draw_skin_segment(side + "_forearm", elbow, wrist, thickness, body.a)
		_draw_skin_joint(elbow, height * 0.020 * thickness, body.a)
		_draw_skin_hand(
			side + "_hand", wrist, points.direction, height, thickness, right_side, body.a
		)
		return _skin_canvas_transform * wrist
	draw_line(shoulder, elbow, body, height * 0.042 * thickness)
	draw_line(elbow, wrist, body, height * 0.038 * thickness)
	draw_circle(elbow, height * 0.020 * thickness, joint)
	draw_circle(wrist, height * 0.024 * thickness, Color(0.93, 0.86, 0.70, joint.a))
	return wrist


## 本帧画出的两只手腕位置，供竹签连线取点。
var _left_wrist: Vector2 = Vector2.ZERO
var _right_wrist: Vector2 = Vector2.ZERO


## 头：正面画五官、反面只留一道背缝，两者在灰度下也能区分。
func _draw_head(
	centre: Vector2, radius: float, showing_front: bool, body: Color, rim: Color, alpha: float
) -> void:
	var skin_id: int = skin_override if skin_override >= 0 else puppet_state.head_id
	if _skins.has(str(skin_id)) and (skin_override >= 0 or skin_id < SKIN_TEXTURES.size()):
		var skin: Dictionary = _skins[str(skin_id)]
		var size: float = radius * float(skin["head_size_per_radius"])
		var facing: float = 1.0 if showing_front else -1.0
		if _has_body_skin():
			facing = float(_skins[str(_body_skin_id())]["reference_facing"])
		var mirror: float = facing / float(skin["reference_facing"])
		_draw_skin_tile(
			skin_id, "head", centre, puppet_state.head_tilt, Vector2(size * mirror, size), alpha
		)
		return
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
			draw_rect(
				Rect2(
					centre.x - radius * 1.15, centre.y - radius * 1.15, radius * 2.30, radius * 0.46
				),
				accent
			)

	if showing_front:
		# 正面：两只眼 + 鼻尖楔形
		draw_circle(
			centre + Vector2(-radius * 0.34, -radius * 0.14),
			radius * 0.13,
			Color(0.10, 0.07, 0.05, alpha)
		)
		draw_circle(
			centre + Vector2(radius * 0.30, -radius * 0.14),
			radius * 0.13,
			Color(0.10, 0.07, 0.05, alpha)
		)
		var nose := PackedVector2Array(
			[
				centre + Vector2(radius * 0.82, -radius * 0.10),
				centre + Vector2(radius * 1.42, radius * 0.40),
				centre + Vector2(radius * 0.82, radius * 0.46),
			]
		)
		draw_colored_polygon(nose, body)
	else:
		# 反面：一道竖背缝 + 缝上的小签钉
		draw_line(
			centre + Vector2(0.0, -radius * 0.72), centre + Vector2(0.0, radius * 0.96), rim, 2.0
		)
		draw_circle(centre + Vector2(0.0, -radius * 0.72), radius * 0.16, rim)


## 美术适配只读状态，保持分件枢轴、接口签名和动作数据。
func _read_skins() -> Dictionary:
	var parsed: Variant = SKIN_MANIFEST.data
	if not parsed is Dictionary or parsed.get("version", 0) != 1:
		push_error("影人美术清单无效：%s" % SKIN_MANIFEST_PATH)
		return {}
	var skins: Dictionary = {}
	var characters: Dictionary = parsed.get("characters", {}).duplicate()
	characters.merge(IMMORTAL_MANIFEST.data.get("characters", {}))
	for character: String in characters:
		var skin: Dictionary = characters[character].duplicate()
		var parts: Dictionary = skin.get("parts", {})
		var id: int = int(skin.get("skin_id", skin.get("puppet_id", -1)))
		if (
			id < 0
			or (id >= SKIN_TEXTURES.size() and not EXTRA_SKIN_TEXTURES.has(id))
			or float(skin.get("head_size_per_radius", 0.0)) <= 0.0
		):
			push_error("影人美术定义无效：%s (%s)" % [character, SKIN_MANIFEST_PATH])
			continue
		var valid: bool = true
		if parts.has("lower_body"):
			var lower_size: Array = skin.get("lower_body_size_ratio", [])
			var lower: Dictionary = parts["lower_body"]
			if lower_size.size() != 2 or lower.get("rect", []).size() != 4 or lower.get("pivot", []).size() != 2:
				push_error("影人袍摆定义无效：%s" % character)
				valid = false
			for value: Variant in lower_size:
				if not is_finite(float(value)) or float(value) <= 0.0:
					push_error("影人袍摆尺寸无效：%s" % character)
					valid = false
		var shoulder_width: float = float(skin.get("shoulder_half_width_ratio", HALF_W_RATIO))
		if not is_finite(shoulder_width) or shoulder_width <= 0.0 or shoulder_width > 0.25:
			push_error("影人肩间距无效：%s (%s)" % [character, SKIN_MANIFEST_PATH])
			valid = false
		for part_name: String in [
			"head",
			"torso",
			"left_upper_arm",
			"left_forearm",
			"left_hand",
			"right_upper_arm",
			"right_forearm",
			"right_hand",
			"left_thigh",
			"left_calf",
			"right_thigh",
			"right_calf"
		]:
			var part: Dictionary = parts.get(part_name, {})
			if (
				part.get("rect", []).size() != 4
				or part.get("pivot", []).size() != 2
				or float(part.get("axis_pixels", 0.0)) <= 0.0
			):
				push_error("影人分件无效：%s/%s" % [character, part_name])
				valid = false
			var width_scale: float = float(part.get("width_scale", 1.0))
			if not is_finite(width_scale) or width_scale <= 0.0 or width_scale > 2.0:
				push_error("影人分件宽度无效：%s/%s" % [character, part_name])
				valid = false
		if valid:
			skin["joint_color"] = Color(
				skin.get("joint_hex", parsed["named_samples"]["gold_joint"]["hex"])
			)
			skin["ink_color"] = Color(skin.get("ink_hex", parsed["named_samples"]["ink"]["hex"]))
			skins[str(id)] = skin
	return skins


func _has_body_skin() -> bool:
	return _skins.has(str(_body_skin_id()))


func _body_skin_id() -> int:
	return skin_override if skin_override >= 0 else puppet_state.puppet_id


## 饰带随躯干，锡杖随右腕；同一个翻面矩阵用于实体、投影和附件。
func _draw_skin_accessories(ground: Vector2, height: float, alpha: float) -> void:
	if not _has_body_skin():
		return
	var id: int = _body_skin_id()
	var skin: Dictionary = _skins[str(id)]
	var shoulder := ground + Vector2(0.0, -height * SHOULDER_RATIO + walk_body_offset(height))
	if skin["parts"].has("ribbons"):
		var ribbon_size: float = height * float(skin.get("ribbons_size_ratio", 0.65))
		var ribbon_rotation: float = puppet_state.head_tilt if skin.has("accessories") else 0.0
		var ribbon_origin: Vector2 = shoulder + Vector2(-height * 0.04, -height * 0.10)
		if skin.has("accessories"):
			var neck: Vector2 = shoulder + Vector2(0, -height * .04)
			ribbon_origin = neck + (ribbon_origin - neck).rotated(ribbon_rotation)
		_draw_skin_tile(
			id, "ribbons", ribbon_origin, ribbon_rotation, Vector2.ONE * ribbon_size, alpha
		)
	if skin["parts"].has("staff"):
		var wrist: Vector2 = (
			UpperPose
			. arm_points(
				shoulder + Vector2(shoulder_half_width_px(height, 1.0), 0),
				puppet_state.hand_angle.y,
				puppet_state.elbow_angle.y,
				true,
				height
			)
			. wrist
		)
		var staff_size: float = height * float(skin["staff_size_ratio"])
		var upper_matrix: Transform2D = _skin_canvas_transform
		_skin_canvas_transform = _skin_figure_transform(ground)
		wrist = upper_transform() * wrist
		var staff_rotation: float = float(skin.get("staff_rotation_rad", 0.0))
		_draw_skin_tile(id, "staff", wrist, staff_rotation, Vector2.ONE * staff_size, alpha)
		_skin_canvas_transform = upper_matrix


func _draw_skin_tile(
	skin_id: int, part_name: String, at: Vector2, rotation_rad: float, size: Vector2, alpha: float
) -> void:
	var part: Dictionary = _skins[str(skin_id)]["parts"][part_name]
	var rect: Array = part["rect"]
	var pivot: Array = part["pivot"]
	var source := Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
	var offset := Vector2(float(pivot[0]) / source.size.x, float(pivot[1]) / source.size.y)
	var tile_transform := Transform2D(
		rotation_rad, Vector2(size.x / source.size.x, size.y / source.size.y), 0.0, at
	)
	draw_set_transform_matrix(_skin_canvas_transform * tile_transform)
	draw_texture_rect_region(
		SKIN_TEXTURES[skin_id] if skin_id < SKIN_TEXTURES.size() else EXTRA_SKIN_TEXTURES[skin_id],
		Rect2(-offset * source.size, source.size),
		source,
		Color(1.0, 1.0, 1.0, alpha)
	)
	draw_set_transform(Vector2.ZERO)


func _draw_skin_segment(
	part_name: String, start: Vector2, end: Vector2, width_ratio: float, alpha: float
) -> void:
	var skin_id: int = _body_skin_id()
	var skin: Dictionary = _skins[str(skin_id)]
	var part: Dictionary = skin["parts"][part_name]
	var length: float = start.distance_to(end)
	var tile_length: float = length * 512.0 / float(part["axis_pixels"])
	_draw_skin_tile(
		skin_id,
		part_name,
		start,
		(end - start).angle() - PI * 0.5,
		Vector2(tile_length * width_ratio * float(part.get("width_scale", 1.0)), tile_length),
		alpha
	)


func _draw_skin_hand(
	part_name: String,
	wrist: Vector2,
	direction: Vector2,
	height: float,
	thickness: float,
	right_side: bool,
	alpha: float
) -> void:
	var skin: Dictionary = _skins[str(_body_skin_id())]
	var size: float = height * float(skin["hand_size_ratio"])
	var mirror: float = 1.0 if right_side else -1.0
	var side: String = "right" if right_side else "left"
	if _held_prop_hand == side and skin["parts"].has(part_name + "_grip"):
		part_name += "_grip"
	_draw_skin_tile(
		_body_skin_id(),
		part_name,
		wrist,
		direction.angle() - PI * 0.5,
		Vector2(size * mirror * thickness, size),
		alpha
	)


func _draw_skin_joint(at: Vector2, radius: float, alpha: float) -> void:
	var skin: Dictionary = _skins[str(_body_skin_id())]
	var ink: Color = skin["ink_color"]
	var gold: Color = skin["joint_color"]
	ink.a = alpha
	gold.a = alpha
	draw_set_transform_matrix(_skin_canvas_transform)
	draw_circle(at, radius, ink)
	draw_circle(at, radius * 0.72, gold)
	draw_circle(at, radius * 0.20, ink)
	draw_set_transform(Vector2.ZERO)


## 三根竹签：一根连胸签、两根连手，全部汇到签手的手部。
## 这是「借签操演」在画面上唯一的直接证据（PRD 第 4 节）。
func _draw_sticks(ground: Vector2, height: float, alpha: float) -> void:
	_left_wrist = hand_screen_position("left")
	_right_wrist = hand_screen_position("right")
	if render_mode == RenderMode.ENTITY:
		_draw_bamboo(Vector2(ground.x, ground.y - height * 0.62), hand_anchor - Vector2(0, 28), 3.7)
		_draw_bamboo(_left_wrist, hand_anchor + Vector2(-18, -22), 2.5)
		_draw_bamboo(_right_wrist, hand_anchor + Vector2(18, -22), 2.5)
		return
	var color := Color(STICK.r, STICK.g, STICK.b, alpha * 0.95)
	var chest: Vector2 = Vector2(ground.x, ground.y - height * 0.62)
	draw_line(chest, hand_anchor, color, 4.0)
	draw_line(_left_wrist, hand_anchor, color, 3.0)
	draw_line(_right_wrist, hand_anchor, color, 3.0)


func _draw_bamboo(start: Vector2, end: Vector2, width: float) -> void:
	draw_line(start, end, Color("#493824"), width + 1.4, true)
	draw_line(start, end, Color("#be995e"), width, true)
	var normal: Vector2 = (end - start).normalized().orthogonal()
	draw_line(start + normal * 0.6, end + normal * 0.6, Color(0.88, 0.76, 0.49, 0.55), 0.6, true)
	for blend: float in [0.28, 0.61, 0.85]:
		var knot: Vector2 = start.lerp(end, blend)
		draw_line(knot - normal * width, knot + normal * width, Color("#79613b"), 1.3, true)
	draw_circle(start, width * 1.35, Color("#6b4b28"))
	draw_circle(start, width * 0.6, Color("#d4b578"))


## 胸签热区的可视化。前四关允许出现融入画面的操作图标（PRD 第 3、8 节）。
func _draw_chest_tag() -> void:
	var centre: Vector2 = chest_tag_screen()
	if render_mode == RenderMode.ENTITY:
		# 融入签手操作的细刻线；保留原命中范围与落点。
		for i in range(8):
			draw_arc(
				centre,
				PuppetControllerScript.CHEST_TAG_RADIUS_PX,
				TAU * i / 8.0,
				TAU * i / 8.0 + 0.16,
				6,
				Color(0.73, 0.51, 0.24, 0.36),
				1.4,
				true
			)
		draw_circle(centre, 4.0, Color(0.83, 0.68, 0.42, 0.8))
		return
	draw_arc(
		centre,
		PuppetControllerScript.CHEST_TAG_RADIUS_PX,
		0.0,
		TAU,
		40,
		Color(0.95, 0.55, 0.20, 0.75),
		3.0
	)
	draw_circle(centre, 7.0, Color(0.99, 0.80, 0.42, 0.95))
