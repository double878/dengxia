extends RefCounted
class_name CSceneryDef
## C 侧布景数据（**背景环境**：柳树、桥一类舞台景物）。
##
## ⚠️ 名词澄清（本项目有三个长得很像、但完全不同的东西，别混）：
##   1. 「布景」= 本文件 = 背景环境（山水、桥、柳树），纯装饰、**不参与判定**
##   2. 「开演站位」= `scripts/a/stage_def.gd` 的 `initial`（谁在场、站哪、什么姿势），
##      那是 A 的数据，决定判定，**不是本文件负责的**
##   3. 「灯光/影子」= 由 LampState 驱动，与布景无关（布景**不随灯影缩放**）
##
## 契约依据：
##   - PRD.md 第 2 节：五关共用同一幕后工作台/幕布/灯/影人，差异来自「目标动作、
##     **局部布景**、灯况与节奏」
##   - PRD.md 第 6 节第 3 关：「通过灯位使影子先缩小**经过布景**，再放大形成亮相……
##     **布景以演出调度呈现，不做实体推挡板玩法**」
##   - TECH_DESIGN.md 第 2.2 节：`StageDef` 字段含「局部布景」
##
## 三条硬约束（由本数据结构本身保证，不靠调用方自觉）：
##   ① **景物只能左右平移**：位移字段只有 `pan_x`；本结构**不提供** y/缩放/旋转字段。
##      （`anchor_y` 是「接地线在哪」，不是「可以上下移动」——它被限制在极窄的
##      [Y_MIN, Y_MAX] 内，用来把布景对齐到影人的接地线，不是自由纵向位移。）
##   ② **纵轴基准对齐影人接地点**：`anchor_y` 必须落在 `ANCHOR_Y ± Y_TOLERANCE` 内。
##      影人的接地点是归一化 y = 0.5（见 A 侧 `stage_def.gd` 的 `initial.positions`），
##      布景的「底」也在这条线上，画的才是「同一个地面」。
##   ③ **不参与判定**：本文件只被显示端读取，不进 PuppetState / LampState，
##      不进记录与回放（不产生事件、不进 CSnapshot）。
##
## 坐标口径：舞台归一化 0–1，与影人**同一坐标系**（`PlaceholderPuppet.stage_to_screen()`
## 与 A 侧 `PuppetController.STAGE_PIXEL_SIZE` 同源）。这样布景与影人天然对齐，
## 换关只换数据、不换映射。

## —— 纵轴基准与容差 ——
## 影人接地点：A 侧 `stage_def.gd` 第一关 `initial.positions` 三具全部 y = 0.5。
## 布景的接地线必须与它对齐，否则树根/桥脚与影人的脚会分处两条线（画面像贴上去的）。
const ANCHOR_Y: float = 0.5
## 允许的上下浮动。用户 2026-10-08 定案「上下浮动不能超过 0.03」。
## 三条断言都盯这个值：`anchor_y`、树冠底、桥面高都不得越出 [0.47, 0.53]。
const Y_TOLERANCE: float = 0.03
const Y_MIN: float = ANCHOR_Y - Y_TOLERANCE   ## 0.47
const Y_MAX: float = ANCHOR_Y + Y_TOLERANCE   ## 0.53

## —— 第一关「入手 · 游湖借伞」布景参数（用户 2026-10-08 定案）——
## 用户手绘草图 + 后续四条修正得来。**只有两样东西**：
##   柳树：树干在 x = 0.08（许仙身侧，许仙在 x = 0.13）
##   拱桥：起点 x = 0.72，向右侧拱起、到画布右缘后水平延伸出画
##
## ⚠️ 用户明确「**暂时不画花草**」「边界线不用画」——本关不出现花草与画框线。
## 记为常量而不是散在函数里，是为了让断言能直接引用同一个数（避免数据与测试各写一套）。
const LEVEL1_WILLOW_X: float = 0.08      ## 柳树树干
const LEVEL1_BRIDGE_START_X: float = 0.72  ## 拱桥起点（用户 2026-10-08 由 0.85 改为 0.72）

## —— 元素种类 ——
## 显示端按 `kind` 选画法。新增种类时两边都要改（数据 + 画面），故集中在这里。
const KIND_WILLOW: String = "willow"      ## 柳树：树干 + 向左上展开的树冠
const KIND_ARCH_BRIDGE: String = "arch_bridge"  ## 拱桥：半拱 + 水平延伸出画

## —— 位移字段名（**唯一**合法的位置相关字段）——
## 断言会检查每条元素「除这些以外没有别的位移字段」，防止有人偷偷加 y/scale/rotation。
const POSITION_KEYS: Array[String] = ["anchor_x", "anchor_y", "pan_x"]

var stage_id: int = 1
## 布景元素列表。每条：
##   "id"       : String  元素标识（同一关内不得重复）
##   "kind"     : String  画法种类（见 KIND_* 常量）
##   "anchor_x" : float   水平定位，归一化 0–1
##   "anchor_y" : float   接地线高度，必须 ∈ [Y_MIN, Y_MAX]
##   "pan_x"    : float   水平平移量（演出中唯一允许的位移），初始 0
##   "params"   : Dictionary  该种元素自己的形状参数（不参与通用校验）
var items: Array[Dictionary] = []


## 第一关布景：柳树 + 拱桥。
## 用户 2026-10-08 手绘草图后逐条修正定案：
##   - 柳树树干 x = 0.08（在许仙身侧；许仙 x = 0.13，树干略靠他左边）
##   - 拱桥起点 x = 0.72（用户先给 0.85，后修正为 0.72）
##   - 桥在小青**右侧方向**延伸（用户 2026-10-08 选「方案 A」）；
##     小青本人仍站在 A 侧数据的 x = 0.86，**本文件不改小青位置**
##     （用户明确：「小青的位置不改动，我只负责改动背景的位置」）
##   - 树根与桥脚都落在接地线 y = 0.5 上（用户选「接地线对齐」方案 A）
static func make_level1() -> CSceneryDef:
	var def := CSceneryDef.new()
	def.stage_id = 1
	def.items = [
		{
			"id": "willow_left",
			"kind": KIND_WILLOW,
			"anchor_x": LEVEL1_WILLOW_X,
			"anchor_y": ANCHOR_Y,
			"pan_x": 0.0,
			"params": {
				# 树干高 / 树冠横向展开半径 / 树冠纵向半径，单位都是「画布高度比例」。
				# 树冠向左上展开：`crown_bias_x` 为负表示树冠中心在树干左侧。
				"trunk_height": 0.20,
				"crown_radius_x": 0.075,
				"crown_radius_y": 0.055,
				"crown_bias_x": -0.02,
			},
		},
		{
			"id": "bridge_right",
			"kind": KIND_ARCH_BRIDGE,
			"anchor_x": LEVEL1_BRIDGE_START_X,
			"anchor_y": ANCHOR_Y,
			"pan_x": 0.0,
			"params": {
				# 半拱：从 anchor_x 起拱，到 `arch_end_x` 到达拱顶高度，之后水平延伸出画。
				# `arch_end_x` = 1.0 表示「拱顶正好在画布右缘」，随后桥面水平伸到画外。
				"arch_end_x": 1.0,
				"deck_rise": 0.10,   ## 桥面（拱顶）比接地线高多少
				"deck_thickness": 0.018,
				"pier_width": 0.010,
			},
		},
	]
	return def


## 按关卡编号取布景数据。未知编号返回**空布景**（而不是给一关默认的），
## 免得「第 2 关没做」被静默顶替成第 1 关的布景、画面看着像做完了。
static func make_stage(stage_id: int) -> CSceneryDef:
	match stage_id:
		1:
			return make_level1()
	var empty := CSceneryDef.new()
	empty.stage_id = stage_id
	return empty
