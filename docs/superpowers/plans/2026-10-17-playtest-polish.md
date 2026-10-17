# 三关试玩修订 Implementation Plan

> **Execution:** Implement authorized tasks in the current chat, respecting dependency order and the user's stage boundaries. Use subagents only when the user explicitly requests or approves them. Track steps with checkbox (`- [x]`) syntax.

**Goal:** 落实用户 AAA：移除第一关备用头，检查全部白素贞普通对白并纠正断句，厅堂加入 4–6 秒前奏、改善惊叫，鹿童自动动作不跨到白素贞左侧。后续追加：许仙末声按第四声“à”与突然惊恐的目标重制，单独记录听验边界。

**Architecture:** 保留控制器与旧记录格式；第一关场景移除头架绘制与换头入口。声音离线制作、按真实帧数重排清单；厅堂前奏嵌入既有主轨并仍使用唯一时钟。鹿童的出山落点和打戏目标统一取右侧可用空间，不写玩家位置。

**Tech Stack:** Godot 4.7.2.stable.official.ed1daf0bf、现有 F5/Seed 本地缓存、48k 双声道 PCM16。

## Global Constraints

- 用户确认 AAA 即授权实现，不再逐条请求批准；不用子智能体。
- 不改已认可唱段、人设音色、其他角色对白、演出记录格式或首页/视频流程。
- 尊重已有 `.workbuddy/`、`output/`、PDF 工具和根目录参考图，不混入提交。
- 每个切片先解析，再定向回归；每个问题最多两次质量修订，三轮无进展则报告。
- 人耳自然度、ASR、技术格式与实际图形混音各自记录，不互相替代。

### Task 1: 声音诊断与制作

**Input:** act1-natural/score.json、旧 F5 与 VC 中间件、厅堂主轨及纯伴奏。
**Files:** `tools/prepare_playtest_audio.py`、目标音频与清单；临时制作入口放 builds 下。
**Output:** 全部七句白素贞对白的检查记录、修正音源、前奏、惊叫及精确时标/输入哈希。

- [x] 对七句白素贞普通对白及旧惊叫的 TTS/VC 分层转写与技术检查，确认问题层。
- [x] 去掉两句省略号，按完整语义控制断句；保留角色身份与所有字头字尾。
- [x] 复用厅堂纯伴奏约五秒作为前奏，在 `hall_start_ms` 开始，完整对唱稍后进入；前奏阶段不显示未唱出的字幕。
- [x] 使用自然惊叫源与许仙身份制作新惊叫，按真实长度等待再倒地；记录听感未人工验收边界。
- [x] 校验精确帧数、哈希、完整解码、对唱保留与暂停/录放。

### Task 2: 移除头架

**Input:** 第一关场景；保持 PuppetController 和旧回放数据兼容。
**Files:** `scripts/a_test/level1_a_scene.gd`；定向图形回归。
**Output:** 第一关头架与编号消失，1/2/3 和旧热区点击不换头，其余操演保留。

- [x] 删除头架绘制、常量、点击与按键入口和第一关换头提示。
- [x] `--check-only` 解析；真实输入确认头部不变并保存无头架截图。

### Task 3: 鹿童右侧动作

**Input:** `guard_entrance.gd`、`fight_choreography.gd`、实际舞台范围与玩家位置。
**Output:** 出山和打戏的自动跳跃/进剑不越到玩家左侧；靠近右边缩短距离，玩家姿态位置不被改写。

- [x] 出山落点取 `max(山缘外落点, 白素贞右侧安全距离)`，舞台内缩短跳距。
- [x] 鹿童准备位固定右侧，招式位移下界取蓄势时右侧安全距离；玩家动作中逼近时只缩短鹿童位移。
- [x] 定向回归覆盖不同起点、靠山/台边、跳跃中玩家右移、暂停、真实录放，保留鹤童原规则。

### Task 4: 集成与交付

**Files:** PRD.md、TECH_DESIGN.md、`docs/playtest-polish-delivery.md`、相关正式回归。

- [x] 三个切片的解析与定向回归通过后提交功能切片并 push。
- [x] 实际 Windows/WASAPI 验证前奏→对唱、暂停、惊叫→倒地、头架消失及鹿童同侧画面。
- [x] 执行导入、无头启动60帧、Windows export、实际 PCK 复验与 exe 启动。
- [x] 检查任务范围与临时产物，更新文档，提交并 push 后交付可运行程序。
