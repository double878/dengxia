# 第一、二关原创伴奏与法海合成音色 Implementation Plan

> **Execution:** Implement authorized tasks in the current chat, respecting dependency order and the user's stage boundaries. Use subagents only when the user explicitly requests or approves them. Track steps with checkbox (`- [ ]`) syntax.

**Goal:** 保留现有唱腔人声，移除第一、二关伴奏中的外部录音采样，法海三句对白改用不参考现有演员录音的预设合成男声。

**Architecture:** 离线使用现有纯人声分轨、新编音符和程序合成乐器制作 PCM 音源，复用现有资源路径、播放器和唯一 MusicClock。法海使用 Kokoro v1.1-zh 的预设中文男声，按完整输出帧数重建六句对白时间轴。素材先在 builds 内准备、校验，再写入正式目录。

**Tech Stack:** Python 3.10、NumPy/SciPy/soundfile、Kokoro ONNX/Misaki、Godot 4.7.2 Standard。

## Global Constraints

- 不使用子智能体；保留本次开始时已有的未跟踪文件。
- Godot 固定为 `D:\Godot\4.7.2\godot.exe`，版本 `4.7.2.stable.official.ed1daf0bf`。
- 交付音频为 48 kHz、双声道、16-bit PCM；禁用裁头尾、归一化及主轨循环。
- 唱腔纯人声及许仙已有对白保持；伴奏不读取央视/B站/用户视频的音频波形，不做原曲改调或变速。
- 法海不读取旧人物身份、旧韵律参考或第三方影视台词。预设模型和音色的来源、版本、许可和哈希须记录。
- 本轮只处理第一、二关伴奏与法海音色，不能将保留的唱腔、其他对白或全作品登记为全部版权清理完成。
- 开工时 main 与 origin/main 同步，个人分支 `fix-original-accompaniment-fahai`。

---

### Task 1: 离线制作可追溯替代素材

**Task / Input:** 当前三份音源清单、原制作目录的纯人声分轨、预设 TTS 模型；逐项校验哈希。

**Output:** `builds/original-audio-20261022/` 内备份、原创伴奏事件、纯人声与新混音、法海完整对白、输入输出哈希。

**Constraints:** 保留既有时长的伴奏段；不把旧混音用作新伴奏输入；TTS 依赖和权重仅放 builds 内。

**Acceptance:** 新混音由保留的人声加原创伴奏重建；新法海请求不包含录音参考；完整解码、有限值、无削波，保存可试听的音频。

- [x] 增加离线伴奏合成工具及确定性的音符/节奏编排，包含移步、唱段、等待、游湖、收束和第二关开场。
- [x] 核验 Kokoro 模型许可及下载文件哈希，以固定中文男声生成三句法海完整台词。
- [x] 保存基线文件与每条替代素材的制作清单；逐样本验证保留的纯人声。

### Task 2: 接入当前游戏音源与正式审计

**Task / Input:** Task 1 的替代素材、原有帧数与音源清单。

**Output:** `assets/audio/act1-natural`、`act2-opening`、`act2-hall` 中必要 WAV/清单；正式制作来源记录及工具。

**Constraints:** 第一关和厅堂使用原有时标；法海按自然输出帧数更新字幕、间隔和暗场；不强制变速凑时长。

**Acceptance:** 第一关对白 PCM 不变；保留人声逐样本保留（仅原既有统一增益）；许仙三句对白不变；开场六句的完整 PCM 与主轨对应；新音源版本进入真实回放。

- [x] 按原始精确帧边界替换所有目标伴奏，更新音源哈希、来源、局部授权状态和音源版本。
- [x] 更新第二关自然对白检查工具，使其检查新法海制作来源和原创音乐，而非旧演员小样/原视频一致性。
- [x] 记录新规则覆盖 PRD/TECH_DESIGN 中旧素材选择，说明保留素材的权利边界。

### Task 3: 验证、交付与版本保存

**Task / Input:** Task 2 的最终工程。

**Output:** 音频审计、相关 Godot 回归和 Windows 音频输出证据、导出包及提交。

**Constraints:** 改 GDScript 时先解析；调试只跑相关切片；单一问题最多两次修订，三轮无进展就报告。

**Acceptance:** 原创音源和保留内容的独立审计通过；第一关音频、第二关对白/厅堂/回放回归通过；Godot 导入、启动、Windows 导出通过；不把自动输出检查等同人耳认可。

- [x] 执行音频哈希、完整解码、原声残留输入检查及保留人声/对白对比。
- [x] 执行相关切片回归及 Windows/WASAPI 播放、暂停和真实回放检查。
- [x] 执行三项 Godot 门禁，审查差异、清除临时测试入口，确认暂存仅包含本轮文件，供个人分支提交和推送。

实际验证记录见 `docs/audio/2026-10-22-original-accompaniment-fahai.md`。版本保存按工程规则在验证后提交并推送，以 Git 历史和远端分支为准。
