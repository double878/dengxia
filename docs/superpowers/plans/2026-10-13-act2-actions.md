# 第二关第二幕动作 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. 本任务用户明确要求不用子智能体，直接执行。 Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 正式厅堂完成三人对坐、递杯饮酒、两次离场、分节蛇替身、取药返回惊死的可操演流程。

**Architecture:** 正式宿主复用现有控制、时钟和舞台；一个动作调度器控制剧情门槛和单杯归属。蛇的有限分节状态与视图独立，实体/投影共享。人形只增加默认关闭的坐姿和倒地显示。

**Tech Stack:** Godot 4.7.2 Standard、GDScript；Pillow/NumPy 仅开发期整理用户参考素材。

## Global Constraints

- Godot 4.7.2 Standard（4.7.2.stable.official.ed1daf0bf），同版本模板，无第三方运行依赖。
- 单独工作区 `builds/worktrees/feat-act2-actions`，基于 origin/main 合入厅堂与已完成上半身分支。
- 保留原工程既有改动；不改 project.godot 或导入缓存。只交付第二幕动作。
- 仅唯一 MusicClock；暂停冻结所有动作和字幕。依赖剧情等待实际输入，无超时替演。
- 每次脚本修改先 `--headless --path . --check-only --script res://<文件>`，调试只跑定向测试；最多三轮无进展即报告。
- 全过程直接执行。切片验证后分别提交、推送，完成后再建一个功能 PR。

## Task 1：正式人物、坐姿与控制

**Files:** `scripts/act2/act2_hall.gd`, `scripts/a_test/placeholder_puppet.gd`, `tests/c/run_act2_hall.gd`, `tests/c/run_act2_actions.gd`。

**Input:** 厅堂 22 号现有凳子坐标，现有 PuppetController/InputReader。
**Output:** 正式三人可操演；坐姿实体/投影一致、拖离凳子起身、误退场保留状态。
**Acceptance:** 拖手/头不移动坐姿；拖胸签离凳后站起；空格/R/暂停/失焦正确，第一场换景仍进入同一厅堂。

- [ ] 编写正式宿主回归，以 `get_node_or_null("Xuxian") != null`、对坐和上身拖动为首个失败行为；观察当前空厅堂失败。
- [ ] 视图增加 `seated`、`seated_offset` 和 `fall_angle`，默认全零；坐姿腿和姿态变换共用实体/投影，腕/头查询同一变换。
- [ ] 宿主建立三个影人及输入、灯、操作手、字幕/暂停；地面/座位复用布景常量。
- [ ] 解析修改脚本，定向执行 `tests/c/run_act2_actions.gd` 与 `tests/c/run_act2_hall.gd`，通过后提交。

## Task 2：实际递杯、饮酒和离返调度

**Files:** 新增 `scripts/act2/act2_hall_actions.gd`, `scripts/act2/wine_cup_view.gd`；修改宿主、`scripts/c/c_scenery_view.gd`，扩展动作回归。

**Input:** 唯一时钟、在场名单、实际双腕/嘴点、地面位置、显露度。
**Output:** `phase`、当前字幕/提示、`cup_owner`、持杯手、正式离场标记和换身许可。
**Acceptance:** 杯不复制；递到接收手才转移、送嘴并保持才饮酒；小青及取药必须走台边，误退场不替代正常剧情。

- [ ] 用真实宿主状态编写小青未离场/杯未交接/杯未到嘴不推进及误退场恢复测试，先观察失败。
- [ ] 实现 `update(on_stage, hands, mouths, positions, exposure, snake_position)` 和 `leave(id, at_edge)`；字幕以歌曲时间推进，保持动作以真实时间判断。
- [ ] 动态杯消费 `cup_owner` 与真实腕点；布景隐藏同一静态杯。显示隐藏列表默认空，不影响原布景。
- [ ] 完成普通对白、两次正常离场、对白缺演员时冻结、压灯与人蛇互斥门槛。
- [ ] 解析并定向回归，检查错误侧/当前位置退场不能正常推进、暂停保持和等待无超时；提交。

## Task 3：分节白蛇、惊倒及交付

**Files:** 新增 `tools/build_snake_assets.py`, `assets/puppets/snake/`, `scripts/act2/snake_pose.gd`, `scripts/act2/snake_view.gd`, `tests/b/run_act2_actions_graphics.gd`；修改宿主及动作回归。

**Input:** 用户 JPEG 参考；动作调度换身许可与真实控制输入；StageSurface 透射画布。
**Output:** 透明白蛇分件、固定长度分节姿态、同源双视图、返回后惊退仰倒定格、验证记录。
**Acceptance:** 头部拖动改变相邻节，整体拖动保持节姿态，松手不跳变；无 NaN/断节，暗场换身互斥；许仙离场或远处不会惊倒，返回走近才倒地。

- [ ] 编写固定长度/有限值/拖头与整移、未饮酒不得上蛇、未返回不得惊倒、倒地不复活回归，观察失败。
- [ ] 保留参考原稿，按轮廓去背景；重整遮挡、关节重叠和尾部，输出分件与几何清单，原稿 SHA256 写清单。
- [ ] 白蛇分节求解使用固定长度与有限角度，拖头改变可达目标，拖躯干平移根；视图仅读状态，透射复用幕面/灯距。
- [ ] 实现许仙回场位置与走近条件、一次惊退仰倒；终止旧输入，保留惊死画面。暂停停止整个过程。
- [ ] Windows 图形探针通过正式 `_input` 走递杯、饮酒、离场、换蛇、拖头与返回，截图并目视检查。定向测试通过后运行相关回归及三项门禁。
- [ ] 更新 PRD/TECH_DESIGN/README 和交付记录，审查最终差异、清理临时产物，提交推送并接回原工程。
