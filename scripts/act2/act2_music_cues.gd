extends Node
## 用户视频的出场音乐与落地重音。只读真实阶段，不推进剧情。

const ENTRY := "res://assets/audio/act2-hall/fahai-entry.wav"
const HIT := "res://assets/audio/act2-hall/xu-fall-hit.wav"
var entry: AudioStreamPlayer
var hit: AudioStreamPlayer
var hit_count: int = 0
var _paused: bool = false


func setup() -> bool:
	entry = _player(ENTRY, true)
	hit = _player(HIT, false)
	return entry != null and hit != null


func _player(path: String, loop: bool) -> AudioStreamPlayer:
	var stream: AudioStreamWAV = load(path) as AudioStreamWAV
	if (
		stream == null
		or stream.mix_rate != 48000
		or not stream.stereo
		or stream.format != AudioStreamWAV.FORMAT_16_BITS
	):
		push_error("第二幕视频音乐格式不符：" + path)
		return null
	var player := AudioStreamPlayer.new()
	var copy: AudioStreamWAV = stream.duplicate()
	copy.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	copy.loop_end = int(round(copy.get_length() * copy.mix_rate))
	player.stream = copy
	add_child(player)
	return player


func update_entrance(phase: String, present: bool) -> void:
	if entry == null or _paused:
		return
	if phase == "wait_arrival" and present:
		if not entry.playing:
			entry.play()
	else:
		entry.stop()


func update_fall(progress: float) -> void:
	if hit == null or _paused or hit_count > 0 or progress < 0.95:
		return
	hit_count += 1
	hit.play()


func set_paused(value: bool) -> void:
	_paused = value
	for player: AudioStreamPlayer in [entry, hit]:
		if player != null:
			player.stream_paused = value


func _exit_tree() -> void:
	for player: AudioStreamPlayer in [entry, hit]:
		if player != null:
			player.stop()
			player.stream = null
