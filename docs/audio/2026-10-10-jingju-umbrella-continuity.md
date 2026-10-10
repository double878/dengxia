# 京剧借伞：尾音、等待与交接音乐样段

日期：2026-10-10。六句连续对答修正版 01 已通过用户整体试听；Q12 随后确认“三段都通过，继续制作念白”，尾音微调、即时／延迟接伞及三轮等待过门已通过试听。当前未修改 Godot 运行代码或正式音频资产，未执行实际游戏、声卡或回放验证。

## 目标与输入

用户确认“试听通过，再多一点尾音就好了，继续制作吧”，随后明确选择“末句‘徨’字稍多一点拖腔（推荐）”。目标是保持已通过的连续角色对答，稍延长末字，再验证“移步器乐 → 六句 → 接伞过门 → 独立一次收锣、旧乐停止 → 新器乐游湖”。即时接伞和延迟接伞两版都要包含新乐入口；等待过门连续播放三轮供检查。

唱段来自 `builds/act1-jingju-duet/six-lines-continuous-revision-01-*.wav`，混音 SHA-256 `23acea77efbd90da43a53d91bcbcb0b0967de6552b47cbbff92d2f96cba6eebd`。`continuous-revision-result.json`、`continuous-revision-verification.json` 已记录 `accepted_by_user` 和用户原话；原通过版本不覆盖。

器乐候选取自同场[央视《CCTV空中剧院》京剧《白蛇传·游湖》](https://tv.cctv.com/2020/07/02/VIDEGhi9Sw6SpdWEg573OBfO200702.shtml)，原媒体 SHA-256 `fa8740a1f82066fe704954f0c4de91450bc8a20734c282a407228795aea89569`，每次裁剪前重新核对。原音轨约 30 kbps AAC；重采样不会提高原始音质。

## 尾音与器乐候选

尾音处理从已通过六句第 30.100 秒开始，用 FFmpeg 的立体声 `atempo` 在保持音高的前提下延长末段 350 ms，人声和伴奏用同一时间比例 `0.720461238956`，编辑入口融合 25 ms。30.100 秒前的人声、伴奏与原文件逐采样一致；不重新生成唱词或全段变速。此为已录末字的时间伸缩，是否自然、是否保留“徨”字的合适拖腔仍需试听。末尾 RMS 活动估计约增加 310 ms，只是能量证据，不是字音定位或听感结论。

| 内容 | 原媒体区间 | 制作处理与当前边界 |
| --- | --- | --- |
| 移步器乐 | 00:46–00:52，46000–52000 ms | 固定衰减匹配伴奏能量；120 ms 轻起，180 ms 接入唱段 |
| 接伞等待过门 | 00:52–00:54.250，52000–54250 ms | 80 ms 首尾重叠，周期 2170 ms；连续三轮另存；音乐性与无人声待听 |
| 游湖器乐 | 11:52–12:10，712000–730000 ms | 280 ms 轻起承接收锣，550 ms 收尾；画面中为同场行船调度，不据此认定音频绝无喊声或人声 |
| 接伞收锣 | 项目原创候选，没有外部采样区间 | 12 个非谐性模态及短噪声冲击合成；固定 seed `2026101002`，1.6 秒；不是从实际演出取得的传统收锣，音色待试听 |

器乐不存在与否的听验结论尚未取得，统一 `voice_absence_verified = false`。候选视频画面辅助定位，不能以无字幕证明无人声；源 11:48 附近有“开船喽”字幕，本次游湖候选从 11:52 起，仍需听验排除余音。另存的 11:44–12:12 原始候选含这个范围，只供追溯，不用于样段。

独立收锣为确定性原创合成候选：基频 350 Hz、12 个模态比例、逐模态衰减和轻微音高展开，短噪声攻击；只构造一次起音。完全参数与实现保存在 `builds/act1-opera-continuity/assemble_continuity.py`，它是试听制作工具，不是游戏新依赖。收锣不写入样段的无重音主轨，只在模拟交接事件处混入试听版；后续运行仍由实际 `umbrella_take` 触发。

## 两版时间轴与输出

所有以下输出位于 `builds/act1-opera-continuity/`，48 kHz、双声道、16-bit PCM：

| 文件 | 时长 ms | SHA-256 |
| --- | ---: | --- |
| `duet-tail-01-mix.wav` | 31352.0625 | `71ae2a80fdfa9869a1ac401bdf32aa16f953f7e74af57322ab09fc8c11f3f375` |
| `wait-take-loop-01.wav` | 2170 | `97fb429b18f9e538f86798774799dec49c338f7ec8f2b941f634191324edf664` |
| `take-close-gong-01.wav` | 1600 | `5744854b80c3ff27ed028b9a8a3c76e55f4c45a1bdb9a88ced10bae22f6653c7` |
| `immediate-take-preview-01.wav` | 55352.0625 | `b7c26c822068c70b4c9a93d71df13328288fe08c6405a2fae8dd0c9250b11c2e` |
| `delayed-take-preview-01.wav` | 59692.0625 | `913058e9a5d5d926ccd84881d2a1d2329e45f66c7a4ab765140505fb0f5d3931` |

六句在两版都从 5.820 秒开始，37.1720625 秒完整结束；即时版在 37.2720625 秒模拟交接，延迟版在 41.6120625 秒模拟交接，多等两个完整循环、共 4.340 秒。旧过门在重音后释放 25 ms，新游湖音乐于重音后 80 ms 轻起。本次即时版约 55 秒是素材编排结果，未以旧 55 秒作为长度目标。

100 ms 唱段结束后的间距只用于离线试听，不是实际声卡缓冲保护区测量结果。冻结时标、事件起点、全部样本数与参数见 `continuity-result.json`。样段只有模拟一次接伞，没有假装实际用户已交伞，也没有开场或还伞念白。

另存两版 `*-take-main-01.wav`、`*-take-gong-track-01.wav`，分别为无独立收锣的主轨和一次收锣轨；试听混音 `*-take-preview-01.wav` 为两者相加。等待音轨另存 `wait-take-loop-three-cycles-01.wav`，三轮逐采样相同，供听爆音、节奏回绕与原唱残余。

## 实际验证与后续

执行命令：

```powershell
& 'builds/audio-tools/Scripts/python.exe' -m py_compile 'builds/act1-opera-continuity/assemble_continuity.py'
& 'builds/audio-tools/Scripts/python.exe' 'builds/act1-opera-continuity/assemble_continuity.py'
& 'builds/audio-tools/Scripts/python.exe' -m py_compile 'builds/act1-opera-continuity/verify_continuity.py'
& 'builds/audio-tools/Scripts/python.exe' 'builds/act1-opera-continuity/verify_continuity.py'
```

均退出 0。19 条工作/输出音频的哈希、格式、数值与 FFmpeg `-xerror` 严格完整解码均通过，PCM 无满幅样本。独立核验还确认：前 30.100 秒独立轨完全保留；尾段增加 16800 帧（350 ms）；三轮等待确为同一循环；每版独立收锣只在一次交接区间出现；主轨与收锣相加等于试听版；两版最早交接以前及扣除等待差后的内容逐采样相同。循环边界单采样差约 `0.00006103515625`，只证明幅值变化很小，不证明乐句或循环自然。

技术证据为 `continuity-verification.json`。`listening_result = pending`、`game_integration_ready = false`、`sound_card_guard_calibrated = false`。本次只做声音制作工具和候选，不改 Godot 运行工程，因此未重复 Godot 三项门禁；体验也不由已有门禁证明。

Q12 已确认“三段都通过，继续制作念白”。`continuity-result.json`、`continuity-verification.json` 已保存 `accepted_by_user` 和原话，器乐无人声结论以此次用户试听为依据；不能由源画面或数值检查推导。记录中 earlier `pending` 均描述提交时状态，当前以本段及结构化记录为准。

接下来验证开场四句、还伞九句戏曲念白，再制作完整基础轨与实际声卡保护区，最后冻结素材并进入玩法、播放器及真实 Recorder/Replay 接入。未取得戏曲念白能力证据前，不承诺普通 TTS 已能完成验收。
