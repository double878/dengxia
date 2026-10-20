# 第三关连续打戏交付

> 2026-10-15 打戏动作修订已取代下方最初“拔剑只改变道具”的说明：自动出鞘的 550 ms 内提持剑手（按最新截图换到原来的另一只手，状态 left），之后恢复玩家操控；三关所有人形 W 短促张腿跳、S 压身后撤；鹿童/鹤童各三套组合。具体行为与新一轮验证见 [动作修订交付](combat-motion-delivery.md)。

2026-10-15。第三关《盗仙草》只有一场，本次在既有上山、求情之后接入用户提供的约 41 秒交手视频。玩家主要操演白素贞，鹿童、鹤童按原声编排轮流接战，并根据她的实际位置调整距离。

## 当前行为

- 开演即播放原声。白素贞近山后，鹿童等前奏末尾 27.56 秒的重音才跳出；原有出山前等待保留，跳出后不再增加动作门槛、补救或停唱。
- 新片“急忙用剑迎”（用户称“连忙用剑挡”）字头自动出鞘，约 0.55 秒展开剑身；不添加 F 键。拔剑只改变道具，玩家位置、手势、前倾、转身与蹲站不被接管。
- 鹿童先蓄势再进剑、收势；白素贞移动时，双童用有界速度调整距离。进剑期间锁定方向和落点，玩家可以避让。鹿童按唱词败退，鹤童从山里跃出接战。
- 鹿童退回山里与鹤童跃出共用原山体遮罩，实体、剑和幕影一致。交手期间不能接手或误收走双童，空格只接白素贞；此前若持鹿童，会交回白素贞。
- 实体剑身相交才有短暂交锋闪光，空招不产生假格挡；不增加合成碰撞声音，声音保持视频原声。
- **没有跌倒动作**。原声中的跌倒唱词完整保留，画面继续由玩家操演。
- 现有素材自然播完后进入 `awaiting_material`，保留同一舞台与白素贞操控，等待后续剧情素材；不提前收场、不弹回放选择。真实录放功能保留，正式回放入口等待整关剧情完成。

## 原声与时轴

新视频：`c27c498b3a24839601fd86c7f71bc339.mp4`，SHA256 `9cdc99da56368bb2e33721e26e72d74d31183b3d787f865b746ad5d6af67d7b1`。视频 1280×576、24fps、985 帧；原音轨 AAC 44.1kHz 单声道，非空。

复用原 FFmpeg 解码为 48kHz 双声道 PCM16，不归一化、不调增益、不变速、不去噪、不合成人声。旧 `original.wav` 与新 `fight-original.wav` 均保留。正式使用 `performance.wav`：旧音源前 99.625 秒接新音源；新音源原有 1,971,653 帧，仅去掉开头 27,102 帧全静音（564.625 ms），共 6,726,551 帧、140.136479 秒。`fight-source.json` 保存输入/输出散列与剪接点；`tools/check_act3_fight_audio.py` 比较逐字节 PCM，确认两段全部选定有声采样未被修改，删去的前缀每个采样都为零。

两段画面字幕在“说罢分心刺”处重叠，剪接保留一次该句。剪接与字幕时标根据视频抽帧标注，精度约 0.25 秒；不是采样级相同录音匹配或逐字 ASR 对齐。已经验证实际音频输出，未将其表述为真人逐字听验。

| 段落 | 歌曲时间 |
| --- | --- |
| 鹿童交手起点 | 99.625 秒 |
| 自动出鞘 | 101.310 秒起，0.55 秒完成 |
| 鹿童受挫 / 退回山里 | 113.560 / 115.810 秒 |
| 鹤童出山 / 正式接战 | 119.060 / 124.060 秒 |
| 现有素材尾 | 140.136 秒 |

## 代码与录放边界

`fight_choreography.gd` 只写双童 PuppetState，唯一 MusicClock 决定段落。`sword_view.gd` 按 actor_id 共享腕点几何。采集器保存三人真实姿态、剑出鞘比例、搭戏阶段、双方山后遮挡与实际交锋点/强度。幕前仅读这些记录，不重跑双童动作或碰撞。

本次继续使用 `feat-act3-mountain` 和已有未提交前置成果。工作区另有第二关、上半身、人物素材等改动，未混合暂存、提交或推送。

## 2026-10-15 出山时机与原声接续修正

原出山逻辑只检查山脚距离，白素贞提前到位就会提前触发。现在同时检查唯一 MusicClock 的歌曲时间，27.560 秒的末尾重音才允许起跳；去掉触发后额外 0.16 秒的蓄势，直接腾空。晚到仍按既有上山等待处理，反复靠山不重跳。

原拼接把新录屏开头 27,102 帧全静音一同接入，造成 564.625 ms 的额外停顿。现在只删除这一段精确为零的前缀，全部有声 PCM 逐字节保留；后续字幕、拔剑和双童交接同步前移。剪接仍保留原 99.625 秒的段落边界，未宣称完成逐字听验或采样相同的重叠录音匹配。`python tools/prepare_act3_fight.py` 可从已有原始 WAV 与散列清单重建，不依赖已经失效的微信临时视频路径。

本次实际验证（同一 Godot 4.7.2）：

| 检查 | 结果 |
| --- | --- |
| 改动的 5 个 GDScript 解析、gdformat、gdlint | 通过 |
| `tests/c/run_act3_entrance.gd` | 31 项 / 0 失败，新增提前靠山、重音前等待、暂停及立即起跳回归 |
| `tests/c/run_act3_fight.gd` / `run_act3_story.gd` | 31 / 41 项，均 0 失败 |
| Windows `tests/b/run_act3_entrance_graphics.gd` | 26 项 / 0 失败，WASAPI；首次腾空歌曲位置 27.563 秒，相对重音晚 3 ms，无提前 |
| Windows `tests/b/run_act3_fight_graphics.gd` | 29 项 / 0 失败，真实播放跨越接续、拔剑、双童交接与片尾，并检查回放原声 |
| `python tools/check_act3_fight_audio.py` | 删去的前缀全为零，前段与后段选定采样、散列、时长和导入设置通过 |
| `--headless --path . --import` | 退出 0 |
| `--headless --path . --quit-after 60` | 退出 0；默认第一关仍有既有 2 个 ObjectDB / 1 个资源退出清理告警 |
| `--headless --path . --export-release "Windows Desktop" builds/dengxia.exe` | 退出 0，导出包已更新 |
| `builds/dengxia.exe --headless --quit-after 60 -- --act3-rehearsal` | 退出 0，无第三关入口告警 |

最新窗口证据保存在 `docs/art/act3/timing/`，日志前缀为 `builds/stage-realism/logs/act3-timing-*`。临时自动转写探针因本机依赖环境不可用未参与结论，探针与依赖已清理；没有把音量非零检查当成人耳听验。最终源码及音频检查均未依赖该探针。

## 前次打戏验证

所有命令在项目根目录使用同一 `D:\Godot\4.7.2\godot.exe`；精确版本与 `4.7.2.stable` 导出模板已核对。

| 实际检查 | 结果 |
| --- | --- |
| 修改脚本逐文件 `--headless --path . --check-only --script res://...` | 通过 |
| `--headless --path . --script res://tests/c/run_act3_fight.gd` | 31 项 / 0 失败，含白素贞不代演、真实接剑、鹤童遮挡与回放 |
| `--headless --path . --script res://tests/c/run_act3_entrance.gd` | 27 项 / 0 失败 |
| `--headless --path . --script res://tests/c/run_act3_story.gd` | 41 项 / 0 失败 |
| `--path . --script res://tests/c/run_act3_story.gd` | 49 项 / 0 失败，Windows 图形剧情与逐采样点回放 |
| `--path . --script res://tests/b/run_act3_fight_graphics.gd` | 29 项 / 0 失败，Windows / WASAPI 实时声音与动作 |
| `python tools/check_act3_fight_audio.py` | 原声选定采样逐字节相等，帧数/散列/导入设置通过 |
| gdformat / gdlint，本次 11 个 GDScript | 通过 |
| `--headless --path . --import` | 退出 0 |
| `--headless --path . --quit-after 60` | 退出 0，默认第一关仍有既有的 2 个 ObjectDB / 1 个资源退出清理告警 |
| `--headless --path . --export-release "Windows Desktop" builds/dengxia.exe` | 退出 0 |
| `builds/dengxia.exe --headless --quit-after 60 -- --act3-rehearsal` | 退出 0，无第三关入口告警 |
| `git diff --check` | 通过，已有 CRLF 提示不计为内容错误 |

实时声音检查先验证空山开演有声，然后定位到歌曲 98.8 秒，真实播放跨越拼接、拔剑、双童交接，直至现有素材尾；没有把加速剧情检查当作完整 140 秒实时试玩。暂停混音峰值为 0；恢复、鹤童交手及对应幕前回放均有非零混音。证据见 `docs/art/act3/fight/verification.json` 和同目录截图；详细日志位于 `builds/stage-realism/logs/act3-fight-*`。

本轮窗口检查首次失败源于测试把白素贞停在出山距离之外后定位音乐，仍触发旧上山等待；已修正前置条件并加入断言，修复后和最终版均通过。没有通过放宽出山条件或跳过等待来凑测试。

## 排练

运行 `& .\tools\play_act3.ps1` 打开已更新的导出包，或在 Godot 打开 `scenes/act3/rehearsal.tscn` 按 F6。

开演后按 1 上白素贞，空格接手，拖胸签走向右侧山脚。对白段可自由摆手；到唱词自动持剑后，拖持剑手或用既有抬手键挥剑、接剑，拖胸签进退。素材尾保持舞台，不把这段未完成的打戏当作整关结局。
