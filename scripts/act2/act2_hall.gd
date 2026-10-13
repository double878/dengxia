extends Node2D
## 第二关第二幕「端阳饮酒」：把**编号 22 的室内厅堂布景**接进游戏。
##
## 与第一幕（`scripts/act2/act2_opening.gd`，门楼版编号 2）的关系：
##   第一幕在门外（法海劝酒），末句应允后自动暗场清场；本幕接在暗场之后，
##   舞台换成厅堂（`CSceneryDef.make_level2_act2()`，编号 `LEVEL2_ACT2_STAGE_ID` = 22）。
##   两场同属第二关，中途不结算、不回放（PRD 第 6.2 节）。
##
## ⚠️ 交付边界（用户 2026-10-13 定案「**只把厅堂景摆进游戏**」）：
##   本场景**只负责把厅堂布景按正式舞台的层级挂上去并显示**——
##   背幕(-2) → 幕布(-1) → 布景(0)，与第一幕同一套层级、同一块幕布尺寸。
##   递杯、抬杯饮酒、人身退场换完整白蛇、调灯显形与许仙惊倒等剧情**均未实现**，
##   属后续切片；因此本幕**不放影人、不接受操控输入**。
##
## 布景不参与判定（见 `c_scenery_def.gd` 三条硬约束）：本场景读到的布景只用来画，
## 不进 `PuppetState` / `LampState`、不产生事件、不进记录与回放。

## 幕布矩形。**必须与 A 侧 `level1_a_scene.gd` 与 C 侧 `CStageBinding.CLOTH` 同值。**
const CLOTH := Rect2(66, 92, 1788, 588)
## 第二关第二幕的布景编号，与 `CSceneryDef.LEVEL2_ACT2_STAGE_ID` 同值。
## ⚠️ 两处都写死 22 是有意的：布景数据归 C 侧、切幕归本场景，
## 取错编号会静默画成第一幕门楼或空布景，故测试会正面断言「本幕只取 22」。
const HALL_STAGE_ID: int = 22
## 与第一幕同一固定步长口径，保证火光/幕面闪烁的推进速度一致。
const FIXED_DELTA: float = 1.0 / 60.0

## 唯一时钟。本幕**没有主音轨**，只借它的真实时间驱动火光与幕面闪烁，
## 免得另开一套计时器与第一幕不同源。
var clock := MusicClock.new()
var lamp_controller := LampController.new()
var _surface: StageSurface
var _status: Label
var _hint: Label
var _accumulator: float = 0.0


func _ready() -> void:
	clock.start()
	# 无音轨：歌曲时间冻结在 0，真实时间照走（供火光使用），与第一幕就位等待同口径。
	clock.set_song_frozen(true)
	lamp_controller.clock = clock
	lamp_controller.setup()
	var backdrop := StageBackdrop.new()
	backdrop.z_index = -2
	add_child(backdrop)
	_surface = StageSurface.new()
	_surface.z_index = -1
	add_child(_surface)
	_surface.configure(CLOTH)
	# 本幕无影人：按「无人上场」状态初始化投影，避免幕面上出现残留。
	_surface.sync_puppets([], [])
	# 布景层：与第一幕同一个绑定层，只是换成编号 22（厅堂）。本幕无雨。
	var binding := CStageBinding.new()
	binding.name = "CStageBinding"
	binding.stage_id = HALL_STAGE_ID
	binding.enable_rain = false
	add_child(binding)
	_build_hud()
	_refresh()


func _process(delta: float) -> void:
	_accumulator += maxf(delta, 0.0)
	var steps: int = 0
	while _accumulator >= FIXED_DELTA and steps < 8:
		_accumulator -= FIXED_DELTA
		steps += 1
		clock.update(FIXED_DELTA)
		lamp_controller.update(FIXED_DELTA)
	if steps == 8:
		_accumulator = 0.0
	_refresh()


func _refresh() -> void:
	_surface.update_light(
		lamp_controller.lamp, clock.get_real_time_ms(), clock.get_song_time_ms(), clock.bpm
	)


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	# 与第一关同名的台口信息层，便于宿主与测试按名字取用。
	hud.name = "Hud"
	add_child(hud)
	_status = _label(hud, Vector2(76, 18), Vector2(1570, 50), 28)
	_status.text = "第二关 · 端阳惊变    第二幕 · 端阳饮酒"
	_hint = _label(hud, Vector2(80, 1005), Vector2(1770, 55), 26)
	_hint.text = "本幕本轮只交付厅堂布景；递杯、饮酒与显形等待后续切片"


func _label(parent: Node, at: Vector2, size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#e7c590"))
	parent.add_child(label)
	return label


func _exit_tree() -> void:
	clock.pause()
