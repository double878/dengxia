# 第一、二关新伴奏与法海合成音色

本次按用户选择保留唱腔人声，重制伴奏，法海使用无演员录音参考的合成预设。第一、二关旧伴奏的录音采样已从本次交付的目标段落替换；保留唱腔的旋律、唱法、身份参考和其他对白仍可能需要权利人授权，不能凭本次替换认定竞赛或整部作品已合规。第三关、片头片尾、图片不属于本次范围。

## 正式资源

| 位置 | 变化 |
| --- | --- |
| `assets/audio/act1-natural` | 主轨内五个音乐区间重新编排；等待过门、接伞锣替换。13 条普通对白、范围外主轨 PCM、时标和原合成补救鼓保留。 |
| `assets/audio/act2-opening` | 开场音乐与已停用但仍会打包的器乐循环替换；三条法海对白重新合成；三条许仙对白逐采样保留。 |
| `assets/audio/act2-hall` | 纯人声加新伴奏重建饮酒对唱；两条旧视频器乐音效也替换，保持现有惊叫和取消落地重音的流程。 |
| `assets/audio/retained-vocals` | 保留的两条原制作人声分轨，供音源审计复现。 |
| `assets/audio/original-audio-sources.json` | 12 个新编排音乐段的音符事件、无外部采样声明、输入/输出/工具 SHA-256、TTS 请求与未核实授权范围；随发布包保存。 |

新伴奏由 `tools/compose_original_accompaniment.py` 编排并合成，使用拨弦、笛、鼓、木梆、锣的数学模型，不读旧伴奏、MIDI、SoundFont 或他人乐谱。保留人声未重新分离、改调、变速、裁切或加入混响。厅堂沿用原人声固定增益及重采样；清单中旧混音的响度测量已明确标为历史数据。新伴奏按段落使用固定增益，唱段器乐约 −31dBFS RMS，独立器乐约 −23dBFS RMS，保护人声且避免开场过轻；这些数值不是 LUFS 测量或听感验收。原有音符或演唱旋律未声称完成权利清理。

第一关主轨保持 111.111 秒，厅堂保持 69.517 秒；第二关开场六句主轨按新法海自然输出重排为 2,020,535 帧 / 42.094479 秒。开场音乐仍为 380,928 帧 / 7.936 秒，只播放一次。对白间停顿为 850ms，最后一条后停 500ms 再进入两秒暗场。游戏读取同一清单，不添加第二套时间轴。

## 法海来源与许可

- 模型：[hexgrad/Kokoro-82M-v1.1-zh](https://huggingface.co/hexgrad/Kokoro-82M-v1.1-zh)，固定 revision `01e7505bd6a7a2ac4975463114c3a7650a9f7218`，官方模型卡标注 Apache-2.0。作者 hexgrad；原模型参数和音色权重未修改。
- ONNX 发布：[thewh1teagle/kokoro-onnx model-files-v1.1](https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.1)，使用官方 FP32 `kokoro-v1.1-zh.onnx`。模型 SHA-256：`859f9ded9f53be16c24857cdab3254a45da53c3afd5ba6ef134c7de3f822e326`；音色库 SHA-256：`14cb6186c99e4f6016871405f62046c5df863ae27465cbdc4ee08be7dd703acd`。其余输入哈希见正式清单。
- 推理库 kokoro-onnx 0.6.1（MIT，Copyright (c) 2025 github.com/thewh1teagle）、Misaki 0.9.4，CPU 推理。模型及依赖只在本地 builds，不随游戏打包。[Apache-2.0 许可全文](https://www.apache.org/licenses/LICENSE-2.0)；模型许可描述的是上游权重，不等同对任何人物声音或其他素材作权利保证。
- 预设 `zm_010`、模型原生速度 `0.86`；不读旧法海身份、影视原句、自然男声韵律样本或其他录音，`recording_references=[]`。短语之间加入 550ms 静音，输出整句固定增益。没有后期变调、时间拉伸、混响或字头字尾裁切。
- 法海三条完整台词保持不变，帧数分别为 403,136、262,688、449,728（48kHz）。自动转写中“许施主/许师主”“将至/将指”“雄黄/熊黄”等差异仅作读音复核提示，不据此裁剪，也不视为人耳验收。

## 复现与独立审计

在本项目根目录，以 `builds/act1-reference-experiment/runtime/Scripts/python.exe` 运行。TTS 还使用本批 `deps/` 内的依赖和 `models/` 权重。批次目录为 `builds/original-audio-20261022`，`before/inputs.json` 固定旧资源哈希；安装器发现资源在快照后被其他人修改会拒绝覆盖。

```powershell
$audioPython = 'builds/act1-reference-experiment/runtime/Scripts/python.exe'
$audioBatch = 'builds/original-audio-20261022'
$audioFFmpeg = 'builds/audio-tools/Lib/site-packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe'
& $audioPython tools/prepare_fahai_synthetic.py --batch $audioBatch
& $audioPython tools/replace_stage_accompaniment.py --batch $audioBatch
& $audioPython tools/check_original_audio.py --batch $audioBatch --audio-root "$audioBatch/delivery" --ffmpeg $audioFFmpeg --report "$audioBatch/staged-audit.json"
& $audioPython tools/replace_stage_accompaniment.py --batch $audioBatch --install
& $audioPython tools/check_original_audio.py --batch $audioBatch --ffmpeg $audioFFmpeg --report "$audioBatch/installed-audit.json"
& $audioPython tools/check_act2_natural_opening.py --ffmpeg $audioFFmpeg --report "$audioBatch/installed-opening-audit.json"
& $audioPython tools/check_act2_audio.py --ffmpeg $audioFFmpeg --report "$audioBatch/installed-hall-audit.json"
```

审计从基线和保留分轨检查 23 条普通对白逐采样不变、两个唱腔分轨 SHA-256 不变、新混音逐样本重建、音乐区间外 PCM 不变、无旧器乐文件残留、TTS 请求无录音参考、完整解码/有限值/峰值。开场检查另外覆盖六句完整 PCM、静音停顿、字幕帧数、两秒暗场及既有导入保护。它们验证来源记录与制作完整性，不能证明音色自然、音乐与唱腔悦耳或最终法律合规。

## 本轮验证

本批全部实际验证使用 `D:/Godot/4.7.2/godot.exe`，版本 `4.7.2.stable.official.ed1daf0bf`，对应 Windows release 模板存在。日志在 `builds/stage-realism/logs/original-*.out.log/.err.log`；本轮最终音频审计和 Windows 报告在 `builds/original-audio-20261022/`。

- Python 新增/修改工具经解析检查。音频审计：40 个文件完整解码、23 条普通对白保持、两个唱腔人声分轨保持、12 条新编排器乐可复现，新混音与分轨逐采样重建一致，全部峰值小于 0.98。自然对白审计为 8 个资源、6 句完整台词；厅堂审计为 12 个资源、7 条完整对白及 3 个静音动作保护区，均通过。
- `tests/a/run_tests.gd`：1,285 条通用断言及 22 条第一幕自然对白断言通过；`tests/c/run_tests_c.gd`：464 条断言通过，0 失败。
- 相关无头回归：`run_act1_game_audio.gd` 26/26、`run_act2_dialogue.gd` 47/47、`run_act2_music_cues.gd` 26/26、`run_act2_hall_audio.gd` 18/18、`run_act2_hall_refinement.gd` 10/10；两场录放另在 Windows 验证。
- 最终 Windows/WASAPI：第一关 `tests/b/run_replay_audio.gd` 12/12；第二关六句完整实播 `tests/b/run_act2_original_graphics.gd` 37/37，覆盖新音乐、六句对白、暂停静音与双时钟冻结、缺场续播、晚出场及不重播音乐。
- 完整开场音乐实际录放 `tests/b/run_act2_intro_replay.gd` 513/513，7.936 秒音乐实际记录到 8.017 秒，记录长 8.367 秒；现场与回放混音峰值均为 0.413892。没有注入音乐完成事件。
- 两场完整实时回放 `tests/c/run_act2_replay.gd -- realtime` 103/103，记录 108,568ms，实际播放 108,591ms；两场均经过，当前全部台词和四组对唱有声，惊叫一次，已删除的厅堂前置五句未出现。首轮仅这五句的过期“应有声”断言失败，依当前剧情契约修正后定向复验通过，未改游戏流程或音源来适配测试。
- 三项门禁 `--headless --path . --import`、`--headless --path . --quit-after 60`、`--headless --path . --export-release "Windows Desktop" builds/dengxia.exe` 退出 0。额外加载导出的 PCK 逐采样检查三份清单内全部音源与源工程 PCM 哈希一致，且来源清单已打包，0 失败；最终 `builds/dengxia.exe --headless --quit-after 60` 退出 0。
- 为避免 Git 的 LF 行尾规则破坏来源哈希，生成器固定以 LF 写 JSON；暂存区内 46 个制作工具/音源/清单/分轨的实际内容哈希与来源记录一致。此后刷新仅改变清单与工具哈希，38 条游戏 WAV 均与最终 Windows 检查版本逐字节一致。

通用负向测试有意输出非法输入诊断，部分无头测试仍出现退出时对象/资源未释放诊断；断言通过不表示 stderr 无警告。临时 ASR 与导出检查脚本在使用后删除，正式审计工具保留。

整关实时回放须显式传递 Godot 用户参数分隔符，命令如下；以输出 `ACT2_REPLAY_WALL` 证明执行了实际时长分支。厅堂历史前五句仍保存在音源中，但从 2026-10-17 起不播放；实时回放断言已按该契约检查它们不出现，同时检查当前全部对白、四组对唱有实际声音。

```powershell
& tools/run_godot.ps1 -LogName original-final-windows-realtime -GodotArgs @('--path', '.', '--script', 'tests/c/run_act2_replay.gd', '--', 'realtime')
```

本批人耳听验尚未完成；所有资源的 `human_listening_verified` 保持 false。Windows 混音、字节一致性和转写只证明各自检查范围，不替代听感认可或授权文件。
