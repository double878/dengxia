extends Node2D
class_name CRainOverlay
## 烟雨氛围层：斜向飘落的雨丝（近/远两层视差）+ 静态雾霭渐变。
##
## ⚠️ 职责边界（与布景同规矩，多一条「这是特效不是景物」）：
##   1. **纯表现**：不写任何 State、不参与判定、不进记录/快照/回放——
##      回放期怎么重现？与锣鼓同性质：属于「按时间轴重触发的表现」，归 B/回放表现层，
##      本节点只在**实时演出**时挂上去（ Recorder 不采集它）。
##   2. **不碰布景数据**：雨幕不是 CSceneryDef 里的元素（景物 = 静态摆件，只能左右平移；
##      雨是全场特效，会动）——两者分开，避免破坏「景物只能左右平移」的契约口径。
##   3. **只画在幕布内**：本节点永远开启渲染器级裁剪（见下），雨丝/雾霭不会印到
##      幕布外的黑边框上。
##
## —— 裁剪方案（clip_children），2026-10-08 定案 ——
## 雨贴图 = 幕布尺寸，滚动 wrap 的 4 张副本必然越出幕布。原本用
## `draw_texture_rect_region` 与幕布求交手工裁剪，但 Compatibility 渲染器上该 API
## 实测**画白块/碎片**（2026-10-08 对照实验）。故改用与 CSceneryView 同一套结构：
## 本节点开启 `CLIP_CHILDREN_ONLY`，自身 `_draw()` 画一块**不透明幕布矩形**作模板
## （模板不显示），真正的雨/雾画在子节点 `_content` 上，副本整图直绘、越界部分
## 由渲染器裁掉。本文件**禁用** `draw_texture_rect_region`。
##
## 动画：_process 以 delta 累加滚动偏移（不依赖时钟系统——雨与演出节奏无关，
## 它是环境常量，录制暂停时照下不误；若以后要「暂停雨也停」，再接 MusicClock）。
##
## 落向：雨点笔触向右下斜（scratch/make_rain.py 生成，dx/dy≈0.42），滚动向量取同方向。

const RAIN_NEAR := preload("res://assets/scenery/level1/rain_near.png")
const RAIN_FAR := preload("res://assets/scenery/level1/rain_far.png")

## 近层落速（px/s，向**右**下）：雨点斜率 dx/dy ≈ 0.42（生成脚本同参数），
## 落向沿笔触方向 (70, 300)。
## ⚠️ 方向必须与贴图笔触一致：旧 woop 笔触向左下时取 (-70,300)；
## 2026-10-08 雨点重生成（scratch/make_rain.py）后笔触向右下，落速随之改号。
const VEL_NEAR := Vector2(70.0, 300.0)
## 远层落速：约近层一半，制造纵深视差。
const VEL_FAR := VEL_NEAR * 0.5

## 雾霭（烟雨蒙蒙）：白色顶点色渐变。
##   底部 0.30 → 中部 0 → 顶部再压一层 0.10 的薄雾（远景朦）
const MIST_BOTTOM_ALPHA: float = 0.30
const MIST_TOP_ALPHA: float = 0.10

## 裁剪模板色（不显示，只取 alpha 圈区域；同 CSceneryView.MASK_COLOR 的用法）。
const MASK_COLOR := Color.WHITE

## 幕布尺寸（贴图、模板与渐变都按它铺）。由调用方 setup 注入，避免两处各写一个数。
var _rect_size: Vector2 = Vector2.ZERO
## 滚动偏移（各自取模贴图尺寸，保证 4 张拼接无缝）。
var _off_near: Vector2 = Vector2.ZERO
var _off_far: Vector2 = Vector2.ZERO
## 实际雨/雾内容画在这个子节点上；本节点自身绘制 = 裁剪模板（见类头「裁剪方案」）。
var _content: Node2D = null


## 注入幕布尺寸（探针与正式集成场景各自传入自己的版面常量）。
func setup(cloth_size: Vector2) -> void:
	_rect_size = cloth_size
	queue_redraw()
	if _content != null:
		_content.queue_redraw()


func _ready() -> void:
	# 雨幕永远裁到幕布：滚动副本必然越界，裁剪不是可选项（不像布景的 clip_rect 可选）。
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_content = Node2D.new()
	_content.name = "RainContent"
	add_child(_content)
	_content.draw.connect(_draw_weather)
	queue_redraw()          # 画裁剪模板
	_content.queue_redraw()


func _process(delta: float) -> void:
	if _rect_size == Vector2.ZERO:
		return
	# posmodv（不是 posmod）：Vector2 逐分量取模要用 posmodv，posmod 只收 float。
	_off_near = (_off_near + VEL_NEAR * delta).posmodv(
		Vector2(RAIN_NEAR.get_width(), RAIN_NEAR.get_height()))
	_off_far = (_off_far + VEL_FAR * delta).posmodv(
		Vector2(RAIN_FAR.get_width(), RAIN_FAR.get_height()))
	if _content != null:
		_content.queue_redraw()


func _draw() -> void:
	# 裁剪模板：不透明幕布矩形（自身不显示，只当子节点的裁剪区域用）。
	draw_rect(Rect2(Vector2.ZERO, _rect_size), MASK_COLOR)


## 实际雨/雾绘制（画在子节点 _content 上，被本节点的模板裁进幕布）。
func _draw_weather() -> void:
	if _rect_size == Vector2.ZERO:
		return
	# 远层先画（在雾霭之下、更「远」）
	_draw_layer(RAIN_FAR, _off_far, 0.55)
	# 雾霭：两块顶点色渐变多边形——底部往上由浓变透明（水汽），顶部往下一层薄霭（远山朦）
	_draw_mist()
	# 近层最后画（最「近」，盖在雾上）
	_draw_layer(RAIN_NEAR, _off_near, 1.0)


## 平铺一层雨：4 张拼接覆盖 x/y 双向 wrap（偏移恒在 [0, W/H) 内，2×2 张足够）。
## **整图直绘 + 渲染器裁剪**：副本越出模板的部分由 clip_children 裁掉，
## 不在绘制端做求交/region（draw_texture_rect_region 在 Compatibility 渲染器上画白块）。
## 雨丝在贴图生成时都整条落在图内（不跨边），所以接缝处不会有「切断的雨丝」。
func _draw_layer(tex: Texture2D, off: Vector2, modulate_a: float) -> void:
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	var tint := Color(1.0, 1.0, 1.0, modulate_a)
	for ix in 2:
		for iy in 2:
			var copy_pos: Vector2 = off - Vector2(w, h) * Vector2(float(ix), float(iy))
			_content.draw_texture_rect(tex, Rect2(copy_pos, Vector2(w, h)), false, tint)


## 雾霭渐变：draw_polygon 每顶点给 alpha，竖直方向插值平滑，一次调用无接缝。
func _draw_mist() -> void:
	var w := _rect_size.x
	var h := _rect_size.y
	# 底部水汽：底边 0.30 → 45% 高度处 0（水面往上蒸起的濛）
	var mid_y := h * 0.45
	var bottom_mist := PackedVector2Array([
		Vector2(0, mid_y), Vector2(w, mid_y), Vector2(w, h), Vector2(0, h),
	])
	var bottom_cols := PackedColorArray([
		Color(1, 1, 1, 0), Color(1, 1, 1, 0),
		Color(1, 1, 1, MIST_BOTTOM_ALPHA), Color(1, 1, 1, MIST_BOTTOM_ALPHA),
	])
	_content.draw_polygon(bottom_mist, bottom_cols)
	# 顶部薄霭：顶边 0.10 → 30% 高度处 0（远景朦）
	var top_y := h * 0.30
	var top_mist := PackedVector2Array([
		Vector2(0, 0), Vector2(w, 0), Vector2(w, top_y), Vector2(0, top_y),
	])
	var top_cols := PackedColorArray([
		Color(1, 1, 1, MIST_TOP_ALPHA), Color(1, 1, 1, MIST_TOP_ALPHA),
		Color(1, 1, 1, 0), Color(1, 1, 1, 0),
	])
	_content.draw_polygon(top_mist, top_cols)
