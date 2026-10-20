# 跳劈与鹤童活动范围 Implementation Plan

> **Execution:** Implement authorized tasks in the current chat, respecting dependency order and the user's stage boundaries. Use subagents only when the user explicitly requests or approves them. Track steps with checkbox (`- [x]`) syntax.

**Goal:** 第三关白素贞拔剑后按 W 短跳并下劈；鹤童围绕她搭戏，留出自由操演空间。

**Architecture:** 沿用共用短跳和状态录放；第三关搭戏器仅在本关 W 输入时附加持剑臂动作。鹤童蓄势时捕获白素贞位置和出招侧，随后将原招式横移夹紧到这次出招的搭戏范围；不移动白素贞。

**Tech Stack:** Godot 4.7.2 Standard / GDScript / 现有 Windows 探针。

## Global Constraints

- 同一个 `D:\Godot\4.7.2\godot.exe`；先解析修改脚本，再定向回归，最后资源导入、无头启动、Windows 导出及导出包检查。
- 第一、二关与完整白蛇操作沿用；第三关出鞘前 W 仍为普通短跳，出鞘后才跳劈。
- 张腿短跳仍合计 0.46 秒、原地锁身、按住不连跳，暂停冻结动作；唱腔持续。
- 持剑手沿用最新截图定案 `left`；落地恢复此前手姿，原状态进入正式录放。
- 不加血量、动作门槛、强制跌倒或新的音效，不改变出山与接战时标。

### Task 1: W 跳劈

**Files:** `scripts/act3/act3_opening.gd`, `scripts/act3/fight_choreography.gd`, `tests/c/run_act3_fight.gd`, `tests/b/run_combat_motion_graphics.gd`。

**Input:** 正式 W 输入、现有 `controller.motion.elapsed` 与 `draw_progress`。

**Output:** 单次持剑手由原姿抬起，再下劈，最后恢复；位置和空手不变。

- [x] 在原正式宿主测试中按 W，比较提剑与下劈的实际剑尖方向；先确认现有实现失败。
- [x] 在宿主 W 分支请求搭戏器启动跳劈；仅接受当前白素贞、进行中的短跳和已出鞘三条件。保存持剑手原姿，沿短跳经过的时间抬剑（0–0.14s）、下劈（0.14–0.30s）、恢复（0.32–0.46s）。动作结束或取消立即清理。
- [x] 定向回归确认锁身、空手保持、落地复原与可重复触发；Windows 实际渲染和原声探针截图覆盖提剑/下劈及同次回放。

### Task 2: 鹤童留出操作空间

**Files:** `scripts/act3/fight_choreography.gd`, `tests/c/run_act3_fight.gd`。

**Input:** 原六套招式、蓄势阶段的白素贞位置与鹤童所在侧。

**Output:** 鹤童通常在距离 200–340px 内搭戏，准备位 280px；靠边按舞台可用余量缩短，不强制跨过玩家换侧。

- [x] 使用 60Hz、两轮招式分别观察白素贞 x=0.20/0.56/0.80；现有证据最大间距 464px、右侧换位最小间距 0.6px。
- [x] 鹤童准备位按当前所在侧取 280px；蓄势时保存本招玩家位置。出招后将原横移夹紧到该侧 200–340px 区间，再按舞台边界夹紧；鹿童沿用原逻辑。
- [x] 回归检查中场最大间距、靠边不穿身、进剑后仍不追踪改向。清理临时探针。

### Final verification

- [x] 修改脚本解析，`tests/c/run_act3_fight.gd` 与 `tests/a/run_puppet_motion.gd`；Windows `tests/b/run_combat_motion_graphics.gd`。
- [x] 检视实际截图及同次回放；资源导入、启动、导出与包入口验证；`git diff --check`。
- [x] 同步 PRD/TECH 与交付记录，仅交付本次范围及实际验证状态。
