extends Node
## 正式入口：幕后演出 → 观众选择 → 幕前回放 / 本幕收场。

const PERFORMANCE_SCENE := preload("res://scenes/a_test/level1_a.tscn")
const ReplayView := preload("res://scripts/b/performance_replay.gd")
var _level: Node = null
var _replay: Node = null
var _page: Control = null
var _flow: CResultFlow = null
var _stage_id: int = 1
var _title: String = ""


func _ready() -> void:
	_start_performance()


func _start_performance() -> void:
	_level = PERFORMANCE_SCENE.instantiate()
	_level.performance_finished.connect(_performance_finished)
	add_child(_level)


func _performance_finished(record: CPerformanceRecord, stage_id: int, title: String) -> void:
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
	add_child(_page)
	var background := ColorRect.new()
	background.size = Vector2(1920, 1080)
	background.color = Color("#1d2422")
	_page.add_child(background)
	var heading := Label.new()
	heading.text = _title + " · 本幕收场"
	heading.position = Vector2(200, 280)
	heading.size = Vector2(1520, 80)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 48)
	heading.add_theme_color_override("font_color", Color("#e7c590"))
	_page.add_child(heading)
	var detail := Label.new()
	detail.text = "想从幕前看看刚才的演出吗？" if choice else "这一幕已经落下帷幕。"
	detail.position = Vector2(200, 400)
	detail.size = Vector2(1520, 70)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 32)
	_page.add_child(detail)
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


func _exit_tree() -> void:
	if _flow != null:
		_flow.leave_stage()
