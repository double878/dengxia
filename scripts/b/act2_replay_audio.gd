extends Node
## 按记录恢复两场主轨、视频音乐和补救鼓，不连接 MusicClock 或动作判定。
var players: Dictionary = {}
var _active: Dictionary = {}
var scene_id: int = 0
var _entry_streams: Dictionary = {}


func setup() -> void:
	var opening_config: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/audio/act2-opening/score.json")
	)
	for key: String in ["opening", "hall", "entry", "hit", "slow"]:
		var path: String
		if key in ["opening", "hall"]:
			var manifest: String = "res://assets/audio/act2-%s/score.json" % key
			var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest))
			path = str(config.main_path)
		else:
			path = {
				"entry": str(opening_config.get("intro_path", "")),
				"hit": "res://assets/audio/act2-hall/xu-fall-hit.wav",
				"slow": "res://assets/audio/act1-natural/remedy.wav"
			}[key]
		var wav := load(path) as AudioStreamWAV
		if wav == null:
			push_error("第二关回放缺少音源：" + path)
			continue
		var player := AudioStreamPlayer.new()
		var stream: AudioStreamWAV = wav.duplicate()
		stream.loop_mode = (
			AudioStreamWAV.LOOP_FORWARD
			if key == "slow"
			else AudioStreamWAV.LOOP_DISABLED
		)
		stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
		player.stream = stream
		add_child(player)
		players[key] = player
		_active[key] = false
		if key == "entry":
			_entry_streams[2] = stream
	var hall_entry := load("res://assets/audio/act2-hall/fahai-entry.wav") as AudioStreamWAV
	if hall_entry != null:
		var hall_loop: AudioStreamWAV = hall_entry.duplicate()
		hall_loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		hall_loop.loop_end = int(round(hall_loop.get_length() * hall_loop.mix_rate))
		_entry_streams[22] = hall_loop


func apply_recorded(scene: int, view: Dictionary, paused: bool) -> void:
	if scene != scene_id:
		stop()
		scene_id = scene
		if players.has("entry") and _entry_streams.has(scene):
			players.entry.stream = _entry_streams[scene]
	for key: String in players:
		var source: String = "main" if key == ("opening" if scene == 2 else "hall") else key
		var state: Dictionary = (
			{} if key in ["opening", "hall"] and source != "main" else view.get(source, {})
		)
		var player: AudioStreamPlayer = players[key]
		if not bool(state.get("playing", false)):
			player.stream_paused = false
			player.stop()
			_active[key] = false
			continue
		var at: float = maxf(float(state.get("position_ms", 0)) / 1000.0, 0.0)
		var hold: bool = paused or bool(state.get("paused", false))
		# WAV 在暂停时 seek 不一定更新声音游标；恢复/跳段从记录位置播放。
		if not _active[key] or (player.stream_paused and not hold):
			player.stream_paused = false
			player.play(at)
			_active[key] = true
		elif absf(player.get_playback_position() - at) > .15:
			player.stream_paused = false
			player.play(at)
		player.volume_db = float(state.get("volume_db", 0))
		player.stream_paused = hold


func stop() -> void:
	for key: String in players:
		players[key].stream_paused = false
		players[key].stop()
		_active[key] = false


func _exit_tree() -> void:
	stop()
	for player: AudioStreamPlayer in players.values():
		player.stream = null
