# 第二关第一幕许仙对白接入 Implementation Plan

> **Execution:** Implement authorized tasks in the current chat, respecting dependency order and the user's stage boundaries. Use subagents only when the user explicitly requests or approves them. Track steps with checkbox (`- [x]`) syntax.

**Goal:** 将用户认可的许仙小样原样接入，并用同一音色和断句方式制作本场另两句许仙对白。

**Architecture:** 复用现有 F5-TTS / Seed-VC 本机流程，只在独立 builds 批次生成新词。现有装配器增加可选许仙交付清单，按实际 PCM 帧数重排字幕与暗场；播放器、MusicClock 和录放逻辑沿用。

**Tech Stack:** Python 3.10、F5-TTS、Seed-VC、FFmpeg、Godot 4.7.2 Standard。

## Global Constraints

- 不使用子智能体；不覆盖工作区已有无关文件。
- 认可小样 SHA256 为 `122ad6246b0c039994c1a9b9d75321d56c7bf52c7c1bd5e1cc124df54e7284b1`，不得重新生成、增益或剪裁。
- 原音色；保留完整字头字尾，慢速、明确断句和自然语调；不变调、不强制变速、不加混响。
- 同一 `D:/Godot/4.7.2/godot.exe`，版本 `4.7.2.stable.official.ed1daf0bf`。
- 交付 48kHz、双声道、PCM16；保持开场音乐、法海、第一关和厅堂资源哈希。

### Task 1: 制作并核验许仙三句交付

**Files:** `builds/act2-xuxian-approved-20261017/produce.py`、`delivery.json` 和三条 WAV。

**Interfaces:** 输入已认可小样及其身份/韵律参考；输出逐句 `line_id/text/path/sha256/frames/production` 与身份记录。

- [x] 直接复制认可小样为 dialogue-02，逐字节比对。
- [x] 沿用认可身份，原生慢速生成 dialogue-04、dialogue-06，短语间加入 650/850ms 静音。
- [x] 用 `check_audio.py` 完整解码；自动转写诊断错漏字，保留人工听验范围。

### Task 2: 装配并验证正式资源

**Files:** `tools/prepare_act2_natural_opening.py`、`tools/check_act2_natural_opening.py`、`assets/audio/act2-opening/`、接入记录及 PRD/TECH_DESIGN 当前说明。

**Interfaces:** 装配器新增 `--xuxian-batch <批次目录>`，读取通过核验的 delivery.json；沿用 score.json 现有运行时接口。

- [x] 校验全部输入后写入三句音频，按实际帧数装配 main.wav 和 score.json；为新批次保留复现与听验元数据。
- [x] 运行独立音频审计，证明认可小样原样、六句逐样本完整及非本次资源未改变。
- [x] 运行 `tests/c/run_act2_dialogue.gd` 和 `tests/c/run_act2_replay.gd` 相关回归。
- [x] 运行 `tests/b/run_act2_original_graphics.gd` 实际 Windows/WASAPI 播放及真实回放检查。
- [x] 依次执行 `--headless --path . --import`、`--headless --path . --quit-after 60`、`--headless --path . --export-release "Windows Desktop" "builds/dengxia.exe"`。
- [x] 更新接入记录，检查 diff 与暂存范围；按仓库约定提交、推送当前分支，交付实际验证结果。
