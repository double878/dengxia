extends Node
## 第一场自然对白、真实迎接许可与暗场，只读取宿主唯一 MusicClock。

signal finished

const MANIFEST := "res://assets/audio/act2-opening/score.json"
const GREETING_STEP := 40.0
var config: Dictionary = {}
var phase: String = "wait_arrival"
var player: AudioStreamPlayer
var clock: MusicClock
var controller: PuppetController
var problem: String = ""
var arrival_target_x: float = 0.0
var greeting_target_x: float = 0.0
var _greeting_origin: float = 0.0
var _missing_actor: bool = false
var _fahai_present: bool = false
var _xuxian_present: bool = false


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
	var dark := int(config.get("dark_start_ms", -1))
	var duration := int(config.get("duration_ms", -1))
	if dark <= 0 or duration <= dark:
		return _fail("第二关第一幕暗场时标非法")
	var lines: Variant = config.get("lines")
	if not (lines is Array) or lines.is_empty():
		return _fail("第二关第一场缺少对白字幕")
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
			or str(row.get("role_id", "")) not in ["fahai", "xuxian"]
			or begin < previous
			or end <= begin
			or end > dark
		):
			return _fail("第二关第一幕台词身份、时标或内容非法：" + id)
		ids[id] = true
		previous = end
	var greeting_gate := int(config.get("greeting_gate_ms", -1))
	if greeting_gate != 0:
		return _fail("第二关对白须从实际迎接后完整播放，不得提前消耗首句")
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
	arrival_target_x = controller.get_puppet(0).stage_pos.x - 380.0 / 1920.0
	_greeting_origin = controller.get_puppet(1).stage_pos.x
	return true


func update(on_stage: Array[int], entrance_clear: bool, music_ready: bool = true) -> void:
	if phase in ["error", "finished"] or clock.is_paused():
		return
	_fahai_present = on_stage.has(0)
	_xuxian_present = on_stage.has(1)
	_missing_actor = not _fahai_present or (phase != "wait_arrival" and not _xuxian_present)
	if phase != "closing" and _missing_actor:
		clock.set_song_frozen(true)
		return
	if phase == "wait_arrival":
		var fahai := controller.get_puppet(0)
		if entrance_clear and fahai.facing == -1.0:
			_update_greeting_target()
			phase = "wait_greeting"
		return
	var now := clock.get_song_time_ms()
	if phase == "wait_greeting":
		_update_greeting_target()
		if _has_greeted() and music_ready:
			phase = "dialogue"
			clock.set_song_frozen(false)
		return
	clock.set_song_frozen(false)
	# 开场音乐完整结束并实际迎接后，六句对白连续走同一主轨。
	if now >= int(config.dark_start_ms):
		phase = "closing"
	if now >= int(config.duration_ms):
		phase = "finished"
		clock.set_song_frozen(true)
		player.stop()
		finished.emit()


func _update_greeting_target() -> void:
	var direction := signf(controller.get_puppet(0).stage_pos.x - _greeting_origin)
	greeting_target_x = controller.get_puppet(0).stage_pos.x - direction * 300.0 / 1920.0


func _has_greeted() -> bool:
	var fahai := controller.get_puppet(0)
	var xuxian := controller.get_puppet(1)
	var toward := signf(fahai.stage_pos.x - xuxian.stage_pos.x)
	var direction := signf(fahai.stage_pos.x - _greeting_origin)
	var moved := (xuxian.stage_pos.x - _greeting_origin) * direction * 1920.0
	var gap := absf(fahai.stage_pos.x - xuxian.stage_pos.x) * 1920.0
	return (
		moved >= GREETING_STEP
		and gap >= 220.0
		and gap <= 380.0
		and fahai.facing == -toward
		and xuxian.facing == toward
		and absf(fahai.stage_pos.y - xuxian.stage_pos.y) * 1080.0 < 50.0
	)


func get_line() -> Dictionary:
	if phase in ["wait_arrival", "wait_greeting", "error", "finished"] or _missing_actor:
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
			if not _fahai_present:
				return "按 1 请法海上场 · 空格接手后向左走出柳树"
			if controller.controlled_id == 0:
				return "向左走出柳树，等许仙出门迎接"
			return "空格接手法海 · 向左走出柳树，等许仙迎接"
		"wait_greeting":
			if not _fahai_present:
				return "按 1 请法海重新上场，等许仙迎接"
			if not _xuxian_present:
				return "按 2 请许仙出门迎接 · 空格接手后朝法海走近"
			if controller.controlled_id == 1:
				return "从门洞朝法海走近，面对面迎接后回话"
			return "空格接手许仙 · 从门洞朝法海走近，面对面迎接后回话"
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
