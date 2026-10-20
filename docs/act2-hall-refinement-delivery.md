# 第二场厅堂剧情与操演修订

2026-10-17，用户确认 AAAA。保留法海劝酒，厅堂直接双人对唱；拖手靠近取杯，头旁停留约半秒饮酒；许仙喊“啊——！”后惊退倒地。

## 实际改动

- 厅堂开场仅白素贞、许仙对坐，直接从 `duet_start_ms=20119` 开唱。小青不在场，按 3 也不能进入，不再生成她的买菜、恢复或离场任务。旧前五句仍留在源 PCM 和制作清单，正式演出跳过。
- 许仙取杯半径从 26 px 放宽到 52 px；仍由玩家拖手，递杯继续读取真实腕点。白素贞饮酒改为持杯手进入实际头中心 64 px 内，停留 550 ms；提示和师父目标同步改到头旁。
- 见蛇时先进入 `fright` 并播放一次许仙惊叫，完整 1,985 ms 后进入原 1.5 秒惊退仰倒，再保留原收势和观看选择。暂停同步冻结喊声、两个时钟及动作。原落地视频重音不再触发。
- 真实回放保留两场、动作等待、头旁饮酒和惊叫。沿用既有 `audio.hit` 一次性声音槽，其实际资源现为 `xu-fright.wav`。

## 两处声音中断的原因与证据

主轨此前已逐样本保留完整唱白；问题出在暂停 WAV 的 `seek()` 没有可靠地更新实际播放游标，逻辑时间却已跳到下一段，最终按领先的逻辑时间提前冻结声音。

新回归 `tests/b/run_music_clock_seek.gd` 在真实 WASAPI 下复现：冻结跳段的逻辑时间为 20,119 ms，实际游标仍在 173 ms；原实现 8 项检查中 4 项失败。`advance_to_ms()` 改为从目标位置 `play()` 并恢复原冻结/菜单暂停状态后，相同检查为 8 项、0 失败；同次日志的逻辑/实际读数为 20,119/20,132 ms，恢复后为 62,278/62,288 ms。

Windows 正式厅堂回归另外直接断言：进入取杯等待时，实际游标已越过白素贞末句尾腔；允许许仙取药离场时，实际游标已越过完整取药台词。现有唱段、伴奏和取药音源未重生成，完整 PCM 独立审计通过。

## 惊叫制作

新音源 `assets/audio/act2-hall/xu-fright.wav`，48 kHz、双声道、PCM16，95,295 帧，约 1.985 秒。SHA256：`c0db694bcff096220849839db35dcef98097c5d6314c594dd737014bf884c976`。沿用第一关 `return-02.wav` 的许仙对白身份和韵律参考，F5-TTS 32 步 / CFG 2，Seed-VC 25 步 / CFG 0.7 / length 1.0，不用 F0 或变调；仅完整重采样与固定增益，交付峰值约 0.801，无裁尾和有损压缩。

本机离线生成请求、中间件及完整模型输入指纹保存在 `builds/act2-hall-refinement-20261017/`；装配入口为 `tools/prepare_act2_fright.py`，正式清单记录参考、种子、参数、输入/输出及脚本哈希。生成使用已存在的模型缓存，没有新增游戏运行依赖。新喊声尚未经用户听验；声音身份、惊吓力度和自然度不能用技术检查替代。

## 已执行验证

统一通过 `tools/run_godot.ps1` 调用 `D:\Godot\4.7.2\godot.exe`（`4.7.2.stable.official.ed1daf0bf`）。修改脚本先执行 `--headless --path . --check-only --script res://<文件>`，格式与 lint 通过。

| 回归入口 | 实际结果 |
| --- | --- |
| `tests/b/run_music_clock_seek.gd`，Windows / WASAPI | 8 项，0 失败；修复前 4 失败 |
| `tests/a/test_music_clock.gd`，临时仅调用 `run_all()` 的入口，已删除 | 47 项通过 |
| `tests/a/run_act1_opera.gd` | 22 项通过 |
| `tests/c/run_act2_hall_refinement.gd` | 10 项，0 失败；初始双人开唱/禁止小青断言已验证旧实现失败 |
| `tests/c/run_act2_actions.gd` | 79 项，0 失败 |
| `tests/c/run_act2_hall_audio.gd` | 18 项，0 失败 |
| `tests/c/run_act2_remedy.gd` | 26 项，0 失败 |
| `tests/c/run_act2_music_cues.gd` | 26 项，0 失败 |
| `tests/c/run_act2_hall.gd` | 39 项，0 失败 |
| `tests/c/run_act2_replay.gd`，headless | 59 项，0 失败；113,084 ms / 6,787 快照 / 64 事件 |
| `tests/b/run_act2_voice_graphics.gd`，Windows / WASAPI | 41 项，0 失败；四组唱腔、两句饮后对白、完整尾音游标、宽容取杯、头旁饮酒、暂停及单次惊叫 |
| `tests/b/run_act2_actions_graphics.gd`，Windows | 实际输入走完整流程，Q/E、蛇头/躯干拖动、补救和结尾通过 |
| `tests/c/run_act2_replay.gd`，Windows / WASAPI | 82 项，0 失败；实际回放音乐/对白/对唱/惊叫、等待静音、暂停画面和声音 |
| `py -3.13 tools/check_act2_audio.py --ffmpeg "D:\Cursor_program\灯下\builds\audio-tools\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe" --report builds/act2-hall-refinement-20261017/pcm-verification.json` | 12 条 WAV 哈希、严格解码、完整 PCM 和保护静音通过 |

Windows 实时混音中四组对唱均有声音，惊叫峰值约 0.801，惊退和落地后的混音峰值为 0。相关截图位于 `builds/act2-voice/`、`builds/act2-actions/` 和 `builds/act2-replay/`；已目视检查双人对坐、头旁抬杯及倒地构图。

最终门禁实际执行：`--headless --path . --import`、`--headless --path . --quit-after 60`、`--headless --path . --export-release "Windows Desktop" builds/dengxia.exe`，三项均退出 0。导出日志包含 `xu-fright.wav` 与厅堂清单；导出包 `builds/dengxia.exe --headless --quit-after 60` 实际启动退出 0，仍有下述快速退出资源释放诊断。

既有部分无头测试仍报告 ObjectDB/resource 退出释放诊断，不将退出码 0 写成无警告。无头模式不用于证明声音和画面体验；本次也未重做三幕全流程首次玩家验收或性能基准。
