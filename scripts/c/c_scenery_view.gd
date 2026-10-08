extends Node2D
class_name CSceneryView
## C 侧布景画面节点：把 `CSceneryDef` 的**背景环境**画出来（柳树、拱桥……）。
##
## ⚠️ 职责边界（不越界的三条）：
##   1. **只读**布景数据，不写任何 State。布景不参与判定（PRD 第 6 节：布景是演出调度，
##      不是可交互物件）。
##   2. **不进记录**：不产生事件、不进 CSnapshot、不被 Recorder 采集。录制回放完全不涉及本类。
##   3. **不随灯影缩放**：本节点**不得**挂在影子的缩放根（如 B 的 `_shadow_root`）之下。
##      TECH_DESIGN 第 3.2 节的灯距缩放只作用于「在场影人及挂起影人」；PRD 第 6 节
##      第 3 关明写「影子先缩小**经过布景**」——影子穿过布景，说明布景静止。
##
## 画面层级：布景应**画在幕布之上、影人之下**。调用方负责把本节点加到正确的位置
## （见类尾 `usage_hint()`）；本类不自己去改父节点。
##
## 坐标口径：舞台归一化 0–1，映射到 `stage_size`（与影人同一坐标系）。
## 只支持**水平平移**（`pan_x`）——景物不能上下移动/缩放/旋转（用户 2026-10-08 定案）。

const DefScript := preload("res://scripts/c/c_scenery_def.gd")

## 颜色：取自 TECH_DESIGN 第 5.2 节项目色板。布景是**背景**，整体压暗、降饱和，
## 免得抢了幕前影人的视觉重心。
const COLOR_WILLOW: Color = Color("#34866A")        ## 皮影绿（小青主色，也用于布景局部）
const COLOR_WILLOW_DARK: Color = Color("#27503F")
const COLOR_BRIDGE: Color = Color("#8a5a2b")        ## 木褐（比「幕后木褐 #3A2A18」亮，作桥可见）
const COLOR_BRIDGE_LIGHT: Color = Color("#b07a41")
const BACKDROP_ALPHA: float = 0.55                   ## 整体透明度：背景不抢戏

## 舞台映射区。必须与影人用**同一套**（由调用方注入，避免两处各写一个数）。
@export var stage_origin: Vector2 = Vector2.ZERO
@export var stage_size: Vector2 = Vector2(1920.0, 1080.0)

var _def: CSceneryDef = null


## 装载一关的布景。传 null 视为空布景（画空白，不报错——第 2~5 关还没做）。
func setup(scenery_def: CSceneryDef) -> void:
	_def = scenery_def
	queue_redraw()


## 水平平移（**唯一**允许的位移；第 1 关恒 0）。
## 之所以做成方法而不是直接暴露变量，是为了留着将来「布景随剧情左右滑动」的接口，
## 而实现里除水平偏移外**不可能**出现别的位移。
func set_pan(item_id: String, pan_x: float) -> void:
	if _def == null:
		return
	for item in _def.items:
		if str(item.get("id", "")) == item_id:
			item["pan_x"] = pan_x
			queue_redraw()
			return


## 归一化 → 像素。**与影人同一公式**（PlaceholderPuppet.stage_to_screen）；
## 两处必须一致，否则布景与影人会错位。
func _to_px(nx: float, ny: float) -> Vector2:
	return Vector2(
		stage_origin.x + nx * stage_size.x,
		stage_origin.y + ny * stage_size.y)


func _draw() -> void:
	if _def == null:
		return
	for item in _def.items:
		var kind: String = str(item.get("kind", ""))
		var x: float = float(item.get("anchor_x", 0.0)) + float(item.get("pan_x", 0.0))
		var y: float = float(item.get("anchor_y", DefScript.ANCHOR_Y))
		var params: Dictionary = item.get("params", {})
		match kind:
			DefScript.KIND_WILLOW:
				_draw_willow(x, y, params)
			DefScript.KIND_ARCH_BRIDGE:
				_draw_arch_bridge(x, y, params)
			_:
				# 未知种类不静默吞掉：这类 bug 在画面上表现为「布景少了东西」，
				# 排查时最怕它一声不吭。push_warning 让 --headless 也能看见。
				push_warning("CSceneryView: 未知布景种类 %s（id=%s）" % [kind, str(item.get("id", ""))])


## 柳树：树干 + 向左上展开的树冠。
## 树干底部落在接地线 anchor_y 上（用户 2026-10-08 选「接地线对齐」方案 A）。
func _draw_willow(anchor_x: float, anchor_y: float, params: Dictionary) -> void:
	var base: Vector2 = _to_px(anchor_x, anchor_y)
	var trunk_h: float = float(params.get("trunk_height", 0.20)) * stage_size.y
	var crown_rx: float = float(params.get("crown_radius_x", 0.075)) * stage_size.y
	var crown_ry: float = float(params.get("crown_radius_y", 0.055)) * stage_size.y
	var bias_x: float = float(params.get("crown_bias_x", -0.02)) * stage_size.y

	var top: Vector2 = base + Vector2(0.0, -trunk_h)
	var crown: Vector2 = top + Vector2(bias_x, 0.0)

	# 树冠：三团叠加的椭圆，做出「枝叶成团」的剪影感（程序化占位，后由贴图替换）
	var leaf: Color = COLOR_WILLOW
	leaf.a = BACKDROP_ALPHA
	var leaf_dark: Color = COLOR_WILLOW_DARK
	leaf_dark.a = BACKDROP_ALPHA

	# 垂枝：柳树的枝条向下垂（与普通树的「向上分叉」区分）
	for i in 5:
		var t := float(i) / 4.0
		var spread := lerpf(-crown_rx, crown_rx, t)
		var start: Vector2 = crown + Vector2(spread * 0.7, -crown_ry * 0.2)
		var end: Vector2 = start + Vector2(spread * 0.35, crown_ry * 1.2)
		draw_line(start, end, leaf_dark, 2.0)

	draw_circle(crown, crown_ry, leaf)
	draw_circle(crown + Vector2(-crown_rx * 0.55, crown_ry * 0.15), crown_ry * 0.78, leaf)
	draw_circle(crown + Vector2(crown_rx * 0.55, crown_ry * 0.15), crown_ry * 0.78, leaf)
	draw_circle(crown + Vector2(0.0, -crown_ry * 0.5), crown_ry * 0.82, leaf)

	# 树干
	var trunk_w: float = maxf(6.0, stage_size.y * 0.008)
	var trunk: Color = COLOR_BRIDGE
	trunk.a = BACKDROP_ALPHA
	draw_line(base, top, trunk, trunk_w)


## 拱桥：从 anchor_x 起拱，到 `arch_end_x` 到达拱顶高度，之后**水平延伸出画**。
## 用户 2026-10-08：「拱桥从 0.72 开始……不用画出完整拱桥，只画一半，平行延伸到画布外」。
func _draw_arch_bridge(anchor_x: float, anchor_y: float, params: Dictionary) -> void:
	var foot: Vector2 = _to_px(anchor_x, anchor_y)
	var end_x: float = float(params.get("arch_end_x", 1.0))
	var rise: float = float(params.get("deck_rise", 0.10)) * stage_size.y
	var thick: float = maxf(5.0, float(params.get("deck_thickness", 0.018)) * stage_size.y)
	var pier_w: float = maxf(4.0, float(params.get("pier_width", 0.010)) * stage_size.y)

	var deck: Color = COLOR_BRIDGE
	deck.a = BACKDROP_ALPHA
	var deck_hi: Color = COLOR_BRIDGE_LIGHT
	deck_hi.a = BACKDROP_ALPHA

	# 半拱：用一串短线段拼出弧（不依赖贝塞尔节点，画法直白、参数好调）
	var arch_end: Vector2 = _to_px(end_x, anchor_y) + Vector2(0.0, -rise)
	# 控制点取「拱脚正上方偏右」，拱形先陡后缓，接近石拱桥。两端固定（foot→arch_end），
	# 控制点只影响弯曲程度，因此整条弧随 anchor_x / rise 连续变化，不会跳。
	var ctrl: Vector2 = Vector2(foot.x + (arch_end.x - foot.x) * 0.18, foot.y - rise * 1.35)
	var segs: int = 16
	# 先算出整条弧的点列，桥面与高光共用（高光必须沿弧走——画成直线会横穿弧面，像裂缝）
	var pts: Array[Vector2] = []
	for i in range(segs + 1):
		pts.append(_quad(foot, ctrl, arch_end, float(i) / float(segs)))
	for i in range(segs):
		draw_line(pts[i], pts[i + 1], deck, thick)
		draw_line(pts[i] + Vector2(0.0, -thick * 0.35),
			pts[i + 1] + Vector2(0.0, -thick * 0.35), deck_hi, 2.0)

	# 水平延伸段：从拱顶一路平伸到画布右缘之外（`_to_px` 不裁剪，自然出画）
	var off_canvas: Vector2 = Vector2(stage_size.x * 2.0, 0.0)
	draw_line(arch_end, arch_end + off_canvas, deck, thick)
	draw_line(arch_end + Vector2(0, -thick * 0.35),
		arch_end + off_canvas + Vector2(0, -thick * 0.35), deck_hi, 2.0)

	# 拱脚一小段立墩（把桥「种」在接地线上）
	draw_line(foot, foot + Vector2(0.0, -rise * 0.35), deck, pier_w)


## 二次贝塞尔取点（纯几何工具，无状态）。
static func _quad(p0: Vector2, ctrl: Vector2, p1: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return u * u * p0 + 2.0 * u * t * ctrl + t * t * p1


## 给调用方的挂载说明（本类不自己去改父节点，也不建 .tscn —— 走零 .tscn 路线）。
static func usage_hint() -> String:
	return "把 CSceneryView 作为舞台的子节点 add_child，并让它排在幕布之后、影人之前" \
		+ "（z_index 设为负值，或作为影人节点之前的兄弟节点）。" \
		+ "切勿挂到影子缩放根之下——布景不随灯影缩放。"
