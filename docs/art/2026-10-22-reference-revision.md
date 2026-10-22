# 2026-10-22 新参考影人、步态修复与纯人声对唱

用户取消上一批已经试听认可的两段对唱伴奏。当前第一关和第二关厅堂对唱恢复纯人声；第二关空台原开场音乐、法海三条用户录音的修音版继续使用。两张新人物参考图采用用户本轮文件；许仙去掉篮子和挑杆。白素贞补齐颈部，许仙颈部与衣领对齐。最新录屏反馈要求两人明显迈步并收窄袖口，修正法海脚步倒滑，按新图改成长环首锡杖；不再要求插入地面。

## 素材与实现

- 用户原图保留于 `assets/puppets/source/baisuzhen-reference-20261022.jpg` 和 `xuxian-reference-20261022.jpg`，均为 1280×2278。离线描轮廓与边缘清理保留源像素，裁去背景、操纵杆以及许仙篮子/挑杆。
- 白素贞 16 分件，许仙 13 分件；旧分件 rect/pivot 和骨架朝向保持；白素贞沿用原肩距，许仙肩距按新图可见肩宽适配。前臂袖片横向缩至原 72%，保持骨长与腕点。源图先适配既有朝向，避免照片朝向改变逻辑左右手和递杯距离。站立用完整袍摆，行走时腰部固定、8×4 网格下摆与鞋交替位移；坐姿、跳跃复用原有腿链。手臂遮挡处复用可见袖料，背面镜像；不声称恢复未拍到的背面细节。
- 初版颈部断口来自头/衣领各自缩放和颈根掩码截断。按源图颈根定位头与躯干，保留深入衣领的重叠；头部显示、拖头、口部及伞的头部查询共用计算。白素贞冠饰连接一并保留。
- 法海新杖源图为 `assets/puppets/source/staff-reference-20261022.png`（92×282）。保留金色环首镂空，清除袖子、羽毛和白底；从无遮挡直杆拟合轴线，转正并只延伸直杆。tile 尺寸为身高 1.5 倍，非透明部分约为身高 1.3 倍，握点 `[256,270]`；随实际右腕移动、不随腰倾转横，删除旧穿地延伸片。除新杖及被清空的旧延伸格外，法海 atlas 原有身体、头、双脚分件逐像素不变。
- 旧步态把前后位移与抬脚共用正弦相位，形成伸脚后退回再落地。现在腾空半周期从身后向前送，接地半周期从前向后匀速蹬，左右脚相差半周期；依素材原朝向计算后共用实体/投影/回放翻面矩阵。连续袍摆不再绕过这套步态，不增加新时钟或状态字段。
- 收尾核心回归发现上轮缩肩后仍有旧接伞几何：独立腕点测试仍使用占位肩宽，交接中心比实际双手相接点偏约 19 px。本轮按白素贞 0.074、许仙 0.055 身高的肩半宽及两段手臂长度重新推导 `HAND_REACH_X`，约 0.048；默认交接目标带为 `[0.166,0.286]`，容差不变。判据和戏单共用窗口函数，腕点独立测试读取正式肩距。
- 两关主轨与无伴奏基线逐字节一致。38 条 WAV 中仅三条变化：两份 `main.wav` 和厅堂 `wine-duet.wav`；其余 35 条保持，包括 380,928 帧的第二关开场与法海录音。主轨长度、唱段外 PCM、对白、保护静音和动作时轴保持。

当前美术来源、输出/工具哈希见 `assets/puppets/reference-revision.json`；音频来源清单为 `assets/audio/original-audio-sources.json` v3。旧的伴奏试听批准保留为历史记录，`duet_accompaniment_enabled=false` 表示当前使用干声；不能再用旧批次混音审计判断当前输出。

## 重做与审计

制作批次和不可覆盖的备份位于 `builds/reference-revision-20261022/`。美术工具的 `--rebuild` 先校验当前安装哈希，再从原备份重建；不会覆盖备份或静默覆盖并发美术改动。

```powershell
& 'D:/Trae-Python/Anaconda3/Anaconda3/python.exe' tools/prepare_couple_references.py --bai 'assets/puppets/source/baisuzhen-reference-20261022.jpg' --xu 'assets/puppets/source/xuxian-reference-20261022.jpg' --batch builds/reference-revision-20261022 --rebuild
& 'builds/act1-reference-experiment/runtime/Scripts/python.exe' tools/check_reference_revision.py --batch builds/reference-revision-20261022 --ffmpeg builds/audio-tools/Lib/site-packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe
& 'builds/act1-reference-experiment/runtime/Scripts/python.exe' tools/check_act2_natural_opening.py --ffmpeg builds/audio-tools/Lib/site-packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe --report builds/reference-revision-20261022/opening-audit.json
& 'builds/act1-reference-experiment/runtime/Scripts/python.exe' tools/check_act2_audio.py --ffmpeg builds/audio-tools/Lib/site-packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe --report builds/reference-revision-20261022/hall-audit.json
```

音频恢复工具 `remove_duet_backing.py` 已执行一次；安装完成后它会拒绝再次覆盖。最初的 `--clean-batch` 为 `builds/user-restoration-20261022-v1`。美术依赖仅开发期 Python/Pillow/NumPy/SciPy/OpenCV；游戏运行不依赖 Python 或 FFmpeg。

## 上轮颈部与纯人声验证记录（步态修订前）

本轮统一使用 `D:/Godot/4.7.2/godot.exe`，精确版本 `4.7.2.stable.official.ed1daf0bf`。下面的 Godot 命令通过 `tools/run_godot.ps1 -LogName revision-...` 执行并保存退出码和 stdout/stderr；修改的 GDScript 均先 `--check-only --script <文件>`，三个新增 Python 工具均经 AST 解析。

| 实际命令（Godot wrapper 后参数） | 实际结果 |
| --- | --- |
| `--headless --path . --script tests/a/run_tests.gd` | 核心 1285 条、正式唱说 22 条断言通过，退出 0；非法输入用例主动输出错误，另有原有退出资源警告。 |
| `--headless --path . --script tests/b/run_act1_game_audio.gd` | 26 条通过，退出 0。 |
| `--path . --script tests/b/run_reference_puppets.gd` | 实际 Windows ANGLE 渲染，72 条通过；两角色正反面、头俯仰 ±30°、弯腰的颈部连续，法杖穿过地面。 |
| `--path . --script tests/b/run_upper_body_graphics.gd` | 正式鼠标输入、复位、第一关真实捕获与幕前姿态回放 22 条通过。 |
| `--path . --script tests/b/run_combat_motion_graphics.gd` | 三关跳跃/后撤、第三关剑柄与腕点、自动出鞘/下劈和录放 61 条通过；WASAPI 暂停峰值为 0。 |
| `--path . --script tests/c/run_act2_replay.gd -- live` | 两场实际录制及实时幕前播放 103 条通过；记录 117018ms、墙钟回放 117047ms，7023 帧快照、64 事件。 |
| `--path . --script tests/c/run_act2_replay.gd` | 最终许仙肩宽调整后再跑整关录制/回放及实际混音探针，82 条通过。 |
| `--path . --script tests/b/run_replay_audio.gd` | 纯人声配置、实际混音、暂停与恢复 13 条通过。 |
| `--headless --path . --import` | 最终导入退出 0。 |
| `--headless --path . --quit-after 60` | 最终源码启动退出 0。 |
| `--headless --path . --export-release "Windows Desktop" builds/dengxia-refined.exe` | Windows 导出退出 0。 |

PowerShell 转发实时回放参数时使用 `-GodotArgs @('--path','.','--script','tests/c/run_act2_replay.gd','--','live')`，防止 PowerShell 消耗 `--`。实时测试后，最终肩宽修订又经过最后一轮快速整关回归和图形检查。

上节三个审计均退出 0：38 条 WAV 解码、35 条保持、两份干声主轨精确匹配、源图与工具哈希、原枢轴、法海旧分件像素、颈根源像素及新增下杖通过；开场审计 8 资源/6 句对白，厅堂审计 12 资源/7 句/3 保护静音区。

Windows 图形环境加载最终 `builds/dengxia-refined.pck`，比较五份清单字节、三名角色实际导入像素、35 条关卡音轨帧数和 PCM，114 条检查通过。导出 EXE 的 `--headless --quit-after 60` 及实际 Windows ANGLE 的 `--quit-after 60` 启动均退出 0。单次打包检查入口和递杯定位入口验证后删除；正式图形回归保留。

日志位于 `builds/stage-realism/logs/revision-*`，批次审计位于 `builds/reference-revision-20261022/`；整关实时报告位于 `builds/act2-replay/realtime.json`。初次回归发现的颈根透明断口和照片朝向导致的递杯偏差均已修复并复查，最终无失败断言。

画面证据位于本轮批次 `character-check.png`、六张 `couple-*.png`、四张 `staff-*.png`。这些图由实际 Windows ANGLE 渲染产生；背景对比板为验收工具，不是新增游戏界面。

已知边界：照片照明保留在纹理中，alpha 不代表实测皮革透光率。自动输入与混音回归不能代替用户最终看验、听验；法海本轮修音尚无单独的用户最终听验记录。部分旧测试退出时有对象/资源未释放警告，断言通过不表示 stderr 完全无警告。

## 最新步态、袖口与环首锡杖验证

输入录屏共 743 帧、30 fps、约 24.77 秒。固定位置对比两相时，旧版白素贞与许仙下半身像素变化均为 0；修订后，实体/投影双方向的下半身均交替变化，站定不受残留步相影响。已检查四相下摆与鞋的实际 Windows 渲染；104 帧往返、起步和停止示例输出为 `builds/gait-revision-20261022/walk-preview.mp4` 与 `.gif`。

本轮使用相同 Godot 和 wrapper；修改的 GDScript 均先解析检查，两个 Python 工具 `py_compile` 通过。当前实际结果如下（取最后成功运行的日志）：

| 命令（wrapper 后参数） | 结果 / 日志前缀 |
| --- | --- |
| `--path . --script tests/b/run_puppet_gait.gd` | 249 项，0 失败；覆盖白/许/法海及三名额外角色、左右朝向、实体/投影、停止与双脚周期；`gait-final-all-skins`。 |
| `--path . --script tests/b/run_reference_puppets.gd` | 72 项，0 失败；颈根连续、杖轴与腕点、环首及长度；`gait-final-puppets`。 |
| `--path . --script tests/b/run_upper_body_graphics.gd` | 22 项，0 失败；正式输入与第一关姿态录放；`gait-final-upper`。 |
| `--path . --script tests/b/run_combat_motion_graphics.gd` | 61 项，0 失败，stderr 无脚本错误；`gait-final-combat-fixed`。 |
| `--path . --script tests/b/run_stage_walk.gd` | 24 项，0 失败；正式胸签拖动、桥面路径、停步和步态数据；`gait-final-stage-input`。 |
| `--path . --script tests/c/run_act2_replay.gd` | 82 项，0 失败；两场录制、递杯和幕前回放；`gait-final-act2`。此轮为快速回归，未重跑实时全长模式。 |
| `--path . --script tests/b/run_replay_audio.gd` | 13 项，0 失败；`gait-final-replay-audio`。 |
| `--headless --path . --script tests/a/run_tests.gd` | 1285 项及正式唱说 22 项，0 失败；`gait-final-core-fixed`。仍有非法输入用例的预期错误及原有退出资源警告。 |
| `--headless --path . --script tests/c/run_game_replay_success.gd` | 12 项，0 失败；完整接伞、往返、还伞与回放，记录 117017 ms；`gait-final-act1-handoff`。此轮为无头模拟。 |
| `--headless --path . --import` | 退出 0；`gait-delivery-import`。 |
| `--headless --path . --quit-after 60` | 退出 0；`gait-delivery-startup`。 |
| `--headless --path . --export-release "Windows Desktop" builds/dengxia-gait.exe` | 退出 0；`gait-delivery-export`。旧 `dengxia-refined.exe` 仍在运行，故单独输出新文件名。 |

来源审计 `check_reference_revision.py` 退出 0：38 条 WAV 解码通过，纯人声及开场/法海音频不变；两角色颈根、原枢轴、72% 袖片、新锡杖源图哈希、法海所有身体分件不变及旧延伸格清空均通过。完整当前画面为 `builds/gait-revision-20261022/character-check.png`，动态为同批次 `walk-000.png` 至 `walk-103.png`。

本轮回归曾暴露额外角色使用独立贴图字典、不能索引原三人纹理数组；已修正并把三名额外角色加入正式步态回归。初次新杖抠图轴线偏移与羽毛残留也已按源图无遮挡杆段拟合、裁取修复。旧失败日志保留用于追溯，以上表格仅列最终结果。单次接伞测试入口验证后已删除。

实际 `builds/dengxia-gait.pck` 再经 Windows ANGLE 校验：步态 249 项、颈部/锡杖与两份当前清单 SHA-256 共 74 项，均 0 失败，stderr 无脚本错误。打包资源渲染的 104 帧与源码批次逐字节相同。日志为 `gait-packed-final`、`gait-packed-reference`；外部测试入口只改输出目录以适应 PCK 的只读 `res://`，已清理。导出 EXE 无头及 Windows ANGLE 启动均退出 0，日志为 `gait-exe-headless`、`gait-exe-windows`。
