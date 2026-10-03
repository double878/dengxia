# A 范围测试说明（第一关操控与关卡逻辑）

工具链统一为 Godot `4.7.2.stable.official.ed1daf0bf`。以下命令都假设在仓库根目录执行，
`godot.exe` 取本机同一版本路径（示例为 `D:\Godot\4.7.2\godot.exe`）。

## 1. 无头行为测试（回归门禁，退出码 0/1）

```powershell
& 'D:\Godot\4.7.2\godot.exe' --headless --path . --script res://tests/a/run_tests.gd
```

两套共 23 条行为、146 条断言：

- **切片 1（操控，13 条）**：初始不变量、胸签命中、横向与纵向拖动及两端截断、
  转身渐进过渡、双手独立与双手同动、按住连续/松开保持、相反指令保持姿势、
  连续量边界、`TimedEvent` 契约与取走即清空、状态先于事件、同帧松开结算位移、
  暂停时丢弃操控输入。
- **切片 2（音乐时钟与关卡时长，10 条）**：自由计时单调推进、暂停冻结（含拍序号
  与跨拍报告）、恢复不跳变、跨拍每拍只报一次且序号连续、`beat_time_ms` 与
  `get_beat_index` 互逆、第一关 35000 ms / 56 拍 / 校验通过、校验能报出未覆盖与
  `cue_id` 重复与落点越界、操控事件时间戳等于 `MusicClock` 读数、缺音轨时明确降级。

## 2. 图形环境脚本化实测（真实窗口，退出码 0/1）

```powershell
& 'D:\Godot\4.7.2\godot.exe' --path . res://scenes/a_test/a_controls_test.tscn -- a_controls_probe
```

分两段：

- **同步段**（`controls_probe.gd`）：真实窗口里用与游玩完全相同的 `PuppetController`
  输入接口走完整链路（胸签命中 → 拖动 → 状态 → 事件），打印转身过渡帧数、站蹲两端、
  双手数值、冲突冻结、240 帧边界压力、第一关时长与数据校验。
- **逐帧段**（`clock_check.gd`）：用真实墙钟做对照，测量歌曲时间推进速度（漂移）、
  暂停期间是否完全冻结、恢复后是否从冻结值继续（不跳变、不把暂停时长算进歌曲时间），
  并断言 `is_audio_driven()` 为真。

**为什么需要它：**验证者无法向运行中的窗口注入真实鼠标/键盘事件，
而「脚本能解析」不等于「操控与时钟正确」。本模式让图形环境下的可测量行为留下
可复现证据。

## 3. 人工实测（必须由人在图形环境完成）

```powershell
& 'D:\Godot\4.7.2\godot.exe' --path . res://scenes/a_test/a_controls_test.tscn
```

脚本化实测与无头测试都**不能**替代以下人工确认：

- 真实鼠标按住胸签拖动的**手感**是否跟手、身位与手指是否对得上；
- 真实键盘按住 `A`/`D`/`Shift+A`/`Shift+D`/`W`/`S` 的连续变化与松开保持；
- 画面上转身是否看得出「渐进翻面」而不是跳变；
- **是否真的听见临时节拍音**（代码只能证明音频在播放、位置在正确推进）；
- 按空格暂停后是否**听得出**音频停住、再按一次是否从原处继续而没有重复拍子；
- 在 1920×1080 目标分辨率下整台与 HUD 是否完整可见。

## 4. 每轮三项门禁（`TECH_DESIGN.md` 第 1.2 节）

```powershell
& 'D:\Godot\4.7.2\godot.exe' --headless --path . --import
& 'D:\Godot\4.7.2\godot.exe' --headless --path . --quit-after 60
& 'D:\Godot\4.7.2\godot.exe' --headless --path . --export-release "Windows Desktop" "builds/dengxia.exe"
```

无头模式使用虚拟音频驱动，因此这三项通过**不能**证明音频、手感或画面正确。

## 5. 关于音频来源

B 的正式锣鼓主音轨尚未交付。A 的测试场景用 `scripts/a_test/metronome.gd` 现场合成
节拍音（`AudioStreamGenerator`），不引用任何素材文件、不改 B 的正式音频目录。
拿到正式音轨后必须复测时钟与拍点对齐，在复测之前不得宣称「已与正式音轨对齐」。
