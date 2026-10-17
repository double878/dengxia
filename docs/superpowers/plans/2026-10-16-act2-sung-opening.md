# 第二关第一幕连续接唱 Implementation Plan

> **Execution:** Implement authorized tasks in the current chat, respecting dependency order and the user's stage boundaries. Use subagents only when the user explicitly requests or approves them. Track steps with checkbox (`- [ ]`) syntax.

**Goal:** 修正许仙字头残留原音色，参考 BV1xX4y1Y7sJ 第一集 45:30 附近，把法海出场、开唱与许仙接唱做成连贯段落。

**Architecture:** 用户已选择直接完成全场并接入，随后补充“法海不要改太多”。法海整场原词原唱：开头采用参考视频 45:34–45:52 的“许施主不请到此地”，后六句保留第二段视频的原唱、原词与速度，不使用生成法海。许仙采用第一关实际唱声整句生成“原来金山寺老禅师”“此事容我归家思量”，不混回旧视频字头。法海出场即起 45:30 附近的同源器乐，迎接等待不断，实际就位后在器乐循环边界接唱，唯一 MusicClock 沿用。

**Tech Stack:** 既有本地 YingMusic-Singer-Plus、MelBandRoformer、FFmpeg/Python；游戏若接入沿用 Godot 4.7.2 和唯一 MusicClock。

## Global Constraints

- 不使用 character-voice-production 技能，不使用子智能体。
- 第一关和厅堂音频不修改；直接完成第二关第一幕，法海整场禁止重唱或改词。
- 使用已有 Python 3.10.22 / PyTorch 2.6.0+cpu 环境，权重离线；不新增运行时依赖。
- 不凭字幕、BPM 估计、自动转写或波形宣称人工听感通过；生成最多两轮有明确原因的修订。
- 继续 `feat-act3-mountain`，保护开工前未跟踪图片与导入信息；远端上轮连接重置，不无界重试。

### Task 1: 参考与字头根因

**Input:** 用户指定 URL、45:30 时间点、完整本地原音轨及来源散列、上一版编辑清单与混合实现。
**Output:** 参考范围、画面字幕、分离的人声/伴奏与散列；字头残留原因。
**Acceptance:** 核实第一集位置和完整音轨；明确旧版将原人声混入字头的边界与淡变策略；不把 ASR 当作准确唱词。

- [x] 核对仓库状态和当前 PRD/TECH_DESIGN，查阅现有制作入口。
- [x] 查参考网页并验证本地母参考散列，提取 45:15–46:45 与字幕画面。
- [x] 分离 45:30–45:56 参考并确定完整乐句和器乐衔接点；90 秒上下文首次分离超时，未形成结果，缩为实际所需的 26 秒后通过。

### Task 2: 保留法海原唱的完整接唱

**Input:** Task 1 连续伴奏与完整旋律，第一关实际许仙唱声。
**Output:** 正式 main.wav、entrance-loop.wav、score.json、开头试听与来源清单，独立解码和字头保护检查。
**Acceptance:** 第一句即唱，角色身份参考可追溯；许仙整句包含字头，不混回原唱；伴奏不因角色切换重启，不切断收腔；无削波和意外静音。

- [x] 按完整乐句排入许仙两句新词，法海七句原唱保留。
- [x] 使用现有离线模型生成许仙完整句，保留原始 FLOAT 输出。
- [x] 制作连续伴奏混音与接唱预览，检查来源、完整帧数、峰值和边界。微信源视频已失效，法海后段 PCM 比对先前独立解码审计散列，不声称本轮重新解码原视频。

### Task 3: 交付与接入范围

**Input:** 已验证音轨与用户“直接改完整第一幕并接入”及“法海不要改太多”的选择。
**Output:** 完整第一幕、法海出场同节奏前奏、字幕、暂停/回放及 Windows 门禁证据。
**Acceptance:** 资源导入、无头启动、Windows 导出、完整实播及实际回放声音通过；交付准确区分技术验证与人耳听感。

- [x] 完整第一幕接入，更新字幕、出场器乐、暂停及录放；Windows 完整实播 27 项、回放探针 82 项零失败，导出及导出 EXE 图形启动退出 0。交付记录明确人耳听感未验、微信源视频失效及既有无头退出释放告警。
