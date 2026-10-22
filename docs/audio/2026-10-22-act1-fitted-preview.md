# 第一关跟腔伴奏试听小样

用户要求“先试做”，范围为约 20 秒原唱加新配伴奏小样。选当前第一关唱段前 1,082,400 帧，即 22.55 秒，完整包含许仙“湖边风急雨丝长，娘子莫教湿衣裳”及白素贞“君子相怜情意厚，怎教你独受风凉”两组。此为独立试听文件，正式游戏资源保持本轮之前的状态。

## 制作

输入是 `assets/audio/act1-natural/main.wav` 的 `[1201213,2283613)` 帧；主轨 SHA256 为 `200fac72215776b476dc65e24a1adccbbb305788866463d9dff284c59ed948a1`。原唱 PCM 摘要为 `c3c068cf9ca1c6321b5bfe4d34b059f512d08965c65139bd16bf8d9538eb9d9f`。

`tools/make_act1_fitted_preview.py` 使用现有 librosa pYIN 分析干声，以约 35ms 的跟腔延迟新合成弓弦音色，许仙段高一个八度、白素贞段同度；拨弦落在可靠的唱句起音，少量木质打击声强调句头，不使用独立固定拍速。跟腔保留原唱音高起伏，气口处收声。乐器是合成近似，不是真实京胡、月琴录音或传统板式复刻；未读取或混入旧央视伴奏。

原唱不变速、变调或调增益。伴奏在响亮唱字处轻让位，约低于原唱 11.93dB RMS；这是能量比较，不是主观响度或听感验收。最终先量化伴奏，再与原唱 PCM 整数相加，保留混音减伴奏精确等于原唱的关系。

## 输出与验证

目录 `builds/act1-fitted-preview-20261022/`：

- `act1-with-accompaniment.wav`：原唱加伴奏，22.55 秒，48kHz 双声道 PCM16。
- `act1-accompaniment.wav`：单独伴奏。
- `act1-original-vocals.wav`：对应原唱，便于比较。
- `bowed.wav`、`plucked.wav`、`percussion.wav`：制作分轨，未加最终伴奏让位与整体淡变。
- `preview-manifest.json`、`pitch-analysis.npz`：输入、合成器、脚本、音高缓存和输出哈希。
- `technical-check.json`：六条音频的格式、帧数、峰值、非静音及 FFmpeg 严格完整解码结果。
- `independent-audit.json`：另一路 YIN 音高核对、原唱及混音关系、正式资源哈希审计。

本轮实际检查：Python AST 解析通过；六条音频均严格解码通过，混音峰值 0.6853、无满幅采样；原唱 PCM 一致，混音减伴奏精确等于原唱，所有正式音频/清单哈希不变。另用 YIN 检测实际合成分轨，对 1344 个可靠帧比较原唱跟腔目标，绝对音高误差中位数 13.02 cents、90 分位 42.99 cents。

制作命令：

```powershell
& builds/act1-reference-experiment/runtime/Scripts/python.exe tools/make_act1_fitted_preview.py --batch builds/act1-fitted-preview-20261022
```

音频检查使用角色制作技能的 `check_audio.py`，对以上六条 WAV 指定本机 FFmpeg，结果保存于 `technical-check.json`。未修改游戏代码或资源，本轮不运行 Godot 导入/导出及游戏回归；没有人工听感验收，音色和音乐性待用户试听。
