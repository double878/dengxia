extends RefCounted
## 第一幕桥面路径。采点沿桥贴图的栏杆底/桥面上缘，不沿柱帽或拱洞。
## 布景的锚点与比例直接读取 CSceneryDef，避免画面和脚点各用一套定位。

const SceneryDef := preload("res://scripts/c/c_scenery_def.gd")
const DECK := [
	Vector2(0, 636.85714),
	Vector2(100, 592),
	Vector2(300, 509),
	Vector2(500, 370),
	Vector2(700, 218),
	Vector2(921, 160),
	Vector2(1140, 218),
	Vector2(1340, 370),
	Vector2(1540, 509),
	Vector2(1740, 592),
	Vector2(1842, 636.85714)
]
var _origin: Vector2
var _scale: float


func _init() -> void:
	for item: Dictionary in SceneryDef.make_level1().items:
		if str(item.kind) == SceneryDef.KIND_ARCH_BRIDGE:
			_scale = float(item.get("texture_scale_px", SceneryDef.TEXTURE_SCALE_PX))
			_origin = (
				Vector2(float(item.anchor_x) * 1920, float(item.anchor_y) * 1080)
				- item.texture_foot_px * _scale
			)
			return
	push_error("第一幕桥面路径找不到 arch_bridge 布景")


## 该 x 是否落在**桥跨之内**（贴图坐标 px ∈ (0, 1842)）。
## px = 0 正是**桥头**（0.52853，与许仙开局站位重合）⇒ 桥头算「桥外」。
## 之所以要把这件事公开：桥跨以外没有桥面可言，脚点该落回**各自的落地线**，
## 而那条约线由调用方按影人给（见 `PuppetController.ground_y`）。
func is_on_deck(stage_x: float) -> bool:
	if _scale <= 0.0:
		return false
	var px: float = (stage_x * 1920.0 - _origin.x) / _scale
	return px > 0.0 and px < 1842.0


## 脚点高度（归一化 0–1）。`ground_y` 是**桥跨之外**的落地线。
##
## 🔴 2026-10-16 用户报「人物站位太高」后改口径：桥外不再一律返回 0.5，
##   改回**调用方给的落地线**（第一关 = 许仙 0.587963 / 两位娘子 0.597222）。
##   0.5 只是没给落地线时的兜底（例如没装布景、单测直接 new 出路径）。
##   旧口径让三具影人开局脚点全被抬到 540px，关卡数据的 635/645px 从未生效——
##   三具影人（0.26 / 0.32 / 0.5285）都在桥跨外或恰在左缘，正好全部命中旧分支。
func height_at(stage_x: float, ground_y: float = 0.5) -> float:
	if not is_on_deck(stage_x):
		return ground_y
	var px: float = (stage_x * 1920.0 - _origin.x) / _scale
	for i in range(DECK.size() - 1):
		var a: Vector2 = DECK[i]
		var b: Vector2 = DECK[i + 1]
		if px <= b.x:
			return (_origin.y + lerpf(a.y, b.y, (px - a.x) / (b.x - a.x)) * _scale) / 1080.0
	return ground_y
