# 第三关《盗仙草》结尾与山脚构图

2026-10-16 按用户确认的 Q1/Q2/Q3=A 修订。第三关保持一场连续演出，主轨现为 175.288479 秒。

## 本次行为

- 鹿童依旧在 27.560 秒重音跃出，落点位于山左缘外 110px。白素贞贴近落点时，越过她落到另一侧空地，避免身体重叠；落地面向白素贞。
- 结尾顺序固定为白素贞→仙翁→鹤童→鹿童。白素贞由玩家自行移到最左边，其余三人位于 x=.53/.63/.73 的山脚前景，间隔约 192px；鹿童仅脚部叠住山脚，不再整身压山纹，也不随玩家位置换侧。
- 仙翁实际可见身高继续与双童接近。全程取消灵芝道具、递交与持草手，只保留原声对白、拄杖和说话/指路手势。
- 完整保留前一个打戏视频里的鹤童最后一句及句尾，再停顿 300ms 接仙翁原声；仙翁不在鹤童说完之前出场。
- 仙翁讲话段播放离线分离的原始人声，不混入分离的伴奏。没有合成新台词、变声或变速。
- W 短跳/出鞘后跳劈、S 压身后撤、自由走位和身段、重音出山与双童打戏沿用。谢别后玩家 W 跳起、右键退场；原声未完继续播完，已完就直接收场。原声先完时保持操控，等待玩家离场。

## 原声选区

原始解码文件保持不变：`finale-arrival-original.wav`、`finale-blessing-original.wav`。微信临时目录中的原 MP4 本轮已不可访问，因此使用项目内已保存且与上一版 PCM 哈希完全相符的解码原声；本轮没有重新验证原视频文件哈希，清单标记 `source_video_verified_now=false`。

| 区间 | 采样处理 |
| --- | --- |
| 前 6,726,551 帧 / 140136.479ms | 与此前完整上山/打戏录音逐样本相同，完整保留鹤童末句 |
| 随后 14,400 帧 | 300ms 停顿 |
| 第一段新视频 | 从原片 1.000s 的安静区间接入分离人声，保留仙翁约 1.3s 起的发声与全部后续人声；删除此前重复的鹤童尾音 |
| 第二段新视频 | 仅去掉原有 448 帧全零开头；前 21.8s 使用分离人声，随后白素贞收尾使用原始混音采样 |
| 整轨 | 8,413,847 帧，48kHz 双声道 PCM16，175.288479s |

`tools/separate_act3_finale.py` 使用本机缓存 MelBandRoformer。模型、配置、输入和浮点人声/伴奏哈希保存在 `finale-source.json.voice_extraction`，开发中间件位于 `builds/act3-revision/voice-v1/`。`tools/prepare_act3_finale.py --voice-dir ... --ffmpeg ... <arrival.mp4> <blessing.mp4>` 重建主轨；源视频不在时，仅允许使用已有清单和分离指纹共同核验的缓存 PCM。

`tools/check_act3_finale_audio.py` 逐样本检查完整旧轨、停顿、两个人声选区和原始尾段；人声资源与主轨均关闭压缩、裁剪、归一化和循环。背景分离可能残留录音混响或少量伴奏痕迹；自动检查不能保证主观听感绝对纯净。混合戏曲 ASR 出现明显错词，未据此裁切字头字尾；对白时标仍以波形和视频观察为依据，没有宣称人工听验或逐字对齐已通过。

| 歌曲时间 | 动作 |
| --- | --- |
| 140136ms | 鹤童完整末句结束 |
| 140436ms | 接仙翁人声段并开始出场 |
| 140736ms | 喝止停战、停止交锋、白素贞开始收剑 |
| 142536ms | 鹿童回场 |
| 147991ms | 后段仙翁对白与手势，不递草 |
| 160491ms | 指路手势 |
| 169791ms | 谢别字幕和离场许可 |
| 175288ms | 原声结束，已离场则收场，否则保留操控 |

## 记录与回放

沿用三个控制槽和独立 `PuppetState(3)` 仙翁。现场、幕影和幕前回放共用 `finale_view.gd`，均不显示灵芝。`performance.finale` 保留旧兼容字段，但新记录中的 `herb_owner` 始终为 -1、`gift_progress` 始终为 0。固定站位、出场/遮罩、仙翁姿态和玩家最后跳起、退场、片尾等待均进入同次记录；回放只读，不重新编排。

## 本轮验证

统一引擎：`D:\Godot\4.7.2\godot.exe`，版本 `4.7.2.stable.official.ed1daf0bf`。实际命令由 `tools/run_godot.ps1` 等待并返回退出码，日志位于 `builds/stage-realism/logs/staging-*`。

| 检查 | 结果 |
| --- | --- |
| 修改脚本 `--headless --check-only --script ...` | 通过 |
| `tests/c/run_act3_staging.gd` | 46 项，0 失败；修复前复现 27 项不符合新要求 |
| `tests/c/run_act3_entrance.gd` | 31 项，0 失败 |
| `tests/c/run_act3_finale.gd` | 61 项，0 失败 |
| `tests/c/run_act3_fight.gd` | 75 项，0 失败 |
| `tests/c/run_act3_story.gd` | 41 项，0 失败 |
| `python tools/check_act3_finale_audio.py` | 通过；完整鹤童录音与处理后选区逐样本匹配 |
| `python tools/check_act3_fight_audio.py` | 通过；上山及打戏原声采样保持一致 |
| `tests/b/run_act3_entrance_graphics.gd` | Windows OpenGL/WASAPI，27 项，0 失败；实际起跳 27563ms，目标 27560ms；落点、暂停和回放检查通过 |
| `tests/b/run_act3_finale_graphics.gd` | Windows OpenGL/WASAPI，58 项，0 失败；固定站位、无道具、无音乐停顿、实际对白、W/右键离场及同次幕前回放 |
| `tests/c/run_tests_c.gd` | 464 项，0 失败；非法输入负向用例主动输出预期错误 |
| 资源导入 `--headless --path . --import` | 退出 0 |
| 启动 `--headless --path . --quit-after 60` | 退出 0；退出时有第一关 `act1-natural/main.wav` 音频实例释放提示，详见 verbose 日志；本次未修改第一关音频模块 |
| Windows 导出 `--export-release "Windows Desktop" builds/dengxia.exe` | 退出 0，已更新 EXE 和 PCK |
| 导出包 `builds/dengxia.exe --headless --quit-after 8 -- --act3-rehearsal` | 退出 0，stderr 为空，第三关入口可启动 |

结尾图形检查首次发现三个旧测试假设失效：去伴奏后开口前接近静音，而旧测试要求全窗口持续有声。根据已分离音源的波形核实停顿后，测试区分无音乐停顿与有声对白，并在实际有声采样位置验证回放，未通过调音量规避检查。

截图包括 `builds/act3-entrance/landed.png`、`builds/act3-finale/05-foreground-lineup.png`、`06-return-to-zhenjiang.png` 和同次幕前回放截图。当前验收不替代玩家对接话、音质的实际试听。

## 试演

执行 `tools/play_act3.ps1`。开演后上白素贞，走近山脚。仙翁到场后自行把白素贞移到左边，其他三人自动就位；谢别后 W 跳起、右键点白素贞退场。未提交或推送工作区既有改动。
