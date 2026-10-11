extends SceneTree
## 布景灯光耦合验证探针（切幕前置，零 .tscn，只读运行）。
##
## 目的：肉眼确认「灯灭 → 布景跟着暗；灯亮 → 布景跟着亮」。
## 这一层以前**不存在**——StageSurface（幕布）吃 shader、影人有 lamp_state，
## 而布景完全没有灯光耦合，灯全灭时门楼/柳树依然亮着，直接切幕会穿帮。
##
## 输出三张对照图到 user://shots_light/：满灯 / 半灯 / 灯灭。
## 同时打印各档的 modulate 实测值，供与测试断言对照。

const BindingScript := preload("res://scripts/c/c_stage_binding.gd")

const CANVAS := Vector2(1920.0, 1080.0)
const CLOTH := Rect2(66.0, 92.0, 1788.0, 588.0)
const OUT := "user://shots_light"

var _root: Node2D = null
var _binding: Node2D = null
var _shots: int = 0
var _stage: int = 0


func _initialize() -> void:
	_build()
	process_frame.connect(_on_frame)


func _build() -> void:
	_root = Node2D.new()
	_root.name = "LightProbe"
	get_root().add_child(_root)

	var board := BoardLayer.new()
	_root.add_child(board)

	# 影人占位（z=20）：与真演出同层，用来对比「影人暗了、布景暗没暗」
	var xs: Array = [0.52, 0.60, 0.68]
	for i in 3:
		var fig := Figure.new()
		fig.x_pos = float(xs[i]) * CANVAS.x
		fig.z_index = 20
		# 影人按灯光同步压暗（模拟 A 侧 lamp_state 的效果）
		fig.light = 1.0
		_root.add_child(fig)

	_binding = BindingScript.new()
	_binding.stage_id = 1
	_root.add_child(_binding)
	print("[light] 绑定层默认亮度 = %.4f" % _binding.get_light_level())


## 三档：满灯 → 半灯 → 灯灭
const STEPS := [
	{"level": -1.0, "name": "full", "lamp": 1.0, "label": "满灯 exposure=1"},
	{"level": 0.45, "name": "half", "lamp": 0.45, "label": "半灯 exposure=0.45"},
	{"level": 0.0, "name": "dark", "lamp": 0.0, "label": "灯灭 exposure=0"},
]


func _on_frame() -> void:
	if _stage >= STEPS.size():
		quit()
		return
	# 每档等8 帧：modulate 是即时属性，但合成要过一帧才反映到 get_image()
	var n := 0
	while n < 8:
		await process_frame
		n += 1
	_capture(STEPS[_stage])
	_stage += 1


func _capture(step: Dictionary) -> void:
	var level: float = float(step["level"])
	if level < 0.0:
		# 满灯：直接给 exposure/oil，让内部按BASE_LIGHT 折算
		_binding.set_light(1.0, 1.0)
	else:
		_binding.set_light_level(level)
	# 影人同步（真演出里这层归 A 侧 LampState，这里只是让对比图真实）
	var figs: Array[Node] = []
	for c in _root.get_children():
		if c is Figure:
			figs.append(c)
	for f in figs:
		var fig := f as Figure
		fig.light = maxf(0.06, fig.light)
		fig.set_light(float(step["lamp"]))
		fig.queue_redraw()

	var img: Image = get_root().get_texture().get_image()
	if img == null:
		push_error("无渲染纹理（不可加 --headless）")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	var p := OUT + "/%s_%d.png" % [step["name"], int(Time.get_unix_time_from_system())]
	if img.save_png(p) == OK:
		print("[light] %s → level=%.4f  %s" % [step["label"],
			_binding.get_light_level(), ProjectSettings.globalize_path(p)])


class BoardLayer extends Node2D:
	func _draw() -> void:
		# 幕布底：模拟 StageSurface 在灯灭时的样子（环境光 0.58+0.42×oil →灯灭≈0.58）
		draw_rect(Rect2(Vector2.ZERO, CANVAS), Color("#1a1410"))
		draw_rect(CLOTH, Color("#8a7f68"))


class Figure extends Node2D:
	var x_pos: float = 0.0
	var light: float = 1.0
	func set_light(v: float) -> void:
		light = clampf(v, 0.0, 1.0)
		modulate = Color(light, light, light, 1.0)
	func _draw() -> void:
		var y: float = 0.62 * CANVAS.y
		# 影身
		draw_rect(Rect2(Vector2(x_pos - 26.0, y - 170.0), Vector2(52.0, 170.0)),
			Color("#1c1c1c"))
		# 头
		draw_circle(Vector2(x_pos, y - 186.0), 24.0, Color("#1c1c1c"))
		# 伞（示意：第一幕有伞）
		draw_rect(Rect2(Vector2(x_pos - 70.0, y - 232.0), Vector2(140.0, 16.0)),
			Color("#1c1c1c"))