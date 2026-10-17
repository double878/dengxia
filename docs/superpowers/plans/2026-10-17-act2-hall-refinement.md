# 第二场厅堂剧情与操演修订 Implementation Plan

> **Execution:** Implement authorized tasks in the current chat, respecting dependency order and the user's stage boundaries. Use subagents only when the user explicitly requests or approves them. Track steps with checkbox (`- [ ]`) syntax.

**Goal:** 法海场保留，厅堂直接对唱；唱白完整播放，取杯和头旁饮酒更宽容，许仙喊叫后惊倒。

**Architecture:** 复用厅堂宿主、Actions、MusicClock 和整关录放。保留已制作唱白的完整 PCM，仅修正实际播放游标；旧前五句留作制作来源但不进入演出。惊叫使用独立一次性播放器，与真实阶段一起记录回放。

**Tech Stack:** Godot 4.7.2 Standard、GDScript；既有离线 F5-TTS / Seed-VC；48 kHz 双声道 PCM16。

## Global Constraints

- 用户确认 AAAA：保留法海场、拖手靠近取杯、头旁停留约半秒、许仙“啊——！”后倒地。
- 不使用子智能体；不触碰已有无关未跟踪文件。
- 固定 `D:\Godot\4.7.2\godot.exe`，每个修改脚本先解析再运行相关回归。
- 真实 Windows 图形和声音检查，最终执行资源导入、无头启动、Windows 导出。

### Task 1: 定位与修正唱白跳段

**Files:** `scripts/a/music_clock.gd`；`tests/b/run_music_clock_seek.gd`。

**Interfaces:** 消费唯一时钟的暂停和前向跳段；输出歌曲时间与 WAV 实际播放游标一致、真实时间不重置。

- [ ] 添加真实 WAV 冻结跳段回归，比较 `player.get_playback_position()` 与 `clock.get_song_time_ms()`，容差 80 ms。
- [ ] 先运行复现，记录失败读数；修正已证实的播放游标问题。
- [ ] 保留冻结状态，用实际播放入口定位：

```gdscript
player.play(_free_s)
player.stream_paused = _paused or _song_frozen
_position_s = _free_s
```

- [ ] 执行 `tools/run_godot.ps1 -LogName hall-seek --path . --script res://tests/b/run_music_clock_seek.gd`，验证冻结/菜单暂停跳段与续播。

### Task 2: 厅堂动作和惊叫

**Files:** `scripts/act2/act2_hall_actions.gd`、`act2_hall.gd`、`act2_music_cues.gd`；`scripts/c/c_act2_capture.gd`、`scripts/b/act2_replay_audio.gd`；`assets/audio/act2-hall/score.json`、新惊叫 WAV 与导入设置。

**Interfaces:** 保持既有主轨与音源时标；新增 `fright` 阶段和惊叫记录，饮酒几何读取实际头部中心。

- [ ] `on_stage = [0, 1]`，Actions 初始化直接进入 `duet`，禁止小青上场。
- [ ] 取杯半径扩大到 52 px；饮酒采用头中心附近 64 px，保持 550 ms。提示和补救目标同步。
- [ ] 独立制作 `xu-fright`，仅一句“啊！”，采用现有许仙音色，保留原始输出和参数哈希。技术检查有限值、完整采样、峰值、格式。
- [ ] 见蛇进入 `fright`，播放一次惊叫；按该音源实际长度结束后进入现有 `startled` 动作，取消旧落地重音触发。
- [ ] 更新对应 Actions、音频、补救及录放回归，执行解析与定向检查。

### Task 3: 真实演出与交付

**Files:** `tests/b/run_act2_voice_graphics.gd`、相关厅堂图形回归；`PRD.md`、`TECH_DESIGN.md`、`docs/act2-hall-refinement-delivery.md`。

**Interfaces:** 消费新厅堂阶段与录放音频；输出检查计数、截图、实际 WAV 游标与清单尾点对照。

- [ ] 更新 Windows 实时回归：完整四组对唱、尾音结束后的游标、头旁饮酒、取药句完整游标、惊叫/暂停和真实回放。
- [ ] 单独运行相关动作、补救、音频及录放回归；共享 MusicClock 运行既有相关回归。
- [ ] 运行三项门禁及导出包启动；目视检查厅堂截图，记录听感未由用户确认的范围。
- [ ] `git diff --check`、范围审查，清理临时探针；只提交本任务文件，推送个人分支。
