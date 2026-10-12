# 第二关第一幕对白接入 Implementation Plan

> **For agentic workers:** 按 executing-plans 在当前会话顺序执行；用户要求默认不用子智能体。

**Goal:** 六句已确认的自然对白配合真实上场、法海就位及许仙上前应允，末句结束后暗场清场。

**Architecture:** 复用 PuppetController、Act2Entrance 和唯一 MusicClock。新增 Act2Dialogue 管理一个完整对白主轨、动作等待、字幕与暗场进度；开场宿主提供真实位置和在场状态，不自动代演。

**Tech Stack:** Godot 4.7.2 Standard；本机 F5-TTS 与 Seed-VC；48 kHz 双声道 PCM16 WAV。

## Global Constraints

- 分支 feat-act2-dialogue 从最新 origin/main 创建，现有工作区干净，按用户仓库流程在当前 checkout 开发。
- 台词以 .firecrawl/act2-opening-dialogue-draft.md 的六句为准；许仙沿用第一关声音，法海采用独立男声参考，听感认可范围如实记录。
- 正常主轨及收尾约 30 秒；上场、到位和应允等待另计，无超时跳过。
- 不新增持续音乐；误退场冻结音频，重新上场续播；菜单暂停冻结双时钟。
- 第二幕饮酒、变蛇、整关计分与录放不在本切片；第一幕结束发出完成信号，停留在端阳暗场过渡画面。

## Task 1: 制作六句音频

**Input:** 已确认文本、现有模型与许仙参考。**Output:** assets/audio/act2-opening/main.wav、逐句 WAV、score.json 与生成记录。

- [x] 检查缓存与参考哈希，使用独立 builds/act2-dialogue 输出，不覆盖旧音源。
- [x] F5 生成自然韵律，再使用 Seed-VC 分角色转换；所有输出保留中间件与参数。
- [x] 用实际波形帧数编排；第五句之后留保护静音，agreement_gate_ms 位于该静音内，末句播放后进入 dark_start_ms。
- [x] 完整解码、帧数、有限值、峰值、哈希和逐句自动转写检查；人耳听验单独注明。

**Acceptance:** 六句文本及角色正确、输入可追溯、主轨约 30 秒、无循环与自动裁头。

## Task 2: 接入动作与对白

**Files:** scripts/act2/act2_dialogue.gd、scripts/act2/act2_opening.gd、tests/c/run_act2_dialogue.gd。

- [x] 先写行为测试：未就位不播、两人面对面开始、第五句后等待真实许仙步进、误退场续播、暂停冻结、末尾只暗场一次。缺少 Act2Dialogue 时明确失败。
- [x] 先解析新测试，再运行证明缺失功能导致失败。
- [x] 实现 Act2Dialogue.setup(clock, controller)、update(on_stage, entrance_clear)、get_line()、get_hint()、fade_amount()，唯一 MusicClock 驱动状态；setup 内加载并校验清单。
- [x] 开场绑定主播放器，在场信息与位置只读；等待提示显示目标范围，字幕按实际音源时标。暗场结束释放接手并清场。
- [x] 解析每个改动脚本，再运行相关切片；补齐重叠与边缘恢复回归。

**Acceptance:** 两人实际在场、法海走出树并面向许仙后才开始；许仙真实上前才播放应允；等待不重复台词；暂停、误退场不跳段；既有上场与入口回归通过。

## Task 3: 验证与交付

- [x] Windows 图形运行实际音频和鼠标键盘，检查字幕、等待、暂停恢复、暗场与清场；保存截图和运行报告，16 项无失败。
- [x] 运行资源导入、60 帧无头启动及 Windows 导出三项门禁；运行既有相关回归和 A/B/C 整套测试。导出主入口启动通过，第二关从 PCK 单独加载通过。
- [x] 自查 diff、来源、时长、边界和临时文件；更新 PRD/TECH_DESIGN 与音频交付记录。

交付流程：只暂存相关文件，提交并推送个人分支，创建一个功能 PR；不合并。

**Acceptance:** 实际验证有证据，未覆盖听验与第二幕范围明确，临时探针已删除。
