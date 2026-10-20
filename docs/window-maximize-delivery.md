# Windows 最大化与退出修复

2026-10-20。用户报告放大为全屏后卡住，关闭按钮无效，只能结束进程。

## 复现与修复

本机 Windows、Intel Arc Graphics `31.0.101.5382`、2880×1920 高 DPI 屏幕；Godot `4.7.2.stable.official.ed1daf0bf`。

原生 OpenGL 下，仅启动首页、发送与标题栏最大化相同的 `WM_SYSCOMMAND/SC_MAXIMIZE`，窗口即停止响应；`WM_NULL` 的 1.5 秒响应检查失败，`WM_CLOSE` 后 4 秒仍不退出。测试只终止自己启动的进程。现场见 `builds/window-resize/baseline-result.json` 与 `baseline.log`。

保持同一工程，只增加 `--rendering-driver opengl3_angle`，最大化、还原、再次最大化及正常关闭全部成功，退出码 0。日志确认实际后端为 ANGLE / Direct3D 11。该对照定位到本机原生 OpenGL 的窗口变化路径，不将其误写为关卡逻辑或音频冻结。

修复仅在 `project.godot` 增加 `gl_compatibility/driver.windows="opengl3_angle"`，继续使用 Godot Compatibility 渲染器和原有画布/开窗尺寸。不禁用最大化，不新增运行依赖，不改变演出或录放状态。

## 正式回归

`tests/b/check_window_resize.py` 使用 Python 标准库及真实 Win32 窗口消息。检查只选择自己启动的进程；两轮最大化/还原逐项检查响应及 `IsZoomed` 状态，防止以禁用最大化掩盖错误；最后发送正常关闭消息并验证进程退出 0。窗口发现最多 10 秒、单次响应最多 1.5 秒、关闭最多 4 秒，失败后清理该测试进程并返回 1。完整全屏通过 Godot 的 `--fullscreen` 启动参数验证。

```powershell
py -3.13 -m py_compile tests/b/check_window_resize.py
py -3.13 tests/b/check_window_resize.py
py -3.13 tests/b/check_window_resize.py --intro
py -3.13 tests/b/check_window_resize.py --fullscreen
py -3.13 tests/b/check_window_resize.py --fullscreen --intro
py -3.13 tests/b/check_window_resize.py --scene res://scenes/a_test/level1_a.tscn
py -3.13 tests/b/check_window_resize.py --scene res://scenes/act2/opening.tscn
py -3.13 tests/b/check_window_resize.py --scene res://scenes/act2/hall.tscn
py -3.13 tests/b/check_window_resize.py --scene res://scenes/act3/opening.tscn
py -3.13 tests/b/check_window_resize.py --exe builds/dengxia.exe
py -3.13 tests/b/check_window_resize.py --exe builds/dengxia.exe --intro
py -3.13 tests/b/check_window_resize.py --exe builds/dengxia.exe --fullscreen
py -3.13 tests/b/check_window_resize.py --exe builds/dengxia.exe --fullscreen --intro
```

源工程 8 组、实际发布 exe 4 组均通过，正常关闭退出码均为 0；12 组的 JSON 和日志分别保存在 `builds/window-resize/source-*.json/.log`、`packed-*.json/.log`。原版运行正式回归曾得到 `WINDOW_RESIZE_PASS=False`，改配置后为 `True`。

## 图形、媒体与门禁

统一经 `tools/run_godot.ps1` 调用同一个 Godot 可执行文件。

| 实际命令参数 | 结果 |
| --- | --- |
| `--path . --maximized --script res://tests/b/run_cinematics_graphics.gd` | 真实 Windows / WASAPI，49 项检查、0 失败，退出 0 |
| `--headless --path . --import` | 退出 0 |
| `--headless --path . --quit-after 60` | 退出 0 |
| `--headless --path . --export-release "Windows Desktop" builds/dengxia.exe` | 退出 0，更新实际正式 exe 与 PCK |

图形回归在最大化窗口完整播放片头与片尾、验证暂停/恢复及真实回放接线；实际混音暂停峰值 0，片头约 0.381、片尾约 0.570。已查看 `builds/cinematics/01-home.png` 和 `04-first-level.png`，画面为 2880×1620，保留 16:9，无拉伸或裁切。结果详见 `builds/cinematics/verification.json`；门禁日志前缀为 `builds/stage-realism/logs/window-angle-*`。

交付程序为 `builds/dengxia.exe`（109,127,680 字节）和同目录 `dengxia.pck`（223,569,496 字节），2026-10-20 重新导出。发布 exe 的实际图形日志同样确认 ANGLE / Direct3D 11，不依赖命令行临时覆盖。

验证范围是本机窗口、图形与视频，不包含重新手动演完全部三关，也不将混音读数视为人工听感验收。
