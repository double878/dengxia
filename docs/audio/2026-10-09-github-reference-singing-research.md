# GitHub 真实参考唱段模仿与换词资源核查

日期：2026-10-09。目标：找到使用真实唱段、替换台词后仍尽量保留旋律和演唱特点的路线，优先服务第一关的短句唱腔。已读取官方仓库 README、文件树和关键推理代码；没有安装或运行这些模型，没有试听其演示，也没有取得本轮新音频。

## 结论与推荐顺序

优先验证 **YingMusic-Singer-Plus**：它的输入直接对应“真实唱段 + 原唱词 + 新唱词”，可以分别提供音色和旋律参考，不要求人工逐音素标注。其次是 **Vevo2**：已公开的推理代码将新文本、原音频的韵律、风格和音色同时作为条件，另有独立的演唱风格转换入口。

需要精细控制音符与时长时，考虑 **TCSinger / StyleSinger**。专门研究戏曲声学建模的 **FT-GAN** 是长期训练路线，不能当成现成的任意参考换词工具。普通音色转换可作为后处理，但它本身不制作新唱词。

这些项目提供了实际的参考音频条件机制。能接收参考音频，仍不等于已经证明能保留京剧或皮影戏的字头、拖腔、润腔和角色表达。最终判断必须使用本项目参考录音与新词进行试听。

## 项目对照

| 项目 | 已核对的输入和能力 | 与本项目的关系 | 本轮运行准备状态 |
| --- | --- | --- | --- |
| [YingMusic-Singer-Plus](https://github.com/ASLP-lab/YingMusic-Singer-Plus) | 音色参考、旋律参考、参考唱词、目标唱词；中文/英文；保留旋律的整句或局部换词；无需手工逐音素配 MIDI | 第一优先短句实验 | 推理源码在；README 提供权重地址，但本机未取得权重；部分文档命令需纠正 |
| [Vevo2 / Amphion](https://github.com/open-mmlab/Amphion/tree/main/models/svc/vevo2) | 新文本与参考音频；唱词编辑、旋律控制、风格转换；风格和音色参考可分开 | 第二优先，比较风格保留能力 | 推理源码在；README 提供预训练组件地址，本机未取得权重 |
| [TCSinger](https://github.com/AaronZ345/TCSinger) | 参考人声及其音素对齐、目标音素、音符、时长、休止/连音类型；零样本风格迁移 | 可显式指定新词如何进入旋律，准备工作较多 | README 声明中英预训练模型；需准备对齐与曲谱，未运行 |
| [StyleSinger](https://github.com/AaronZ345/StyleSinger) | 参考人声、目标音素、音符、时长与连音类型；跨域歌声风格迁移 | 可作为需要曲谱控制的备选 | README 声明中文预训练模型；源代码有直接 CUDA 调用，未运行 |
| [FT-GAN / Gezi-Opera-Synthesis](https://github.com/zhengmidon/Gezi-Opera-Synthesis) | 戏曲数据、文本和音高/时长建模；官方流程包含数据处理和声学模型训练 | 有明确中国戏曲研究证据；适合长期适配目标剧种 | 未找到可直接使用的主声学模型下载入口；官方流程要求先训练 |
| [DiffSinger / OpenVPI](https://github.com/openvpi/DiffSinger) | 音素、音符、时长、连续音高等；控制音高、力度、气声等参数 | 可精修旋律和润腔，需要合适歌声模型 | 框架公开；本轮未选定或取得适合戏曲的声库 |
| [Seed-VC](https://github.com/Plachtaa/seed-vc) | 已唱好的源音频、目标音色参考；SVC 支持源音高条件 | 制作好新词导唱后可做音色转换 | 不直接接收目标歌词，不能独立完成本轮换词任务 |
| [TCSinger 2](https://github.com/AaronZ345/TCSinger2) | 多语种、参考风格和曲谱条件；训练与推理代码公开 | 研究备选，暂不作为最快试听路线 | README 未给出主模型权重入口；现存 `scripts/test_sing.py` 默认读取本地训练日志中的检查点 |

## 优先项目的源码证据

### YingMusic-Singer-Plus

来源：[README](https://github.com/ASLP-lab/YingMusic-Singer-Plus/blob/baa409c2e7e5e775f09b4e92a220808f4827d2cc/README.md)、[实际单样本入口 infer_api.py](https://github.com/ASLP-lab/YingMusic-Singer-Plus/blob/baa409c2e7e5e775f09b4e92a220808f4827d2cc/infer_api.py)、[歌声模型输入处理](https://github.com/ASLP-lab/YingMusic-Singer-Plus/blob/baa409c2e7e5e775f09b4e92a220808f4827d2cc/src/YingMusicSinger/infer/YingMusicSinger.py)。

- `infer_api.py` 实际定义 `--ref_audio`、`--melody_audio`、`--ref_text`、`--target_text`。参考唱词使用 `|` 划分乐句，推理设为 `sentence_level`；“免逐音素标注”不代表无需提供参考文本或整理乐句。
- 模型处理参考人声的音频潜变量、旋律参考与新词音素，旋律参考同时提供目标长度；这与只有“京剧风格”的文本提示不同。
- 模型输入要求纯人声。入口提供可选分离及混入原伴奏的能力；分离是否伤害锣鼓、字头与长音需要另验。
- 当前 README 的 `python infer.py`、`python batch_infer.py` 对应文件均不在仓库文件树中。可以核查现存的 `infer_api.py`，不能照抄不存在的入口并称为已经跑通。
- README 使用新模型名 `ASLP-lab/YingMusic-Singer-Plus`，代码中的 `from_pretrained()` 和初始化下载仍使用旧名 `ASLP-lab/YingMusic-Singer`；实际模型重定向及文件兼容性尚未核实。
- `get_device()` 有 CPU 分支，但完整推理的可用性和耗时均未实测，不能根据这一个分支保证本机能够完成小样。

### Vevo2

来源：[README](https://github.com/open-mmlab/Amphion/blob/26f6883110181f1dbfe95c70a7c7dbaf4de5f42a/models/svc/vevo2/README.md)、[推理入口](https://github.com/open-mmlab/Amphion/blob/26f6883110181f1dbfe95c70a7c7dbaf4de5f42a/models/svc/vevo2/infer_vevo2_ar.py)。

- `vevo2_editing()` 传入目标新词，把原录音同时用于 `prosody_wav_path`、`style_ref_wav_path` 和 `timbre_ref_wav_path`，并启用 `use_prosody_code`。示例包含中文换词。
- `vevo2_singing_style_conversion()` 使用独立风格参考，同时保留源人声作为音色参考；可用来比较演唱风格迁移与只换音色的区别。
- `vevo2_melody_control()` 可同时传入新文本、旋律音频、风格参考和音色参考。
- README 将旋律表示说明为粗粒度韵律码。保留具体戏曲滑音、长拖腔和咬字的程度没有本项目实测证据。

### TCSinger 与 StyleSinger

来源：[TCSinger 的参考迁移代码](https://github.com/AaronZ345/TCSinger/blob/aa49e529bc2c0bd4f40d9a1093817aec0a0df332/inference/style_transfer.py)、[TCSinger README](https://github.com/AaronZ345/TCSinger/blob/aa49e529bc2c0bd4f40d9a1093817aec0a0df332/README.md)、[StyleSinger 推理代码](https://github.com/AaronZ345/StyleSinger/blob/5a977c426b16bf683baa2686c2327c3fd09b88dc/inference/StyleSinger.py)。

TCSinger 源码读取 `ref_audio`、参考音素时长 `ph_durs`，并组合参考/目标的音素、音符、时长和类型。StyleSinger 对参考人声提取音色、情绪与声学特征，同时输入目标音素、音符和时长。两者需要把新词在旋律中的安排具体写出来；自动估计音高不能代替完整的歌词对齐和润腔安排。

## 专门的中国戏曲资源

[FT-GAN 官方论文](https://ojs.aaai.org/index.php/AAAI/article/view/29943/31649)研究歌仔戏的细粒度音调建模，并报告京剧扩展实验。其[官方仓库](https://github.com/zhengmidon/Gezi-Opera-Synthesis)给出数据处理、训练和推理流程，不能将歌仔戏模型或实验直接叫作《白蛇传》皮影戏模型。

仓库 README 提供通用声码器与音高提取器下载，随后要求训练声学模型。本轮文件树中的 `checkpoints/spec_cls_conv2d/model_ckpt_steps_3000.ckpt` 不能当作已经取得完整戏曲歌声合成模型。该项目为“戏曲需要专门建模”提供技术依据，不能保证拿一段参考就完成零样本换词。

## 实际下载与本机条件

- 八个 GitHub 仓库的元数据、README 和文件树读取成功，关键候选的推理源码已读取。代码快照保存在忽略目录 `.firecrawl/github-opera-resources/`。
- 对 YingMusic-Singer-Plus、TCSinger、StyleSinger、Vevo2 的官方模型元数据接口，本机 HTTP 请求均返回 502；对应公共镜像请求均超时。已停止网络重试，没有要求用户再次登录。
- 因此，报告里的“预训练模型”指 README 提供的作者下载声明；本轮没有验证完整权重文件可下载、模型可加载或推理成功。
- 本机图形适配器查询得到 `Intel(R) Arc(TM) Graphics`，未找到 `nvidia-smi`。TCSinger / StyleSinger 文档以 NVIDIA + CUDA 为运行路径；YingMusic 和 Vevo2 有 CPU 选择代码，但当前未验证完整 CPU 推理，不把 Intel Arc 默认当作 CUDA 设备。
- 本轮没有下载大模型、创建训练环境、购买云 GPU、上传参考录音或修改游戏运行代码。许可证和模型组件条件以各自官方文件为准，没有将代码开放等同于所有演出录音及模型组件可任意使用。

## 最小验证设计

先验证真正换词且唱腔仍相近，再扩展到已批准的《游湖》对白。

1. 从真实参考中整理一条完整短乐句，分离人声，保留原版与伴奏；准确标注原唱词。已有乐亭参考可用于能力探测，但其盗仙草情境不直接作为借伞成品。
2. 首轮采用同字数的小改词，降低配词变化，例如原句“且慢动手尊仙童”改为“且慢移步许官人”。原唱词目前来自画面字幕，具体音频范围和逐字一致性还需要听辨，不能按十秒固定窗口冒充完整乐句。
3. 使用 YingMusic 的真实参考/旋律条件制作新词人声，保留原唱和新唱两个完整乐句以供对照。权重与环境先通过加载检查，再调用生成；本轮未执行这些步骤。
4. 分别验收：新字是否真的唱出；句内旋律和长音是否保留；声音是否仍有目标唱腔；是否漏字、增字、丢字头或硬切收腔。歌词字幕与波形差异不能代替声音验收。
5. 若首轮明确失去唱腔或仍唱旧词，定位一次原因，最多进行一次有明确原因的修正；不反复换提示词碰运气。成功后再制作“君子相怜情意厚／怎教你独受风凉”，随后验证许仙与连续对唱。

## 本轮验证边界

已完成资源调研和 README/源码交叉核查，确认真实参考条件、新词输入和实际文件存在情况。未完成模型下载、推理、音频听感验收和游戏接入。Mureka 纯提示词路线已按用户明确反馈停止；其准备文件保留为历史记录。
