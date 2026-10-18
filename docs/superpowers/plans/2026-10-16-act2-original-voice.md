# 第二幕法海劝酒原声衔接 Implementation Plan

> **Execution:** Implement authorized tasks in the current chat, respecting dependency order and the user's stage boundaries. Use subagents only when the user explicitly requests or approves them. Track steps with checkbox (`- [x]`) syntax.

**Goal:** 按用户提供的两段视频顺序衔接原声，替换第二幕第一场对白，字幕、入场等待、暂停与真实回放同步。

**Architecture:** 48 kHz 双声道 PCM16 离线解码，按精确帧数顺序连接，保存来源哈希和选区。复用原 MusicClock、主轨、字幕和录放；法海走出柳树、许仙实际迎接后才播放从许仙开口的原声，完整结束后暗场换景。

**Tech Stack:** Godot 4.7.2 Standard、Python、已有 FFmpeg。

## Global Constraints

- 不使用子智能体；当前工作区已有改动以开工快照保留，不切分支、不覆盖他人工作。
- 固定 `D:\Godot\4.7.2\godot.exe`，版本 `4.7.2.stable.official.ed1daf0bf`。
- 仅第一场改声音；第二场厅堂及第三关不改。
- 不生成新声音、不强制变速或变调；来源视频仅作为内容资料。
- 先解析，再相关回归；收尾执行导入、无头启动和 Windows 导出，并做实际 Windows 音频/暂停检查。

### Task 1: 原声与时表

**Files:** `tools/prepare_act2_opening.py`、`assets/audio/act2-opening/main.wav`、`assets/audio/act2-opening/score.json`。

**Interfaces:** 消费两段用户视频；输出顺序主轨、逐段来源帧/哈希和双角色字幕时表。

- [x] 解码两段并核对原画字幕、接头与尾音；保留制作前的相关文件快照。
- [x] 生成主轨和实际波形时间表，独立检查完整解码、PCM 一致性与来源顺序。

### Task 2: 第一场原声调度

**Files:** `scripts/act2/act2_dialogue.gd`、第一场相关回归。

**Interfaces:** 消费清单中的动态字幕行、迎接冻结点和暗场时标；沿用 `get_line()`、`phase`、唯一 MusicClock 和现有回放。

- [x] 允许原片真实台词顺序，取消旧六句与固定角色交替约束。
- [x] 走出柳树后等待许仙迎接，整段原声只播放一次；完整结束再暗场。
- [x] 解析改动脚本，再验证入场、缺场、暂停、接头、尾段和换景及真实回放。

### Task 3: 验证与交付

**Files:** `docs/audio/2026-10-16-act2-original-voice.md`、根文档的最新变更说明。

- [x] 运行音频审计及相关第一场、第二关录放回归。
- [x] 实际 Windows 图形/音频运行，检查有声、暂停静音、接头和末尾换景。
- [x] 执行资源导入、无头启动、Windows 导出；检查任务差异和临时产物，记录实际通过范围及剩余限制。
