# 第三关出山、结尾站位和仙翁原声修正 Implementation Plan

> **Execution:** Implement authorized tasks in the current chat, respecting dependency order and the user's stage boundaries. Use subagents only when the user explicitly requests or approves them. Track steps with checkbox (`- [ ]`) syntax.

**Goal:** 鹿童跳出山外；鹤童完整说完再由仙翁登场讲话；结尾白素贞由玩家移到左侧，其余三人固定在山脚前景，取消灵芝，仙翁只留原声人声。

**Architecture:** 复用 GuardEntrance、FinaleChoreography、FinaleView 和同一 MusicClock。人声离线分离并记录来源/边界，现场和回放播放同一主轨；不写玩家位置，不改已认可的打戏与离场操作。

**Tech Stack:** Godot 4.7.2 Standard / GDScript；Python；本机缓存 MelBandRoformer。

## Global Constraints

- 用户已确认 Q1/Q2/Q3 均为 A，直接实施，不使用子智能体。
- 保留 27.560 秒出山重音、自由操演、W 跳劈、S 后撤、唱腔持续及 W/右键片尾离场。
- 原始视频与解码 PCM 保持原样；仅仙翁讲话段去伴奏，不合成声音、不变速。
- 尊重已有未提交工作；不进行清理、暂存或提交。

### Task 1: 出山与山脚站位

**Files:** `scripts/act3/guard_entrance.gd`、`scripts/act3/finale_choreography.gd`、`scripts/act3/finale_view.gd`、`scripts/act3/act3_opening.gd`，及现有对应回归。

**Interfaces:** 沿用 `update(delta, controller, on_stage, song_ms, cue_ms)` 与 `recorded_view() -> Dictionary`；草归属保留兼容字段但新记录始终为 -1/0。

- [x] 给现有出山测试加入落点离山体的距离断言；结尾测试改为固定仙翁→鹤童→鹿童顺序、不写白素贞、无草归属。
- [x] 修改 `_land_x`：用山左缘限制角色身体余量，保持出山跳跃原时间。
- [x] 固定三人山脚前景站位，解除出山后的山后遮罩；删除新演出的递草/持草动作与显示。
- [x] 先解析修改脚本，再运行出山、结尾相关切片。

### Task 2: 原声接话与去伴奏

**Files:** `tools/prepare_act3_finale.py`、`tools/check_act3_finale_audio.py`、必要的离线分离工具及 `assets/audio/act3-mountain/` 清单与主轨。

**Interfaces:** 输出 48kHz 双声道 PCM16 主轨，时长/对白边界/动作点从同一采样表派生；记录原始与处理后哈希和精确选区。

- [x] 检查原片对白边界；完整保留鹤童句尾，仙翁声音和出现均置于其后。
- [x] 使用缓存模型提取仙翁人声；不把整条主轨音量调低来冒充去伴奏。
- [x] 重建主轨和清单，更新逐样本检查：非仙翁段仍等于原采样，仙翁段等于已记录的人声文件。
- [x] 检查帧数、格式、有限值、衔接；完整保留旧片句尾和后段采样。混合戏曲 ASR 失真，不能认证逐字完整性，听感仍需人工试听。

### Task 3: 实际舞台与导出

**Files:** `tests/b/run_act3_entrance_graphics.gd`、`tests/b/run_act3_finale_graphics.gd`、`PRD.md`、`TECH_DESIGN.md`、`docs/act3-finale-delivery.md`。

- [x] Windows 图形/真实混音中查看鹿童落点、结尾三人间距、无灵芝及同次幕前回放。
- [x] 运行相关故事/打戏回归，导入、启动和 Windows 导出；不擅自关闭用户的游戏。启动退出时第一关音频释放提示已记录。
- [x] 更新交付说明，记录真实结果；移除单次排查脚本。导出包第三关入口启动退出 0，stderr 为空。
