# 第二关第一幕连续接唱交付

最终修订日期：2026-10-17。用户选择直接完成整幕并接入，补充“法海的不要改太多”。本记录覆盖前一版局部换声、出场静音方案。

## 最终行为

法海实际入场即播放参考第一集 45:30 附近的同源器乐；走出柳树及等待许仙迎接时持续循环。双方真实就位后，在器乐循环边界解除唯一 `MusicClock` 的主轨冻结，以 250ms 交叉淡化转入主轨器乐前奏及唱段。菜单暂停冻结双时钟及全部声音；对唱期间演员误退场仍沿用既有冻结机制。

法海七句全部使用原词原唱，不采用生成法海。开头“许施主不请到此地”取参考视频 45:34–45:52 的原唱，分离人声后与同段伴奏混回；后六句保留用户第二段视频整段 49.344 秒，不变速、不换声、不改词。法海后段只受统一总增益及头 40ms、尾 150ms 声音交叉淡化影响。

许仙两句整句生成：“原来金山寺老禅师”“此事容我归家思量”。身份参考取第一关已经交付的实际许仙唱声，字头与后续唱声使用同一个完整生成结果，不混回旧视频许仙人声。每句入口交叉淡化在测得的起音之前结束；人声统一增益，不对字头单独淡入。

全幕收腔后器乐自然收束，接既有 2 秒暗场及 1.5 秒章节卡换入厅堂。第一关、厅堂音频及厅堂惊倒重音保持原资源。

## 正式资源与时序

资源均为 48kHz、双声道、PCM16；导入保持 `trim=false`、`normalize=false`、`loop_mode=0`、`compress/mode=0`。出场循环由播放器设置，不改原文件的导入循环。

| 资源 | 帧数 | 时长 | SHA256 |
| --- | ---: | ---: | --- |
| `assets/audio/act2-opening/main.wav` | 5,345,394 | 111.362375s，含末尾 2 秒暗场 | `98af63b8714e3d0cadd885b8102ee9a1ecfcd9591b270f05eba0be5f27ee15de` |
| `assets/audio/act2-opening/entrance-loop.wav` | 184,800 | 3.85s | `1a11aceb78bf63ab0469e072c147334bc815a2ad115652cd58810bd4b352ee3a` |

清单 `score.json` 保存实际采样帧、9 条字幕、生成参数、来源散列、接头、总增益和身份参考。暗场起点为 109362ms，法海原视频后段在 40050ms 接入。统一总增益 0.6283001751185082，峰值 0.889984130859375，无削波。

| 角色 | 唱词 | 主轨范围 ms | 来源 |
| --- | --- | ---: | --- |
| 法海 | 许施主不请到此地 | 3881–19711 | 参考原唱 |
| 许仙 | 原来金山寺老禅师 | 22005–37903 | 第一关许仙身份参考生成 |
| 法海 | 可记得保和堂里点化你 | 40050–51300 | 用户第二段原唱 |
| 法海 | 说你被那妖魔缠 | 51300–58800 | 同上 |
| 法海 | 你妻本是妖蛇变 | 58800–65550 | 同上 |
| 法海 | 变化人形在你的身边 | 65550–73550 | 同上 |
| 法海 | 五月端阳可曾应验 | 73550–80300 | 同上 |
| 法海 | 现出原形在你的身边 | 80300–89394 | 同上 |
| 许仙 | 此事容我归家思量 | 89500–105352 | 第一关许仙身份参考生成 |

## 来源与复现

参考：[乐亭皮影戏《白蛇传》第一集，45:30](https://www.bilibili.com/video/BV1xX4y1Y7sJ/?p=1&t=2730)。本地完整母音轨为 `builds/real-performance-reference/乐亭白蛇传_第一集_原始参考.m4a`，SHA256 为 `a8d909b1a16ac2384f6d0f71c61a2169f5930189b05704aad28316c2084e9701`。实际分离 45:30–45:56；90 秒上下文只作定位。参考页面信息与原字幕画面仅用于核对出处和唱词，不充当听感证据。

本地制作目录：`builds/act2-sung-opening-20261016/`，由 Git 忽略，包含请求、原始 FLOAT 生成结果、分离结果、试听、审计 JSON 和 Windows 实播截图。

| 材料 | SHA256 |
| --- | --- |
| 45:15–46:45 上下文 WAV | `869f0ca5978fa94f49f9af11af9e904d93ef12e57177fb1f84084efd588ad9d2` |
| 45:30–45:56 分离人声 | `350d356fecf2df74129dd495fc67e715e4e8be793bb723c9e08aa0083292fac0` |
| 同段分离伴奏 | `0288b8a21ed806765c0330f8b89dabb7865c77536964d4a61b025d46cc4a77af` |
| 第一关许仙身份 WAV | `c3305ac7d68f3c0fe99df36851cbae988a6ec7bc2eeacc1f559e15d5fe0240eb` |
| 用户第二段 MP4（此前已核验） | `6f8fe55eee803528b9c9df89eeec0731e8e24f59414e5058f7f2d606fa49d769` |
| 第二段完整解码 PCM | `15fcbc6afc8b17e7c9cf38cd5bd3070feb5cf10f17ddc82c589d09339445feec` |

许仙身份来自 `builds/act1-opera-continuity/duet-tail-01-vocals.wav` 的 22.55 秒以后，参考词为“些小风雨何须讲｜请接此伞莫彷徨”，重采样到 44.1kHz。使用既有 YingMusic-Singer-Plus 离线环境：Python 3.10.22、PyTorch 2.6.0+cpu、模型提交 `baa409c2e7e5e775f09b4e92a220808f4827d2cc`、权重提交 `7443a818cb43c5ece9976a78ec8b625660bc522d`。许仙两句种子 2026101621/2026101622；32 步、CFG 3.0、t_shift 0.5、尾静音 0.5 秒、sentence_level 对齐。游戏无新增推理依赖。

本轮最终审计时，两份微信临时 MP4 已不在原路径。法海后段使用此前保存的 2,368,512 帧完整 PCM；其散列与上一版已独立重解码审计的散列现场比对一致。审计明确报告 `source_video_redecoded=false`、`source_pcm_matches_prior_independent_audit=true`，本轮不声称重新解码了已失效视频。制作器和审计器在源视频仍存在时核验原文件，失效时严格校验既有 PCM 散列。

制作及独立审计命令（工作区根目录）：

```powershell
& 'builds/act1-reference-experiment/runtime/Scripts/python.exe' -X utf8 tools/prepare_act2_sung_opening.py builds/act2-sung-opening-20261016 --output assets/audio/act2-opening
& 'builds/act1-reference-experiment/runtime/Scripts/python.exe' -X utf8 tools/check_act2_sung_opening.py builds/act2-sung-opening-20261016 --ffmpeg builds/audio-tools/Lib/site-packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe
```

## 验证记录

统一使用 `D:/Godot/4.7.2/godot.exe`，版本 `4.7.2.stable.official.ed1daf0bf` 和 `4.7.2.stable` 模板；所有游戏检查通过 `tools/run_godot.ps1` 记录真实退出码。日志位于 `builds/stage-realism/logs/sung-final-*.out.log` 与对应 stderr。

| 检查 | 最终版结果 |
| --- | --- |
| Python 制作器/审计器编译 | 通过 |
| 独立音频审计 | 7 条法海原唱、2 个许仙字头、58 个第一关/厅堂文件不变；0 削波；PCM 误差不超过 1/32768 |
| 资源导入 `--headless --path . --import` | 退出 0 |
| 最终对白测试解析 `--check-only` | 退出 0；其余改动脚本此前已逐文件解析通过 |
| `tests/c/run_act2_dialogue.gd`，无头 | 51 项，0 失败 |
| `tests/c/run_act2_music_cues.gd`，无头 | 14 项，0 失败 |
| `tests/c/run_act2_opening.gd`，无头 | 169 项，0 失败 |
| `tests/c/run_act2_replay.gd`，无头 | 59 项，0 失败；195284ms、11719 个快照、73 个事件 |
| Windows 完整实播 | Windows/WASAPI，27 项，0 失败；整轨播放、字幕与暗场完成 |
| Windows 幕前回放声音探针 | Windows/WASAPI，82 项，0 失败；195301ms、11720 个快照、73 个事件 |
| 无头启动 `--headless --path . --quit-after 60` | 退出 0；退出资源释放告警见下文 |
| Windows 导出及导出 EXE 图形启动 | 导出退出 0；导出 EXE 在 Windows/OpenGL 图形环境默认入口启动 60 帧后退出 0，stderr 为空 |

Windows 完整实播使用 `tests/b/run_act2_original_graphics.gd`，验证出场立即有声、迎接器乐连续/主轨冻结、循环边界接唱、全部字幕/声音输出、接头暂停静音与双时钟冻结、完整尾音及暗场清场。回放使用 `tests/c/run_act2_replay.gd`，快速生成完整真实状态记录，再在 Windows 音频设备采集实际回放输出、暂停恢复及离开静音；这不等同于完整整关人耳试听。

Windows 证据分别保存在 `builds/act2-sung-opening-20261016/windows-playback.json` 与 `builds/act2-replay/windows-audio.json`。回放出场/对白/对唱/倒地重音/补救采集峰值分别约 0.4223/0.6616/0.2621/0.7859/0.1047，取杯等待峰值为 0；暂停静音、画面冻结及恢复继续通过。

补充法海开头独立审计时，最初直接用重采样后的 float64 原人声计算理论混音，忽略了制作器先保存 FLOAT/float32 中间人声，出现 26 个采样比 PCM16 量化上界最多多约 1.1e-8 的误报。核对中间保存误差最大 5.96e-8 后，改为先限制该误差，再按实际保存的人声核验混音；音频未重新制作，PCM16 上界未放宽。最终法海开头最大误差 0.000030517335638025056，后段最大误差 0.00003051615947846642，均小于 1/32768。

无头默认入口退出报告 2 个 ObjectDB 实例及 1 个仍使用的资源；同类告警也存在于本轮之前的 `baseline-startup.err.log`、`audio-cleanup-startup.err.log` 等记录。本轮未修复这一既有退出清理问题，不能将该项称为无告警通过。最终 Windows 图形实播、回放、导出和导出 EXE 启动的 stderr 均为空。

通过包装脚本执行导出时，预设名须连同双引号传入，避免 `Start-Process` 拆开带空格的参数；首次未保留引号时报告无效预设 `Windows`，随后以下命令成功：

```powershell
.\tools\run_godot.ps1 -LogName sung-final-export --headless --path . --export-release '"Windows Desktop"' 'builds/dengxia.exe'
```

最终本地交付散列（导出资源包需与 EXE 一起保留）：

| 文件 | SHA256 |
| --- | --- |
| `builds/dengxia.exe` | `4a9eaded8955ef789ab02651ed9d2dde80328fbb342bd2a6db4db33e86305668` |
| `builds/dengxia.pck` | `680f0dd29314be7c2ef916a4fc93dd4ecee0ace42206dac4502dce6a6c528a0d` |
| `builds/act2-sung-opening-20261016/opening-preview.wav` | `fc0838e6c8d499778557c47b4c5980be76d255f129b781bdbae99aadce23d3fe` |

技术检查不证明许仙咬字、音色相似度或听感连贯性已获人工认可。戏曲 ASR 在原参考和生成结果上均有明显识别幻觉，未作为唱词通过证据。正式清单与审计均保留 `human_listening_verified=false`；最终听感需用户试听。
