extends Node2D
class_name CStageBinding
## C 侧布景接入A 侧演出场景的**绑定层**（切片 2.1）。
##
## 职责边界（不越界的四条）：
##   1. **只挂载，不改造**：本文件只负责把 `CSceneryView` + `CRainOverlay` 挂到
##      已有演出场景的合适层级上，并按关卡取布景数据。它**不修改** A 侧的
##      `level1_a_scene.gd`，也不碰 A 侧的任何节点——A 侧代码对 C 侧无感知。
##   2. **不改判定**：布景不产生事件、不进 `PuppetState`/`LampState`、不参与任何
##      合拍判定（与 `c_scenery_def.gd` 的三条硬约束一致）。
##   3. **不覆盖 A 侧版本控制**：布景用 `z_index` 插在幕布表面之上、影人之下；
##      不去改别人已定的z_index，只在自己的节点上设。
##   4. **优雅缺席**：布景数据缺失或贴图加载失败时**静默降级**（不画布景），
##      演出照常进行——布景是装饰，缺它不该让游戏开天窗。
##
## 层级依据（`level1_a_scene.gd` 现状，A 侧定案）：
##   -2 StageBackdrop（舞台背幕）
##   -1 StageSurface（幕布表面，configure(CLOTH)）
##    0 **← 布景层在这里**（幕布之上、影人之下）
##   15 **← 雨幕层在这里**（影人之下，避免雨丝盖住人物表演）
##   18 UmbrellaVisual / 20 影人 / 30 灯 / 80 前景提示层
##
## 用法（A 侧场景 `_ready()` 里，**在 surface 之后、影人之前**）：
##   var binding := CStageBinding.new()
##   binding.stage_id = _stage_def.id
##   add_child(binding)
## 或不设stage_id（默认 1）。

const SceneryViewScript := preload("res://scripts/c/c_scenery_view.gd")
const RainOverlayScript := preload("res://scripts/c/c_rain_overlay.gd")
const SceneryDefScript := preload("res://scripts/c/c_scenery_def.gd")

## 幕布矩形。**必须与 A 侧 `level1_a_scene.gd` 的 CLOTH 同值**（Rect2(66,92,1788,588)）。
## ⚠️ 这是跨侧约定：A 侧改了版面尺寸，这里必须跟着改。断言里有一致性检查兜底。
const CLOTH := Rect2(66.0, 92.0, 1788.0, 588.0)

## 舞台映射区。与 A 侧同口径（1920×1080 归一化坐标系，原点对齐）。
const CANVAS_SIZE := Vector2(1920.0, 1080.0)

## 布景层与雨幕层的 z_index（见类头层级依据）。
const Z_SCENERY: int = 0
const Z_RAIN: int = 15

## 关卡编号（1–4）。取布景数据用；缺省 1。
@export var stage_id: int = 1

## 是否挂雨幕氛围层。演出中默认开；幕前回放期由调用方关掉（回放画面另有构图）。
@export var enable_rain: bool = true

var _scenery: Node2D = null
var _rain: Node2D = null


func _ready() -> void:
	# 布景：未知关卡返回空布景（不是拿第 1 关顶替），空就真的不画
	var def: CSceneryDef = SceneryDefScript.make_stage(stage_id)
	if def == null or def.items.is_empty():
		return
	_scenery = SceneryViewScript.new()
	_scenery.name = "CScenery"
	# stage_size/origin 必须在**进树前**设好——CSceneryView 的 _ready 按 clip_rect
	# 决定是否开启渲染器级裁剪，进树后再设就来不及了。
	_scenery.stage_origin = Vector2.ZERO
	_scenery.stage_size = CANVAS_SIZE
	_scenery.z_index = Z_SCENERY
	# 裁剪到幕布：布景越界部分由渲染器裁掉，不会印到幕布外的木框/黑边上。
	_scenery.clip_rect = CLOTH
	_scenery.setup(def)
	add_child(_scenery)

	if not enable_rain:
		return
	_rain = RainOverlayScript.new()
	_rain.name = "CRainOverlay"
	_rain.position = CLOTH.position
	_rain.z_index = Z_RAIN
	add_child(_rain)
	_rain.setup(CLOTH.size)


## 关掉雨幕（幕前回放期用：回放画面有自己的构图，雨幕会干扰 1:1 还原）。
func set_rain_enabled(on: bool) -> void:
	enable_rain = on
	if _rain == null:
		return
	_rain.visible = on
	# 雨幕靠 _process 自持滚动，隐藏即可停；不设 process=false 是为了让再次显示时
	# 偏移连续（视觉上不跳变）。