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
##
## —— 裁剪方案（clip_children），2026-10-08 定案 ——
## 贴图桥比幕布宽（右缘出画约 227px），越界部分会印到幕布外的黑边框上。
## 原本想用 `draw_texture_rect_region` 与幕布求交手工裁剪，但 Compatibility 渲染器上
## 该 API 实测**画白块/碎片**（2026-10-08 对照实验：preload 整图直绘完美、
## region 子矩形全废）。故改用渲染器级裁剪，本文件**禁用** `draw_texture_rect_region`：
##   - 本节点自身 `_draw()` 画一块**不透明矩形**作裁剪模板；
##     `CLIP_CHILDREN_ONLY` 模式下模板本身不显示，只取它圈定的区域做模板。
##   - 真正的布景内容画在子节点 `_content` 上，由渲染器裁进模板区域。
##   - 因此所有绘制都**整图/整体直绘**（`draw_texture_rect` / `draw_line` 等），
##     越不越界交给裁剪，不在绘制端做几何裁剪。
## `clip_rect` 必须在节点**进树之前**设置（`_ready` 按它决定是否开启裁剪）；
## 零尺寸（默认）= 不裁剪，内容原样画出（headless/断言路径不受影响）。

const DefScript := preload("res://scripts/c/c_scenery_def.gd")

## 颜色：取自 TECH_DESIGN 第 5.2 节项目色板。布景是**背景**，整体压暗、降饱和，
## 免得抢了幕前影人的视觉重心。
const COLOR_WILLOW: Color = Color("#34866A")        ## 皮影绿（小青主色，也用于布景局部）
const COLOR_WILLOW_DARK: Color = Color("#27503F")
const COLOR_BRIDGE: Color = Color("#8a5a2b")        ## 木褐（比「幕后木褐 #3A2A18」亮，作桥可见）
const COLOR_BRIDGE_LIGHT: Color = Color("#b07a41")
const BACKDROP_ALPHA: float = 0.55                   ## 整体透明度：背景不抢戏

## 裁剪模板色。CLIP_CHILDREN_ONLY 下模板不显示，只取其 alpha 圈区域——
## 用纯白表达「这是模板，不是颜色设计」。
const MASK_COLOR := Color.WHITE

## 舞台映射区。必须与影人用**同一套**（由调用方注入，避免两处各写一个数）。
@export var stage_origin: Vector2 = Vector2.ZERO
@export var stage_size: Vector2 = Vector2(1920.0, 1080.0)

## 可选裁剪矩形（**本节点局部坐标**，与 stage_origin 同参照；探针把节点放在原点，
## 故即画布坐标）。零尺寸（默认）= 不裁剪。
## ⚠️ 必须在进树前设置——`_ready` 里按它决定是否开启 clip_children。
@export var clip_rect: Rect2 = Rect2()

var _def: CSceneryDef = null
## 贴图缓存：路径 → Texture2D（或 null 表示加载失败，避免每帧重试）。
## 为什么缓存 null：资源缺失时每帧 `load()` 会刷屏报错，缓存住只报一次。
var _tex_cache: Dictionary = {}
## 实际布景内容画在这个子节点上；本节点自身绘制 = 裁剪模板（见类头「裁剪方案」）。
var _content: Node2D = null


## 装载一关的布景。传 null 视为空布景（画空白，不报错——第 2~5 关还没做）。
func setup(scenery_def: CSceneryDef) -> void:
	_def = scenery_def
	queue_redraw()
	if _content != null:
		_content.queue_redraw()


func _ready() -> void:
	# 组装「模板（自身）+ 内容（子节点）」结构。只有给了 clip_rect 才开裁剪；
	# 不开时 _draw 什么都不画，内容按原样画出（与旧版为等价行为）。
	_content = Node2D.new()
	_content.name = "SceneryContent"
	add_child(_content)
	_content.draw.connect(_draw_items)
	if clip_rect.size != Vector2.ZERO:
		clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		queue_redraw()   # 画裁剪模板
	_content.queue_redraw()


## 取贴图（带缓存）。找不到资源返回 null，由调用方回退程序化画法。
## 检测两种失败：路径为空、以及 `load()` 拿到的是「非 Texture2D」（避免把脚本当贴图）。
func _get_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var res: Resource = null
	if ResourceLoader.exists(path):
		res = load(path)
	var tex: Texture2D = res as Texture2D
	if tex == null:
		# 只在首次失败时提示：贴图缺失是「用占位画法继续跑」的正常降级路径，
		# 不是崩溃。headless 批跑正好走这条分支（无渲染资源）。
		push_warning("CSceneryView: 贴图不可用，回退程序化占位 —— %s" % path)
	_tex_cache[path] = tex
	return tex


## 水平平移（**唯一**允许的位移；第 1 关恒 0）。
## 之所以做成方法而不是直接暴露变量，是为了留着将来「布景随剧情左右滑动」的接口，
## 而实现里除水平偏移外**不可能**出现别的位移。
func set_pan(item_id: String, pan_x: float) -> void:
	if _def == null:
		return
	for item in _def.items:
		if str(item.get("id", "")) == item_id:
			item["pan_x"] = pan_x
			if _content != null:
				_content.queue_redraw()
			return


## 归一化 → 像素。**与影人同一公式**（PlaceholderPuppet.stage_to_screen）；
## 两处必须一致，否则布景与影人会错位。
func _to_px(nx: float, ny: float) -> Vector2:
	return Vector2(
		stage_origin.x + nx * stage_size.x,
		stage_origin.y + ny * stage_size.y)


func _draw() -> void:
	# 裁剪模板：CLIP_CHILDREN_ONLY 下自身绘制不显示，只当子节点的裁剪区域用。
	# 未开裁剪（clip_rect 为零）时这里什么都不画。
	if clip_children == CanvasItem.CLIP_CHILDREN_ONLY:
		draw_rect(clip_rect, MASK_COLOR)


## 实际布景绘制（画在子节点 _content 上，被本节点的模板裁进幕布）。
## 结构与取数逻辑与旧版一致，只是绘制目标从 self 换成 _content。
func _draw_items() -> void:
	if _def == null:
		return
	for item in _def.items:
		var kind: String = str(item.get("kind", ""))
		var x: float = float(item.get("anchor_x", 0.0)) + float(item.get("pan_x", 0.0))
		var y: float = float(item.get("anchor_y", DefScript.ANCHOR_Y))
		var params: Dictionary = item.get("params", {})
		# 贴图优先：有可用贴图就画贴图，否则回退程序化占位。
		# 两条路都**只受 anchor_x/anchor_y/pan_x 影响**，不存在额外位移。
		var tex: Texture2D = _get_texture(str(item.get("texture", "")))
		if tex != null:
			_draw_texture_item(item, tex, x, y)
			continue
		match kind:
			DefScript.KIND_WILLOW:
				_draw_willow(x, y, params)
			DefScript.KIND_ARCH_BRIDGE:
				_draw_arch_bridge(x, y, params)
			_:
				# 未知种类不静默吞掉：这类 bug 在画面上表现为「布景少了东西」，
				# 排查时最怕它一声不吭。push_warning 让 --headless 也能看见。
				push_warning("CSceneryView: 未知布景种类 %s（id=%s）" % [kind, str(item.get("id", ""))])


## 贴图摆放：统一像素比例缩放 + 把「贴图内的桥脚接地点」对齐到 (anchor_x, anchor_y)。
##
## 数学：设 scale = 贴图1px → 画布多少px（item 级 `texture_scale_px` 优先，
## 缺省用全局 `TEXTURE_SCALE_PX`），贴图内接地点像素为 (fx, fy)，
## 则贴图左上角应画在 `target - (fx, fy) * scale`，整张图以 `target` 为基准定位。
## 好处：贴图内的雨丝、水雾、桥面装饰都按同一比例随桥缩放，比例自洽；
## 调整大小只需改一个缩放数，anchor 不动。
##
## 裁剪：**不做几何裁剪**，整图直绘，越界部分由渲染器的 clip_children 裁掉
## （draw_texture_rect_region 在 Compatibility 渲染器上画白块，见类头）。
func _draw_texture_item(item: Dictionary, tex: Texture2D, anchor_x: float, anchor_y: float) -> void:
	var target: Vector2 = _to_px(anchor_x, anchor_y)
	var scale: float = DefScript.TEXTURE_SCALE_PX
	if item.has("texture_scale_px"):
		scale = float(item["texture_scale_px"])
	var foot: Vector2 = item.get("texture_foot_px", Vector2.ZERO)
	var size: Vector2 = Vector2(tex.get_width(), tex.get_height()) * scale
	var top_left: Vector2 = target - foot * scale
	_content.draw_texture_rect(tex, Rect2(top_left, size), false,
		Color(1.0, 1.0, 1.0, BACKDROP_ALPHA))


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
		_content.draw_line(start, end, leaf_dark, 2.0)

	_content.draw_circle(crown, crown_ry, leaf)
	_content.draw_circle(crown + Vector2(-crown_rx * 0.55, crown_ry * 0.15), crown_ry * 0.78, leaf)
	_content.draw_circle(crown + Vector2(crown_rx * 0.55, crown_ry * 0.15), crown_ry * 0.78, leaf)
	_content.draw_circle(crown + Vector2(0.0, -crown_ry * 0.5), crown_ry * 0.82, leaf)

	# 树干
	var trunk_w: float = maxf(6.0, stage_size.y * 0.008)
	var trunk: Color = COLOR_BRIDGE
	trunk.a = BACKDROP_ALPHA
	_content.draw_line(base, top, trunk, trunk_w)


## 拱桥：从 anchor_x 起拱，到 `arch_end_x` 到达拱顶高度，之后**水平延伸出画**。
## 用户 2026-10-08：「拱桥从 0.72 开始……不用画出完整拱桥，只画一半，平行延伸到画布外」。
## （贴图接入后此画法只作无贴图时的回退占位；延伸出画的部分由裁剪收进幕布。）
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
		_content.draw_line(pts[i], pts[i + 1], deck, thick)
		_content.draw_line(pts[i] + Vector2(0.0, -thick * 0.35),
			pts[i + 1] + Vector2(0.0, -thick * 0.35), deck_hi, 2.0)

	# 水平延伸段：从拱顶一路平伸到画布右缘之外（`_to_px` 不裁剪，渲染器裁剪收进幕布）
	var off_canvas: Vector2 = Vector2(stage_size.x * 2.0, 0.0)
	_content.draw_line(arch_end, arch_end + off_canvas, deck, thick)
	_content.draw_line(arch_end + Vector2(0, -thick * 0.35),
		arch_end + off_canvas + Vector2(0, -thick * 0.35), deck_hi, 2.0)

	# 拱脚一小段立墩（把桥「种」在接地线上）
	_content.draw_line(foot, foot + Vector2(0.0, -rise * 0.35), deck, pier_w)


## 二次贝塞尔取点（纯几何工具，无状态）。
static func _quad(p0: Vector2, ctrl: Vector2, p1: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return u * u * p0 + 2.0 * u * t * ctrl + t * t * p1


## 给调用方的挂载说明（本类不自己去改父节点，也不建 .tscn —— 走零 .tscn 路线）。
static func usage_hint() -> String:
	return "把 CSceneryView 作为舞台的子节点 add_child，并让它排在幕布之后、影人之前" \
		+ "（z_index 设为负值，或作为影人节点之前的兄弟节点）。" \
		+ "若贴图可能越出幕布，请在进树前把 clip_rect 设为幕布矩形（渲染器级裁剪）。" \
		+ "切勿挂到影子缩放根之下——布景不随灯影缩放。"
