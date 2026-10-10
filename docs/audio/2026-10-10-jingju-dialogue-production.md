# 第一关四句开场与九句还伞念白制作

日期：2026-10-10。Q13 已确认三位角色原念白参考，Q14 已通过白素贞开场一句新词。四句开场技术核验通过，但 Q15 用户指出“小青的部分有些电音”，整体未通过；Q16 确认原始和分离参考均自然，仅生成的新词有电音。还伞九句已生成、编排并通过技术核验，提交为 Q17。Godot 运行代码和正式资产未修改。

## 制作约束

台词逐字保持 `2026-10-09-white-snake-source-adaptation.md` 已批准稿，开场四句、还伞九句共十三句。实际断言已核对请求里的十三句均原样出现在报告中、句号与角色唯一、只有白素贞开场第二句复用已通过小样；其余十二句各一次生成，不修改问名、相约和真实还伞后才说“奉还”的前置条件。

三角色参考、分离结果和作者模型来源均复用 `2026-10-10-jingju-speech-pilot.md`。种子、目标时长、表达意图与完整生成参数保存在 `builds/act1-jingju-speech/dialogue-request.json`。目标时长是制作选择，不是原演出事实或逐字时标；声学表达说明只记录创作意图，没有假装该模型支持情绪文字指令。

各句使用自己的角色纯人声念白作音色参考。韵律参考按新词长度用 FFmpeg `atempo` 调整到候选时长，比例超出 0.5–2 时拆成合法链；输入变速保持音高，生成输出不再整体变速。较短台词的语调移植仍需试听，不能因为字数匹配就说停顿自然。

参数仍为 32 步、CFG 3.0、t_shift 0.5、参考尾静音 0.5 秒、句级对齐。开场一次加载模型、三次生成，复用一条已通过人声；还伞一次加载模型、九次生成。CPU 分组顺序执行，避免两份模型抢占内存；开场限时 480 秒、还伞限时 900 秒，超时终止该子进程树。此处“子进程”是本机 Python，不使用子智能体。

## 开场输出与实际核验

开场生成内部用时 140.609 秒，限时执行器 152.776 秒、退出 0。四句均保留完整生成采样，句间只增加 380／330／360 ms 间距，开头 120 ms、末尾 400 ms 空白；不叠背景音乐、混响或对人声淡入淡出。对白开始时标是文件位置，不冒称每字时间已经对齐。

连续文件 `builds/act1-jingju-speech/opening-dialogue-01.wav`，48 kHz、双声道、16-bit PCM，1498497 帧、31218.6875 ms，峰值 0.558624；SHA-256 `8a52298d8bdbe7c8386e4bf77db38eed96d446d1dd894327a069b17477e09197`。

实际命令：

```powershell
& 'builds/audio-tools/Scripts/python.exe' -m py_compile 'builds/act1-jingju-speech/generate_dialogue.py' 'builds/act1-jingju-speech/bounded_dialogue.py'
& 'builds/audio-tools/Scripts/python.exe' 'builds/act1-jingju-speech/bounded_dialogue.py' opening
& 'builds/audio-tools/Scripts/python.exe' -m py_compile 'builds/act1-jingju-speech/assemble_dialogue.py' 'builds/act1-jingju-speech/verify_dialogue.py'
& 'builds/audio-tools/Scripts/python.exe' 'builds/act1-jingju-speech/assemble_dialogue.py' opening
& 'builds/act1-reference-experiment/runtime/Scripts/python.exe' 'builds/act1-jingju-speech/verify_dialogue.py' opening
```

均退出 0。三条韵律参考、四条原始生成、四条试听版及一条连续段共 12 条音频的哈希、格式、数值和 FFmpeg `-xerror` 严格完整解码均通过。16-bit PCM 没有满幅采样；重建重采样结果与逐句试听版差异小于一个量化单位，连续段各句逐采样完全匹配，句间只有所记录的零采样。证明未加配乐、未截生成字头或尾响；不能证明模型实际逐字念对。

参数与证据为 `opening-generation-result.json`、`opening-dialogue-result.json`、`opening-dialogue-verification.json`。用户已通过的第二句保持其通过状态；Q15 后整体标为 `rejected_by_user_xiaoqing_artifact`，小青两句不得进入正式素材。不能仅靠源码中的角色 ID 判断听感区别。

## 还伞与正式接入前的门槛

九句还伞已生成，内部用时 444.391 秒、执行器 457.784 秒、退出 0。生成器、编排与独立核验实际命令同上，分组参数改为 `return`，均退出 0。九条韵律输入、九条原始生成、九条试听版及连续段共 28 条音频严格解码和哈希检查通过，完整逐句采样保留、没有额外配乐；文字元数据与批准稿一致，但逐字可懂度仍待 Q17。

连续文件 `builds/act1-jingju-speech/return-dialogue-01.wav`，48 kHz、双声道、16-bit PCM，3045264 帧、63443 ms，峰值 0.683014，SHA-256 `0c8b073c8b368f56129bdaec46b5b3f597c8fa04d2fc11c6fdca26a14d69b37e`。句间停顿 400／450／450／450／500／450／550／550 ms，所有生成语音完整保留；停顿意图不能冒称模型已经表达出含蓄好感。

无配乐对白试听不证明实际游戏已还伞；宿主接入后必须由真实 `umbrella_return` 才进入这段，超时不能播放“奉还”。未改变三段通过的接伞音乐、独立一次收锣或等待上限。

## 小青电音感：定向修正

Q16 用户确认“参考都自然，只有生成的新词有电音”。技术核验已排除 PCM 削波、后期添加伴奏或混响、裁剪生成波形等处理，问题定位到生成或输入韵律条件，尚不能断定模型本身还是参考时间伸缩导致。诊断见 `xiaoqing-artifact-diagnosis.json`。

原两句小青输入把 5.2 秒参考分别延长到 8.2／7.2 秒。修正 01 先只试第一句，改回未拉长的 5.2 秒原念白韵律；目标词句、音色参考、种子 `2026101031` 与全部模型参数不变，避免同时改多个因素。生成时长较短，必须重新确认完整词句和语速，不能用电音减少但漏字的版本替换。

修正脚本 `retry_xiaoqing.py` 已通过解析，限时 300 秒，当前第一句修正执行中。同一问题最多两次有明确原因的修正；第一句通过后才用同一处理修正另一句，否则记录具体失败再决定下一步，不盲目换种子或批量调参。还伞段不含小青，因此其已完成的制作和 Q17 听验不必等待这条修正。

完整开场、唱段、接伞与还伞念白会形成比旧固定 55／70 秒更长的新第一关。按设计文档，第一个音源冻结点需用实长复核三幕总时长，不压缩第二、第三幕来掩盖超预算；完整录音未完成前不写虚假的最终时长。用户明确允许第一关脱离旧 55／60 秒上限，三幕五分钟预算仍需在冻结时处理。

全部对白听验通过后再制作完整基础轨、对白前声卡保护区、等待入口／出口及真实锣鼓动作标记，之后进入玩法和播放器。正式字幕必须对照实际念出的词句，当前元数据不能代替听辨或逐字对齐。尚未执行游戏内音频、输入、声卡测量和 Recorder/Replay 验收。
