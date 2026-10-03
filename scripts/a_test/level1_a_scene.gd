extends Node2D
## 第一关正式 A 侧运行入口：只显示幕后占位表现、A 状态、提示、补救和事件接收结果。

const HarnessScript := preload("res://scripts/a_test/level1_harness.gd")
const ProbeScript := preload("res://scripts/a_test/level1_a_probe.gd")
const LampControllerScript := preload("res://scripts/a/lamp_controller.gd")
const CueScript := preload("res://scripts/a/cue.gd")
const StageDefScript := preload("res://scripts/a/stage_def.gd")

const CANVAS_SIZE := Vector2(1920.0, 1080.0)
const PROBE_FLAG := "level1_a_probe"
const RECEIVER_LOG_LIMIT := 14

@onready var _puppet: PlaceholderPuppet = $Puppet
@onready var _lamp: PlaceholderLamp = $Lamp
@onready var _state_label: RichTextLabel = $Hud/StatePanel/StateLabel
@onready var _cue_label: RichTextLabel = $Hud/CuePanel/CueLabel
@onready var _clock_label: RichTextLabel = $Hud/ClockPanel/ClockLabel
@onready var _event_label: RichTextLabel = $Hud/EventPanel/EventLabel
@onready var _hint_label: Label = $Hud/HintLabel

var _harness: Object = null
var _stage_def: StageDef = null
var _received: Array = []
var _frame_events: Array[Dictionary] = []
var _paused: bool = false
var _probe_mode: bool = false
var _shutting_down: bool = false


func _ready() -> void:
	var window: Window = get_window()
	window.size = Vector2i(1280, 720)
	window.content_scale_size = Vector2i(int(CANVAS_SIZE.x), int(CANVAS_SIZE.y))
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	_stage_def = StageDefScript.make_level1()
	_harness = HarnessScript.new(self)
	if _harness.runtime == null:
		_shutdown_and_quit(1)
		return
	_puppet.puppet_state = _harness.runtime.puppet_controller.get_controlled()
	_puppet.stage_origin = Vector2.ZERO
	_puppet.stage_size = PuppetController.STAGE_PIXEL_SIZE
	_lamp.lamp = _harness.runtime.lamp_controller.lamp
	_lamp.anchor = Vector2(1280.0, 900.0)
	_hint_label.text = "第一关 · 拖动胸签 · A/D/W/S 操控双手 · Q/E 调灯 · 滚轮推拉 · 空格暂停 · Esc 退出"
	if OS.get_cmdline_args().has(PROBE_FLAG) or OS.get_cmdline_user_args().has(PROBE_FLAG):
		_probe_mode = true
		var probe := ProbeScript.new()
		var failures: int = probe.run(_harness)
		_shutdown_and_quit(1 if failures > 0 else 0)


func _process(delta: float) -> void:
	if _probe_mode or _harness == null:
		return
	_harness.advance(delta)
	_consume_events()
	_refresh_hud()


func _input(event: InputEvent) -> void:
	if _harness == null:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_SPACE:
			_set_paused(not _paused)
			get_viewport().set_input_as_handled()
			return
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			_shutdown_and_quit(0)
			return
	if not _paused and _harness.handle_input(event):
		get_viewport().set_input_as_handled()


func _set_paused(value: bool) -> void:
	_paused = value
	_harness.set_paused(value)


func _consume_events() -> void:
	_frame_events = _harness.take_events()
	if _frame_events.is_empty():
		return
	# 接收端只按**油灯**的事件契约校验 object_id 必须是字符串 "lamp_main"；
	# 判定/操控事件（影人 0-2）的 object_id 是 int，交给它会被判成畸形事件。
	# 这里按 object_id 分流：油灯事件走校验，其他事件原样进面板。
	for event in _frame_events:
		var is_lamp: bool = (typeof(event.get("object_id", null)) == TYPE_STRING)
		if is_lamp:
			_received.append_array(LampControllerScript.receive_events([event]))
		else:
			_received.append(event)
	if _received.size() > RECEIVER_LOG_LIMIT * 5:
		_received = _received.slice(_received.size() - RECEIVER_LOG_LIMIT * 3)


func _refresh_hud() -> void:
	var runtime: Object = _harness.runtime
	var state: PuppetState = runtime.puppet_controller.get_controlled()
	var lamp: LampState = runtime.lamp_controller.lamp
	_puppet.puppet_state = state
	_lamp.lamp = lamp
	var status := "已暂停" if _paused else ("已结束" if runtime.is_over() else "演出中")
	var state_lines: Array[String] = [
		"[b]第一关 A 侧状态[/b]",
		"运行状态：%s    FPS：%d" % [status, Engine.get_frames_per_second()],
		"puppet_id=%d  stage_pos=(%.3f, %.3f)  stance=%.3f" %
			[state.puppet_id, state.stage_pos.x, state.stage_pos.y, state.stance],
		"facing=%+.3f  hand=(%+.3f, %+.3f)" %
			[state.facing, state.hand_angle.x, state.hand_angle.y],
		"distance=%.4f  exposure=%.4f" % [lamp.distance, lamp.exposure],
		"oil=%.4f  flame_feedback=%.4f" % [lamp.oil, lamp.flame_feedback],
		"LampState 合法范围：%s" % ("通过" if lamp.is_in_range() else "越界"),
	]
	_state_label.text = "\n".join(state_lines)
	_refresh_clock_panel(runtime)
	_refresh_cue_panel(runtime)
	_refresh_event_panel()


func _refresh_clock_panel(runtime: Object) -> void:
	var song_ms: int = _harness.clock.get_song_time_ms()
	var progress: float = clampf(float(song_ms) / float(_stage_def.duration_ms), 0.0, 1.0)
	_clock_label.text = "\n".join([
		"[b]MusicClock / 第一关时间线[/b]",
		"歌曲时间：%d / %d ms" % [song_ms, _stage_def.duration_ms],
		"进度：%s" % _bar(progress),
		"BPM：%.1f    时钟来源：%s" % [_stage_def.bpm,
			"音频播放位置" if _harness.clock.is_audio_driven() else "自由计时"],
		"暂停：%s    演出结束：%s" % ["是" if _paused else "否", "是" if runtime.is_over() else "否"],
		"临时节拍音：%s" % ("播放中" if _harness.metronome.is_active() else "不可用"),
	])


func _refresh_cue_panel(runtime: Object) -> void:
	var performance: PerformanceSystem = runtime.director.performance
	var remedy: RemedySystem = runtime.director.remedy
	var song_ms: int = _harness.clock.get_song_time_ms()
	var active: Array[String] = []
	var segment_name: String = ""
	for segment in _stage_def.segments:
		if song_ms >= int(segment["start_ms"]) and song_ms < int(segment["end_ms"]):
			segment_name = str(segment["name"])
			break
	for cue in _stage_def.cues:
		var cue_id: String = str(cue["cue_id"])
		if performance.has_outcome(cue_id):
			continue
		if song_ms >= CueScript.hint_time_ms(cue):
			active.append("%s(%s)" % [_action_label(str(cue["action"])), cue_id])
	var demo: String = "无"
	var remaining: int = 0
	if not remedy.current_demo_cue_id.is_empty():
		demo = remedy.current_demo_cue_id
		remaining = remedy.remaining_ms(demo, song_ms)
	var lines: Array[String] = [
		"[b]Cue / 补救提示数据[/b]",
		"当前段落：%s" % (segment_name if not segment_name.is_empty() else "演出结束"),
		"当前线索：%s" % ("、".join(active) if not active.is_empty() else "无"),
		"补救示范：%s    剩余：%d ms" % [demo, remaining],
		"已判定：%d / %d    开放窗口：%d" %
			[_stage_def.cues.size() - performance.pending_count(), _stage_def.cues.size(), remedy.open_count()],
	]
	_cue_label.text = "\n".join(lines)


func _refresh_event_panel() -> void:
	var lines: Array[String] = [
		"[b]TimedEvent / 模拟接收端[/b]",
		"本帧事件：%d    累计接收：%d" % [_frame_events.size(), _received.size()],
	]
	var start: int = maxi(_received.size() - RECEIVER_LOG_LIMIT, 0)
	for i in range(start, _received.size()):
		var event: Dictionary = _received[i]
		var payload: Dictionary = event["payload"]
		lines.append("t=%-5d %-20s obj=%s cue=%s" %
			[int(event["time_ms"]), str(event["kind"]), str(event["object_id"]), str(event["cue_id"])])
		lines.append("  payload: %s" % str(payload))
	if _received.is_empty():
		lines.append("（尚未收到事件）")
	_event_label.text = "\n".join(lines)


func _action_label(action: String) -> String:
	match action:
		CueScript.ACTION_STAND_UP: return "站起"
		CueScript.ACTION_CROUCH: return "蹲下"
		CueScript.ACTION_HAND_RAISE: return "抬手"
		CueScript.ACTION_MOVE_LEFT: return "向左移动"
		CueScript.ACTION_MOVE_RIGHT: return "向右移动"
		CueScript.ACTION_REACH: return "移动到目标位"
	return action


func _bar(value: float) -> String:
	var filled: int = int(round(clampf(value, 0.0, 1.0) * 12.0))
	return "[%s%s]" % ["#".repeat(filled), "-".repeat(12 - filled)]


func _shutdown_and_quit(code: int) -> void:
	if _shutting_down:
		return
	_shutting_down = true
	if _harness != null:
		_harness.shutdown()
	get_tree().quit(code)
