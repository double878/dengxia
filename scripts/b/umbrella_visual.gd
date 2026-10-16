extends Node2D
class_name UmbrellaVisual
## 实体与透射复用一套几何，各自读取相应显示节点的腕点。
##
## 造型按用户 2026-10-16 参考图重做：**象牙白伞面 + 淡金伞骨 + 淡金镂空檐带 +
## 深棕木杆 + 露出的伞尖**。参考图是一把**完整的伞**（伞杆一直伸到伞柄球头），
## 这里只画「手托住的那一段」——伞杆终止于腕点；球头落在手以下，手握持的姿势里
## 本来就看不见，不画。
##
## 🔴 尺寸口径照旧：`LIFT` / `RADIUS` / `DROP` 三个常量**没有改动**。A 侧
## `level1_a_scene.gd` 的 `CANOPY_*` 与 `tests/a/test_umbrella.gd` 的「伞面盖住头」
## 断言都读它们，一改就四处失信。参考图的伞面比 `DROP` 更深，多出来的那截做成
## **向下垂的镂空檐带**（`_drop_of_band()`）——于是那条断言约束的仍是伞面**主体**。

const LIFT: float = 0.44
const RADIUS: float = 0.45
const DROP: float = 0.20
## 檐带在伞面主体下沿之下再垂这么多（相对 `DROP`）。
## 参考图伞面高:半宽 ≈ 210:308 = 0.68；本文件 (1 + BAND_DROP_RATIO) × DROP / RADIUS
## = (1 + 0.45) × 0.20 / 0.45 ≈ 0.644，两者接近（差的那点是 `DROP` 受断言压住的）。
const BAND_DROP_RATIO: float = 0.45
## 伞面轮廓 u = sin(πv/2)^POWER 的幂次，按参考图逐行宽度反推：正圆在 v=0.38 处
## 半宽已到 0.92，参考图只有 0.65 —— 它比正圆扁得多。
const PROFILE_POWER: float = 0.76
## 上轮廓采样段数（每侧）。16 段在伞只有几百像素宽时已看不出折线。
const OUTLINE_SEGMENTS: int = 16
## 伞骨每侧条数。参考图正面可见左右各 4 条（逐行扫描出的暗线簇数）。
const RIBS_PER_SIDE: int = 4
## 檐带镂空格数（每侧）。参考图整圈约 50 格，但那是 617 px 伞面宽下的 12 px 周期，
## 折算到本文件每格只有个位数像素、读不出形状，因此减到每侧 10 格 ——
## **这是简化，不是 1:1 复刻**。
const BAND_CELLS: int = 10

## —— 配色：以参考图实测为基准，再按**幕布透射**校正 ——
## 🔴 参考图是照片，本项目是**皮影**：玩家看到的是幕布（实测亮度 ≈ 0.78）乘上一张
##    透射率贴图。象牙白伞面（参考图 0.85~0.93）透射后约 0.72，**只比幕布暗 7%**，
##    画面上等于看不见（2026-10-16 实测）。因此伞面整体压暗一档到中调暖米，
##    并用深色轮廓把形体「立」起来——这是**为幕布可读性做的取舍**，不是配色失误。
const PAPER_TOP: Color = Color("#cfc4a4")
const PAPER_RIM: Color = Color("#9d8e6f")
## 伞面轮廓（上拱 + 檐口）。皮影靠深色边把形体从幕布上分出来。
const PAPER_EDGE: Color = Color("#6b5533")
## 淡香槟金：参考图金色像素的主簇是 `#D0C098` / `#C8B890` / `#C0B080` / `#B8A070`。
const GOLD: Color = Color("#c9b98d")
const GOLD_DEEP: Color = Color("#9a8250")
const GOLD_LIGHT: Color = Color("#e3d7ad")
## 伞骨专用：比 `GOLD` 深一档。伞面在幕布上本来就淡（见上），**伞的形体靠骨架线读**，
## 所以骨要够深够粗；参考图的金线暗部实测 `#B09860`，这里再压一档。
const GOLD_RIB: Color = Color("#8b7546")
## 木杆：参考图实测 `#5C3105` ~ `#633402`（比旧版的 `#8a5a2b` 深得多）。
const WOOD: Color = Color("#5c3306")
const WOOD_LIGHT: Color = Color("#7d4c17")
const WOOD_EDGE: Color = Color("#331c03")

var views: Array = []
var umbrella: UmbrellaController = null


func _view(id: int) -> PlaceholderPuppet:
	if id < 0 or id >= views.size():
		return null
	var view: PlaceholderPuppet = views[id]
	return view if view.visible and view.puppet_state != null else null


func geometry() -> Dictionary:
	if umbrella == null:
		return {}
	var holder: PlaceholderPuppet = _view(umbrella.holder_id_of())
	if holder == null:
		return {}
	var hand: Vector2 = holder.hand_screen_position(umbrella.holder_hand_of())
	var height: float = holder.figure_px_height()
	var flip: float = holder.flip_width_ratio()
	if umbrella.handing_off:
		var previous: PlaceholderPuppet = _view(umbrella.handoff_from_id())
		if previous != null:
			var blend: float = umbrella.handoff_blend()
			hand = previous.hand_screen_position(umbrella.handoff_from_hand()).lerp(hand, blend)
			height = lerpf(previous.figure_px_height(), height, blend)
			flip = lerpf(previous.flip_width_ratio(), flip, blend)
	return {"hand": hand, "height": height, "flip": flip}


## 轮廓正函数：v（0 = 伞顶、1 = 伞面主体下沿）→ u（0 = 中轴、1 = 伞缘）。
static func profile_u(v: float) -> float:
	return pow(sin(clampf(v, 0.0, 1.0) * PI * 0.5), PROFILE_POWER)


## 轮廓反函数：u → v。伞骨端点与「伞缘在哪一高度」都按它算，与画出来的轮廓同源。
static func profile_v(u: float) -> float:
	return (2.0 / PI) * asin(pow(clampf(u, 0.0, 1.0), 1.0 / PROFILE_POWER))


func _draw() -> void:
	var data: Dictionary = geometry()
	if data.is_empty():
		return
	var hand: Vector2 = data["hand"]
	var height: float = data["height"]
	var flip: float = data["flip"]
	var canopy: Vector2 = hand + Vector2(0, -height * LIFT)
	var radius: float = height * RADIUS * flip
	var drop: float = height * DROP
	# 先伞面与檐带，最后伞杆——参考图里伞杆压在伞面前面。
	_draw_canopy(canopy, radius, drop, height)
	_draw_band(canopy, radius, drop, height)
	_draw_shaft(hand, canopy, drop, height, flip)


## 伞面主体：上拱 + 檐口水平线 = 3D 圆顶的正交投影（弓形）。
## 逐顶点色让顶端最亮、伞缘背光最暗，替代参考图里那层绢的漫射。
func _draw_canopy(canopy: Vector2, radius: float, drop: float, height: float) -> void:
	var face := PackedVector2Array()
	var colors := PackedColorArray()
	for i in range(-OUTLINE_SEGMENTS, OUTLINE_SEGMENTS + 1):
		var u: float = float(i) / float(OUTLINE_SEGMENTS)
		var v: float = profile_v(absf(u))
		face.append(canopy + Vector2(u * radius, v * drop))
		colors.append(PAPER_TOP.lerp(PAPER_RIM, clampf(v, 0.0, 1.0)))
	draw_polygon(face, colors)
	# 伞面轮廓：上拱一条折线 + 下沿一条直线（`draw_polygon` 闭合的那条边）。
	var edge_width: float = maxf(height * 0.0050, 1.0)
	draw_polyline(face, PAPER_EDGE, edge_width, true)
	draw_line(face[0], face[face.size() - 1], PAPER_EDGE, edge_width, true)
	# 伞骨：从伞顶辐射到各自与轮廓的交点。中心那根是伞杆本身，不重复画。
	# 🔴 两侧的落差都往**下**加（`+reach` 与 `+(-x, y)`）——写成 `canopy - reach`
	#    会让左半边伞骨翻到伞面上方去（2026-10-16 实测踩到）。
	var rib_width: float = maxf(height * 0.0076, 1.2)
	for k in range(1, RIBS_PER_SIDE + 1):
		var u: float = float(k) / float(RIBS_PER_SIDE)
		var reach := Vector2(u * radius, profile_v(u) * drop)
		draw_line(canopy, canopy + reach, GOLD_RIB, rib_width, true)
		draw_line(canopy, canopy + Vector2(-reach.x, reach.y), GOLD_RIB, rib_width, true)


## 檐带：挂在伞面主体下沿之下的一圈镂空花边。
## 镂空靠「不画」实现——幕布透射用 `mix(vec3(1.0), encoded, alpha)` + `blend_mul`，
## 没画到的地方 alpha=0 就是真透光（`puppet_transmission.gdshader`）。
func _draw_band(canopy: Vector2, radius: float, drop: float, height: float) -> void:
	var hang: float = drop * BAND_DROP_RATIO
	var line_width: float = maxf(height * 0.0034, 1.0)
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	for i in range(-BAND_CELLS, BAND_CELLS + 1):
		var u: float = float(i) / float(BAND_CELLS)
		var rim: Vector2 = canopy + Vector2(u * radius, drop)
		# 下沿走荷叶边：格心垂到底、格与格之间收一点，形成一圈齿。
		upper.append(rim)
		lower.append(rim + Vector2(0.0, hang if i % 2 != 0 else hang * 0.60))
	draw_polyline(upper, GOLD, line_width, true)
	draw_polyline(lower, GOLD_DEEP, line_width * 1.5, true)
	# 每格两侧的立柱
	for i in range(-BAND_CELLS, BAND_CELLS + 1):
		var u: float = float(i) / float(BAND_CELLS)
		var rim: Vector2 = canopy + Vector2(u * radius, drop)
		draw_line(rim, rim + Vector2(0.0, hang * 0.92), GOLD, line_width, true)
	# 格心的小金环：环内不画，露出的就是镂空
	for i in range(-BAND_CELLS, BAND_CELLS):
		var u: float = (float(i) + 0.5) / float(BAND_CELLS)
		var rim: Vector2 = canopy + Vector2(u * radius, drop)
		draw_arc(
			rim + Vector2(0.0, hang * 0.44),
			hang * 0.28,
			0.0,
			TAU,
			14,
			GOLD_LIGHT,
			line_width,
			true
		)


## 伞杆与伞尖。参考图的伞杆竖直、上细下粗，伞尖在伞面之上露出一小截木柱。
func _draw_shaft(
	hand: Vector2, canopy: Vector2, drop: float, height: float, flip: float
) -> void:
	var squeeze: float = maxf(flip, 0.25)
	draw_line(hand, canopy, WOOD_EDGE, height * 0.036 * squeeze, true)
	draw_line(hand, canopy, WOOD, height * 0.023 * squeeze, true)
	# 一道偏左的受光高光，让圆杆不显得是一块平色
	var gleam: Vector2 = Vector2(-height * 0.0055 * squeeze, 0.0)
	draw_line(hand + gleam, canopy + gleam, WOOD_LIGHT, height * 0.0062 * squeeze, true)
	# 伞尖：露在伞面之上的一小截，带一个顶头
	var tip: Vector2 = canopy - Vector2(0.0, drop * 0.22)
	draw_line(tip, canopy, WOOD_EDGE, height * 0.031 * squeeze, true)
	draw_line(tip, canopy, WOOD, height * 0.018 * squeeze, true)
	draw_circle(tip, height * 0.0165 * squeeze, WOOD_EDGE)
	draw_circle(tip, height * 0.0115 * squeeze, WOOD)
