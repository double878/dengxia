extends Node
## 正式入口：幕后演出 → 观众选择 → 幕前回放 / 本幕收场。

const PERFORMANCE_SCENE := preload("res://scenes/a_test/level1_a.tscn")
const ACT2_SCENE := preload("res://scenes/act2/opening.tscn")
const HALL_SCENE := preload("res://scenes/act2/hall.tscn")
const ACT3_SCENE := preload("res://scenes/act3/opening.tscn")
const ReplayView := preload("res://scripts/b/performance_replay.gd")
## 关卡/幕编号。第二关分两场，各占一个编号：第一场「法海劝酒」= 2，
## 第二场「端阳饮酒」= 22（与 `CSceneryDef.LEVEL2_ACT2_STAGE_ID` 同值）。
const ACT2_STAGE_ID: int = 2
const ACT2_HALL_STAGE_ID: int = 22
var _level: Node = null
var _replay: Node = null
var _page: Control = null
var _flow: CResultFlow = null
var _stage_id: int = 1
var _title: String = ""
var _advancing: bool = false


func _ready() -> void:
	_start_performance()


func _start_performance() -> void:
	if _stage_id == 3:
		_level = ACT3_SCENE.instantiate()
		add_child(_level)
		return
	if _stage_id == ACT2_HALL_STAGE_ID:
		_level = HALL_SCENE.instantiate()
		add_child(_level)
		return
	if _stage_id == ACT2_STAGE_ID:
		_level = ACT2_SCENE.instantiate()
		# 第一幕末句应允 → 暗场 → 清场，走完章节卡后换景进第二幕（不结算、不回放）。
		_level.scene_finished.connect(_on_first_scene_finished)
		add_child(_level)
		return
	_level = PERFORMANCE_SCENE.instantiate()
	_level.performance_finished.connect(_performance_finished)
	add_child(_level)
	var skip := Button.new()
	skip.name = "SkipAct1Button"
	skip.text = "跳过第一关"
	skip.position = Vector2(1506, 15)
	skip.size = Vector2(240, 52)
	skip.add_theme_font_size_override("font_size", 24)
	skip.pressed.connect(_skip_act1)
	_level.get_node("Hud").add_child(skip)


func _skip_act1() -> void:
	if _advancing or _stage_id != 1 or _level == null:
		return
	_advancing = true
	_level.get_node("Hud/SkipAct1Button").disabled = true
	_level.set_process(false)
	_level.set_process_input(false)
	_advance_to_act2.call_deferred()


func _performance_finished(record: CPerformanceRecord, stage_id: int, title: String) -> void:
	if _advancing:
		return
	_stage_id = stage_id
	_title = title
	_flow = CResultFlow.new()
	if not _flow.offer_replay(record, stage_id):
		push_error("本幕回放记录无法加载")
		return
	_level.queue_free()
	_level = null
	_show_page(true)


func _show_page(choice: bool) -> void:
	_clear_page()
	_page = Control.new()
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_page)
	var background := ColorRect.new()
	background.size = Vector2(1920, 1080)
	background.color = Color("#1d2422")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(background)
	var heading := Label.new()
	heading.text = _title + " · 本幕收场"
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.position = Vector2(200, 280)
	heading.size = Vector2(1520, 80)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 48)
	heading.add_theme_color_override("font_color", Color("#e7c590"))
	_page.add_child(heading)
	var detail := Label.new()
	detail.text = "想从幕前看看刚才的演出吗？" if choice else "这一幕已经落下帷幕。"
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.position = Vector2(200, 400)
	detail.size = Vector2(1520, 70)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 32)
	_page.add_child(detail)
	if not choice and _stage_id == 1:
		detail.text = "点击任意位置，进入第二关《端阳惊变》"
		return
	_add_button(
		"观看幕前回放",
		Vector2(480, 550),
		func() -> void:
			if choice:
				_choose_replay(true)
			else:
				_watch_replay()
	)
	_add_button(
		"不看回放" if choice else "再演一遍",
		Vector2(1010, 550),
		func() -> void:
			if choice:
				_choose_replay(false)
			else:
				_restart()
	)


func _add_button(text: String, at: Vector2, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = Vector2(430, 90)
	button.add_theme_font_size_override("font_size", 30)
	button.pressed.connect(action)
	_page.add_child(button)


func _choose_replay(watch: bool) -> void:
	if _flow == null or _flow.get_flow_state() != &"choice":
		return
	_flow.choose_replay(watch)
	if watch:
		_enter_replay()
	else:
		_show_page(false)


func _watch_replay() -> void:
	if _flow != null and _flow.rewatch():
		_enter_replay()


func _enter_replay() -> void:
	_clear_page()
	_replay = ReplayView.new()
	_replay.flow = _flow
	_replay.stage_id = _stage_id
	_replay.title = _title
	_replay.finished.connect(_replay_finished)
	add_child(_replay)


func _skip_replay() -> void:
	if _flow != null:
		_flow.skip()
	_replay_finished()


func _replay_finished() -> void:
	if _replay != null:
		_replay.stop()
		_replay.queue_free()
		_replay = null
	_show_page(false)


func _restart() -> void:
	_clear_page()
	if _replay != null:
		_replay.stop()
		_replay.queue_free()
		_replay = null
	if _flow != null:
		_flow.leave_stage()
		_flow = null
	_start_performance()


func _clear_page() -> void:
	if _page != null:
		_page.hide()
		_page.queue_free()
		_page = null


func _unhandled_input(event: InputEvent) -> void:
	if _advancing or _stage_id != 1 or _flow == null or _flow.get_flow_state() != &"result":
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		return
	get_viewport().set_input_as_handled()
	_advancing = true
	_advance_to_act2.call_deferred()


func _advance_to_act2() -> void:
	_clear_page()
	if _level != null:
		remove_child(_level)
		_level.queue_free()
		_level = null
	if _flow != null:
		_flow.leave_stage()
		_flow = null
	_stage_id = 2
	_start_performance()
	_advancing = false


## 信号由**正在运行的场景自身**在 `_process` 里发出，故推迟到本帧末再换景，
## 不在信号发送过程中释放发送方。
func _on_first_scene_finished() -> void:
	_advance_to_act2_hall.call_deferred()


## 第二关第一场 → 第二场：暗场清场后换上编号 22 的室内厅堂布景。
## 两场同属第二关，中途不结算、不回放（PRD 第 6.2 节）。
func _advance_to_act2_hall() -> void:
	_clear_page()
	if _level != null:
		remove_child(_level)
		_level.queue_free()
		_level = null
	if _flow != null:
		_flow.leave_stage()
		_flow = null
	_stage_id = ACT2_HALL_STAGE_ID
	_start_performance()


func _exit_tree() -> void:
	if _flow != null:
		_flow.leave_stage()
