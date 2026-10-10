# 第一关京剧新词素材目录

更新日期：2026-10-10。正式声音方向为京剧《白蛇传·游湖》角色表达，台词为已批准的游戏改写。当前为本地制作候选目录；完整音频配置尚未冻结、游戏尚未接入。

来源均为[央视《CCTV空中剧院》京剧《白蛇传·游湖》，郭霄、郝仕鹏](https://tv.cctv.com/2020/07/02/VIDEGhi9Sw6SpdWEg573OBfO200702.shtml)，媒体 ID `df814b60471b440cbf09fdb801630527`。公开可访问不代表已核实再发行许可，候选的 `rights_status` 为本地原型参考。不能将原词演出登记为新词成品。

## 已通过的白素贞角色小样

| 字段 | 值 |
| --- | --- |
| `asset_id` | `baisuzhen_borrow_continuous_01` |
| `role_ids` | `baisuzhen` |
| `source_part` | 官方《游湖》片段；本地媒体区间 |
| `source_start_ms` / `source_end_ms` | `1000000` / `1009000` |
| `reference_text` | 我家就在红楼上／还望君子早降光；已核对实际画面字幕 |
| `text` | 君子相怜情意厚／怎教你独受风凉 |
| `path` | `builds/act1-jingju-pilot/baisuzhen-continuous-vocals-01.wav` |
| `sha256` | `1f1b08f70311e8e8da3a14f61317499ea23f0d8aa7b3ab7f755d521c87d16276` |
| `sample_rate_hz` / `channels` | `48000` / `2` |
| `duration_ms` | `9009.354166666666` |
| `decode_verified` | `true`；独立完整解码、哈希及削波检查通过 |
| `listening_result` | 用户确认“新词清楚，连唱自然，没有明显电音感” |
| `rights_status` | `local_prototype_only; redistribution_permission_unverified` |
| `game_integration_ready` | `false`；完整编排、念白和玩法接入未完成 |

对应伴奏混音为 `builds/act1-jingju-pilot/baisuzhen-continuous-mix-01.wav`，SHA-256 `26f23562042179dbb040d1c5299100131fcce5f385d37196c48246dea0509a42`；同样是 48 kHz 双声道 16-bit PCM、9009.354166666666 ms。原始浮点生成、参考人声与分离伴奏均保留。完整模型参数、处理方法和验收证据见 `2026-10-10-jingju-baisuzhen-pilot.md`。

## 已通过的许仙小生答句

同场小生参考为本地媒体 14:29–14:39，即 869000–879000 ms，原词“些小之事何足介意／怎敢劳玉趾访寒微”。用户确认“完整，可以作为许仙参考”；参考工作副本为 `builds/act1-jingju-xuxian-pilot/original-xuxian-1429-1439.wav`，SHA-256 `93c110038575a6b25c2cf589792ad74e76860b952da81590bf509c8ff78771c4`，完整解码通过。

目标答句“些小风雨何须讲／请接此伞莫彷徨”已一次生成，独立人声与混音的完整解码和哈希检查通过，用户确认“清楚自然，适合许仙”。文件为 `builds/act1-jingju-xuxian-pilot/xuxian-answer-continuous-vocals-01.wav`（SHA-256 `9da04aff1dc51e688edf6360e92b12fed27fa04f4207b5ba93622d3b925d36f6`，9984.583333333334 ms）与 `xuxian-answer-continuous-mix-01.wav`（SHA-256 `aa9afac6670e6d049677ffb5b20f53396ef35564746ef503f2c3885a1685f73c`，10000 ms），均为 48 kHz 双声道 16-bit PCM；详情见 `2026-10-10-jingju-xuxian-pilot.md`。

## 六句连续修正版 01：技术核验与整体试听通过

首版六句 `six-lines-mix-01.wav` 被用户判退：两处伴奏与角色衔接均生硬、语调太单一。其拒绝结论保留；用户已批准同场连续生旦对答参考“适合，按这段连续对答改词”。修正版使用三组对应旋律和一条不在角色边界剪接的连续分离伴奏，角色音色参考仍为上述已通过的小样参考。

| 字段 | 值 |
| --- | --- |
| `asset_id` | `borrow_six_lines_continuous_revision_01` |
| `role_ids` | `xuxian`, `baisuzhen`；许仙—白素贞—许仙 |
| `source_part` | 同场官方《游湖》连续对答；本地媒体区间 |
| `source_start_ms` / `source_end_ms` | `838000` / `869000`；原参考副本为 `837000`–`869000`，输出从副本第 1 秒起 |
| `text` | 湖边风急雨丝长／娘子莫教湿衣裳／君子相怜情意厚／怎教你独受风凉／些小风雨何须讲／请接此伞莫彷徨 |
| `path` | `builds/act1-jingju-duet/six-lines-continuous-revision-01-mix.wav` |
| `sha256` | `23acea77efbd90da43a53d91bcbcb0b0967de6552b47cbbff92d2f96cba6eebd` |
| `sample_rate_hz` / `channels` | `48000` / `2`；16-bit PCM |
| `duration_ms` | `31002.0625` |
| `decode_verified` | `true`；独立哈希、严格完整解码、满幅样本与整条采样比对通过 |
| `listening_result` | `accepted_by_user`；“试听通过，再多一点尾音就好了，继续制作吧”；末句拖腔微调另行验收 |
| `rights_status` | `local_prototype_only; redistribution_permission_unverified` |
| `game_integration_ready` | `false`；前后器乐、念白、完整编排与玩法接入未完成 |

独立人声和伴奏试听版分别为同目录的 `six-lines-continuous-revision-01-vocals.wav`、`six-lines-continuous-revision-01-accompaniment.wav`。模型参数、三组旋律区间与种子、全部输出哈希及实际核验命令见 `2026-10-10-jingju-six-line-duet.md`；结构化证据为 `continuous-revision-request.json`、`continuous-revision-result.json`、`continuous-revision-verification.json`。

## 待完成内容

许仙开场两句已随六句修正版通过；末句“徨”字拖腔微调、移步与游湖器乐、等待过门及独立合成收锣已包含在即时／延迟两版试听中。Q12 用户确认“三段都通过，继续制作念白”，两版及三轮循环均通过，新器乐无人声结论以这次听验为依据。参数、来源区间、全部哈希与验证见 `2026-10-10-jingju-umbrella-continuity.md`、`builds/act1-opera-continuity/continuity-result.json`。

开场及还伞念白仍待制作。完整声音方案通过后才确定主轨长度、对白时标、声卡实测保护区和循环安全出口，生成正式 `assets/audio/act1-opera/manifest.json`。不为现有 55 秒音轨补空白，也不以多个混音副本冒充独立分轨。

## 白素贞开场念白能力小样：待 Q14 试听

三位角色的原念白参考已通过 Q13。当前只试白素贞“青妹，你看，柳色映着湖波，果然是好风光。”，文件 `builds/act1-jingju-speech/baisuzhen-opening-speech-pilot-01.wav`，SHA-256 `c650f86bb2b2bf6741324195aaad5aec56a763381cd9bfd101f421d0d88e72c9`；48 kHz、双声道、16-bit PCM，9613.0625 ms。没有额外添加配乐；哈希、严格完整解码及波形核验通过，`listening_result = pending`、`speech_support_verified = false`。参数、角色参考、原始生成哈希及实际验证见 `2026-10-10-jingju-speech-pilot.md`；不能从歌唱小样通过推导念白能力或全部念白已通过。
