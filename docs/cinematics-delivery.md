# 首页与片头片尾接入

2026-10-17，按用户“AA，取消原有最终收场页，点击任意处回到首页，A”实现。

## 实际流程

- 普通启动：用户首页原图 → 任意键或左/右/中键点击 → 片头 → 第一关。
- 第三关：真实演出结束 → 观看选择 → 不看、回放跳过或自然结束 → 片尾。
- 片尾结束或 Esc 跳过后，保留源片最后一帧和“点击任意处回到首页”；点击后释放旧记录并重置第一关。回首页的点击不会同时开启下一轮片头。
- 播片支持空格暂停/继续、Esc 跳过；其他按键和点击不会结束视频。按键连发、松开及滚轮不触发首页或最终返回。
- 第一、二关收场沿用原流程；指定关号、`initial_stage` 和 `--act3-rehearsal` 保持直接排练。

`scripts/ui/media_screen.gd` 只负责媒体显示与输入；`scripts/game_flow.gd` 串接首页、演出和片尾。播放片头时尚未创建第一关，不消耗演出时间；片尾开始前已停止回放并释放记录。没有改动关卡玩法或真实回放格式。

## 素材与转换

| 用户素材 | 游戏资源 | 实际规格 |
| --- | --- | --- |
| `codex-clipboard-ebd7a8a5-df12-4abf-bddf-742ecce3e7b7.png` | `assets/cinematics/title.png` | 原文件逐字节复制，2048×1152，哈希一致 |
| 第一个视频 `96cd9ff2abeaf962d006d20686ed36f6.mp4` | `assets/cinematics/intro.ogv` | 34.57 秒，1280×720，30fps，立体声 44.1kHz |
| 第二个视频 `3c432ed05887ae0efe32e44e45b6954d.mp4` | `assets/cinematics/outro.ogv` | 12.59 秒，1280×720，30fps，立体声 44.1kHz |
| 第二个视频实际最后一帧 | `assets/cinematics/outro-last.png` | 保留原片淡出后的暗画面，叠加返回提示 |

两段 OGV 使用 Godot 内置 Theora/Vorbis，无运行时 FFmpeg、外部播放器或插件。开发时 FFmpeg 使用 `-map 0:v:0 -map 0:a:0 -map_metadata -1 -c:v libtheora -q:v 7 -pix_fmt yuv420p -c:a libvorbis -q:a 5`，没有裁掉头尾或重做声音。最后一帧用 `-sseof -1 -i <第二个视频> -an -update 1` 提取。转码文件均通过 `-v error -xerror -i <ogv> -f null -` 完整解码。

两段视频 SHA-256：

```text
intro.ogv f6d61a4c06a9915053fa95a763995083848ccf129adf7d712070fdf3b2078768
outro.ogv 3152c9306de8f2f67325884c1a51452d4667a53524c6e62ad4ac4c4b191c6aa3
```

## 验证命令与结果

统一通过 `tools/run_godot.ps1` 调用 `D:\Godot\4.7.2\godot.exe`，实际版本 `4.7.2.stable.official.ed1daf0bf`。所有修改的 GDScript 先用 `--headless --path . --check-only --script res://<脚本>` 解析，通过后才运行对应回归。

| 检查 | 实际结果 |
| --- | --- |
| 源工程 Windows/WASAPI 媒体回归 | 48 项，0 失败；两段视频按真实时间完整播放，暂停无声且位置冻结，验证按键/点击、跳过、三条回放结束路径和回首页 |
| 第一关 `tests/c/run_game_replay.gd` | 37 项，0 失败；真实记录 44,283ms、2,181 快照、2,981 事件 |
| 第二关入口 `tests/c/run_act2_opening.gd` | 169 项，0 失败；首两关转场和跳关保持可用 |
| 第三关 `tests/c/run_act3_finale.gd` | 61 项，0 失败；真实结尾与记录回放后进入片尾并释放记录 |
| `--headless --path . --import` | 退出码 0，最终导入日志无错误 |
| `--headless --path . --quit-after 60` | 退出码 0 |
| Windows Desktop release 导出 | 退出码 0，生成 `builds/dengxia.exe` 与 `builds/dengxia.pck` |
| 导出 exe 普通图形入口 `--quit-after 120` | 实际 Intel Arc OpenGL Compatibility，退出码 0，无错误日志 |
| 同版本引擎加载实际 PCK 的媒体回归 | 49 项，0 失败；比首轮源工程多一个外部输出目录检查。结果与截图归档在 `builds/cinematics-packed/` |

可复跑命令：

```powershell
& .\tools\run_godot.ps1 -LogName cinematics-windows --path . --script res://tests/b/run_cinematics_graphics.gd
& .\tools\run_godot.ps1 -LogName cinematics-act1-replay --headless --path . --script res://tests/c/run_game_replay.gd
& .\tools\run_godot.ps1 -LogName cinematics-act2-entry --headless --path . --script res://tests/c/run_act2_opening.gd
& .\tools\run_godot.ps1 -LogName cinematics-act3-finale --headless --path . --script res://tests/c/run_act3_finale.gd
& .\tools\run_godot.ps1 -LogName cinematics-import --headless --path . --import
& .\tools\run_godot.ps1 -LogName cinematics-smoke --headless --path . --quit-after 60
& .\tools\run_godot.ps1 -LogName cinematics-export --headless --path . --export-release '"Windows Desktop"' builds/dengxia.exe
& .\tools\run_godot.ps1 -LogName cinematics-packed-windows --path . --main-pack builds/dengxia.pck --script res://tests/b/run_cinematics_graphics.gd
```

包装脚本通过 `Start-Process -ArgumentList` 调用 GUI 引擎，因此带空格的导出预设需保留内层双引号。测试先将输出目录解析成绝对路径，避免向 PCK 的资源目录申请创建文件夹；重跑默认更新 `builds/cinematics/`。

源工程媒体混音最大峰值：片头约 0.381、片尾约 0.570，暂停为 0。真实 Windows 画面截图为 `builds/cinematics/01-home.png` 至 `07-home-again.png`，打包复验截图位于 `builds/cinematics-packed/`。已实际查看首页、片头和结束页，确认画面无拉伸、完整显示、提示可见。

## 验证边界与既有告警

媒体回归用真实完整视频与实际 Windows 音频混音；三条第三关结束路径用宿主产生的短演出记录验证接线，第三关完整结尾逻辑另由既有 `run_act3_finale.gd` 覆盖。没有重新手动演完全部三关，也不把混音非静音描述为人工听验。

第一关旧录放脚本退出仍报告 2 个 ObjectDB 实例和 1 个资源未释放。使用本轮修改前 `HEAD` 的 `GameFlow` 及同一回归脚本独立复跑，得到相同 37 项通过与相同告警，确认属于既有基线；本轮媒体回归、入口冒烟、导出及发布图形启动没有该告警。用于比较的临时入口与暂停诊断脚本已删除。

交付程序为 `builds/dengxia.exe`，运行时保留同目录 `dengxia.pck`。所有媒体在包内，启动不依赖微信临时目录或原始 MP4。
