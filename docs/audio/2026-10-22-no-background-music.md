# 第一、二关取消背景音乐

按用户最终选择，第一关移步、对唱、等待、游湖与收束的背景伴奏，第二关开场、饮酒对唱及备用器乐全部取消。唱段由既有纯人声分轨重建，保留既有统一增益和重采样；对白、雨声、接伞锣、补救鼓与许仙惊叫保留。法海沿用独立合成预设，制作及许可见 [音色记录](2026-10-22-original-accompaniment-fahai.md)。第三关和片头片尾不在本次范围。

三份音源清单均写入 `background_music=false`。十个背景 cue 没有音符事件，输出全零 PCM；两个数学合成动作 cue 保留，其中旧厅堂落地音效仍不在当前流程播放。第一关和厅堂时长及字幕不变。第二关开场只保留 100ms 静音控制片段，继续使用已有 `finished` 机制，人物完成迎接即可开口，无需等待旧 7.936 秒音乐。六句对白主轨保持 42.094479 秒。第二关演前简介同步去除“开场音乐”。

## 复现

保留原始批次 `builds/original-audio-20261022/before`，不重新拍摄已修改音源的基线。新暂存和证据在 `builds/no-background-audio-20261022`，上一轮带伴奏交付保留。安装器按基线、上一交付和当前暂存哈希保护并发修改，并跳过完全相同的文件。曾有一次文件写入失败导致安装未完成；恢复时逐字段核对，仅更新清单的听验说明，随后重新完整安装并审计。

```powershell
$audioPython = 'builds/act1-reference-experiment/runtime/Scripts/python.exe'
$audioFFmpeg = 'builds/audio-tools/Lib/site-packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe'
& $audioPython tools/replace_stage_accompaniment.py --batch builds/original-audio-20261022 --delivery builds/no-background-audio-20261022/delivery --no-background-music --install
& $audioPython tools/check_original_audio.py --batch builds/original-audio-20261022 --ffmpeg $audioFFmpeg --report builds/no-background-audio-20261022/installed-audit.json
& $audioPython tools/check_act2_natural_opening.py --ffmpeg $audioFFmpeg --report builds/no-background-audio-20261022/opening-audit.json
& $audioPython tools/check_act2_audio.py --ffmpeg $audioFFmpeg --report builds/no-background-audio-20261022/hall-audit.json
```

## 验证记录

使用固定 `D:/Godot/4.7.2/godot.exe`。本轮日志为 `builds/stage-realism/logs/no-bgm-*`，音频及 Windows 报告为 `builds/no-background-audio-20261022/`；旧伴奏版本的测试报告不作为本轮证据。

- Python 修改工具解析通过；音频审计验证 40 个文件可完整解码、23 条普通对白 PCM 不变、两个唱腔分轨哈希不变、无伴奏主轨逐采样重建一致、十处背景 cue 全零、两个动作 cue 可复现。第二关六句对白与两秒暗场、100ms 静音开场、厅堂七条完整对白及三个静音保护区审计通过。
- 相关无头回归：第一关真实音源 26/26；第二关对白 47/47、声音许可 26/26、厅堂音源 18/18、厅堂流程 10/10。

- Windows/WASAPI：`tests/b/run_replay_audio.gd` 13/13；`tests/b/run_act2_intro_replay.gd` 42/42，100ms 静音控制片段实际记录到 150ms，500ms 记录的现场及回放峰值均为 0；`tests/b/run_act2_original_graphics.gd` 38/38，六句完整对白有声，空台和迎接等待静音，迎接后 500ms 内开始对白，覆盖暂停、缺场恢复和晚出场。
- 两场完整实时回放 `tests/c/run_act2_replay.gd -- realtime`：103/103，记录 108,568ms，实际播放 108,606ms，惊叫一次；对白、四组唱段有声，空台与递杯等待无伴奏，暂停静音。命令使用 `-GodotArgs @('--path', '.', '--script', 'tests/c/run_act2_replay.gd', '--', 'realtime')`，日志包含 `ACT2_REPLAY_WALL`，未以快速模拟替代实际时长分支。
- 收尾通用回归 `tests/a/run_tests.gd`：1,285 + 22 条断言；`tests/c/run_tests_c.gd`：464 条，均为 0 失败。负向测试有意输出非法输入诊断；第一关测试退出仍有既有对象/资源释放诊断，不影响断言与退出码，但不称 stderr 全无警告。
- Godot 三项门禁 `--headless --path . --import`、`--headless --path . --quit-after 60`、`--headless --path . --export-release "Windows Desktop" builds/dengxia.exe` 均退出 0。额外从导出 PCK 加载全部 38 条游戏 WAV，PCM 哈希与源工程一致，三份 score 和来源清单也逐字节一致（42 项、0 失败）；导出的 `builds/dengxia.exe --headless --quit-after 60` 退出 0。临时导出检查入口已清理。

自动检查不替代人耳听验；`human_listening_verified=false`。保留唱腔和其他对白的授权仍未核实，不能仅凭取消伴奏认定整部作品或竞赛材料已合规。
