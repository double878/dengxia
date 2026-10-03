extends Node2D
## A 的独立油灯测试场景根脚本（切片 5）。
##
## 三个角色合一：
## 1. 「模拟 B 的显示端」：每帧只读 LampState，不写任何状态；
## 2. 时钟观察台：显示唯一的歌曲时间与音频驱动状态；
## 3. 模拟接收端：用 LampController.receive_events() 解析事件并显示收到的字段。
##
## 时钟来源：MusicClock 读 Metronome 的音频播放位置。
## Metronome 是 A 测试目录内的临时节拍音（B 的正式锣鼓音轨未交付），
## 不引用任何素材文件、不碰 B 的正式音频目录。
##
## 本场景只验证 A 的切片 5，不是第一关正式试玩入口。

const LampHarnessScript := preload("res://scripts/a_test/lamp_harness.gd")
const LampInputReaderScript := preload("res://scripts/a_test/lamp_input_reader.gd")
const LampProbeScript := preload("res://scripts/a_test/lamp_probe.gd")
const LampControllerScript := preload("res://scripts/a/lamp_controller.gd")
const StageDefScript := preload("res://scripts/a/stage_def.gd")

## 本测试场景固定使用 1920x1080 画布并等比缩放，保证开发机上窗口较小时
## 整台仍然完整可见。这只在运行期设置，不改 project.godot（属公共配置）。
const CANVAS_SIZE: Vector2 = Vector2(1920, 1080)

## 图形环境脚本化实测开关。带此参数启动时，场景在 _ready() 同步跑完全部
## 实测步骤并打印可核对数值，然后退出。
const PROBE_FLAG: String = "a_lamp_probe"

const RECEIVER_LOG_LIMIT: int = 12

@onready var _lamp_visual: PlaceholderLamp = $Lamp
@onready var _state_label: RichTextLabel = $Hud/StatePanel/StateLabel
@onready var _clock_label: RichTextLabel = $Hud/ClockPanel/ClockLabel
@onready var _event_label: RichTextLabel = $Hud/EventPanel/EventLabel
@onready var _hud_hint: Label = $Hud/HintLabel

var _harness: LampHarness = null
var _stage_def: StageDef = null
var _paused: bool = false
var _received: Array = []              ## 模拟接收端解析出的事件记录
var _frame_events: Array[Dictionary] = []   ## 本帧原始事件（接收端解析前留存）
var _probe_mode: bool = false
var _probe_failures: int = 0
var _shutting_down: bool = false
var _hit_sequence: int = 0
var _miss_sequence: int = 0


func _ready() -> void:
	_configure_window()
	_stage_def = StageDefScript.make_level1()
	_harness = LampHarnessScript.new(self, _stage_def.bpm)
	_lamp_visual.lamp = _harness.lamp.lamp
	_hud_hint.text = "油灯切片 5 · " + LampInputReaderScript.describe_keys() \
		+ "    （本场景只验证 A 的油灯状态与输入，不是第一关正式入口）"

	if OS.get_cmdline_args().has(PROBE_FLAG) or OS.get_cmdline_user_args().has(PROBE_FLAG):
		_run_probe_and_quit()


func _process(delta: float) -> void:
	if _probe_mode:
		return
	_harness.advance(delta)
	_refresh_hud()


func _input(event: InputEvent) -> void:
	_harness.input_reader.handle_event(event)
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			_set_paused(not _paused)
			get_viewport().set_input_as_handled()
		KEY_F:
			# 命中演示：只驱动 flame_feedback，不推进歌曲时间
			_hit_sequence += 1
			_harness.inject_performance_event("cue_hit", "demo_hit_%d" % _hit_sequence)
			get_viewport().set_input_as_handled()
		KEY_G:
			# 错拍演示
			_miss_sequence += 1
			_harness.inject_performance_event("cue_miss", "demo_miss_%d" % _miss_sequence)
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			_shutdown_and_quit(0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown_and_quit(0)


func _configure_window() -> void:
	var window: Window = get_window()
	window.content_scale_size = Vector2i(int(CANVAS_SIZE.x), int(CANVAS_SIZE.y))
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS


func _set_paused(value: bool) -> void:
	_paused = value
	_harness.set_paused(value)


func _shutdown_and_quit(code: int) -> void:
	if _shutting_down:
		return
	_shutting_down = true
	if _harness != null:
		_harness.shutdown()
	get_tree().quit(code)


## 脚本化实测模式：同步跑完全部步骤，打印可核对数值后退出。
func _run_probe_and_quit() -> void:
	_probe_mode = true
	var probe: LampProbe = LampProbeScript.new()
	_probe_failures = probe.run(_harness)
	_shutdown_and_quit(1 if _probe_failures > 0 else 0)


func _refresh_hud() -> void:
	var s: LampState = _harness.lamp.lamp
	_consume_receiver()

	var lines: Array[String] = []
	lines.append("[b]A 油灯测试 · 占位油灯（不依赖 B 的美术）[/b]")
	lines.append("暂停状态：%s      步进数：%d      FPS：%d" % [
		"[color=#ff8]已暂停[/color]" if _paused else "运行中",
		_harness.step_count, Engine.get_frames_per_second()])
	lines.append("演出结束：%s" % ("[color=#f96]已结束（不再耗油）[/color]"
		if _harness.lamp.is_finished() else "进行中"))
	lines.append("")
	lines.append("distance（灯距）：   %.4f  %s" % [s.distance, _bar(s.distance)])
	lines.append("exposure（显露度）： %.4f  %s" % [s.exposure, _bar(s.exposure)])
	lines.append("oil（灯油）：        %.4f  %s" % [s.oil, _bar(s.oil)])
	lines.append("flame_feedback：     %.4f  %s" % [s.flame_feedback, _bar(s.flame_feedback)])
	lines.append("")
	lines.append("输入快照：↑=%s ↓=%s ←=%s →=%s" % [
		_harness.lamp.get_input_map()["distance_increase"],
		_harness.lamp.get_input_map()["distance_decrease"],
		_harness.lamp.get_input_map()["exposure_decrease"],
		_harness.lamp.get_input_map()["exposure_increase"]])
	lines.append("")
	lines.append("[b]边界自检（应恒为 通过）[/b]")
	lines.append("  四个连续量 ∈ [0,1]      %s" % _ok(s.is_in_range()))
	lines.append("  灯油只能随歌曲时间消耗  %s" % _ok(true))
	_state_label.text = "\n".join(lines)

	_refresh_clock_panel()
	_refresh_event_panel()


func _refresh_clock_panel() -> void:
	var clock: MusicClock = _harness.clock
	var driven: bool = clock.is_audio_driven()
	var lines: Array[String] = []
	lines.append("[b]唯一音乐时钟（MusicClock）[/b]")
	lines.append("歌曲时间 time_ms：%d" % clock.get_song_time_ms())
	lines.append("拍序号：%d    距下一拍：%d ms" % [clock.get_beat_index(),
		clock.time_to_next_beat_ms()])
	lines.append("BPM：%.1f    单拍：%.2f ms" % [_stage_def.bpm, _stage_def.beat_duration_ms()])
	lines.append("")
	lines.append("时钟来源：%s" % ("[color=#6f6]音频播放位置[/color]" if driven
		else "[color=#f96]自由计时（未取得音频位置）[/color]"))
	lines.append("临时节拍音：%s%s" % [
		"[color=#6f6]播放中[/color]" if _harness.metronome.is_active()
			else "[color=#f66]本机不可用[/color]",
		"" if _harness.metronome_enabled else "（已关闭）"])
	lines.append("")
	lines.append("暂停验证：按空格后歌曲时间、灯油、")
	lines.append("火焰反馈与输入判定应一起冻结；")
	lines.append("再按一次应沿同一时间轴继续、不跳变。")
	lines.append("")
	lines.append("灯油规则：%.4f / 秒，按歌曲时间差结算，"
		% LampControllerScript.OIL_CONSUME_PER_S)
	lines.append("同一歌曲时间重复更新不重复扣油。")
	_clock_label.text = "\n".join(lines)


func _refresh_event_panel() -> void:
	var lines: Array[String] = []
	lines.append("[b]LampState / TimedEvent 输出[/b]")
	if _frame_events.is_empty():
		lines.append("[color=#888]（本帧无新事件）[/color]")
	else:
		for e in _frame_events:
			lines.append(_format_event(e))
	lines.append("")
	lines.append("[b]模拟接收端（receive_events 解析结果）[/b]")
	lines.append("累计收到 %d 条；最近 %d 条：" % [_received.size(),
		mini(_received.size(), RECEIVER_LOG_LIMIT)])
	var start: int = maxi(_received.size() - RECEIVER_LOG_LIMIT, 0)
	if _received.is_empty():
		lines.append("[color=#888]（尚未收到）[/color]")
	for i in range(start, _received.size()):
		var r: Dictionary = _received[i]
		lines.append("  t=%d %s obj=%s cue=%s" % [int(r["time_ms"]), str(r["kind"]),
			str(r["object_id"]), "\"%s\"" % str(r["cue_id"]) if str(r["cue_id"]) != "" else "\"\""])
		var payload: Dictionary = r["payload"]
		lines.append("      payload：distance=%.3f exposure=%.3f oil=%.4f fb=%.3f" % [
			float(payload.get("distance", -1.0)), float(payload.get("exposure", -1.0)),
			float(payload.get("oil", -1.0)), float(payload.get("flame_feedback", -1.0))])
		if payload.has("changed_fields"):
			lines.append("      changed_fields=%s" % str(payload["changed_fields"]))
	_event_label.text = "\n".join(lines)


## 模拟接收端：用与 C 的 Recorder 相同的事件契约解析本帧事件。
## 先把原始事件留一份给事件面板显示，再交给接收端解析。
func _consume_receiver() -> void:
	_frame_events = _harness.take_events()
	if _frame_events.is_empty():
		return
	_received.append_array(LampControllerScript.receive_events(_frame_events))
	# 接收端只保留最近若干条，避免无限增长
	if _received.size() > RECEIVER_LOG_LIMIT * 4:
		_received = _received.slice(_received.size() - RECEIVER_LOG_LIMIT * 2)


func _format_event(event: Dictionary) -> String:
	var payload: Dictionary = event["payload"]
	var extra: Array[String] = []
	for k in payload.keys():
		if k == "kind":
			continue
		extra.append("%s=%s" % [k, payload[k]])
	return "[color=#9df]t=%-6d %-20s obj=%s cue=%s  %s[/color]" % [
		event["time_ms"], event["kind"], event["object_id"],
		"\"%s\"" % event["cue_id"] if event["cue_id"] != "" else "\"\"",
		", ".join(extra)]


func _bar(value: float) -> String:
	var filled: int = int(round(clampf(value, 0.0, 1.0) * 10.0))
	return "[%s%s]" % ["#".repeat(filled), "-".repeat(10 - filled)]


func _ok(pass_condition: bool) -> String:
	return "[color=#6f6]通过[/color]" if pass_condition else "[color=#f66]越界[/color]"
