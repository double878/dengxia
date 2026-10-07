extends Node2D
## 幕后演出画面（A 模块）。**前四关共用这一个场景**，只换 `StageDef` 数据：
##   godot.exe --path . res://scenes/a_test/level1_a.tscn -- stage=2
##
## 本文件只做四件事：
## 1. 把物理键鼠按 **PRD 第 4.1 节**的输入规则翻译给 Level1Runtime；
## 2. 按关卡数据的 `initial` 布置开演布景（在场影人、挂起分布、站位、灯况）；
## 3. 按示意图布局画出幕后工作台：上方幕布与影子，下方「你的手边 · 身前矮处」
##    一条放油灯、手与三根签、两个挂钩、备用头架；
## 4. 作为**模拟显示端**每帧只读 PuppetState / LampState / TimedEvent，从不写状态，
##    因此它证明「A 先改状态，B/C 再读」这条单向数据流成立。
##
## 两类提示手（教学手 / 补救手）见下方 `_remedy_hand_visible` 前的说明——
## 它们的触发时机与条件必须互相区分、互不重叠。
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
## 开发用切关开关：`场景 -- stage=2`。四关共用这一个幕后场景，只换关卡数据。
## 刻意**不做成按键**：PRD 第 4.1 节只定义了一套键位，往演出场景里加测试键会让
## 玩家按到没有文档依据的键（空格曾被误当暂停就是这么来的）。
const STAGE_ARG_PREFIX := "stage="

@onready var _lamp: PlaceholderLamp = $Lamp
@onready var _puppet_views: Array = [$Puppet0, $Puppet1, $Puppet2]
@onready var _pause_button: Button = $Hud/PauseButton
@onready var _cue_label: Label = $Hud/CueLabel
@onready var _remedy_banner: Label = $Hud/RemedyBanner
@onready var _hook_label: Label = $Hud/HookLabel
@onready var _status_label: Label = $Hud/StatusLabel

var _harness: Level1Harness = null
var _stage_def: StageDef = null
## 本关在场的影人编号（来自关卡数据的开演布景）。不在列表里的未登场，画面不出现。
var _on_stage: Array = [0, 1, 2]
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


## 开发用切关：从命令行参数取 `stage=N`（1–4），缺省或非法时回第 1 关。
## 做成静态纯函数是为了能被无头测试直接断言「参数解析不会把非法值静默变成别的关」。
static func requested_stage_id() -> int:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for arg in args:
		var text: String = str(arg)
		if not text.begins_with(STAGE_ARG_PREFIX):
			continue
		var value: int = int(text.substr(STAGE_ARG_PREFIX.length()))
		if value >= 1 and value <= StageDef.LAST_TUTORIAL_LEVEL:
			return value
		return StageDef.LEVEL1_ID
	return StageDef.LEVEL1_ID


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
	_stage_def = StageDefScript.make_stage(requested_stage_id())
	if _stage_def == null:
		push_error("无法识别的关卡编号，请用 `-- stage=1..4`")
		_shutdown_and_quit(1)
		return
	_harness = HarnessScript.new(self, _stage_def)
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
		# 该探针断言的是第一关的布景与时序（35000 ms / 6 条关键动作 / 两钩皆满），
		# 其它关的布景不同，跑它只会得到一堆无意义的失败——明确跳过而不是误报。
		if _stage_def.id != StageDef.LEVEL1_ID:
			print("第一关探针不适用于第 %d 关（用 `-- stage=1` 再跑）" % _stage_def.id)
			_shutdown_and_quit(0)
			return
		var probe := ProbeScript.new()
		var failures: int = probe.run(_harness)
		_shutdown_and_quit(1 if failures > 0 else 0)


## 开演前的起始布景。全部来自关卡数据的 `initial`（PRD 第 4.2、6 节）：
## 起始受控影人、在场影人、挂起分布、站位与手角、灯距/显露/灯油。
##
## 布景之所以必须逐关不同：第 2 关要教挂起，**开局必须留出一个空挂钩**。
## 若沿用第一关「两钩皆满」的布景，`hook_current()` 找不到空位必然失败，
## 而 `take_back` 又要求「当前无人受控」——玩家会卡死在原地，整关无法完成。
func _configure_initial_stage() -> void:
	var runtime: Level1Runtime = _harness.runtime
	var lamp: LampState = runtime.lamp_controller.lamp
	lamp.exposure = float(_stage_def.initial.get("exposure", 1.0))
	lamp.distance = float(_stage_def.initial.get("distance", 0.5))
	lamp.oil = float(_stage_def.initial.get("oil", 1.0))
	var controller: PuppetController = runtime.puppet_controller
	var positions: Dictionary = _stage_def.initial.get("positions", {})
	var hand_angles: Dictionary = _stage_def.initial.get("hand_angles", {})
	var hung: Dictionary = _stage_def.initial.get("hung", {})
	for state in controller.puppets:
		var puppet_id: int = state.puppet_id
		state.is_controlled = false
		state.hook_slot = PuppetState.HOOK_SLOT_NONE
		if positions.has(puppet_id):
			var place: Array = positions[puppet_id]
			state.stage_pos = Vector2(float(place[0]), float(place[1]))
		if hand_angles.has(puppet_id):
			var angles: Array = hand_angles[puppet_id]
			state.hand_angle = Vector2(float(angles[0]), float(angles[1]))
		if hung.has(puppet_id):
			state.hook_slot = int(hung[puppet_id])
	# 恰好一个受控影人（不变量 1）：先全部清掉再设。
	var controlled: int = int(_stage_def.initial.get("controlled", 0))
	controller.controlled_id = controlled
	controller.get_puppet(controlled).is_controlled = true
	var on_stage: Array = _stage_def.initial.get("on_stage", [0, 1, 2])
	_on_stage = on_stage if not on_stage.is_empty() else [0, 1, 2]


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
		# 不在场的影人不画：第 2 关只让白素贞与小青登场，好让开局留出一个空挂钩。
		view.visible = _on_stage.has(i)
		view.puppet_state = runtime.puppet_controller.puppets[i]
		view.lamp_state = runtime.lamp_controller.lamp
		view.hand_anchor = HAND_ANCHOR
		view.stage_origin = Vector2.ZERO
		view.stage_size = CANVAS_SIZE

	_status_label.text = _stage_def.title
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


## 当前「已经被告知、但还没判定」的那条关键动作（无则返回空字典）。
## 这一条 cue 同时驱动三件事：HUD 文字、目标边界/方向箭头、**教学提示手**。
## 三处读同一个来源，因此「文字说的」与「手指的」永远是同一个动作，不会各说各话。
func _active_cue() -> Dictionary:
	if _stage_def == null or _harness == null:
		return {}
	var song_ms: int = _harness.clock.get_song_time_ms()
	for cue in _stage_def.cues:
		if _harness.runtime.director.performance.has_outcome(str(cue["cue_id"])):
			continue
		if song_ms >= CueScript.hint_time_ms(cue):
			return cue
	return {}


func _active_cue_text() -> String:
	var cue: Dictionary = _active_cue()
	if cue.is_empty():
		return "握住手边的胸签，跟着鼓点入场"
	return _action_text(str(cue.get("action", "")))


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
		CueScript.ACTION_MOVE_LEFT: return "向左拖动胸签，走向许仙"
		CueScript.ACTION_MOVE_RIGHT: return "向右拖动胸签，走到小青身旁"
		CueScript.ACTION_REACH: return "把影人带回幕布中央"
		CueScript.ACTION_HOOK: return "按空格挂起当前影人"
		CueScript.ACTION_TAKE_BACK: return "点选挂起的影人，按空格取回"
		CueScript.ACTION_HEAD_SWAP: return "按 1 / 2 / 3 与备用头架换头"
		CueScript.ACTION_LAMP_DISTANCE: return "滚轮推拉灯，让全场影子同步缩放"
		CueScript.ACTION_LAMP_EXPOSURE: return "按 Q / E 调整影子的显露"
		CueScript.ACTION_UMBRELLA_TAKE: return "走到许仙面前，按 A 抬左手到 90°，两只手碰到就接伞"
		CueScript.ACTION_UMBRELLA_RETURN: return "向左走回许仙身旁，把伞还回他的右手"
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
	# 伞先画：它挂在影人身后那一侧（幕后看到的正是背面），不该压住持伞的人。
	_draw_umbrella()
	_draw_hooks()
	_draw_head_rack()
	_draw_hands_and_tags()
	draw_rect(FOOTER, Color("#222927"))
	draw_line(Vector2(0.0, FOOTER.position.y), Vector2(CANVAS_SIZE.x, FOOTER.position.y),
		Color("#ad8147"), 2.0)
	_draw_beat_indicator()
	_draw_target_marker()
	# 两类提示手：同一时刻只画一只。互斥规则集中在 hint_hand_choice 一处，
	# 显示端只消费它的结果，不做第二套判断。
	var hand: int = _hand_choice()
	if hand == HAND_REMEDY:
		_draw_remedy_hand()
	elif hand == HAND_TEACHING:
		_draw_teaching_hand()
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
	# 初始两颗头换下后仍显示同一美术；头架位置、命中区与交换逻辑不变。
	if head_id == 0 or head_id == 1:
		var skin_manifest: Variant = PuppetViewScript.SKIN_MANIFEST.data
		if skin_manifest is Dictionary:
			var character: String = "baisuzhen" if head_id == 0 else "xuxian"
			var skin: Dictionary = skin_manifest.get("characters", {}).get(character, {})
			if not skin.is_empty():
				var size: float = 21.0 * float(skin["head_size_per_radius"])
				var mirror: float = 1.0 / float(skin["reference_facing"])
				draw_set_transform(centre, 0.0, Vector2(mirror, 1.0))
				draw_texture_rect_region(PuppetViewScript.SKIN_TEXTURES[head_id],
					Rect2(Vector2(-size * 0.5, -size * 0.5), Vector2(size, size)),
					Rect2(0.0, 0.0, 512.0, 512.0))
				draw_set_transform(Vector2.ZERO)
				return
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


## 某个影人的显示节点（下标即影人编号，与 `_refresh_ui` 的取法一致）。
## 不在场（未登场）或编号越界时返回 null，调用方据此不画——道具跟着人走，人不在就不画。
func _puppet_view(puppet_id: int) -> PlaceholderPuppet:
	if puppet_id < 0 or puppet_id >= _puppet_views.size():
		return null
	var view: PlaceholderPuppet = _puppet_views[puppet_id]
	return view if view.visible else null


## 第一关的伞（借伞还伞流程）。**落点由显示端决定**：画在持伞那只手画出来的手腕上
## （`PlaceholderPuppet.hand_screen_position`），所以伞永远握在手上，而且影子随灯距缩放时
## 手和伞一起变大变小。递伞过渡期间，从原来那只手的手腕移到新手的手腕，比例取 A 的
## `umbrella.handoff_blend()`（已缓入缓出），画面上就是「一只手把伞递出去」。
##
## 为什么不读 `UmbrellaController.position`：那是 A 内部的相对口径（归一化「幕布」坐标，
## 手高按 A 自己的肩高/臂长公式算），与影人显示端画出来的手臂比例不是同一套坐标系。
## 2026-10-04 实测：拿它换算像素，许仙举伞时伞被画到幕布底部（y≈668 px），
## 而他自己画出的右手在 267 px 高处——这就是「开局伞不在许仙手上」的原因。
##
## 别的关卡 `umbrella` 为 null，这里直接不画。
## —— 伞的几何（静态纯函数，供测试断言「伞面在头顶之上、且横向盖住头」）——
## 用户 2026-10-05 定案三条：① 伞留在**原位置**（拿伞的那只手上），不挪到头顶、也不居中；
## ② 整体放大，让伞面显得更大；③ **伞柄笔直**，不弯不斜。
##
## 因此伞面中心就在**手腕正上方**、伞杆是一条竖直线——而不是「从手斜拉到头顶」。
## 代价是几何上的：手举 90° 时腕点离身体中心 0.415 个身高（半身宽 0.105 + 整臂 0.31），
## 所以伞面半径必须 ≥ 0.415 个身高才能在横向盖住头，伞宽因此接近一个身高。
## 半径与下垂量都按当前身高算，灯距推拉、站蹲、翻面时伞都跟着走。
const CANOPY_LIFT_RATIO: float = 0.44    ## 伞面中心在手腕正上方多高（身高比例）
## 伞面半径（身高比例）。**0.415 是硬门槛**（手腕离身体中心的水平距离），低于它就盖不到头；
## 取 0.45 留一点余量，于是伞面左缘落到头顶左侧约 0.035 个身高处。
const CANOPY_RADIUS_RATIO: float = 0.45
## 伞面中心到最低下沿的距离（身高比例）。取 0.20 使伞面下沿恰好落在头顶之上
## （0.80 肩 + 0.44 抬升 − 0.20 下垂 = 1.04 > 头顶的 1.02）。
const CANOPY_DROP_RATIO: float = 0.20
## 伞杆粗细与「伞在谁手上」的标记也按身高走，灯距推拉时与影人一起缩放（原来是写死的像素）。
const CANOPY_STEM_EDGE_RATIO: float = 0.034
const CANOPY_STEM_WOOD_RATIO: float = 0.021
const CANOPY_GRIP_RATIO: float = 0.030

## 伞面中心：**手腕正上方** `CANOPY_LIFT_RATIO` 个身高处（伞杆因此是竖直的）。
static func umbrella_canopy_centre(hand: Vector2, figure_height: float) -> Vector2:
	return hand + Vector2(0.0, -figure_height * CANOPY_LIFT_RATIO)


static func umbrella_canopy_radius(figure_height: float) -> float:
	return figure_height * CANOPY_RADIUS_RATIO


static func umbrella_canopy_drop(figure_height: float) -> float:
	return figure_height * CANOPY_DROP_RATIO


func _draw_umbrella() -> void:
	# 清除上帧握持贴图，再按原控制器归属选择。交接与输入逻辑不变。
	for id in [0, 1]:
		var view: PlaceholderPuppet = _puppet_view(id)
		if view != null:
			view._held_prop_hand = ""
	if _harness == null:
		return
	var umbrella: UmbrellaController = _harness.runtime.director.umbrella
	if umbrella == null:
		return
	var holder: PlaceholderPuppet = _puppet_view(umbrella.holder_id_of())
	if holder == null:
		return
	holder._held_prop_hand = umbrella.holder_hand_of()
	# 握伞的那只手：伞面就在这只手的正上方，位置不挪动（用户 2026-10-05 第 1 条）
	var hand: Vector2 = holder.hand_screen_position(umbrella.holder_hand_of())
	var height: float = holder.figure_px_height()
	var flip_width: float = holder.flip_width_ratio()
	if umbrella.handing_off:
		var previous: PlaceholderPuppet = _puppet_view(umbrella.handoff_from_id())
		if previous != null:
			var blend: float = umbrella.handoff_blend()
			hand = previous.hand_screen_position(umbrella.handoff_from_hand()) \
				.lerp(hand, blend)
			height = lerpf(previous.figure_px_height(), height, blend)
			flip_width = lerpf(previous.flip_width_ratio(), flip_width, blend)
	var wood := Color("#8a5a2b")
	var paper := Color(0.87, 0.79, 0.62, 0.92)
	var edge := Color("#3a2a18")
	var canopy: Vector2 = umbrella_canopy_centre(hand, height)
	var radius: float = umbrella_canopy_radius(height) * flip_width
	var drop: float = umbrella_canopy_drop(height)
	# 伞杆：从手握处**竖直**向上到伞面中心（用户 2026-10-05 第 3 条：不弯不斜）
	draw_line(hand, canopy, edge, height * CANOPY_STEM_EDGE_RATIO * maxf(flip_width, 0.25))
	draw_line(hand, canopy, wood, height * CANOPY_STEM_WOOD_RATIO * maxf(flip_width, 0.25))
	# 伞面：一条弧（顶点在伞面中心，向两侧下垂），加上几条伞骨
	var rim := PackedVector2Array([
		canopy + Vector2(-radius, drop * 0.68),
		canopy + Vector2(-radius * 0.5, drop * 0.92),
		canopy + Vector2(0.0, drop),
		canopy + Vector2(radius * 0.5, drop * 0.92),
		canopy + Vector2(radius, drop * 0.68),
	])
	var face := PackedVector2Array([canopy])
	face.append_array(rim)
	draw_colored_polygon(face, paper)
	for i in rim.size():
		draw_line(canopy, rim[i], Color(edge.r, edge.g, edge.b, 0.45), 2.0)
	draw_polyline(rim, edge, 3.0)
	# 分件手本身显示握持；旧的大圆会遮住手指与伞杆的接触。
	if holder.puppet_state.puppet_id > 1:
		draw_circle(hand, height * CANOPY_GRIP_RATIO, Color(0.98, 0.72, 0.25, 0.90))


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
## 补救冻结期间**不画**：那时演出时间停住、新的落点不会到来，提示落点位置只会误导，
## 而且玩家正在补做上一个动作（与教学提示手同一条规则）。
func _draw_target_marker() -> void:
	if _harness == null or _paused or _harness.runtime.is_over():
		return
	if not _stage_def.is_tutorial():
		return
	if _harness.clock.is_song_frozen():
		return
	var cue: Dictionary = _active_cue()
	if cue.is_empty():
		return
	var bounds: Dictionary = cue.get("target_range", {})
	var key: String = str(bounds.get("key", ""))
	var action: String = str(cue.get("action", ""))
	if key == "x":
		var x0: float = CLOTH.position.x + float(bounds.get("min", 0.0)) * CLOTH.size.x
		var x1: float = CLOTH.position.x + float(bounds.get("max", 1.0)) * CLOTH.size.x
		draw_rect(Rect2(x0, CLOTH.position.y + 8.0, x1 - x0, CLOTH.size.y - 16.0),
			Color(0.98, 0.72, 0.25, 0.12))
		for x in range(int(x0), int(x1), 34):
			draw_line(Vector2(float(x), CLOTH.end.y - 10.0),
				Vector2(float(x), CLOTH.end.y - 34.0), Color(0.98, 0.72, 0.25, 0.55), 3.0)
	elif key == "distance" or key == "exposure":
		_draw_lamp_marker(key, bounds)
	elif CueScript.EVENT_ACTIONS.has(action):
		_draw_key_hint(action)
	else:
		_draw_pose_arrow(action)


## 灯位/倾灯类落点：在灯的那一侧画一条目标刻度带。只表达「推到哪一段」，
## 不显示百分比、不显示当前值（PRD 第 4.3、6 节明确不显示百分比）。
func _draw_lamp_marker(key: String, bounds: Dictionary) -> void:
	var track := Rect2(1516.0, 748.0, 24.0, 188.0)
	if key == "exposure":
		track = Rect2(1428.0, 748.0, 24.0, 188.0)
	draw_rect(track, Color(0.14, 0.11, 0.09, 0.72))
	var lo: float = float(bounds.get("min", 0.0))
	var hi: float = float(bounds.get("max", 1.0))
	var y0: float = track.end.y - hi * track.size.y
	var y1: float = track.end.y - lo * track.size.y
	draw_rect(Rect2(track.position.x, y0, track.size.x, maxf(y1 - y0, 4.0)),
		Color(0.98, 0.72, 0.25, 0.55))
	draw_rect(track, Color(0.98, 0.72, 0.25, 0.90), false, 2.0)


## 按键类落点（挂起/取回/换头）在受控影人身旁画一个按键徽标。
## 画的是「按哪个键」，不是「按哪个拍」——拍号依旧不得泄露（PRD 第 5.1 节）。
func _draw_key_hint(action: String) -> void:
	var controller: PuppetController = _harness.runtime.puppet_controller
	var controlled: PuppetState = controller.get_controlled()
	var base := Vector2(CANVAS_SIZE.x * 0.5, 320.0)
	if controlled != null:
		base = Vector2(controlled.stage_pos.x * CANVAS_SIZE.x,
			controlled.stage_pos.y * CANVAS_SIZE.y - 258.0)
	var label: String = "1·2·3" if action == CueScript.ACTION_HEAD_SWAP else "空格"
	var colour := Color(0.98, 0.72, 0.25, 0.90)
	var box := Rect2(base.x - 54.0, base.y - 27.0, 108.0, 54.0)
	draw_rect(box, Color(0.10, 0.08, 0.06, 0.78))
	draw_rect(box, colour, false, 3.0)
	draw_string(ThemeDB.fallback_font, Vector2(box.position.x, base.y + 11.0), label,
		HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 30, colour)


## 姿势类动作（站起/蹲下/抬手/落手）用影人身旁的方向箭头提示，不写数字。
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


## —— 两类提示手 ——
##
## 这是本文件里最容易被做重的一处，因此把「谁是预告、谁是纠正」写清楚：
##
## |            | 教学提示手（前四关） | 补救提示手 |
## | 触发条件   | 某条落点已进入线索时间、且尚无判定结果 | 补救窗口开着（`current_demo_cue_id` 非空） |
## | 结束条件   | 该落点被判定（命中或错拍） | 窗口关闭（补做成功／超时／收场） |
## | 计时依据   | **歌曲时间**（演出正常推进） | **真实时间**（歌曲时间此时已冻结） |
## | 样式       | 半透明描边（预告，轻） | 实色填充 + 外圈光晕（纠正，重） |
##
## **互斥规则：补救冻结期间一律不画教学手，同一时刻只画一只。** 理由有两条：
## 1. 补救冻结时演出时间停住，**新的落点不会到来**——这时预告「即将到来的动作」是误导，
##    而且玩家此刻正在补做上一个动作，屏幕上多一只手只会干扰。
## 2. 漏做型补救的窗口开在落点之后，该落点的线索时段本就已过，天然不重叠；
##    只有「低合拍型补救挂在段内更靠前、还没到落点的 cue 上」时才可能重叠，必须显式压制。
## 提示手的选择结果。用整数而不是两个 bool，是为了让「互斥」在类型上就成立：
## 同一时刻只可能返回其中一种，不存在两只手同时为真的状态。
const HAND_NONE: int = 0
const HAND_TEACHING: int = 1
const HAND_REMEDY: int = 2


## 两类提示手的显示判定。做成**静态纯函数**，这样互斥规则可以被无头测试直接断言，
## 不必靠跑图形界面去看「画面上到底有几只手」。
## 优先级：补救手 > 教学手；补救冻结期间一律不出手（教学手被压制，补救手本就来自窗口）。
static func hint_hand_choice(paused: bool, over: bool, is_tutorial: bool, frozen: bool,
		remedy_demo_cue_id: String, active_cue_id: String) -> int:
	if paused or over:
		return HAND_NONE
	if not remedy_demo_cue_id.is_empty():
		return HAND_REMEDY
	if frozen:
		return HAND_NONE
	if not is_tutorial:
		return HAND_NONE
	if active_cue_id.is_empty():
		return HAND_NONE
	return HAND_TEACHING


func _hand_choice() -> int:
	if _harness == null or _stage_def == null:
		return HAND_NONE
	return hint_hand_choice(_paused, _harness.runtime.is_over(), _stage_def.is_tutorial(),
		_harness.clock.is_song_frozen(),
		_harness.runtime.director.remedy.current_demo_cue_id,
		str(_active_cue().get("cue_id", "")))


## 教学提示手：每个关键动作**发生之前**出现，示范「该做什么」（PRD 第 5.1 节）。
## 用歌曲时间驱动摆动——这是正常演出时间，与补救手的真实时间形成明确区分。
func _draw_teaching_hand() -> void:
	var cue: Dictionary = _active_cue()
	if cue.is_empty():
		return
	var now_s: float = _harness.clock.get_song_time_s()
	var sway: float = sin(now_s * 4.0) * 16.0
	var base: Vector2 = HAND_ANCHOR + Vector2(-186.0, 4.0) \
		+ _action_motion(str(cue.get("action", "")), sway)
	_draw_hand_shape(base, true, 0.62)


## 补救提示手：只在失误后的补救窗口里出现，只示范动作本身（PRD 第 5.2 节）。
func _draw_remedy_hand() -> void:
	# 用真实时间驱动示范手的摆动：补救期间歌曲时间是冻结的，用它会得到一只僵住的手，
	# 而这只手的作用恰恰是「让玩家看出该补做什么动作」。
	var now_s: float = _harness.clock.get_real_time_s()
	var action: String = str(_find_cue(
		_harness.runtime.director.remedy.current_demo_cue_id).get("action", ""))
	var sway: float = sin(now_s * 7.0) * 20.0
	var base: Vector2 = HAND_ANCHOR + Vector2(-186.0, 4.0) + _action_motion(action, sway)
	# 外圈光晕：让「纠正」比「预告」更重，两类手一眼可分。
	draw_arc(base, 46.0, 0.0, TAU, 40, Color(1.0, 0.85, 0.5, 0.35), 5.0)
	_draw_hand_shape(base, false, 1.0)


## 由动作类型得到示范手的摆动方向：横移类左右摆，抬落/挂取类上下摆。
## 两类提示手共用，保证「手指的方向」与「落点要求的动作」永远一致。
func _action_motion(action: String, sway: float) -> Vector2:
	match action:
		CueScript.ACTION_MOVE_LEFT: return Vector2(-sway, 0.0)
		CueScript.ACTION_MOVE_RIGHT, CueScript.ACTION_REACH: return Vector2(sway, 0.0)
		CueScript.ACTION_CROUCH, CueScript.ACTION_HAND_LOWER: return Vector2(0.0, sway)
		CueScript.ACTION_LAMP_DISTANCE: return Vector2(sway, 0.0)
		CueScript.ACTION_LAMP_EXPOSURE: return Vector2(0.0, -sway)
		CueScript.ACTION_HOOK, CueScript.ACTION_TAKE_BACK: return Vector2(0.0, -sway * 0.6)
		CueScript.ACTION_HEAD_SWAP: return Vector2(sway * 0.5, -sway * 0.5)
		CueScript.ACTION_UMBRELLA_TAKE: return Vector2(0.0, -sway)
		CueScript.ACTION_UMBRELLA_RETURN: return Vector2(sway, 0.0)
		_: return Vector2(0.0, -sway)


## 一只手。`outlined` 为 true 时只描边（教学手），false 时实色填充（补救手）。
func _draw_hand_shape(centre: Vector2, outlined: bool, alpha: float) -> void:
	var edge := Color(0.44, 0.25, 0.15, alpha)
	var fill := Color(0.90, 0.73, 0.51, alpha)
	for i in 4:
		var root := Vector2(centre.x - 25.0 + float(i) * 17.0, centre.y - 14.0)
		var tip := Vector2(root.x - 2.0, centre.y - 70.0 - float(i % 2) * 12.0)
		if not outlined:
			draw_line(root, tip, fill, 11.0)
		draw_line(root, tip, edge, 3.0)
	var thumb_root: Vector2 = centre + Vector2(-25.0, 16.0)
	var thumb_tip: Vector2 = centre + Vector2(-62.0, -19.0)
	if not outlined:
		draw_line(thumb_root, thumb_tip, fill, 14.0)
	draw_line(thumb_root, thumb_tip, edge, 3.0)
	if outlined:
		draw_arc(centre, 36.0, 0.0, TAU, 32, edge, 4.0)
	else:
		draw_circle(centre, 36.0, fill)
		draw_arc(centre, 36.0, 0.0, TAU, 36, edge, 3.0)


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
