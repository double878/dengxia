# 白素贞普通对白—唱段—普通对白对照小样

日期：2026-10-10。最新状态：**第二版参考原词小样获用户确认“自然、无电音，音色也一致”，对白自然度、无电音和唱说音色均通过听验；原唱段保留。** 第一版“对白不是很自然而且有电音”仍为历史判退；第二版通过不覆盖第一版结论。本次为离线能力实验，未接入游戏。

## 本轮已确认规则

用户选择 `1A 2A 3A 4A`、`5A 6A`：各角色保留自己的音色；该角色唱和说的音色须一致。有持续伴奏的台词演唱，无持续伴奏的台词以普通自然对话说出，不使用京剧念白语调。持续锣鼓也算伴奏，雨声、脚步声、单次收锣不算。整句或段落按预先配乐安排决定表达方式，短暂停顿、淡出或用户静音不触发唱说切换。

保留已通过角色唱声，让普通对白匹配唱声音色。先对白素贞制作“普通对白 → 已通过唱句 → 普通对白”小样，用户确认后才扩展角色。此要求覆盖本轮旧稿“无配乐仍使用京剧念白”的制作方向；不改写旧记录里的历史试听结论。

## 输入与实际方法

唱声音色和中间唱段来自 `builds/act1-jingju-pilot/generation-result.json`，其 `listening_result = accepted_by_user`。本次重新计算纯人声、原始生成和带伴奏唱段 SHA-256，全数与记录一致。

- 音色条件：已通过新词纯唱声 `baisuzhen-continuous-vocals-01.wav`，SHA-256 `1f1b08f70311e8e8da3a14f61317499ea23f0d8aa7b3ab7f755d521c87d16276`；参考文字“君子相怜情意厚／怎教你独受风凉”。
- 中间演唱：保留已通过带伴奏 `baisuzhen-continuous-mix-01.wav`，SHA-256 `26f23562042179dbb040d1c5299100131fcce5f385d37196c48246dea0509a42`，不重新生成、剪尾或变速。
- 普通语调条件：已安装 Windows `System.Speech` 的 `Microsoft Huihui Desktop`，`zh-CN`、语速 0，按两句已批准台词离线生成。两条输入为 22.05 kHz / 单声道 PCM，分别 5792.789 与 4773.560 ms。它只作为普通说话语调参考，不直接作为白素贞成品或混入试听。

复用本机 CPU YingMusic-Singer-Plus 及既有权重和环境；源码 `baa409c2e7e5e775f09b4e92a220808f4827d2cc`、权重来源版本 `7443a818cb43c5ece9976a78ec8b625660bc522d` 为既有实验记录的版本依据，本轮未重新下载或更换。作者入口确实分别接收音色和旋律音频，但 README 定位仍为歌唱生成，因此自然对白是能力实验，不能宣称官方已保证支持。

两句共加载一次模型、调用两次，种子 `2026101041`、`2026101042`。其余参数：32 步、CFG 3.0、t_shift 0.5、参考尾静音 0.5 秒、句级文字对齐。模型加载与两次生成内部共 144.218 秒，限时执行器共 173.911 秒，退出码 0；预算 300 秒。没有换种子重试，也没有修改作者源码。

对白原始输出完整保留；试听版仅重采样为 48 kHz / 双声道 / 16-bit PCM，两句固定增益均为 1.0，未额外加音乐、混响、变速或变调。不能由“未额外加音乐”推断生成器绝无残余音乐，仍需试听。

## 可试听输出

所有音频与请求、日志、可追溯制作入口都位于忽略目录 `builds/baisuzhen-speech-song-comparison/`。

| 小样位置 | 台词／内容 | 实际区间 ms |
| --- | --- | --- |
| 普通对白候选一 | 青妹，你看，柳色映着湖波，果然是好风光。 | 0–5805 |
| 停顿 | 零采样静音 | 5805–6305 |
| 原已通过唱段 | 君子相怜情意厚／怎教你独受风凉 | 6305–15314.354 |
| 停顿 | 零采样静音 | 15314.354–15814.354 |
| 普通对白候选二 | 君子，雨住了。这伞，奉还。 | 15814.354–20597.667 |

对白取已批准稿，本段仅把三个剧情位置串成声音对照，不是连续剧情或游戏内实际还伞证据。

| 文件 | 用途 | SHA-256 |
| --- | --- | --- |
| `baisuzhen-speech-song-speech-01-mix.wav` | 主试听：无配乐对白 → 原带伴奏演唱 → 无配乐对白 | `6b1af7a6a2b42fe5f2bc4d78f28ff4c08a67e875e545f1d5ed8674242ad40053` |
| `baisuzhen-speech-song-speech-01-vocals.wav` | 去掉中间伴奏供诊断音色；不是游戏编排 | `a301e56fe45f26c796e1c89ddca808d1d1804e426dd512a9a2b416e752725af9` |

两版均 48 kHz / 双声道 / 16-bit PCM，988688 帧，20597.666667 ms。完整保留三个输入段落采样，各插入 24000 帧即 500 ms 静音；没有对人声或唱段做淡入淡出。

## 实际验证

本轮首先执行 Python `py_compile` 与 PowerShell AST 解析，均通过；随后实际执行：

```powershell
& 'builds/baisuzhen-speech-song-comparison/synthesize_prosody.ps1'
& 'builds/audio-tools/Scripts/python.exe' 'builds/baisuzhen-speech-song-comparison/make_comparison.py' bounded-generate
& 'builds/audio-tools/Scripts/python.exe' 'builds/baisuzhen-speech-song-comparison/make_comparison.py' assemble
& 'builds/audio-tools/Scripts/python.exe' 'builds/baisuzhen-speech-song-comparison/verify_comparison.py'
```

均退出 0。核验入口独立重新读取 10 条输入/输出音频，哈希、元数据、有限采样与 FFmpeg `-xerror` 严格完整解码均通过，PCM 没有满幅采样。两版三个段落均与输入逐采样相同，两处间隔全部为零；已通过唱段未被重新处理。记录为 `comparison-verification.json`，状态 `technical_checks_passed_listening_pending`。

使用同一个 `D:/Godot/4.7.2/godot.exe` 执行项目规定门禁：

```powershell
& 'tools/run_godot.ps1' -LogName 'baisuzhen-comparison-import' --headless --path . --import
& 'tools/run_godot.ps1' -LogName 'baisuzhen-comparison-startup' --headless --path . --quit-after 60
& 'tools/run_godot.ps1' -LogName 'baisuzhen-comparison-export-quoted' --headless --path . --export-release '"Windows Desktop"' 'builds/dengxia.exe'
```

三项最终退出码均为 0；无头启动输出精确版本 `4.7.2.stable.official.ed1daf0bf`。首次导出将普通字符串 `'Windows Desktop'` 交给包装脚本，`Start-Process` 将其拆开，报 `Invalid export preset name: Windows`，退出 1；保留参数内引号后原预设导出成功，未修改包装脚本。日志在 `builds/stage-realism/logs/baisuzhen-comparison-*`。

未执行游戏内新对白播放、实际声卡测量、输入或 Recorder/Replay 验收。上述门禁不能证明声音或体验通过。

## 初次送听时的验收与范围

初次送听要求分别检查前后对白是否普通自然说话、每字完整、无电音或拖腔；唱段与前后对白是否保持同一白素贞音色。仅同一参考文件或使用同一模型不证明听感一致。首次送听时 `listening_result = pending`；用户反馈后已更新为判退，见下方诊断记录。当前 `natural_speech_verified = false`、`timbre_match_verified = false`、`game_integration_ready = false`。

本轮只新增本记录、制作计划及忽略目录中的候选/入口/证据；未修改已有工作区内容、Godot 运行代码、正式素材登记或历史听验。尚未形成通过听验的功能切片，未提交或推送。第一次候选送听后停止，等用户确认再扩大制作。

## 用户听验与定向诊断

用户明确反馈“对白不是很自然而且有电音，唱的很好”；本版本对白不得进入正式素材，唱段无需重做。再次试听原 Windows 普通语调参考后，用户确认“参考没有电音，但不自然”。这提供两个不同结论：语调输入自然度不足；用户报告的电音感在生成后出现，不能把两者合为“参考本身有电音”。

继续检查原始生成、重采样试听和连续拼接三层，只允许根据证据确定下一步，不批量调参。当前歌唱配置 `is_tts_pretrain = 0`，推理入口的同名函数参数并未进入执行逻辑；不能仅打开该参数就声称获得普通 TTS 支持。优先准备更自然的普通说话参考，并核对专用语音/音色转换入口；具体机制和候选听感尚未证明。

已实际执行 `diagnose_speech.py`（先 `py_compile`，再运行，均退出 0）：从原始浮点生成重建 48 kHz 重采样，再与试听 PCM 比较。两句最大误差分别为 `0.000030517345294356346`、`0.00003051733619940933`，均不超过一个 16-bit 量化单位 `1/32768`；PCM 无削波，两版拼接段落逐采样不变。由此排除后期额外效果、拼接改音与 PCM 饱和；不能单凭这些数值确定模型内部的电音机制。证据为 `speech-diagnosis.json`。

已将本轮 `generation-result.json`、`comparison-result.json`、`comparison-verification.json` 的试听字段更新为 `rejected_by_user_unnatural_speech_and_artifacts`，保留原技术检查和音频，不覆盖通过的唱段来源记录。用户没有逐句定位问题，两句只按整段判退，不编造每句各自的听验结果。

### 替代音源检查与停止点

- 将 `edge-tts 7.2.8` 及依赖安装到独立的 `neural-prosody/deps`，安装退出 0、30.335 秒，没有改动已有音频工具或歌唱模型环境。用 `zh-CN-XiaoxiaoNeural` 请求同一条台词，限制 45 秒；连接 `speech.platform.bing.com:443` 时报 `ClientConnectorError`／`WinError 64`，退出 1，未产生可播放声音。当前没有配置 HTTP/HTTPS 代理，没有据此盲目重试。
- 为专用语音模型检查 F5-TTS 作者仓库元数据：Hugging Face 请求连接超时；检查的 ModelScope 同名 ID `SWivid/F5-TTS` 返回 404、API Code `10010205001`。这些仅说明已检查入口没有取得权重，不代表 F5-TTS 或 ModelScope 全部不可用。
- Firecrawl CLI 已认证，执行一次带正文的下载入口搜索成功返回页面；返回内容没有确认可用于本轮中文普通对白的有效权重入口。缓存文件 `.firecrawl/f5-natural-speech-route-2026-10-10.json` 实际是 CLI 格式化文本，不能作为 JSON 解析或宣称已经得到模型。
- 同时阅读项目已缓存的 Seed-VC 作者 README 与 `inference.py`（快照提交 `51383efd921027683c89e5348211d93ff12ac2a8`），确认存在普通语音音色转换入口和 CPU 选择分支；这不是本轮已经加载或运行该模型的证据。所需声学模型、内容编码器和声码器尚未取得，不能保证对京剧唱声音色的匹配。

替代音源检查连续三轮未取得有效候选，按项目“超过 3 轮没有实质进展就停下来汇报”的约束停止。没有重跑 YingMusic、批量换种子或添加降噪来掩盖问题，没有新修正版音频。下一步应验证普通语音克隆/音色转换的专用模型，同时保留原唱段；能否达到同一角色音色仍须实际加载、单句生成和用户听验。当前卡点是取得可用的自然语音来源及专用模型入口，具体模型内部根因仍未证明。

### 诊断收尾检查

再次核对三个本轮结果文件均已记录对白判退，原已通过唱段的哈希及 `accepted_by_user` 状态不变；删除本次在线连接失败留下的 0 字节 MP3，避免被误当作新音频。文档无新增行尾空白，临时依赖仅在独立忽略目录，不修改既有环境。没有正式素材或游戏代码变更。

按项目要求又实际执行同一 Godot 的三项门禁，命令如下，均退出 0：

```powershell
& 'tools/run_godot.ps1' -LogName 'baisuzhen-speech-diagnosis-import' --headless --path . --import
& 'tools/run_godot.ps1' -LogName 'baisuzhen-speech-diagnosis-startup' --headless --path . --quit-after 60
& 'tools/run_godot.ps1' -LogName 'baisuzhen-speech-diagnosis-export' --headless --path . --export-release '"Windows Desktop"' 'builds/dengxia.exe'
```

启动 stderr 有 `2 ObjectDB instances were leaked at exit` 警告，未定位来源，未扩大到无关工程排查。上述门禁和诊断检查都不能代替声音听验；本轮普通对白仍失败，游戏内音频及回放未验证。

## 用户新增自然对白参考：《白蛇影》

用户提供 [《白蛇影（白蛇传与皮影戏的结合）》](https://www.bilibili.com/video/BV1uD4y1R7jH)，认为其中对白更加自然。将其登记为对白语气、停顿和节奏的参考；白素贞音色仍以已通过的唱声为准。用户没有指定台词或时间点，已通过异步问题请求定位；未自行确定具体说话人、单句边界或无伴奏区间。

已核对 Bilibili 公开页面和元数据：视频标题一致，作者“纯白辣条”，`bvid = BV1uD4y1R7jH`、`cid = 251924955`，元数据时长 329 秒。作者说明这是 Unity / Leap Motion 的交互课程作品；这些是页面事实，不据此推断录音者、配音方法或对白自然度。公开播放器接口返回的字幕和章节列表均为空；每 12 秒的画面检查也没有提供本次定位所需的台词字幕。

公开音视频取得于忽略目录 `builds/baisuzhen-speech-song-comparison/baisheying-reference/`，用于本轮参考分析。原视频 32567957 字节，SHA-256 `a97855573cb6580a7cfeef19490f7bcb22e94a70cf1a812857244e13c4e0265f`；原音轨 13114799 字节，SHA-256 `6d98cfb6cf48df33aaee6acf75233663add84a3942e22400d460586341cea95b`。公开页面与 API 缓存在 `.firecrawl/baisheying-natural-dialogue-*`。

复用了已有画面取样入口，生成两张场景时间图，仅用于定位；首次用轻量音频环境时缺少 Pillow，改用已含 Pillow 的既有模型环境即成功，没有安装新依赖。完整音轨执行 FFmpeg 解码检查，退出 0。另提取 `opening-0004-0044-context.wav`，明确为开头 4–44 秒的定位试听，保留原视频声音，非已核验的单角色、无音乐对白，也非生成成品。该片段为 48 kHz、双声道 PCM16、40 秒，SHA-256 `3ef5735798b768974ae1260e830c46df843f8404798029ec5309b6cd276dc061`；帧数、双声道、无 PCM 饱和及来源哈希检查通过。原已通过唱声音色参考哈希复核不变。证据为 `source-acquisition.json`、`reference-verification.json`，获取入口为 `acquire_reference.py`（先解析检查再执行，均退出 0）。

专用普通语音转换路线取得新证据：Seed-VC 作者配置经 `hf-mirror.com` 返回 200，其普通语音检查点 HEAD 返回 200，标示长度 440312082 字节。实际下载了小型配置，未下载模型检查点，也未安装或运行 Seed-VC。配置还要求 Whisper-small、CAMPPlus 和 BigVGAN；仅入口可达不能证明完整依赖可用、普通对白质量合格或与唱声音色一致。探针证据为 `.firecrawl/seed-vc-speech-route-probe.json`，配置为 `.firecrawl/seed-vc-speech-config.yml`。

当前状态：原对白判退有效，原唱声保留；已取得新参考，等待用户定位具体对白。尚无新的生成小样，未取得对白自然度或音色一致的通过听验，未接入正式素材或游戏。此轮仅参考分析与记录，没有新增 Godot 修改，未重复引擎门禁；此前门禁结果不作为本次参考听感的证据。

## 用户授权自行选句后的专用语音转换实验

用户回复“都可以的，你自己挑选一句”，无需继续请求句子选择许可。选取游湖开场白素贞候选对白“人世间竟有如此美丽的湖山”，原视频 7.7–11.1 秒，3.4 秒工作副本。该文字由完整语境和所选短句的 Whisper-small 自动转写一致支持；8 秒画面中戴冠女性张口、抬手，12 秒红衣女性开始下一轮动作，作为说话人语境依据。仍未将自动转写或画面证据冒称人工听辨通过。

为取得无伴奏工作副本，复用既有 MelBandRoformer，CPU 分离原视频 4–44 秒，共 225.718 秒，退出 0；输出 44.1 kHz 双声道 FLOAT，SHA-256 `fc538668d16fd598c8e0e68c6503488db1dbd75121bb943ea6f86df05d8b0131`。分离可引入变化，其对白自然度和分离听感仍待试听。

自动转写的时间戳不能直接作为剪辑边界：长段转写将开头静音计时处理错误，后一段还出现重复文本及超出输入长度的时间戳；原音轨带配乐的短段转写也出现与内容无关的文本，均不作为制作依据。通过 100 ms 窗口的实际分离人声能量查到第一句约 7.8 秒起声、10.8 秒结束，下一轮约 11.9 秒才开始；所选窗口前留约 100 ms、后留约 300 ms 静音。只取这一完整短句再次自动转写，得到“人世間竟有如此美麗的湖山”，简体转换后与长段首句一致。证据为 `selected-complete-line.json`、`opening-asr.json`、`first-dialogue-asr.json` 和 `first-dialogue-boundaries.png`，错误/部分转写结果保留，未覆盖或当作合格结果使用。

本次专用路线为 Seed-VC 普通语音配置，`f0_condition = false`。作者源码快照 `51383efd921027683c89e5348211d93ff12ac2a8` 的 75 个所需源码/配置文件按 Git blob SHA-1 核对，720251 字节；只额外安装 `munch==4.0.0` 到本次独立 `deps/`，复用既有 Python 3.10.22 / PyTorch 2.6.0+cpu，不更改既有环境。Python 导入检查通过。

实际取得 16 个模型/处理器文件；以下四个大文件大小及公开 LFS SHA-256 全数验证一致：

| 模型 | 固定版本 | 文件字节数 | SHA-256 |
| --- | --- | ---: | --- |
| Seed-VC 普通语音 | `257283f9f41585055e8f858fba4fd044e5caed6e` | 440312082 | `8ec8841b20bb46df9f7e8e570a6946a4b87b940133c7f0e778487ff33841f720` |
| Whisper-small | `973afd24965f72e36ca33b3055d56a652f456b4d` | 966995080 | `1d7734884874f1a1513ed9aa760a4f8e97aaa02fd6d93a3a85d27b2ae9ca596b` |
| BigVGAN 22 kHz | `633ff708ed5b74903e86ff1298cf4a98e921c513` | 449228171 | `e95ba25972d3de0628d99cd156e9315a9c018899bf739988959ebe3544080ced` |
| CAMPPlus | `e4b6ede7ce16997aff4ae69fbca1f0175e2afede` | 28036335 | `3388cf5fd3493c9ac9c69851d8e7a8badcfb4f3dc631020c4961371646d5ada8` |

下载过程中一次读取超时、两次达到 480 秒限制；每轮均取得实质增量，保留已完成数据块，仅补缺失数据，最终成功。未据此声称网络或完整语音模型已提前就绪。验证记录为 `weights-verification.json`，源码记录为 `source-acquisition.json`。

第一次严格加载在实际生成前失败：检查点的位置缓存为 8192，源码按 16384 重建；两个按公式计算的频率缓存不在旧检查点内；另有当前禁用的 F0 分支权重。对照作者原加载函数（按名称及形状过滤，非严格加载）后，适配入口明确校验位置缓存确为连续整数、缺失项确为 buffer、F0 条件确为关闭，再重建这些计算型缓存并移除未使用的 F0 项，其余权重仍按 `strict=True` 加载。没有修改作者源码或泛化忽略未知缺失项。运行使用 CPU float32、本地文件和 FLOAT 原始导出，保留诊断能力。

本次请求和入口位于 `builds/baisuzhen-speech-song-comparison/seed-vc-speech/`：`conversion-request.json`、`convert_reference.py`。参数冻结为 25 步、CFG 0.7、长度 1.0、无 F0 条件、无移调，种子 `2026101043`；实际语音转换以最终结果记录为准，加载失败不计作已生成候选。参考句原词只用于本次音色实验，未替换游戏台词。

本轮已实际执行以下 Godot 门禁，退出码均为 0：

```powershell
& 'tools/run_godot.ps1' -LogName 'baisuzhen-natural-vc-import' --headless --path . --import
& 'tools/run_godot.ps1' -LogName 'baisuzhen-natural-vc-startup' --headless --path . --quit-after 60
& 'tools/run_godot.ps1' -LogName 'baisuzhen-natural-vc-export' --headless --path . --export-release '"Windows Desktop"' 'builds/dengxia.exe'
```

启动仍有 `2 ObjectDB instances were leaked at exit` 警告。无新增 Godot 代码或正式音频素材，门禁不证明对白通过；未执行游戏内音频或回放听验。

### 第二版已生成、技术检查通过，等待听验

兼容处理后全部模块加载成功，最终仅执行一次语音转换，模型加载和转换共 45.750 秒，退出 0。原始输出 22.05 kHz / 单声道 FLOAT，74752 帧、3.390113 秒，峰值 0.288708，SHA-256 `c2e1a281ff4cd9c2cacf11d24bbe07afc3373ecc08c7d2a1a6355d963d3466fe`。原词来自选定真人对白，音色条件来自原已通过白素贞纯唱声；这不自动证明最终音色一致。

试听对白仅重采样至 48 kHz、单声道复制到双声道、PCM16 导出，固定增益 1.0，没有变调、变速或加混响。主对照 `baisuzhen-speech-song-speech-02-mix.wav` 共 805901 帧、16.789604 秒：新对白约 3.390 秒 → 500 ms 静音 → 原已通过完整唱段约 9.009 秒 → 500 ms 静音 → 重复同一句新对白。重复用于前后音色比较，非连续剧情。主对照 SHA-256 `632af1e4776f754ce00d2e3d5770459b481422c6d7bcef57159292cb2351e494`；诊断纯人声版 SHA-256 `f97d8473994ed54023b0710d98f8cf1d106c84cb64f4c91ab1463a5ad840d92d`。

实际执行 `assemble_comparison.py`、独立的 `verify_comparison.py`，均退出 0；此前修改的入口均先通过 `py_compile`。独立验证重新读取音频，FFmpeg 完整解码通过；格式为 48 kHz 双声道 PCM16；新对白无 PCM 削波；500 ms 停顿均为零采样；两个版本内的原唱段和重复对白逐采样保持对应输入不变。记录为 `generation-result-02.json`、`comparison-result-02.json`、`comparison-verification-02.json`。原视频所选 3.4 秒原声也单独保留为 `baisheying-baisuzhen-selected-original.wav`，供对照。

技术检查不判断自然度、电音或同一角色音色，当前三份结果的 `listening_result = pending`、`natural_speech_verified = false`、`timbre_match_verified = false`、`game_integration_ready = false`。第二版尚未获用户听验，原第一版的对白判退记录继续有效；不替换正式素材、不扩展角色、不提交“音频完成”的结论。

另对新对白单独自动转写，得到“人世間竟有如此美麗的湖山”，简体规范化后与所选源句相同，记录为 `converted-speech-asr.json`。这为词句保留提供自动检查证据，不替代用户对吐字、自然度或音色的判断。

### 第二版用户听验通过

用户在第二版约 17 秒唱说对照的反馈问题中明确回复：“自然、无电音，音色也一致”。已将第二版的 `generation-result-02.json`、`comparison-result-02.json`、`comparison-verification-02.json` 更新为 `listening_result = accepted_by_user`、`natural_speech_verified = true`、`timbre_match_verified = true`、`no_electronic_artifacts_verified_by_user = true`，保存原话和验收范围。再次计算对照音频和原纯唱声哈希，全数与送听记录一致。

通过范围仅为已选参考原词“人世间竟有如此美丽的湖山”的普通对白与原唱段衔接，未验证新游戏台词、其他角色或游戏内播放；`game_integration_ready = false` 保留。前文待听验字段是送听时的历史状态，最新状态以本段和更新后的结果文件为准。后续复用该基准制作原已确定的两句游戏对白，仍逐候选听验，不把基准通过外推为所有新音频通过。
