# 法海与两关衔接 Implementation Plan

> **For agentic workers:** Use executing-plans in the current `feat-act2` branch. 用户要求直接实现且不使用子智能体；无需再次选择执行方式。

**Goal:** 制作可操纵的法海分件，并从第一关任意收场路径点击进入正式第二关开场。

**Architecture:** 分件沿用现有 512px tile atlas，视图通过独立 skin_override 选择法海，运行影人编号仍为 0/1。第二关开场复用唯一 MusicClock、现有操控和幕布渲染；GameFlow 负责一次性清理第一关并加载新场景。

**Tech Stack:** Godot 4.7.2 Standard、GDScript、Pillow 和 NumPy（仅素材制作）。

## Global Constraints

- 分支 `feat-act2`，不使用子智能体，不改变第一关演出和初次回放选择。
- 统一 `D:\Godot\4.7.2\godot.exe`；每轮解析优先，再相关回归，收尾执行导入/启动/Windows 导出。
- 演出只显示幕后；显示只读状态，灯距影响所有影子。
- 本切片仅开场操演，不伪称完整第二关剧情和录放已完成。

## Task 1: 素材与第二关开场

**Files:** `tools/build_fahai_assets.py`、`assets/puppets/fahai.png`、`assets/puppets/puppet_assets.json`、`scripts/a_test/placeholder_puppet.gd`、`scripts/act2/act2_opening.gd`、`scenes/act2/opening.tscn`、`tests/c/run_act2_opening.gd`。

**Interfaces:** 视图 `skin_override: int = -1`（3 为法海）；开场提供 `controller: PuppetController`、`on_stage: Array[int]` 和可使用真实输入的场景。

- [x] 写回归：当前结果页不应有重看/重演按钮，新开场必须存在；验证旧实现失败。
- [x] 保存参考原图，按手工轮廓提取分件和镂空，生成透明 atlas，锡杖独立绑到手腕。用 `py -3.13 tools/build_fahai_assets.py` 可重建。
- [x] 在视图中加入法海皮肤覆盖和持杖分件，旧角色默认行为不变。
- [x] 新建开场，`1/2` 只上场、空格循环接手、右键退场、ESC 暂停；复用输入读取和现有控制器。
- [x] 解析并运行相关回归，在 Windows 窗口截图检查抬手、翻面和灯光一致性。

## Task 2: 第一关收场到第二关

**Files:** `scripts/game_flow.gd`、`tests/c/run_act2_opening.gd`、`PRD.md`、`TECH_DESIGN.md`、`README.md`。

**Interfaces:** GameFlow 的第一关 result 状态消费鼠标左/中/右键 pressed，延后切换、释放 CResultFlow 并实例化 `res://scenes/act2/opening.tscn`。

- [x] 测试不看、跳过、自然回放结束三条路径；点击选择页、滚轮和鼠标释放不得切关。
- [x] 移除第一关收场按钮，所有装饰 Control 忽略鼠标，消费有效点击后只切换一次。
- [x] 验证旧记录释放、旧回放/音源停止、点击不穿透到新场景。
- [x] 文档注明用户定案优先于旧换头/挂钩和 105 秒条款，并说明本次交付边界。
- [x] 对改动运行 gdformat/gdlint、解析和相关既有回归，执行三项 Godot 门禁及 Windows 图形回归。
- [x] 自查 diff 与临时产物，只暂存任务文件，按可验证切片提交并 push `feat-act2`。

验证证据见 docs/act2-opening-delivery.md。
