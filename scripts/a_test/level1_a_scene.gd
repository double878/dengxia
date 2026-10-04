extends Node2D
## 第一关「入手」的幕后演出画面（A 模块）。本文件只做三件事：
## 1. 把物理键鼠按 **PRD 第 4.1 节**的输入规则翻译给 Level1Runtime；
## 2. 按示意图布局画出幕后工作台：上方幕布与影子，下方「你的手边 · 身前矮处」
##    一条放油灯、手与三根签、两个挂钩、备用头架；
## 3. 作为**模拟显示端**每帧只读 PuppetState / LampState / TimedEvent，从不写状态，
##    因此它证明「A 先改状态，B/C 再读」这条单向数据流成立。
##
## 本场景不自行计算拍点、不判定对错、不决定补救时机——那些全部来自 Level1Runtime。
##
## 键位（只有这些，没有测试专用键）：
##   鼠标左键点影人/手边的签 = 接手并拖动胸签；滚轮 = 推拉灯；Q/E = 倾灯
##   A/D 抬左手/右手，Shift+A / Shift+D 放下，W/S 双手同抬/同落
##   1/2/3 = 与备用头架对应位置换头；空格 = 挂起/取回影人；ESC 或右上角按钮 = 暂停

const HarnessScript := preload("res://scripts/a_test/level1_harness.gd")
const ProbeScript := preload("res://scripts/a_test/level1_a_probe.gd")
const StageDefScript := preload("res://scripts/a/stage_def.gd")
const CueScript := preload("res://scripts/a/cue.gd")
const CueHintScript := preload("res://scripts/a/cue_hint.gd")
const PuppetControllerScript := preload("res://scripts/a/puppet_controller.gd")
const PuppetViewScript := preload("res://scripts/a_test/placeholder_puppet.gd")

const CANVAS_SIZE := Vector2(1920.0, 1080.0)

## —— 版面：与用户示意图一致的三段结构 ——
const TOP_BAR := Rect2(0.0, 0.0, 1920.0, 76.0)
const SCREEN_FRAME := Rect2(50.0, 76.0, 1820.0, 620.0)
## 幕布本体。影子落在这上面。
const CLOTH := Rect2(66.0, 92.0, 1788.0, 588.0)
## 「你的手边 · 身前矮处」
const TABLE := Rect2(0.0, 696.0, 1920.0, 288.0)
## 底部条：节拍指示（仅教学关）。示意图里的「观众情绪」按 PRD 第 2 节本期不做。
const FOOTER := Rect2(0.0, 984.0, 1920.0, 96.0)

const HAND_ANCHOR := Vector2(960.0, 856.0)
const HAND_AREA := Rect2(768.0, 712.0, 384.0, 256.0)
const HOOK_X: Array = [1186.0, 1290.0]
const RACK_SLOT_X: Array = [1512.0, 1590.0, 1668.0]
const RACK_Y := 838.0
const RACK_HIT_RADIUS := 40.0
## 点选挂钩上的影人时的命中半径（屏幕像素）
const PUPPET_HIT_RADIUS := 96.0

const PROBE_FLAG := "level1_a_probe"

@onready var _lamp: PlaceholderLamp = $Lamp
@onready var _puppet_views: Array = [$Puppet0, $Puppet1, $Puppet2]
@onready var _pause_button: Button = $Hud/PauseButton
@onready var _cue_label: Label = $Hud/CueLabel
@onready var _remedy_banner: Label = $Hud/RemedyBanner
@onready var _hook_label: Label = $Hud/HookLabel
@onready var _status_label: Label = $Hud/StatusLabel

var _harness: Level1Harness = null
var _stage_def: StageDef = null
var _paused: bool = false
## 已选中、等待取回的挂起影人编号（-1 表示未选中）
var _selected_puppet: int = -1
var _probe_mode: bool = false
var _shutting_down: bool = false
## 诊断开关：带 `diag` 参数启动时每 30 帧打印一次读数（fps / 歌曲时间 / 音频是否
## 在驱动 / 窗口尺寸 / 画布缩放）。起因是导出包曾在带窗口启动时卡死而编辑器里
## 复现不出来；卡死根因已修（见 _ready 的注释），但这个开关保留——排查音频时钟、
## 掉帧、窗口尺寸不符时仍然要看它，不靠肉眼猜。
var _diag: bool = false
var _frame_count: int = 0


func _ready() -> void:
	# 窗口尺寸与画布拉伸由 project.godot 的 [display] 段（window_width_override /
	# window_height_override / stretch.mode）在**建窗之前**一次定好，本场景不再改窗口。
	#
	# 以前这里在运行期写 window.size = 1280x720 与 content_scale_*。在本机
	# （Windows + Intel Arc + 2880x1920 @200% 缩放）会以约 20% 的概率让渲染提交
	# 阶段陷入 resize 反馈环：主线程跑满一个核、画面停在第 5 帧左右不再前进、
	# 窗口「无响应」且关闭按钮无效（只能从任务管理器结束进程）。实测把尺寸要求
	# 挪到建窗前（等价于启动参数 --resolution）后不再出现，故保留此写法。
	# 场景只负责演出本身，不负责窗口——这也让另外两个测试场景可以共用同一套显示设置。
	_stage_def = StageDefScript.make_level1()
	_harness = HarnessScript.new(self)
	if _harness.runtime == null:
		_shutdown_and_quit(1)
		return
	_configure_initial_stage()
	_diag = OS.get_cmdline_args().has("diag") or OS.get_cmdline_user_args().has("diag")
	if _diag:
		print("DIAG: 诊断开关已开启")
	_lamp.cloth_rect = CLOTH
	_pause_button.pressed.connect(_toggle_pause)
	_refresh_ui()
	if OS.get_cmdline_args().has(PROBE_FLAG) or OS.get_cmdline_user_args().has(PROBE_FLAG):
		_probe_mode = true
		var probe := ProbeScript.new()
		var failures: int = probe.run(_harness)
		_shutdown_and_quit(1 if failures > 0 else 0)


## 开演前的起始布景（PRD 第 4.2、6 节）：
## 三个影人同时在场，只有一个受控，另两个挂在两个挂钩上保持姿势；
## 第一关「灯明亮」，所以显露度从满值起步。
func _configure_initial_stage() -> void:
	var runtime: Level1Runtime = _harness.runtime
	var lamp: LampState = runtime.lamp_controller.lamp
	lamp.exposure = 1.0
	lamp.distance = 0.5
	lamp.oil = 1.0
	var puppets: Array = runtime.puppet_controller.puppets
	puppets[0].stage_pos = Vector2(0.50, 0.5)
	puppets[1].stage_pos = Vector2(0.13, 0.5)
	puppets[1].hand_angle = Vector2(1.20, 0.10)
	_set_hung(puppets[1], 0)
	puppets[2].stage_pos = Vector2(0.86, 0.5)
	puppets[2].hand_angle = Vector2(0.10, 1.20)
	_set_hung(puppets[2], 1)


## 把影人挂到挂钩上。走与 PuppetController 相同的字段，保证不变量继续成立。
func _set_hung(state: PuppetState, slot: int) -> void:
	state.is_controlled = false
	state.hook_slot = slot


func _process(delta: float) -> void:
	if _probe_mode or _harness == null:
		return
	_frame_count += 1
	if _diag:
		_diag_process(delta)
		return
	_harness.advance(delta)
	_harness.take_events()
	_refresh_ui()
	queue_redraw()


## 诊断路径：与正常路径做同样的事，但每 30 帧打印一次读数与各段耗时。
## 只在带 `diag` 参数启动时走这里，正常游玩零开销。
## 存在的理由：这个工程曾在带窗口启动时以约 20% 的概率卡死在渲染提交阶段，
## 而那种情况在编辑器里复现不出来；有了这个开关，卡死现场可以从 exe 自己的输出里读。
## （根因是运行期改窗口尺寸触发 resize 反馈环，已改为在 project.godot 里建窗前定好；
## 开关保留——以后排查音频时钟、掉帧、窗口尺寸不符时仍然要用它，不靠肉眼猜。）
func _diag_process(delta: float) -> void:
	var t0: int = Time.get_ticks_msec()
	_harness.advance(delta)
	var t1: int = Time.get_ticks_msec()
	_harness.take_events()
	var t2: int = Time.get_ticks_msec()
	_refresh_ui()
	var t3: int = Time.get_ticks_msec()
	queue_redraw()
	if _frame_count % 30 != 0:
		return
	var clock: MusicClock = _harness.clock
	var metronome: Metronome = _harness.metronome
	var player: AudioStreamPlayer = metronome.get_player()
	var position_s: float = player.get_playback_position() if player != null else -1.0
	# win / scale 用来核对「实际开窗尺寸」与「1920x1080 画布的等比缩放」是否符合预期：
	# 窗口尺寸不对或缩放出 1 时，画面会被裁切或变形，而这两种情况从读数上一眼可辨。
	var window: Window = get_window()
	print("DIAG ticks=%d frame=%d fps=%d song=%dms real=%dms frozen=%s beat=%d audio_driven=%s playing=%s pos=%.3fs active=%s advance=%dms ui=%dms delta=%.1fms win=%dx%d canvas_scale=%.3f" % [
		Time.get_ticks_msec(), _frame_count, Engine.get_frames_per_second(),
		clock.get_song_time_ms(), clock.get_real_time_ms(), clock.is_song_frozen(),
		clock.get_beat_index(), clock.is_audio_driven(),
		player.playing if player != null else false, position_s,
		metronome.is_active(), t1 - t0, t3 - t2, delta * 1000.0,
		window.size.x, window.size.y, get_viewport_transform().get_scale().x])


func _input(event: InputEvent) -> void:
	if _harness == null:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			_handle_key(key.keycode)
		return
	if _paused or _harness.runtime.is_over():
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			if not _handle_left_press(button.position):
				# 手边的签与影人身上的胸签都能抓：统一换算成控制器认得的热区位置
				var translated := button.duplicate() as InputEventMouseButton
				translated.position = _grab_position(button.position)
				_harness.handle_input(translated)
			get_viewport().set_input_as_handled()
			return
	if _harness.handle_input(event):
		get_viewport().set_input_as_handled()


func _handle_key(keycode: int) -> void:
	match keycode:
		KEY_ESCAPE:
			_toggle_pause()
			get_viewport().set_input_as_handled()
		KEY_SPACE:
			# PRD 第 4.1 节：空格是挂起/取回影人，**不是暂停**
			if not _paused:
				_toggle_hook()
			get_viewport().set_input_as_handled()
		KEY_1:
			_try_swap_head(0)
			get_viewport().set_input_as_handled()
		KEY_2:
			_try_swap_head(1)
			get_viewport().set_input_as_handled()
		KEY_3:
			_try_swap_head(2)
			get_viewport().set_input_as_handled()


## 点击优先给「备用头架」和「挂钩上的影人」，都不命中才当作抓胸签。
func _handle_left_press(position: Vector2) -> bool:
	if _paused or _harness.runtime.is_over():
		return true
	var slot: int = _rack_slot_at(position)
	if slot >= 0:
		_try_swap_head(slot)
		return true
	var puppet_id: int = _hung_puppet_at(position)
	if puppet_id >= 0:
		_selected_puppet = puppet_id
		_refresh_ui()
		return true
	return false


## 把「抓手里这根签」换算成「受控影人胸签所在的屏幕位置」。
## 不能像以前那样写死 (960, 495)：影人一旦移开原位，那个点就不再落在热区里，
## 玩家会突然抓不住自己控制的影人。
func _grab_position(position: Vector2) -> Vector2:
	var controller: PuppetController = _harness.runtime.puppet_controller
	var controlled: PuppetState = controller.get_controlled()
	if controlled == null:
		return position
	if not HAND_AREA.has_point(position):
		return position
	return Vector2(controlled.stage_pos.x * CANVAS_SIZE.x,
		controlled.stage_pos.y * CANVAS_SIZE.y
			- PuppetControllerScript.CHEST_TAG_RADIUS_PX * 0.5)


func _try_swap_head(slot: int) -> void:
	if _paused or _harness.runtime.is_over():
		return
	var controller: PuppetController = _harness.runtime.puppet_controller
	if controller.controlled_id < 0:
		return
	controller.swap_head(slot)
	_refresh_ui()


func _toggle_hook() -> void:
	var controller: PuppetController = _harness.runtime.puppet_controller
	if controller.controlled_id >= 0:
		controller.hook_current()
		_selected_puppet = -1
	elif _selected_puppet >= 0 and controller.take_back(_selected_puppet):
		_selected_puppet = -1
	_refresh_ui()


func _toggle_pause() -> void:
	if _harness == null or _harness.runtime.is_over():
		return
	_paused = not _paused
	_harness.set_paused(_paused)
	_pause_button.text = "▶" if _paused else "Ⅱ"
	_pause_button.tooltip_text = "继续演出" if _paused else "暂停演出"
	_refresh_ui()
	queue_redraw()


func _refresh_ui() -> void:
	if _harness == null:
		return
	var runtime: Level1Runtime = _harness.runtime
	_lamp.lamp = runtime.lamp_controller.lamp
	for i in _puppet_views.size():
		var view: PlaceholderPuppet = _puppet_views[i]
		view.puppet_state = runtime.puppet_controller.puppets[i]
		view.lamp_state = runtime.lamp_controller.lamp
		view.hand_anchor = HAND_ANCHOR
		view.stage_origin = Vector2.ZERO
		view.stage_size = CANVAS_SIZE

	_status_label.text = "第一折 · 入手"
	if runtime.is_over():
		_status_label.text += "　本折已收场"
	elif _harness.clock.is_song_frozen():
		# 补救冻结期间歌曲时间停住、鼓点变成 0.1 倍速，这是玩家判断
		# 「现在不是正常演出时间」的主要依据，所以必须写在画面上。
		_status_label.text += "　补救中 · 演出计时已暂停"
	elif not _harness.clock.is_audio_driven():
		# 时钟已降级（无声卡 / 音频停摆）时明确写出来，避免"画面在动但听不到声音"
		# 被误报成"游戏卡死"或"音乐没做"。
		_status_label.text += "　（音频时钟不可用，本场按计时推进）"
	if runtime.is_over():
		_cue_label.text = "本折已收场"
		_pause_button.disabled = true
	elif _paused:
		_cue_label.text = "已暂停 · 按 ESC 或点右上角继续"
	else:
		_cue_label.text = _active_cue_text()

	var demo_id: String = runtime.director.remedy.current_demo_cue_id
	var frozen: bool = _harness.clock.is_song_frozen()
	_remedy_banner.visible = (not demo_id.is_empty() or frozen) and not _paused
	if frozen:
		var remedy_text: String = "跟着示范补做刚才漏掉的动作"
		if not demo_id.is_empty():
			remedy_text = _action_text(str(_find_cue(demo_id).get("action", "")))
		_remedy_banner.text = "补救中　·　演出已暂停　·　%s" % remedy_text
	elif not demo_id.is_empty():
		_remedy_banner.text = "师父示范　·　%s" % _action_text(
			str(_find_cue(demo_id).get("action", "")))

	var controller: PuppetController = runtime.puppet_controller
	_hook_label.text = hook_hint_text(controller, _selected_puppet)


## 空格那一行的提示文案。**按实际可用性说话**：挂钩满的时候不宣称可以挂起。
##
## 第一关开局三个影人同时在场，其中两个分别挂在两个挂钩上（PRD 第 4.2 节），
## 也就是说这一关两个槽从第一帧起就是满的，`hook_current()` 永远找不到空位。
## 这种情况下原来那行「空格 = 挂起这个影人」是**说了做不到**——玩家按下去什么
## 都不会发生，只会以为按键坏了。挂起/取回属第 2 关（双人）的机制（PRD 第 6 节），
## 第一关不该宣传它，所以这里返回空串。
##
## 做成静态纯函数是为了能被无头测试直接断言：文案规则不依赖场景节点，
## 「什么状态显示什么话」这一条因此不必靠跑图形界面来验证。
static func hook_hint_text(controller: PuppetController, selected_puppet: int) -> String:
	if controller.controlled_id >= 0:
		if controller.find_free_hook_slot() < 0:
			return ""
		return "空格 = 挂起这个影人"
	if selected_puppet < 0:
		return "点手边的签选中挂起的影人，再按空格取回"
	return "空格 = 取回 %d 号影人" % (selected_puppet + 1)


func _active_cue_text() -> String:
	var song_ms: int = _harness.clock.get_song_time_ms()
	for cue in _stage_def.cues:
		if _harness.runtime.director.performance.has_outcome(str(cue["cue_id"])):
			continue
		if song_ms >= CueScript.hint_time_ms(cue):
			return _action_text(str(cue["action"]))
	return "握住手边的胸签，跟着鼓点入场"


func _find_cue(cue_id: String) -> Dictionary:
	for cue in _stage_def.cues:
		if str(cue["cue_id"]) == cue_id:
			return cue
	return {}


func _action_text(action: String) -> String:
	match action:
		CueScript.ACTION_CROUCH: return "向下拖动胸签，蹲下"
		CueScript.ACTION_STAND_UP: return "向上拖动胸签，站起"
		CueScript.ACTION_HAND_RAISE: return "按 A 抬起左手"
		CueScript.ACTION_HAND_LOWER: return "按 Shift+A 放下左手"
		CueScript.ACTION_MOVE_LEFT: return "向左拖动胸签"
		CueScript.ACTION_MOVE_RIGHT: return "向右拖动胸签"
		CueScript.ACTION_REACH: return "把影人带回幕布中央"
	return "跟着鼓点继续演出"


## —— 以下全是只读的画面表现 ——

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), Color("#171b19"))
	draw_rect(TOP_BAR, Color("#232a27"))
	draw_rect(SCREEN_FRAME, Color("#7b4d23"))
	# 幕布用「未被照亮」的底色；画面上的亮度全部由油灯的洗光提供，
	# 这样灯油变暗、Q/E 改显露度才在画面上看得见。
	draw_rect(CLOTH, Color("#a3977c"))
	_draw_cloth_grain()
	draw_rect(TABLE, Color("#382818"))
	draw_line(Vector2(0.0, TABLE.position.y), Vector2(CANVAS_SIZE.x, TABLE.position.y),
		Color("#8a6335"), 3.0)
	_draw_foot_rail()
	_draw_hooks()
	_draw_head_rack()
	_draw_hands_and_tags()
	draw_rect(FOOTER, Color("#222927"))
	draw_line(Vector2(0.0, FOOTER.position.y), Vector2(CANVAS_SIZE.x, FOOTER.position.y),
		Color("#ad8147"), 2.0)
	_draw_beat_indicator()
	_draw_target_marker()
	if _harness != null and not _harness.runtime.director.remedy.current_demo_cue_id.is_empty():
		_draw_teacher_hand()
	if _harness != null and _harness.clock.is_song_frozen():
		_draw_freeze_overlay()
	if _paused:
		draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), Color(0.0, 0.0, 0.0, 0.45))


## 补救冻结的画面提示：幕布整体压暗 + 外框一圈琥珀色。
## PRD 第 5.2 节把补救定义成「帮助玩家继续表演」而不是失败，因此这里只做提示，
## 不打分数、不显示倒计时秒数（第 3、5.1 节明确禁止泄露数值）。
func _draw_freeze_overlay() -> void:
	draw_rect(CLOTH, Color(0.06, 0.04, 0.02, 0.42))
	draw_rect(SCREEN_FRAME, Color(0.98, 0.72, 0.25, 0.80), false, 6.0)


## 幕布经纬线的淡淡质感，避免整块幕布是一块死板的纯色。
func _draw_cloth_grain() -> void:
	for x in range(int(CLOTH.position.x), int(CLOTH.end.x), 52):
		draw_line(Vector2(float(x), CLOTH.position.y), Vector2(float(x), CLOTH.end.y),
			Color(0.42, 0.34, 0.22, 0.045), 1.0)
	for y in range(int(CLOTH.position.y), int(CLOTH.end.y), 52):
		draw_line(Vector2(CLOTH.position.x, float(y)), Vector2(CLOTH.end.x, float(y)),
			Color(0.42, 0.34, 0.22, 0.035), 1.0)


## 工作台前沿的横杆与台下阴影。
func _draw_foot_rail() -> void:
	draw_rect(Rect2(0.0, TABLE.end.y - 26.0, CANVAS_SIZE.x, 26.0), Color("#241a0f"))
	draw_line(Vector2(0.0, TABLE.end.y - 26.0), Vector2(CANVAS_SIZE.x, TABLE.end.y - 26.0),
		Color("#6b4a28"), 3.0)


## 两个挂钩（PRD 第 4.2 节：另两人可以挂在各自挂钩上）。
func _draw_hooks() -> void:
	var wood := Color("#b07a41")
	for x in HOOK_X:
		draw_line(Vector2(x, TABLE.position.y + 12.0), Vector2(x, 790.0), wood, 9.0)
		draw_arc(Vector2(x + 15.0, 795.0), 17.0, 0.1, PI + 0.35, 18, wood, 7.0)


## 备用头架：三个备用头，编号 1/2/3 指架上位置。可用鼠标直接点取。
func _draw_head_rack() -> void:
	if _harness == null:
		return
	var wood := Color("#b07a41")
	draw_line(Vector2(RACK_SLOT_X[0] - 62.0, 764.0),
		Vector2(RACK_SLOT_X[2] + 62.0, 764.0), wood, 11.0)
	for i in RACK_SLOT_X.size():
		var x: float = RACK_SLOT_X[i]
		draw_line(Vector2(x, 764.0), Vector2(x, 804.0), wood, 5.0)
		var head_id: int = _harness.runtime.puppet_controller.head_on_rack(i)
		if head_id >= 0:
			_draw_spare_head(Vector2(x, RACK_Y), head_id)
		else:
			draw_arc(Vector2(x, RACK_Y), 20.0, 0.0, TAU, 24, Color(0.42, 0.36, 0.28), 3.0)
		draw_string(ThemeDB.fallback_font, Vector2(x - 6.0, RACK_Y + 48.0),
			str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.85, 0.75, 0.55))


## 备用头的形状按 head_id 变化，与影人头上的头饰同一套映射，
## 这样「按 1/2/3 换头」在画面上是可核对的。
func _draw_spare_head(centre: Vector2, head_id: int) -> void:
	var accents: Array = PuppetViewScript.HEAD_ACCENTS
	var shapes: Array = PuppetViewScript.HEAD_SHAPES
	var index: int = head_id % accents.size()
	var accent: Color = accents[index]
	draw_circle(centre, 21.0, Color(0.30, 0.20, 0.12))
	draw_arc(centre, 21.0, 0.0, TAU, 28, Color(0.83, 0.60, 0.28), 2.0)
	match str(shapes[index]):
		"bun_high":
			draw_circle(centre + Vector2(0.0, -28.0), 9.0, accent)
		"bun_twin":
			draw_circle(centre + Vector2(-17.0, -17.0), 7.0, accent)
			draw_circle(centre + Vector2(17.0, -17.0), 7.0, accent)
		_:
			draw_rect(Rect2(centre.x - 24.0, centre.y - 24.0, 48.0, 10.0), accent)


## 「你的手边 · 手与三根签」：签手握住的三根签，也是鼠标抓胸签的落点。
func _draw_hands_and_tags() -> void:
	var wood := Color("#c08f4a")
	var skin := Color("#e0b783")
	var edge := Color("#6d4224")
	# 三根签的杆身
	for i in 3:
		var x: float = HAND_ANCHOR.x - 34.0 + float(i) * 34.0
		draw_line(Vector2(x, HAND_ANCHOR.y - 122.0), Vector2(x, HAND_ANCHOR.y + 6.0),
			Color("#4a3419"), 11.0)
		draw_line(Vector2(x, HAND_ANCHOR.y - 122.0), Vector2(x, HAND_ANCHOR.y + 6.0),
			wood, 7.0)
	# 手：掌 + 四指 + 拇指
	draw_circle(HAND_ANCHOR, 40.0, skin)
	draw_arc(HAND_ANCHOR, 40.0, 0.0, TAU, 36, edge, 3.0)
	for i in 4:
		var x: float = HAND_ANCHOR.x - 30.0 + float(i) * 20.0
		draw_line(Vector2(x, HAND_ANCHOR.y - 18.0),
			Vector2(x - 2.0, HAND_ANCHOR.y - 74.0 - float(i % 2) * 10.0), edge, 16.0)
		draw_line(Vector2(x, HAND_ANCHOR.y - 18.0),
			Vector2(x - 2.0, HAND_ANCHOR.y - 74.0 - float(i % 2) * 10.0), skin, 12.0)
	draw_line(HAND_ANCHOR + Vector2(-30.0, 10.0), HAND_ANCHOR + Vector2(-72.0, -26.0),
		edge, 20.0)
	draw_line(HAND_ANCHOR + Vector2(-30.0, 10.0), HAND_ANCHOR + Vector2(-72.0, -26.0),
		skin, 15.0)


## 节拍指示（仅教学关）。不打拍号、不显示倒计时，只让重音循环亮一下。
func _draw_beat_indicator() -> void:
	if _harness == null:
		return
	var beat: int = posmod(_harness.clock.get_beat_index(), 4)
	for i in 4:
		var x: float = 1372.0 + float(i) * 66.0
		var active: bool = i == beat and not _paused and not _harness.runtime.is_over()
		draw_circle(Vector2(x, FOOTER.position.y + 48.0), 15.0 if active else 10.0,
			Color("#ef9f27") if active else Color("#776857"))


## 当前线索的目标范围。前四关允许出现目标边界图标，但不泄露精确拍号（PRD 第 5.1 节）。
func _draw_target_marker() -> void:
	if _harness == null or _paused or _harness.runtime.is_over():
		return
	var runtime: Level1Runtime = _harness.runtime
	var song_ms: int = _harness.clock.get_song_time_ms()
	for cue in _stage_def.cues:
		var cue_id: String = str(cue["cue_id"])
		if runtime.director.performance.has_outcome(cue_id):
			continue
		var hint: Dictionary = CueHintScript.make(cue)
		if not CueHintScript.is_visible(hint, song_ms):
			continue
		var bounds: Dictionary = cue.get("target_range", {})
		if str(bounds.get("key", "")) == "x":
			var x0: float = CLOTH.position.x + float(bounds.get("min", 0.0)) * CLOTH.size.x
			var x1: float = CLOTH.position.x + float(bounds.get("max", 1.0)) * CLOTH.size.x
			draw_rect(Rect2(x0, CLOTH.position.y + 8.0, x1 - x0, CLOTH.size.y - 16.0),
				Color(0.98, 0.72, 0.25, 0.12))
			for x in range(int(x0), int(x1), 34):
				draw_line(Vector2(float(x), CLOTH.end.y - 10.0),
					Vector2(float(x), CLOTH.end.y - 34.0), Color(0.98, 0.72, 0.25, 0.55), 3.0)
		else:
			_draw_pose_arrow(str(cue.get("action", "")))
		return


## 姿势类动作（站起/蹲下/抬手）用影人身旁的方向箭头提示，不写数字。
func _draw_pose_arrow(action: String) -> void:
	var controller: PuppetController = _harness.runtime.puppet_controller
	var controlled: PuppetState = controller.get_controlled()
	if controlled == null:
		return
	var base := Vector2(controlled.stage_pos.x * CANVAS_SIZE.x + 118.0,
		controlled.stage_pos.y * CANVAS_SIZE.y - 190.0)
	var up: bool = action == CueScript.ACTION_STAND_UP or action == CueScript.ACTION_HAND_RAISE
	var tip := base + Vector2(0.0, -58.0 if up else 58.0)
	var colour := Color(0.98, 0.72, 0.25, 0.85)
	draw_line(base, tip, colour, 7.0)
	draw_line(tip, tip + Vector2(-17.0, 22.0 if up else -22.0), colour, 7.0)
	draw_line(tip, tip + Vector2(17.0, 22.0 if up else -22.0), colour, 7.0)


## 师父示范手：只在失误后的补救窗口里出现，只示范动作本身（PRD 第 5.2 节）。
func _draw_teacher_hand() -> void:
	# 用真实时间驱动示范手的摆动：补救期间歌曲时间是冻结的，用它会得到一只僵住的手，
	# 而这只手的作用恰恰是「让玩家看出该补做什么动作」。
	var now_s: float = _harness.clock.get_real_time_s()
	var action: String = str(_find_cue(
		_harness.runtime.director.remedy.current_demo_cue_id).get("action", ""))
	var sway: float = sin(now_s * 7.0) * 20.0
	var motion := Vector2.ZERO
	match action:
		CueScript.ACTION_MOVE_LEFT: motion.x = -sway
		CueScript.ACTION_MOVE_RIGHT, CueScript.ACTION_REACH: motion.x = sway
		CueScript.ACTION_CROUCH, CueScript.ACTION_HAND_LOWER: motion.y = sway
		_: motion.y = -sway
	var base: Vector2 = HAND_ANCHOR + Vector2(-186.0, 4.0) + motion
	var skin := Color("#e6bb83")
	var edge := Color("#714025")
	draw_arc(base, 46.0, 0.0, TAU, 40, Color(1.0, 0.85, 0.5, 0.35), 5.0)
	draw_circle(base, 36.0, skin)
	draw_arc(base, 36.0, 0.0, TAU, 36, edge, 3.0)
	for i in 4:
		var x: float = base.x - 25.0 + float(i) * 17.0
		draw_line(Vector2(x, base.y - 14.0),
			Vector2(x - 2.0, base.y - 70.0 - float(i % 2) * 12.0), edge, 15.0)
		draw_line(Vector2(x, base.y - 14.0),
			Vector2(x - 2.0, base.y - 70.0 - float(i % 2) * 12.0), skin, 11.0)
	draw_line(base + Vector2(-25.0, 16.0), base + Vector2(-62.0, -19.0), edge, 19.0)
	draw_line(base + Vector2(-25.0, 16.0), base + Vector2(-62.0, -19.0), skin, 14.0)


## 点中备用头架哪个槽位（-1 表示没点中）
func _rack_slot_at(position: Vector2) -> int:
	if position.distance_to(Vector2(0.0, RACK_Y)) > 260.0:
		return -1
	for i in RACK_SLOT_X.size():
		if position.distance_to(Vector2(RACK_SLOT_X[i], RACK_Y)) <= RACK_HIT_RADIUS:
			return i
	return -1


## 点中哪个挂钩上的影人（-1 表示没点中）
func _hung_puppet_at(position: Vector2) -> int:
	var controller: PuppetController = _harness.runtime.puppet_controller
	for state in controller.puppets:
		if state.hook_slot == PuppetState.HOOK_SLOT_NONE:
			continue
		var ground := Vector2(state.stage_pos.x * CANVAS_SIZE.x,
			state.stage_pos.y * CANVAS_SIZE.y)
		if position.distance_to(ground - Vector2(0.0, 110.0)) <= PUPPET_HIT_RADIUS:
			return state.puppet_id
	return -1


## 场景被移出场景树时收尾：临时音轨若仍在播放，音频线程会在引擎清理阶段
## 报 ObjectDB 泄漏。选关与重开本关（PRD 第 3、8 节）都会走到这条路径。
## 注：`--quit-after` 这类**引擎级强制退出**不会等到音频播放对象释放，
## 那种情况下仍会打印两条 AudioStreamGeneratorPlayback 泄漏告警
## （主音轨 + 补救慢鼓各一条；退出码仍为 0）。
func _exit_tree() -> void:
	if _harness != null:
		_harness.shutdown()


func _shutdown_and_quit(code: int) -> void:
	if _shutting_down:
		return
	_shutting_down = true
	if _harness != null:
		_harness.shutdown()
	get_tree().quit(code)
