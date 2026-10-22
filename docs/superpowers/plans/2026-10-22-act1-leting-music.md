# 第一关乐亭器乐试听接入 Implementation Plan

> **Execution:** Implement authorized tasks in the current chat, respecting dependency order and the user's stage boundaries. Use subagents only when the user explicitly requests or approves them. Track steps with checkbox (`- [ ]`) syntax.

**Goal:** 把用户授权的 BV1xX4y1Y7sJ 第一集器乐接入第一关对白后与实际接伞后，交付可运行试听包。

**Architecture:** 离线裁取/分离来源器乐，按现有主轨精确帧区间替换两处静音；保留主轨长度和唱说 PCM。沿用唯一 MusicClock 和真实回放音频快照，等待音乐按阶段选择，不在接伞前误放游湖音乐。

**Tech Stack:** Godot 4.7.2 Standard、现有 FFmpeg、MelBandRoformer、Python / NumPy / SoundFile。

## Global Constraints

- 用户已确认视频原声授权；本轮直接接入供试听，听感尚待用户确认。
- 第一、二关对唱保留纯人声；第二关、美术、输入及道具许可不改。
- 保持实际接伞许可、8 秒等待、菜单暂停及真实幕前回放契约。
- 固定使用 `D:/Godot/4.7.2/godot.exe`；执行导入、无头启动及 Windows 导出。

### Task 1: 音乐资源、阶段等待及试听交付

**Files:**
- Create: `tools/prepare_act1_leting_music.py`，保存来源、备份、选区、处理参数及输出哈希，安装两处主轨音乐及等待循环。
- Modify: `assets/audio/act1-natural/main.wav`、`wait_loop.wav`、`score.json`，及 `assets/audio/original-audio-sources.json`。
- Modify: `scripts/b/act1_opera_audio.gd`，仅在配置允许的等待阶段播放器乐。
- Test: `tests/b/run_replay_audio.gd`、`tests/b/run_act1_game_audio.gd`，验证音乐输出和阶段、暂停、回放。
- Document: `docs/audio/2026-10-22-act1-leting-music.md`、PRD/TECH 顶部当前约定。

**Interfaces:** 输入已核验完整源 SHA256、原主轨精确帧范围；输出同长度 48k 双声道 PCM16、来源清单、可运行 Windows 包和两个短音频预览。

- [x] 从原声截取候选器乐，记录精确来源区间和分离方式。
- [x] 备份原第一关资源；用固定选区制作两段与等待循环；核对所有非目标 PCM 完全一致。
- [x] 加入 `waiting_music_phases` 配置，只覆盖到位等待、还伞等待；接伞等待保持静音。
- [x] 先做 GDScript 解析，再跑相关正式入口/剧情/回放音频测试；Windows 混音采样证明两段均有输出，暂停位置冻结。
- [x] 完成导入、启动、导出；核验来源及最终 diff，准备试听包。用户听感反馈尚待本轮交付后确认。
