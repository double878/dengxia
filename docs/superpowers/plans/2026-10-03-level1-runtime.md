# Level 1 A Runtime Implementation Plan

> **For agentic workers:** Execute inline in this session. Do not dispatch subagents.

**Goal:** 将现有 A 侧操控、MusicClock、Cue 判定、8 秒补救、油灯和 35 秒结束串成独立的第一关运行场景。

**Architecture:** `Level1Runtime` 只编排已有模块，统一输出一条 `TimedEvent` 流；`Level1Harness` 负责真实场景中的音频时钟、输入轮询和固定步长；`level1_a.tscn` 只读状态并显示占位影人、油灯、提示、补救和事件接收结果。

**Tech Stack:** Godot 4.7.2 Standard、GDScript、现有 `MusicClock`、`PuppetController`、`StageDirector`、`LampController`。

## Global Constraints

- 不修改 `project.godot`、`export_presets.cfg`、`PRD.md`、`TECH_DESIGN.md`。
- 不修改 B/C 文件，不制作幕前预览、分屏、分数 UI、自动代演或预制回放。
- 不把 `a_controls_test.tscn` 继续作为第一关入口。
- 所有判定、补救、油灯消耗使用同一个 `MusicClock` 歌曲时间。

### Task 1: Runtime orchestration

**Files:**
- Create: `scripts/a/level1_runtime.gd`
- Test: `tests/a/test_level1_runtime.gd`
- Modify: `tests/a/run_tests.gd`

`Level1Runtime.tick(delta)` 的固定顺序为：操控状态 → `StageDirector.update()` → `LampController.update()` → 事件合并；结束时调用 `LampController.finish_show()`。

### Task 2: Standalone playable A scene

**Files:**
- Create: `scripts/a_test/level1_harness.gd`
- Create: `scripts/a_test/level1_a_scene.gd`
- Create: `scripts/a_test/level1_a_probe.gd`
- Create: `scenes/a_test/level1_a.tscn`

场景只读取状态，显示第一关时间、油灯四字段、当前 Cue 提示、补救示范/倒计时、暂停状态和模拟接收端最近事件。

### Task 3: Verification and handoff

运行 A 行为测试、图形探针、资源导入、无头启动和 Windows 导出；确认工作区只包含切片 6 文件，并输出 B/C 的接口需求与最小接入建议。

---
