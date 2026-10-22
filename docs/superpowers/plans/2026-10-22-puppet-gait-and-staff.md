# 影人步态、袖口与锡杖修订 Implementation Plan

> **Execution:** Implement authorized tasks in the current chat, respecting dependency order and the user's stage boundaries. Use subagents only when the user explicitly requests or approves them. Track steps with checkbox (`- [x]`) syntax.

**Goal:** 白素贞、许仙行走时交替迈步，袖口更窄；法海前送脚、落地蹬步，改持用户新图的长环首锡杖。

**Architecture:** 仅消费现有 `walk_phase/walk_amount`。整袍使用腰部固定、下摆双侧反相的纹理网格，起停保持同一张袍摆；分腿骨链使用同一前送/蹬地曲线。离线制作工具重建袖口比例及竖直锡杖，不增加运行时依赖。

**Tech Stack:** Godot `4.7.2.stable.official.ed1daf0bf`、Pillow/NumPy/OpenCV。

## Global Constraints

- 最新要求取消杖尾必须插地；够长、环首清楚、固定右腕且保持竖直。
- 保留两关纯人声、颈根连接、坐姿/跳跃、伞/杯/剑接口及录放状态。
- 不使用子智能体，不处理已有无关未跟踪文件。
- 先解析检查，再 Windows 图形定向回归，最后 import/startup/Windows export。

### Task 1: 可复现步态回归与显示修复

**Files:** `tests/b/run_puppet_gait.gd`、`scripts/a_test/placeholder_puppet.gd`

**Interfaces:** 输入现有 `PuppetState`；输出 GPU 像素、四相截图/动态帧及 `walk_step_offset(side, height)` 的局部位移。不得写入状态或增加时钟。

- [x] 固定位置、相同躯干起伏，对比两相下半身像素；旧版白/许应失败。
- [x] 整袍网格腰部不动，左右下摆与鞋按步态交替；停止时恢复原形。分腿前送和落地错开四分之一周期，按素材原朝向计算。
- [x] 检查左右面向、实体/投影、停止、坐姿/跳跃以及接伞递杯/剑动作。

### Task 2: 袖口与新图锡杖

**Files:** `tools/prepare_couple_references.py`、`tools/check_reference_revision.py`、`assets/puppets/`、`tests/b/run_reference_puppets.gd`

**Interfaces:** 从不可变 `builds/reference-revision-20261022/before/puppets` 基线重建；新杖源图纳入 `assets/puppets/source`。输出同一 atlas/pivot/腕点接口及可审计 hash。

- [x] 前臂袖片宽度缩至原 0.72，手腕和骨长不变；上臂保留关节覆盖。
- [x] 按新图轮廓及镂空制作竖直环首锡杖，去掉旧穿地延伸片，以整杖长 1.35 倍身高适配实际腕点。
- [x] 更新审计与实际像素测试，允许杖尾离地，要求杖长、环首、轴线和腕点正确。

### Task 3: 验证、记录与交付

**Files:** `PRD.md`、`TECH_DESIGN.md`、`docs/art/2026-10-22-reference-revision.md`

- [x] 解析、GPU 步态/颈/杖、上身与战斗定向回归及来源审计通过，人工查看动态帧。
- [x] 导入、启动、Windows 导出通过，更新文档为本轮实际证据，清理临时入口。
- [x] 审查 diff，显式暂存提交并 push 已有分支，更新 PR #23，不合并。

实际验证及打包证据见 `docs/art/2026-10-22-reference-revision.md` 最新验证节。额外修复上轮缩肩后接伞中心的 19 px 偏差；当前核心、定向与打包回归通过。
