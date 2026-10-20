extends Node
## 仅播放用户原声。缺少真实样本时明确进入无声排练，不制造空主轨。
const MANIFEST := "res://assets/audio/act3-mountain/score.json"
const GATE_IDS: Array[String] = ["entrance", "challenge"]
var config: Dictionary = {}
var player: AudioStreamPlayer
var problem: String = ""


func setup(clock: MusicClock) -> bool:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not data is Dictionary or clock == null:
		return _fail("第三幕时钟或音源清单缺失")
	config = data
	var duration: int = int(config.get("duration_ms", 0))
	if duration <= 0 or int(config.get("scene_id", 0)) != 31:
		return _fail("第三幕时长或场次非法")
	var previous: int = -1
	var ids: Dictionary = {}
	var gates: Variant = config.get("gates")
	if not gates is Array or gates.size() != GATE_IDS.size():
		return _fail("第三幕上山与出山清单缺失")
	for i in range(gates.size()):
		var gate: Variant = gates[i]
		if not gate is Dictionary or str(gate.get("id", "")) != GATE_IDS[i]:
			return _fail("第三幕动作身份或顺序非法")
		var at: int = int(gate.get("at_ms", -1))
		var id: String = str(gate.get("id", ""))
		if at <= previous or at >= duration or id.is_empty() or ids.has(id):
			return _fail("第三幕动作等待点无效")
		previous = at
		ids[id] = true
	previous = 0
	var lines: Variant = config.get("lines")
	if not lines is Array or lines.is_empty():
		return _fail("第三幕字幕清单缺失")
	for line: Variant in lines:
		if not line is Dictionary:
			return _fail("第三幕字幕条目无效")
		var start: int = int(line.get("start_ms", -1))
		var end: int = int(line.get("end_ms", -1))
		if (
			start < previous
			or end <= start
			or end > duration
			or str(line.get("text", "")).is_empty()
		):
			return _fail("第三幕字幕清单无效")
		previous = end
	var fight: Variant = config.get("fight", {})
	if not fight is Dictionary:
		return _fail("第三幕交手编排必须为字典")
	previous = -1
	if not fight.is_empty():
		for key: String in [
			"start_ms", "draw_ms", "defeat_ms", "retreat_ms", "crane_ms", "duel_ms"
		]:
			var at: int = int(fight.get(key, -1))
			if at <= previous or at >= duration:
				return _fail("第三幕交手编排时间非法：" + key)
			previous = at
	var finale: Variant = config.get("finale", {})
	if not finale is Dictionary:
		return _fail("第三幕仙翁编排必须为字典")
	if not finale.is_empty():
		previous = int(fight.get("duel_ms", -1))
		for key: String in [
			"start_ms", "stop_ms", "gather_ms", "gift_ms", "advice_ms", "farewell_ms", "end_ms"
		]:
			var at: int = int(finale.get(key, -1))
			if at <= previous or at > duration:
				return _fail("第三幕仙翁编排时间非法：" + key)
			previous = at
		if int(finale.end_ms) != duration or not bool(config.get("complete", false)):
			return _fail("仙翁结尾必须与整关收场时长一致")
	if not bool(config.get("audio_available", false)):
		if not str(config.get("main_path", "")).is_empty():
			return _fail("缺音排练不能指向占位音轨")
		return true
	var wav := load(str(config.get("main_path", ""))) as AudioStreamWAV
	if (
		wav == null
		or wav.mix_rate != 48000
		or not wav.stereo
		or wav.format != AudioStreamWAV.FORMAT_16_BITS
		or wav.loop_mode != AudioStreamWAV.LOOP_DISABLED
		or wav.get_length() <= 0.0
		or absf(wav.get_length() * 1000.0 - int(config.get("audio_duration_ms", 0))) > 1.0
		or absf(wav.get_length() * 1000.0 - duration) > 100.0
	):
		return _fail("第三幕原声须有真实 48k 双声道 PCM16 样本，并与本场时轴对齐")
	player = AudioStreamPlayer.new()
	player.name = "OriginalVideoAudio"
	player.stream = wav
	add_child(player)
	clock.set_player(player)
	return true


func _fail(message: String) -> bool:
	problem = message
	push_error(message)
	return false


func _exit_tree() -> void:
	if is_instance_valid(player):
		player.stop()
		player.stream = null
