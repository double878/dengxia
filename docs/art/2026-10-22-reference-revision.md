# 2026-10-22 新参考影人、颈部修复与纯人声对唱

用户取消上一批已经试听认可的两段对唱伴奏。当前第一关和第二关厅堂对唱恢复纯人声；第二关空台原开场音乐、法海三条用户录音的修音版继续使用。两张新人物参考图采用用户本轮文件；许仙去掉篮子和挑杆。后续纠正同时纳入：法海竖持法杖并向下加长，可插入地面；白素贞补齐颈部，许仙颈部与衣领对齐。

## 素材与实现

- 用户原图保留于 `assets/puppets/source/baisuzhen-reference-20261022.jpg` 和 `xuxian-reference-20261022.jpg`，均为 1280×2278。离线描轮廓与边缘清理保留源像素，裁去背景、操纵杆以及许仙篮子/挑杆。
- 白素贞 16 分件，许仙 13 分件；旧分件 rect/pivot 和骨架朝向保持；白素贞沿用原肩距，许仙肩距按新图可见肩宽适配。源图先适配既有朝向，避免照片朝向改变逻辑左右手和递杯距离。站立用完整袍摆，坐姿、跳跃复用原有腿链。手臂遮挡处复用可见袖料，背面镜像；不声称恢复未拍到的背面细节。
- 初版颈部断口来自头/衣领各自缩放和颈根掩码截断。按源图颈根定位头与躯干，保留深入衣领的重叠；头部显示、拖头、口部及伞的头部查询共用计算。白素贞冠饰连接一并保留。
- 法海原杖围绕原握点转至竖向；新下延长分件复用原杖下段纹理，长度为身高的 1.1 倍，只向握点下方延长。握点和装饰上端不变，杖轴随实际右腕移动、不随腰倾转横。原法海 atlas 的全部旧分件像素不变。
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

## 验证记录

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
