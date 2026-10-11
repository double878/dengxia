extends RefCounted
## 第一幕入口的固定遮挡；只读布景和显示几何，不写 PuppetState。

const CANVAS_SIZE := Vector2(1920, 1080)
const TreeTexture := preload("res://assets/scenery/level2/willow_branch.png")
## 门洞在原图 x≈820–1050；靠右门框露出后，向右走到空地。
const DOOR_RIGHT_PX: float = 1050.0
const DOOR_START_PX: float = 1000.0

var masks: Array[Texture2D] = []
var positions: Array[Vector2] = []
var _exit_edges: Array[float] = []
var _mask_images: Array[Image] = []


func setup(cloth: Rect2) -> void:
	var gate_left: float = CSceneryDef.LEVEL2_GATE_X * CANVAS_SIZE.x
	var door_edge: float = gate_left + DOOR_RIGHT_PX * CSceneryDef.LEVEL2_GATE_SCALE
	var tree_ground := (
		Vector2(CSceneryDef.LEVEL2_TREE_X, CSceneryDef.LEVEL2_TREE_BASE_Y) * CANVAS_SIZE
	)
	var tree_origin: Vector2 = tree_ground - Vector2(688, 1866) * CSceneryDef.LEVEL2_TREE_SCALE
	var door_mask: Image = Image.create(1920, 1080, false, Image.FORMAT_R8)
	door_mask.fill(Color.BLACK)
	door_mask.fill_rect(
		Rect2i(
			int(cloth.position.x),
			int(cloth.position.y),
			ceili(door_edge - cloth.position.x),
			int(cloth.size.y)
		),
		Color.WHITE
	)
	_mask_images = [_tree_mask(cloth, tree_origin), door_mask]
	masks = [
		ImageTexture.create_from_image(_mask_images[0]), ImageTexture.create_from_image(door_mask)
	]
	positions = [
		(tree_ground + Vector2(115, 0)) / CANVAS_SIZE,
		(
			Vector2(
				gate_left + DOOR_START_PX * CSceneryDef.LEVEL2_GATE_SCALE,
				CSceneryDef.LEVEL2_GATE_BASE_Y * CANVAS_SIZE.y
			)
			/ CANVAS_SIZE
		),
	]
	_exit_edges = [tree_origin.x, door_edge]


## 每行取树的左右外轮廓，填实装饰镂空；避免人脸从树的花纹孔中提前出现。
## 遮罩只作用于幕布内，幕布外的竹签和操作手保持可见。
func _tree_mask(cloth: Rect2, origin: Vector2) -> Image:
	var source: Image = TreeTexture.get_image()
	if source.is_compressed():
		var error: Error = source.decompress()
		assert(error == OK, "Act2Entrance: 柳树图像解压失败")
	var mask: Image = Image.create(1920, 1080, false, Image.FORMAT_R8)
	mask.fill(Color.BLACK)
	for y in range(int(cloth.position.y), int(cloth.end.y)):
		var row: int = floori((float(y) - origin.y) / CSceneryDef.LEVEL2_TREE_SCALE)
		if row < 0 or row >= source.get_height():
			continue
		var left: int = 0
		var right: int = source.get_width() - 1
		while left <= right and source.get_pixel(left, row).a < 0.08:
			left += 1
		while right >= left and source.get_pixel(right, row).a < 0.08:
			right -= 1
		if left > right:
			continue
		var from_x: int = maxi(
			floori(origin.x + left * CSceneryDef.LEVEL2_TREE_SCALE), int(cloth.position.x)
		)
		var to_x: int = mini(
			ceili(origin.x + (right + 1) * CSceneryDef.LEVEL2_TREE_SCALE), int(cloth.end.x)
		)
		if to_x > from_x:
			mask.fill_rect(Rect2i(from_x, y, to_x - from_x, 1), Color.WHITE)
	return mask


## 输入与实体使用同一遮罩，避免点击布景时抓到或收走藏在后面的影人。
func blocks_point(id: int, at: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, CANVAS_SIZE).has_point(at):
		return false
	return _mask_images[id].get_pixel(int(at.x), int(at.y)).r > 0.5


## 连同灯距投影、手腕和冠帽预留一起离开入口，才永久切到布景前。
func has_cleared(id: int, entity: PlaceholderPuppet, projection: PlaceholderPuppet) -> bool:
	for view: PlaceholderPuppet in [entity, projection]:
		var ground: Vector2 = view.stage_to_screen(view.puppet_state.stage_pos)
		var height: float = view.figure_px_height()
		var bounds := Rect2(
			ground - Vector2(height * 0.27, height * 1.15), Vector2(height * 0.54, height * 1.2)
		)
		bounds = bounds.expand(view.hand_screen_position("left"))
		bounds = bounds.expand(view.hand_screen_position("right")).grow(16)
		bounds = view.transform * bounds
		if (
			(id == 0 and bounds.end.x >= _exit_edges[0])
			or (id == 1 and bounds.position.x <= _exit_edges[1])
		):
			return false
	return true
