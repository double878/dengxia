# 京剧念白新词能力实验

日期：2026-10-10。用户已通过六句唱段、末句尾音微调及即时／延迟接伞音乐样段，并要求继续制作念白。三位角色原念白参考已由 Q13 确认“三段都完整合适，继续改词”；白素贞开场新词随后由 Q14 确认“通过，按这个方向继续其他念白”。该结论只证明这一句的新词念白可用，其余角色与较长对白另行制作和听验。

## 参考与台词边界

来源为同场[央视《白蛇传·游湖》](https://tv.cctv.com/2020/07/02/VIDEGhi9Sw6SpdWEg573OBfO200702.shtml)，原媒体 SHA-256 `fa8740a1f82066fe704954f0c4de91450bc8a20734c282a407228795aea89569`。画面字幕提供初步转录，随后用户试听确认三段台词与边界；不把字幕当作独立音频听辨。

| 角色 | 原媒体区间 ms | 参考原词 | 原参考 WAV SHA-256 |
| --- | --- | --- | --- |
| 白素贞 | 318000–327600 | 青妹，你来看，这就是有名的断桥了。 | `51bbedf69e25ed1faceefa2475e44ae04ee5f3da9baf87f62bfe76952b04bc7c` |
| 小青 | 332700–337900 | 姐姐，既叫断桥，怎么桥没断呢？ | `51bfdfeb62ac3073f511a98ac80b89b9f0abf9d81900e22e745700858f88ca72` |
| 许仙 | 1046400–1052700 | 明日一定奉访。小姐慢走。 | `09af7d99b05c1b771707b1c73423fc0178e123150309246ae148fe485cc80b70` |

文件位于 `builds/act1-jingju-speech/original-*-speech-02.wav`，48 kHz、双声道、16-bit PCM。最初 01 裁剪经相邻帧检查缩窄为 02，01 没有展示或获批准，不用作模型输入。边界图、固定媒体哈希与 Q13 原话在 `reference-candidates-02.json` 中保留。

先将三段排成 23.5 秒工作音频，每段后 800 ms 无字间隔，一次加载既有 MelBandRoformer，CPU 分离背景，按原区间分回各角色。内部用时 101.640 秒，限时执行器用时 108.703 秒、退出 0；输出为实际分离人声和移除背景，不用原混音复制成分轨。来源低码率与分离残余仍可能影响听感。

## 最小新词实验

试白素贞已批准开场台词：

> 青妹，你看，柳色映着湖波，果然是好风光。

复用本机 YingMusic-Singer-Plus，作者源码 `baa409c2e7e5e775f09b4e92a220808f4827d2cc`、ModelScope 权重 `7443a818cb43c5ece9976a78ec8b625660bc522d`、Python 3.10.22 / PyTorch 2.6.0+cpu。白素贞分离后的念白同时作为音色和韵律参考；作者参数 `melody_audio_path` 接收此念白，但作者资料尚未证明这个歌唱模型可可靠生成戏曲念白，因此只运行一次能力小样。

种子 `2026101021`，32 步、CFG 3.0、t_shift 0.5、参考尾部静音 0.5 秒、句级对齐。不给输出加伴奏、混响、变速或变调；48 kHz / 16-bit PCM 试听版只做重采样及必要固定衰减。同一问题最多两次有明确原因的尝试，不批量调参。

制作脚本为 `builds/act1-jingju-speech/run_speech_pilot.py`，参考、生成分别限时 300 秒；请求为 `speech-pilot-request.json`。原词是输入参考，不作为游戏开场成品。

实际命令：

```powershell
& 'builds/audio-tools/Scripts/python.exe' -m py_compile 'builds/act1-jingju-speech/run_speech_pilot.py'
& 'builds/audio-tools/Scripts/python.exe' 'builds/act1-jingju-speech/run_speech_pilot.py' separate
& 'builds/audio-tools/Scripts/python.exe' 'builds/act1-jingju-speech/run_speech_pilot.py' generate
```

三条均已退出 0；生成内部加载加推理用时 73.766 秒，限时执行器 85.161 秒。新词原始生成与试听版为：

| 文件 | 格式与时长 | SHA-256 |
| --- | --- | --- |
| `baisuzhen-opening-speech-pilot-01-raw.wav` | 44.1 kHz、双声道 FLOAT；423936 帧、9613.061224 ms | `29aac34c41489cae895db518e9430f21e8e58577d57221622f89b8332ec775ac` |
| `baisuzhen-opening-speech-pilot-01.wav` | 48 kHz、双声道 16-bit PCM；461427 帧、9613.0625 ms | `c650f86bb2b2bf6741324195aaad5aec56a763381cd9bfd101f421d0d88e72c9` |

试听版峰值 0.478760、固定增益 1.0。没有新增配乐或混响，未裁剪原始生成。

独立核验实际命令：

```powershell
& 'builds/act1-reference-experiment/runtime/Scripts/python.exe' -m py_compile 'builds/act1-jingju-speech/verify_speech_pilot.py'
& 'builds/act1-reference-experiment/runtime/Scripts/python.exe' 'builds/act1-jingju-speech/verify_speech_pilot.py'
```

均退出 0。三条原念白参考、六条分离输出及原始生成／试听版共 11 条音频重新核对哈希、格式、数值并执行 FFmpeg `-xerror` 严格完整解码，全数退出 0；16-bit PCM 无满幅样本。重建重采样试听波形与输出逐采样误差低于一个量化单位，证明没有额外添加伴奏或删去生成采样。

结构化证据为 `speech-separation-result.json`、`speech-pilot-generation-result.json`、`speech-pilot-verification.json`；已将小样提交为 Q14。以上只验证文件与处理，不代替戏曲念白、新词可懂度、语调与分离残余的听验。

新词试听必须确认：确实念出整句，保持旦角说白语调与停顿，没有变成唱段，没有电音或明显伴奏残余。通过后再继续小青、许仙和完整四句开场／九句还伞念白。当前 `speech_support_verified = false`、`game_integration_ready = false`，正式素材、时标、玩法与回放未接入。

Q14 已确认“通过，按这个方向继续其他念白”。结构化生成与验证记录同步 `accepted_by_user`、`speech_support_verified = true`，并注明仅白素贞该句已通过；早期 `false` 表示提交时的能力状态。扩展制作见 `2026-10-10-jingju-dialogue-production.md`，原小样复用而不重复推理。
