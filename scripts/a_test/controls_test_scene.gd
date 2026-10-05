extends Node2D
## A 的独立操控 + 音乐时钟测试场景根脚本。
##
## 三个角色合一：
## 1. 「模拟 B 的显示端」：每帧只读 PuppetState 与 TimedEvent，不写任何状态；
## 2. 时钟观察台：显示唯一的歌曲时间、拍序号与音频驱动状态；
## 3. 脚本化实测宿主：带 a_controls_probe 参数启动时同步跑完探针并退出。
##
## 时钟来源：MusicClock 读 Metronome 的音频播放位置。
## Metronome 是 A 测试目录内的临时节拍音（B 的正式锣鼓音轨未交付），
## 不引用任何素材文件、不碰 B 的正式音频目录。

const ControlsHarnessScript := preload("res://scripts/a_test/controls_harness.gd")
const PlaceholderPuppetScript := preload("res://scripts/a_test/placeholder_puppet.gd")
const ControlsProbeScript := preload("res://scripts/a_test/controls_probe.gd")
const CueProbeScript := preload("res://scripts/a_test/cue_probe.gd")
const ClockCheckScript := preload("res://scripts/a_test/clock_check.gd")
const MusicClockScript := preload("res://scripts/a/music_clock.gd")
const MetronomeScript := preload("res://scripts/a_test/metronome.gd")
const StageDefScript := preload("res://scripts/a/stage_def.gd")
const PerformanceSystemScript := preload("res://scripts/a/performance_system.gd")
const CueScript := preload("res://scripts/a/cue.gd")

const STAGE_ORIGIN: Vector2 = Vector2(0.0, 150.0)
const STAGE_SIZE: Vector2 = Vector2(1920.0, 640.0)

## 本测试场景固定使用 1920x1080 画布并等比缩放，保证开发机上窗口较小时
## 整台仍然完整可见。这只在运行期设置，不改 project.godot（属公共配置）。
const CANVAS_SIZE: Vector2 = Vector2(1920.0, 1080.0)

## 图形环境脚本化实测开关。带此参数启动时，场景在 _ready() 同步跑完全部
## 实测步骤并打印可核对数值，然后退出——用于给「无法注入真实输入」的
## 验证者留下可复现的图形环境证据。正常游玩时不带此参数。
const PROBE_FLAG: String = "a_controls_probe"

@onready var _puppet: PlaceholderPuppet = $Puppet
@onready var _state_label: RichTextLabel = $Hud/StatePanel/StateLabel
@onready var _cue_label: RichTextLabel = $Hud/CuePanel/CueLabel
@onready var _clock_label: RichTextLabel = $Hud/ClockPanel/ClockLabel
@onready var _event_label: RichTextLabel = $Hud/EventPanel/EventLabel
@onready var _hud_hint: Label = $Hud/HintLabel

var _harness: ControlsHarness = null
var _clock: MusicClock = null
var _metronome: Metronome = null
var _stage_def: StageDef = null
var _performance: PerformanceSystem = null
var _paused: bool = false
var _metronome_enabled: bool = true
var _last_crossing_ms: int = -1
var _crossing_count: int = 0
var _probe_mode: bool = false
var _probe_failures: int = 0
var _clock_check: ClockCheck = null
var _shutting_down: bool = false


func _ready() -> void:
	var window: Window = get_window()
	window.content_scale_size = Vector2i(int(CANVAS_SIZE.x), int(CANVAS_SIZE.y))
	# EXPAND：保留设计分辨率与等比缩放，同时让舞台在窗口比例不同时也不会被裁掉
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS

	_stage_def = StageDefScript.make_level1()
	var problems: Array[String] = _stage_def.validate()
	if not problems.is_empty():
		# 开发构建启动时直接报出问题，防止静默跳过动作（TECH_DESIGN.md 2.2）
		for p in problems:
			push_error("第一关数据校验失败：%s" % p)

	_metronome = MetronomeScript.new()
	_metronome.name = "Metronome"
	add_child(_metronome)
	_clock = MusicClockScript.new()
	_metronome.setup(_clock)
	# 先设播放器再 start()：start() 会从 0 播放并重置时间轴
	_clock.set_player(_metronome.get_player(), _stage_def.bpm)
	_clock.start()

	_harness = ControlsHarnessScript.new(3)
	_harness.controller.clock = _clock
	_performance = PerformanceSystemScript.new()
	_performance.setup(_stage_def.cues, _clock, _harness.controller.puppets)
	var puppet_state: PuppetState = _harness.controller.get_controlled()
	_puppet.puppet_state = puppet_state
	_puppet.stage_origin = STAGE_ORIGIN
	_puppet.stage_size = STAGE_SIZE
	_hud_hint.text = "拖动胸签 = 横向移动 / 纵向站蹲 / 沿移动方向翻面    " \
		+ "A=抬左手 D=抬右手 Shift+A=落左手 Shift+D=落右手 W=双手抬 S=双手落    " \
		+ "空格=挂起/取回影人（PRD 第 4.1 节）    ESC=暂停/继续"

	if OS.get_cmdline_args().has(PROBE_FLAG) or OS.get_cmdline_user_args().has(PROBE_FLAG):
		_run_probe_and_quit()


func _process(delta: float) -> void:
	_sync_stage_to_canvas_scale()
	if _clock_check != null:
		_drive_clock_check(delta)
		return
	if _probe_mode:
		# 脚本化实测的同步部分在 _ready() 里跑完；此处不得再推进时钟
		return
	if _metronome_enabled:
		_metronome.update()
	if _clock.update(delta):
		_crossing_count += 1
		_last_crossing_ms = _clock.get_song_time_ms()
	_harness.advance(delta)
	# 判定在操控状态更新之后运行：先有状态，再有判定
	_performance.update(_clock.get_song_time_ms(), _harness.take_frame_events())
	_refresh_hud()


## 逐帧驱动音乐时钟的真实时间测量；跑完后打印结论并退出。
## 这里同时推进节拍音与时钟，保证测的是同一条时间轴。
func _drive_clock_check(delta: float) -> void:
	if _metronome_enabled:
		_metronome.update()
	if _clock.update(delta):
		_crossing_count += 1
		_last_crossing_ms = _clock.get_song_time_ms()
	_harness.advance(delta)
	_clock_check.step(delta)
	_refresh_hud()
	if _clock_check.is_done() and not _shutting_down:
		_shutting_down = true
		var failures: int = _probe_failures + _clock_check.report()
		_shutdown_and_quit(1 if failures > 0 else 0)


## 退出前有序收尾：先停音频播放、断开时钟与播放器的引用，再退出。
## 否则音频线程可能仍持有生成器播放缓冲，导致退出时报
## 「ObjectDB instance was leaked」甚至偶发访问违例。
func _shutdown_and_quit(exit_code: int) -> void:
	if _metronome != null:
		_metronome.stop()
	if _clock != null:
		if _clock.is_paused():
			_clock.resume()
		_clock.set_player(null, _clock.bpm)
	_clock_check = null
	get_tree().quit(exit_code)


func _input(event: InputEvent) -> void:
	if _paused:
		if event is InputEventKey:
			var resume_key := event as InputEventKey
			if resume_key.pressed and not resume_key.echo and resume_key.keycode == KEY_ESCAPE:
				_set_paused(false)
				get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			# 暂停统一用 ESC：空格在任何场景里都不再是暂停键（PRD 第 4.1 节把
			# 空格定为「挂起/取回影人」，两处含义冲突会让人误判第一关的行为）。
			if key.keycode == KEY_ESCAPE:
				_set_paused(not _paused)
				get_viewport().set_input_as_handled()
				return
	_harness.input_reader.handle_event(event)


func _notification(what: int) -> void:
	# 失去焦点时收尾拖动，避免「松手事件丢失 → 影人粘着鼠标」
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _harness != null:
		_harness.input_reader.release_drag()


func _set_paused(value: bool) -> void:
	_paused = value
	_harness.set_paused(value)
	if value:
		_clock.pause()
	else:
		_clock.resume()


## 脚本化实测模式：先同步跑完不依赖真实时间的操控检查，
## 再交给 _process 逐帧跑音乐时钟的真实时间测量，跑完打印结论并退出。
func _run_probe_and_quit() -> void:
	_probe_mode = true
	var probe: ControlsProbe = ControlsProbeScript.new()
	probe.clock = _clock
	probe.stage_def = _stage_def
	_probe_failures = probe.run()
	# 探针可能把时钟留在暂停态，时钟实测需要它恢复运行
	if _clock.is_paused():
		_clock.resume()
	# 关键动作判定的图形实测（同步、确定性，复用探针模式）
	var cue_probe := CueProbeScript.new()
	_probe_failures += cue_probe.run()
	_clock_check = ClockCheckScript.new()
	_clock_check.start(_clock)


## 画布等比缩放时，鼠标事件落在虚拟画布坐标空间里。
## 舞台固定为 1920x1080，与画布同尺寸时换算系数为 1.0，手感与开发分辨率一致。
func _sync_stage_to_canvas_scale() -> void:
	var scale: float = get_window().content_scale_factor
	if scale <= 0.0:
		scale = 1.0
	_harness.input_reader.scale_factor = scale


func _refresh_hud() -> void:
	var state: PuppetState = _harness.controller.get_controlled()
	_puppet.puppet_state = state
	var input_map: Dictionary = _harness.controller.get_input_map()

	var lines: Array[String] = []
	lines.append("[b]A 操控 + 音乐时钟测试 · 占位影人（不依赖 B 的美术）[/b]")
	lines.append("暂停状态：%s    步进数：%d    FPS：%d" % [
		"[color=#ff8]已暂停[/color]" if _paused else "运行中",
		_harness.get_step_count(), Engine.get_frames_per_second()])
	lines.append("")
	lines.append("puppet_id：%d    受控：%s" % [state.puppet_id, state.is_controlled])
	lines.append("stage_pos：x=%.4f  y=%.4f   （0-1，接地点）" % [state.stage_pos.x, state.stage_pos.y])
	lines.append("stance：%.4f   %s" % [state.stance, _bar(state.stance)])
	lines.append("facing：%+.0f（+1 正面 / -1 反面）   翻面进度 turn_progress：%.4f"
		% [state.facing, state.turn_progress])
	lines.append("hand_angle：左手 %+.4f  右手 %+.4f  （弧度，0 = 垂下 / %.4f = 举过头顶）"
		% [state.hand_angle.x, state.hand_angle.y, PuppetState.HAND_ANGLE_MAX])
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
	lines.append("  facing 恰为 ±1（正/反两面）%s" % _ok(absf(state.facing) == 1.0))
	lines.append("  turn_progress ∈ [0,1]    %s" % _ok(state.turn_progress >= 0.0 and state.turn_progress <= 1.0))
	lines.append("  hand_angle ∈ [%.4f, %.4f] %s" % [PuppetState.HAND_ANGLE_MIN, PuppetState.HAND_ANGLE_MAX,
		_ok(state.hand_angle.x >= PuppetState.HAND_ANGLE_MIN - 1e-6
			and state.hand_angle.x <= PuppetState.HAND_ANGLE_MAX + 1e-6
			and state.hand_angle.y >= PuppetState.HAND_ANGLE_MIN - 1e-6
			and state.hand_angle.y <= PuppetState.HAND_ANGLE_MAX + 1e-6)])
	_state_label.text = "\n".join(lines)
	_refresh_clock_panel()
	_refresh_cue_panel()

	var events: Array[Dictionary] = _harness.controller.take_events()
	var event_lines: Array[String] = []
	event_lines.append("[b]TimedEvent 流（操控 + 判定，取走即清空）[/b]")
	if events.is_empty():
		event_lines.append("[color=#888]（无新操控事件）[/color]")
	else:
		for e in events:
			event_lines.append(_format_event(e))
	for e in _performance.take_events():
		event_lines.append("[color=#9df]%s[/color]" % _format_event(e))
	_event_label.text = "\n".join(event_lines)


## 关键动作面板：当前生效的线索、下一个落点倒计时、每条关键动作的判定结果。
func _refresh_cue_panel() -> void:
	var song_ms: int = _clock.get_song_time_ms()
	var lines: Array[String] = []
	lines.append("[b]第一关关键动作判定[/b]")
	lines.append("待判定 %d / 共 %d 条" % [_performance.pending_count(), _stage_def.cues.size()])
	lines.append("")

	# 当前可感知的线索（落点前 1 s 出现），以及最近的未判定落点
	var active_hints: Array[String] = []
	var next_cue: Dictionary = {}
	var next_delta: int = 1 << 30
	for cue in _stage_def.cues:
		var cue_id: String = str(cue["cue_id"])
		if _performance.has_outcome(cue_id):
			continue
		if song_ms >= CueScript.hint_time_ms(cue):
			active_hints.append("%s（%s）" % [_action_label(str(cue["action"])), cue_id])
		var delta: int = int(cue["beat_time_ms"]) - song_ms
		if delta > 0 and delta < next_delta:
			next_delta = delta
			next_cue = cue
	lines.append("当前线索：%s" % ("、".join(active_hints) if not active_hints.is_empty() else "（无）"))
	if not next_cue.is_empty():
		lines.append("下一个落点：%s  还有 %d ms" % [str(next_cue["cue_id"]), next_delta])
	else:
		lines.append("下一个落点：（本关已无未判定落点）")
	lines.append("")
	lines.append("[b]判定结果[/b]")
	var graded: int = 0
	for cue in _stage_def.cues:
		var cue_id: String = str(cue["cue_id"])
		if not _performance.has_outcome(cue_id):
			continue
		graded += 1
		var o: Dictionary = _performance.get_outcome(cue_id)
		var mark: String = "[color=#6f6]命中[/color]" if bool(o["hit"]) else "[color=#f96]未命中[/color]"
		lines.append("  %-20s %-6s offset=%+5d ms" % [cue_id, mark, int(o["offset_ms"])])
	if graded == 0:
		lines.append("  [color=#888]（尚无判定结果）[/color]")
	lines.append("")
	lines.append("[b]说明[/b]")
	lines.append("判定的是「姿势到位/状态切换」的瞬间，")
	lines.append("平移本身不逐帧评分；容差 ±250 ms 为可配置原型值。")
	lines.append("错拍动作照常发生，只记为未命中。")
	_cue_label.text = "\n".join(lines)


func _action_label(action: String) -> String:
	match action:
		CueScript.ACTION_STAND_UP:
			return "站起"
		CueScript.ACTION_CROUCH:
			return "蹲下"
		CueScript.ACTION_HAND_RAISE:
			return "抬手"
		CueScript.ACTION_HAND_LOWER:
			return "落手"
		CueScript.ACTION_MOVE_LEFT:
			return "向左移动"
		CueScript.ACTION_MOVE_RIGHT:
			return "向右移动"
		CueScript.ACTION_REACH:
			return "移动到目标位"
	return action


func _refresh_clock_panel() -> void:
	var song_ms: int = _clock.get_song_time_ms()
	var beat: int = _clock.get_beat_index()
	var driven: bool = _clock.is_audio_driven()
	var progress: float = clampf(float(song_ms) / float(_stage_def.duration_ms), 0.0, 1.0)

	var lines: Array[String] = []
	lines.append("[b]唯一音乐时钟（MusicClock）[/b]")
	lines.append("歌曲时间 time_ms：%d" % song_ms)
	lines.append("关卡进度：%s  %d / %d ms" % [_bar(progress), song_ms, _stage_def.duration_ms])
	lines.append("")
	lines.append("拍序号 beat_index：%d    距下一拍：%d ms" % [beat, _clock.time_to_next_beat_ms()])
	lines.append("单拍时长：%.2f ms    BPM：%.1f" % [_stage_def.beat_duration_ms(), _stage_def.bpm])
	lines.append("跨拍次数：%d    最近跨拍：%s" % [_crossing_count,
		"尚未跨拍" if _last_crossing_ms < 0 else "%d ms" % _last_crossing_ms])
	lines.append("")
	lines.append("时钟来源：%s" % ("[color=#6f6]音频播放位置[/color]" if driven
		else "[color=#f96]自由计时（未取得音频位置）[/color]"))
	lines.append("输出延迟 output_latency：%.1f ms" % (_clock.get_output_latency_s() * 1000.0))
	lines.append("临时节拍音：%s%s" % [
		"[color=#6f6]播放中[/color]" if _metronome.is_active() else "[color=#f66]本机不可用[/color]",
		"" if _metronome_enabled else "（已用 M 关闭）"])
	lines.append("采样率：%.0f Hz" % _metronome.get_mix_rate())
	lines.append("")
	lines.append("说明：B 的正式锣鼓主音轨尚未交付，")
	lines.append("此处用 A 测试目录内的合成节拍音提供音频位置，")
	lines.append("不引用素材文件、不改 B 的正式音频目录。")
	lines.append("")
	lines.append("暂停验证：按 ESC 后，音频、歌曲时间、")
	lines.append("拍序号与操控判定应一起冻结，")
	lines.append("再按一次应沿同一时间轴继续、不跳变。")
	_clock_label.text = "\n".join(lines)


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
