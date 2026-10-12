extends SceneTree
## 布景验证探针（零 .tscn，只读运行）—— **任意关卡通吃**。
## 与 c_probe_scenery 同构：只建幕布 + 布景 + 三个影人占位，不加雨幕/不建 B 侧，
## 目的是看清该关各件布景的位置与比例。
##
## 用法：
##   第二关第一幕（缺省）：godot --path . --script res://tests/c/c_probe_scenery_lv2.gd
##   第二关第二幕（厅堂）：godot --path . --script res://tests/c/c_probe_scenery_lv2.gd -- --stage=22
##   第三关（山）：        godot --path . --script res://tests/c/c_probe_scenery_lv2.gd -- --stage=3
##
## 🔴 原来关卡号与输出目录都写死为 2，第二关之后就没法用了；
## 现在关卡号从命令行读，输出按关卡分文件（`stage22_*.png`）。
## ⚠️ **不可加 --headless**：要真渲染纹理才能截图。
## ⚠️ 图中 x=0.55 / 0.70 / 0.85 处三个苍白矩形是**本探针自带的影人占位**
##    （`Figure`，白 18%），不是布景缺陷——别把它当成没加载贴图的 bug 去查。
const DefScript := preload("res://scripts/c/c_scenery_def.gd")
const ViewScript := preload("res://scripts/c/c_scenery_view.gd")

const CANVAS_SIZE := Vector2(1920.0, 1080.0)
const CLOTH := Rect2(66.0, 92.0, 1788.0, 588.0)
const OUT := "user://shots_scenery"

## 当前关卡号（由 `_stage_id()` 在启动时写入，输出文件名要用）。
var _sid: int = 2

## 从命令行读关卡号：`-- --stage=N`，缺省 2。
static func _stage_id() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			return int(a.substr(8))
	return 2

var _frames: int = 0


func _initialize() -> void:
	_build()
	process_frame.connect(_on_frame)


func _build() -> void:
	var root := Node2D.new()
	root.name = "SceneryProbe"
	get_root().add_child(root)

	var board := BoardLayer.new()
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


class BoardLayer:
	extends Node2D

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), Color("#3a2a18"))
		draw_rect(CLOTH, Color("#a3977c"))
		# 刻度参考（0.1 间隔）
		for i in range(1, 10):
			var x: float = float(i) / 10.0 * CANVAS_SIZE.x
			draw_line(
				Vector2(x, CLOTH.position.y), Vector2(x, CLOTH.end.y), Color(1, 1, 1, 0.06), 1.0
			)
			draw_string(
				ThemeDB.fallback_font,
				Vector2(x + 4, CLOTH.position.y + 20),
				"%.1f" % (float(i) / 10.0),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				16,
				Color(1, 1, 1, 0.4)
			)


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
