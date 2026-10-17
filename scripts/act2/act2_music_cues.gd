extends Node
## 用户视频的出场音乐与许仙惊叫。只读真实阶段，不推进剧情。

const ENTRY := "res://assets/audio/act2-hall/fahai-entry.wav"
const HIT := "res://assets/audio/act2-hall/xu-fright.wav"
var entry: AudioStreamPlayer
# 沿用录放的 hit 单次声音槽，内容现为许仙惊叫，不再播放落地重音。
var hit: AudioStreamPlayer
var hit_count: int = 0
var _paused: bool = false
var _play_once_on_start: bool = false
var _entry_finished: bool = false


func setup(entry_path: String = ENTRY, play_once_on_start: bool = false) -> bool:
	_play_once_on_start = play_once_on_start
	entry = _player(entry_path, not play_once_on_start)
	hit = _player(HIT, false)
	if entry == null or hit == null:
		return false
	if _play_once_on_start:
		entry.finished.connect(_on_entry_finished)
		entry.play()
	return true


func _on_entry_finished() -> void:
	_entry_finished = true


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


func update_entrance(phase: String, present: bool, song_ms: int = 0, crossfade_ms: int = 0) -> void:
	if entry == null or _paused:
		return
	# 开场单次音乐从 setup 播放到 finished，不受出场、迎接或缺场影响。
	if _play_once_on_start:
		return
	if phase in ["wait_arrival", "wait_greeting"] and present:
		entry.volume_db = 0.0
		if not entry.playing:
			entry.play()
	elif (
		phase == "dialogue"
		and present
		and entry.playing
		and crossfade_ms > 0
		and song_ms < crossfade_ms
	):
		entry.volume_db = linear_to_db(maxf(1.0 - float(song_ms) / crossfade_ms, 0.0001))
	else:
		entry.stop()
		entry.volume_db = 0.0


func can_start_main() -> bool:
	if _play_once_on_start:
		return _entry_finished
	if entry == null or not entry.playing:
		return true
	var position := entry.get_playback_position()
	# 同源器乐在循环边界交接；只读播放器，不增加剧情时钟。
	return position <= 0.03 or position >= entry.stream.get_length() - 0.06


func play_fright() -> void:
	if hit == null or _paused or hit_count > 0:
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
