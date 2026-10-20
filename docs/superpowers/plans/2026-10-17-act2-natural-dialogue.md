# 第二关第一场自然对白接入计划

> **Execution:** Implement authorized tasks in the current chat, respecting dependency order and the user's stage boundaries. Use subagents only when the user explicitly requests or approves them. Track steps with checkbox (`- [ ]`) syntax.

**Goal:** 沿用用户认可的法海低沉、慢速、明显断句小样制作完整对白，第二关进入即完整播放视频音乐，再在真实迎接后说话。

**Architecture:** 保留唯一 MusicClock 与现有实际迎接许可。开场辅轨使用显式单次播放模式，结束前禁止对白；厅堂沿用原模式。录放复用现有播放器状态快照。

**Tech Stack:** Godot 4.7.2 Standard、现有 F5-TTS/Seed-VC 离线缓存、FFmpeg、PCM48k stereo16。

## Global Constraints

- 不使用子智能体，不覆盖工作区既有图片，不修改第一关、厅堂和第三关音源。
- 不变调、不后期强制变速、不加混响；小样首句逐字节复用。
- 从实际帧数产生字幕时标；暂停冻结音频与双时钟；真实回放保留音乐起点和等待。
- 按先解析、相关回归、Windows 声音验证、导入/启动/导出的顺序验证。

### Task 1: 制作与核验音源

**Files:** 新批次 `builds/act2-natural-opening-20261017/`；正式资源 `assets/audio/act2-opening/`；装配工具 `tools/prepare_act2_natural_opening.py`。

**Interfaces:** 输入已认可小样、同一法海身份、第一关许仙身份缓存和用户音乐视频；输出主轨、单次 intro.wav、六句对白与 score.json（帧数、哈希、时标和制作参数）。

- [x] 校验缓存哈希；原样复用法海首句与文本匹配的三句许仙对白（旧 PCM 从仓库恢复并核验）。
- [x] F5 原生慢速生成法海后两句的六个短语，Seed-VC 使用同一身份与参数，每阶段只加载一次模型。
- [x] 按 650/850ms 明确停顿编排，整段固定增益，完整保留音频；运行 check_audio.py 与单句自动转写。

### Task 2: 接入和定向回归

**Files:** `scripts/act2/act2_music_cues.gd`、`act2_opening.gd`、`act2_dialogue.gd`、`tests/c/run_act2_music_cues.gd`、`run_act2_dialogue.gd`、相关录放/图形测试。

**Interfaces:** `setup(entry_path: String = ENTRY, play_once_on_start: bool = false) -> bool`；`can_start_main() -> bool` 单次模式仅在 finished 信号后返回 true；默认模式保持厅堂行为。

- [x] setup 后空台立即 entry.play()；单次模式不随人物出退场重播；finished 设置完成许可。
- [x] 对白清单要求两角色均为 speech；真实迎接加音乐结束才解除冻结。
- [x] 先 check-only，再跑音乐、对白、出场、厅堂、录放相关回归；覆盖早到、迟到、暂停和音乐完整结束。

### Task 3: 交付

**Files:** `tests/b/run_act2_voice_graphics.gd`、`PRD.md`、`TECH_DESIGN.md`、`docs/audio/2026-10-17-act2-natural-opening.md`。

- [x] Windows/WASAPI 验证空台音乐、完整对白、暂停续播、换幕与回放。37项整幕实播、104项两场回放、513项完整音乐实际录放通过。
- [x] 运行资源导入、无头启动、Windows 导出和完整回归，报告真实结果及听验边界。
- [x] 检查 diff 与临时产物，显式暂存本次相关文件。仅交付音源、编排、相关测试与记录；无临时 GDScript 留在工作区。
- 版本收尾：本切片通过后提交并推送已有 `feat-act3-mountain`；结果以本轮 Git 输出为准。
