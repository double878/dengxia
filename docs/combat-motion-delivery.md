# 三关短跳、躲闪与第三关打戏修订

2026-10-15，按用户六项定案制作。参考视频 `348249de5c1e484fa88cb5e2b8bab4c3.mp4` 只用于动作观察，声音继续使用已有连续视频原声。

后续修订：第三关白素贞出鞘后按 W，在原有 0.46 秒张腿短跳中先提持剑手、再自动下劈，落地恢复此前手姿；切人或取消也清理临时手姿。空手、地面位置与其他关操作沿用，唱腔持续。鹤童准备位收至约 280 px，同一招围绕蓄势时的玩家位置，在所在侧约 200–340 px 内搭戏；台边按余量缩短，取消原靠右时强制穿过白素贞换侧的逻辑。鹿童招式与剧情时标沿用。

本次实际证据：修改的 4 个脚本解析与 gdformat/gdlint 通过；打戏回归 75 项、共用短跳回归 45 项、Windows 图形/混音 61 项均为 0 失败。60Hz 两轮招式观测，中场间距由 200–464 px 收至 200–340 px；白素贞 x=0.80 时，原最小绝对间距约 0.6 px 的强制穿身消失，鹤童留在同侧，受台边限制相距约 134.4 px。左右两侧和台边均有正式回归。窗口证据含 [提剑](../builds/combat-motion/act3-jump-cut-raised.png)、[下劈](../builds/combat-motion/act3-jump-cut-down.png)、[同次下劈回放](../builds/combat-motion/replay-jump-cut-down.png)、[鹤童腾挪](../builds/combat-motion/npc-2-1.png)。

Windows 探针在正式 W/S 输入后用宿主固定步长取提剑、下劈和后撤中点，真实渲染与 WASAPI 原声持续；最初按墙钟 0.18 秒检查后撤受渲染帧影响而错过取样点，改为固定步长取中点，未修改后撤实现或时长。检查属于脚本键鼠与画面核对，不代表用户人工试玩。资源导入、默认无头启动、Windows 导出和导出包第三关启动均退出 0；默认入口沿用下表既有资源退出清理告警。试玩程序已更新，日志前缀 `builds/stage-realism/logs/jump-cut-*`，临时位移探针已删除。

同日按用户截图再次修正：白素贞的剑换到原来的另一只手（状态 `left`），自动拔剑只带动这只手；实体、幕影、交锋几何及回放共用该腕点，双童的持剑手保持各自绑定。补充验证：6 个修改脚本解析通过，打戏回归 56 项、Windows 图形与混音检查 49 项均为 0 失败，实际截图见 [换手画面](../builds/combat-motion/act3-sword-hand.png)。资源导入、无头启动、Windows 导出和导出包第三关启动均退出 0，默认第一关启动仍有下表记录的既有退出清理告警；试玩程序已更新。日志前缀 `builds/stage-realism/logs/sword-hand-*`。下表保留前一轮完整动作切片的检查记录。

## 操作与表现

- 三关所有当前接手的人形：W 按一次原地张腿短跳，合计约 0.46 秒，其中腾空约 0.32 秒；按住不连跳。动作期间锁定胸签、手签、头腰拖动、抬落手和 R，落地恢复。桥顶按幕布余量收小高度，落脚仍在原桥面。
- S 按一次压身后撤约 92 px，约 0.42 秒完成；保持面朝对手，台边收小后撤距离，结束恢复原身段。A/D 与 Shift+A/D 分别抬落手。厅堂使用短动作会离座；完整白蛇保留原分节操控。
- 白素贞面朝右时，鞘口和剑柄朝右、鞘尾斜向左下；镜像时随身翻转。按最新截图将剑换到原来的另一只手（状态 left），到原唱词自动提持剑手出鞘，550 ms 后交还玩家，剑柄始终跟随持剑手实际腕点。上半身、离地、整身倾角、实体/幕影/回放使用同一几何。
- 鹿童三套：跃身进刺、下扫接上挑、转身横扫；鹤童三套：架剑反挑、腾挪回身剑、跃起劈剑。每套有蓄势、进攻、收势，双臂、腿、身体倾角、腾空和进退共同变化。蓄势时调整接战距离，出招后锁定方向与步幅。
- 原声、27.560 秒重音出山、鹿童败退和鹤童接战时标沿用；唱腔不因玩家跳/闪/漏招停止。不加血量、动作门槛或强制跌倒。第三关仍只有一场，现有素材结束继续留台操演。

## 实现与录放

`scripts/a/puppet_motion.gd` 只处理有界的玩家单次动作，继续由 PuppetController 写状态。新增 `air_height`、`leg_spread`、`body_angle` 进入正式快照、补采样、插值、显示和独立校验，旧记录缺失为零。回放只读取同次演出的实际状态，不重跑输入和 NPC 编排。

`scripts/act3/fight_moves.gd` 保存两童各三套关键帧；打戏调度复用原歌曲时标，动作中不追着玩家改变已发动的招式。完整袍摆在张腿时使用已有大腿/小腿分件，未重做人物资产。

## 验证口径

同一 `D:\Godot\4.7.2\godot.exe`，脚本先逐文件解析，再运行定向回归和 Windows 图形探针。Windows 探针通过正式宿主发送脚本键鼠事件，使用 Intel Arc / OpenGL 与 WASAPI；不代表用户已经人工试玩或听验审美效果。

| 实际检查 | 结果 |
| --- | --- |
| 本轮 23 个 GDScript 逐文件 `--check-only --script` | 通过 |
| `tests/a/run_puppet_motion.gd` | 45 项，0 失败；锁姿、短跳、后撤、切人、挂起、桥面与录放 |
| `tests/a/run_upper_body.gd` | 100 项，0 失败 |
| `tests/c/run_act3_fight.gd` | 48 项，0 失败；含六套招式、锁定方向、剑鞘与持剑腕点 |
| `tests/c/run_act3_entrance.gd` | 31 项，0 失败 |
| `tests/c/run_act2_actions.gd` | 86 项，0 失败 |
| `tests/c/run_game_replay_success.gd` | 12 项，0 失败；第一关完整接还伞及回放，落手自动化同步改用 Shift+A/D |
| `tests/a/run_tests.gd` | 1284 + 22 项，0 失败；保留原故意非法输入诊断和退出清理告警 |
| `tests/c/run_tests_c.gd` | 464 项，0 失败；新增事件后同步总数断言为 37，原非法输入诊断属于测试覆盖 |
| `tests/c/run_act3_story.gd` | 41 项，0 失败 |
| Windows `tests/b/run_combat_motion_graphics.gd` | 48 项，0 失败，WASAPI；15 张截图，含同次跳跃真实回放 |
| `python tools/check_act3_fight_audio.py` | 通过；6,726,551 帧，140,136 ms，原采样与接续点一致 |
| gdformat / gdlint（新增及主要动作脚本） | 通过 |
| `--headless --path . --import` | 退出 0 |
| `--headless --path . --quit-after 60` | 退出 0；默认第一关仍有既有 2 个 ObjectDB / 1 个资源退出清理告警 |
| `--headless --path . --export-release "Windows Desktop" builds/dengxia.exe` | 退出 0，试玩程序已更新 |
| `builds/dengxia.exe --headless --quit-after 60 -- --act3-rehearsal` | 退出 0，无第三关入口告警 |
| `git diff --check` | 通过 |

Windows 图形探针 `tests/b/run_combat_motion_graphics.gd` 覆盖第一关桥面跳/闪、第二关门楼和厅堂离座起跳、白蛇边界、第三关真实原声下出鞘/跳/闪/暂停、同次跳跃回放及六招截图。逐时墙钟取样曾错过短跳顶点（观察到动作已到 316.7 ms），改为观察实际腾空状态后截图；没有修改动作时长或放宽功能验收以凑结果。

窗口证据保存在 [verification.json](../builds/combat-motion/verification.json)、[六招对照图](../builds/combat-motion/moves-contact.jpg)、[张腿短跳](../builds/combat-motion/act3-player-jump.png)、[后撤](../builds/combat-motion/act3-player-dodge.png) 和 [同次回放](../builds/combat-motion/replay-player-jump.png)。完整日志前缀为 `builds/stage-realism/logs/combat-*`。测试过程中临时诊断输出已移除，保留的两份新回归入口覆盖稳定动作/录放契约；没有遗留临时脚本。源码工作区包含本轮前已有的第二关、角色资产和第三关改动，保持原状，未混合暂存、提交或推送。

## 运行

项目根目录运行 `& .\tools\play_act3.ps1`，或打开 `scenes/act3/rehearsal.tscn` 按 F6。开演按 1 上白素贞，向右侧山脚走近，鹿童随原声重音跳出。到唱词自动拔剑后，拖持剑手摆剑，W 短跳、S 后撤。
