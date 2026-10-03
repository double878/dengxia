extends RefCounted
class_name StageDef
## 第一关关卡数据：固定时长、BPM 与段落。
##
## 契约见 TECH_DESIGN.md 第 2.2 节与 docs/superpowers/plans/2026-10-03-level1-a.md。
## 本切片只落「时长 + BPM + 段落地基」；关键动作 Cue 列表属切片 3，届时填写，
## 读取器与校验器现在就把 Cue 纳入结构，避免切片 3 再改契约。

const LEVEL1_DURATION_MS: int = 35000     ## PRD 第 6 节：第一关固定 35 秒（不延长）
const LEVEL1_BPM: float = 96.0            ## PRD 第 10 节：原型 BPM 初始考虑 90-100
const LEVEL1_ID: int = 1

var id: int = LEVEL1_ID
var duration_ms: int = LEVEL1_DURATION_MS
var bpm: float = LEVEL1_BPM
var track_path: String = ""               ## 正式锣鼓主音轨；B 未交付时保持为空
var segments: Array = []                  ## [{name: String, start_ms: int, end_ms: int}]
var cues: Array = []                      ## 关键动作列表，结构见 make_cue()；切片 3 填写


## 第一关数据。段落按拍数编排（TECH_DESIGN.md 2.1：关卡数据按拍数、以毫秒存储）。
static func make_level1() -> StageDef:
	var def := StageDef.new()
	def.id = LEVEL1_ID
	def.duration_ms = LEVEL1_DURATION_MS
	def.bpm = LEVEL1_BPM
	def.track_path = ""
	# 段落连续覆盖整关、单调递增且不重复（TECH_DESIGN.md 2.2 的校验要求）
	def.segments = [
		{"name": "起势", "start_ms": def.beat_ms(0), "end_ms": def.beat_ms(8)},
		{"name": "起身", "start_ms": def.beat_ms(8), "end_ms": def.beat_ms(20)},
		{"name": "移步", "start_ms": def.beat_ms(20), "end_ms": def.beat_ms(34)},
		{"name": "抬手", "start_ms": def.beat_ms(34), "end_ms": def.beat_ms(46)},
		{"name": "收势", "start_ms": def.beat_ms(46), "end_ms": def.duration_ms},
	]
	def.cues = []
	return def


func beat_duration_ms() -> float:
	return 60000.0 / maxf(bpm, 1.0)


func beat_ms(beat_index: int) -> int:
	return int(round(float(beat_index) * beat_duration_ms()))


func total_beats() -> int:
	return int(floor(float(duration_ms) / beat_duration_ms()))


## 关键动作条目工厂。字段依 TECH_DESIGN.md 2.2 的 Cue 行。
static func make_cue(cue_id: String, beat_time_ms: int, action: String, target_object: int,
		target_range: Dictionary, tolerance_ms: int, demo_action: String) -> Dictionary:
	return {
		"cue_id": cue_id,
		"beat_time_ms": beat_time_ms,
		"action": action,
		"target_object": target_object,
		"target_range": target_range,
		"tolerance_ms": tolerance_ms,
		"demo_action": demo_action,
	}


## 校验关卡数据。返回问题列表；空列表表示通过。
## 开发构建启动时直接报出关卡与 cue_id，防止静默跳过动作（TECH_DESIGN.md 2.2）。
func validate() -> Array[String]:
	var problems: Array[String] = []
	if id <= 0:
		problems.append("stage %d: id 必须为正整数" % id)
	if duration_ms <= 0:
		problems.append("stage %d: duration_ms 必须为正，实际 %d" % [id, duration_ms])
	if bpm <= 0.0:
		problems.append("stage %d: bpm 必须为正，实际 %s" % [id, str(bpm)])
	var previous_end: int = -1
	for i in segments.size():
		var seg: Dictionary = segments[i]
		var name: String = str(seg.get("name", "?"))
		var start_ms: int = int(seg.get("start_ms", 0))
		var end_ms: int = int(seg.get("end_ms", 0))
		if start_ms < 0 or end_ms > duration_ms:
			problems.append("stage %d 段「%s」超出关卡时长：%d-%d（时长 %d）"
				% [id, name, start_ms, end_ms, duration_ms])
		if end_ms <= start_ms:
			problems.append("stage %d 段「%s」起止不递增：%d-%d" % [id, name, start_ms, end_ms])
		if start_ms < previous_end:
			problems.append("stage %d 段「%s」与上一段重叠：start=%d < 上一段 end=%d"
				% [id, name, start_ms, previous_end])
		previous_end = end_ms
	if not segments.is_empty() and previous_end < duration_ms:
		problems.append("stage %d 段落未覆盖整关：最后一段结束于 %d，时长 %d"
			% [id, previous_end, duration_ms])
	var seen: Dictionary = {}
	for cue in cues:
		var cue_id: String = str(cue.get("cue_id", ""))
		if cue_id.is_empty():
			problems.append("stage %d: 存在空 cue_id" % id)
			continue
		if seen.has(cue_id):
			problems.append("stage %d: cue_id 重复「%s」" % [id, cue_id])
		seen[cue_id] = true
		var beat_time_ms: int = int(cue.get("beat_time_ms", -1))
		if beat_time_ms < 0 or beat_time_ms > duration_ms:
			problems.append("stage %d cue「%s」落点 %d 不在关卡时长内" % [id, cue_id, beat_time_ms])
		if int(cue.get("tolerance_ms", 0)) <= 0:
			problems.append("stage %d cue「%s」缺少有效判定容差" % [id, cue_id])
	return problems
