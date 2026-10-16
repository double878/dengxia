# 第二关第一幕许仙音色与原声接入记录

2026-10-16。按用户最终要求，第一关沿用原有许仙音色；将本轮两段视频中的许仙人声转换为该音色，接入第二关第一幕，并取消法海独立出场配乐。本记录覆盖同日旧版两段视频原声记录。未使用 character-voice-production 技能或子智能体，先前 A/B/C 小样未接入。

## 来源与制作

原视频位于用户提供的微信临时目录 `C:/Users/雷双阳/xwechat_files/wxid_zjjb8la6hpvm22_79e5/temp/RWTemp/2026-10/96f892188cff5075e4fac8918e042ad9/`，按以下顺序使用。

| 文件 | 完整解码音频 | 视频 SHA256 |
| --- | --- | --- |
| `a544af721c118308a367784dc4b0ff67.mp4` | 1,353,728 帧 / 28.202667 秒 | `c6eb11c8cebf4ed954b10b39544a65ff5971cd2bd6759a12c4a44e290699ea13` |
| `5b0f4a74b22bfab46696d30f1c62ccc3.mp4` | 2,368,512 帧 / 49.344 秒 | `6f8fe55eee803528b9c9df89eeec0731e8e24f59414e5058f7f2d606fa49d769` |

全部帧数均指 48 kHz 双声道音频帧。第一段视频标称约 29 秒，但音轨完整解码为 28.202667 秒；未按视频容器时长补造对白。

只处理第一段的两处许仙人声：6.10–9.05 秒“啊，你是？”和 17.55–28.202667 秒“哦，原来你是金山寺的老禅师啊。”。MelBandRoformer 分离人声后，Seed-VC 直接转换原发声，以正式第一关 `assets/audio/act1-natural/return-02.wav`、`return-06.wav`、`return-08.wav` 为身份参考。未重新合成文本；第二段为法海原声。

换声参数：diffusion_steps=25、CFG=0.7、length_adjust=1.0、F0 与自动变调关闭、pitch_shift=0、种子 2026101610/2026101611。原混音减去分离人声形成背景残差，再叠加换声人声；两处换声增益分别约 +3.552/+4.367 dB，局部替换两端作 80 ms 淡变。模型输出量化差异只在句尾补 51/303 帧静音，没有整句变速。局部范围和来源散列见正式 `score.json`。

两段重叠 1,920 帧 / 40 ms，作余弦交叉淡化，不另加停顿。接头始于第 1,351,808 帧 / 28.162667 秒。连续原声共 3,720,320 帧 / 77.506667 秒；再追加既有 96,000 帧 / 2 秒暗场静音，正式主轨共 3,816,320 帧 / 79.506667 秒。

正式资源：`assets/audio/act2-opening/main.wav` 和 `score.json`，48 kHz / 双声道 / PCM16；导入禁止裁头、归一化、循环和有损压缩。主轨 SHA256 为 `39748691df7d4397f3d6830ebdc29e9b1fd0f199bb59d404aaaedc1e9a938d9d`。

11 条字幕依视频画面录入，从法海“许施主，请了”到“现出原形在你的身边”。许仙两句标记为 `voice_converted`，法海为 `original`。字幕时标参考原字幕出现区间，未宣称逐字强制对齐。新素材没有旧版“告辞了”，未补合成应允；保留“五月端阳可曾应验”原句，不据其改写厅堂时间线。

## 场景行为

`act2_opening.gd` 删除三处独立出场音乐更新。法海走出柳树、等待许仙迎接期间静音；保留声音状态对象与播放器字段供真实录放兼容，厅堂倒地重音保留。原视频自带伴奏随主轨保留。

`act2_dialogue.gd` 允许法海首句和许仙换声标记，法海仍要求原声。双方实际就位、面对面迎接后才从零点播放唯一主轨；沿用 MusicClock、缺场冻结、暂停与恢复、完整尾音后暗场和换景。第一关及第二关厅堂共 58 份音频相关文件经前后散列比较保持不变。

## 实际验证

Godot 固定为 `D:/Godot/4.7.2/godot.exe`，现场版本 `4.7.2.stable.official.ed1daf0bf`，对应 `4.7.2.stable` 模板目录存在。以下 Godot 参数均通过 `tools/run_godot.ps1 -LogName <日志名>` 执行，日志在 `builds/stage-realism/logs/voice-*`。

| 命令或检查 | 结果 |
| --- | --- |
| 改动的 7 份 GDScript 逐文件 `--headless --path . --check-only --script res://<脚本>` | 全部通过 |
| `python -m py_compile tools/prepare_act2_opening.py tools/check_act2_opening_audio.py` | 通过 |
| `check_act2_opening_audio.py <两段视频> --ffmpeg <既有FFmpeg> --edit-manifest builds/act2-xuxian-voice-20261016/edits.json --report builds/act2-xuxian-voice-20261016/technical-audit.json` | 独立重解码，来源、身份参考、两处局部混合、范围外法海 PCM、接头、11 字幕、完整解码、暗场和导入保护通过 |
| `--headless --path . --script res://tests/c/run_act2_dialogue.gd` | 53 项，0 失败 |
| `--headless --path . --script res://tests/c/run_act2_music_cues.gd` | 12 项，0 失败 |
| `--headless --path . --script res://tests/c/run_act2_opening.gd` | 169 项，0 失败 |
| `--headless --path . --script res://tests/c/run_act2_replay.gd` | 59 项，0 失败 |
| `--headless --path . --import` | 退出 0 |
| `--headless --path . --quit-after 60` | 退出 0 |
| `--path . --script res://tests/b/run_act2_original_graphics.gd` | 实际 Windows / WASAPI 完整实时播放 28 项，0 失败；出场静音、11 字幕有混音、接头前暂停静音与双时钟冻结、恢复、尾音和暗场清场通过 |
| `--path . --script res://tests/c/run_act2_replay.gd` | Windows 实际回放音频探针 82 项，0 失败；记录 163,451 ms、9,809 快照、72 事件，出场/等待静音、对白/对唱/重音/补救混音及暂停恢复通过 |
| `--headless --path . --export-release '"Windows Desktop"' builds/dengxia.exe` | 退出 0 |
| 导出 `builds/dengxia.exe --quit-after 60` | 实际 Windows 图形启动退出 0，stderr 为空；只证明导出包默认入口启动，完整音频以前述实时场景测试为证 |
| `verify_delivery.py` | 退出 0；58 份第一关/厅堂文件散列不变、主轨无削波、帧数与散列一致 |
| `git diff --check` | 通过，仅 LF/CRLF 转换提示 |

无头音乐、开场及启动退出仍有既有 ObjectDB/resource 释放提示，不能表述为无警告；Windows 完整主轨测试、实际回放和最终导出启动日志没有这些错误。修改期间曾定位一条旧测试错误：未启动的 entry 播放器无需 `stream_paused=true`；定向检查宿主暂停且不播放后回归通过，临时诊断输出已删除。

主轨峰值 0.864288，无削波采样；交叉淡化两侧采样阶跃分别约 0.000763 / 0.021606。CAMPPlus 与第一关参考的余弦相似度，短句由 0.315 到 0.674，长句由 0.340 到 0.836。这些只作数值诊断，不能证明自然度、咬字或音乐连贯性。戏曲念白自动转写不稳定，源与输出均有误识别，长句转换后亦有明显转写差异，未用 ASR 宣称咬字正确；未完成人工听感验收。

## 制作资料与版本管理

本地制作资料保存在被忽略的 `builds/act2-xuxian-voice-20261016/`：`produce_voice_edits.py`、`compose_recipe.py`、`edits.json`、`conversion.json`、`reference.json`、`technical-audit.json`、`windows-playback.json`、`delivery-verification.json`、`word-diagnostics.json`，以及分离、转换、源音和截图。`splice-preview.wav` 为正式主轨 24–35 秒的 11 秒接头试听。中间件与日志未提交；仓库保留正式音源、来源散列、制作/审计入口及回归。

制作器用法：`python tools/prepare_act2_opening.py <第一段视频> <第二段视频> --ffmpeg <既有FFmpeg> --work <工作目录> --output assets/audio/act2-opening --edit-manifest builds/act2-xuxian-voice-20261016/edits.json`。省略编辑清单时沿用旧版原声制作方式，不能用于重建本次换声。

本轮继续已有 `feat-act3-mountain` 分支，起始 HEAD 为 `deb7345`。`git fetch origin` 长时间停在接收 pack，已终止本次 fetch 的进程树；随后合并本地 `origin/main` 返回 Already up to date，未宣称已刷新远端。未编辑、暂存或删除开工前未跟踪的两份 raw 视频、微信图片及其 `.import`。最终检查时，两份 raw 视频已不在根目录，原因未核实；微信图片及其 `.import` 仍为未跟踪文件，不纳入本轮提交。

本轮切片已在本地提交；有界执行 `git push origin feat-act3-mountain` 返回 128，错误为 `Recv failure: Connection was reset`，远端未更新。日志保存在制作目录的 `git-push.out.log` / `git-push.err.log`，实际本地提交号见 Git 历史和最终交付说明。
