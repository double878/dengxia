extends RefCounted
class_name StageDef
## 前四关关卡数据：固定时长、BPM、段落与关键动作。
##
## 契约见 TECH_DESIGN.md 第 2.2 节与 docs/superpowers/plans/2026-10-03-level1-a.md。
##
## 一关 = 一折。四关按《白蛇传》皮影戏的经典折目改写教程，但**关键动作严格依 PRD 第 6 节**：
##   第 1 关「入手」→ 游湖借伞（单人：站起/移步/抬手/到位）
##   第 2 关「双人」→ 游湖同舟（挂起/取回 + 一人挂起保持姿势、另一人运动组同框）
##   第 3 关「灯位」→ 盗仙草（灯位推拉使全场影子先缩后放、先隐后亮）
##   第 4 关「显隐」→ 端阳现身（换头 + 倾灯由低显露逐步推到完整亮相）
## 情节只决定「谁出场、怎么出场、做什么动作的动机」，**不改动**各关要教的操作与判定范围。
##
## 四关统一 96 BPM（PRD 第 10 节的原型起点 90–100 内），时长与 PRD 第 6 节一致：
## 35 / 45 / 50 / 55 秒。

const CueScript := preload("res://scripts/a/cue.gd")
const PuppetStateScript := preload("res://scripts/a/puppet_state.gd")

const LEVEL1_DURATION_MS: int = 35000     ## PRD 第 6 节：第一关固定 35 秒（不延长）
const LEVEL2_DURATION_MS: int = 45000     ## 第二关「双人」
const LEVEL3_DURATION_MS: int = 50000     ## 第三关「灯位」
const LEVEL4_DURATION_MS: int = 55000     ## 第四关「显隐」
const LEVEL1_BPM: float = 96.0            ## PRD 第 10 节：原型 BPM 初始考虑 90-100
const LEVEL1_ID: int = 1
const LAST_TUTORIAL_LEVEL: int = 4        ## 1–4 关为教学关（前四关可出现教学图标）
## —— 手角口径与两档「抬手」到位区间（弧度）——
## 手角以「手臂自然垂下」为 0、π/2 为水平前伸、π 为举过头顶（见 PuppetState）。
##
## 「举过头顶」档：第 2~4 关的抬手落点（举桨 / 采仙草 / 举杯）用它。
## 名字里刻意不带关卡号——它被 L2/L3/L4 共用；L1 的抬手是下面的「打伞位」，不是举过头顶。
const HAND_OVERHEAD_MIN_RAD: float = PI * 0.75   ## 135°
const HAND_OVERHEAD_MAX_RAD: float = PI          ## 180°
## 第一关「打伞位」与交接窗口
## 许仙固定站在这个 x 上；交接窗口由「两人都抬手到 90°、手在中间相接」推出，
## 因此与 `UmbrellaController.join_window_x()` 是同一处来源——落点数据与运行时判据不会漂开。
const LEVEL1_XUXIAN_X: float = 0.13
## 小青的开局站位（整关不动）。白素贞接到伞后要走到她**身旁**当作折返点。
## 用户 2026-10-05 定案：原先要求走到舞台最右端（x≥0.95），实测太远、也没必要。
const LEVEL1_XIAOPING_X: float = 0.86
## 「走到小青身旁」落点的目标带。两条硬约束：
##   ① 必须与交接窗口（0.176~0.296）不重叠，否则这一步会先经过交接窗口、
##      被还伞判定抢走伞（还伞要求已到过折返点，顺序一颠倒这一趟就白走）；
##   ② 下界**直接取控制器的 `TURN_POINT_X`**，不另写一个数——控制器置起「已到过折返点」
##      的条件就是 `x ≥ TURN_POINT_X`。落点带若写得比它低，玩家停在两者之间时会出现
##      最坏的一种错配：**拍点判命中、却没记下到过折返点，走回去时还伞永远不触发**。
## 上界 0.84 让白素贞停在小青（0.86）左侧；再往右画面上会与她叠在一起（两具影身各宽约 0.026）。
const LEVEL1_TURN_MIN: float = UmbrellaController.TURN_POINT_X
const LEVEL1_TURN_MAX: float = 0.84
## 「走向许仙」落点的目标带：只要确实向左走过一段就成立，具体停在哪儿交给交接窗口。
const LEVEL1_APPROACH_MIN: float = 0.0
const LEVEL1_APPROACH_MAX: float = 0.35
## 长距离移动落点的线索提前量（毫秒）。这一折有两次长距离横移：接到伞后走到小青身旁
## （约 0.55 个舞台宽 ≈ 1060 画布像素）、再走回许仙身旁（约 0.50 ≈ 960 px），
## 按正常拖速 450~600 px/s 各需 1.6~2.4 s，再加反应时间。原地动作仍用默认 1 s。
const LEVEL1_MOVE_HINT_LEAD_MS: int = MOVE_BUDGET_MS
## 后半段三条落点的拍号（用户 2026-10-05 定案「铺开到 31 s」）。
## 改动前：接伞后 2.5 s 就要求走到最右端，动作挤在 10~19 s 全部做完，之后 16 s 无事可做。
## 现在把三条落点均匀铺到第 48 拍，每段留 5~6 s（每趟移动本身只需 1.6~1.8 s），
## 玩家可以从容走位、按鼓点踩点，最后留 5 s 收势。
const LEVEL1_TURN_BEAT: int = 26      ## 16250 ms：接伞后 6.25 s，走到小青身旁
const LEVEL1_RETURN_BEAT: int = 40    ## 25000 ms：再 8.75 s 走回交接窗口还伞
const LEVEL1_LOWER_BEAT: int = 48     ## 30000 ms：再 5 s 放下左手收势（关卡 35 s，余 5 s）
## 最后一条落点之后留给收势的时间上限（毫秒）。用户 2026-10-05 报「所有动作做完还有约 10 秒
## 没事做」——后半段三条落点因此铺到第 48 拍，尾部只留 5 s。
## 由 `tests/a/test_level1_cues.gd` 的结构断言钉住，防止以后又把落点往前挪回去。
const LEVEL1_TAIL_MS: int = 6000

## 「落手」到位区间：接近自然垂下。
const HAND_LOWER_MIN_RAD: float = 0.0
const HAND_LOWER_MAX_RAD: float = 0.35

## 长距离移动落点的最小时间预算（毫秒）。判据是**画面上要走多远**，不是"给了几拍"：
## 这一折两次横移各走约 0.5~0.55 个舞台宽（960~1060 画布像素，拖动是 1:1 映射
## `dpx.x / STAGE_PIXEL_SIZE.x`），按正常拖速 450~600 px/s 需 1.6~2.4 s，再加 0.3~0.5 s 反应。
## 因此：长距离移动落点之间、以及它的线索提前量，都必须 ≥ 这个值。
## 由 `tests/a/test_level1_cues.gd` 的结构断言钉住（原地动作不受影响，仍按 1 s 提前）。
const MOVE_BUDGET_MS: int = 3000

## —— 第一关「打伞位」——
## 用户 2026-10-04 定案：打伞时手臂抬到 90° 即可，不必举过头顶。于是许仙开局举伞 90°，
## 白素贞也只需抬到 90° 接伞。90° = 手臂水平前伸：伞杆从手向上撑起，伞面罩在头顶。
const LEVEL1_HAND_MAX_RAD: float = PI * 0.5      ## 90°，同时是第一关的手角上限
## 第一关抬手（打伞位）的到位区间。下界取 75° 不是随手定的：
## 它必须**完整包住接伞的对齐窗口**，否则会出现「拍点算抬手到位、伞却不换手」的错配。
## 对齐窗口 = 两手手高差 ≤ 0.04（≈±7.6°）∩ 本关 90° 上限 = 82.4°~90° ⊂ [75°, 90°]。
const LEVEL1_UMBRELLA_RAISE_MIN_RAD: float = PI * 75.0 / 180.0
const LEVEL1_UMBRELLA_RAISE_MAX_RAD: float = LEVEL1_HAND_MAX_RAD

var id: int = LEVEL1_ID
var duration_ms: int = LEVEL1_DURATION_MS
var bpm: float = LEVEL1_BPM
## 本折的手角上限（弧度）。默认 = PuppetState.HAND_ANGLE_MAX（180°，举过头顶）。
## 第一关收到 90°：这一折的姿势只有「打伞位」，手臂不需要举过头顶。除了姿势本身，
## 收上限还有一个手感上的作用——它让「抬到 90°」变成一个**能停住的位置**：
## 按住抬手键到顶就是 90°，玩家不必掐角度、也不会扫过头（见 LEVEL1_HAND_MAX_RAD）。
## 由 Level1Runtime.setup 交给 PuppetController.hand_angle_max。
var hand_angle_max_rad: float = PI
var track_path: String = ""               ## 正式锣鼓主音轨；B 未交付时保持为空
## 本折的戏名与戏单文案（PRD 第 3、5.1 节：演前戏单说明段落顺序、出场角色与表演目标，
## 不含逐键操作与精确拍号）。显示端只读，不参与判定。
var act: String = ""                      ## 折名，如「游湖借伞」
var title: String = ""                    ## 关名，如「第一折 · 入手」
var roles: Array[String] = []             ## 本折出场角色
var summary: String = ""                  ## 戏单简介
## 开演布景（由显示端读取，不参与判定）：
##   "controlled": int                 起始受控影人编号
##   "on_stage": [int]                 在场的影人编号（不在列表里的未登场，画面不出现）
##   "hung": {int: int}                影人编号 -> 挂钩槽位
##   "positions": {int: [float, float]} 接地点归一化 x/y
##   "hand_angles": {int: [float, float]} 左右手角（弧度，不得超过 hand_angle_max_rad）
##   "distance" / "exposure" / "oil": float  灯的初值
var initial: Dictionary = {}
var segments: Array = []                  ## [{name: String, start_ms: int, end_ms: int}]
var cues: Array = []                      ## 关键动作列表，结构见 Cue.make()


## 按关卡编号取数据。未知编号返回 null（调用方负责报错，不静默给一关默认数据）。
static func make_stage(stage_id: int) -> StageDef:
	match stage_id:
		1:
			return make_level1()
		2:
			return make_level2()
		3:
			return make_level3()
		4:
			return make_level4()
	return null


## —— 第一折 · 入手 ·《游湖借伞》——
## 按用户 2026-10-04 定案的第一关流程表：许仙固定站位、右手举起持伞；
## 玩家控制白素贞走到他身旁、左手与许仙右手等高时自动接伞（`UmbrellaController`），
## 持伞走到舞台最左边，再向右返回**实际接伞的位置**自动还伞；末了放下左手并入舟。
## 本折学握胸签与双手，同时由「抬手相接」与「走到小青身旁再走回来」教出借还伞的因果。
static func make_level1() -> StageDef:
	var def := StageDef.new()
	def.id = LEVEL1_ID
	def.duration_ms = LEVEL1_DURATION_MS
	def.bpm = LEVEL1_BPM
	def.track_path = ""
	def.act = "游湖借伞"
	def.title = "第一折 · 入手"
	def.roles = ["白素贞", "许仙"]
	def.summary = "许仙立在湖边，右手举伞相候。白素贞走到他面前、左手抬到与他右手齐平——两只手碰到一起便接过伞；随后持伞走到小青身旁，转身走回原地把伞还回许仙右手，再放下手。本折学握胸签与双手。"
	# 本折的手角上限收到 90°（打伞位）。这一折没有「举过头顶」的姿势，收上限同时解决手感：
	# 「抬到 90°」于是变成一个能停住的位置——按住 A 到顶就是 90°，不必掐角度、不会扫过头。
	def.hand_angle_max_rad = LEVEL1_HAND_MAX_RAD
	# 许仙（1 号）右手举到 **90°**（水平前伸）持伞——流程表「开场：许仙固定站位，
	# 右手举起持伞」，角度按用户 2026-10-04 定案由 180° 改为 90°。
	# 这个角度与对齐条件自洽：白素贞要抬进 [75°, 90°] 才算「抬手」到位（见上面的常量），
	# 而接伞要求两手手高差 ≤ 0.04（UmbrellaController.HAND_HEIGHT_TOLERANCE，换算 ≈±7.6°），
	# 两者叠加后「抬手到位」的区间完整包住对齐窗口（82.4°~90°），
	# 所以她抬手到位就一定能接住伞，不会出现「拍点算到位、伞却不换手」。
	# 白素贞（0 号）左手自然垂下；她要自己把左手抬起来才会接伞。
	# 两个挂钩仍由许仙、小青占满，第一关因此不会产生挂起/取回事件（见交接文档第 7 节）。
	def.initial = {
		"controlled": 0,
		"on_stage": [0, 1, 2],
		"hung": {1: 0, 2: 1},
		"positions": {0: [0.50, 0.5], 1: [LEVEL1_XUXIAN_X, 0.5], 2: [LEVEL1_XIAOPING_X, 0.5]},
		"hand_angles": {0: [0.0, 0.0], 1: [1.20, LEVEL1_HAND_MAX_RAD], 2: [0.10, 1.20]},
		"distance": 0.5, "exposure": 1.0, "oil": 1.0,
	}
	# 段落连续覆盖整关、单调递增且不重复（TECH_DESIGN.md 2.2 的校验要求）。
	# 「还伞」段覆盖 22–42 拍：这一段包含走到小青身旁（第 26 拍）与走回还伞（第 40 拍），
	# 本身就是一次完整的往返。「同舟」从第 42 拍起，剩下的是放手收势与收场。
	def.segments = [
		{"name": "出峨眉", "start_ms": def.beat_ms(0), "end_ms": def.beat_ms(3)},
		{"name": "化人形", "start_ms": def.beat_ms(3), "end_ms": def.beat_ms(7)},
		{"name": "游湖", "start_ms": def.beat_ms(7), "end_ms": def.beat_ms(12)},
		{"name": "借伞", "start_ms": def.beat_ms(12), "end_ms": def.beat_ms(22)},
		{"name": "还伞", "start_ms": def.beat_ms(22), "end_ms": def.beat_ms(42)},
		{"name": "同舟", "start_ms": def.beat_ms(42), "end_ms": def.duration_ms},
	]
	def.cues = make_level1_cues(def)
	return def


## 第一关关键动作表。落点全部取整拍，方便与重音对齐核对。
## 每条都在落点**前**有可读线索（hint_lead_ms），满足「落点前获得提示数据」。
##
## 提示提前量按动作**需要多少时间**分两档（用户 2026-10-04 定案）：
##   原地动作（蹲下 / 站起 / 抬手 / 接伞 / 放手）→ 1 s。抬一下手、按一下键就能到位。
##   长距离移动（向左走 / 走到小青身旁 / 走回还伞）→ 3 s。
## 起因：这几段移动各要走 0.5~0.55 个舞台宽（960~1060 画布像素，拖动是 1:1 映射），
## 正常拖速 450~600 px/s 下需要 1.6~2.4 s，再加反应时间。原来一律按 1 s 给，
## 玩家只在最后 1 秒才看到提示，实测「根本来不及向右走」。
##
## segment 字段指向所在段落名，供按段汇总合拍度与低合拍补救使用。
##
## 本条流程里的位置关系（用户 2026-10-05 修订：折返点改为**小青身旁**，后半段铺开到第 48 拍）：
##   游湖（第 8 拍）  白素贞在 x=0.5 向左走，学会用胸签横移
##   借伞（第 14 拍） 左手抬到 90°（打伞位），与许仙举着的右手齐平
##   接伞（第 16 拍） 走进交接窗口（两只手相接的那一段）+ 手高齐平 → 伞转到白素贞左手
##   向右走（第 26 拍）接到伞后向右走，走到**小青身旁**（不必走到舞台最右端）
##   还伞（第 40 拍） 转身走回（拖动方向一变自动翻面），走回交接窗口就把伞还回许仙右手
##   同舟（第 48 拍） 放下已空的左手收势
static func make_level1_cues(def: StageDef) -> Array:
	# 交接窗口（白素贞接地点 x）：与 UmbrellaController 的判据同一处来源，
	# 因此「拍点说该到位了」与「控制器真的换手」不会漂开。
	var join: Vector2 = UmbrellaController.join_window_x(LEVEL1_XUXIAN_X)
	var cues: Array = [
		# 第 2 拍：先蹲下（stance 落到接近 1.0），为第 4 拍的站起做准备
		CueScript.make("l1_c0_crouch", def.beat_ms(2), CueScript.ACTION_CROUCH, 0,
			{"key": "stance", "min": 0.85, "max": 1.0}, 250, "crouch"),
		# 重音（第 4 拍）：站起。stance 0.0 = 完全站立，因此「站起」的到位范围是接近 0，
		# 而不是 0.7-1.0（那是蹲下方向，写成后者会让蹲到底反而被判成站起）。
		CueScript.make("l1_c1_stand", def.beat_ms(4), CueScript.ACTION_STAND_UP, 0,
			{"key": "stance", "min": 0.0, "max": 0.05}, 250, "stand_up"),
		# 第 8 拍：向左走向许仙（他从 x=0.13 起就站在那里，右手一直举着）。
		# 这一条虽是移动，但只需走 0.15 个舞台宽；仍按移动档给 3 s 提前量，
		# 让「移动 = 3 s」这条规则只有一条、不必按距离分档（线索早出现无害：
		# 提示一次只显示最靠前的那条未完成落点，前面的没做完就不会轮到它）。
		CueScript.make("l1_c2_move_left", def.beat_ms(8), CueScript.ACTION_MOVE_LEFT, 0,
			{"key": "x", "min": LEVEL1_APPROACH_MIN, "max": LEVEL1_APPROACH_MAX}, 250,
			"move_left", LEVEL1_MOVE_HINT_LEAD_MS),
		# 第 14 拍：把左手抬到打伞位（90°），与许仙举着的右手齐平。
		# 到位区间见 LEVEL1_UMBRELLA_RAISE_*：它完整包住接伞的手高窗口（82.4°~90°），
		# 因此「抬手」这条落点成立时手高就已经齐平。
		CueScript.make("l1_c3_hand_raise", def.beat_ms(14), CueScript.ACTION_HAND_RAISE, 0,
			{"key": "angle", "min": LEVEL1_UMBRELLA_RAISE_MIN_RAD,
				"max": LEVEL1_UMBRELLA_RAISE_MAX_RAD},
			250, "hand_raise"),
		# 重音（第 16 拍）：伞在**两只手相接**的那一刻换手（走进交接窗口 + 手高齐平）。
		# 目标带就是交接窗口本身（约 0.176~0.296）：她站在许仙右侧、不必贴到他身上，
		# 更不必穿过他。落点在这里接棒：玩家提前走进窗口、或补救时再走进去，
		# 都由这一条如实记下偏移。物理上的伞早在两手相接时就换手了
		# （PRD 第 5.1 节：动作照常发生），本落点只判拍。
		CueScript.make("l1_c4_take_umbrella", def.beat_ms(16), CueScript.ACTION_UMBRELLA_TAKE,
			UmbrellaController.BAISUZHEN_ID,   # 事件上报「接手的人」；写错会被判定直接跳过
			{"key": "x", "min": join.x, "max": join.y}, 250, "umbrella_take"),
		# 重音（第 26 拍）：接到伞后向右走，走到**小青身旁**（她在 x=0.86，整关不动）。
		# 用户 2026-10-05 定案：原先要求走到舞台最右端（x≥0.95），实测太远、也没必要。
		# 目标带 [TURN_POINT_X, 0.84]：下界直接取控制器的 `TURN_POINT_X`（同源，见上面的注释），
		# 上界 0.84 让白素贞停在小青左侧、不至于画面上叠在一起。
		# **必须与交接窗口（0.176~0.296）不重叠**，否则这一步会先经过交接窗口、
		# 被还伞判定抢走伞（还伞要求已到过折返点，顺序一颠倒这一趟就白走了）。
		#
		# 落点是**第 26 拍**：接伞（第 16 拍）之后留 10 拍 = 6.25 s。这一趟走 0.55 个舞台宽
		# ≈ 1060 画布像素，正常拖速下只要 1.6~2 s；多出来的时间是给玩家从容走位、按鼓点踩点的
		# （用户 2026-10-05 定案「动作铺开到 31 s」——原先挤在 10~19 s 做完，之后 16 s 无事可做）。
		#
		# `cue_id` 必须与第 8 拍的 `l1_c2_move_left` **不同**（动作也相反）：
		# 两条是两次独立的漏做机会。补救系统按 `cue_id` 去重（同一 cue 不能重复触发
		# 自己的窗口），共用一个 id 会让这一条漏做开出两个窗口——实测就是这样多出
		# 第 9 个 remedy_open 的。
		CueScript.make("l1_c5_move_to_xiaoping", def.beat_ms(LEVEL1_TURN_BEAT),
			CueScript.ACTION_MOVE_RIGHT, 0,
			{"key": "x", "min": LEVEL1_TURN_MIN, "max": LEVEL1_TURN_MAX}, 250,
			"move_right", LEVEL1_MOVE_HINT_LEAD_MS),
		# 重音（第 40 拍）：转身向左走回许仙身旁（影人只有正反两面，拖动方向一变
		# 就自动翻面，不另开一条「转身」落点），走回交接窗口就把伞还回他右手。
		# 目标带与接伞同一段窗口：**还伞遵循同样的判据**（用户定案）。
		# 从折返点（约 0.80）走回交接窗口（0.296）约 0.50 个舞台宽 ≈ 960 px，
		# 与「走到小青身旁」隔 14 拍 = 8.75 s，同样是「够用且留有余裕」。
		#
		# ⚠️ `target_object` 必须是**许仙**，不是白素贞：交接事件上报的 `object_id` 是
		# 「接手的那个人」（见 UmbrellaController._emit 与交接文档 §5）——接伞记白素贞、
		# 还伞记许仙。判定时 `_register_action` 会拿 `target_object != object_id` 直接跳过，
		# 所以这里写 0 会让这条落点**永远判不到**：玩家把伞还回去也拿不到命中，
		# 窗一过就被判「完全没做」并开出补救窗口。实测踩到过（原先误记成「测试台的时序问题」）。
		CueScript.make("l1_c6_return_umbrella", def.beat_ms(LEVEL1_RETURN_BEAT),
			CueScript.ACTION_UMBRELLA_RETURN, UmbrellaController.XUXIAN_ID,
			{"key": "x", "min": join.x, "max": join.y}, 250,
			"umbrella_return", LEVEL1_MOVE_HINT_LEAD_MS),
		# 第 48 拍：放下已经空掉的左手收势（不要求重新抬手，也不要求转身）。
		# 原地动作，线索仍按默认 1 s 提前。放在关卡收尾前 5 s，让整折以一次「落手」收住。
		CueScript.make("l1_c7_hand_lower", def.beat_ms(LEVEL1_LOWER_BEAT),
			CueScript.ACTION_HAND_LOWER, 0,
			{"key": "angle", "min": HAND_LOWER_MIN_RAD, "max": HAND_LOWER_MAX_RAD}, 250, "hand_lower"),
	]
	# 标注所属段落
	var segment_of: Dictionary = {
		"l1_c0_crouch": "出峨眉",
		"l1_c1_stand": "化人形",
		"l1_c2_move_left": "游湖",
		"l1_c3_hand_raise": "借伞",
		"l1_c4_take_umbrella": "借伞",
		# 「走到小青身旁」归「还伞」段：还伞段从第 22 拍起，正是这一段的开头；
		# 语义上也如此——还伞段就是「拿着伞走一趟、再走回来还给他」的完整往返。
		# （段界口径是 `start ≤ t < end`，见 test_level1_runtime 的段落归属校验。）
		"l1_c5_move_to_xiaoping": "还伞",
		"l1_c6_return_umbrella": "还伞",
		# 放手收势归「同舟」段：还伞已在第 40 拍完成，第 48 拍是入舟后的收势。
		"l1_c7_hand_lower": "同舟",
	}
	for cue in cues:
		cue["segment"] = str(segment_of.get(str(cue.get("cue_id", "")), ""))
	return cues


## —— 第二折 · 双人 ·《游湖同舟》——
## 小青已在岸边候场（挂在钩上），白素贞登舟；雨来，白素贞挂起撑伞，小青接桨同框。
## 本折练「签不够用时的挂起与换签」：先挂起当前影人，再取回另一人。
##
## ⚠️ 布景必须**留出一个空挂钩**：开局若两钩都满，`hook_current()` 找不到空位必然失败，
## 而 `take_back` 又要求「当前无人受控」，玩家会卡死在原地。因此本折只让两个影人登场。
static func make_level2() -> StageDef:
	var def := StageDef.new()
	def.id = 2
	def.duration_ms = LEVEL2_DURATION_MS
	def.bpm = LEVEL1_BPM
	def.track_path = ""
	def.act = "游湖同舟"
	def.title = "第二折 · 双人"
	def.roles = ["白素贞", "小青"]
	def.summary = "白素贞登舟，小青岸边候场。雨来时把当前影人挂起、再取回另一人，一人保持姿势、一人接手同框。本折学挂起与取回。"
	def.initial = {
		"controlled": 0,
		"on_stage": [0, 1],
		"hung": {1: 0},
		"positions": {0: [0.30, 0.5], 1: [0.72, 0.5]},
		"hand_angles": {1: [1.35, 0.05]},
		"distance": 0.5, "exposure": 1.0, "oil": 1.0,
	}
	def.segments = [
		{"name": "候场", "start_ms": def.beat_ms(0), "end_ms": def.beat_ms(6)},
		{"name": "登舟", "start_ms": def.beat_ms(6), "end_ms": def.beat_ms(12)},
		{"name": "留影", "start_ms": def.beat_ms(12), "end_ms": def.beat_ms(20)},
		{"name": "接桨", "start_ms": def.beat_ms(20), "end_ms": def.beat_ms(26)},
		{"name": "同框", "start_ms": def.beat_ms(26), "end_ms": def.beat_ms(42)},
		{"name": "收桨", "start_ms": def.beat_ms(42), "end_ms": def.duration_ms},
	]
	def.cues = make_level2_cues(def)
	return def


## 第二关关键动作表。除登舟一步外，全部以 `-1`（当前受控影人）为目标：
## 取回之后「谁受控」由玩家的操作决定，写死编号会让后面的构图落点必然错配。
static func make_level2_cues(def: StageDef) -> Array:
	var cues: Array = [
		# 第 6 拍：白素贞向右登舟
		CueScript.make("l2_c0_move_right", def.beat_ms(6), CueScript.ACTION_MOVE_RIGHT, -1,
			{"key": "x", "min": 0.55, "max": 1.0}, 250, "move_right"),
		# 重音（第 12 拍）：挂起当前影人（空格）——白素贞留在舟上撑伞
		CueScript.make("l2_c1_hook", def.beat_ms(12), CueScript.ACTION_HOOK, -1,
			{}, 250, "hook"),
		# 第 20 拍：取回挂起的影人（先点选，再按空格）——小青接桨
		CueScript.make("l2_c2_take_back", def.beat_ms(20), CueScript.ACTION_TAKE_BACK, -1,
			{}, 250, "take_back"),
		# 第 26 拍：向左移，与仍挂着的白素贞同框
		CueScript.make("l2_c3_move_left", def.beat_ms(26), CueScript.ACTION_MOVE_LEFT, -1,
			{"key": "x", "min": 0.0, "max": 0.45}, 250, "move_left"),
		# 第 34 拍：抬手（举桨）
		CueScript.make("l2_c4_hand_raise", def.beat_ms(34), CueScript.ACTION_HAND_RAISE, -1,
			{"key": "angle", "min": HAND_OVERHEAD_MIN_RAD, "max": HAND_OVERHEAD_MAX_RAD},
			250, "hand_raise"),
		# 重音（第 42 拍）：回到白素贞身旁，组成同框画面
		CueScript.make("l2_c5_reach_pair", def.beat_ms(42), CueScript.ACTION_REACH, -1,
			{"key": "x", "min": 0.47, "max": 0.58}, 250, "reach_pair"),
		# 第 56 拍：落桨收势
		CueScript.make("l2_c6_hand_lower", def.beat_ms(56), CueScript.ACTION_HAND_LOWER, -1,
			{"key": "angle", "min": HAND_LOWER_MIN_RAD, "max": HAND_LOWER_MAX_RAD}, 250, "hand_lower"),
	]
	var segment_of: Dictionary = {
		"l2_c0_move_right": "登舟",
		"l2_c1_hook": "留影",
		"l2_c2_take_back": "接桨",
		"l2_c3_move_left": "同框",
		"l2_c4_hand_raise": "同框",
		"l2_c5_reach_pair": "同框",
		"l2_c6_hand_lower": "收桨",
	}
	for cue in cues:
		cue["segment"] = str(segment_of.get(str(cue.get("cue_id", "")), ""))
	return cues


## —— 第三折 · 灯位 ·《盗仙草》——
## 白素贞夜上昆仑盗仙草：灯远离、全场影子缩小穿过云雾；灯推近、影子放大在仙草前亮相。
## 本折练「滚轮推拉灯使所有在场影子同步缩放」，落点全部读 LampState.distance。
static func make_level3() -> StageDef:
	var def := StageDef.new()
	def.id = 3
	def.duration_ms = LEVEL3_DURATION_MS
	def.bpm = LEVEL1_BPM
	def.track_path = ""
	def.act = "盗仙草"
	def.title = "第三折 · 灯位"
	def.roles = ["白素贞"]
	def.summary = "白素贞夜上昆仑。灯推远，全场影子一并缩小穿过云雾；灯拉近，影子放大在仙草前亮相。本折学滚轮推拉灯位。"
	def.initial = {
		"controlled": 0,
		"on_stage": [0, 1, 2],
		"hung": {1: 0, 2: 1},
		"positions": {0: [0.50, 0.5], 1: [0.12, 0.5], 2: [0.88, 0.5]},
		"hand_angles": {1: [0.90, 0.20], 2: [0.20, 0.90]},
		"distance": 0.5, "exposure": 1.0, "oil": 1.0,
	}
	def.segments = [
		{"name": "夜行", "start_ms": def.beat_ms(0), "end_ms": def.beat_ms(8)},
		{"name": "隐现", "start_ms": def.beat_ms(8), "end_ms": def.beat_ms(20)},
		{"name": "采药", "start_ms": def.beat_ms(20), "end_ms": def.beat_ms(38)},
		{"name": "云雾", "start_ms": def.beat_ms(38), "end_ms": def.beat_ms(50)},
		{"name": "亮相", "start_ms": def.beat_ms(50), "end_ms": def.beat_ms(60)},
		{"name": "归去", "start_ms": def.beat_ms(60), "end_ms": def.duration_ms},
	]
	def.cues = make_level3_cues(def)
	return def


static func make_level3_cues(def: StageDef) -> Array:
	var cues: Array = [
		# 第 8 拍：向下滚轮，灯远离，全场影子缩小没入云雾
		CueScript.make("l3_c0_lamp_far", def.beat_ms(8), CueScript.ACTION_LAMP_DISTANCE, -1,
			{"key": "distance", "min": 0.0, "max": 0.25}, 250, "lamp_far"),
		# 重音（第 20 拍）：向上滚轮，灯推近，影子放大
		CueScript.make("l3_c1_lamp_near", def.beat_ms(20), CueScript.ACTION_LAMP_DISTANCE, -1,
			{"key": "distance", "min": 0.80, "max": 1.0}, 250, "lamp_near"),
		# 第 28 拍：抬手采仙草
		CueScript.make("l3_c2_hand_raise", def.beat_ms(28), CueScript.ACTION_HAND_RAISE, -1,
			{"key": "angle", "min": HAND_OVERHEAD_MIN_RAD, "max": HAND_OVERHEAD_MAX_RAD},
			250, "hand_raise"),
		# 第 38 拍：云雾再起，灯又推远、影子收小
		CueScript.make("l3_c3_lamp_far", def.beat_ms(38), CueScript.ACTION_LAMP_DISTANCE, -1,
			{"key": "distance", "min": 0.0, "max": 0.25}, 250, "lamp_far"),
		# 重音（第 50 拍）：灯再推近，完整亮相
		CueScript.make("l3_c4_lamp_near", def.beat_ms(50), CueScript.ACTION_LAMP_DISTANCE, -1,
			{"key": "distance", "min": 0.80, "max": 1.0}, 250, "lamp_near"),
		# 第 60 拍：向左退去
		CueScript.make("l3_c5_move_left", def.beat_ms(60), CueScript.ACTION_MOVE_LEFT, -1,
			{"key": "x", "min": 0.0, "max": 0.40}, 250, "move_left"),
		# 重音（第 68 拍）：回到中位收势
		CueScript.make("l3_c6_reach_center", def.beat_ms(68), CueScript.ACTION_REACH, -1,
			{"key": "x", "min": 0.47, "max": 0.53}, 250, "reach_center"),
	]
	var segment_of: Dictionary = {
		"l3_c0_lamp_far": "隐现",
		"l3_c1_lamp_near": "采药",
		"l3_c2_hand_raise": "采药",
		"l3_c3_lamp_far": "云雾",
		"l3_c4_lamp_near": "亮相",
		"l3_c5_move_left": "归去",
		"l3_c6_reach_center": "归去",
	}
	for cue in cues:
		cue["segment"] = str(segment_of.get(str(cue.get("cue_id", "")), ""))
	return cues


## —— 第四折 · 显隐 ·《端阳现身》——
## 端阳佳节，许仙劝饮雄黄酒。白素贞换头现出真身，倾灯由低显露逐步推到完整亮相，复又换回人形。
## 本折练「换头 + 倾灯控制影子显露」。初始显露度从低起步（PRD 第 6 节）。
static func make_level4() -> StageDef:
	var def := StageDef.new()
	def.id = 4
	def.duration_ms = LEVEL4_DURATION_MS
	def.bpm = LEVEL1_BPM
	def.track_path = ""
	def.act = "端阳现身"
	def.title = "第四折 · 显隐"
	def.roles = ["白素贞", "许仙"]
	def.summary = "端阳劝酒。白素贞与备用头架换头现出真身，倾灯把幕布上的影子由隐到显、逐步推到完整亮相，末了复还人形。本折学换头与倾灯。"
	def.initial = {
		"controlled": 0,
		"on_stage": [0, 1],
		"hung": {1: 0},
		"positions": {0: [0.72, 0.5], 1: [0.30, 0.5]},
		"hand_angles": {1: [1.50, 0.05]},
		"distance": 0.5, "exposure": 0.15, "oil": 1.0,
	}
	def.segments = [
		{"name": "端阳", "start_ms": def.beat_ms(0), "end_ms": def.beat_ms(8)},
		{"name": "显形", "start_ms": def.beat_ms(8), "end_ms": def.beat_ms(16)},
		{"name": "初显", "start_ms": def.beat_ms(16), "end_ms": def.beat_ms(26)},
		{"name": "举杯", "start_ms": def.beat_ms(26), "end_ms": def.beat_ms(32)},
		{"name": "现形", "start_ms": def.beat_ms(32), "end_ms": def.beat_ms(42)},
		{"name": "惊变", "start_ms": def.beat_ms(42), "end_ms": def.beat_ms(52)},
		{"name": "复形", "start_ms": def.beat_ms(52), "end_ms": def.beat_ms(70)},
		{"name": "收势", "start_ms": def.beat_ms(70), "end_ms": def.duration_ms},
	]
	def.cues = make_level4_cues(def)
	return def


static func make_level4_cues(def: StageDef) -> Array:
	var cues: Array = [
		# 第 8 拍：换头，现出真身之头（按 1/2/3 或点备用头架）
		CueScript.make("l4_c0_head_swap", def.beat_ms(8), CueScript.ACTION_HEAD_SWAP, -1,
			{}, 250, "head_swap"),
		# 第 16 拍：倾灯，影子初显
		CueScript.make("l4_c1_exposure_low", def.beat_ms(16), CueScript.ACTION_LAMP_EXPOSURE, -1,
			{"key": "exposure", "min": 0.45, "max": 0.60}, 250, "exposure_up"),
		# 重音（第 26 拍）：继续推高显露
		CueScript.make("l4_c2_exposure_mid", def.beat_ms(26), CueScript.ACTION_LAMP_EXPOSURE, -1,
			{"key": "exposure", "min": 0.75, "max": 0.90}, 250, "exposure_up"),
		# 第 32 拍：抬手（举杯痛饮）
		CueScript.make("l4_c3_hand_raise", def.beat_ms(32), CueScript.ACTION_HAND_RAISE, -1,
			{"key": "angle", "min": HAND_OVERHEAD_MIN_RAD, "max": HAND_OVERHEAD_MAX_RAD},
			250, "hand_raise"),
		# 重音（第 42 拍）：完整亮相
		CueScript.make("l4_c4_exposure_full", def.beat_ms(42), CueScript.ACTION_LAMP_EXPOSURE, -1,
			{"key": "exposure", "min": 0.95, "max": 1.0}, 250, "exposure_up"),
		# 第 52 拍：向左惊走
		CueScript.make("l4_c5_move_left", def.beat_ms(52), CueScript.ACTION_MOVE_LEFT, -1,
			{"key": "x", "min": 0.0, "max": 0.40}, 250, "move_left"),
		# 第 60 拍：再换一头，复还人形
		CueScript.make("l4_c6_head_swap_back", def.beat_ms(60), CueScript.ACTION_HEAD_SWAP, -1,
			{}, 250, "head_swap"),
		# 重音（第 70 拍）：回到中位收势
		CueScript.make("l4_c7_reach_center", def.beat_ms(70), CueScript.ACTION_REACH, -1,
			{"key": "x", "min": 0.47, "max": 0.53}, 250, "reach_center"),
		# 第 78 拍：灯推近，影子放大收束
		CueScript.make("l4_c8_lamp_near", def.beat_ms(78), CueScript.ACTION_LAMP_DISTANCE, -1,
			{"key": "distance", "min": 0.80, "max": 1.0}, 250, "lamp_near"),
	]
	var segment_of: Dictionary = {
		"l4_c0_head_swap": "显形",
		"l4_c1_exposure_low": "初显",
		"l4_c2_exposure_mid": "举杯",
		"l4_c3_hand_raise": "现形",
		"l4_c4_exposure_full": "惊变",
		"l4_c5_move_left": "复形",
		"l4_c6_head_swap_back": "复形",
		"l4_c7_reach_center": "收势",
		"l4_c8_lamp_near": "收势",
	}
	for cue in cues:
		cue["segment"] = str(segment_of.get(str(cue.get("cue_id", "")), ""))
	return cues


func beat_duration_ms() -> float:
	return 60000.0 / maxf(bpm, 1.0)


func beat_ms(beat_index: int) -> int:
	return int(round(float(beat_index) * beat_duration_ms()))


func total_beats() -> int:
	return int(floor(float(duration_ms) / beat_duration_ms()))


## 这一关是不是教学关（前四关）。第 5 关没有常驻教学图标（PRD 第 3、6 节）。
func is_tutorial() -> bool:
	return id >= 1 and id <= LAST_TUTORIAL_LEVEL


## 校验关卡数据。返回问题列表；空列表表示通过。
## 开发构建启动时直接报出关卡与 cue_id，防止静默跳过动作（TECH_DESIGN.md 2.2）。
func validate() -> Array[String]:
	var problems: Array[String] = []
	if id <= 0:
		problems.append("stage %d: id 必须为正整数" % id)
	if duration_ms <= 0:
		problems.append("stage %d: duration_ms 必须为正，实际 %d" % [id, duration_ms])
	if bpm <= 0.0:
		problems.append("stage %d: bpm 必须为正，实际 %s" % [id, str(bpm)])
	var previous_end: int = -1
	for i in segments.size():
		var seg: Dictionary = segments[i]
		var name: String = str(seg.get("name", "?"))
		var start_ms: int = int(seg.get("start_ms", 0))
		var end_ms: int = int(seg.get("end_ms", 0))
		if start_ms < 0 or end_ms > duration_ms:
			problems.append("stage %d 段「%s」超出关卡时长：%d-%d（时长 %d）"
				% [id, name, start_ms, end_ms, duration_ms])
		if end_ms <= start_ms:
			problems.append("stage %d 段「%s」起止不递增：%d-%d" % [id, name, start_ms, end_ms])
		if start_ms < previous_end:
			problems.append("stage %d 段「%s」与上一段重叠：start=%d < 上一段 end=%d"
				% [id, name, start_ms, previous_end])
		previous_end = end_ms
	if not segments.is_empty() and previous_end < duration_ms:
		problems.append("stage %d 段落未覆盖整关：最后一段结束于 %d，时长 %d"
			% [id, previous_end, duration_ms])
	var seen: Dictionary = {}
	for cue in cues:
		var cue_id: String = str(cue.get("cue_id", ""))
		if cue_id.is_empty():
			problems.append("stage %d: 存在空 cue_id" % id)
			continue
		if seen.has(cue_id):
			problems.append("stage %d: cue_id 重复「%s」" % [id, cue_id])
		seen[cue_id] = true
		for p in CueScript.validate(cue):
			problems.append("stage %d: %s" % [id, p])
		var beat_time_ms: int = int(cue.get("beat_time_ms", -1))
		if beat_time_ms < 0 or beat_time_ms > duration_ms:
			problems.append("stage %d cue「%s」落点 %d 不在关卡时长内" % [id, cue_id, beat_time_ms])
		# 前四关重要落点必须给补救留出可见时间（TECH_DESIGN.md 2.2）
		if CueScript.hint_time_ms(cue) >= beat_time_ms and beat_time_ms > 0:
			problems.append("stage %d cue「%s」的线索时间不早于落点" % [id, cue_id])
		# 每条关键动作必须归属一个真实段落，否则按段汇总合拍度会把它漏掉
		var segment_name: String = str(cue.get("segment", ""))
		if segment_name.is_empty():
			problems.append("stage %d cue「%s」缺少 segment 归属" % [id, cue_id])
	# 开演布景：受控影人必须在场，且挂钩槽位不重复
	var on_stage: Array = initial.get("on_stage", [])
	var controlled: int = int(initial.get("controlled", -1))
	if not on_stage.is_empty() and not on_stage.has(controlled):
		problems.append("stage %d 开演布景：受控影人 %d 不在场" % [id, controlled])
	var used_slots: Dictionary = {}
	for puppet_id in initial.get("hung", {}).keys():
		var slot: int = int(initial["hung"][puppet_id])
		if used_slots.has(slot):
			problems.append("stage %d 开演布景：挂钩槽位 %d 被重复占用" % [id, slot])
		used_slots[slot] = true
		if not on_stage.is_empty() and not on_stage.has(int(puppet_id)):
			problems.append("stage %d 开演布景：挂起的影人 %d 不在场" % [id, int(puppet_id)])
	# 本折的手角上限必须落在 PuppetState 的硬边界内，且开演布景不能超出它。
	# 布景由显示端直接写进 PuppetState（不经控制器），所以这里必须查：
	# 否则一个「上限 90°、布景却摆 180°」的关卡会让操控手感与开演姿势自相矛盾。
	if hand_angle_max_rad < PuppetStateScript.HAND_ANGLE_MIN \
			or hand_angle_max_rad > PuppetStateScript.HAND_ANGLE_MAX:
		problems.append("stage %d: hand_angle_max_rad 越界：%s（合法 %s ~ %s）"
			% [id, str(hand_angle_max_rad), str(PuppetStateScript.HAND_ANGLE_MIN),
				str(PuppetStateScript.HAND_ANGLE_MAX)])
	for puppet_id in initial.get("hand_angles", {}).keys():
		var angles: Array = initial["hand_angles"][puppet_id]
		for hand_index in angles.size():
			var angle: float = float(angles[hand_index])
			if angle > hand_angle_max_rad + 1e-9:
				problems.append("stage %d 开演布景：影人 %d 的手角 %s 超过本折上限 %s"
					% [id, int(puppet_id), str(angle), str(hand_angle_max_rad)])
	return problems
