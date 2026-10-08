extends SceneTree
## 布景探针（零 .tscn）：运行时组装「幕布 + 布景 + 三个影人」，截图供人眼核对。
##
## 为什么用 `--script` 入口而不是 .tscn：C 侧不建场景文件（红律）。本探针只做一件事——
## 把布景和影人放在同一个画面里，验证「树根/桥脚与人影脚在同一条接地线上」。
##
## 用法：
##   godot --path <项目> --script res://scripts/c/c_scenery_probe.gd
## 产出：
##   res://scratch/shots/scenery_<unix>/stage.png
##
## ⚠️ 两个必须遵守的写法（否则探针会静默失效）：
##   - `extends SceneTree` 时**不要覆盖 `_process`**（会被引擎忽略），改用 `process_frame` 信号；
##   - `Image.save_png` 遇已存在文件返回 err=12 **且不覆盖**，所以每次写独立子目录。

const DefScript := preload("res://scripts/c/c_scenery_def.gd")
const ViewScript := preload("res://scripts/c/c_scenery_view.gd")
const RainScript := preload("res://scripts/c/c_rain_overlay.gd")
const PuppetStateScript := preload("res://scripts/a/puppet_state.gd")
const PuppetViewScript := preload("res://scripts/a_test/placeholder_puppet.gd")

## 与 A 侧 `level1_a_scene.gd` 同一套版面常量（对齐它的视觉，便于并排比较）。
const CANVAS_SIZE := Vector2(1920.0, 1080.0)
const CLOTH := Rect2(66.0, 92.0, 1788.0, 588.0)

## 第一关三具影人的初始站位（**只读** A 侧数据的口径，不在这里改判定）。
## 许仙 0.13 举伞 / 白素贞 0.50 主控 / 小青 0.86（用户 2026-10-08：小青位置不改动）。
const PUPPET_X: Array[float] = [0.50, 0.13, 0.86]
const PUPPET_GROUND_Y: float = 0.5
const PUPPET_HAND: Array = [[0.0, 0.0], [1.20, PI * 0.5], [0.10, 1.20]]

var _root: Node2D = null
var _frames: int = 0


func _initialize() -> void:
	_build()
	process_frame.connect(_on_frame)


func _build() -> void:
	_root = Node2D.new()
	_root.name = "SceneryProbeStage"
	get_root().add_child(_root)

	# 1) 幕布（照 A 侧配色：未受光的幕布底色 + 外框）
	var board := Node2D.new()
	board.name = "Board"
	board.draw.connect(_draw_board.bind(board))
	_root.add_child(board)

	# 2) 布景层：**画在幕布之后、影人之前**。同 z_index（0）下 Godot 按子节点顺序绘制，
	#    所以只要保证 add_child 的次序是 Board → Scenery → 影人即可。
	#    （不能用 z_index = -1：负 z 会把布景画到 z=0 的幕布 Board **后面**，被幕布盖住。）
	var scenery := ViewScript.new()
	scenery.name = "Scenery"
	scenery.stage_origin = Vector2.ZERO
	scenery.stage_size = CANVAS_SIZE
	# 贴图桥比幕布宽（右缘出画 227px）。裁剪走渲染器级 clip_children（视图内部实现）：
	# draw_texture_rect_region 手工求交在 Compatibility 渲染器上画白块（实测 bug），禁用。
	scenery.clip_rect = CLOTH
	var def: CSceneryDef = DefScript.make_level1()
	_apply_bridge_override(def)
	scenery.setup(def)
	_root.add_child(scenery)

	# 3) 三具影人（复用 A 的占位表现；它只读 PuppetState）
	for i in 3:
		var view := PuppetViewScript.new()
		view.name = "Puppet%d" % i
		view.stage_origin = Vector2.ZERO
		view.stage_size = CANVAS_SIZE
		view.z_index = 1
		var st = PuppetStateScript.new(i)
		st.stage_pos = Vector2(PUPPET_X[i], PUPPET_GROUND_Y)
		st.head_id = i
		st.hand_angle = Vector2(PUPPET_HAND[i][0], PUPPET_HAND[i][1])
		st.is_controlled = (i == 0)
		view.puppet_state = st
		_root.add_child(view)

	# 4) 烟雨氛围层：全场铺在最上（雨丝 + 雾霭）。节点定位到幕布左上角，
	#    内部自带 clip_children 模板裁剪——滚动副本越出幕布的部分由渲染器裁掉，
	#    不会印到黑边框上。
	var rain := RainScript.new()
	rain.name = "Rain"
	rain.position = CLOTH.position
	rain.setup(CLOTH.size)
	_root.add_child(rain)


## 摆放选型开关（**仅探针用，不入正式数据**）：环境变量覆盖拱桥的 anchor_x 与贴图缩放，
## 用于一次性跑出多个摆放方案截图、供人眼挑选拍板。
##   BRIDGE_ANCHOR_X  归一化 0~1（缺省用数据里的 0.86）
##   BRIDGE_SCALE     素材像素比（缺省用 DefScript.TEXTURE_SCALE_PX）
## 「只露右半拱」已烘进资产本身（arch_bridge.png = 1024×726 右半），
## 不再需要裁半开关；改「露多少」直接重裁资产并同步 texture_foot_px。
## 选型定案后，把拍板数值写回 c_scenery_def.gd，此函数留作以后调型用。
func _apply_bridge_override(def: CSceneryDef) -> void:
	var ax := OS.get_environment("BRIDGE_ANCHOR_X")
	var sc := OS.get_environment("BRIDGE_SCALE")
	if ax.is_empty() and sc.is_empty():
		return
	for item in def.items:
		if str(item.get("id", "")) != "bridge_right":
			continue
		if not ax.is_empty():
			item["anchor_x"] = float(ax)
		if not sc.is_empty():
			# 探针级覆盖：直接改视图常量不行（const），改为把缩放写进 item，
			# 由 CSceneryView 优先读 item 级 `texture_scale_px`（见视图端注释）。
			item["texture_scale_px"] = float(sc)


## 幕布与工作台（照 A 侧 `level1_a_scene.gd` 的版面，只画布景校验需要的部分）。
## 刻意**不画**接地参考线：画面要尽量接近成品观感，用来看布景本身的形状与位置是否顺眼；
## 数值层面的对齐由 `run_scenery_tests.gd` 的断言负责，不在画面上打辅助线。
func _draw_board(_node: Node2D) -> void:
	var b: Node2D = _node
	b.draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), Color("#171b19"))
	b.draw_rect(CLOTH, Color("#a3977c"))


func _on_frame() -> void:
	# `Viewport.get_texture().get_image()` 滞后一帧，等足 3 帧再截。
	_frames += 1
	if _frames < 3:
		return
	_save_and_quit()


func _save_and_quit() -> void:
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		# --headless 用 dummy 渲染器，没有纹理可截。明说，别让调用方对着 null 报错猜。
		push_error("截图失败：无渲染纹理。本探针需要真实渲染器——运行时不要加 --headless")
		quit(1)
		return
	var dir_path := "res://scratch/shots/scenery_%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(dir_path)
	var path := dir_path + "/stage.png"
	var err := img.save_png(path)
	if err != OK:
		push_error("截图失败 err=%d → %s" % [err, path])
	else:
		print("[scenery_probe] 已保存：", ProjectSettings.globalize_path(path))
	quit()
