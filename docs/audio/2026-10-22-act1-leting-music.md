# 第一关乐亭原声器乐试听版

用户要求先接入试听，本轮不等待额外选项。来源为用户已明确授权的 [乐亭皮影戏《白蛇传》第一集](https://www.bilibili.com/video/BV1xX4y1Y7sJ/)。听感尚待用户确认，不将自动化混音检查称为人工听验。

## 试听行为

- 开场最后一句“待我上前，借问一声”完整结束后，19.025 秒开始移步音乐；25.025 秒前收掉，不覆盖对唱。尚未到位时由既有等待器乐延续。
- 三句对唱完整保留原纯人声；尚未实际接伞的等待保持静音。
- 实际接伞解除等待，56.877 秒开始游湖音乐，至 74.877 秒；还伞等待延续器乐，还伞普通对白开始前已收掉。
- 接伞锣、补救鼓、雨声、两关对白和唱声、美术及输入保持既有实现。菜单暂停冻结播放器；幕前读取记录中的原音频快照。

## 来源与制作

完整源：`builds/real-performance-reference/乐亭白蛇传_第一集_原始参考.m4a`，本轮核验 SHA256 为 `a8d909b1a16ac2384f6d0f71c61a2169f5930189b05704aad28316c2084e9701`。

截取原片 00:00–00:32，复用本机 MelBandRoformer 离线分离器乐。移步选 00:02–00:08，游湖选 00:10–00:28；不生成或替换唱声，不变速、不变调。两段共用固定增益，首尾淡入淡出，48k 双声道 PCM16。等待循环取 00:22–00:28，接缝重叠 200ms；仅用于到位和还伞等待。

正式主轨只改两处精确帧区间 `[913213,1201213)`、`[2730112,3594112)`；主轨仍为 5,333,317 帧。工具审计其余 PCM、台词时标、对唱 PCM 摘要及第二关资源逐字节保持。清单里的 `background_music=true` 表示移步与游湖有器乐，`duet_accompaniment_enabled=false` 单独表示对唱纯人声。

制作输入、分离结果、安装前备份、选区预览及审计报告在 `builds/act1-leting-music-20261022/`。正式来源与处理哈希登记在 `assets/audio/original-audio-sources.json` 的 `act1_leting_preview`；`tools/prepare_act1_leting_music.py --batch builds/act1-leting-music-20261022 --audit` 可重新核验。

## 验证与交付

运行包：`builds/dengxia-leting-preview.exe` 与同名 PCK。短试听：`builds/act1-leting-music-20261022/after-dialogue-context.wav`（含前后对白/唱声）及 `after-take-context.wav`（含接伞前尾腔、游湖音乐及还伞开句）。单独器乐为 `approach-preview.wav`、`tour-preview.wav`。

固定使用 Godot `4.7.2.stable.official.ed1daf0bf` 与本机 `4.7.2.stable` 模板。本轮实际执行：

```powershell
& tools/run_godot.ps1 -LogName leting-audio-parse --headless --path . --check-only --script scripts/b/act1_opera_audio.gd
& tools/run_godot.ps1 -LogName leting-replay-parse --headless --path . --check-only --script tests/b/run_replay_audio.gd
& tools/run_godot.ps1 -LogName leting-game-parse --headless --path . --check-only --script tests/b/run_act1_game_audio.gd
& tools/run_godot.ps1 -LogName leting-import --headless --path . --import
& tools/run_godot.ps1 -LogName leting-opera-flow --headless --path . --script tests/a/run_act1_opera.gd
& tools/run_godot.ps1 -LogName leting-game-audio --path . --script tests/b/run_act1_game_audio.gd
& tools/run_godot.ps1 -LogName leting-replay-audio --path . --script tests/b/run_replay_audio.gd
& tools/run_godot.ps1 -LogName leting-full-replay --headless --path . --script tests/c/run_game_replay_success.gd
& tools/run_godot.ps1 -LogName leting-final-startup --headless --path . --quit-after 60
& tools/run_godot.ps1 -LogName leting-export -GodotArgs @('--headless','--path','.','--export-release','"Windows Desktop"','builds/dengxia-leting-preview.exe')
& tools/run_godot.ps1 -LogName leting-packed-audio -GodotArgs @('--path','.','--main-pack','builds/dengxia-leting-preview.pck','--script','D:/Cursor_program/灯下/tests/b/run_replay_audio.gd')
& builds/act1-reference-experiment/runtime/Scripts/python.exe tools/prepare_act1_leting_music.py --batch builds/act1-leting-music-20261022 --audit
```

结果：三份脚本解析、资源导入、无头启动及 Windows 导出退出 0；唱说/真实交接门禁 22 项通过。实际 Windows ANGLE 环境正式音频接线 28 项、回放混音 16 项通过，采样确认两处音乐和等待循环均非静音，暂停原位冻结，重复帧不重复收锣。完整接还伞与幕前回放模拟 12 项通过，实际记录 117,017ms（包含等待）；本轮没有做全长实时人工听验。

最终 PCK 在 Windows 图形/音频环境重跑混音 16 项通过；新 EXE 以 `--headless --quit-after 60` 启动退出 0。日志在 `builds/stage-realism/logs/leting-*.out.log` 与同名 stderr。PCM 审计通过：两处音乐之外的主轨、原对唱、对白时标及其他正式音频资源一致；当前仍为等待用户反馈的试听状态。
