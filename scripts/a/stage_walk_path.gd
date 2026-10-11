extends RefCounted
## 第一幕桥面路径。采点沿桥贴图的栏杆底/桥面上缘，不沿柱帽或拱洞。
## 布景的锚点与比例直接读取 CSceneryDef，避免画面和脚点各用一套定位。

const SceneryDef := preload("res://scripts/c/c_scenery_def.gd")
const DECK := [Vector2(0, 636.85714), Vector2(100, 592), Vector2(300, 509),
	Vector2(500, 370), Vector2(700, 218), Vector2(921, 160),
	Vector2(1140, 218), Vector2(1340, 370), Vector2(1540, 509),
	Vector2(1740, 592), Vector2(1842, 636.85714)]
var _origin: Vector2
var _scale: float


func _init() -> void:
	for item: Dictionary in SceneryDef.make_level1().items:
		if str(item.kind) == SceneryDef.KIND_ARCH_BRIDGE:
			_scale = float(item.get("texture_scale_px", SceneryDef.TEXTURE_SCALE_PX))
			_origin = Vector2(float(item.anchor_x) * 1920, float(item.anchor_y) * 1080) - item.texture_foot_px * _scale
			return
	push_error("第一幕桥面路径找不到 arch_bridge 布景")


func height_at(stage_x: float) -> float:
	if _scale <= 0.0:
		return 0.5
	var px: float = (stage_x * 1920.0 - _origin.x) / _scale
	if px <= 0.0 or px >= 1842.0:
		return 0.5
	for i in range(DECK.size() - 1):
		var a: Vector2 = DECK[i]
		var b: Vector2 = DECK[i + 1]
		if px <= b.x:
			return (_origin.y + lerpf(a.y, b.y, (px - a.x) / (b.x - a.x)) * _scale) / 1080.0
	return 0.5
