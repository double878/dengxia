# YingMusic 单句参考换词实验记录

日期：2026-10-09 开始，2026-10-10 完成单句验收。状态：**本机 CPU 已完成运行检查、人声分离和单句生成；用户确认新词清晰唱出、保留唱腔与拖腔，单句能力实验通过。完整借伞唱段、角色声音和游戏接入另行验收。**

依据：`docs/superpowers/specs/2026-10-09-act1-opera-flow-design.md`、`docs/audio/2026-10-09-github-reference-singing-research.md` 及用户“先做一个小实验，后面再实施计划”的要求。本轮仅验证真实参考换词路线，不进入关卡接入。

## 实验目标与输入

使用 YingMusic-Singer-Plus 的真实音色、旋律和歌词条件，把一条七字完整乐句换成另一条七字新词。验收需要同时满足：新字确实唱出、旋律和收腔相近、目标唱腔仍成立、没有漏字或混入下一句。文件、波形和音素变化均不能单独证明听感通过。

| 输入 | 本轮确定值 |
| --- | --- |
| 原句 | 且慢动手尊仙童 |
| 目标句 | 且慢移步许官人 |
| 原演出 | 乐亭皮影戏《白蛇传》第一集，`https://www.bilibili.com/video/BV1xX4y1Y7sJ/?p=1` |
| 完整乐句范围 | 源录音 350000–357000 ms，7 秒 |
| 边界确认 | 用户否定 9 秒候选，指出末尾进入下一句；随后试听并确认 7 秒候选完整、可用于实验 |
| 原唱处理 | 仅裁剪，不改变速度、音高或已有增益 |
| 用途 | 真实参考换词的能力探测；原唱为盗仙草情境，不能当作正式借伞对白 |

实验目录：`D:/Cursor_program/灯下/builds/act1-reference-experiment/`，由已有 `builds/` 忽略规则与 `.gdignore` 排除出版本控制和 Godot 资源。

参考文件为 `original-phrase-candidate-0550-0557.wav`，SHA-256：`7e8fc4520c8600fd1495185dc9ae5ca686be969631cdb455cffea710aab1be1b`。完整读取验证：48 kHz、双声道、16-bit PCM、7.000 秒，样本均有限，峰值 0.86737060546875，没有满幅饱和样本。母参考 SHA-256 与既有记录一致。

## 已取得的模型与工具

- 源码从作者仓库 `ASLP-lab/YingMusic-Singer-Plus` 克隆，实际提交为 `baa409c2e7e5e775f09b4e92a220808f4827d2cc`，未修改作者代码。
- 本轮 Hugging Face 直接模型查询仍返回 502，公开演示入口返回 503；镜像模型元数据、配置和权重范围读取成功。旧模型名返回的元数据指向 Plus，解决了调研中“旧模型名是否重定向”的疑问；完整代码兼容性仍需加载模型确认。
- 完整权重实际来自作者同名 ModelScope 仓库，文件版本固定为 `7443a818cb43c5ece9976a78ec8b625660bc522d`。Hugging Face 查询版本仅作元数据参考，不冒称它是本轮加载过的模型版本。
- 创建隔离 Python 3.10.22 环境，安装官方 PyTorch 2.6.0+cpu 及本次执行所需依赖。离线安装新增 148 个包，再按分离工具自身的依赖声明补装 `beartype==0.14.1`；实际环境清单保存在 `runtime-installed-freeze.txt`。
- 本机图形适配器为 Intel Arc，没有 NVIDIA CUDA。运行检查确认 `cuda_available: false`，人声分离和生成均在 CPU 上实际完成；生成期间一次采样的可用内存约 2.6 GB，不能据此保证长唱段的内存和耗时。

完整文件均按来源提供的字节数与 SHA-256 核验，收尾时再次逐文件计算通过：

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `model.safetensors` | 2910134776 | `b32dc225a6cfff37f2252b7d3b60cbf536f656de349eba6d5b773aa5f5b780e4` |
| `ckpts/MelBandRoformer.ckpt` | 913106900 | `87201f4d31afb5bc79993230fc49446918425574db48c01c405e44f365c7559e` |
| `ckpts/config_vocals_mel_band_roformer_kj.yaml` | 1721 | `f63f38eb1e6e40a7db0dade714a5ae257555dd8748f4e774eae8679275a81926` |
| `config.json` | 209 | `8c01e299f82d8a4a9851cfb5072f11363a1fca48fcc27443eae5fcb9211602bb` |

## 环境准备与已解决卡点

初次环境准备的主要下载卡点是 `scipy==1.15.3` 和解析出的 `llvmlite==0.50.0`：

1. 清华镜像安装遇到 Windows DNS 解析失败；其余已下载缓存保留。
2. 官方 PyPI 文件整包下载在 180 秒限制内仅取得少量数据，没有形成可安装的完整 wheel。
3. 范围请求探针返回有效的 206 和 `Content-Range`，但最终分段下载仍返回 `Final science-wheel correction exceeded 180 seconds`，未完成两个文件的大小和哈希校验。
4. 用户询问下一步后，补做一次有时限的阿里云镜像下载：60 秒内每个包均取得 20971520 字节。这是新的实质进展，因此没有换镜像重试，而是对已有文件各做一次断点续传；约 65 / 67 秒完成。两个完整 wheel 的大小与 PyPI 元数据 SHA-256 均通过，记录在 `wheels-v2/resume-result.json`。随后离线依赖安装退出码为 0，用时约 73 秒。

首次运行检查退出码为 1，原生 eSpeak 报 `phontab: Illegal byte sequence`，错误路径包含中文工程名。只将已安装的 eSpeak 数据复制到纯英文目录 `D:/Cursor_program/yingmusic-native-runtime/espeakng-loader-0.2.4/espeak-ng-data`，通过 `ESPEAK_DATA_PATH` 指向它，再运行同一检查退出码为 0，证实路径处理是本次故障原因。没有修改作者代码或替换歌词处理方式。首次分离缺少 `beartype`，按分离工具要求补装后再次运行成功。

完整权重校验通过后的临时分片清理操作曾被自动审批拒绝，理由为 `blocked by policy`；分段文件、失败下载和结构化记录仍在忽略的实验目录中，尚未清理。未绕过拒绝继续删除。

## 准备好的执行入口与验收状态

`experiment-request.json` 保存用户确认的参考哈希、原/目标歌词、源码和权重来源。实际调用使用 32 步、CFG 3.0、t_shift 0.5、尾部静音 0.5 秒、句级歌词对齐；种子 `2026100901` 已传入模型并完成生成。没有执行第二次生成来验证位级可重复性。

`run_experiment.py` 与 `bounded_phase.py` 分为检查、人声分离、生成三个独立进程，分别限定 180、300、600 秒。Windows 超时会停止本次启动的进程树；分离进程退出后再启动生成，避免同时常驻两套模型。脚本修改后先做 Python 解析检查。以下三条命令均已实际执行，最终退出码为 0：

```powershell
& 'D:/Cursor_program/灯下/builds/audio-tools/Scripts/python.exe' 'D:/Cursor_program/灯下/builds/act1-reference-experiment/bounded_phase.py' check
& 'D:/Cursor_program/灯下/builds/audio-tools/Scripts/python.exe' 'D:/Cursor_program/灯下/builds/act1-reference-experiment/bounded_phase.py' separate
& 'D:/Cursor_program/灯下/builds/audio-tools/Scripts/python.exe' 'D:/Cursor_program/灯下/builds/act1-reference-experiment/bounded_phase.py' generate
```

检查最终用时 23.454 秒，模型类导入和原/目标中文歌词编码通过，音素编码分别为 14 / 13 个且不同。分离进程最终用时 37.461 秒，其中分离计算约 23 秒；输出均为 44.1 kHz 双声道浮点 WAV。生成进程用时 71.693 秒，其中模型加载加生成为 60.313 秒（加载 13.969 秒）；实际从本地完整权重加载，生成成功退出。三个进程分别保留 `.out.log`、`.err.log` 和 `*-execution.json`。

## 可试听的生成候选

`new-lyrics-vocals-01.wav` 保留模型原始浮点输出：44.1 kHz、双声道、309248 帧、7.012426 秒，SHA-256 为 `486a2b2fa6b9ce404c5e40ec7af8e986a989fb5dd6e3a0e761ca08620cf35eac`。完整解码后样本均有限，峰值 0.589127779006958，没有满幅饱和样本。以上只能确认文件可用，不能确认新词确实可懂或目标唱腔成立。

`prepare_listening.py` 已解析检查并实际执行成功，输出两份 48 kHz、双声道、16-bit PCM WAV，均完整解码且没有满幅饱和样本：

| 文件 | 处理 | 时长 / 峰值 |
| --- | --- | --- |
| `new-lyrics-vocals-listen-01.wav` | 新词人声重采样；增益 1.0 | 7.0124375 秒 / 0.587799 |
| `new-lyrics-mix-listen-01.wav` | 与同一原唱分离伴奏按起点混合；整体固定增益 0.940007929 后重采样 | 7.0124375 秒 / 0.942383 |

混音对较短的原伴奏补零到人声尾端，不截短收腔；没有变速或改音高。浮点处理文件和模型原输出均保留。完整参数、解码结果和试听版哈希见 `listening-verification.json`。分离残余原人声、旋律与新词时序是否协调均需听辨，没有将未试听的混音登记为正式成品。

2026-10-10 用户试听结论：“清晰唱出来了，保留唱腔和拖腔”，并要求根据第一关流程设计与台词改写报告继续接入唱腔。本条单句验收通过；不把它扩大解释为六句借伞唱段、许仙男声、小青念白或连续音乐衔接均已通过。下一步按已批准台词先制作角色小样，再制作连续样段并接入第一关。

| 验收项 | 结果 |
| --- | --- |
| 原句边界与可用参考 | 用户确认 7 秒版本；完整解码和哈希检查通过 |
| 取得完整推理权重 | 四个文件大小与来源哈希均通过 |
| 本实验运行环境 / 中文音素检查 | 已完成；最终检查退出码 0 |
| 模型加载 / CPU 人声分离 / 新词生成 | 均实际完成；最终分离、生成退出码 0 |
| 候选与试听版完整解码 / 有限数值 / 削波 | 均通过；试听版为 48 kHz / 16-bit PCM |
| 本条新词可懂度、唱腔与拖腔试听 | 用户确认清晰唱出并保留唱腔、拖腔；单句通过 |
| 连续器乐与唱段样段、游戏接入、实际回放 | 均未实施 |

## 工程检查与范围

实际使用同一个 `D:/Godot/4.7.2/godot.exe`，版本为 `4.7.2.stable.official.ed1daf0bf`，对应模板目录存在。执行 `tools/run_godot.ps1` 包装下列 TECH_DESIGN 命令，均取得实际退出码 0：

```powershell
godot.exe --headless --path . --import
godot.exe --headless --path . --quit-after 60
godot.exe --headless --path . --export-release "Windows Desktop" "builds/dengxia.exe"
```

日志位于 `builds/stage-realism/logs/act1-pilot-*.out.log` / `.err.log`。无头启动出现 `2 ObjectDB instances were leaked at exit` 警告，未定位其来源；导入和导出 stderr 没有错误。以上不证明声音体验通过。未跑全套功能测试、Windows 图形环境的新唱腔播放或实际回放验收。

本次收尾重新核对原始候选、分离输出和两份试听版本存在且与解码记录中的 SHA-256 一致；实验记录本身无行尾空白。全工作区 `git diff --check` 发现既有 `PRD.md` 第 3、6、7、8 行的行尾空白，未修改用户已有内容，也不将全工作区空白检查描述为通过。

本实验新增受版本控制范围文件仅本实验记录；运行脚本、模型、工具环境、音频候选及结构化证据在忽略的实验目录，另有纯英文路径中的 eSpeak 数据副本。实验期间未修改游戏代码、场景或正式音频资产登记。用户现已确认单句并授权继续第一关接入，后续按功能切片另记验证结果。

后续路线已同步为本机 YingMusic 参考换词，Mureka 保持停止。用户曾选择乐亭方向；白素贞双句随后因独立人声和混音均有电音感、两句衔接生硬被判退。用户最新明确“算了，按照文档中的来吧”，正式制作恢复原文档京剧《白蛇传·游湖》方向。本条乐亭单句通过结论保留，双句失败记录在 `builds/act1-opera-pilot/baisuzhen-result.json`，不得作为正式音源。
