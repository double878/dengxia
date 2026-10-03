# A 范围测试说明（第一关操控与关卡逻辑）

工具链统一为 Godot `4.7.2.stable.official.ed1daf0bf`。以下命令都假设在仓库根目录执行，
`godot.exe` 取本机同一版本路径（示例为 `D:\Godot\4.7.2\godot.exe`）。

## 1. 无头行为测试（回归门禁，退出码 0/1）

```powershell
& 'D:\Godot\4.7.2\godot.exe' --headless --path . --script res://tests/a/run_tests.gd
```

覆盖切片 1 的 11 条行为：初始不变量、胸签命中、横向与纵向拖动及两端截断、
转身渐进过渡、双手独立与双手同动、按住连续/松开保持、相反指令保持姿势、
连续量边界、`TimedEvent` 契约与取走即清空、状态先于事件。

## 2. 图形环境脚本化实测（真实窗口，退出码 0/1）

```powershell
& 'D:\Godot\4.7.2\godot.exe' --path . res://scenes/a_test/a_controls_test.tscn -- a_controls_probe
```

在真实窗口里用与游玩完全相同的 `PuppetController` 输入接口走完整链路
（胸签命中 → 拖动 → 状态 → 事件），并把可核对数值打到 stdout：转身过渡帧数、
站蹲两端、双手数值、冲突冻结、240 帧边界压力。

**为什么需要它：**验证者无法向运行中的窗口注入真实鼠标/键盘事件，
而「脚本能解析」不等于「操控正确」。本模式让图形环境下的可测量行为留下
可复现证据。

## 3. 人工实测（必须由人在图形环境完成）

```powershell
& 'D:\Godot\4.7.2\godot.exe' --path . res://scenes/a_test/a_controls_test.tscn
```

脚本化实测与无头测试都**不能**替代以下人工确认：

- 真实鼠标按住胸签拖动的**手感**是否跟手、身位与手指是否对得上；
- 真实键盘按住 `A`/`D`/`Shift+A`/`Shift+D`/`W`/`S` 的连续变化与松开保持；
- 画面上转身是否看得出「渐进翻面」而不是跳变；
- 在 1920×1080 目标分辨率下整台与 HUD 是否完整可见。

## 4. 每轮三项门禁（`TECH_DESIGN.md` 第 1.2 节）

```powershell
& 'D:\Godot\4.7.2\godot.exe' --headless --path . --import
& 'D:\Godot\4.7.2\godot.exe' --headless --path . --quit-after 60
& 'D:\Godot\4.7.2\godot.exe' --headless --path . --export-release "Windows Desktop" "builds/dengxia.exe"
```

无头模式使用虚拟音频驱动，因此这三项通过**不能**证明音频、手感或画面正确。
