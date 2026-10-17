# 三关试玩细修交付

2026-10-17，落实用户 AAA，并按后续要求将许仙末声改为第四声方向、短促惊恐的“啊（à）！”。

## 行为变化

- 第一关删除备用头架、编号、文字及鼠标/1/2/3 换头入口。共用 PuppetController 与旧记录字段保留兼容。
- 检查白素贞七句普通对白的原 TTS、转换层及停顿；只重制三句：“君子，雨住了，这伞奉还。”“伞可以托青儿送来，谢意还是我亲口说的好。”“那就莫忘了。”。其他对白、唱段及未替换区间逐采样保留，主轨更新为 111,288 ms。
- 厅堂先播放 5 秒连续器乐，再进入原有四组完整对唱；前奏期间不显示歌词。主轨从 `hall_start_ms=20119` 开始，对唱起点改为 `duet_start_ms=25119`，后续绝对时标整体加 5000 ms，总长 74,517 ms。沿用同一 MusicClock、动作等待及暂停机制。
- 许仙见蛇只惊叫一次，按新 WAV 的实际 331 ms 时长等待，再执行原惊退倒地；没有落地重音。
- 鹿童初次出山、准备位、三种招式与退势均位于白素贞右侧；右界 0.94、目标间距 160 px，靠近舞台边缘时缩短移动。白素贞位置不被自动改写，鹤童沿用旧编排。

首页、片头片尾、三关演前简介和真实幕前回放沿用既有流程。

## 声音制作与验收边界

白素贞沿用自然对白韵律参考及已交付角色音色：F5-TTS 32 步 / CFG 2；Seed-VC 25 步 / CFG 0.7 / length 1.0，不做 F0 条件、变调或混响。旧 `return-09` 转写出现“那就啊啊啊 莫忘了”，重制后为“那就莫忘了”；`return-03` 内部停顿从约 1.04 秒减为约 0.54 秒。其他转写含同音字误识别，未据此声称逐字听验通过。

许仙的普通“啊！”及英文感叹词生成均测到上扬音高，未选入最终版。固定 F5 词表缺少 `a4`；最终以有效 `da4` 发音载体生成，再按波形和频谱边界删除前 12,290 帧的静音/起始辅音，取出元音及全部尾声。使用已交付许仙普通对白作为参考，固定种子 2026101721、32 步、CFG 2；没有二次声线转换、后期变调、变速或混响。选取元音主要音高从约 514 Hz 降至 324 Hz，支持下落语调；固定增益后峰值约 0.800。

最终惊叫为 48 kHz / 双声道 / PCM16，15,868 帧，0.330583 秒，SHA256：`c98037bc25e8ef17d1f6617ecaf327ea4e2ebdbbfb7937e9c00a7d99488fece9`。短音自动转写误识为“拜拜”，不作为字音或情绪证据。**下落音高、格式检查和 Windows 实际混音均不能代替人耳判断第四声、惊恐感、自然度或电音；最终版尚未经用户听验。**

制作入口为 `tools/prepare_playtest_audio.py`（`prepare`、`prepare-fright`、`finish-fright`、`package`），诊断入口为 `tools/check_playtest_speech.py`。输入、原始浮点中间件、模型权重核验、生成参数和哈希保存在本机 `builds/playtest-polish-20261017/` 与 `builds/playtest-fright-fourth-vowel-20261017/`；正式 score.json 同步保存制作追踪。生成只使用现有离线模型，游戏运行没有新增 Python 或模型依赖。

## 实际验证

统一由 `tools/run_godot.ps1` 调用 `D:\Godot\4.7.2\godot.exe`，版本 `4.7.2.stable.official.ed1daf0bf`。本轮改动的 GDScript 先运行 `--headless --path . --check-only --script res://<文件>`，再运行定向回归；`py -3.13 -m gdtoolkit.formatter --check <本切片五个脚本>` 与 `py -3.13 -m gdtoolkit.linter <同上>` 均通过。

| 入口 | 已执行结果 |
| --- | --- |
| `tests/b/run_head_rack_removed.gd`，Windows | 4 项，0 失败；真实按键/旧热区点击不换头，保存并目视检查无头架画面 |
| `tests/c/run_deer_spacing.gd` | 13 项，0 失败；多起点、右边界、移动玩家、全部三种招式 |
| `tests/c/run_act3_fight.gd` | 75 项，0 失败 |
| `tests/c/run_act3_story.gd` | 41 项，0 失败；旧第三关收场断言按现有片尾流程更新 |
| `tests/b/run_act3_entrance_graphics.gd`，Windows/WASAPI | 28 项，0 失败；真实跳出、落点、暂停和回放 |
| `tests/b/run_act1_game_audio.gd`，Windows | 26 项，0 失败；正式音源、字幕、单主轨、等待和暂停 |
| `tests/c/run_act2_hall_audio.gd`，最终音源 | 20 项，0 失败；前奏长度、字幕与唯一主轨 |
| `tests/c/run_act2_actions.gd` | 79 项，0 失败 |
| `tests/c/run_act2_replay.gd`，最终音源 | 59 项，0 失败；116,417 ms / 6,987 快照 / 65 事件 |
| `tests/c/run_game_replay.gd` | 38 项，0 失败；44,283 ms / 2,181 快照 / 2,981 事件 |
| `tests/b/run_act2_voice_graphics.gd -- --hall-only`，最终 Windows/WASAPI | 44 项，0 失败；完整前奏→对唱→取杯饮酒→弯腰→取药→换蛇→惊叫→倒地，含暂停 |
| `tests/b/run_fright_pause.gd`，Windows/WASAPI 及最终导出 PCK | 各 8 项，0 失败；暂停混音峰值 0，恢复约 0.800，完整叫完后倒地、单次触发及时长一致 |
| `tools/check_act2_audio.py --ffmpeg <固定 FFmpeg> --report <本轮报告>` | 12 条 WAV 哈希/帧数/完整解码、七句完整对白、原连续对唱及三处等待静音通过 |
| skill 的 `scripts/check_audio.py` | 六条更改 WAV 完整解码、48k/stereo/PCM16、无满幅削波通过；最终惊叫增益单独复查通过 |
| 独立 PCM 审计 | 第一关全部未替换区间、厅堂前奏前原段及完整对唱至轨尾逐采样一致；全部正式资源哈希一致 |

日志：`builds/stage-realism/logs/polish-*.{out,err}.log`，最终厅堂为 `polish-hall-windows-release-final`，最终 PCK 惊叫为 `polish-delivery-pack-fright`。PCM 与生成证据见制作目录的 `final-pcm-verification.json`（五条其他 WAV 与增益前惊叫）、`fright-final-headroom.json`（最终惊叫）、`hall-pcm-delivery.json`（最终全部厅堂资产）、`independent-final-audit.json`、`vowel-edit.json`。

短惊叫令旧测试固定 250 ms 后暂停的假设失效；改为实际长度的前四分之一，并检查暂停前所处阶段、暂停前后真实时间和倒地进度。最终日志为 `phase=fright`、`progress=0→0`、`real=55983→55983`、`peak=0`。独立短场景另在首帧渲染完成后启动惊叫，排除冷启动耗时干扰，不改游戏时钟或延长音源。

早期部分无头回归出现 ObjectDB/resource 退出释放诊断；对应断言通过，但不记为无警告。最终厅堂音源定向回归和已完成的 Windows 图形回归退出 0、无错误日志。未做三关全程人耳听验或首次玩家验收。

## 最终构建

最终依次执行 `--headless --path . --import`、`--headless --path . --quit-after 60`、`--headless --path . --export-release "Windows Desktop" builds/dengxia.exe`，均退出 0，日志无错误。导出 PCK 通过上述短惊叫 8 项实际 WASAPI 回归；无头架输入/画面检查在导出包上 4 项通过。`builds/dengxia.exe --quit-after 120` 在实际 Windows/OpenGL 环境启动退出 0。

产物：`builds/dengxia.exe` 与同目录 `builds/dengxia.pck`，运行时需要放在一起。正式回归和其 UID 保留；本轮引擎顺带生成、与切片无关的旧测试 UID 已清理。未改动用户已有未跟踪目录、PDF 工具和参考图片。
