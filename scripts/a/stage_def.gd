extends RefCounted
class_name StageDef
## 第一关关卡数据：固定时长、BPM 与段落。
##
## 契约见 TECH_DESIGN.md 第 2.2 节与 docs/superpowers/plans/2026-10-03-level1-a.md。
## 本切片只落「时长 + BPM + 段落地基」；关键动作 Cue 列表属切片 3，届时填写，
## 读取器与校验器现在就把 Cue 纳入结构，避免切片 3 再改契约。

const CueScript := preload("res://scripts/a/cue.gd")

const LEVEL1_DURATION_MS: int = 35000     ## PRD 第 6 节：第一关固定 35 秒（不延长）
const LEVEL1_BPM: float = 96.0            ## PRD 第 10 节：原型 BPM 初始考虑 90-100
const LEVEL1_ID: int = 1
## 「抬手」到位的角度区间（弧度）。手角以「手臂自然垂下」为 0、π 为举过头顶，
## 因此 135°～180° 就是「手举到顶」这一档姿势。
const LEVEL1_HAND_RAISE_MIN_RAD: float = PI * 0.75
const LEVEL1_HAND_RAISE_MAX_RAD: float = PI

var id: int = LEVEL1_ID
var duration_ms: int = LEVEL1_DURATION_MS
var bpm: float = LEVEL1_BPM
var track_path: String = ""               ## 正式锣鼓主音轨；B 未交付时保持为空
var segments: Array = []                  ## [{name: String, start_ms: int, end_ms: int}]
var cues: Array = []                      ## 关键动作列表，结构见 make_cue()；切片 3 填写


## 第一关数据。段落按拍数编排（TECH_DESIGN.md 2.1：关卡数据按拍数、以毫秒存储）。
## 关键动作覆盖 PRD 第 6 节对第一关的最低要求：站起、横向移动、抬手，
## 以及至少一次落在重音上的关键动作（重音每 4 拍一次，落点序号都是 4 的倍数）。
static func make_level1() -> StageDef:
	var def := StageDef.new()
	def.id = LEVEL1_ID
	def.duration_ms = LEVEL1_DURATION_MS
	def.bpm = LEVEL1_BPM
	def.track_path = ""
	# 段落连续覆盖整关、单调递增且不重复（TECH_DESIGN.md 2.2 的校验要求）
	def.segments = [
		{"name": "起势", "start_ms": def.beat_ms(0), "end_ms": def.beat_ms(3)},
		{"name": "起身", "start_ms": def.beat_ms(3), "end_ms": def.beat_ms(7)},
		{"name": "移步", "start_ms": def.beat_ms(7), "end_ms": def.beat_ms(13)},
		{"name": "抬手", "start_ms": def.beat_ms(13), "end_ms": def.beat_ms(17)},
		{"name": "回行", "start_ms": def.beat_ms(17), "end_ms": def.beat_ms(23)},
		{"name": "收势", "start_ms": def.beat_ms(23), "end_ms": def.duration_ms},
	]
	def.cues = make_level1_cues(def)
	return def


## 第一关关键动作表。落点全部取整拍，方便与重音对齐核对。
## 每条都在落点前 1 s 有可读线索（hint_lead_ms），满足「落点前获得提示数据」。
## segment 字段指向所在段落名，供按段汇总合拍度与低合拍补救使用。
static func make_level1_cues(def: StageDef) -> Array:
	var cues: Array = [
		# 第 2 拍：先蹲下（stance 落到接近 1.0），为第 4 拍的站起做准备
		CueScript.make("l1_c0_crouch", def.beat_ms(2), CueScript.ACTION_CROUCH, 0,
			{"key": "stance", "min": 0.85, "max": 1.0}, 250, "crouch"),
		# 重音（第 4 拍）：站起。stance 0.0 = 完全站立，因此「站起」的到位范围是接近 0，
		# 而不是 0.7-1.0（那是蹲下方向，写成后者会让蹲到底反而被判成站起）。
		CueScript.make("l1_c1_stand", def.beat_ms(4), CueScript.ACTION_STAND_UP, 0,
			{"key": "stance", "min": 0.0, "max": 0.05}, 250, "stand_up"),
		# 第 8 拍：向左横向移动（默认站位 x=0.5 不算「已到位」，必须真的左移）
		CueScript.make("l1_c2_move_left", def.beat_ms(8), CueScript.ACTION_MOVE_LEFT, 0,
			{"key": "x", "min": 0.0, "max": 0.35}, 250, "move_left"),
		# 第 14 拍：抬手（手角 0 = 自然垂下，π = 举过头顶）
		CueScript.make("l1_c3_hand_raise", def.beat_ms(14), CueScript.ACTION_HAND_RAISE, 0,
			{"key": "angle", "min": LEVEL1_HAND_RAISE_MIN_RAD, "max": LEVEL1_HAND_RAISE_MAX_RAD},
			250, "hand_raise"),
		# 重音（第 20 拍）：向右横向移动
		CueScript.make("l1_c4_move_right", def.beat_ms(20), CueScript.ACTION_MOVE_RIGHT, 0,
			{"key": "x", "min": 0.65, "max": 1.0}, 250, "move_right"),
		# 重音（第 24 拍）：移动到中位到位
		CueScript.make("l1_c5_reach_center", def.beat_ms(24), CueScript.ACTION_REACH, 0,
			{"key": "x", "min": 0.47, "max": 0.53}, 250, "reach_center"),
	]
	# 标注所属段落
	var segment_of: Dictionary = {
		"l1_c0_crouch": "起势",
		"l1_c1_stand": "起身",
		"l1_c2_move_left": "移步",
		"l1_c3_hand_raise": "抬手",
		"l1_c4_move_right": "回行",
		"l1_c5_reach_center": "收势",
	}
	for cue in cues:
		var cue_id: String = str(cue.get("cue_id", ""))
		cue["segment"] = str(segment_of.get(cue_id, ""))
	return cues


func beat_duration_ms() -> float:
	return 60000.0 / maxf(bpm, 1.0)


func beat_ms(beat_index: int) -> int:
	return int(round(float(beat_index) * beat_duration_ms()))


func total_beats() -> int:
	return int(floor(float(duration_ms) / beat_duration_ms()))


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
		for p in CueScript.validate(cue):
			problems.append("stage %d: %s" % [id, p])
		var beat_time_ms: int = int(cue.get("beat_time_ms", -1))
		if beat_time_ms < 0 or beat_time_ms > duration_ms:
			problems.append("stage %d cue「%s」落点 %d 不在关卡时长内" % [id, cue_id, beat_time_ms])
		# 前四关重要落点必须给补救留出可见时间（TECH_DESIGN.md 2.2）
		if CueScript.hint_time_ms(cue) >= beat_time_ms and beat_time_ms > 0:
			problems.append("stage %d cue「%s」的线索时间不早于落点" % [id, cue_id])
	return problems
