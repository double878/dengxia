# 第一关跟腔伴奏小样 Implementation Plan

> **Execution:** Implement authorized tasks in the current chat, respecting dependency order and the user's stage boundaries. Use subagents only when the user explicitly requests or approves them. Track steps with checkbox (`- [ ]`) syntax.

**Goal:** 交付约 22 秒第一关原唱加新配伴奏试听，覆盖许仙、白素贞各一组完整唱句。

**Architecture:** 从当前正式主轨只读提取已保留的干声，以 pYIN 分析音高、气口及句间交接。新合成跟腔弓弦、拨弦及少量打击乐；保留原唱 PCM，单独输出混音和伴奏供试听。

**Tech Stack:** 现有 Python 3.10 / librosa / NumPy / SciPy / SoundFile / FFmpeg。

## Global Constraints

- 仅试做，不安装游戏资源，不改第一关过门、第二关或美术。
- 不读取、裁取或混入央视伴奏；唱声仍使用当前已认可版本。
- 乐器为合成音色，不宣称真实京胡、月琴演奏或传统板式复刻。
- 不硬套固定 BPM，不对人声变速、变调、裁尾或归一化。
- 保存输入、脚本、音高分析、音符与输出哈希；听感待用户确认。

### Task 1: 跟腔分析、编配与小样交付

**Files:** Create `tools/make_act1_fitted_preview.py`；产物写入新的 `builds/act1-fitted-preview-20261022/`，不覆盖历史试听。

**Interfaces:** 输入当前主轨、来源清单及精确唱段帧；输出混音、原唱、伴奏、分轨和制作/验收 JSON。

**Acceptance:** 两组唱句完整；原唱 PCM 一致；混音逐采样等于原唱加新伴奏；48k 双声道 PCM16 可完整解码、无削波；跟腔轨与原唱有足够音高对应；正式音频文件哈希一致。

- [x] 分析当前唱段的音高、起音和停顿，可靠音高覆盖 64.54%，39 个候选起音。
- [x] 生成跟腔弓弦、稀疏拨弦和轻打击乐，混音并保存制作清单。
- [x] Python 解析通过；六条 WAV 严格解码与峰值检查通过；独立 YIN 检查 1344 帧，音高误差中位数 13.02 cents、P90 42.99 cents。原唱逐采样不变，混音减伴奏精确等于原唱，正式音频哈希不变。交付供用户试听，听感待确认。
