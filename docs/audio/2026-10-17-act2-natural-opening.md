# 第二关第一场自然对白

用户已认可 `法海慢速断句小样.wav`，并要求沿用生成并接入游戏。本轮覆盖之前的连续接唱版本。随后用户认可许仙“善/是”翘舌修订小样，并要求同样接入第一场；当前许仙制作来源以下文修订为准。

## 音画顺序

1. 进入第二关空台即播放用户 `4d581c8d224a06b09165d2a57003d266.mp4` 的完整音频一次。
2. 法海出树、许仙出门面对面迎接仍由玩家完成。音乐和实际迎接两条件都完成后，才从法海首句开始。
3. 六句对白无伴奏，按完整音频帧数编排字幕和轮次间隔；最后许仙应允，完整尾音后暗场、显示端阳卡、自动进入厅堂。
4. 菜单暂停冻结播放器及双时钟；缺场冻结对白。音乐播放期间不因人物出退场截断或重播，音乐播完后可静音等待。
5. 真实回放在零点就含开场音乐，按记录播放音乐、等待、对白、换幕和厅堂。

## 台词

| 角色 | 台词 |
| --- | --- |
| 法海 | 许施主。你家娘子，并非凡人。贫僧今日，正是为此而来。 |
| 许仙 | 我娘子心地善良，怎会是妖？ |
| 法海 | 人妖有别。莫被她的温情，蒙蔽了双眼。 |
| 许仙 | 大师这样说，可有凭据？ |
| 法海 | 端午将至。你劝她，喝杯雄黄酒。是人是妖。一试，便知。 |
| 许仙 | 这，我便劝她一杯。若是无事，还请大师莫再疑她。 |

## 制作与复用

- 法海身份为本轮用户提供的 `20261017-0717-27.5908446.mp4` 分离人声，视频 SHA-256：`d6a5a81adf561bb3ccfcfd8061828a8819c11341f7f44c03e2f8b08dfeb4c448`。复用已核验的分离缓存，保持普通说话语气。
- 首句逐字节复制用户认可的小样，SHA-256：`7e13574fd107ede34f539cb37c3fceb8ff223fc71be307c0bc2dee6c942f7bbf`，463212 帧、9.65025 秒，内部停顿为 650/850ms。
- 后两句分六个短语，F5 原生目标时长依次为 2.0、4.1、2.1、3.2、2.0、2.0 秒；实际帧数以生成文件为准。短语间显式加入 650/850ms 静音。
- F5 自然男声韵律参考沿用认可小样，文本为“对，这就是我，万人敬仰的太乙真人。”，32 步、CFG 2.0。Seed-VC 使用本轮法海身份，25 步、CFG 0.7、长度 1.0，关闭 F0 条件、自动 F0 和半音偏移。
- 许仙初版复用旧批次三条相同台词的完整交付 PCM，身份取第一关 `return-02/06/08.wav`。该初版已由下面的用户听验修订替换。
- 输出 48kHz 双声道 PCM16。只重采样和整句固定增益，无裁切、变调、后期强制变速或混响。视频音乐完整 PCM 直接保留。
- 本批输入、参数、中间件与日志在 `builds/act2-natural-opening-20261017/`。正式主轨、音乐及六句位于 `assets/audio/act2-opening/`；帧数、音源哈希、模型输入哈希、原生时长、种子和实际时标写入 `score.json`。

## 可复现装配和独立核验

使用 `builds/act1-reference-experiment/runtime/Scripts/python.exe` 运行 `tools/prepare_act2_natural_opening.py`，传入 `--batch builds/act2-natural-opening-20261017`、`--music-video` 用户原视频绝对路径和 `--ffmpeg` 本机已有的 FFmpeg。

`tools/check_act2_natural_opening.py` 从原视频独立解码并逐采样比较完整开场音乐，验证认可小样哈希、全部单句在主轨中的逐采样完整性、字幕帧数、静音、PCM 峰值及导入保护设置。`check_audio.py` 检查完整解码、格式与峰值；自动转写仅作疑似错词诊断。

## 验证与听验边界

已执行以下验证，日志保存在 `builds/stage-realism/logs/natural-*.out.log/.err.log`，音频审计与 Windows 报告在本批 builds 目录。

- 固定 `D:/Godot/4.7.2/godot.exe`，实际版本 `4.7.2.stable.official.ed1daf0bf`，对应 Windows 导出模板存在。
- 修改脚本及测试先运行 `--headless --path . --check-only --script <文件>`，均退出 0。
- `check_act2_natural_opening.py`：8 资源、完整音乐 380928 帧、主轨 2237091 帧（46.6060625 秒）、6 句完整对白、字幕/静音/首句哈希均通过。音乐时长 7.936 秒。
- `check_audio.py`：8 文件完整解码、48k 双声道 PCM16、无满幅剪切，通过。
- 定向回归：`run_act2_dialogue.gd` 47/47，`run_act2_music_cues.gd` 26/26，`run_act2_opening.gd` 169/169，`run_act2_entrances.gd` 28/28，`run_act2_hall_audio.gd` 20/20，`run_act2_actions.gd` 86/86，`run_act2_replay.gd` 无头 60/60。
- 通用回归：`tests/a/run_tests.gd` 1284 条及自然对白 22 条断言，`tests/c/run_tests_c.gd` 464 条断言，0 失败。
- Windows/WASAPI：`tests/b/run_act2_original_graphics.gd`（保留旧入口名）37/37，实际覆盖空台音乐、音乐完整结束再对白、全部六句混音、暂停静音及双时钟冻结、误退场续播、暗场清场、晚到不重播音乐和从首句开口。
- Windows 真实幕前回放：`tests/c/run_act2_replay.gd -- realtime` 104/104，记录 130551ms，实际播放 130593ms，包含两场、全部对白/唱段、动作等待静音与一次落地重音；回放暂停画面逐像素冻结且实际静音。此用例快速制作记录，另以 `tests/b/run_act2_intro_replay.gd` 对开场原音乐做实际完整录制与回放，不注入完成信号。
- 完整开场音乐实际录放：`tests/b/run_act2_intro_replay.gd` 513/513，7.936 秒音源实际记录至 8.017 秒（播放器缓冲/固定步检测误差约81ms），记录 8.367 秒并按原时长回放。现场与回放实际混音峰值均为 0.67043，空台期间对白时间始终为零，音乐结束后保持静音。
- 初次导入沿用了 Godot 默认 WAV 压缩，格式门禁发现后将新音源 `.wav.import` 的 `compress/mode` 固定为 0，重新导入与全部相关检查通过。未修改 `.godot` 缓存。
- 回放原短取样窗口只有 600ms，而用户视频前 600ms 自带静音，首次 entry 音量断言误报。独立波形定位后仅将 entry 取样延至 1.1 秒，保留完整原音源；复验 entry 实际混音峰值 0.383，其他对白/唱段/重音及暂停静音正常。
- `--headless --path . --import`、`--headless --path . --quit-after 60`、`--headless --path . --export-release "Windows Desktop" builds/dengxia.exe` 均退出 0。部分通用测试和无头快速退出仍输出对象/资源未释放诊断；未将退出码 0 描述为无警告。
- 导出的 `builds/dengxia.exe --headless --quit-after 60` 实际加载发布包启动，退出 0，仍有上述快速退出资源释放诊断。

自动转写逐句完成。它对低沉法海声音出现“断五/熊黄酒/四人四妖”等同音替换，对旧许仙缓存也有“大师/老师”等疑似识别差异，不能据此认证字音或代替听验。用户听验仅直接覆盖首句小样；其余新词沿用该方法，不将技术检查或自动转写宣称为逐句人耳认可。

## 许仙用户听验修订

- 用户在试听后认可原音色版本，并要求接入第二关第一幕。第一关已认可唱段不变。
- `dialogue-02.wav` 直接复制 `builds/act2-xuxian-retroflex-clear-20261017/许仙对白小样.wav`，SHA256 为 `122ad6246b0c039994c1a9b9d75321d56c7bf52c7c1bd5e1cc124df54e7284b1`，293679 帧 / 6.1183125 秒。保留全部声音和 650ms 句间停顿，不再增益或重新转换。
- 认可小样的原始音色来源是同一原许仙演员的干净参考 `builds/act1-jingju-xuxian-pilot/reference-vocals.wav`，SHA256 为 `7f0dfdf27e99c370523a4f3bbb103dca9a34074d3f614c59e2d72a1a36aef2f2`。这是认可小样实际使用的身份输入。另两句最终直接以用户认可的普通说话小样作为转换参考，保持相同角色身份并匹配普通对白发音；新词合成原声及其哈希保持不变。
- F5 自然男声参考、原生慢速与明确断句沿用认可小样的方法；新词 CFG 2.6、32 步，Seed-VC 25 步 / CFG .7，长度 1.0，关闭 F0 条件、自动 F0、半音偏移。只做重采样及整句固定增益，不剪字头字尾、不后期强制变速、不混响。
- 新批次 `builds/act2-xuxian-approved-20261017/` 保存请求、模型/参考哈希、短语音源、转换参数与 `delivery.json`。正式装配继续调用原装配器，增加 `--xuxian-batch builds/act2-xuxian-approved-20261017/content-guidance-revision2`；原 `--batch` 仍指向法海批次 `builds/act2-natural-opening-20261017`。
- 用户直接听验覆盖法海首句和许仙 `dialogue-02`，另外两句新许仙对白沿用其方法，自动转写与技术检查不等于逐句人耳认可。
- 字音保留核验后，三个疑点短语（xu04-b/xu06-a/xu06-b）的 Seed-VC CFG 调为 1.2，其他短语仍为 .7；源 PCM、种子、时长和说话身份不变。两次有原因的转换修订已结束，不继续参数扫描。
- 最终自动转写：dialogue-04 为“大师这样说，可有凭据”，文字一致；dialogue-06 对“这/是、劝/欠、若是/做事”仍有疑似差异，实际发音与自然度未获逐句人耳确认，不能把转写或格式检查宣称为听感通过。
- 当前主轨 2724808 帧 / 56.766833333 秒，三句许仙分别为 293679、265258、497763 帧；暗场和字幕均从实际 PCM 重建。

### 本次接入验证

- `python -X utf8 -m py_compile tools/prepare_act2_natural_opening.py tools/check_act2_natural_opening.py` 通过；没有修改运行时 GDScript 或场景。
- `check_act2_natural_opening.py` 独立审计 8 资源通过：认可许仙小样逐字节相同，六句对白逐样本完整，字幕、静音、暗场、完整音乐及无压缩导入设置一致。报告：`builds/act2-xuxian-approved-20261017/final-integration-audit.json`。
- `produce.py verify` 核对 62 个保护资源哈希：第一关、厅堂、音乐及三句法海均保持原样。
- 固定 `D:/Godot/4.7.2/godot.exe`，版本仍为 `4.7.2.stable.official.ed1daf0bf`；对应 Windows 模板存在。
- `tools/run_godot.ps1 -LogName xu-approved-dialogue --headless --path . --script res://tests/c/run_act2_dialogue.gd`：47/47。
- `tests/c/run_act2_replay.gd` 无头回归：60/60；Windows 快速验证：83/83。
- Windows `tests/b/run_act2_original_graphics.gd`：37/37，实际显示设备 Windows、音频驱动 WASAPI；覆盖空台完整音乐、六句对白输出、暂停静音、双时钟冻结、缺场续播、晚迎接及暗场。报告复制到本批 `windows-playback.json`；截图已检查，无新增布局问题。
- 真正按墙钟播放的 Windows 回放命令为 `tools/run_godot.ps1 -LogName xu-approved-replay-realtime -GodotArgs @('--path', '.', '--script', 'res://tests/c/run_act2_replay.gd', '--', 'realtime')`。进程命令行已确认包含 `-- realtime`，104/104；记录 140701ms，实际播放 140763ms，落地重音一次，全部台词/唱段混音存在。报告：本批 `realtime-replay.json`。首次位置参数调用中的 `--` 被 PowerShell 参数绑定消耗，只完成了快速验证，未将该次结果称为实时回放。
- 上述实时回放 stderr 出现 `WASAPI: GetBufferSize error` / `Current output_device invalidated`。内部混音及回放断言通过，但不能据此证明声卡设备在整个回放中连续输出；本轮保留这一设备限制，不宣称无警告。
- `--headless --path . --import` 和 `--headless --path . --quit-after 60` 均退出 0。启动及发布包快速退出仍有既有的 2 个 ObjectDB 实例、1 个资源未释放诊断。
- 默认 `builds/dengxia.exe` 正在运行，原路径导出被既有保护阻止，没有覆盖运行中的资源包。改为 `--headless --path . --export-release "Windows Desktop" builds/dengxia-xuxian-20261017.exe` 后退出 0；新 EXE/PCK 存在，实际发布包 `--headless --quit-after 60` 启动退出 0。试听须打开这个新版，当前旧版进程仍使用原 PCK。
- 本次使用 Godot 的 `AudioEffectCapture` 与真实 Windows/WASAPI 验证，未取得新的外部系统回录。初次 Python 回录辅助入口因当前 3.10 环境没有 `pyaudiowpatch` 未启动，随后使用现有 Godot 实播测试；未安装新依赖。
- 本次未重跑通用 A/C 全套及第三关独立回归。验证范围为本次声音资源、字幕时序、正式第一场和第二关整关录放，不将这些检查扩展为全部关卡重新验收。
