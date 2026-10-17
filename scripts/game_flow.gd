extends Node
## 正式入口：首页 → 片头 → 三关演出与真实回放 → 片尾 → 首页。

const PERFORMANCE_SCENE := preload("res://scenes/a_test/level1_a.tscn")
const ACT2_SCENE := preload("res://scenes/act2/opening.tscn")
const HALL_SCENE := preload("res://scenes/act2/hall.tscn")
const ACT3_SCENE := preload("res://scenes/act3/opening.tscn")
const Act2Capture := preload("res://scripts/c/c_act2_capture.gd")
const ReplayView := preload("res://scripts/b/performance_replay.gd")
const MediaScreen := preload("res://scripts/ui/media_screen.gd")
const TITLE_IMAGE := preload("res://assets/cinematics/title.png")
const INTRO_VIDEO := preload("res://assets/cinematics/intro.ogv")
const OUTRO_VIDEO := preload("res://assets/cinematics/outro.ogv")
const OUTRO_LAST_IMAGE := preload("res://assets/cinematics/outro-last.png")
## 关卡/幕编号。第二关分两场，各占一个编号：第一场「法海劝酒」= 2，
## 第二场「端阳饮酒」= 22（与 `CSceneryDef.LEVEL2_ACT2_STAGE_ID` 同值）。
const ACT2_STAGE_ID: int = 2
const ACT2_HALL_STAGE_ID: int = 22
## 演示用跳关按钮的节点名。关卡场景的输入层按这个名字把按钮区域的左键按下
## 及其配对松开交给 GUI（`act2_opening.gd` / `act2_hall.gd` / `level1_a_scene.gd`）。
const SKIP_ACT1_BUTTON: String = "SkipAct1Button"
const SKIP_ACT2_BUTTON: String = "SkipAct2Button"
## 专用排练入口沿用正式收场与回放流程，不必先演前两关。
@export_range(1, 3, 1) var initial_stage: int = 1
var _level: Node = null
var _replay: Node = null
var _page: Control = null
var _flow: CResultFlow = null
var _stage_id: int = 1
var _title: String = ""
var _advancing: bool = false
var _act2_capture: RefCounted
var _result_ready: bool = false


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--act3-rehearsal"):
		_stage_id = 3
	elif initial_stage in [2, 3]:
		_stage_id = initial_stage
	elif _stage_id == 1:
		_show_home()
		return
	_start_performance()


func _show_home() -> void:
	_clear_page()
	if _flow != null:
		_flow.leave_stage()
		_flow = null
	_stage_id = 1
	_title = ""
	_advancing = false
	var home := MediaScreen.new()
	home.name = "HomeScreen"
	home.image = TITLE_IMAGE
	home.finished.connect(_play_intro, CONNECT_DEFERRED)
	_page = home
	add_child(home)


func _play_intro() -> void:
	_clear_page()
	var intro := MediaScreen.new()
	intro.name = "IntroVideo"
	intro.stream = INTRO_VIDEO
	intro.finished.connect(_intro_finished, CONNECT_DEFERRED)
	_page = intro
	add_child(intro)


func _intro_finished() -> void:
	_clear_page()
	_start_performance()


func _play_outro() -> void:
	_clear_page()
	if _flow != null:
		_flow.leave_stage()
		_flow = null
	var outro := MediaScreen.new()
	outro.name = "OutroVideo"
	outro.stream = OUTRO_VIDEO
	outro.end_image = OUTRO_LAST_IMAGE
	outro.finished.connect(_show_home, CONNECT_DEFERRED)
	_page = outro
	add_child(outro)


func _start_performance() -> void:
	if _stage_id == 3:
		_level = ACT3_SCENE.instantiate()
		_level.performance_finished.connect(_performance_finished)
		add_child(_level)
		return
	if _stage_id == ACT2_HALL_STAGE_ID:
		if _act2_capture == null:
			_act2_capture = Act2Capture.new()
		_level = HALL_SCENE.instantiate()
		_level.capture = _act2_capture
		_level.scene_finished.connect(_on_second_scene_finished)
		add_child(_level)
		_add_skip_button(_level, SKIP_ACT2_BUTTON, "跳过第二关", _skip_act2)
		return
	if _stage_id == ACT2_STAGE_ID:
		_act2_capture = Act2Capture.new()
		_level = ACT2_SCENE.instantiate()
		_level.capture = _act2_capture
		# 第一幕末句应允 → 暗场 → 清场，走完章节卡后换景进第二幕（不结算、不回放）。
		_level.scene_finished.connect(_on_first_scene_finished)
		add_child(_level)
		_add_skip_button(_level, SKIP_ACT2_BUTTON, "跳过第二关", _skip_act2)
		return
	_level = PERFORMANCE_SCENE.instantiate()
	_level.performance_finished.connect(_performance_finished)
	add_child(_level)
	_add_skip_button(_level, SKIP_ACT1_BUTTON, "跳过第一关", _skip_act1)


## 演示用跳关按钮：注入当前关卡的 `Hud`，放在右上角与暂停按钮同一行。
## 第二关两场（编号 2 / 22）各注入一个，因此从第二关任一场次都能直接进第三关；
## 第三关不再保留。按钮只在正式入口创建，单场景调试入口没有它。
func _add_skip_button(level: Node, button_name: String, text: String, action: Callable) -> void:
	var hud := level.get_node_or_null("Hud")
	if hud == null:
		push_error("%s 缺少 Hud，无法注入跳关按钮" % level.name)
		return
	var skip := Button.new()
	skip.name = button_name
	skip.text = text
	skip.position = Vector2(1506, 15)
	skip.size = Vector2(240, 52)
	skip.add_theme_font_size_override("font_size", 24)
	skip.pressed.connect(action)
	hud.add_child(skip)


func _skip_act1() -> void:
	if _advancing or _stage_id != 1 or _level == null:
		return
	_advancing = true
	_level.get_node("Hud/" + SKIP_ACT1_BUTTON).disabled = true
	_level.set_process(false)
	_level.set_process_input(false)
	_advance_to_act2.call_deferred()


## 跳过第二关：停住旧场次（含厅堂的整关录制）、释放记录，直接加载第三关入口。
## 与跳过第一关同构：点击后禁止重复切换，跳过时到达的完成信号不进入回放选择。
func _skip_act2() -> void:
	if _advancing or _stage_id not in [ACT2_STAGE_ID, ACT2_HALL_STAGE_ID] or _level == null:
		return
	_advancing = true
	var button := _level.get_node_or_null("Hud/" + SKIP_ACT2_BUTTON) as Button
	if button != null:
		button.disabled = true
	_level.set_process(false)
	_level.set_process_input(false)
	_advance_to_act3.call_deferred()


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
	_act2_capture = null
	_show_page(true)


func _show_page(choice: bool) -> void:
	if not choice and _stage_id == 3:
		_play_outro()
		return
	_clear_page()
	_result_ready = false
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
	if not choice and _stage_id in [1, 2]:
		detail.text = "点击任意位置，进入第二关《端阳惊变》" if _stage_id == 1 else "点击任意位置，进入第三关《盗仙草》"
		_arm_result_click.call_deferred()
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
	_result_ready = false


func _arm_result_click() -> void:
	_result_ready = _flow != null and _flow.get_flow_state() == &"result" and _page != null


func _unhandled_input(event: InputEvent) -> void:
	if (
		_advancing
		or not _result_ready
		or _stage_id not in [1, 2]
		or _flow == null
		or _flow.get_flow_state() != &"result"
	):
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		return
	get_viewport().set_input_as_handled()
	_advancing = true
	if _stage_id == 1:
		_advance_to_act2.call_deferred()
	else:
		_advance_to_act3.call_deferred()


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


func _advance_to_act3() -> void:
	_clear_page()
	# 收场点击进入本函数时 `_level` 已在 `_performance_finished` 里释放；
	# 「跳过第二关」直接进本函数，宿主还在树上，必须在这里释放（移出场景树触发
	# 各场次既有 `_exit_tree`：停时钟、停主轨、放补救鼓）。
	if _level != null:
		remove_child(_level)
		_level.queue_free()
		_level = null
	if _flow != null:
		_flow.leave_stage()
		_flow = null
	_act2_capture = null
	_stage_id = 3
	_start_performance()
	_advancing = false


func _on_second_scene_finished() -> void:
	_finish_act2.call_deferred()


func _finish_act2() -> void:
	if _stage_id != ACT2_HALL_STAGE_ID or _act2_capture == null or not _act2_capture.finished:
		return
	_performance_finished(_act2_capture.record, 2, "端阳惊变")


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
