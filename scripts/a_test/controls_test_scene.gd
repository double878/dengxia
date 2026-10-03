extends Node2D
## A 的独立操控测试场景根脚本。
## 「模拟 B 的显示端」+「调试 HUD」：每帧先 tick，再只读 PuppetState 与 TimedEvent，
## 不写任何状态，用来证明「状态先变化，再供表现和录制读取」这条单向数据流成立。

const ControlsHarnessScript := preload("res://scripts/a_test/controls_harness.gd")
const PlaceholderPuppetScript := preload("res://scripts/a_test/placeholder_puppet.gd")
const ControlsProbeScript := preload("res://scripts/a_test/controls_probe.gd")

const STAGE_ORIGIN: Vector2 = Vector2(0.0, 150.0)
const STAGE_SIZE: Vector2 = Vector2(1920.0, 640.0)
const MAX_EVENT_LINES: int = 16

## 图形环境脚本化实测开关。带此参数启动时，场景在 _ready() 同步跑完全部
## 实测步骤并打印可核对数值，然后退出——用于给「无法注入真实输入」的
## 验证者留下可复现的图形环境证据。正常游玩时不带此参数。
const PROBE_FLAG: String = "a_controls_probe"

@onready var _puppet: PlaceholderPuppet = $Puppet
@onready var _state_label: RichTextLabel = $Hud/StatePanel/StateLabel
@onready var _event_label: RichTextLabel = $Hud/EventPanel/EventLabel
@onready var _hud_hint: Label = $Hud/HintLabel

## 本测试场景固定使用 1920x1080 画布并等比缩放，保证开发机上窗口较小时
## 整台仍然完整可见。这只在运行期设置，不改 project.godot（属公共配置）。
const CANVAS_SIZE: Vector2 = Vector2(1920.0, 1080.0)

var _harness: ControlsHarness = null
var _paused: bool = false


func _ready() -> void:
	var window: Window = get_window()
	window.content_scale_size = Vector2i(int(CANVAS_SIZE.x), int(CANVAS_SIZE.y))
	# EXPAND：保留设计分辨率与等比缩放，同时让舞台在窗口比例不同时也不会被裁掉
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS

	_harness = ControlsHarnessScript.new(3)
	_sync_stage_to_canvas_scale()
	var puppet_state: PuppetState = _harness.controller.get_controlled()
	_puppet.puppet_state = puppet_state
	_puppet.stage_origin = STAGE_ORIGIN
	_puppet.stage_size = STAGE_SIZE
	_hud_hint.text = "鼠标左键按住胸签圆圈拖动 = 横向移动 / 纵向站蹲 / 沿移动方向转身    " \
		+ "A=抬左手  D=抬右手  Shift+A=落左手  Shift+D=落右手  W=双手抬  S=双手落    " \
		+ "空格=暂停/继续（音频、时间、判定一起冻结）"

	if OS.get_cmdline_args().has(PROBE_FLAG) or OS.get_cmdline_user_args().has(PROBE_FLAG):
		_run_probe_and_quit()


## 脚本化实测模式：同步跑完探针，打印结果并以退出码反映是否符合预期。
func _run_probe_and_quit() -> void:
	var probe: ControlsProbe = ControlsProbeScript.new()
	var failures: int = probe.run()
	get_tree().quit(1 if failures > 0 else 0)


func _process(delta: float) -> void:
	_sync_stage_to_canvas_scale()
	_harness.advance(delta)
	_refresh_hud()


## 画布等比缩放时，鼠标事件落在虚拟画布坐标空间里。
## 舞台固定为 1920x1080，与画布同尺寸时换算系数为 1.0，手感与开发分辨率一致。
func _sync_stage_to_canvas_scale() -> void:
	var scale: float = get_window().content_scale_factor
	if scale <= 0.0:
		scale = 1.0
	_harness.input_reader.scale_factor = scale


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_SPACE:
			_paused = not _paused
			_harness.set_paused(_paused)
			get_viewport().set_input_as_handled()
			return
	_harness.input_reader.handle_event(event)


func _notification(what: int) -> void:
	# 失去焦点时收尾拖动，避免「松手事件丢失 → 影人粘着鼠标」
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _harness != null:
		_harness.input_reader.release_drag()


func _refresh_hud() -> void:
	var state: PuppetState = _harness.controller.get_controlled()
	_puppet.puppet_state = state
	var input_map: Dictionary = _harness.controller.get_input_map()

	var lines: Array[String] = []
	lines.append("[b]A 操控测试 · 占位影人（不依赖 B 的美术）[/b]")
	lines.append("暂停状态：%s    步进数：%d" % ["[color=#ff8]已暂停[/color]" if _paused else "运行中",
		_harness.get_step_count()])
	lines.append("歌曲时间 time_ms：%d" % _harness.clock.get_song_time_ms())
	lines.append("")
	lines.append("puppet_id：%d    受控：%s" % [state.puppet_id, state.is_controlled])
	lines.append("stage_pos：x=%.4f  y=%.4f   （0-1，接地点）" % [state.stage_pos.x, state.stage_pos.y])
	lines.append("stance：%.4f   %s" % [state.stance, _bar(state.stance)])
	lines.append("facing：%+.4f   转身进度 turn_progress：%.4f" % [state.facing, state.turn_progress])
	lines.append("hand_angle：左手 %+.4f  右手 %+.4f  （弧度）" % [state.hand_angle.x, state.hand_angle.y])
	lines.append("head_id：%d    hook_slot：%d" % [state.head_id, state.hook_slot])
	lines.append("拖动中：%s" % _harness.input_reader.is_drag_active())
	lines.append("")
	lines.append("输入快照：A=%s Shift+A=%s D=%s Shift+D=%s W=%s S=%s" % [
		input_map["left_raise"], input_map["left_lower"],
		input_map["right_raise"], input_map["right_lower"],
		input_map["both_raise"], input_map["both_lower"]])
	lines.append("")
	lines.append("边界自检（应恒为 通过）：")
	lines.append("  stage_pos ∈ [0,1]        %s" % _ok(_in_unit(state.stage_pos.x) and _in_unit(state.stage_pos.y)))
	lines.append("  stance ∈ [0,1]           %s" % _ok(state.stance >= 0.0 and state.stance <= 1.0))
	lines.append("  facing ∈ [-1,1]          %s" % _ok(state.facing >= -1.0 and state.facing <= 1.0))
	lines.append("  |hand_angle| ≤ 0.6 rad   %s" % _ok(absf(state.hand_angle.x) <= 0.6 + 1e-6
		and absf(state.hand_angle.y) <= 0.6 + 1e-6))
	_state_label.text = "\n".join(lines)

	var events: Array[Dictionary] = _harness.controller.take_events()
	var event_lines: Array[String] = []
	event_lines.append("[b]TimedEvent 流（取走即清空）[/b]")
	if events.is_empty():
		event_lines.append("[color=#888]（无新事件）[/color]")
	else:
		for e in events:
			event_lines.append(_format_event(e))
	_event_label.text = "\n".join(event_lines)


func _format_event(event: Dictionary) -> String:
	var payload: Dictionary = event["payload"]
	var extra: Array[String] = []
	for k in payload.keys():
		if k == "kind":
			continue
		extra.append("%s=%s" % [k, payload[k]])
	return "t=%-6d %-14s obj=%d cue=%s  %s" % [
		event["time_ms"], event["kind"], event["object_id"],
		"\"%s\"" % event["cue_id"] if event["cue_id"] != "" else "\"\"",
		", ".join(extra)]


func _bar(value: float) -> String:
	var filled: int = int(round(clampf(value, 0.0, 1.0) * 10.0))
	return "[%s%s]" % ["#".repeat(filled), "-".repeat(10 - filled)]


func _in_unit(value: float) -> bool:
	return value >= 0.0 and value <= 1.0


func _ok(pass_condition: bool) -> String:
	return "[color=#6f6]通过[/color]" if pass_condition else "[color=#f66]越界[/color]"
