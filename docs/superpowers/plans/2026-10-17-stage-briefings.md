# 三关演前简介 Implementation Plan

> **Execution:** Implement authorized tasks in the current chat, respecting dependency order and the user's stage boundaries. Use subagents only when the user explicitly requests or approves them. Track steps with checkbox (`- [ ]`) syntax.

**Goal:** 三关均显示参考第三关的标题、剧情目标、操作、声音说明与“开演”，确认后才开始演出。

**Architecture:** 提取第三关现有版式为 `scripts/ui/stage_briefing.gd`；第三关沿用自身 `start_scene()`，第一、二关由 `GameFlow` 在实例化宿主之前展示同一组件。第二关换到厅堂时不重复简介。

**Tech Stack:** Godot `4.7.2.stable.official.ed1daf0bf`、GDScript、现有 Control / Label / Button。

## Global Constraints

- 用户截图为版式参考；第一、二关文案依当前玩法、音源和操作编写，第三关保留现有内容。
- 简介期间不播放对白/音乐、不推进双时钟、不采集演出；点击后才建立第一、二关宿主。
- 按钮单次生效、延后换景，背景点击及普通游戏按键不直接开演。
- 首页、片头、真实回放、首两关收场、片尾与排练入口保持串接。
- 不修改 `project.godot`、资源缓存、玩法判定和演出记录格式。
- 保留已有未跟踪资源；只提交本任务文件。

### Task 1: 简介组件与入口

**Files:** Create `scripts/ui/stage_briefing.gd`; modify `scripts/game_flow.gd`, `scripts/act3/act3_opening.gd`.

**Interfaces:** `stage_id: int` 在加入场景树前指定；`start_requested` 发出一次；`audio_note: Label` 供第三关更新真实音源状态。

- [x] 复用第三关原始坐标和色彩，集中三关内容到 `BRIEFINGS`，保留 `StartScene` 按钮名。
- [x] 第一、二关使用如下入口；第三关直接进入既有候场宿主，避免双简介：

```gdscript
func _show_briefing() -> void:
    if _stage_id not in [1, 2]:
        _start_performance()
        return
    _clear_page()
    var briefing := StageBriefing.new()
    briefing.stage_id = _stage_id
    briefing.start_requested.connect(_briefing_finished, CONNECT_DEFERRED)
    _page = briefing
    add_child(briefing)
```

- [x] 片头结束、第一关收场/跳过、重新演出均进入相应简介；第二关场内换景直接进入厅堂。
- [x] 第三关改用同一组件，原 `start_scene()` 与音源错误提示继续有效。
- [x] 所有修改脚本先 `--headless --path . --check-only --script res://<脚本>`，再执行定向验证。

### Task 2: 验证与交付

**Files:** Create `tests/b/run_stage_briefings.gd`, `docs/stage-briefings-delivery.md`; update touched entry tests, `PRD.md`, `TECH_DESIGN.md`.

**Input:** 实际三关宿主、统一简介组件、现有回归入口。
**Output:** 三关截图、Windows/WASAPI 记录、相关回归及导出结果。

- [x] 验证三张简介画面与文案、静音等待、游戏按键不推进、点击开演只生效一次，点击不穿透操演。
- [x] 更新原录放测试的入口准备，使它们在简介确认之后才测试演出。
- [x] 跑第一关录放、第二关入口及场内换景、第三关真实结尾，匹配变更后的等待与开演行为。
- [x] 运行资源导入、无头启动、Windows release 导出及导出包图形复验；逐项记录通过与既有告警。
- [x] `git diff --check`，核对任务范围，提交并推送 `feat-stage-briefings`。
