# 舞台实物质感升级交付与验证

依据已批准的 `stage-realism-plan.md`。视觉实现、独立幕前验收及 Windows 普通入口图形启动已完成；正式演出记录回放未接入。

## 实际修改

- 原创棉纹、木纹及可重建源；连续漫透射、包边、绷布结、角部拉痕、木框接合、木销、立柱和台面拼缝。
- 固定实体与幕影分层，实体竹签连接胸部/手腕；幕影与伞共用离屏透射，相乘叠色、彩色透皮、明亮镂空、局部窄柔边、轻斜切与偏移。取消幕上脚底椭圆。
- 小碗油灯的足圈、油面、灯芯、反光、曲线火焰与局部光晕；自然闪烁读真实时间、拍脉冲读歌曲时间，暂停冻结，高反馈更稳，低油仍可操作。
- 伞保留原归属、垂直柄、大伞面和手腕挂点；实体与投影各自计算显示挂点，真实低手还伞过渡已有回归。
- 开发场景覆盖亮/暗、远/近、三人、重叠、换头、翻面、边界与离幕柔边。正常演出没有幕前预览。静止分件按需重绘。

## 实际验证

统一执行文件 `D:\Godot\4.7.2\godot.exe`，精确版本 `4.7.2.stable.official.ed1daf0bf`，对应模板，Compatibility / Intel Arc / OpenGL 3.3。下列参数由 `tools/run_godot.ps1` 等待真实进程结束并保留 stdout/stderr。解析检查已逐个运行。

```powershell
& .\tools\run_godot.ps1 -LogName import --headless --path . --import
& .\tools\run_godot.ps1 -LogName startup --headless --path . --quit-after 60
& .\tools\run_godot.ps1 -LogName export --headless --path . --export-release '"Windows Desktop"' builds/dengxia.exe
& .\tools\run_godot.ps1 -LogName test-a --headless --path . --script res://tests/a/run_tests.gd
& .\tools\run_godot.ps1 -LogName test-b --headless --path . --script res://tests/b/run_stage_visuals.gd
& .\tools\run_godot.ps1 -LogName graphics --path . --resolution 1920x1080 --script res://tests/b/stage_graphics_probe.gd
& .\tools\run_godot.ps1 -LogName backstage --path . --resolution 1920x1080 --script res://tests/b/backstage_graphics_probe.gd
```

| 验证 | 结果 |
| --- | --- |
| 导入 / 无头启动 / Windows 导出 | 退出码均为 0。 |
| A 全量回归 | 1277 条通过，0 条失败。 |
| 新 B 行为回归 | 270 条通过，0 条失败。实体固定尺寸/腕点/命中，全场含挂起者缩放，确定性火光，反馈高更稳，实体/投影伞及交接。 |
| 实际幕前图形探针 | 35 项通过，0 失败。包含纹理色/alpha 不重复相乘、孔透光、染色、重叠变暗、镜像、裁切、暂停逐像素冻结、恢复及样例实际改变幕面。 |
| 正常入口幕后图形探针 | 14 项通过，0 失败。注入原输入事件验证滚轮、胸签拖动、实体腕点与低光、暂停。此项是程序注入，不是人工鼠标手感或听觉验收。 |
| 打包 PCK 图形探针 | 同版本 godot.exe 读取实际 PCK，幕后 14 项、幕前 35 项均通过，0 失败。证明打包后的材质、场景、输入接线可运行。 |
| 导出 exe 无头启动 | 退出码 0。 |
| 导出 exe 图形启动 | 普通入口带 `--resolution 1920x1080 --quit-after 480 -- diag` 完成 480 帧，退出码 0；实际窗口与设计坐标均为 1920×1080，稳定段诊断 FPS 58–61，advance/UI 每帧约 0–1 ms。初始加载期 FPS 读数包含启动开销，不作为稳态指标。 |

已有基线告警仍存在：强制无头启动退出有 2 个 ObjectDB 泄漏；A 回归的故意非法 cue 输入会输出错误，退出有 4 个 ObjectDB / 1 个资源告警。这些是基线现象，不描述为干净日志。正式图形探针正常释放场景，无新增资源泄漏或 shader 错误。

早期尝试用 `--script` 运行发布 exe 的探针没有进入脚本。后核查 Godot 帮助，`--script` 属于 X 类参数，默认 release 模板禁用路径覆盖；这不是游戏图形启动故障。发布 exe 用普通主场景入口验证，探针改为同版本引擎加载 PCK。失败日志保留，所有本任务超时进程已终止。外部屏幕截图未作为最终证据使用；可信图像来自 GPU viewport 读取。

## 可亲眼检查的入口与证据

源码正常演出：`D:\Godot\4.7.2\godot.exe --path D:\Cursor_program\灯下`。

独立幕前场景：`D:\Godot\4.7.2\godot.exe --path D:\Cursor_program\灯下 res://scenes/b/stage_visual_lab.tscn`。Tab 和方向键仅属于开发场景。

实际打包资源的可验证运行入口：

```powershell
& .\tools\run_godot.ps1 -LogName packed --path . --main-pack builds/dengxia.pck --resolution 1920x1080 --script res://tests/b/backstage_graphics_probe.gd -- output=D:/Cursor_program/灯下/builds/stage-realism/packed
```

PCK 为只读资源包，图形探针输出应使用绝对路径或 `user://`，不要写入包内 `res://`。`builds/.gdignore` 防止截图、日志、临时入口被导入或打包；只有本任务临时入口会清理。小青基线及用户的设计文件/临时测试均保留。

证据在忽略目录 `builds/stage-realism/`：`before.png` 为原始 1280×720 基线；`backstage.png`、`backstage-near.png`、`backstage-far.png`、`backstage-low-game.png`、`backstage-paused.png` 为升级后正常入口 1920×1080；`front-final/` 为源码幕前固定样例、光学色片与原始指标；`packed/`、`packed-front-final/` 为最终实际 PCK 图形证据；`logs/` 保留成功与失败日志。

## 性能和剩余验收

Intel Arc、1920×1080、每侧 240 帧的短样本：源码幕后平均 16.88 ms / P95 17.77 ms / 最大 50.99 ms；源码幕前平均 16.81 ms / P95 19.61 ms / 最大 54.97 ms；实际 PCK 幕后平均 17.49 ms / P95 19.68 ms / 最大 66.59 ms，最终幕前平均 16.82 ms / P95 19.41 ms / 最大 49.51 ms。数值含垂直同步及系统调度，有偶发长帧，不能外推为五关稳定 60 FPS。

尚待：目标比赛机适配、人工键鼠/音频体验、五关长流程性能，以及 Recorder/Replay 接入后的真实动作、灯况、伞交接、镜像、暂停与 1:1 时长核对。历史资料未提供统一实测透光率、灯距、火焰频谱；所有渲染参数仍标作设计值。
