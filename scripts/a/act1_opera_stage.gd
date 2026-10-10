extends RefCounted
class_name Act1OperaStage
## 根据已制作音源建第一幕；旧 StageDef 工厂仍供其他关卡和旧测试使用。

static func make_stage(config: Dictionary) -> StageDef:
	var def := StageDef.make_level1()
	def.duration_ms = int(config.duration_ms)
	def.track_path = str(config.main_path)
	def.title = "第一幕 · 游湖借伞"
	def.roles = ["白素贞", "许仙", "小青"]
	def.segments = []
	var starts: Array = [0, int(config.opening_end_ms), int(config.arrival_ms),
		int(config.tour_start_ms), int(config.return_gate_ms), int(config.closing_ms), def.duration_ms]
	var names: Array = ["湖边对白", "移步", "借伞", "游湖", "还伞对白", "收势"]
	for i in names.size():
		def.segments.append({"name": names[i], "start_ms": starts[i], "end_ms": starts[i + 1]})
	# 交接改为真实条件触发，不用固定拍点考玩家；对白期间不安排评分动作。
	# 保留收势姿态的原有评分/补救通路，移动指导由当前剧情阶段提供。
	def.cues = [Cue.make("l1_opera_lower_hand", int(config.closing_ms) + 900,
		Cue.ACTION_HAND_LOWER, 0,
		{"key": "angle", "min": -0.15, "max": 0.15}, 250, "hand_lower")]
	def.cues[0]["segment"] = "收势"
	return def
