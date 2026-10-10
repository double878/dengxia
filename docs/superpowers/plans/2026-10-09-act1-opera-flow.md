# 第一关念白与唱腔接入实施计划

> 执行方式：在当前会话直接按切片推进，使用 executing-plans 工作流；默认不使用子智能体。每个切片验收后再进入下一切片。

**Goal:** 完成念白开场、配乐移步、到位入唱、实际接伞触发重音止乐、换乐游湖及还伞念白。

**Architecture:** 按已批准的改写台词制作新的唱念录音，分段验收后离线编排一条不循环的基础音轨；仅在器乐交接点暂停主轨并播放等待循环。接伞收锣为实际交接事件触发的一次性短音频，不重复放在基础轨。第一关流程由 StageDirector 管理，MusicClock 是唯一歌曲/真实时间源，交接许可由动作控制器执行。

**Tech Stack:** Godot 4.7.2 Standard、GDScript、内置音频节点、48 kHz / 16-bit PCM WAV；无新增第三方运行时插件。

**Design:** `docs/superpowers/specs/2026-10-09-act1-opera-flow-design.md`。

**2026-10-09 音源路线更新：**用户已批准 `docs/audio/2026-10-09-white-snake-source-adaptation.md` 的台词与角色表达方案，并要求执行。先试白素贞两句新词，再试许仙答句，试听通过后制作六句连续借伞段。旧 MiniMax 参考翻唱与 ACE-Step `only_lyrics` 样段仍为拒绝状态；新路线不能复用旧录音中的原词，也不以普通语音合成冒称戏曲唱念。

**2026-10-10 实际生成路线与最新决定：**本机 YingMusic-Singer-Plus 参考换词，固定作者源码 `baa409c2e7e5e775f09b4e92a220808f4827d2cc`、ModelScope 权重版本 `7443a818cb43c5ece9976a78ec8b625660bc522d`，Python 3.10.22 / PyTorch 2.6.0+cpu。乐亭 7 秒单句通过；后续双句因电音感和衔接生硬被用户判退。用户明确“算了，按照文档中的来吧”，恢复京剧《白蛇传·游湖》声音方向。京剧白素贞连续双句随后通过，继续小生许仙及六句连续段。Mureka 网页路线保持停止，旧实验记录保留；其他角色与完整编排未验收。证据见 `docs/audio/2026-10-10-yingmusic-single-line-experiment.md` 和 `docs/audio/2026-10-10-jingju-baisuzhen-pilot.md`。

## 全局约束与依赖

- 用户已选择 `BABAA`、`AAA`，随后批准新词路线。戏曲听感优先，字幕对应新录音实际台词；不以未通过的 AI 小样代替正式素材。
- 先确认工作区改动归属，再按 AGENTS.md 建立或继续连字符命名分支；本计划不授权覆盖现有改动。
- 不改第二、第三幕的玩法，不实现通用剧情系统，不增加幕前实时预览或自动代演。
- 各等待点最多一次、最多 8 秒，与同一动作的补救不能累计两次等待。
- 基础主轨关闭循环；菜单暂停冻结所有声音与双时钟。
- `D:/Godot/4.7.2/godot.exe` 已实际核对为 `4.7.2.stable.official.ed1daf0bf`，对应 `4.7.2.stable` 模板存在。2026-10-10 同步主干 C 侧代码后，导入、无头启动、Windows 导出均退出 0，日志为 `builds/stage-realism/logs/act1-opera-start-*`；启动仍有两项 ObjectDB 泄漏警告。新音频、操作和回放体验不由这些命令证明。
- 顺序依赖：音源样段 → 交接流程 → 播放器接入 → 完整第一关 → 收尾验证。主干已合入 C 侧 Recorder/Replay 与布景代码；第一关宿主尚未接线，需依据当前实际接口集成，不能把 C 的独立验证当作正式入口验收。
- 代码改完先解析，只跑相关切片；收尾再跑整套和工程门禁。单次问题三轮无实质进展就报告事实与卡点。

## 切片 1：新词音源制作与连续样段

**任务：**按已批准台词制作京剧旦角、小生角色声音小样，确认唱词与戏曲听感后，再制作念白、器乐、六句借伞及独立收锣，打磨连续音乐关系。

**当前进展：**京剧白素贞双句及许仙答句均已获用户确认。首版六句判退后，三组对应旋律及连续伴奏的修正版 01 已获整体试听通过；Q12 进一步确认末句“徨”字拖腔微调、即时／延迟接伞样段和三轮等待过门全部通过。Q13 通过三位角色念白参考；白素贞开场新词约 9.613 秒小样已生成，11 条工作/输出音频严格解码及波形核验通过，Q14 听感待确认。完整念白与接入尚未完成。记录见角色小样、六句对唱、交接编排和 `docs/audio/2026-10-10-jingju-speech-pilot.md`。

修正版 01 约 31.002 秒，整体试听状态为 `accepted_by_user`，用户原话“试听通过，再多一点尾音就好了，继续制作吧”。新尾音候选延长 350 ms，即时／延迟接伞样段约 55.352／59.692 秒，二者只差 4.340 秒等待。19 条工作/输出音频严格解码通过，主轨与一次收锣分开核验；Q12 已通过新增拖腔、器乐和三轮等待循环。Q13 随后确认三位角色的念白参考完整合适；先生成一条白素贞开场念白验证能力，再扩展其余台词。实际游戏、声卡同步、完整念白和正式音源冻结尚未完成。

**输入：**设计文档、已批准的来源与改写报告、角色声音方向、真实可调用的生成或录制工具及现有研究记录。参考演出供角色表达比较，不把未听辨的片段登记为已验证音色。

**输出：**`docs/audio/2026-10-09-act1-source-catalog.md`、`assets/audio/act1-opera/manifest.json`，以及 `builds/act1-opera-pilot/` 中的即时/延迟接伞连续样段和参数记录。

**约束：**不得沿用求取灵芝草原词充当借伞对白；不得编造 BPM、分轨或角色；不先改关卡数据来迁就未试听素材。

- [x] 白素贞“君子相怜情意厚／怎教你独受风凉”双句与许仙答句已分别通过用户试听。
- [x] 六句连续唱段整体试听通过；首版判退，连续参考修正版 01 获用户确认。末句拖腔的后续微调另行试听，不覆盖原通过版本。
- [ ] 保存新录音的歌词、风格、服务／模型、实际可核实的种子与完整参数；同一问题最多两次有明确原因的尝试，不批量重复无效路线。
- [ ] 使用完整解码确认格式、时长和峰值，保留原始下载与哈希；剪辑只动工作副本。
- [ ] 借伞唱段的台词只表达借伞请求/意愿，不在交接发生前宣告已接伞。
- [x] 制作两个样段：唱完立即接伞；唱完后额外等待，再接伞。两版都包含第二段器乐入口，并保留独立一次收锣。
- [x] 两个样段及三轮等待器乐实际试听通过；Q12 用户确认“三段都通过，继续制作念白”。
- [ ] 制作小青/白素贞开场念白和白素贞/许仙还伞念白候选；开场录音无连续配乐，角色声音与唱段协调。
- [ ] 试听通过后确定基础轨长度、段落接点、循环入口/出口和实际锣鼓节点，再冻结正式配置。

**素材记录字段：**`asset_id`、`source_url`、`source_part`、`source_start_ms`、`source_end_ms`、`role_ids`、`text`、`path`、`sha256`、`sample_rate_hz`、`channels`、`duration_ms`、`decode_verified`、`listening_result`、`rights_status`。循环素材另有 `loop_start_sample`、`loop_end_sample`、`safe_exit_samples`；基础轨另有阶段与对白标记。

**验收：**用户能听见自然的器乐—入唱—收腔—重音—止乐—换乐关系，真实唱词适配剧情，没有被截断的字头/尾腔和混入的原唱。未通过就只修正具体素材问题，不批量生成或推进正式接入。

## 切片 2：第一关交接许可与有限等待

**任务：**把第一关从旧固定交接拍点改为新版段落流程，保留现有操影和伞的几何判据。

**输入：**切片 1 冻结的阶段标记、当前影人状态、实际交接事件、MusicClock 双时钟。

**文件：**新增 `scripts/a/level1_opera_flow.gd`、`tests/a/test_level1_opera_flow.gd`、`tests/a/run_level1_opera_flow.gd`；修改 `scripts/a/stage_director.gd`、`stage_def.gd`、`umbrella_controller.gd`；扩展 `tests/a/test_umbrella.gd` 的稳定回归。

**输出接口：**

```gdscript
# Level1OperaFlow 的公开契约；由实现切片提供，不是当前已有接口。
func setup(markers: Dictionary, wait_limit_ms: int = 8000) -> void
func update(song_ms: int, real_ms: int, facts: Dictionary) -> void
func snapshot() -> Dictionary
func take_events() -> Array[Dictionary]

# UmbrellaController 的第一关流程许可。
func set_transfer_permissions(take_allowed: bool, return_allowed: bool) -> void
```

`facts` 必含 `in_join_window`、`holder_id`、`reached_turn_point`、`take_occurred`、`return_occurred`。`snapshot()` 返回 `phase_id`、`waiting_reason`、`wait_deadline_real_ms`、`take_allowed`、`return_allowed`、`finished`；不返回自行累计的时间。交接几何仍由 UmbrellaController 当帧复查。

- [ ] 先写行为回归：唱句未结束时，两手相接不换伞；开放许可后仍相接可立即换伞；先抬后放不能自动接伞。
- [ ] 写快到位/慢到位案例：快到位不截引子，慢到位只进一次等待，到位后只入唱一次。
- [ ] 写游湖案例：只有持伞到过小青身旁并向左返回才能还伞；返程念白依赖真实还伞；还伞后不再次开放借伞。
- [ ] 写等待边界：7999 毫秒尚可完成，8000 毫秒到期；当帧有效动作先于超时判定，重复更新不重复超时事件。
- [ ] 写菜单暂停和时间冻结案例，确保等待截止只看真实时间；同一动作不再叠加额外补救窗口。
- [ ] 实现最小状态转移；StageDirector 在伞更新前设许可、在交接事件产生后消费事实。
- [ ] 只替换第一关新流程的旧交接 Cue，保留其他关卡数据和行为；重新核对移步/抬手动作的实际锣鼓线索。
- [ ] StageDirector 统一以 `waiting_open OR remedy_open` 控制歌曲冻结，并分别产出等待/补救事件。

**定向测试入口：**

```gdscript
extends SceneTree

func _initialize() -> void:
    var result: Dictionary = preload("res://tests/a/test_level1_opera_flow.gd").new().run_all()
    quit(int(result["exit_code"]))
```

**验收：**上面的实际状态转移回归通过；伞归属永远由真实交接改变；新版接伞不再由旧固定拍点误报漏做。

## 切片 3：基础轨、等待过门与暂停续播

**任务：**把已验收音源接入现有音频模块和唯一时钟，先跑通移步至接伞这一段。

**输入：**切片 1 素材清单、切片 2 阶段/等待状态与真实交接事件。

**文件：**修改 `scripts/b/audio_score.gd`、`performance_audio.gd`、`scripts/a_test/level1_harness.gd`、`level1_a_scene.gd`；扩展 `tests/b/test_performance_audio.gd`；新增正式第一关素材至 `assets/audio/act1-opera/`。

**输出：**新版 `AudioScore` 配置、实际播放器、可读字幕与 `opera_*` / `audio_*` 事件。

- [ ] AudioScore 接受 `performance_mix` 主轨及按等待原因映射的过门，不强制交付五个虚假分轨；保留旧同步分轨路径用于现有测试/其他内容。
- [ ] 校验文件存在、采样率、主轨不循环、总长一致、段落/字幕范围、循环边界和可达安全出口；缺素材明确报错，不静默换回临时旋律。
- [ ] 创建主播放器、一路等待播放器和一次性收锣播放器，复用现有慢鼓播放器；等待/补救音乐按状态选择，不能同时重复发声。
- [ ] 对等待循环连续试听至少三轮。交回主轨时仅使用已标注接点和短释放，主轨从冻结位置续播。
- [ ] 实测演示机输出缓存及帧调度余裕，在对白前制作器乐保护区并将冻结点放在其起点；回归验证未到位时不会由已排队的音频提前漏出人声字头。
- [ ] 消费一次真实 `umbrella_take` 后，停止旧器乐等待、播放独立收锣并恢复基础轨至第二段音乐入口；第二段使用轻起音承接收锣。基础轨不含重复收锣，不能依赖“主轨恰好在重音前一刻暂停”来防止提前响锣。
- [ ] 针对音频缓冲越过冻结接点写回归：没有交接事件始终不触发收锣；重复投递同一交接事件也只触发一次。
- [ ] 暂停统一暂停主轨、过门、收锣、慢鼓、尾响和字幕；恢复不重启唱句、不重放重音、不重置真实时间。
- [ ] 第一关宿主不再启动 Metronome；重开/退出清理主轨、循环、许可和事件。
- [ ] 修改后的每个脚本先解析，再运行 `tests/b/run_performance_audio.gd` 及第一关定向入口；测试正常推进、等待、暂停、重开和重复事件。

**验收：**Windows 实际操作能听见同一段音乐顺畅入唱，接伞重音只一次，旧伴奏收住；提前抬手、延迟接伞、立即离开接伞区都符合设计。无头结果仅证明逻辑，不代替这个验收。

## 切片 4：游湖、还伞念白、收场与记录契约

**任务：**完成第一关正常路线和单一超时兜底，输出可被真实回放消费的记录。

**输入：**已接入的前半段、返程素材、真实伞状态和统一时钟。

**文件：**修改前述第一关流程、音频配置/宿主；按需要扩展 `scripts/a/music_clock.gd`；更新 `PRD.md`、`TECH_DESIGN.md` 和 `docs/handoff/A-to-B-level1.md` / `.contract.json` 的第一关条款。

- [ ] 游湖音乐从收锣后的已制作入口进入，覆盖持伞往返；允许提前还伞，但返程念白在安全乐句入口只播放一次。
- [ ] 增加无对白的短器乐兜底。超时只跳过依赖未完成动作的段落，不改变真实伞归属，不立即宣告失败。
- [ ] 若需跳段，在 MusicClock 增加 `skip_forward_ms(target_song_ms: int) -> void`：只允许前向、重定位主轨、更新播放位置基线，保留真实时间和暂停/冻结状态。禁止借用会调用 `start()` 的现有 `seek_ms()`。
- [ ] 跳段时将被跳过 Cue 标为未执行并退出其检测，不将其补成命中，也不成批开启补救。记录跳转前后歌曲位置。
- [ ] 宿主合并 A/B 事件后统一分配单调序号；事件和连续样本同时包含歌曲时间与真实时间。
- [ ] 更新第一关时长、固定时间轴例外、混合音源控制边界与自由交接评分规则；不覆盖 PRD 工作区其他修改。
- [ ] 新增正式回归：无接伞/无还伞可收场、8 秒不叠加、前向跳段不重置真实时间、同歌曲时间下多次动作样本顺序不丢失。

**验收：**完整第一关可玩到收场；返程念白仅在真实还伞后出现；稀有超时路径不死锁、不自动代演。音频事件足以说明等待长度、字幕变化、交接与跳段；真实回放模块未接入时明确保留该集成项。

## 切片 5：最终检查与 Windows 验收

**任务：**确认最终变更仅涉及本功能，并检查可玩、可听与导出证据。

**输出：**`docs/audio/2026-10-09-act1-opera-validation.md`，记录版本、素材版本、命令退出码、人工结果与未覆盖项。

- [ ] 检查任务文件 diff；清理本任务临时测试产物，保留正式回归，不删除已有小青临时文件。
- [ ] 代码先运行解析检查，再跑相关定向入口；通过后仅在切片收尾跑整套 A/B 测试。
- [ ] 使用同一个已核对的 godot.exe 执行下列工程门禁，保存 stdout、stderr、退出码与导出文件证据。

```powershell
& 'D:/Godot/4.7.2/godot.exe' --headless --path . --check-only --script res://scripts/a/level1_opera_flow.gd
& 'D:/Godot/4.7.2/godot.exe' --headless --path . --script res://tests/a/run_level1_opera_flow.gd
& 'D:/Godot/4.7.2/godot.exe' --headless --path . --script res://tests/b/run_performance_audio.gd
& 'D:/Godot/4.7.2/godot.exe' --headless --path . --script res://tests/a/run_tests.gd
& 'D:/Godot/4.7.2/godot.exe' --headless --path . --import
& 'D:/Godot/4.7.2/godot.exe' --headless --path . --quit-after 60
& 'D:/Godot/4.7.2/godot.exe' --headless --path . --export-release 'Windows Desktop' 'builds/dengxia.exe'
```

- [ ] Windows 逐项试听设计文档的十条验收，重点覆盖唱字/拖腔中暂停、等待中继续移动、即时接伞、延迟接伞、立即持伞离开、退出后无循环声。
- [ ] Recorder/Replay 实际接入后，比对原演出与幕前回放的真实时长、等待中的移动、伞归属、唱句/念白与重音顺序；只提供事件契约时不能报告此项通过。
- [ ] 按 AGENTS.md 检查、暂存本切片文件，并按已确认的 Git 协作流程提交/推送；不使用 `git add -A`。

**结束条件：**每个必需切片的验收均有实际证据，所有播放器能正常收尾，未完成的回放集成或音源条件单独列出。不能以解析通过、解码通过或文档写完代替声音效果通过。

## 本次文档交付的验证范围

已核对当前源码/入口、旧音频配置、时钟冻结/seek 行为及登记音源文件存在。当前仅新增设计与计划；上述新接口、回归入口和素材均属于实施产物，不是本轮已经存在或已经运行的结果。
