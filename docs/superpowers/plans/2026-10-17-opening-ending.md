# 开场图片与片头片尾接入 Implementation Plan

> **Execution:** Implement authorized tasks in the current chat, respecting dependency order and the user's stage boundaries. Use subagents only when the user explicitly requests or approves them. Track steps with checkbox (`- [x]`) syntax.

**Goal:** 首页图片 → 片头 → 第一关；第三关真实回放结束或不看回放 → 片尾 → 点击回首页。

**Architecture:** 保持 `GameFlow` 为唯一入口，增加一个只负责全屏图片、视频、暂停和结束等待的 `MediaScreen`。第三关沿用回放选择，原有最终收场页由片尾取代；第一、二关收场不变。排练入口仍直接进入指定关卡。

**Tech Stack:** Godot 4.7.2 Standard、GDScript、TextureRect、VideoStreamPlayer、Theora/Vorbis OGV；FFmpeg 只用于开发期转换。

## Global Constraints

- 引擎固定 `D:\Godot\4.7.2\godot.exe`，版本 `4.7.2.stable.official.ed1daf0bf`。
- 不修改 `project.godot`、既有关卡演出或记录格式，不增加运行时插件。
- 原图不重复叠加已有“按任意键”文字；画面等比完整显示，保留视频原声。
- 首页接受键盘按下和左/右/中键点击；忽略按键重复、松开、移动和滚轮。
- 播片期间只允许空格暂停/继续、Esc 跳过；输入不传入关卡。
- 片尾完成或跳过后显示源视频最后一帧和点击返回提示，下一次点击返回首页；不循环、不自动重开。
- 保留工作区已有 `.workbuddy/`、`output/`、PDF 工具和参考图片，不暂存无关文件。
- 基于当前含完整三关的版本创建 `feat-opening-ending`；`origin/main` 已是当前版本的祖先。

### Task 1: 媒体资源与独立播放页

**Files:**
- Create: `assets/cinematics/title.png`, `intro.ogv`, `outro.ogv`, `outro-last.png`
- Create: `scripts/ui/media_screen.gd`

**Interfaces:**
- Consumes: 用户图片、按提供顺序排列的两个 MP4。
- Produces: `MediaScreen.finished`；实例在加入场景树前配置 `image: Texture2D`、`stream: VideoStream`、`end_image: Texture2D`。
- `stream == null` 时显示首页，`end_image != null` 时视频结束等待点击，否则结束直接发信号。

- [x] 使用 FFmpeg 映射首个视频与音频流，转为 `libtheora -q:v 7` / `libvorbis -q:a 5`；提取片尾最后一帧，复制原始首页图。
- [x] 播放页实现下列唯一输入边界，并在发送信号前锁定离开状态：

```gdscript
if event is InputEventKey and event.pressed and not event.echo:
    if waiting and stream == null:
        _leave()
    elif not waiting and event.keycode == KEY_SPACE:
        player.paused = not player.paused
    elif not waiting and event.keycode == KEY_ESCAPE:
        _clip_finished()
```

- [x] 视频完成后先停播放器；有 `end_image` 时显示它并等待下一次鼠标点击，没有则发出 `finished`。退出场景时停止播放器。
- [x] 解析检查该脚本，再验证实际 Windows 播放、声音、暂停与自然结束。

### Task 2: 入口与最终回放衔接

**Files:**
- Modify: `scripts/game_flow.gd`, `PRD.md`, `TECH_DESIGN.md`
- Create: `tests/b/run_cinematics_graphics.gd`, `docs/cinematics-delivery.md`

**Interfaces:**
- Consumes: Task 1 的 `MediaScreen.finished` 和媒体资源。
- Produces: `_show_home()`、`_play_intro()`、`_play_outro()`；`_show_page(false)` 仅在第三关转入片尾。

- [x] `_ready()` 默认显示首页，保留 `initial_stage` 与 `--act3-rehearsal` 直达入口。
- [x] 首页完成后进入片头，片头完成后再实例化第一关；返回首页释放第三关回放记录并重置关号。
- [x] 第三关不看回放、回放跳过、回放自然结束统一走片尾；首两关保持既有收场路径。
- [x] 保留正式 Windows 回归入口，验证首页按键/点击、无输入自动推进、片头自然结束、暂停无声、Esc、第三关三条结束路径、最终点击返回、输入不连跳及排练入口。
- [x] 先做脚本解析，再执行相关回归与资源导入、无头启动、Windows release 导出三项门禁；检查导出包包含媒体并实际启动。
- [x] 更新需求补充与交付证据；`git diff --check` 后仅暂存本任务文件，提交并推送功能分支。
