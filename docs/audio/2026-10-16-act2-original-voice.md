# 第二幕第一场两段视频原声衔接

2026-10-16。用户明确选择直接衔接视频原声，替换第二幕第一场“法海劝酒”现有对白。

## 内容与衔接

按用户列出的顺序使用：

1. `85b6e08ce1128fc542b11b16a60f5d24.mp4`：许仙问候、双方问名；完整解码 979,968 帧 / 20.416 秒。
2. `b5283e8e28ef933e73ae8fda070cf3f7.mp4`：法海指出蛇妖身份，许仙反驳，法海交代端阳雄黄酒办法并告辞；完整解码 2,990,080 帧 / 62.293333 秒。

原声总计 3,970,048 帧 / 82.709333 秒；完整保留两段 AAC 解码后的 PCM，不裁剪、混合、变调、变速、换音色或重新生成声音。接头位于 20.416 秒，前段最后四帧为双声道 −1，后段最初四帧为零，无大幅波形阶跃；没有额外插停顿或淡变覆盖字音。原声结束后追加既有 2 秒暗场静音，主轨 4,066,048 帧 / 84.709333 秒。

正式资源为 `assets/audio/act2-opening/main.wav` 与 `score.json`。清单记录文件名、来源/解码散列、源选区、主轨起止帧和字幕；48 kHz / 双声道 / PCM16，导入禁止裁剪、归一化、循环和有损压缩。原六句独立音源保持存档，当前播放器只引用新主轨。

16 条字幕按实际视频画面逐项录入，从许仙“原来是位老师父，请了”到法海“告辞了”。字幕时间参考视频原字幕出现区间，不宣称为逐字强制对齐；跨两段接头保留视频中实际已有的声音。自动转写对戏曲念白不可靠，仅保存边界诊断，不据其改词或剪音。

## 游戏行为

法海按 1 上场，走出柳树后停止出场音乐并等待许仙。按 2 请许仙出门，真实朝法海移步、相距 220–380 px 并面对面后，才从零点开始完整原声；迎接前不漏播许仙首句。之后没有旧版六句应允和额外思考计时，两段连续播放。误退场原位冻结并等待回来；菜单暂停冻结主轨和双时钟。

原声及尾部全部完成后按主轨时间执行 2 秒暗场，再沿既有 1.5 秒章节停留进入厅堂；不额外合成许仙应允。第二场对白、劝酒对唱、饮酒与惊变沿用。真实回放继续从同一清单加载主轨，记录实际迎接等待、暂停以外的缺场等待、字幕、姿态与两场换景。

第一场声音由旧约 31 秒延长至原声约 83 秒，第二关/整剧的旧固定时长预算不再适用本次完整原声选择。

## 可复现与验证

制作入口：`python tools/prepare_act2_opening.py <第一段视频> <第二段视频> --ffmpeg <既有FFmpeg> --work builds/act2-video-singing --output assets/audio/act2-opening`。

只读独立审计：`python tools/check_act2_opening_audio.py <第一段视频> <第二段视频> --ffmpeg <既有FFmpeg> --report builds/act2-video-singing/technical-audit.json`。已通过来源哈希、重新完整解码、两段全部 PCM 逐采样相同、顺序、接头、16 条字幕、2 秒暗场静音及导入保护检查。

全部 Godot 检查固定使用 `D:\Godot\4.7.2\godot.exe`，版本 `4.7.2.stable.official.ed1daf0bf`，对应模板目录已核对。命令通过 `tools/run_godot.ps1` 执行并保存在 `builds/stage-realism/logs/act2-original-*`。

- 改动脚本 `--headless --path . --check-only --script res://<脚本>`：通过。
- `--headless --path . --script res://tests/c/run_act2_dialogue.gd`：59 项，0 失败；覆盖真实迎接、零点等待、全部字幕、接头暂停、缺场续播、尾音后暗场及单次收场。
- `--headless --path . --script res://tests/c/run_act2_opening.gd`：169 项，0 失败；退出有既有 ObjectDB/resource 释放提示。
- `--headless --path . --script res://tests/c/run_act2_replay.gd`：59 项，0 失败；完整两场记录 168,634 ms、10,120 快照、80 事件，包含实际动作等待，非真实声音试听。
- `--headless --path . --import`：通过。

- `--path . --script res://tests/b/run_act2_original_graphics.gd`：真实 Windows / WASAPI 完整实时播放 33 项，0 失败；两段原声、16 条字幕均有实际混音，接头前暂停输出静音、双时钟冻结，恢复后完整播完并暗场清场。报告和接头/暂停截图保存在 `builds/act2-video-singing/`。
- `--path . --script res://tests/c/run_act2_replay.gd`：Windows 图形及回放音频 82 项，0 失败；记录 168,651 ms、10,121 快照、80 事件，原声、对唱、重音、补救及动作等待的混音/静音探针通过。
- `--headless --path . --quit-after 60`：通过，退出 0。
- `--headless --path . --export-release '"Windows Desktop"' builds/dengxia.exe`：通过，退出 0；打包日志包含第一场 `score.json` 和主轨。
- 导出 EXE 默认入口在实际 Windows 图形环境以 `--quit-after 60` 冒烟：退出 0，stderr 为空；此项仅证明默认启动，第一场完整声音以同版本 Godot 的实时场景回归为证。
- Python 编译、`git diff --check`：通过；仅出现已有 LF/CRLF 提示。一次性转写排查脚本已删除，保留可复用制作、独立审计与正式回归。

保留工作区开工前的其他改动，不进行自动合并、提交或推送。旧六句音源未删除，切换回旧生成清单需要同时恢复旧调度逻辑，不能仅换清单。

未执行人工听感验收。不以自动转写、PCM 审计或引擎混音代替人耳对咬字和艺术衔接的评价。
