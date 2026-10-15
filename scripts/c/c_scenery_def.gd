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
##   例外：`anchor_y` 允许落在 [0, 1] 内任意值（见下方 Y_TOLERANCE 说明），
##   即布景可以整体上移/下移，此时接地点会离开影人接地线——这是**有意开放**的，
##   由布景作者自行取舍「贴合度 vs 摆位自由」。

## —— 纵轴基准与容差 ——
## 影人接地点：A 侧 `stage_def.gd` 第一关 `initial.positions` 三具全部 y = 0.5。
## 布景的接地线通常应与它对齐，否则树根/桥脚与影人的脚会分处两条线（画面像贴上去的）。
const ANCHOR_Y: float = 0.5
## 允许的上下浮动。
## 口径变更（用户 2026-10-08 第三次定案）：由 0.03 **放宽至 0.5**。
##   - 原口径「上下浮动不能超过 0.03」把布景纵向位置锁死在 [0.47, 0.53]，
##     第一关把接地线放到 0.53 时即触及上界、再无下移余量。
##   - 放宽到 0.5 后 [Y_MIN, Y_MAX] = [0.0, 1.0]，覆盖整个舞台高度：
##     布景在纵向上不再受硬约束，可自由上移/下移（**左右平移才是那条不可破的约束**）。
##   - ⚠️ 放宽的只是「布景自身能不能移动」；影人接地点仍是 0.5，**没有被改动**。
##     布景若离开 0.5 就与影人的脚不在同一条线上——这是使用者的选择，不再报错。
const Y_TOLERANCE: float = 0.5
const Y_MIN: float = ANCHOR_Y - Y_TOLERANCE  ## 0.0（放宽后覆盖整个舞台高度）
const Y_MAX: float = ANCHOR_Y + Y_TOLERANCE  ## 1.0

## —— 第一关「入手 · 游湖借伞」布景参数（用户 2026-10-08 起逐条定案）——
## **只有两样东西**（2026-10-09 第二次构图定案后）：
##   柳树：树贴图左缘贴幕布左缘（内边距 30px），**树底与桥底同在 y≈573px**
##   拱桥：**完整拱**（woop 原素材即全拱），桥基中心在 x = 0.73，整体落在幕布内
##
## ⚠️ 用户明确「**暂时不画花草**」「边界线不用画」——本关不出现花草与画框线。
## 记为常量而不是散在函数里，是为了让断言能直接引用同一个数（避免数据与测试各写一套）。
## 第二次构图（用户 2026-10-09 16:30 四条指令）落实如下：
##   ① 桥完整显示整张：几何探针实测桥贴图绘制矩形 x 1015~1788，幕布 66~1854，
##      **两侧余量 139px / 66px，本就完整无裁**；此前观感上「像被裁」是因为桥整体
##      偏右（左侧 66~1015 共 949px＝幕布 53% 全空），而非裁剪 bug。
##   ② 树底与桥底对齐 → LEVEL1_WILLOW_BASE_Y 见该常量注。
##   ③ 树左缘贴画布左侧（内边距 30px）→ LEVEL1_WILLOW_X 见该常量注。
##   ④ 「暂不考虑桥或树遮挡人物」：影人站在树冠前属预期，不作为定值依据。
## 第三次构图（用户 2026-10-09 16:51「树整体放大，树冠顶与画面上边缘留 1/9 幕布高」）：
##   用户 AskUserQuestion 拍板 **方案 A**——保住「树底与桥底对齐」优先于「树高占 8/9」。
##   几何原因（已量化）：树底锁在桥底 572.8px 时，树底到幕布顶只有 480.8px
##   ＝幕布高的 6.7/9，故树高物理上最多占 **70.7%**，达不到 8/9；
##   若强行取 8/9（scale 0.2831）树顶会到 y=50，超出幕布顶 42px 被裁（用户明令禁止）。
##   故取「底对齐 + 顶留白 1/9」的解：scale 0.225063 → 树高 416px（幕布 70.7%）、
##   顶留白 65.3px＝幕布高 1/9.00。
##
## —— 2026-10-15 整关净下移 90px（用户定案）——
## 用户先提「所有景物纵坐标下移幕布的五分之一」，量化后为 117.6px（幕布高 588/5），
## 但那会让两件景物底边落到 690.4px、**越出幕布下沿 680px 达 10.4px**，被渲染器的
## clip_children 裁掉（表现为树根/桥脚「陷进幕布下边」被切断）；用户遂改为 **95px**，
## 随后又「再上移 5px」→ 净下移 **90px**（按净量记录，不叠加两次位移）。
## 下移量以「画布归一化」表达（÷1080），两件景物共用同一个 LEVEL1_Y_DOWN。
## ⚠️ 幕布下沿 680px 是硬边界：本关从这里再往下最多还能移 17.2px。
const LEVEL1_Y_DOWN: float = 90.0 / 1080.0  ## ≈ 0.083333333（整关净下移 90px，归一化）

## —— 2026-10-15 柳树树高按「× 幕布高」定案（用户同日四轮：0.75 → 0.8 → 0.9）——
## 树高 = 0.9 × 588 = **529.2px**（占幕布高 **90.0%**；此前 416px/70.7%、441px/75.0%、470.4px/80.0%）。
## 底缘仍锁在景物接地线（见 LEVEL1_WILLOW_BASE_Y）、左缘仍钉在幕布内 30px（96px），
## 所以树是**向上 + 向右**同时长：
##   顶边 = 662.8 − 529.2 = **133.6px**，顶留白 **41.6px**（原 100.4px）；
##   右缘 = 96 + 1436×scale = **507.66px**（原 461.92px）。
##   ⚠️ 右缘已越过 A 侧小青的影身左缘（0.26 → 475.2px）**32.5px**，即小青现在站在柳树
##      绘制矩形的横向范围内（影人 z_index 在布景之上，画面上是「站在柳条前」）。
##      用户 2026-10-09 已定「暂不考虑桥或树遮挡人物，影人站在树冠前属预期」，
##      故不视为越界；但 A 侧站位注释里的判据线（439.05px）与空当（36.2px）已彻底失效。
## ⚠️ 下面三个位置常量现在都写成**派生式**，只依赖本行的树高：
##   改树高只需改这一个数。旧写法是三个手算字面量，改 scale 忘重算会让左缘/底线静默漂，
##   而左边距断言容差是 20~60px，30 → 22px 的漂移它根本抓不住。
## ⚠️ 上限已经很近：树底锁在接地线时树高物理上最多 **570.8px**（幕布顶 92 到接地线 662.8，
##   ＝幕布高 97.1%），再高就被幕布顶裁掉；0.9 距该上限只剩 **41.6px**。
const LEVEL1_WILLOW_HEIGHT_PX: float = 0.9 * 588.0  ## 529.2px = 0.9 × 幕布高（Rect2(66,92,1788,588).size.y）
## 柳树贴图像素比例（逐资产静态常量，非运行时形变能力）。
## 柳素材 1436×1846 与桥素材像素密度不同，全局 TEXTURE_SCALE_PX 不够用。
## 0.9 × 588 ÷ 1846 = **0.28667389**（引擎打印实测；勿手算）。历史：0.20 → 0.26 → 0.21（2026-10-09 三轮调整）
##   → 0.225063（「底对齐 + 顶留白 1/9」联立解）→ 0.2388949（441px）→ 0.25482124（470.4px）→ 0.28667389（529.2px）。
const LEVEL1_WILLOW_SCALE: float = LEVEL1_WILLOW_HEIGHT_PX / 1846.0  ## ≈ 0.28667389
## 柳树 anchor_x：使**贴图左缘**恒落在幕布左缘内 30px（= 66 + 30 = 96px）。
## 左缘 = anchor_x×1920 − 564×scale（564 = 树干接地点素材 x，见 texture_foot_px）
##   ⇒ anchor_x = (96 + 564×scale) / 1920。scale 变则本值自动跟着变，左缘恒 96px。
const LEVEL1_WILLOW_X: float = (96.0 + 564.0 * LEVEL1_WILLOW_SCALE) / 1920.0  ## ≈ 0.13421046
## 柳树基线（树干接地点 y）。**与桥底严格同线**（用户 2026-10-09 16:30 定案，16:51 复确认）。
## 桥：anchor_y=LEVEL1_GROUND_Y → 桥贴图底缘 = anchor_y×1080 + (715−714)×0.42。
## 树：贴图底缘 = anchor_y×1080 + (1846−1845)×scale = anchor_y×1080 + scale。
## ⚠️ 那 1px 素材差本身随 scale 变（scale 0.21 时 0.21、0.28667389 时 0.28667389），
##   所以本常量同样写成派生式：底缘目标（572.8px + 整关下移量）减掉 scale 再除 1080。
##   历史字面量（仅供对照，勿再直接改）：scale 0.225063 且下移 0 时为 0.530162。
const LEVEL1_WILLOW_BASE_Y: float = (572.8 + LEVEL1_Y_DOWN * 1080.0 - LEVEL1_WILLOW_SCALE) / 1080.0  ## ≈ 0.61343826 → 底缘 662.8px
## 拱桥锚点 = 桥基中心 x（**完整拱**：woop 原素材本就是全拱，两端桥台 + 拱顶齐全）。
## 演变记录（用户 2026-10-08 起的定位决定，2026-10-09 定稿为完整拱）：
##   - 最初手绘草图：桥头起点 0.72；
##   - woop 贴图接入后改「桥心」语义，三方案拍板选 C → 0.86（小青站位）；
##   - 同日定案「只露一半」「保留左半」：资产裁成左半拱 1024×726，anchor 先后
##     取 0.86 → 1.00 → 0.965625（修正幕布右缘误读，见 git 历史）；
##   - **2026-10-09 定稿「桥头左移，使桥能够完整展现在幕布中」**：半拱无论怎么移
##     都读作「被裁断的桥」，唯一完整解 = 恢复 woop 的**完整拱**
##     （arch_bridge.png 重裁为 1842×715：y 707~1423 桥体全高、x 106~1943 全跨，
##      顶部雨丝带/底部水雾仍然裁掉），anchor 语义改为**桥基中心** = 0.73：
##     桥跨 1016~1787px，距幕布右缘 67px、左端 1016px，整体完整入幕布。
##     小青（0.86）位于桥右段前方，白素贞（0.50）在桥头左侧。
const LEVEL1_BRIDGE_CENTER_X: float = 0.73

## —— 第一关接地线（用户 2026-10-08 二次定案：由 0.50 下移到 0.53）——
## 用户原话「桥和树的纵轴线再往下移动 0.03」：0.50 + 0.03 = 0.53。
## 当时触及旧容差（0.03）的上界；现已把 Y_TOLERANCE 放宽到 0.5（见上），
## 因此 0.53 不再是边界值，仍可继续微调。
## 但注意 0.53 已经**离开影人接地线 0.5**：树根/桥脚比影人的脚低 0.03×1080 ≈ 32px。
## 这是用户看过截图后的选择；若哪天想回到严格贴合，把它改回 ANCHOR_Y 即可。
##
## —— 2026-10-15 整关净下移 90px（用户定案；来龙去脉见文件上部 LEVEL1_Y_DOWN 注）——
## 现状：底缘 572.8px → **662.8px**（幕布下沿内，余 17.2px）；
##       影人接地点仍是 0.5（540px，A 侧数据不动），景物底线比影人的脚低 ≈122.8px。
const LEVEL1_GROUND_Y: float = ANCHOR_Y + 0.03 + LEVEL1_Y_DOWN  ## ≈ 0.613333

## —— 元素种类 ——
## 显示端按 `kind` 选画法。新增种类时两边都要改（数据 + 画面），故集中在这里。
const KIND_WILLOW: String = "willow"  ## 柳树：树干 + 向左上展开的树冠
const KIND_ARCH_BRIDGE: String = "arch_bridge"  ## 拱桥：半拱 + 水平延伸出画

## —— 位移字段名（**唯一**合法的位置相关字段）——
## 断言会检查每条元素「除这些以外没有别的位移字段」，防止有人偷偷加 y/scale/rotation。
const POSITION_KEYS: Array[String] = ["anchor_x", "anchor_y", "pan_x"]

## —— 贴图相关（用户 2026-10-08 起：以 woop 素材替换程序化占位）——
## 素材来源：`皮影美术素材/桥.woop`（原 architecture-014-002.woop，woop@2 生成资产包）
## 内含 2048×2048 生成纹样——带祥云雕花的石拱桥 + 雨丝 + 桥下水雾，真透明通道。
## 已提取为 `assets/scenery/level1/arch_bridge.png`（**1842×715 完整拱**：
## 原素材 y 707~1423 为桥体全高（两端桥台 + 拱顶齐全）、x 106~1943 为全跨；
## 顶部雨丝带（y<707）与底部水雾（y>1423）均已裁掉）。
## ⚠️ 用 PNG 不用 webp：同一张 PIL 无损 webp，CPU 解码（get_image）正常、
## 但 Compatibility 渲染器实测画成白块/碎片（2026-10-08 踩坑）；PNG 无此问题。
## ⚠️ 雨已抽成独立雨幕 `rain_near.png`/`rain_far.png`（CRainOverlay 全场铺），
## 桥贴图不带雨，避免下两场雨；水雾同理（用户定案「桥底的水雾去掉」）。
##
## 摆放模型：贴图按**统一像素比例**缩放（`TEXTURE_SCALE_PX`：素材 1px → 画布多少 px），
## 再让「贴图内的桥脚接地点」`texture_foot_px` 对齐到元素的 (anchor_x, anchor_y)。
## 这样贴图内部的雕花比例天然自洽，只需调一个缩放数即可整体放大缩小。
##
## 两条路并存（**不是二选一**）：
##   - `texture` 非空且资源可加载 → 贴图绘制
##   - `texture` 为空串（或资源缺失/headless）→ 回退程序化占位画法（见 CSceneryView）
## 这样断言与批跑不依赖贴图资源，画面上又能拿到真美术。
const SCENERY_TEX_BRIDGE: String = "res://assets/scenery/level1/arch_bridge.png"
## 柳树贴图（用户 2026-10-09 提供 `皮影美术素材/柳树.woop`）。
## 素材规格：woop@2 / plant-ornamental-013 / style pink-green，part 1472×1878。
## 已裁到内容包围盒 → `willow.png` = **1436×1846**（透明底、无雨丝、无水雾、
## 无地面底座——桥贴图的三条裁切教训此处直接规避）。
## 形态：自然垂柳（细干缓 S 曲、垂枝帘幕、柳叶披针形），画法与桥同族
## （皮影皮革质感：褐干 + 皮影绿树冠 + 青蓝分层 + 奶白雕边高光）。
const SCENERY_TEX_WILLOW: String = "res://assets/scenery/level1/willow.png"

## ══════════ 第二关「游园惊梦」布景贴图（用户 2026-10-11 提供三份woop） ══════════
## 参考构图：用户手绘/AI 参考图——门楼居**左半幅**（带屋檐、门扇、花窗），
## 菊石盆景在**最左**，柳枝从门右上垂下；三具影人在画面右侧。
## 三份素材都是 woop@2、**单件整图**（joints=0，无需拆件），已从 webp 转 PNG
## （Compatibility 渲染器上 webp 会画白块——与第一关同一条教训）。
const SCENERY_TEX_GATE: String = "res://assets/scenery/level2/gate.png"
const SCENERY_TEX_CHRYS: String = "res://assets/scenery/level2/chrysanthemum.png"
## 花篮（用户 2026-10-11 提供 `皮影美术素材/花篮.woop`）：
## `plant-ornamental-007` / style chinese，单件整图，裁到内容框 → **1403×1718**。
## 🔴 **同日撤下**：加入当天用户即定案移除，不再进 `items`（复用说明见 make_level2 注释）。
## 常量与贴图常量一并保留，便于日后复用。
const SCENERY_TEX_BASKET: String = "res://assets/scenery/level2/flower_basket.png"
const SCENERY_TEX_WILLOW_BRANCH: String = "res://assets/scenery/level2/willow_branch.png"

## ══════ 第二关**第二幕**「端阳饮酒 · 室内厅堂」素材（用户 2026-10-11 woop 包，8 件）══════
## 按用户成品图《端阳惊变幕景·成品.jpg》：立柱围出厅堂，圆桌居中，桌上摆酒具。
## 全部 woop@2 **单件整图**（joints=0），webp→PNG（compat 渲染器上 webp 画白块），
## 已裁到内容包围盒。
##
## ⚠️ 与第一幕（门楼版）**各自独立、互不覆盖**：第一幕 = `make_level2()`（编号 2），
## 本幕 = `make_level2_act2()`（编号 **22**）。两幕共用「第二关」这个剧情段，
## 但布景数据是两套——合并时不得把任一方塞进对方的函数里。
const SCENERY_TEX_COLUMN: String = "res://assets/scenery/level2b/column.png"  # 984×1893（原始素材，现不引用）
## 右柱用**水平翻转**版（用户 2026-10-12 手绘批注「这个需要镜像」）。
## Godot 4 的 `draw_texture_rect` 无 flip_h 参数，故离线镜像成独立 PNG，
## 不走运行时翻转，避开 compat 渲染器的坑。
const SCENERY_TEX_COLUMN_MIRROR: String = "res://assets/scenery/level2b/column_mirror.png"
##
## 🔴 2026-10-12（第二轮定案）：**立柱内侧剪掉，四个横梁保留**。
## 立柱素材自带一条**横贯两侧的雀替臂**（左侧伸到贴图 x=0、右侧伸到 x≈982），
## 「顶天立地」后这条内侧臂正压在横梁端头的位置上（上一版因此整条删了横梁，
## 是把「要剪的」认成了横梁——用户本轮澄清：**梁保留，剪的是柱内侧**）。
## 实测柱身 x 277~604，故把 x≥604 的部分（内侧雀替臂 + 柱础内侧一小段）整条剪掉，
## 保留：柱身 + 深褐**梁头**（贴图 x 334~590，完整保住）+ 外侧雀替臂。
## 剪后 604×1893，**离线切图**再入库——`draw_texture_rect_region` 在 compat 渲染器上
## 画白块（2026-10-08 已验），运行时裁不可用，与 column_mirror 同一条教训。
const SCENERY_TEX_COLUMN_CUT: String = "res://assets/scenery/level2b/column_cut.png"  # 604×1893
const SCENERY_TEX_COLUMN_MIRROR_CUT: String = (
	"res://assets/scenery/level2b/column_mirror_cut.png"
)  # 604×1893 = 上者的水平镜像
## 横梁（**保留**四根）：1762×369，四根等分铺满柱间净宽（见 LEVEL2_BEAM_* 常量）。
const SCENERY_TEX_BEAM: String = "res://assets/scenery/level2b/beam.png"
const SCENERY_TEX_FLOWERPOT: String = "res://assets/scenery/level2b/flowerpot.png"  # 1109×1848
const SCENERY_TEX_TABLE: String = "res://assets/scenery/level2b/table.png"  # 1895×1937
const SCENERY_TEX_STOOL: String = "res://assets/scenery/level2b/stool.png"  # 1401×1281
const SCENERY_TEX_VASE: String = "res://assets/scenery/level2b/vase.png"  # 867×1795（当前未进 items）
const SCENERY_TEX_WINE_POT: String = "res://assets/scenery/level2b/wine_pot.png"  # 1289×1430
## 酒杯原素材 `wine_cup.png`（1661×730）**内含一对杯**（绿釉 + 朱红），
## 按 x=854 的透明空隙切开并各自裁框 → 下面两张。原图保留不删。
const SCENERY_TEX_WINE_CUP_GREEN: String = "res://assets/scenery/level2b/wine_cup_green.png"  # 823×728
const SCENERY_TEX_WINE_CUP_RED: String = "res://assets/scenery/level2b/wine_cup_red.png"  # 779×722

## ══════ 第三关《盗仙草》素材 ══════
## 一座山：`plant-ornamental-020` / style chinese，**单件整图**（joints=0），
## webp→PNG 并裁 bbox → **1494×1754**（宽高比 0.852）。
## 画面内容：昆仑山峰、峰顶殿宇、古松绕崖、云海翻涌——与 PRD「昆仑山、云雾、
## 古松与仙草剪影构成山景」逐项对上，**一件顶三件**，不再另加云/松/草（会重叠打架）。
const SCENERY_TEX_MOUNTAIN: String = "res://assets/scenery/level3/mountain.png"

## —— 第二关三件布景的定位常量（全部由「参考图目测 → 幕布归一化」推出）——
##
## 🔴 2026-10-11 用户三次调整：**门楼放大 1/4（×1.25），其余景物一同调整**
## （即全组统一放大 1.25 倍，保持「树与房屋等高」的比例关系不变）。
## 三次调整的沿革：门楼 549 → ×2/3=366 → ×1.25= **458px**。
##
## 门楼：`architecture-008`，素材 **1870×1314**（横式建筑，宽高比 1.423）。
## 高 366 → **458px**，宽随之 651px。scale = 458/1314 = **0.348174**；
## foot 取**底边左点**（建筑贴图的锚点惯例与树相反，建筑靠左对齐更可控）。
## 左缘 x=109px（贴幕布左边距），底 y=661px（贴地）。
const LEVEL2_GATE_SCALE: float = 0.348174
const LEVEL2_GATE_X: float = 0.056700  # 左缘 109px 归一化
const LEVEL2_GATE_BASE_Y: float = 0.612037  ## 底座 y=661px（贴地，与菊石同一地平线）

## 菊花：`plant-ornamental-005`（墨绿），素材 **1020×1807**（竖式，含底座山石）。
## 原高 368 → 缩到 0.36 = 132 → **×1.25 = 165px**。scale = 165/1807 = **0.091312**；
## foot 取**底边中心**（花盆正中，竖式花木与树同惯例）。
const LEVEL2_CHRYS_SCALE: float = 0.091312
## 菊石仍在门楼左侧露出（几何上限见下），但缩小后露出比例更明显。
const LEVEL2_CHRYS_X: float = 0.061755  ## 左缘 72px（幕布左+6），露出 37px
const LEVEL2_CHRYS_BASE_Y: float = 0.612037  ## 底座 y=661px（**与门楼同一地平线**）

## 花篮（🔴 **已撤下**）：同日在门楼右侧试摆一版（放大 1.2 倍、间隙 15px），
## 用户当日定案移除。素材与常量保留在仓库里不删（删了要重新找美术），
## 要复用时把 `make_level2` 注释里的那段加回 `items` 即可。
const LEVEL2_BASKET_SCALE: float = 0.115250
const LEVEL2_BASKET_X: float = 0.445754  # 底边中心 → 左缘 775、右缘 937
const LEVEL2_BASKET_BASE_Y: float = 0.612037  ## 底 y=661px（贴地，与另三件同一线）

## 柳树（第二关为**整株立树**，非第一关那种小垂枝）：`plant-ornamental-013`（粉绿），
## 素材 **1377×1866**。
## 🔴 2026-10-11 用户调整：从「悬垂柳枝」改为「**右侧靠幕布边界的整株树**」，
## 大小与房屋相当；第三次随房屋一同放大 1.25 → 高 **458px**（= 门楼高度）、宽 338px。
## 右缘贴幕布右内边距 30px（右缘 1824），base_y 与门楼同地平线（661px，**贴地**）。
##
## ⚠️ `anchor_x` 是**锚点（贴图底边中心）**的归一化，**不是左缘**——第一版误按左缘填，
## 实测右缘只到 1689（差 135px），测试当场抓住。现按
## 「右缘 1824 = 幕布右 1854 − 内边距 30」反推。
const LEVEL2_TREE_SCALE: float = 0.245177  ## 458/1866
const LEVEL2_TREE_X: float = 0.862017  ## 底边中心 → 左缘 1486、右缘 1824
const LEVEL2_TREE_BASE_Y: float = 0.612037  ## 底 y=661px（贴地）

## —— 第二关**第二幕**「室内厅堂」定位常量（用户 2026-10-11~10-12 逐轮定案，v8 定稿）——
##
## 关卡编号：**22**。第二关第一幕是编号 2（门楼版，`act2_opening.gd` 在用），
## 第二幕必须另起一个键，否则两幕互相覆盖——这正是本文件把两幕拆成
## `make_level2()` / `make_level2_act2()` 两个函数、两个编号的原因。
const LEVEL2_ACT2_STAGE_ID: int = 22
##
## **六种**锚点高度**并存**（这是本幕与前两关最大的不同，`anchor_y` 是绝对归一化坐标）：
##   ① 贴地件：**桌 / 两凳 653.4**（地平线 0.605）
##   ② 花盆：**658.8**（0.61，第四轮定案——比地平线更低，唯一「更靠前」的贴地件）
##   ③ 桌上酒具：**432**（0.4，第三轮定案）
##   ④ 立柱：**680**（贴幕布下沿，顶天立地，高 566.4）
##   ⑤ 悬挂件·四根横梁：**梁顶 129.6 / 梁底 204.3**（第四轮定案 0.12 定高）
## 参考图上从左到右的布局（第四轮实测：柱内侧已剪、花盆左缘 0.15、两凳 0.4 / 0.6）：
##   左柱 66~246.7 │ 花盆 288~500.7（底 658.8）│ 左凳 698~838 │ 圆桌 834~1087（居中 960）
##   │ 右凳 1082~1222 │ 右柱 1673.3~1854（镜像贴图）；四根横梁 246.7~1673.3 铺满柱间。
const LEVEL2_ACT2_GROUND_Y: float = 0.605  ## 地平线 y=653.4px
## 立柱：**顶天立地**（顶离幕布上缘 21.6px、**底贴幕布下沿 680**），高 566.4。
## ⚠️ 立柱是**唯一不跟随地平线**的贴地件——它的底对齐幕布下边缘（680），
## 而其余贴地件走 653.4。两者差 26.6px 是用户确认过的取舍。
const LEVEL2_ACT2_COLUMN_BASE_Y: float = 0.629630  ## 柱底 y=680px（幕布下沿）
## 剪掉内侧后的柱贴图宽（原 984；内侧 x≥604 的雀替臂整条剪掉，见 SCENERY_TEX_COLUMN_CUT）
const LEVEL2_ACT2_COLUMN_TEX_W: float = 604.0
const LEVEL2_ACT2_COLUMN_SCALE: float = 0.299208  ## 高 566.4px（604×1893 剪后素材）
## 两柱**以幕布中心为轴对称**：左柱中心 + 右柱中心 = 2 × 幕布中心（断言按此写，
## 改幕布尺寸时自动成立，而不是各写死一个数）。
## ⚠️ `anchor_x` 是**贴图底边中心**（= 绘制矩形中心），不是边缘：
##   左柱矩形 66~246.7，中心 66 + 302×0.299208 = 156.36 → 0.081438；
##   右柱矩形 1673.3~1854，中心 1854 − 302×0.299208 = 1763.64 → 0.918563。
const LEVEL2_ACT2_COLUMN_LEFT_X: float = 0.081438  ## 左柱跨 66~246.7
const LEVEL2_ACT2_COLUMN_RIGHT_X: float = 0.918563  ## 右柱跨 1673.3~1854
##
## —— 横梁四根（用户 2026-10-12 第二轮定案：「**四个横梁保留**」）——
## 柱内侧剪掉后柱间净宽由 1199 变为 1426.6（1673.28 − 246.72），四根梁按 v7 立下的
## **同一公式**重新等分：单宽 1426.6/4 = 356.6px → scale = 356.6/1762 = **0.202406**。
## 即「梁随柱宽自适应」；纵向高度见下面这条（第三轮起**以梁顶为准**）。
##
## 🔴 用户 2026-10-12 第四轮：「**横梁移动到 0.12 的位置**」→ 梁顶 **129.6px**（上抬 32.4px）。
## 以「梁顶」为锚（第三轮起），梁底用「贴图高 × scale」推出——
## 换贴图 / 改梁宽时底边自动跟随，不会两处各写一个数而漂移：
##   梁顶 0.12 → **129.6px**；梁高 369 × 0.202406 = 74.7px → **梁底 204.3px**（0.189167）。
## 沿革：梁底 228.4（v7，以底边为锚）→ 梁顶 0.15 / 底 236.7（第三轮）→ 梁顶 0.12 / 底 204.3（本轮）。
## 位置校验：梁顶 129.6 距幕布上缘（92）37.6px、距柱顶（680 − 566.4 = 113.6）低 16.0px
## ——梁仍悬在柱头上方一段，未越幕布、未压柱头。
const LEVEL2_BEAM_SCALE: float = 0.202406  ## 单梁宽 356.6px、高 74.7px（1762×369）
const LEVEL2_BEAM_TEX_H: float = 369.0  ## 梁贴图高（1762×369）
const LEVEL2_BEAM_TOP_Y: float = 0.12  ## 梁顶 y=129.6px（用户第四轮定案）
const LEVEL2_BEAM_Y: float = (
	LEVEL2_BEAM_TOP_Y + LEVEL2_BEAM_TEX_H * LEVEL2_BEAM_SCALE / 1080.0
)  ## 梁底 = 梁顶 + 梁高 → 0.189167 → 204.3px（悬挂件，不接地平线）
const LEVEL2_BEAM_0_X: float = 0.221375  ## 跨 246.7~603.4
const LEVEL2_BEAM_1_X: float = 0.407125  ## 跨 603.4~960.0
const LEVEL2_BEAM_2_X: float = 0.592875  ## 跨 960.0~1316.6
const LEVEL2_BEAM_3_X: float = 0.778625  ## 跨 1316.6~1673.3
##
## 圆桌居中 = 幕布中心，同时是两凳的**对称轴**。
const LEVEL2_ACT2_TABLE_SCALE: float = 0.13354  ## 高 258.7px（1895×1937）
const LEVEL2_ACT2_TABLE_X: float = 0.5  ## 桌面中心 = 幕布中心 960px
## —— 桌面**最高水平面**：桌上酒具的底边一律对齐到这里（用户 2026-10-12 第二轮定案）——
## 桌贴图裁到内容包围盒后，**第 0 行就是桌面最高点**（桌面椭圆远边），
## 它在画布上的位置由桌子自身几何推出：
##   桌底 653.4（地平线） − 1937×0.13354 = **394.7px**
## 🔴 上一版把酒具锚在 595.6，比桌面最高面低 **200.9px**——酒具被画到了桌布下摆和桌腿上。
## 写成**表达式**而不是字面量：桌子挪位 / 改比例时酒具自动跟随，不会两处漂移。
const LEVEL2_ACT2_TABLE_TEX_H: float = 1937.0  ## 桌贴图高（1895×1937）
const LEVEL2_ACT2_TABLE_TOP_ROW_PX: float = 0.0  ## 贴图内「桌面最高行」的行号
const LEVEL2_ACT2_TABLE_TOP_Y: float = (
	(
		LEVEL2_ACT2_GROUND_Y * 1080.0
		- (LEVEL2_ACT2_TABLE_TEX_H - LEVEL2_ACT2_TABLE_TOP_ROW_PX) * LEVEL2_ACT2_TABLE_SCALE
	)
	/ 1080.0
)  ## = 0.365494 → 394.7px（断言会与桌面绘制矩形顶部比对）
const LEVEL2_ACT2_STOOL_SCALE: float = 0.099922  ## 高 128px、宽 140px（1401×1281）
## 🔴 用户 2026-10-12 第四轮：「**左侧凳子移动到 0.4 的位置，右侧凳子对称**」。
## 凳心（= `anchor_x`，贴图底边中心）由 0.366391 / 0.633609 改为 **0.4 / 0.6**
## → 凳心 768 / 1152px（和 = 1920 = 2×幕布中心，仍关于幕布中心对称）、
##    矩形 698.0~838.0 / 1082.0~1222.0（两凳**各向幕布中心挪 64.5px**，即更靠桌）。
## ⚠️ 这两个矩形与**桌子的包围盒**（833.5~1086.5）各相吻 4.5px，但**实际像素并不重叠**：
##   凳顶 525.4 以下的桌只剩中柱与腿基（该高度带实测桌宽仅 24~116px，落在 900~1018），
##   桌布下摆早在 y≈517 就收完。故测试按「桌在凳高度带内的**实际不透明像素跨度**」判定，
##   而不是包围盒——用包围盒判会误报（详见 c_test_scenery.gd 的 ⑦b）。
const LEVEL2_ACT2_STOOL_LEFT_X: float = 0.4  ## 左凳心 768px → 跨 698.0~838.0
const LEVEL2_ACT2_STOOL_RIGHT_X: float = 0.6  ## 右凳心 1152px → 跨 1082.0~1222.0
##
## 花盆：夹在左柱与圆桌之间。
## 🔴 用户 2026-10-12 第三轮：「**花盆最左侧**移动到 0.15」→ 最左缘 **288px**（原 390px）；
## 🔴 第四轮：「**花盆最下水平线下移到 0.61**，**稍微放大一点点**」。
##   ① 最下水平线（= 贴图底足）由地平线 653.4 单独下移到 **0.61 → 658.8px**（下沉 5.4px）。
##      ⚠️ 花盆从此**不再走地平线**——它是本幕唯一「落线比地平线更低」的贴地件（贴地件里
##        桌 / 两凳仍 653.4，立柱走幕布下沿 680）。用户要的是「花盆更靠前」的层次感，
##        不是几何错误，别再"顺手改回 GROUND_Y"。
##   ② 略微放大：`ZOOM = 1.05`（+5%，高 337.5 → **354.4px**、宽 202.5 → **212.7px**）。
##      「一点点」未给数值，此 5% 为 AI 取的档；要更大/更小只改这一个数（1.1 = +10%），
##      `SCALE` 与锚点、左缘都会自动跟随。
##   ③ **最左缘仍钉在 0.15（288px）**：放大向右长，不左移——第三轮那条约束继续成立，
##      与左柱右缘 246.7px 留 41.4px 间隙，压不到柱子。
## `anchor_x` 是**贴图底边中心**（foot 554,1848），故由「左缘」反推锚点：
##   anchor = 0.15×1920 + 554×0.1917615 = **394.2px** → 0.205331
## 写成表达式：以后改左缘目标或改缩放，锚点自动跟随（不再手算）。
const LEVEL2_ACT2_FLOWERPOT_FOOT_X: float = 554.0  ## 贴图内底边中心 x（素材 1109 宽）
const LEVEL2_ACT2_FLOWERPOT_LEFT_X: float = 0.15  ## 用户定案：最左缘归一化 0.15（288px）
const LEVEL2_ACT2_FLOWERPOT_BASE_Y: float = 0.61  ## 用户第四轮定案：最下水平线 y=658.8px
const LEVEL2_ACT2_FLOWERPOT_SCALE_BASE: float = 0.18263  ## 原比例：高 337.5px → 宽 202.5px
const LEVEL2_ACT2_FLOWERPOT_ZOOM: float = 1.05  ## 用户「稍微放大一点点」→ +5%
const LEVEL2_ACT2_FLOWERPOT_SCALE: float = (
	LEVEL2_ACT2_FLOWERPOT_SCALE_BASE * LEVEL2_ACT2_FLOWERPOT_ZOOM
)  ## = 0.191762 → 高 354.4px、宽 212.7px（1109×1848）
const LEVEL2_ACT2_FLOWERPOT_X: float = (
	(
		LEVEL2_ACT2_FLOWERPOT_LEFT_X * 1920.0
		+ LEVEL2_ACT2_FLOWERPOT_FOOT_X * LEVEL2_ACT2_FLOWERPOT_SCALE
	)
	/ 1920.0
)  ## 底边中心 394.2px → 左缘 288px、右缘 500.7px
##
## 桌上酒具：壶在左、两只杯并排在右（用户手绘图排序）。
## 🔴 用户 2026-10-12 第三轮：「**酒具对齐 0.4**」——三件的**最低水平面一律落在这条线上**：
##   0.4 → **432px**，位于桌面椭圆的中前部（桌面可见面 = 后沿 394.7 ~ 前沿 ≈446.2），
##   即「站在桌面上」；而上一版贴在**后沿 394.7**（`LEVEL2_ACT2_TABLE_TOP_Y`）是悬在桌缘上。
## ⚠️ 正因底边（432）落在**桌子绘制矩形之内**，酒具必须**画在桌子之后 → 图层在上**，
##   否则会被桌面盖住。`items` 数组顺序即绘制顺序（后画在上），见 make_level2_act2 的排序说明。
const LEVEL2_ACT2_WINE_BASE_Y: float = 0.4  ## 酒具最低水平面 y=432px
const LEVEL2_ACT2_POT_SCALE: float = 0.041958  ## 酒壶高 60px（1289×1430）
const LEVEL2_ACT2_POT_X: float = 0.476562  ## 跨 888~942
const LEVEL2_ACT2_CUP_GREEN_SCALE: float = 0.046703  ## 绿釉杯高 34px（823×728）
const LEVEL2_ACT2_CUP_GREEN_X: float = 0.507812  ## 跨 956~994
const LEVEL2_ACT2_CUP_RED_SCALE: float = 0.047091  ## 朱红杯高 34px（779×722）
const LEVEL2_ACT2_CUP_RED_X: float = 0.539062  ## 跨 1017~1053

## —— 第三关《盗仙草》定位常量：**一座山，顶天立地、紧靠最右侧**（用户 2026-10-12 定案）——
## 地平线取**幕布下沿 680**（第二幕是 653.4）。本关没有家具，不需要与谁共用地面线，
## 直接贴幕布底沿最稳。
const LEVEL3_GROUND_Y: float = 0.629630  ## 山底 y=680px（幕布下沿）
## 山高 = 幕布高 588px（山顶贴幕布顶 92、山脚贴幕布底 680，纵向满幅）。
## scale = 588/1754 = 0.335234 → 宽 = 1494×0.335234 ≈ 500.8px。
## 右缘内留 20px（右缘 1834）→ 底边中心 1583.6，**左侧 72% 刻意留空**给三位影人。
const LEVEL3_MOUNTAIN_SCALE: float = 0.335234  ## 高 588px（1494×1754）→ 宽 501px
const LEVEL3_MOUNTAIN_X: float = 0.824782  ## 底边中心 → 跨 1333~1834

## 贴图统一像素比例：素材 1 像素 = 画布多少像素。
## 0.42 → 完整拱素材 1842 宽 = 774 画布像素（幕布宽 1788 的 43%），
## 桥基中心锚在 x = 0.73 时桥跨约 1016~1787px，整体完整落在幕布内。
## 0.42 这个数来自用户 2026-10-08 三方案拍板选 C 时的体量判断，沿用至今。
const TEXTURE_SCALE_PX: float = 0.42

## —— 形状走向（决定贴图是否翻转，**不是**可自由变换）——
## 「景物只能左右平移」是硬约束；`polygon` 只是声明这条布景的走向语义，
## 且白名单只允许这两个值（断言会拦），保证素材不会被上下翻转/斜切。
const POLY_ARCH_SPAN: String = "arch_span"  ## 完整拱跨（桥下可过，青白二人可站在拱前后）
const POLY_ARCH_SIDE: String = "arch_side"  ## 半拱侧入（只露桥头 + 小半截桥身，延伸出画）

var stage_id: int = 1
## 布景元素列表。每条：
##   "id"       : String  元素标识（同一关内不得重复）
##   "kind"     : String  画法种类（见 KIND_* 常量）
##   "anchor_x" : float   水平定位，归一化 0–1
##   "anchor_y" : float   接地线高度，必须 ∈ [Y_MIN, Y_MAX]（放宽后即 [0, 1] 全舞台）
##   "pan_x"    : float   水平平移量（演出中唯一允许的位移），初始 0
##   "params"   : Dictionary  该种元素自己的形状参数（不参与通用校验）
var items: Array[Dictionary] = []


## 第一关布景：柳树 + 拱桥。
## 用户 2026-10-08 手绘草图起逐条修正，2026-10-09 第二次构图定稿：
##   - 柳树：树贴图左缘贴幕布左缘（内边距 30px → anchor_x 派生自 scale）、
##     **基线与桥底同线**（贴图底缘 662.8px → anchor_y 派生自 scale）、
##     **树高 529.2px = 0.9 × 幕布高**（2026-10-15 用户同日四轮定案，由 416px 上调；顶留白 41.6px、
##     右缘 507.66px——⚠️ 右缘已越过小青影身左缘 475.2px，A 侧站位判据线需重算）。
##     三个位置常量全是派生式，只依赖 LEVEL1_WILLOW_HEIGHT_PX，见各常量注。
##   - 拱桥 = 完整拱（用户 2026-10-09「桥头左移，使桥能够完整展现在幕布中」定案），
##     桥基中心 x = 0.73，桥跨 ≈1015~1788px 整体落在幕布内
##   - 三名影人的站位全部属 **A 侧数据**（`scripts/a/stage_def.gd`），本文件一律不动。
##     ⚠️ 这里**不写具体数值**：A 侧站位在 2026-10-15 当天已被改过三轮
##     （0.86/0.13/0.80 → 0.17/0.11/0.50 → 0.32/0.26/0.50），写在 C 侧只会立刻过期。
##     要看现值、要改站位，都读那份文件（原文本写的「白素贞 0.50 在桥头左侧」即属此类过期值）。
##   - **2026-10-15 两轮改动**：① 整关纵坐标净下移 90px（先定 95px 再上移 5px），
##     桥与柳同量下移，底缘 572.8px → 662.8px、同线关系不变；
##     ② 柳树树高 416px → **441px**（0.75 × 幕布高），底缘不动、树顶自 246.8px 升到 221.8px，
##     仍在幕布内不裁切（左右也不越界：柳 96~439px）
static func make_level1() -> CSceneryDef:
	var def := CSceneryDef.new()
	def.stage_id = 1
	def.items = [
		{
			"id": "willow_left",
			"kind": KIND_WILLOW,
			"anchor_x": LEVEL1_WILLOW_X,
			"anchor_y": LEVEL1_WILLOW_BASE_Y,
			"pan_x": 0.0,
			# 贴图（用户 2026-10-09 柳树.woop，自然垂柳形态）。空串即回退程序化占位画法。
			"texture": SCENERY_TEX_WILLOW,
			# 贴图内「树干接地点」的素材像素坐标（素材 1436×1846，左上为原点）。
			# 实测（2026-10-09）：裁切后最底 10 行不透明像素 x 423~704、中心 564，
			# 底边 y=1845（内容最底行）——树干底部中心对齐 (anchor_x, anchor_y)。
			"texture_foot_px": Vector2(564.0, 1845.0),
			# 逐资产缩放常量（见 LEVEL1_WILLOW_SCALE 注）；桥仍走全局 TEXTURE_SCALE_PX。
			"texture_scale_px": LEVEL1_WILLOW_SCALE,
			"params":
			# 树干高 / 树冠横向展开半径 / 树冠纵向半径，单位都是「画布高度比例」。
			# 树冠向左上展开：`crown_bias_x` 为负表示树冠中心在树干左侧。
			# 用户 2026-10-08：「树的长度要更高 0.05」→ trunk_height 0.20 → 0.25。
			{
				# 树冠跟着上移（其位置由 trunk_height 推出），因此整棵树变高、树冠顶更高。
				"trunk_height": 0.25,
				"crown_radius_x": 0.075,
				"crown_radius_y": 0.055,
				"crown_bias_x": -0.02,
			},
		},
		{
			# id 保留 `bridge_right`：它最初指「桥在整个画面的右侧」，与「露左半/右半」
			# 无关；完整拱定稿后桥仍在画面右侧。改名会牵动断言与探针的取用键，
			# 收益为零，故不动。
			"id": "bridge_right",
			"kind": KIND_ARCH_BRIDGE,
			"anchor_x": LEVEL1_BRIDGE_CENTER_X,
			"anchor_y": LEVEL1_GROUND_Y,
			"pan_x": 0.0,
			# 贴图（桥.woop，**完整拱**：两端桥台 + 拱顶齐全）。空串即回退程序化占位画法。
			"texture": SCENERY_TEX_BRIDGE,
			# 走向：完整拱跨（白名单既有值；桥下可过，人可站拱前后）。
			# 用户 2026-10-09 定案「桥头左移，使桥能够完整展现在幕布中」。
			"polygon": POLY_ARCH_SPAN,
			# 贴图内「桥基接地锚点」的素材像素坐标（素材 1842×715，左上为原点）。
			# 锚点 = 桥基（两桥台底）x 中心 921 + 桥台底边 y=714（内容最底行）：
			#   y 链条：原 2048² 素材桥体 y 707~1423 → 裁 (104,709)-(1946,1424) → 底行 714；
			#   x 链条：原素材桥体 x 106~1943（中心 ≈1024.5）→ 裁掉左 104px → 中心 ≈921。
			# 桥基中心精确落在 anchor_x=0.73，桥跨 ≈1015~1788px，整体完整入幕布。
			# ✅ 2026-10-09 几何探针实测（scratch/probe_scenery_geom.gd）：
			# 绘制矩形 x 1015~1788 / y 273~573，幕布 66~1854 / 92~680 → 四边越界量均为 0，
			# 左右余量 139px / 66px，整张（含左右两端桥台）完整显示、无半边裁切。
			# 用户曾观感以为只渲染了半边，实为桥整体偏右、左侧 66~1015（占幕布 53%）全空，
			# 并非裁剪 bug；桥的横向定位本轮未动。
			"texture_foot_px": Vector2(921.0, 714.0),
			"params":
			# 程序化占位画法用的形状参数（无贴图时生效；有贴图时被贴图取代）。
			{
				# 保留它们是为了 headless 批跑与断言不依赖贴图资源、且贴图缺失时画面不空。
				"arch_end_x": 1.0,
				# 桥面（拱顶）比接地线高多少。用户 2026-10-08 第三次定案：0.10 → 0.13。
				"deck_rise": 0.13,
				# 桥身厚度。用户 2026-10-08：「桥自身的厚度增加 0.03」→ 0.018 → 0.048。
				"deck_thickness": 0.048,
				"pier_width": 0.010,
			},
		},
	]
	return def


## 按关卡编号取布景数据。未知编号返回**空布景**（而不是给一关默认的），
## 免得「第 2 关没做」被静默顶替成第 1 关的布景、画面看着像做完了。
##
## 编号表（**第二关分两幕，各占一个编号**——两幕布景完全不同，不能共键）：
##   1  = 第一关《许仙借伞》         柳树 + 完整拱桥
##   2  = 第二关第一幕「法海劝酒」   门楼 + 菊石 + 柳树（`act2_opening.gd` 在用）
##   3  = 第三关《盗仙草》           一座山（顶天立地）
##   22 = 第二关第二幕「端阳饮酒」   室内厅堂九件（`LEVEL2_ACT2_STAGE_ID`）
##   其余（含 4）= 未实现 → 空布景
static func make_stage(stage_id: int) -> CSceneryDef:
	match stage_id:
		1:
			return make_level1()
		2:
			return make_level2()
		3:
			return make_level3()
		22:  # = LEVEL2_ACT2_STAGE_ID；此处写字面量：match 里用标识符会被当作绑定模式
			return make_level2_act2()
	var empty := CSceneryDef.new()
	empty.stage_id = stage_id
	return empty


## 第二关「游园惊梦」布景（用户 2026-10-11 定案）：门楼 + 菊花石 + 垂柳枝。
## 构图来自用户参考图：门楼占**左半幅**，菊石在最左，垂柳从门右上垂下；
## 画面右侧留给三具影人（人物站位归 A 侧，本文件一概不动）。
##
## ⚠️ 与第一关的两点差异（决定了本关的锚点取向）：
##   ① **不与桥同地平线**——第一关有桥，桥脚定义了 0.53 这条线；第二关没有桥，
##      门楼/菊石改为**贴幕布底缘**（base_y ≈ 0.59~0.61），避免出现「悬空的建筑」。
##   ② **柳枝是悬垂件**，底端不接地，故它的 base_y 明显高于另两件（0.3375）。
static func make_level2() -> CSceneryDef:
	var def := CSceneryDef.new()
	def.stage_id = 2
	def.items = [
		{
			"id": "gate",
			"kind": KIND_ARCH_BRIDGE,  # 复用建筑类回退画法；贴图存在时不会走到
			"anchor_x": LEVEL2_GATE_X,
			"anchor_y": LEVEL2_GATE_BASE_Y,
			"pan_x": 0.0,
			"texture": SCENERY_TEX_GATE,
			# 锚点 = 贴图**底边左点**（建筑惯例；树/花木用底边中心）。
			# 素材 1870×1314，foot 与 anchor 对齐 → 整门楼左缘即anchor_x。
			"texture_foot_px": Vector2(0.0, 1314.0),
			"texture_scale_px": LEVEL2_GATE_SCALE,
			"params": {"deck_rise": 0.10, "deck_thickness": 0.048, "arch_end_x": 0.45},
		},
		{
			"id": "chrysanthemum",
			"kind": KIND_WILLOW,  # 同上：有贴图不走回退
			"anchor_x": LEVEL2_CHRYS_X,
			"anchor_y": LEVEL2_CHRYS_BASE_Y,
			"pan_x": 0.0,
			"texture": SCENERY_TEX_CHRYS,
			# 锚点 = 贴图底边中心（花盆正中）。素材 1020×1807。
			"texture_foot_px": Vector2(510.0, 1807.0),
			"texture_scale_px": LEVEL2_CHRYS_SCALE,
			"params":
			{
				"trunk_height": 0.25,
				"crown_radius_x": 0.075,
				"crown_radius_y": 0.055,
				"crown_bias_x": 0.0
			},
		},
		# 🔴 花篮（flower_basket）已于 2026-11 用户定案**移除**：加入当天即撤下，
		# 「门的两侧对称摆两盆花」读起来太满，且与菊花的陪衬角色重复。
		# 素材 `assets/scenery/level2/flower_basket.png` 保留在仓库里（美术资产，
		# 删了要重新找素材），只是不再进 `items` —— 复用时把下面这段加回即可：
		#   {"id": "flower_basket", "kind": KIND_WILLOW,
		#    "anchor_x": LEVEL2_BASKET_X, "anchor_y": LEVEL2_BASKET_BASE_Y, "pan_x": 0.0,
		#    "texture": SCENERY_TEX_BASKET,
		#    "texture_foot_px": Vector2(701.0, 1718.0),
		#    "texture_scale_px": LEVEL2_BASKET_SCALE,
		#    "params": {"trunk_height": 0.25, "crown_radius_x": 0.075,
		#      "crown_radius_y": 0.055, "crown_bias_x": 0.0}},
		{
			# id 沿用 `willow_branch` 以免探针/断言的取用键改名；实际已是**整株立树**
			# （用户 2026-10-11 二次调整：从悬垂柳枝改为右侧靠幕布边界的树）。
			"id": "willow_branch",
			"kind": KIND_WILLOW,
			"anchor_x": LEVEL2_TREE_X,
			"anchor_y": LEVEL2_TREE_BASE_Y,
			"pan_x": 0.0,
			"texture": SCENERY_TEX_WILLOW_BRANCH,
			# 锚点 = 贴图**底边中心**（树干接地点）。素材 1377×1866。
			"texture_foot_px": Vector2(688.0, 1866.0),
			"texture_scale_px": LEVEL2_TREE_SCALE,
			"params":
			{
				"trunk_height": 0.25,
				"crown_radius_x": 0.075,
				"crown_radius_y": 0.055,
				"crown_bias_x": 0.0
			},
		},
	]
	return def


## 第二关**第二幕**「端阳饮酒」布景 —— **室内厅堂**（用户 2026-10-12 定案，v8）。
##
## 与第一幕（门楼版，编号 2）的关系：同属第二关剧情，但**布景是两套**，
## 第一幕在门外（门楼 + 菊石 + 柳树），第二幕进厅堂（立柱围合 + 桌椅酒具）。
## 因此各占一个编号：第一幕 2、第二幕 22。切幕时由 A 侧换编号，
## 本文件只保证「取 22 拿到厅堂、取 2 拿到门楼」。
##
## **本轮（2026-10-12 第四轮）的三处调整**（用户逐条给归一化坐标）：
##   ① 两凳**各向幕布中心挪 64.5px**：左凳心 0.366391 → **0.4**（768px）、右凳心 → **0.6**（1152px，对称）。
##   ② 花盆**最下水平线** 653.4 → **0.61（658.8px）**，并**放大 5%**（高 337.5 → 354.4px）；
##      最左缘仍钉 0.15（288px）不动；放大向右长。
##   ③ 横梁**梁顶** 0.15 → **0.12**（162.0 → **129.6px**，上抬 32.4px）；梁底随之 236.7 → **204.3px**。
##
## **第三轮（沿用）**：① 横梁改以**梁顶**定高（底边由梁高推出）；② 花盆最左缘 → 0.15；
##   ③ 酒具落线 → 0.4（432px，桌面椭圆中前部）→ 因底边落进桌子矩形之内，**酒具须排在 table 之后**
##      = 「图层在上，不要被桌子遮住」（见下方排序说明）。
## **第二轮（沿用）**：① 横梁四根恢复；② 立柱内侧剪掉（`column_cut`/`column_mirror_cut`，604×1893）；
##   ③ 酒具由 595.6 提到桌面。
## **v8（沿用）**：右柱镜像——手绘图右下批注「这个需要镜像」，右柱用水平翻转贴图。
##
## 结构沿革（仅供追溯，勿再当现状）：v3~v7 = 柱×2 / 梁×4 / 花盆 / 桌 / 凳×2 / 壶 / 杯×2 共 13 件；
## v8 = 误删横梁 → 9 件；第二轮回到 13 件；第三 / 第四轮件数仍是 **13 件**，只调各件的落点。
##
## ⚠️ **数组顺序 = 绘制顺序，后画者在上**（`CSceneryView._draw_items` 按 `items` 顺序直绘，
## 没有逐件 z_index）。所以「酒具要压在桌子之上」在实现上就是**把 wine_* 排在 table 之后**——
## 见 `_draw_order_covers_wine` 与 `_level2_act2_geometry` 里的绘制顺序断言。
##
## ⚠️ 两种 `kind` 只作「有贴图时不走回退画法」的占位（与第一幕同法）：
##   建筑/家具类（柱、桌、凳）用 `KIND_ARCH_BRIDGE`，花木/器物类（花盆、酒具）用
##   `KIND_WILLOW`。贴图在，两者都不会真的走程序化回退。
static func make_level2_act2() -> CSceneryDef:
	var def := CSceneryDef.new()
	def.stage_id = LEVEL2_ACT2_STAGE_ID
	def.items = [
		# —— 立柱成对：紧贴左右幕布，「顶天立地」（底贴幕布下沿，不随地平线）——
		# 🔴 2026-10-12 第二轮：用**剪掉内侧**的贴图（column_cut / column_mirror_cut），
		#    柱身内侧的雀替臂整条去掉，让横梁端头干净地接到柱身上。
		{
			"id": "column_left",
			"kind": KIND_ARCH_BRIDGE,
			"anchor_x": LEVEL2_ACT2_COLUMN_LEFT_X,
			"anchor_y": LEVEL2_ACT2_COLUMN_BASE_Y,
			"pan_x": 0.0,
			"texture": SCENERY_TEX_COLUMN_CUT,
			# 锚点 = 贴图底边中心。剪后 604×1893。
			"texture_foot_px": Vector2(302.0, 1893.0),
			"texture_scale_px": LEVEL2_ACT2_COLUMN_SCALE,
			"params": {},
		},
		{
			"id": "column_right",
			"kind": KIND_ARCH_BRIDGE,
			"anchor_x": LEVEL2_ACT2_COLUMN_RIGHT_X,
			"anchor_y": LEVEL2_ACT2_COLUMN_BASE_Y,
			"pan_x": 0.0,
			# 右柱用**水平翻转贴图**（用户手绘批注「这个需要镜像」）。
			# Godot 4 的 draw_texture_rect 无 flip_h 参数，故离线镜像成独立 PNG，
			# 不走运行时翻转，避开 compat 渲染器的坑。镜像只翻内容、不改几何，
			# 故左右两柱同宽同高（断言会比这一条）。
			"texture": SCENERY_TEX_COLUMN_MIRROR_CUT,
			"texture_foot_px": Vector2(302.0, 1893.0),
			"texture_scale_px": LEVEL2_ACT2_COLUMN_SCALE,
			"params": {},
		},
		# —— 横梁四根：等分铺满柱间净宽，**梁宽随柱宽自适应**（用户定案「四个横梁保留」）——
		{
			"id": "beam_0",
			"kind": KIND_ARCH_BRIDGE,
			"anchor_x": LEVEL2_BEAM_0_X,
			"anchor_y": LEVEL2_BEAM_Y,  # 悬挂：底边挂在柱间上部，不是地平线
			"pan_x": 0.0,
			"texture": SCENERY_TEX_BEAM,
			# 锚点 = 底边中心。素材 1762×369。
			"texture_foot_px": Vector2(881.0, 369.0),
			"texture_scale_px": LEVEL2_BEAM_SCALE,
			"params": {},
		},
		{
			"id": "beam_1",
			"kind": KIND_ARCH_BRIDGE,
			"anchor_x": LEVEL2_BEAM_1_X,
			"anchor_y": LEVEL2_BEAM_Y,
			"pan_x": 0.0,
			"texture": SCENERY_TEX_BEAM,
			"texture_foot_px": Vector2(881.0, 369.0),
			"texture_scale_px": LEVEL2_BEAM_SCALE,
			"params": {},
		},
		{
			"id": "beam_2",
			"kind": KIND_ARCH_BRIDGE,
			"anchor_x": LEVEL2_BEAM_2_X,
			"anchor_y": LEVEL2_BEAM_Y,
			"pan_x": 0.0,
			"texture": SCENERY_TEX_BEAM,
			"texture_foot_px": Vector2(881.0, 369.0),
			"texture_scale_px": LEVEL2_BEAM_SCALE,
			"params": {},
		},
		{
			"id": "beam_3",
			"kind": KIND_ARCH_BRIDGE,
			"anchor_x": LEVEL2_BEAM_3_X,
			"anchor_y": LEVEL2_BEAM_Y,
			"pan_x": 0.0,
			"texture": SCENERY_TEX_BEAM,
			"texture_foot_px": Vector2(881.0, 369.0),
			"texture_scale_px": LEVEL2_BEAM_SCALE,
			"params": {},
		},
		# —— 花盆：夹在左柱与圆桌之间。
		#    第四轮：**最下水平线 0.61（658.8px，比地平线低 5.4px）** + 放大 5%；最左缘仍 0.15 ——
		{
			"id": "flowerpot",
			"kind": KIND_WILLOW,
			"anchor_x": LEVEL2_ACT2_FLOWERPOT_X,
			"anchor_y": LEVEL2_ACT2_FLOWERPOT_BASE_Y,  # 0.61：本幕唯一「比地平线更低」的贴地件
			"pan_x": 0.0,
			"texture": SCENERY_TEX_FLOWERPOT,
			# 锚点 = 底边中心（花盆底足）。素材 1109×1848。
			# foot x 用常量，好与「左缘 → 锚点」的反推公式同源。
			"texture_foot_px": Vector2(LEVEL2_ACT2_FLOWERPOT_FOOT_X, 1848.0),
			"texture_scale_px": LEVEL2_ACT2_FLOWERPOT_SCALE,
			"params": {},
		},
		# —— 圆桌：居中，同时是两凳的对称轴 ——
		{
			"id": "table",
			"kind": KIND_ARCH_BRIDGE,
			"anchor_x": LEVEL2_ACT2_TABLE_X,
			"anchor_y": LEVEL2_ACT2_GROUND_Y,
			"pan_x": 0.0,
			"texture": SCENERY_TEX_TABLE,
			# 锚点 = 底边中心。素材 1895×1937。
			# ⚠️ 该素材**近似正方**且自带一张圆凳，桌面在贴图约 35% 处——
			# 桌面可用宽度 ≈ 桌绘制宽度（零左右余量），桌面道具总宽超过它就会溢出。
			"texture_foot_px": Vector2(947.0, 1937.0),
			"texture_scale_px": LEVEL2_ACT2_TABLE_SCALE,
			"params": {},
		},
		# —— 凳子成对：以圆桌为对称轴左右各一（第四轮：凳心 0.4 / 0.6）——
		{
			"id": "stool_left",
			"kind": KIND_ARCH_BRIDGE,
			"anchor_x": LEVEL2_ACT2_STOOL_LEFT_X,
			"anchor_y": LEVEL2_ACT2_GROUND_Y,
			"pan_x": 0.0,
			"texture": SCENERY_TEX_STOOL,
			# 锚点 = 底边中心（凳脚）。素材 1401×1281。
			"texture_foot_px": Vector2(700.0, 1281.0),
			"texture_scale_px": LEVEL2_ACT2_STOOL_SCALE,
			"params": {},
		},
		{
			"id": "stool_right",
			"kind": KIND_ARCH_BRIDGE,
			"anchor_x": LEVEL2_ACT2_STOOL_RIGHT_X,
			"anchor_y": LEVEL2_ACT2_GROUND_Y,
			"pan_x": 0.0,
			"texture": SCENERY_TEX_STOOL,
			"texture_foot_px": Vector2(700.0, 1281.0),
			"texture_scale_px": LEVEL2_ACT2_STOOL_SCALE,
			"params": {},
		},
		# —— 桌上三件：anchor_y = **酒具落线**（0.4 / 432px，见 LEVEL2_ACT2_WINE_BASE_Y），
		#    三件的「最低水平面」都落在同一条线上（用户第三轮定案）。
		#    🔴 **必须排在本数组的 table 之后**：绘制顺序 = 数组顺序，后画者在上；
		#    酒具底边（432）落在桌子矩形（394.7~653.4）之内，排在桌子之前就会被桌面盖住——
		#    用户原话：「且图层在上，不要被桌子遮住」。顺序由断言钉住，别随手调序。——
		{
			"id": "wine_pot",
			"kind": KIND_WILLOW,
			"anchor_x": LEVEL2_ACT2_POT_X,
			"anchor_y": LEVEL2_ACT2_WINE_BASE_Y,
			"pan_x": 0.0,
			"texture": SCENERY_TEX_WINE_POT,
			# 锚点 = 底边中心（壶底）。素材 1289×1430。
			"texture_foot_px": Vector2(644.0, 1430.0),
			"texture_scale_px": LEVEL2_ACT2_POT_SCALE,
			"params": {},
		},
		{
			"id": "wine_cup_green",
			"kind": KIND_WILLOW,
			"anchor_x": LEVEL2_ACT2_CUP_GREEN_X,
			"anchor_y": LEVEL2_ACT2_WINE_BASE_Y,
			"pan_x": 0.0,
			"texture": SCENERY_TEX_WINE_CUP_GREEN,
			# 锚点 = 底边中心（杯底）。素材 823×728。
			"texture_foot_px": Vector2(412.0, 728.0),
			"texture_scale_px": LEVEL2_ACT2_CUP_GREEN_SCALE,
			"params": {},
		},
		{
			"id": "wine_cup_red",
			"kind": KIND_WILLOW,
			"anchor_x": LEVEL2_ACT2_CUP_RED_X,
			"anchor_y": LEVEL2_ACT2_WINE_BASE_Y,
			"pan_x": 0.0,
			"texture": SCENERY_TEX_WINE_CUP_RED,
			# 锚点 = 底边中心（杯底）。素材 779×722。
			"texture_foot_px": Vector2(390.0, 722.0),
			"texture_scale_px": LEVEL2_ACT2_CUP_RED_SCALE,
			"params": {},
		},
	]
	return def


## 第三关《盗仙草》布景 —— **一座山，紧靠布景最右侧**（用户 2026-10-12 定案）。
##
## 本关布景**只有这一件**：PRD 写「昆仑山、云雾、古松与仙草剪影构成山景」，
## 而`山.woop` 这张贴图已把峰顶殿宇、古松、云海全画进去了——**一件顶三件**，
## 不再另加云/松/草，否则会与山体贴图里的同一元素重叠打架。
##
## 地平线用**幕布下沿 680**（第二幕是 653.4）。本关没有家具，不需要与谁共用
## 地面线，直接贴幕布底沿最稳。
##
## 画面左侧（约 72%）刻意留空——三位影人的活动区，山在右侧不压人。
## 山高 588 = 幕布全高（**顶天立地**：山顶贴幕布顶 92、山脚贴幕布底 680）。
static func make_level3() -> CSceneryDef:
	var def := CSceneryDef.new()
	def.stage_id = 3
	def.items = [
		{
			"id": "mountain",
			"kind": KIND_WILLOW,  # 有贴图不走回退；与花木同类
			"anchor_x": LEVEL3_MOUNTAIN_X,
			"anchor_y": LEVEL3_GROUND_Y,
			"pan_x": 0.0,
			"texture": SCENERY_TEX_MOUNTAIN,
			# 锚点 = 贴图底边中心（山脚正中）。素材 1494×1754。
			"texture_foot_px": Vector2(747.0, 1754.0),
			"texture_scale_px": LEVEL3_MOUNTAIN_SCALE,
			"params":
			{
				"trunk_height": 0.4,
				"crown_radius_x": 0.3,
				"crown_radius_y": 0.2,
				"crown_bias_x": 0.0
			},
		},
	]
	return def
