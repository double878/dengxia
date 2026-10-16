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

const LEVEL1_DURATION_MS: int = 35000  ## PRD 第 6 节：第一关固定 35 秒（不延长）
const LEVEL2_DURATION_MS: int = 45000  ## 第二关「双人」
const LEVEL3_DURATION_MS: int = 50000  ## 第三关「灯位」
const LEVEL4_DURATION_MS: int = 55000  ## 第四关「显隐」
const LEVEL1_BPM: float = 96.0  ## PRD 第 10 节：原型 BPM 初始考虑 90-100
const LEVEL1_ID: int = 1
const LAST_TUTORIAL_LEVEL: int = 4  ## 1–4 关为教学关（前四关可出现教学图标）
## —— 手角口径与两档「抬手」到位区间（弧度）——
## 手角以「手臂自然垂下」为 0、π/2 为水平前伸、π 为举过头顶（见 PuppetState）。
##
## 「举过头顶」档：第 2~4 关的抬手落点（举桨 / 采仙草 / 举杯）用它。
## 名字里刻意不带关卡号——它被 L2/L3/L4 共用；L1 的抬手是下面的「打伞位」，不是举过头顶。
const HAND_OVERHEAD_MIN_RAD: float = PI * 0.75  ## 135°
const HAND_OVERHEAD_MAX_RAD: float = PI  ## 180°
## —— 第一关影人落地线（用户 2026-10-15 定案：整关下移 95px）——
## 「影人位置最低水平线」原本是三具影人共用的一条接地线；**2026-10-15 起分两条**：
##   许仙 = `LEVEL1_GROUND_Y`（635px）；小青与白素贞 = `LEVEL1_GROUND_Y_LADIES`（645px，见下）。
## 原为归一化 0.5（540px），整关下移 95px → **635px**。以画布归一化表达（÷1080），
## 与 C 侧景物位移同一口径（`c_scenery_def.gd` 的 `LEVEL1_Y_DOWN` 也是 ÷1080）。
##
## 与景物的纵向关系（按 C 侧第一关现场实测值）：
##   景物基准低线（柳树底缘 = 拱桥底缘）**662.8px** → 影人脚比它**高 27.8px**（两位娘子下移后 17.8px）
##   （读作「人略后于景物的落地基准」，不是浮空）；
##   幕布下沿 680px 是硬边界 → 许仙脚下余 **45px**、两位娘子余 **35px**，仍可继续下移。
## ⚠️ 662.8px 只在 `fix-lv1-scenery-down95` 分支上（`LEVEL1_Y_DOWN = 90/1080`）；
## 未合并到该改动的基线上景物底缘仍是 572.8px，那时影人脚会落到景物基准线**以下 62px**。
const LEVEL1_GROUND_DOWN: float = 95.0 / 1080.0  ## ≈ 0.087963（95px，归一化）
const LEVEL1_GROUND_Y: float = 0.5 + LEVEL1_GROUND_DOWN  ## ≈ 0.587963 → 635px
## —— 小青与白素贞专用落地线（用户 2026-10-15：「小青和白素贞的人物纵轴下移 5px」）——
## 在整关落地线 635px 之上**再单独下移**：先 5px（640px），用户随后又说「再下移 5px」→
## **累计 10px → 645px**；许仙不参与（他仍站在桥头 635px）。
## 写法沿用「0.5 + N/1080」的派生式，只把 95 换成 105，便于一眼看出与主线的关系。
##
## ⚠️ 这两人的纵向一变，**不影响任何判定**：接伞/还伞的手高判据 `UmbrellaController.hand_height()`
##   只用「手角 + 站蹲」，**不含 `stage_pos.y`**（那是 A 内部的相对口径，见其注释）。
##   因此本改动只挪画面上的纵向落点，判定与落点带一律不动——无测试需要同步。
const LEVEL1_GROUND_DOWN_LADIES: float = 105.0 / 1080.0  ## ≈ 0.097222（95 + 10px，归一化）
const LEVEL1_GROUND_Y_LADIES: float = 0.5 + LEVEL1_GROUND_DOWN_LADIES  ## ≈ 0.597222 → 645px
## —— 第一关「打伞位」与交接窗口 ——
## 许仙固定站在这个 x 上；交接窗口由「两人都抬手到 90°、手在中间相接」推出，
## 因此与 `UmbrellaController.join_window_x()` 是同一处来源——落点数据与运行时判据不会漂开。
##
## 🔴 2026-10-16（第三轮）用户定案：**许仙站桥上**——「许仙初始位置站桥上」。
##   从桥头 0.5285 再向右挪上桥面：取 **0.58**（= 桥面上约 99px），该处桥面高
##   `StageWalkPath.height_at(0.58)` = **0.5441（588px）**，比桥外落地线（635px）高出
##   47px——画面读作「立在桥面上」，且离桥头不远、构图变化最小。
##
## 「桥头」= 拱桥的**左端**，这是**可算的判据线**（不是观感）。C 侧原文亦以此为准
## （`c_scenery_def.gd` 的桥锚点注里写着「**桥头左移**，使桥能够完整展现在幕布中」，即指左端）：
##   桥贴图 1842×715 × `TEXTURE_SCALE_PX`(0.42) = 宽 **773.64px**；
##   锚点 = 桥基中心 `LEVEL1_BRIDGE_CENTER_X`(0.73) × 1920 = 1401.6px
##   ⇒ 桥左端 = 1401.6 − 773.64/2 = **1014.78px** → 归一化 **0.52853**。
##   桥跨（脚点跟随桥拱的区间）= `StageWalkPath.is_on_deck()`：px ∈ (0, 1842)。
##
## ⚠️ 交接窗口随他整体移动（与 `UmbrellaController.join_window_x()` 同源，判定逻辑一行未改）：
##   0.176~0.296（x=0.13 时代）→ 0.546~0.666（x=0.50）→ 0.5745~0.6945（x=0.5285，加号口径）
##   → 0.3803~0.5003（x=0.5285 减号 + 托顶 140°）
##   → **0.4318~0.5518**（x=0.58；窗口右半已搭在桥跨上——白素贞走入窗口时脚点
##   会经 `_apply_walk_height` 自然贴上桥面拱起，「移动路线沿桥面」由此成立）。
## 公式恒为：许仙 x − `UmbrellaController.CONTACT_REACH_X`（≈0.0882）± `HAND_JOIN_TOLERANCE`(0.06)，
## **那个减号就是方向**，跟着两人的左右关系一起翻。
## 🔴 两人的伸出量**不相等**（许仙 0.0390 / 白素贞 0.0492），别再按「一人一半」去推。
const LEVEL1_XUXIAN_X: float = 0.58
## 许仙的开局脚点 y：**桥面在 0.58 处的高度**（`height_at`，588px）。
## 🔴 他站在桥上，落地线（`LEVEL1_GROUND_Y` 635px）只作**桥外**兜底——运行时
## `set_walk_path()` 会把桥跨内的脚点改写为桥面高度，但**数据里的初值也要一致**
## （DirectorTestBench 等不走路径的测试台直接读初值）。该值**不是手写圆整值**：
## 取 `StageWalkPath.height_at(LEVEL1_XUXIAN_X, LEVEL1_GROUND_Y)` 的全精度读数
## 0.544055307（= 587.58px），由 `test_level1_cues` 的「桥上初值与 height_at
## 同源」断言与 `run_stage_walk` 的 `is_equal_approx` 断言双钉，桥面数据一改立刻红。
const LEVEL1_XUXIAN_Y: float = 0.544055307
## 小青的开局站位（整关不动）。白素贞接到伞后要走到她**身旁**，关卡到此收尾。
##
## ✅ 2026-10-16 定案（用户当天两次确认：「可以这个位置」／「小青和白素贞站树下」）：**0.26**。
##   0.26 = 499.2px，落在柳树绘制矩形（96~507.7px）的**右缘**，读作「站在柳树下」；
##   影身半宽 ≈24px → 左缘 475.2px，与柳枝略有重叠——用户要的就是这个「树下」的位置。
##   ⚠️ 柳树右缘随树高变（= 96 + 1436 × `LEVEL1_WILLOW_SCALE`，C 侧一天内改过四轮），
##   本值只钉「贴着树站」这一意图；要重算判据线时看 `LEVEL1_WILLOW_SCALE`。
## ⚠️ 三人从左到右 = **小青（0.26）/ 白素贞（0.32）/ 许仙（0.58，桥上）**：
##   小青在最左（贴树），白素贞在她**靠许仙的那一侧**。
const LEVEL1_XIAOPING_X: float = 0.26
## 白素贞的开局站位。开场她与小青并肩，**站在小青靠许仙的那一侧**（用户 2026-10-16 原话）。
##
## ✅ 2026-10-16 定案：**0.32**（= 614.4px）。两条约束同时定它：
##   ① 必须站在交接窗口（0.4318~0.5518）之**外**，否则一开局就满足接伞条件；
##   ② 必须留出一段**真正走得到**的距离，这一段就是「走向许仙借伞」这一拍的内容。
##   取 0.32 = 窗口下沿 0.4318 之左 0.1118（≈215px）——去程**向右**入窗；
##   回程从窗口里**向左**走回小青身旁（x ≤ 0.32 = 归位阈值），恰好走回她本来的站位。
## ⚠️ 与小青（0.26）间距 0.06 = 115px，并肩不叠（两具影身各宽约 0.026 个幕宽）。
##
## ⚠️ 朝向：她在小青**右侧**，故朝**左**看小青（= 显式 **-1**）；小青朝右（= 默认 +1，**不入**表）。
##   两人由此相对而立；许仙朝左（-1）面对两位娘子。
##   ——「左右关系一互换、朝向必须整体反号」的又一次实例（见 `make_level1()` 的 `facing`）。
const LEVEL1_BAISUZHEN_X: float = 0.32
## —— 小青的开局亮相姿势（2026-10-16 最终定案 = 用户 16:08 截图，标签「elbow100_Rdown」）——
## 用户连续多轮收敛：「不要镜像」→「右手放下来」→「左手肘弯 100°」→「靠柳树那侧高举」
## → **16:08 截图定案**：高举臂画在**画面右（白素贞侧）**、斜向右上 ~45°、肘内角 100°、
## 袖口收在头顶右上方；另一臂（画面左 = 柳树侧）自然垂下。
## 该截图与姿势试穿探针的 **B 变体**（下标 0 高举 + 肘弯、下标 1 放下）实拍一致，
## 故数据取 B 的参数；此前「柳树侧高举」的读法**作废**。
##
## 🔴 **下标↔画面方位**（`PlaceholderPuppet.arm_direction()` 口径 + 正式入口实拍核对）：
##   小青 facing = +1、素材 `reference_facing` = −1 ⇒ mirror = −1 ⇒ 整具影人连双臂一起翻面：
##   **下标 1（右手）画在画面左 = 柳树侧**，**下标 0（左手）画在画面右 = 白素贞侧**。
##   ⚠️ 这两个下标**不随朝向改**：朝向翻的是整具影人（含双臂），与「左手/右手」无关。
##
## 角度口径见 `UmbrellaController.hand_height()`：0 = 自然垂下、π/2 = 水平前伸、π = 举过头顶。
##   高举 160° 落在「举过头顶」档（`HAND_OVERHEAD_MIN_RAD` = 135°）内，读作亮相而非直挺挺的 180°。
##   另一侧 10° ≈ 自然垂下（略前，避免与躯干重叠）。
##
## 肘弯通道（2026-10-16 加）：`PlaceholderPuppet.hand_bend` 给**前臂再转的屏幕角**，
##   肘内角 = 180° − |bend|。用户参考图高举臂实测肘内角 ≈ **100°** ⇒ bend = ±80°；
##   符号经双方向实拍比对定案：下标 0 取**正号** = 前臂折向头顶右上方（用户 16:08 截图），
##   负号会把袖口送向身后（不对）。只作用在下标 0（`initial["elbow_bends"]`）。
## ⚠️ 高举的 160° **超过本折的 `hand_angle_max_rad`（90°，打伞位）**，是有意的：那条上限是
##   「玩家把手抬到 90° 能停住」的**手感装置**，只约束玩家操控的那一具（见 `validate()` 注）；
##   小青整关静止、不参与接伞（`UmbrellaController._hands_meet()` 只读白素贞与许仙），
##   她的开局姿势因此可以越过它，但仍受 `PuppetState.HAND_ANGLE_MAX`（180°）硬边界约束。
const LEVEL1_XIAOPING_HAND_DOWN_RAD: float = PI * 10.0 / 180.0  ## 自然垂下略前（右手=柳树侧，下标 1）
const LEVEL1_XIAOPING_HAND_RAISED_RAD: float = PI * 160.0 / 180.0  ## 高举过头（左手=白素贞侧，下标 0）
## 高举臂的前臂偏折量：肘内角 = 180° − 本值 = **100°**（用户定案）。
## 落数据时按下标 0 取**正号**（见上注：正号 = 袖口折向头顶右上方）。
const LEVEL1_XIAOPING_ELBOW_BEND_RAD: float = PI * 80.0 / 180.0
## 「回到小青身旁」落点的目标带（2026-10-16 起它就是**本关的完成条件**）。
## **上界直接取控制器的 `TURN_POINT_X`**，不另写一个数：控制器置起「已归位」的条件就是
## `x ≤ TURN_POINT_X`。落点带若写得比它**低**，会出现最坏的一种错配：
## **拍点判命中、控制器却没判归位**，这一趟就白走。
## ✅ 2026-10-16 定案（许仙回桥头）后 = **[0.28, 0.32]**：
##   上界 0.32 = `TURN_POINT_X`（= 小青 0.26 + 0.06，恰是白素贞的开局站位）；
##   下界 0.28 = 小青 + 0.02——再往左两具影身就明显重叠（已接受，读作「并到她身边」）。
## ⚠️ 可用空间很窄：小青 0.26 到交接窗口下沿（0.4318）只有 0.17 个幕宽，故本带也只能有 0.04 宽。
##   两带**不重叠**（0.32 < 0.4318）——这正是「刚接到伞不可能已判归位」的几何保证。
const LEVEL1_TURN_MIN: float = LEVEL1_XIAOPING_X + 0.02
const LEVEL1_TURN_MAX: float = UmbrellaController.TURN_POINT_X
## 「走向许仙」落点的目标带 = **整条交接窗口**（0.4318~0.5518）。
## 她 0.32 起步，**向右**走进窗口即「确实朝许仙走过去了」；停在窗口里也算。
## 写成与 `join_window_x()` 同源的派生式（而不是硬写小数），判定与落点永远一处来源。
## 🔴 那个**减号**必须与 `UmbrellaController.join_window_x()` 一致（白素贞从许仙**左**边来）；
## 两边一旦错开，拍点与控制器就会各说各话。`test_level1_cues` 用等式把两者钉在一起。
## ⚠️ 伸出量之和取 `CONTACT_REACH_X`（许仙 0.0390 + 白素贞 0.0492），**不是**「一人一半」：
## 许仙把伞托在头顶，水平投影短于她。
const LEVEL1_APPROACH_MIN: float = (
	LEVEL1_XUXIAN_X - UmbrellaController.CONTACT_REACH_X - UmbrellaController.HAND_JOIN_TOLERANCE
)
const LEVEL1_APPROACH_MAX: float = (
	LEVEL1_XUXIAN_X - UmbrellaController.CONTACT_REACH_X + UmbrellaController.HAND_JOIN_TOLERANCE
)
## 移动落点的线索提前量（毫秒）。这一折本来有两次长距离横移：接到伞后走到小青身旁
## （约 0.55 个舞台宽 ≈ 1060 画布像素）、再走回许仙身旁（约 0.50 ≈ 960 px），
## 按正常拖速 450~600 px/s 各需 1.6~2.4 s，再加反应时间。原地动作仍用默认 1 s。
## ⚠️ 2026-10-16 定案后两段都短得多（去程约 0.06 个幕宽 ≈ 116px 才进窗，
## 回程约 0.10~0.16 ≈ 192~307px），**仍保留本档**（不按距离分档）：
## 提前量多一点无害，改它要连带复核整条提示时刻表。
const LEVEL1_MOVE_HINT_LEAD_MS: int = MOVE_BUDGET_MS
## 后半段三条落点的拍号（用户 2026-10-05 定案「铺开到 31 s」）。
## 改动前：接伞后 2.5 s 就要求走到最右端，动作挤在 10~19 s 全部做完，之后 16 s 无事可做。
## 现在把三条落点均匀铺到第 48 拍，每段留 5~6 s（每趟移动本身只需 1.6~1.8 s），
## 玩家可以从容走位、按鼓点踩点，最后留 5 s 收势。
const LEVEL1_TURN_BEAT: int = 26  ## 16250 ms：接伞后 6.25 s，走到小青身旁
const LEVEL1_RETURN_BEAT: int = 40  ## 25000 ms：再 8.75 s 走回交接窗口还伞
## 🔴 历史名：第 48 拍「落手收势」cue（l1_c7_hand_lower）已随 2026-10-16 用户定案
## 「最后白素贞手不用放下」下线，本拍号暂无消费者；保留给将来可能的收势拍复用。
const LEVEL1_LOWER_BEAT: int = 48  ## 30000 ms：原收势拍（已下线）
## 最后一条落点之后留给收势的时间上限（毫秒）。用户 2026-10-05 报「所有动作做完还有约 10 秒
## 没事做」——后半段三条落点因此铺开。⚠️ 收势 cue 下线后本关的收尾改由流程驱动
## （走回小青身旁即收关，见 Act1OperaFlow），「尾部空档」结构断言随之取消；
## 本常量留给其它关卡的结构断言复用。
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
## 用户 2026-10-04 定案：**接伞**时手臂抬到 90° 即可，不必举过头顶。于是白素贞只需抬到 90°；
## 90° = 手臂水平前伸，伞杆从手向上撑起、伞面罩在头顶。
## 🔴 2026-10-16（第二轮，用户参考图定案）**许仙把伞举在头顶**：他右手抬到
## `LEVEL1_XUXIAN_UMBRELLA_RAISE_RAD`（140°、手落在头顶高度）、左臂自然垂下。
##   这与「她抬到 90° 就能接」并不矛盾：伞是**竖持**的，他握在伞杆**上段**、她握**下段**，
##   两人的手本来就不在同一高度上。因此接伞不再拿他的实时手高作参考，而是拿「打伞位」
##   （= 本常量 90°，见 `UmbrellaController.CONTACT_HAND_ANGLE_RAD`）——玩家手感一行未变。
const LEVEL1_HAND_MAX_RAD: float = PI * 0.5  ## 90°，打伞位——现作接伞判据的**下界参考角**
## 许仙开局举伞的角度（手落在头顶上方）。**只约束布景影人**，不是玩家上限：
## 那条 90° 的上限是「按住抬手键到顶能停住」的手感装置，只挂在受控影人身上（见 `validate()`）。
const LEVEL1_XUXIAN_UMBRELLA_RAISE_RAD: float = PI * 140.0 / 180.0
## 第一关抬手（打伞位）的到位区间。下界取 75° 不是随手定的：
## 它必须**完整包住接伞的对齐窗口**，否则会出现「拍点算抬手到位、伞却不换手」的错配。
## 🔴 2026-10-16 用户定案放宽后，对齐窗口 = 「任一只手的手高 ≥ 打伞位 − 容差」
## = 82.4°~180°（上界 = 竖直，她的手角上限已放开到 π）；本区间因此上界取 π。
const LEVEL1_UMBRELLA_RAISE_MIN_RAD: float = PI * 75.0 / 180.0
const LEVEL1_UMBRELLA_RAISE_MAX_RAD: float = PI

var id: int = LEVEL1_ID
var duration_ms: int = LEVEL1_DURATION_MS
var bpm: float = LEVEL1_BPM
## 本折的手角上限（弧度）。默认 = PuppetState.HAND_ANGLE_MAX（180°，举过头顶）。
## 第一关收到 90°：这一折的姿势只有「打伞位」，手臂不需要举过头顶。除了姿势本身，
## 收上限还有一个手感上的作用——它让「抬到 90°」变成一个**能停住的位置**：
## 按住抬手键到顶就是 90°，玩家不必掐角度、也不会扫过头（见 LEVEL1_HAND_MAX_RAD）。
## 由 Level1Runtime.setup 交给 PuppetController.hand_angle_max。
var hand_angle_max_rad: float = PI
var track_path: String = ""  ## 正式锣鼓主音轨；B 未交付时保持为空
## 本折的戏名与戏单文案（PRD 第 3、5.1 节：演前戏单说明段落顺序、出场角色与表演目标，
## 不含逐键操作与精确拍号）。显示端只读，不参与判定。
var act: String = ""  ## 折名，如「游湖借伞」
var title: String = ""  ## 关名，如「第一折 · 入手」
var roles: Array[String] = []  ## 本折出场角色
var summary: String = ""  ## 戏单简介
## 开演布景（由显示端读取，不参与判定）：
##   "controlled": int                 起始受控影人编号
##   "on_stage": [int]                 在场的影人编号（不在列表里的未登场，画面不出现）
##   "hung": {int: int}                影人编号 -> 挂钩槽位
##   "positions": {int: [float, float]} 接地点归一化 x/y
##   "hand_angles": {int: [float, float]} 左右手角（弧度，不得超过 hand_angle_max_rad）
##   "elbow_bends": {int: [float, float]} 左右前臂偏折（弧度；肘内角 = 180° − |bend|，
##                     0 = 共线直臂。显示端套在 `PlaceholderPuppet.hand_bend` 上，不进状态）
##   "facing": {int: float}            初始朝向；-1 朝左、+1 朝右，**缺省即 +1**
##   "distance" / "exposure" / "oil": float  灯的初值
var initial: Dictionary = {}
var segments: Array = []  ## [{name: String, start_ms: int, end_ms: int}]
var cues: Array = []  ## 关键动作列表，结构见 Cue.make()


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
	def.summary = "白素贞与小青并肩立在湖边，许仙在桥头举伞相候。白素贞走到他面前、把手抬到打伞位以上（左手右手都可以，最高可到竖直）——碰到便接过伞；随后持伞走回小青身旁，本折即收。本折学握胸签与双手。"
	# 本折的手角上限放开到 **π（竖直）**。🔴 2026-10-16 用户定案「白素贞的手臂最大角度
	# 可以到竖直」：她可以把一只手一路举到头顶竖直（原上限 90° = 打伞位，现降格为
	# 接伞判据的**下界参考角** `UmbrellaController.CONTACT_HAND_ANGLE_RAD`）。
	# 接伞判据同步放宽为「任一只手的手高不低于打伞位」（见 `_meeting_hand()`），
	# 因此「按住抬手键一路到顶」也能接伞，不会再扫过头错过。
	def.hand_angle_max_rad = PI
	# 许仙（1 号）右手举到 **90°**（水平前伸）持伞——流程表「开场：许仙固定站位，
	# 右手举起持伞」，角度按用户 2026-10-04 定案由 180° 改为 90°。
	# 这个角度与对齐条件自洽：白素贞要抬进 [75°, 90°] 才算「抬手」到位（见上面的常量），
	# 而接伞要求两手手高差 ≤ 0.04（UmbrellaController.HAND_HEIGHT_TOLERANCE，换算 ≈±7.6°），
	# 两者叠加后「抬手到位」的区间完整包住对齐窗口（82.4°~90°），
	# 所以她抬手到位就一定能接住伞，不会出现「拍点算到位、伞却不换手」。
	# 白素贞（0 号）左手自然垂下；她要自己把左手抬起来才会接伞。
	# 两个挂钩仍由许仙、小青占满，第一关因此不会产生挂起/取回事件（见交接文档第 7 节）。
	# 站位（2026-10-16 第三轮定案）：**许仙在桥上**（0.58，桥左端 0.5285 之右约 99px，脚点 588px），
	# **小青与白素贞在柳树一带**（0.26 / 0.32——小青贴树，白素贞在她靠许仙的那一侧）。
	# 落地线**分两条**：许仙 LEVEL1_GROUND_Y = 0.587963（635px，由 0.5 下移 95px）；
	# 小青与白素贞 LEVEL1_GROUND_Y_LADIES = 0.597222（**645px，累计再下移 10px**，用户同日定案）。
	# 手角：白素贞双手放下（她要自己抬左手才会接伞）；许仙**右手高举托伞（140°）、左臂垂下**
	# （用户 2026-10-16 参考图：「许仙拿伞动作参考」——手落在头顶高度、另一臂自然垂着）；
		# 小青按用户 2026-10-16 16:08 截图摆**开场亮相**（白素贞侧那条臂斜向右上高举、
		# 肘弯 100°、袖口收在头顶右上方；柳树侧垂下——见上面三条常量注与 `elbow_bends`），
		# 她这一折仍只作陪——姿势是装饰性的，不参与任何判定。
	def.initial = {
		"controlled": 0,
		"on_stage": [0, 1, 2],
		"hung": {1: 0, 2: 1},
		"positions":
		{
			0: [LEVEL1_BAISUZHEN_X, LEVEL1_GROUND_Y_LADIES],
			1: [LEVEL1_XUXIAN_X, LEVEL1_XUXIAN_Y],
			2: [LEVEL1_XIAOPING_X, LEVEL1_GROUND_Y_LADIES]
		},
		"hand_angles":
		{
			0: [0.0, 0.0],
			1: [0.0, LEVEL1_XUXIAN_UMBRELLA_RAISE_RAD],
			2: [LEVEL1_XIAOPING_HAND_RAISED_RAD, LEVEL1_XIAOPING_HAND_DOWN_RAD]
		},
		# 肘弯（前臂偏折，弧度；肘内角 = 180° − |bend|）。只给小青高举的那条臂（下标 0，
		# 白素贞侧）：**正号** = 前臂折向头顶右上方（2026-10-16 用户 16:08 截图定案）。
		# 由显示端套在 `PlaceholderPuppet.hand_bend` 上（`level1_a_scene` 与 B 侧回放各套一次）。
		"elbow_bends": {2: [LEVEL1_XIAOPING_ELBOW_BEND_RAD, 0.0]},
		# 开演朝向（facing：-1 朝左、+1 朝右；**缺省即 +1**，只写偏离默认的那一个）。
		# 参考朝向见 assets/puppets/puppet_assets.json 的 `reference_facing`（许仙 +1、白素贞 -1、
		# 小青 -1）；镜像系数 = facing / reference_facing，因此 **facing 就是画面上的朝向**。
		# 🔴 **许仙 -1**：他在两位娘子的**右侧**（桥上 0.58），必须朝左才读作「面向来人」；
		# 镜像后他举起持伞的右手也画到身体左侧，正对交接方向。
		# 🔴 **白素贞 -1**：她在小青**右侧**（0.32 > 0.26），朝左看小青 → 两人相对而立
		# （小青朝右 = 默认 +1，**不入表**）。许仙朝左，正对两位娘子。
		# ⚠️ 三具里只有**小青**用默认 +1 表达，读方一律走 `.get(id, 1.0)` 取有效值，
		# 不能硬取下标（否则默认值那具会直接抛键错；测试已按此改）。
		"facing": {0: -1.0, 1: -1.0},
		"distance": 0.5,
		"exposure": 1.0,
		"oil": 1.0,
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
##   移动（向右走 / 走到小青身旁 / 走回还伞）→ 3 s。
## 起因：定这一档时这几段移动各要走 0.5~0.55 个舞台宽（960~1060 画布像素，拖动是 1:1 映射），
## 正常拖速 450~600 px/s 下需要 1.6~2.4 s，再加反应时间。原来一律按 1 s 给，
## 玩家只在最后 1 秒才看到提示，实测「根本来不及走」。
## ⚠️ 2026-10-15 折返点镜像后这几段都变短了（最长约 0.18 个舞台宽），**仍保留 3 s**：
## 提前量多一点无害（提示一次只显示最靠前的那条未完成落点），改档位要连带复核整条提示时刻表。
##
## segment 字段指向所在段落名，供按段汇总合拍度与低合拍补救使用。
##
## 本条流程里的位置关系（用户 2026-10-05 修订：折返点改为**小青身旁**，后半段铺开到第 48 拍；
## 2026-10-16 定案：许仙回**桥头** 0.5285、两位娘子站柳树一带 0.26 / 0.32，两次横移的方向随之对调）：
##   游湖（第 8 拍）  白素贞从 0.32 **向右**走，学会用胸签横移（走向桥头的许仙）
##   借伞（第 14 拍） 左手抬到 90°（打伞位）——许仙把伞举在头顶（140°），两人握在伞杆不同高度
##   接伞（第 16 拍） 走进交接窗口（0.3803~0.5003）+ 手到打伞位 → 伞转到白素贞左手
##   回柳树（第 26 拍）接到伞后**向左**走，走到**小青身旁**（不必走到舞台最左端）
##   还伞（第 40 拍） 已随 2026-10-16 流程简化**下线**（拍点、事件与控制器通路都不再产生）
##   同舟（第 48 拍） 放下已空的左手收势
static func make_level1_cues(def: StageDef) -> Array:
	# 交接窗口（白素贞接地点 x）：与 UmbrellaController 的判据同一处来源，
	# 因此「拍点说该到位了」与「控制器真的换手」不会漂开。
	var join: Vector2 = UmbrellaController.join_window_x(LEVEL1_XUXIAN_X)
	var cues: Array = [
		# 第 2 拍：先蹲下（stance 落到接近 1.0），为第 4 拍的站起做准备
		#
		# ⚠️ 待办（2026-10-08，用户认可「先记着」）：用户认为「开局没有必要让白素贞蹲下」，
		# 但本轮为**不动拍点表**（连带不动测试与段落表）而保留这两条。真要删时须一起处理三件事：
		#   ① 删蹲下就必须**连站起一起删**——她本来就站着，stance 已在 [0, 0.05] 内，
		#      留着站起会让开局白送一个命中；
		#   ② 全四关只有这两条落点针对 `stance`，删掉后「蹲站」再没有任何教学落点；
		#   ③ PRD 第 6.1 节第一幕明写教「移动、蹲站与翻面」，且最低可验收动作里写着
		#      「两个影人**先后站起**」，与本文档必须同步修改。两笔账一起留到三幕落地时处理。
		CueScript.make(
			"l1_c0_crouch",
			def.beat_ms(2),
			CueScript.ACTION_CROUCH,
			0,
			{"key": "stance", "min": 0.85, "max": 1.0},
			250,
			"crouch"
		),
		# 重音（第 4 拍）：站起。stance 0.0 = 完全站立，因此「站起」的到位范围是接近 0，
		# 而不是 0.7-1.0（那是蹲下方向，写成后者会让蹲到底反而被判成站起）。
		CueScript.make(
			"l1_c1_stand",
			def.beat_ms(4),
			CueScript.ACTION_STAND_UP,
			0,
			{"key": "stance", "min": 0.0, "max": 0.05},
			250,
			"stand_up"
		),
	# 第 8 拍：**向右**走向许仙（他在桥头 0.5285，右手一直举着伞）。
	# 🔴 2026-10-16 定案（许仙回桥头、两位娘子站柳树下）：本条由「向左走」翻回「向右走」
	# （动作与示范动作一起改；目标带 `LEVEL1_APPROACH_*` 是派生式，自动跟到窗口 0.3803~0.5003）。
	#
	# ⚠️ `cue_id` 里的 `left` 这时又变回**历史名**了（动作是向右）。**仍然不要改名**：
	# 这个名字被 B 侧 `scripts/b/audio_score.gd` 按 id 引用（「姐姐移步到亭前。」那句提示），
	# 改名会破坏既有记录的 cue_id 兼容。
	#
	# 这一条是移动档，给 3 s 提前量：让「移动 = 3 s」这条规则只有一条、不必按距离分档
	# （线索早出现无害：提示一次只显示最靠前的那条未完成落点）。
	CueScript.make(
		"l1_c2_move_left",
		def.beat_ms(8),
		CueScript.ACTION_MOVE_RIGHT,
		0,
		{"key": "x", "min": LEVEL1_APPROACH_MIN, "max": LEVEL1_APPROACH_MAX},
		250,
		"move_right",
		LEVEL1_MOVE_HINT_LEAD_MS
	),
		# 第 14 拍：把左手抬到打伞位（90°），与许仙举着的右手齐平。
		# 到位区间见 LEVEL1_UMBRELLA_RAISE_*：它完整包住接伞的手高窗口（82.4°~90°），
		# 因此「抬手」这条落点成立时手高就已经齐平。
		CueScript.make(
			"l1_c3_hand_raise",
			def.beat_ms(14),
			CueScript.ACTION_HAND_RAISE,
			0,
			{
				"key": "angle",
				"min": LEVEL1_UMBRELLA_RAISE_MIN_RAD,
				"max": LEVEL1_UMBRELLA_RAISE_MAX_RAD
			},
			250,
			"hand_raise"
		),
		# 重音（第 16 拍）：伞在**两只手相接**的那一刻换手（走进交接窗口 + 手高齐平）。
		# 目标带就是交接窗口本身（0.3803~0.5003）：她站在许仙**左侧**、不必贴到他身上，
		# 更不必穿过他。落点在这里接棒：玩家提前走进窗口、或补救时再走进去，
		# 都由这一条如实记下偏移。物理上的伞早在两手相接时就换手了
		# （PRD 第 5.1 节：动作照常发生），本落点只判拍。
		CueScript.make(
			"l1_c4_take_umbrella",
			def.beat_ms(16),
			CueScript.ACTION_UMBRELLA_TAKE,
			UmbrellaController.BAISUZHEN_ID,  # 事件上报「接手的人」；写错会被判定直接跳过
			{"key": "x", "min": join.x, "max": join.y},
			250,
			"umbrella_take"
		),
		# 重音（第 26 拍）：接到伞后**向左**走，走到**小青身旁**（她 0.26，整关不动）。
		# 用户 2026-10-05 定案：原先要求走到舞台最右端（x≥0.95），实测太远、也没必要。
		# 🔴 2026-10-16 定案（许仙回桥头）：本条由「向右走」翻回「向左走」（动作与示范动作一起改）。
		# 目标带 = [TURN_MIN, TURN_MAX] = **[0.28, 0.32]**，**上界**直接取控制器的
		# `TURN_POINT_X`（同源；控制器判归位的条件就是 `x ≤ TURN_POINT_X`）。
		#
		# ⚠️ 这一拍现在是**本关的完成条件**（接到伞 + 走到小青身旁即收尾，见 Act1OperaFlow）；
		# 但拍点本身仍是「漏做机会」：没走到就开补救窗口，与其它落点同一套通路。
		#
		# 落点是**第 26 拍**：接伞（第 16 拍）之后留 10 拍 = 6.25 s。这一趟从窗口（约 0.42）
		# 走回小青身旁（≤0.32）再并到她（0.26）边上，约 0.10~0.16 个舞台宽 ≈ 192~307 px，
		# 正常拖速下 1 s 内就能走完；余下的时间仍是给玩家从容走位、按鼓点踩点的。
		# ⚠️ 拍号与容差**不动**：改拍号会连带整条后半程的时刻表。
		#
		# `cue_id` 必须与第 8 拍的 `l1_c2_move_left` **不同**（动作也相反）：
		# 两条是两次独立的漏做机会。补救系统按 `cue_id` 去重（同一 cue 不能重复触发
		# 自己的窗口），共用一个 id 会让这一条漏做开出两个窗口——实测就是这样多出
		# 第 9 个 remedy_open 的。
		CueScript.make(
			"l1_c5_move_to_xiaoping",
			def.beat_ms(LEVEL1_TURN_BEAT),
			CueScript.ACTION_MOVE_LEFT,
			0,
			{"key": "x", "min": LEVEL1_TURN_MIN, "max": LEVEL1_TURN_MAX},
			250,
			"move_left",
			LEVEL1_MOVE_HINT_LEAD_MS
		),
		# —— 还伞（原第 40 拍 l1_c6_return_umbrella）：2026-10-16 用户定案**取消** ——
		# 流程简化为「借伞 → 回到小青身旁 → 结束」，不再走回许仙还伞，故这一条落点下线。
		# `UmbrellaController._try_return` 的代码保留（旧关卡与 tests/a 仍按两段流程跑），
		# 但正式第一幕不再打开 `return_allowed`，因此它不会被触发。
		# `LEVEL1_RETURN_BEAT` 常量一并保留，供旧测试与将来可能的「第二幕还伞」复用。
		# —— 收势（原第 48 拍 l1_c7_hand_lower）：2026-10-16 用户定案**取消** ——
		# 「最后白素贞手不用放下」：流程收在「走回小青身旁」即结束（Act1OperaFlow 读
		# `is_at_home()` 收关），不再要求任何落手动作。`LEVEL1_LOWER_BEAT` 常量与
		# `CueScript.ACTION_HAND_LOWER` 通路保留（第二关收桨 cue 与补救测试仍在用）。
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
		# ⚠️ 原 `"l1_c6_return_umbrella": "还伞"` 条目已随还伞拍点一起下线（2026-10-16 流程简化）。
		# 「还伞」这个**段落名**刻意保留不动：它现在的含义是「持伞走回小青身旁」这一整段，
		# 改段名要连带动 `def.segments` 与 test_level1_runtime 的段落归属校验，收益不大。
		# 放手收势已随第 48 拍 cue 一起下线（2026-10-16 用户定案「最后不用放下手」），
		# 「同舟」段名保留（段落表口径不动）。
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
		"distance": 0.5,
		"exposure": 1.0,
		"oil": 1.0,
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
		CueScript.make(
			"l2_c0_move_right",
			def.beat_ms(6),
			CueScript.ACTION_MOVE_RIGHT,
			-1,
			{"key": "x", "min": 0.55, "max": 1.0},
			250,
			"move_right"
		),
		# 重音（第 12 拍）：挂起当前影人（空格）——白素贞留在舟上撑伞
		CueScript.make("l2_c1_hook", def.beat_ms(12), CueScript.ACTION_HOOK, -1, {}, 250, "hook"),
		# 第 20 拍：取回挂起的影人（先点选，再按空格）——小青接桨
		CueScript.make(
			"l2_c2_take_back", def.beat_ms(20), CueScript.ACTION_TAKE_BACK, -1, {}, 250, "take_back"
		),
		# 第 26 拍：向左移，与仍挂着的白素贞同框
		CueScript.make(
			"l2_c3_move_left",
			def.beat_ms(26),
			CueScript.ACTION_MOVE_LEFT,
			-1,
			{"key": "x", "min": 0.0, "max": 0.45},
			250,
			"move_left"
		),
		# 第 34 拍：抬手（举桨）
		CueScript.make(
			"l2_c4_hand_raise",
			def.beat_ms(34),
			CueScript.ACTION_HAND_RAISE,
			-1,
			{"key": "angle", "min": HAND_OVERHEAD_MIN_RAD, "max": HAND_OVERHEAD_MAX_RAD},
			250,
			"hand_raise"
		),
		# 重音（第 42 拍）：回到白素贞身旁，组成同框画面
		CueScript.make(
			"l2_c5_reach_pair",
			def.beat_ms(42),
			CueScript.ACTION_REACH,
			-1,
			{"key": "x", "min": 0.47, "max": 0.58},
			250,
			"reach_pair"
		),
		# 第 56 拍：落桨收势
		CueScript.make(
			"l2_c6_hand_lower",
			def.beat_ms(56),
			CueScript.ACTION_HAND_LOWER,
			-1,
			{"key": "angle", "min": HAND_LOWER_MIN_RAD, "max": HAND_LOWER_MAX_RAD},
			250,
			"hand_lower"
		),
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
		"distance": 0.5,
		"exposure": 1.0,
		"oil": 1.0,
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
		CueScript.make(
			"l3_c0_lamp_far",
			def.beat_ms(8),
			CueScript.ACTION_LAMP_DISTANCE,
			-1,
			{"key": "distance", "min": 0.0, "max": 0.25},
			250,
			"lamp_far"
		),
		# 重音（第 20 拍）：向上滚轮，灯推近，影子放大
		CueScript.make(
			"l3_c1_lamp_near",
			def.beat_ms(20),
			CueScript.ACTION_LAMP_DISTANCE,
			-1,
			{"key": "distance", "min": 0.80, "max": 1.0},
			250,
			"lamp_near"
		),
		# 第 28 拍：抬手采仙草
		CueScript.make(
			"l3_c2_hand_raise",
			def.beat_ms(28),
			CueScript.ACTION_HAND_RAISE,
			-1,
			{"key": "angle", "min": HAND_OVERHEAD_MIN_RAD, "max": HAND_OVERHEAD_MAX_RAD},
			250,
			"hand_raise"
		),
		# 第 38 拍：云雾再起，灯又推远、影子收小
		CueScript.make(
			"l3_c3_lamp_far",
			def.beat_ms(38),
			CueScript.ACTION_LAMP_DISTANCE,
			-1,
			{"key": "distance", "min": 0.0, "max": 0.25},
			250,
			"lamp_far"
		),
		# 重音（第 50 拍）：灯再推近，完整亮相
		CueScript.make(
			"l3_c4_lamp_near",
			def.beat_ms(50),
			CueScript.ACTION_LAMP_DISTANCE,
			-1,
			{"key": "distance", "min": 0.80, "max": 1.0},
			250,
			"lamp_near"
		),
		# 第 60 拍：向左退去
		CueScript.make(
			"l3_c5_move_left",
			def.beat_ms(60),
			CueScript.ACTION_MOVE_LEFT,
			-1,
			{"key": "x", "min": 0.0, "max": 0.40},
			250,
			"move_left"
		),
		# 重音（第 68 拍）：回到中位收势
		CueScript.make(
			"l3_c6_reach_center",
			def.beat_ms(68),
			CueScript.ACTION_REACH,
			-1,
			{"key": "x", "min": 0.47, "max": 0.53},
			250,
			"reach_center"
		),
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
		"distance": 0.5,
		"exposure": 0.15,
		"oil": 1.0,
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
		CueScript.make(
			"l4_c0_head_swap", def.beat_ms(8), CueScript.ACTION_HEAD_SWAP, -1, {}, 250, "head_swap"
		),
		# 第 16 拍：倾灯，影子初显
		CueScript.make(
			"l4_c1_exposure_low",
			def.beat_ms(16),
			CueScript.ACTION_LAMP_EXPOSURE,
			-1,
			{"key": "exposure", "min": 0.45, "max": 0.60},
			250,
			"exposure_up"
		),
		# 重音（第 26 拍）：继续推高显露
		CueScript.make(
			"l4_c2_exposure_mid",
			def.beat_ms(26),
			CueScript.ACTION_LAMP_EXPOSURE,
			-1,
			{"key": "exposure", "min": 0.75, "max": 0.90},
			250,
			"exposure_up"
		),
		# 第 32 拍：抬手（举杯痛饮）
		CueScript.make(
			"l4_c3_hand_raise",
			def.beat_ms(32),
			CueScript.ACTION_HAND_RAISE,
			-1,
			{"key": "angle", "min": HAND_OVERHEAD_MIN_RAD, "max": HAND_OVERHEAD_MAX_RAD},
			250,
			"hand_raise"
		),
		# 重音（第 42 拍）：完整亮相
		CueScript.make(
			"l4_c4_exposure_full",
			def.beat_ms(42),
			CueScript.ACTION_LAMP_EXPOSURE,
			-1,
			{"key": "exposure", "min": 0.95, "max": 1.0},
			250,
			"exposure_up"
		),
		# 第 52 拍：向左惊走
		CueScript.make(
			"l4_c5_move_left",
			def.beat_ms(52),
			CueScript.ACTION_MOVE_LEFT,
			-1,
			{"key": "x", "min": 0.0, "max": 0.40},
			250,
			"move_left"
		),
		# 第 60 拍：再换一头，复还人形
		CueScript.make(
			"l4_c6_head_swap_back",
			def.beat_ms(60),
			CueScript.ACTION_HEAD_SWAP,
			-1,
			{},
			250,
			"head_swap"
		),
		# 重音（第 70 拍）：回到中位收势
		CueScript.make(
			"l4_c7_reach_center",
			def.beat_ms(70),
			CueScript.ACTION_REACH,
			-1,
			{"key": "x", "min": 0.47, "max": 0.53},
			250,
			"reach_center"
		),
		# 第 78 拍：灯推近，影子放大收束
		CueScript.make(
			"l4_c8_lamp_near",
			def.beat_ms(78),
			CueScript.ACTION_LAMP_DISTANCE,
			-1,
			{"key": "distance", "min": 0.80, "max": 1.0},
			250,
			"lamp_near"
		),
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
			problems.append(
				"stage %d 段「%s」超出关卡时长：%d-%d（时长 %d）" % [id, name, start_ms, end_ms, duration_ms]
			)
		if end_ms <= start_ms:
			problems.append("stage %d 段「%s」起止不递增：%d-%d" % [id, name, start_ms, end_ms])
		if start_ms < previous_end:
			problems.append(
				"stage %d 段「%s」与上一段重叠：start=%d < 上一段 end=%d" % [id, name, start_ms, previous_end]
			)
		previous_end = end_ms
	if not segments.is_empty() and previous_end < duration_ms:
		problems.append("stage %d 段落未覆盖整关：最后一段结束于 %d，时长 %d" % [id, previous_end, duration_ms])
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
	# 开演朝向：影人只有正反两面，facing 是二值量。写别的值会被 `PuppetState.clamp_continuous`
	# 悄悄吸附成 ±1——数据错了却看不出来。这里把不合法的数据直接报出来，不静默通过。
	for puppet_id in initial.get("facing", {}).keys():
		var facing: float = float(initial["facing"][puppet_id])
		if absf(absf(facing) - 1.0) > 1e-9:
			problems.append("stage %d 开演布景：影人 %d 的朝向 %s 不是 ±1" % [id, int(puppet_id), str(facing)])
		if not on_stage.is_empty() and not on_stage.has(int(puppet_id)):
			problems.append("stage %d 开演布景：设了朝向的影人 %d 不在场" % [id, int(puppet_id)])
	# 本折的手角上限必须落在 PuppetState 的硬边界内。
	# 布景由显示端直接写进 PuppetState（不经控制器），所以这里必须查：
	# 否则一个「上限 90°、布景却摆 180°」的关卡会让操控手感与开演姿势自相矛盾。
	if (
		hand_angle_max_rad < PuppetStateScript.HAND_ANGLE_MIN
		or hand_angle_max_rad > PuppetStateScript.HAND_ANGLE_MAX
	):
		problems.append(
			(
				"stage %d: hand_angle_max_rad 越界：%s（合法 %s ~ %s）"
				% [
					id,
					str(hand_angle_max_rad),
					str(PuppetStateScript.HAND_ANGLE_MIN),
					str(PuppetStateScript.HAND_ANGLE_MAX)
				]
			)
		)
	# 🔴 2026-10-16：本折上限只约束**玩家操控的那一具**。
	# 第一关的上限现为 π（竖直，用户定案「手臂最大可以到竖直」），控制器本来也只在
	# 受控影人身上执行它（PuppetController.set_hand_angle 只夹 `controlled`）。
	# 若某关把上限收得比布景姿势低（例如旧版收在 90° 时小青的 160° 亮相），
	# 布景影人越过它不是「关卡自相矛盾」，是有意的装饰姿势，且不参与接伞判定。
	# 越过本折上限的布景影人仍须落在 PuppetState 的硬边界内，所以这里按身份选天花板。
	for puppet_id in initial.get("hand_angles", {}).keys():
		var angles: Array = initial["hand_angles"][puppet_id]
		var is_controlled_puppet: bool = int(puppet_id) == controlled
		var ceiling: float = (
			hand_angle_max_rad if is_controlled_puppet else PuppetStateScript.HAND_ANGLE_MAX
		)
		for hand_index in angles.size():
			var angle: float = float(angles[hand_index])
			if angle > ceiling + 1e-9:
				problems.append(
					(
						"stage %d 开演布景：影人 %d 的手角 %s 超过%s %s"
						% [
							id,
							int(puppet_id),
							str(angle),
							"本折上限" if is_controlled_puppet else "硬边界",
							str(ceiling)
						]
					)
				)
	# 肘弯是显示端姿势数据：|bend| = π 时前臂折回上臂反方向（肘内角 0°），再大就翻转了。
	for puppet_id in initial.get("elbow_bends", {}).keys():
		var bends: Array = initial["elbow_bends"][puppet_id]
		for bend_index in bends.size():
			var bend: float = float(bends[bend_index])
			if absf(bend) > PI + 1e-9:
				problems.append(
					(
						"stage %d 开演布景：影人 %d 的肘弯偏折 %s 超过硬边界 ±%s"
						% [id, int(puppet_id), str(bend), str(PI)]
					)
				)
	return problems
