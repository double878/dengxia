# 第二关第一场许仙音色与连续原声 Implementation Plan

> **Execution:** Implement authorized tasks in the current chat, respecting dependency order and the user's stage boundaries. Use subagents only when the user explicitly requests or approves them. Track steps with checkbox (`- [x]`) syntax.

**Goal:** 使用本轮两段视频组成第二关第一场，只将许仙人声转换为第一关现有音色，取消法海独立出场配乐，并验证连续主轨、字幕、暂停与回放。

**Architecture:** 离线分离第一段视频人声，选取许仙两次完整回应；Seed-VC 直接转换原有发声，身份参考由正式第一关 return-02/06/08 拼成。保留法海原声和视频伴奏；通过声明的局部替换与短接头混合生成唯一主轨，所有字幕、暗场时标由实际帧数派生。运行时沿用 MusicClock、既有迎接、两场切换和真实录放；只取消第一场的独立出场配乐。

**Tech Stack:** Godot 4.7.2 Standard、既有本地 Python/FFmpeg、MelBandRoformer、Seed-VC；不新增游戏运行依赖。

## Global Constraints

- 固定 `D:\Godot\4.7.2\godot.exe`，精确版本 `4.7.2.stable.official.ed1daf0bf`；模板 `4.7.2.stable`。
- 不使用子智能体，不使用 character-voice-production 技能。保持第一关及第二关厅堂音频逐文件哈希不变。
- 保留开工前未跟踪的视频和图片；继续现有开发分支，未丢弃第三关进度。远程 fetch 长时间无进展，已停止本次 fetch；本地 origin/main 合并结果另记验证记录。
- 交付 48 kHz / 双声道 / PCM16，关闭导入裁头、归一化、循环和有损压缩。
- 不把数值边界、转写或 WASAPI 混音检查冒称人工听感验收；最多两次有原因的音频修订。

### Task 1: 两句许仙换声与完整主轨

**Files:** `tools/prepare_act2_opening.py`、`tools/check_act2_opening_audio.py`、`assets/audio/act2-opening/main.wav`、`assets/audio/act2-opening/score.json`；中间件位于 `builds/act2-xuxian-voice-20261016/`。

**Interfaces:** 输入本轮 `a544…mp4`、`5b0f…mp4`、正式第一关三条参考、局部替换清单；输出包含来源散列、编辑范围、接头帧、字幕、实际时长及转换元数据的 score.json。约束：许仙范围外仅接头允许修改，法海不得换声；不用新文字重新合成对白。验收：完整解码、范围外 PCM 比对、无削波、边界阶跃、转写对比与第一关/厅堂哈希一致。

- [x] 核对原声与字幕，分离人声并确认两句许仙范围。
- [x] 转换两句，保留原始浮点输出；把所有局部处理写入清单。
- [x] 为制作器增加显式编辑清单；审计器独立重建局部混合与接头，核查角色和原声保护。
- [x] `python -m py_compile tools/prepare_act2_opening.py tools/check_act2_opening_audio.py`，执行制作和独立审计，保留报告与接头试听。

### Task 2: 场景接入与必要回归

**Files:** `scripts/act2/act2_opening.gd`、`scripts/act2/act2_dialogue.gd`、`tests/c/run_act2_dialogue.gd`、`tests/c/run_act2_music_cues.gd`、`tests/c/run_act2_replay.gd`、相关 Windows 声音回归入口。

**Interfaces:** 消费 Task 1 主轨和清单；输出同一 MusicClock 驱动的新第一场，出场与迎接等待静音，真实录放的 entry 状态不播放。约束：不新建时钟，不删除厅堂落地重音。验收：法海首句合法、两句许仙和后续法海字幕全部可达；实际迎接前主轨不漏播，暂停冻结双时钟，尾声后正常进入厅堂，回放入口静音。

- [x] 将第一场 music_cues 出场更新移除，保持录放兼容；清单校验允许法海首句及换声标记。
- [x] 修改原声、音乐和回放回归的旧首句/旧出场音乐断言。
- [x] 逐文件执行 `godot.exe --headless --path . --check-only --script res://<修改脚本>`。
- [x] 执行 `res://tests/c/run_act2_dialogue.gd`、`res://tests/c/run_act2_music_cues.gd`、`res://tests/c/run_act2_replay.gd` 及 `res://tests/c/run_act2_opening.gd` 相关回归。

### Task 3: Windows 实播与交付

**Files:** `PRD.md`、`TECH_DESIGN.md`、`docs/audio/2026-10-16-act2-xuxian-matched-voice.md`；验证日志与导出保留 builds。

**Interfaces:** 消费前两项验证结果；输出当前要求、实际命令/结果、来源与听验边界，及可运行的 Windows 导出。验收：资源导入、无头启动、Windows 导出成功；Windows/WASAPI 完整播放原声、换声、接头、暂停、暗场与换景；回放实际音频探针通过。

- [x] 同步两份根文档的当前要求，保留历史说明。
- [x] 运行 `godot.exe --headless --path . --import`。
- [x] 运行 `godot.exe --path . --script res://tests/b/run_act2_original_graphics.gd` 及 Windows 回放音频探针。
- [x] 运行 `godot.exe --headless --path . --quit-after 60` 和 `godot.exe --headless --path . --export-release "Windows Desktop" builds/dengxia.exe`，随后导出包图形启动冒烟。
- [x] 检查 diff 和音频散列，确认一次性测试入口已清理，记录未覆盖听感；用户原有未跟踪媒体不纳入本轮编辑或提交。

**版本交付：** 已按项目约定提交本轮切片；有界推送返回 128（连接重置），远端未更新。实际提交号以 Git 历史和最终交付说明为准。未成功刷新远端，不将本地 `origin/main` 视为最新远端证据。
