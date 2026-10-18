extends Node
## 波形清单与非循环主轨。只绑定宿主时钟，动作许可由 Actions 决定。

const MANIFEST := "res://assets/audio/act2-hall/score.json"
const SPEAKERS: Array[String] = [
	"xuxian", "xiaoqing", "xuxian", "baisuzhen", "xiaoqing", "baisuzhen", "xuxian"
]
var config: Dictionary = {}
var player: AudioStreamPlayer
var problem: String = ""


func setup(clock: MusicClock) -> bool:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not (value is Dictionary) or clock == null:
		return _fail("第二幕缺少时钟或有效音源清单")
	config = value
	if str(config.get("audio_version", "")).is_empty():
		return _fail("第二幕音源没有版本")
	var duration: int = int(config.get("duration_ms", -1))
	if not _rows_valid(config.get("lines"), SPEAKERS, "speech", duration):
		return _fail("第二幕七句对白的身份、内容或时标非法")
	if not _rows_valid(
		config.get("duet"), ["xuxian", "baisuzhen", "xuxian", "baisuzhen"], "singing", duration
	):
		return _fail("第二幕四组对唱的身份、内容或时标非法")
	var qing: int = int(config.get("qing_gate_ms", -1))
	var duet_start: int = int(config.get("duet_start_ms", -1))
	var duet_end: int = int(config.get("duet_end_ms", -1))
	var duet_gate: int = int(config.get("duet_gate_ms", -1))
	var medicine: int = int(config.get("medicine_gate_ms", -1))
	if (
		qing < int(config.lines[4].end_ms)
		or duet_start - qing < 500
		or int(config.duet[0].start_ms) != duet_start
		or duet_end < int(config.duet[-1].end_ms)
		or duet_gate < duet_end
		or int(config.lines[5].start_ms) - duet_gate < 500
		or medicine < int(config.lines[6].end_ms)
		or duration - medicine < 500
	):
		return _fail("第二幕动作等待点缺少完整声音或保护静音")
	var path: String = str(config.get("main_path", ""))
	var wav: AudioStreamWAV = load(path) as AudioStreamWAV
	if (
		wav == null
		or wav.mix_rate != 48000
		or wav.format != AudioStreamWAV.FORMAT_16_BITS
		or not wav.stereo
		or wav.loop_mode != AudioStreamWAV.LOOP_DISABLED
		or absf(wav.get_length() * 1000.0 - duration) > 1.0
	):
		return _fail("第二幕主轨必须为无循环 48k 双声道 PCM16，长度与清单一致")
	player = AudioStreamPlayer.new()
	player.name = "HallMain"
	player.stream = wav
	add_child(player)
	clock.set_player(player)
	clock.start()
	return true


func _rows_valid(rows: Variant, speakers: Array[String], delivery: String, duration: int) -> bool:
	if not (rows is Array) or rows.size() != speakers.size():
		return false
	var previous: int = 0
	var ids: Dictionary = {}
	for i in range(rows.size()):
		var row: Variant = rows[i]
		if not (row is Dictionary):
			return false
		var id: String = str(row.get("line_id", ""))
		var begin: int = int(row.get("start_ms", -1))
		var end: int = int(row.get("end_ms", -1))
		if (
			id.is_empty()
			or ids.has(id)
			or str(row.get("text", "")).is_empty()
			or str(row.get("role_name", "")).is_empty()
			or str(row.get("role_id", "")) != speakers[i]
			or str(row.get("delivery", "")) != delivery
			# 生成器保留的尾部采样可跨音乐窗数毫秒，不裁掉尾音。
			or begin < previous - (20 if delivery == "singing" else 0)
			or end <= begin
			or end > duration
		):
			return false
		ids[id] = true
		previous = end
	return true


func _fail(message: String) -> bool:
	problem = message
	push_error(message)
	return false


func _exit_tree() -> void:
	if player != null:
		player.stop()
		player.stream = null
