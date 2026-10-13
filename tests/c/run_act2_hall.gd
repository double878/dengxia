extends SceneTree
## 第二关第二幕「端阳饮酒」接入回归：厅堂布景（编号 22）在**游戏里**可见。
## 运行：
##   godot.exe --headless --path . --script res://tests/c/run_act2_hall.gd
## 全部通过退出码 0，任一断言失败退出码 1。
##
## 覆盖三件事（缺一件就说明「游戏里看不到第二幕的景」）：
##   ① 第二幕场景 `scenes/act2/hall.tscn` 真的挂上了编号 22 的厅堂布景（13 件、贴图实际加载）；
##   ② 游戏主流程 `game_flow.gd` 把 22 当成一幕来加载（不是只活在测试或探针里）；
##   ③ 第一场收场（末句应允 → 暗场 → 「端阳」章节卡）走完会**自动**换景进第二幕，
##      且换景前不结算、不回放（PRD 第 6.2 节）。
##
## 用 preload 常量而不是 class_name 类型标注：`--script` 模式对全局类名缓存的解析不可靠。

const GAME_SCENE := preload("res://scenes/game_flow.tscn")
const HALL_SCENE := preload("res://scenes/act2/hall.tscn")
const GameFlowScript := preload("res://scripts/game_flow.gd")
const OpeningScript := preload("res://scripts/act2/act2_opening.gd")
## 第二关第二幕的布景编号，与 `CSceneryDef.LEVEL2_ACT2_STAGE_ID` 同值。
const HALL_STAGE_ID: int = 22
## 幕布矩形，必须与 A 侧 `level1_a_scene.gd` 和 C 侧 `CStageBinding.CLOTH` 同值。
const CLOTH := Rect2(66, 92, 1788, 588)
## 第二幕应有的 13 件（定稿：柱×2 + 梁×4 + 花盆 + 桌 + 凳×2 + 壶 + 杯×2），已排序。
const HALL_IDS := [
	"beam_0",
	"beam_1",
	"beam_2",
	"beam_3",
	"column_left",
	"column_right",
	"flowerpot",
	"stool_left",
	"stool_right",
	"table",
	"wine_cup_green",
	"wine_cup_red",
	"wine_pot",
]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ACT2_HALL: " + label)


func _run() -> void:
	await test_hall_scene()
	await test_game_flow_entry()
	await test_auto_advance()
	print("ACT2_HALL checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


## ① 第二幕场景本身：编号 22、无雨、13 件贴图实际加载、裁入幕布、层级正确、不放影人。
func test_hall_scene() -> void:
	check(ResourceLoader.exists("res://scenes/act2/hall.tscn"), "缺少第二幕厅堂场景")
	var hall: Node = HALL_SCENE.instantiate()
	root.add_child(hall)
	await process_frame
	check(hall.scene_file_path == "res://scenes/act2/hall.tscn", "第二幕场景路径不符")
	check(hall.get_node_or_null("Hud") != null, "第二幕缺少台口信息层")
	var binding := hall.get_node_or_null("CStageBinding") as CStageBinding
	check(binding != null, "第二幕缺少布景绑定")
	if binding == null:
		hall.queue_free()
		await process_frame
		return
	check(binding.stage_id == HALL_STAGE_ID, "第二幕没有取 22 号厅堂布景")
	check(not binding.enable_rain and binding.get("_rain") == null, "室内厅堂沿用了游湖雨幕")
	var scenery := binding.get("_scenery") as CSceneryView
	check(scenery != null, "布景绑定存在但未生成布景")
	if scenery == null:
		hall.queue_free()
		await process_frame
		return
	var data := scenery.get("_def") as CSceneryDef
	check(data.stage_id == HALL_STAGE_ID, "布景数据编号不是 22")
	var ids: Array[String] = []
	var order := {}
	for index in range(data.items.size()):
		var item: Dictionary = data.items[index]
		var id := str(item.get("id", ""))
		ids.append(id)
		order[id] = index
		var texture := scenery._get_texture(str(item.get("texture", ""))) as Texture2D
		check(texture != null and texture.get_width() > 0, "厅堂贴图没有实际加载：" + id)
	ids.sort()
	check(ids == HALL_IDS, "第二幕不是厅堂的 13 件构图（取错编号或件数变了）")
	# 绘制顺序 = 数组顺序，后画者在上：酒具必须排在桌子之后，否则被桌面盖住。
	check(order.get("table", -1) < order.get("wine_pot", -1), "酒具没有画在桌子之上")
	check(scenery.clip_rect == CLOTH, "厅堂布景没有裁入幕布")
	check(scenery.z_index > hall.get("_surface").z_index, "布景被幕布遮住")
	check(hall.get_node_or_null("Fahai") == null, "厅堂不应残留第一场法海")
	check(hall.get_node_or_null("Xuxian") != null, "厅堂应接入第二场许仙")
	hall.queue_free()
	await process_frame


## ② 主流程能把 22 当成一幕加载——「游戏里看得见」的前提。
func test_game_flow_entry() -> void:
	var game: Node = GAME_SCENE.instantiate()
	game.set("_stage_id", HALL_STAGE_ID)
	root.add_child(game)
	await process_frame
	var level: Node = game.get("_level")
	check(
		level != null and level.scene_file_path == "res://scenes/act2/hall.tscn", "22 号没有加载第二幕厅堂场景"
	)
	check(game.get_child_count() == 1, "22 号加载了多个场景")
	game.queue_free()
	await process_frame


## ③ 第一场收场自动换景：暗场 → 章节卡停留 → 换到厅堂；换景前不结算。
func test_auto_advance() -> void:
	var game: Node = GAME_SCENE.instantiate()
	game.set("_stage_id", GameFlowScript.ACT2_STAGE_ID)
	root.add_child(game)
	await process_frame
	var opening: Node = game.get("_level")
	if opening == null or opening.scene_file_path != "res://scenes/act2/opening.tscn":
		check(false, "2 号没有加载第二关第一场")
		game.queue_free()
		await process_frame
		return
	opening.set_process(false)
	# 模拟末句应允走完：真实流程由对白推进到 finished 并发出收场信号。
	opening.dialogue.phase = "finished"
	opening.dialogue.finished.emit()
	check(opening.get("_dark_hold") > 0.0, "收场没有进入章节卡停留")
	check(opening.get("_transition_title").visible, "章节卡期间没有显示「端阳」")
	check(opening.get("_dark").color.a >= 1.0, "章节卡期间幕面没有压黑")
	check(game.get("_stage_id") == GameFlowScript.ACT2_STAGE_ID, "章节卡还没走完就换景")
	check(game.get("_flow") == null and game.get("_page") == null, "两场之间出现了结算或回放")
	opening._process(OpeningScript.DARK_HOLD_S + 0.1)
	check(game.get("_stage_id") == GameFlowScript.ACT2_STAGE_ID, "换景没有推迟到帧末执行")
	await process_frame
	await process_frame
	check(game.get("_stage_id") == HALL_STAGE_ID, "第一场收场后没有换到第二幕")
	var level: Node = game.get("_level")
	check(level != null and level.scene_file_path == "res://scenes/act2/hall.tscn", "换景后的场景不是第二幕厅堂")
	check(not is_instance_valid(opening), "换景后第一场宿主没有释放")
	check(game.get_child_count() == 1, "换景加载了多个场景")
	game.queue_free()
	await process_frame
