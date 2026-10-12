extends Node
## 第一幕真实走位许可、自然对白与暗场，只读取宿主唯一 MusicClock。

signal finished

const MANIFEST := "res://assets/audio/act2-opening/score.json"
const AGREEMENT_STEP := 40.0
var config: Dictionary = {}
var phase: String = "wait_arrival"
var player: AudioStreamPlayer
var clock: MusicClock
var controller: PuppetController
var problem: String = ""
var agreement_target_x: float = 0.0
var _agreement_origin: float = 0.0
var _agreement_direction: float = 1.0
var _missing_actor: bool = false


func setup(p_clock: MusicClock, p_controller: PuppetController) -> bool:
	clock = p_clock
	controller = p_controller
	if clock == null or controller == null:
		return _fail("第二关第一幕缺少时钟或影人控制器")
	if not FileAccess.file_exists(MANIFEST):
		return _fail("缺少第二关第一幕音源清单：" + MANIFEST)
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not (value is Dictionary):
		return _fail("第二关第一幕音源清单必须为对象")
	config = value
	if str(config.get("audio_version", "")).is_empty():
		return _fail("第二关第一幕缺少音源版本")
	var gate := int(config.get("agreement_gate_ms", -1))
	var dark := int(config.get("dark_start_ms", -1))
	var duration := int(config.get("duration_ms", -1))
	if gate <= 0 or dark <= gate or duration <= dark:
		return _fail("第二关第一幕应允与暗场时标非法")
	var lines: Variant = config.get("lines")
	if not (lines is Array) or lines.size() != 6:
		return _fail("第二关第一幕须交付六句对白")
	var previous := 0
	var ids := {}
	for i in range(lines.size()):
		var row: Variant = lines[i]
		if not (row is Dictionary):
			return _fail("第二关第一幕台词格式非法")
		var id := str(row.get("line_id", ""))
		var begin := int(row.get("start_ms", -1))
		var end := int(row.get("end_ms", -1))
		if (
			id.is_empty()
			or ids.has(id)
			or str(row.get("text", "")).is_empty()
			or str(row.get("role_name", "")).is_empty()
			or str(row.get("delivery", "")) != "speech"
			or str(row.get("role_id", "")) != ("fahai" if i % 2 == 0 else "xuxian")
			or begin < previous
			or end <= begin
			or end > dark
		):
			return _fail("第二关第一幕台词身份、时标或内容非法：" + id)
		ids[id] = true
		previous = end
	if gate < int(lines[4].end_ms) or gate + 200 > int(lines[5].start_ms):
		return _fail("第二关第一幕等待点须在第五、六句之间的保护静音内")
	var path := str(config.get("main_path", ""))
	if not ResourceLoader.exists(path):
		return _fail("缺少第二关第一幕主轨：" + path)
	var stream: Variant = load(path)
	if not (stream is AudioStreamWAV):
		return _fail("第二关第一幕主轨必须为 PCM WAV")
	var wav: AudioStreamWAV = stream
	if (
		wav.mix_rate != 48000
		or wav.format != AudioStreamWAV.FORMAT_16_BITS
		or not wav.stereo
		or wav.loop_mode != AudioStreamWAV.LOOP_DISABLED
		or absf(wav.get_length() * 1000.0 - duration) > 1.0
	):
		return _fail("第二关第一幕音轨格式、长度或循环设置不符")
	player = AudioStreamPlayer.new()
	player.stream = wav
	add_child(player)
	clock.set_player(player)
	clock.start()
	clock.set_song_frozen(true)
	return true


func update(on_stage: Array[int], entrance_clear: bool) -> void:
	if phase in ["error", "finished"] or clock.is_paused():
		return
	_missing_actor = not on_stage.has(0) or not on_stage.has(1)
	if phase != "closing" and _missing_actor:
		clock.set_song_frozen(true)
		return
	if phase == "wait_arrival":
		var fahai := controller.get_puppet(0)
		var xuxian := controller.get_puppet(1)
		var gap := (fahai.stage_pos.x - xuxian.stage_pos.x) * 1920.0
		if (
			entrance_clear
			and gap >= 220.0
			and gap <= 380.0
			and fahai.facing == -1.0
			and xuxian.facing == 1.0
			and absf(fahai.stage_pos.y - xuxian.stage_pos.y) * 1080.0 < 50.0
		):
			phase = "dialogue"
			clock.set_song_frozen(false)
		return
	var now := clock.get_song_time_ms()
	if phase == "dialogue" and now >= int(config.agreement_gate_ms):
		clock.set_song_frozen(true)
		_reset_agreement_step()
		phase = "wait_agreement"
		return
	if phase == "wait_agreement":
		var xuxian := controller.get_puppet(1)
		var toward := signf(controller.get_puppet(0).stage_pos.x - xuxian.stage_pos.x)
		# 自由走位可能重叠或换到另一侧；重新提示真实方向，不把挪动法海算作应允。
		if toward != _agreement_direction:
			_reset_agreement_step()
			return
		if toward == 0.0:
			return
		var moved := (xuxian.stage_pos.x - _agreement_origin) * _agreement_direction * 1920.0
		if moved >= AGREEMENT_STEP and toward == xuxian.facing:
			phase = "agreement"
			clock.set_song_frozen(false)
		return
	clock.set_song_frozen(false)
	if now >= int(config.dark_start_ms):
		phase = "closing"
	if now >= int(config.duration_ms):
		phase = "finished"
		clock.set_song_frozen(true)
		player.stop()
		finished.emit()


func _reset_agreement_step() -> void:
	_agreement_origin = controller.get_puppet(1).stage_pos.x
	_agreement_direction = signf(controller.get_puppet(0).stage_pos.x - _agreement_origin)
	agreement_target_x = _agreement_origin + _agreement_direction * AGREEMENT_STEP / 1920.0


func get_line() -> Dictionary:
	if phase in ["wait_arrival", "wait_agreement", "error", "finished"] or _missing_actor:
		return {}
	var now := clock.get_song_time_ms()
	for row: Dictionary in config.get("lines", []):
		if now >= int(row.start_ms) and now < int(row.end_ms):
			return row
	return {}


func get_hint() -> String:
	match phase:
		"error":
			return "对白音源加载失败，请查看运行日志"
		"wait_arrival":
			if controller.controlled_id == 0:
				return "向左走出柳树，来到许仙右侧面对面"
			return "空格接手法海 · 向左走出柳树，来到许仙右侧面对面"
		"wait_agreement":
			if _agreement_direction == 0.0:
				return "两人站得太近 · 先将法海移到许仙旁侧，再让许仙上前一步"
			if controller.controlled_id == 1:
				return "朝法海上前一步，表示应允"
			return "空格接手许仙 · 朝法海上前一步，表示应允"
		"closing", "finished":
			return ""
	if _missing_actor:
		return "请让退场的影人重新上场，继续对话"
	return "空格换人 · 左键拖签 · A/D 抬手 · Shift+A/D 落手"


func fade_amount() -> float:
	if phase == "finished":
		return 1.0
	if phase != "closing":
		return 0.0
	return clampf(
		(
			float(clock.get_song_time_ms() - int(config.dark_start_ms))
			/ float(int(config.duration_ms) - int(config.dark_start_ms))
		),
		0.0,
		1.0
	)


func _fail(message: String) -> bool:
	problem = message
	phase = "error"
	push_error(message)
	return false
