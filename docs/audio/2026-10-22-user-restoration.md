# 第一、二关伴奏与法海还原

本轮覆盖同日的无背景音乐及 Kokoro 法海方案。用户先确认“版本 1”和全部制作约束，再试听两段完整对唱并选择“A：两段都采用”。本次安装的两段混音与认可试听逐字节一致。

## 本轮内容

- 第一关对唱：1,201,213–2,706,112 帧，共 31.3520625 秒；纯人声输入及原时轴保留。
- 第二关四组对唱：965,692–2,933,692 帧，共 41 秒；厅堂主轨总长及其他对白/保护静音区保留。
- 新伴奏由显式新编音符事件和数学乐器合成，不以央视伴奏、录音、乐谱、MIDI 或采样音源为输入。配器为模拟弓弦、拨弦、笛、鼓、梆、锣及镲；第一关清丽，厅堂后段逐渐减少喜庆节奏、加入低音和变化音。模拟音色不宣称是真实乐器录音。
- 第二关开场恢复 `builds/original-audio-20261022/before/act2-opening/intro.wav`，380,928 帧 / 7.936 秒。它是本轮明确要求恢复的历史录音，与新编的两关对唱伴奏来源不同。空台播放一次，完整结束及真实迎接后对白，不循环、不叠声。
- 法海第 1/3/5 句分别使用 `14点43分.m4a`、`14点45分.m4a`、`14点45分(2).m4a`。温和降噪、65Hz 高通、局部均衡、压缩和约 −18 LUFS 响度统一，只裁头尾空余，句内停顿保留；无变调、变速、音色转换或混响。
- 三条法海输出分别为 413,280、257,760、555,808 帧。第一、三条采用固定增益响度统一，第五句采用动态增益；帧数均等于保留的连续原录音区间，没有时间缩放。测量分别为 −18.00、−17.99、−18.16 LUFS，真峰值 −3.11、−4.86、−3.03 dBTP。
- 六句主轨 2,131,831 帧 / 44.413146 秒。许仙三条对白逐字节保留；从实际帧数推导字幕、间隔与两秒暗场。
- 法海 atlas 为 2048×2048、14 个 RGBA 分件，来源照片单独保存为 `assets/puppets/source/fahai-reference-20261022.jpg`。保留骨骼枢轴、操控和录放接口；长杖为固定持物，随原持手位置移动。

## 美术边界

按照片逐件描轮廓，保留原像素、纹样与脸谱，不做白底颜色抠除。长杖遮住的帽/手窄条用同一分件邻近像素插值；手遮住的杖段复用原图可见木杖像素。照片遮住的站立侧上腿只映射可见袍服，不补画新服饰；杖尾止于照片原边界。透明度为展示轮廓，不代表测量的皮革透射率；背面为镜像。游戏姿态检查用于核对分件连接及比例，不将源照片抠图等同实际可动影人验证。

## 复现

批次目录为 `builds/user-restoration-20261022-v1/`。`before/` 保留安装前资源及哈希；`duet-preview-manifest.json`、两份 `composition.json`、录音与美术清单分别记录输入输出和参数。新编音乐不接收参考音频；混音阶段才叠加当前无伴奏主轨中的原人声。正式来源统一记录在 `assets/audio/original-audio-sources.json` v2。

```powershell
$restorationPython = 'builds/act1-reference-experiment/runtime/Scripts/python.exe'
$restorationBatch = 'builds/user-restoration-20261022-v1'
$restorationFFmpeg = 'builds/audio-tools/Lib/site-packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe'
& $restorationPython tools/check_user_restoration.py --batch $restorationBatch --ffmpeg $restorationFFmpeg
& $restorationPython tools/check_act2_natural_opening.py --ffmpeg $restorationFFmpeg --report "$restorationBatch/opening-audit.json"
& $restorationPython tools/check_act2_audio.py --ffmpeg $restorationFFmpeg --report "$restorationBatch/hall-audit.json"
```

`build_duet_previews.py` 需要无伴奏主轨作为人声输入；正式安装后重新制作时应读取 `before/`，不能直接把已经有伴奏的主轨再次混入。已认可试听原件保留在批次顶层。旧批次的 `replace_stage_accompaniment.py`、预设 TTS 和旧法海白底脚本不用于本轮安装。

## 已执行验证

- 新增 Python 工具解析通过；改动 GDScript 先逐个执行 `--check-only`，均退出 0。
- 安装审计：38 条音频完整解码、30 条 WAV 逐字节保持；两关范围外 PCM 保持、安装混音与认可试听完全一致、混音重建误差不超过 PCM16 的一个量化单位；原开场音乐逐字节一致。三条录音、14 件 atlas、既有枢轴、其他角色以及透明水印区域核验通过。
- 自然对白审计：8 个资源、6 句完整对白、字幕/静音间隔和两秒暗场通过。厅堂审计：12 个资源、7 条历史/当前对白及 3 个动作保护静音区通过。
- 定向 Godot 回归：第一关实际音频 26/26、第二关对白 47/47、音乐许可 26/26、厅堂音频 18/18、厅堂细化 10/10。
- Windows/WASAPI：原开场实际完整录制及 1:1 回放 514/514，音乐结束记录约 8,000ms，现场/回放混音峰值均为 0.670431；完整六句实播及早到/晚到、缺场、暂停 38/38；第一关回放音频 13/13。
- 第二关完整实时回放 103/103，记录 110,884ms、实际回放 110,907ms，两个场次及全部当前台词/唱段经过，惊叫一次。最终法海比例校正后，再检查两场记录、幕前回放、声音/等待和收场，82/82。
- 最终美术在实际 Windows 图形环境检查正反面、抬手弯肘、头/腰姿态和投影视图；按新照片校正发带、手掌和腿部显示比例，枢轴保持。截图 `builds/user-restoration-20261022-v1/fahai-game-poses.png`。
- A 全套 1,285 条断言及第一幕音频/交接 22 条通过；C 全套 464 条通过，均 0 失败。
- 指定 `D:/Godot/4.7.2/godot.exe` 执行 `--headless --path . --import`、`--headless --path . --quit-after 60`、`--headless --path . --export-release "Windows Desktop" builds/dengxia.exe`，三项退出 0。加载导出 PCK 检查三份清单引用的 37 条音频帧数/可用 PCM 哈希及新版来源/法海清单，0 失败；`builds/dengxia.exe --headless --quit-after 60` 退出 0。

日志位于 `builds/stage-realism/logs/restoration-*`；音频审计、开场录放及实播报告位于本轮批次；两场实时回放报告为 `builds/act2-replay/realtime.json`。单次画面与打包检查入口在验证后移除，不纳入版本库；导出预设排除 tests/tools/docs。

部分既有无头测试退出仍报告对象/资源未释放；断言通过不表示 stderr 无警告。两段伴奏已有用户试听认可，法海后期与最终游戏画面尚无单独用户听验/看验记录。
