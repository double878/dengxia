extends SceneTree
## 布景验证探针（零 .tscn，只读运行）—— **任意关卡通吃**。
## 与 c_probe_scenery 同构：只建幕布 + 布景 + 三个影人占位，不加雨幕/不建 B 侧，
## 目的是看清该关各件布景的位置与比例。
##
## 用法：
##   第二关第一幕（缺省）：godot --path . --script res://tests/c/c_probe_scenery_lv2.gd
##   第二关第二幕（厅堂）：godot --path . --script res://tests/c/c_probe_scenery_lv2.gd -- --stage=22
##   第三关（山）：        godot --path . --script res://tests/c/c_probe_scenery_lv2.gd -- --stage=3
##   关掉坐标网格：        … -- --stage=22 --grid=0
##
## 🔴 原来关卡号与输出目录都写死为 2，第二关之后就没法用了；
## 现在关卡号从命令行读，输出按关卡分文件（`stage22_*.png`）。
## ⚠️ **不可加 --headless**：要真渲染纹理才能截图。
## ⚠️ 图中 x=0.55 / 0.70 / 0.85 处三个苍白矩形是**本探针自带的影人占位**
##    （`Figure`，白 18%），不是布景缺陷——别把它当成没加载贴图的 bug 去查。
##
## 坐标参考（用户 2026-10-12 要求「标个横纵坐标参考」）：
##   默认叠一层坐标网格——0.05 细格 / 0.10 主刻度，四周标归一化坐标值；
##   另按关卡画关键水平面标线（地平线、桌面最高水平面），并写出像素值，
##   便于「酒具底边要对齐桌面最高水平面」这类关系直接在图上核对。
const DefScript := preload("res://scripts/c/c_scenery_def.gd")
const ViewScript := preload("res://scripts/c/c_scenery_view.gd")

const CANVAS_SIZE := Vector2(1920.0, 1080.0)
const CLOTH := Rect2(66.0, 92.0, 1788.0, 588.0)
const OUT := "user://shots_scenery"

## 色板：网格线取冷蓝（在米色幕布与深棕底上都压得住），刻度值用暖黄。
const COL_GRID_MINOR := Color(0.22, 0.74, 1.0, 0.20)
const COL_GRID_MAJOR := Color(0.22, 0.74, 1.0, 0.62)
const COL_TICK_TEXT := Color(0.99, 0.90, 0.32, 0.95)
const COL_TEXT_SHADOW := Color(0.0, 0.0, 0.0, 0.80)

## 当前关卡号（由 `_stage_id()` 在启动时写入，输出文件名要用）。
var _sid: int = 2

## 从命令行读关卡号：`-- --stage=N`，缺省 2。
static func _stage_id() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			return int(a.substr(8))
	return 2


## 命令行开关 `-- --grid=0` 关掉坐标网格（缺省开）。
static func _grid_on() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--grid="):
			return int(a.substr(7)) != 0
	return true


var _frames: int = 0


func _initialize() -> void:
	_build()
	process_frame.connect(_on_frame)


func _build() -> void:
	var root := Node2D.new()
	root.name = "SceneryProbe"
	get_root().add_child(root)

	var board := BoardLayer.new()
	board.show_grid = _grid_on()
	board.guides = _guides(_stage_id())
	root.add_child(board)

	# 三个影人占位（模拟影人活动区；人物站位归 A 侧，这里只做视觉参照）
	var xs: Array = [0.55, 0.70, 0.85]
	for i in 3:
		var fig := Figure.new()
		fig.x_pos = float(xs[i]) * CANVAS_SIZE.x
		fig.z_index = 20
		root.add_child(fig)

	# ★ 被测对象：该关布景
	var scenery := ViewScript.new()
	scenery.stage_origin = Vector2.ZERO
	scenery.stage_size = CANVAS_SIZE
	scenery.clip_rect = CLOTH
	scenery.z_index = 0
	scenery.setup(DefScript.make_stage(_stage_id()))
	root.add_child(scenery)


## 关键水平面标线（按关卡取；数值全部引用布景常量，不另写一份）。
## 每条 = {y: 画布像素, text: 说明, color: 颜色}。
static func _guides(sid: int) -> Array:
	match sid:
		22:
			return [
				{
					"y": DefScript.LEVEL2_ACT2_TABLE_TOP_Y * 1080.0,
					"text":
						(
							"桌面最高水平面 y=%.1fpx（%.4f）← 酒具底边一律对齐此线"
							% [DefScript.LEVEL2_ACT2_TABLE_TOP_Y * 1080.0, DefScript.LEVEL2_ACT2_TABLE_TOP_Y]
						),
					"color": Color(1.0, 0.28, 0.86, 0.92),
				},
				{
					"y": DefScript.LEVEL2_ACT2_GROUND_Y * 1080.0,
					"text":
						(
							"地平线 y=%.1fpx（%.4f）← 花盆 / 桌 / 两凳落地线"
							% [DefScript.LEVEL2_ACT2_GROUND_Y * 1080.0, DefScript.LEVEL2_ACT2_GROUND_Y]
						),
					"color": Color(0.30, 1.0, 0.45, 0.92),
				},
				{
					"y": DefScript.LEVEL2_ACT2_COLUMN_BASE_Y * 1080.0,
					"text": "立柱 / 幕布下沿 y=680.0px（0.6296）",
					"color": Color(1.0, 0.62, 0.20, 0.85),
				},
			]
		3:
			return [
				{
					"y": DefScript.LEVEL3_GROUND_Y * 1080.0,
					"text": "地平线 y=680.0px（0.6296，幕布下沿）",
					"color": Color(0.30, 1.0, 0.45, 0.92),
				}
			]
		2:
			return [
				{
					"y": DefScript.LEVEL2_GATE_BASE_Y * 1080.0,
					"text": "地平线 y=661.0px（0.6120）← 门楼 / 菊石 / 树落地线",
					"color": Color(0.30, 1.0, 0.45, 0.92),
				}
			]
	return []


class BoardLayer:
	extends Node2D

	var show_grid: bool = true
	var guides: Array = []

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), Color("#3a2a18"))
		draw_rect(CLOTH, Color("#a3977c"))
		# 幕布边界描一圈，坐标参考才有「画框」可依
		draw_rect(CLOTH, Color(1.0, 1.0, 1.0, 0.35), false, 2.0)
		if show_grid:
			_draw_grid()
		for g in guides:
			var gy: float = float(g["y"])
			var col: Color = g["color"]
			draw_line(Vector2(0.0, gy), Vector2(CANVAS_SIZE.x, gy), col, 2.0)
			# 标线文字压在线上方，避免压住景物
			_text(Vector2(72.0, gy - 8.0), str(g["text"]), col)

	## 0.05 细格 + 0.10 主刻度；四边标归一化坐标值（0.1~0.9）
	func _draw_grid() -> void:
		for i in range(1, 20):
			var x: float = float(i) * 0.05 * CANVAS_SIZE.x
			var y: float = float(i) * 0.05 * CANVAS_SIZE.y
			var col: Color = COL_GRID_MAJOR if i % 2 == 0 else COL_GRID_MINOR
			draw_line(Vector2(x, 0.0), Vector2(x, CANVAS_SIZE.y), col, 1.0)
			draw_line(Vector2(0.0, y), Vector2(CANVAS_SIZE.x, y), col, 1.0)
		for i in range(1, 10):
			var v: float = float(i) / 10.0
			var x: float = v * CANVAS_SIZE.x
			var y: float = v * CANVAS_SIZE.y
			# 上方（幕布外的深棕底）与左侧各标一次
			_text(Vector2(x + 4.0, 34.0), "%.1f" % v, COL_TICK_TEXT)
			_text(Vector2(6.0, y - 6.0), "%.1f" % v, COL_TICK_TEXT)

	func _text(pos: Vector2, text: String, col: Color) -> void:
		# 先描一层深色影子：米色幕布与深棕底上都要读得清
		draw_string(
			ThemeDB.fallback_font,
			pos + Vector2(1.5, 1.5),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			26,
			COL_TEXT_SHADOW
		)
		draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, col)


class Figure:
	extends Node2D
	var x_pos: float = 0.0

	func _draw() -> void:
		var y: float = 0.62 * CANVAS_SIZE.y
		draw_rect(
			Rect2(Vector2(x_pos - 30.0, y - 130.0), Vector2(60.0, 130.0)), Color(1, 1, 1, 0.18)
		)


func _on_frame() -> void:
	_frames += 1
	if _frames < 22:
		return
	_save_and_quit()


func _save_and_quit() -> void:
	# 打印几何（与几何探针同口径，便于核对）
	_sid = _stage_id()
	var def: CSceneryDef = DefScript.make_stage(_sid)
	print("[scenery] 关卡 %d 布景 %d 件" % [def.stage_id, def.items.size()])
	for it in def.items:
		var tex_path := str(it.get("texture", ""))
		var img := Image.load_from_file(ProjectSettings.globalize_path(tex_path))
		if img == null:
			continue
		var sc: float = float(it.get("texture_scale_px", DefScript.TEXTURE_SCALE_PX))
		var ft: Vector2 = it.get("texture_foot_px", Vector2.ZERO)
		var tg := Vector2(
			float(it.get("anchor_x", 0.0)) * 1920.0, float(it.get("anchor_y", 0.0)) * 1080.0
		)
		var r := Rect2(tg - ft * sc, Vector2(float(img.get_width()), float(img.get_height())) * sc)
		print(
			(
				"   %-18s x %.0f~%.0f  y %.0f~%.0f  (scale %.4f)"
				% [str(it.get("id", "?")), r.position.x, r.end.x, r.position.y, r.end.y, sc]
			)
		)
	for g in _guides(_sid):
		print("   [标线] y=%.1fpx  %s" % [float(g["y"]), str(g["text"])])

	# 第二幕专查：酒具「最低水平面」与「桌面最高水平面」的差值（用户 2026-10-12 要求对齐 0）
	if _sid == 22:
		var plane: float = DefScript.LEVEL2_ACT2_TABLE_TOP_Y * 1080.0
		print("[核对] 桌面最高水平面 y=%.1fpx" % plane)
		for it in def.items:
			if str(it.get("id", "")).begins_with("wine"):
				var bottom: float = float(it.get("anchor_y", 0.0)) * 1080.0
				print(
					(
						"        %-16s 最低水平面 y=%.1fpx  与桌面最高面差 %+.1fpx"
						% [str(it.get("id", "?")), bottom, bottom - plane]
					)
				)

	var img2: Image = get_root().get_texture().get_image()
	if img2 == null:
		push_error("无渲染纹理（不可加 --headless）")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	var p := OUT + "/stage%d_%d.png" % [_sid, int(Time.get_unix_time_from_system())]
	if img2.save_png(p) == OK:
		print("[shot] ", ProjectSettings.globalize_path(p))
	else:
		push_error("保存失败")
	quit()
