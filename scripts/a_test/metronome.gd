extends Node
class_name Metronome
## 第一关**临时**音轨：现场合成的旋律、低鼓与每四拍的重音。
##
## 现状说明（不要读成"正式音轨已交付"）：PRD 第 8 节要求固定 BPM 的锣鼓作为判定基准，
## 而正式锣鼓主音轨属 B 的交付物、**尚未交付**。为了让第一关当场就能听见音乐、
## 并让 MusicClock 有一个真实音频播放位置可读，这里用 AudioStreamGenerator 现场合成。
##
## 按范围限定：不改 B 的正式音频目录、不引用任何外部素材文件、不登记使用权。
## 正式音轨到位后，本类整体替换为播放素材即可，MusicClock 与判定逻辑不受影响。
##
## 每 accent_every 拍加重音，其余轻音，便于人耳确认拍点。
##
## 补救冻结期间另有一路慢鼓（RemedySlowPlayer）：主音轨此时是真的暂停了
## （解冻后必须从同一拍点续上，否则拍点会漂），所以「鼓点变成 0.1 倍速」由这条
## 独立音路表达，而不是去改主音轨的播放位置。

const SAMPLE_RATE_FALLBACK: float = 44100.0
const NOTES: Array[float] = [220.0, 247.0, 294.0, 330.0, 294.0, 247.0, 196.0, 220.0]
## 总音量增益。合成音轨的峰值本来就偏低，若不提升，实际听起来会以为「没有音乐」。
const MASTER_GAIN: float = 1.45
const PEAK_LIMIT: float = 0.92
## 补救冻结期间的慢放倍率：0.1 倍速，玩家一听就知道「现在不是正常演出时间」。
const REMEDY_SLOW_FACTOR: float = 0.1
## 慢鼓的循环长度（拍）。4 拍一段既听得出是锣鼓，又不会一路跑出曲子末尾。
const SLOW_LOOP_BEATS: int = 4

var clock: MusicClock = null

var _player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _mix_rate: float = SAMPLE_RATE_FALLBACK
var _active: bool = false
var _accent_every: int = 4
var _sample_cursor: int = 0
var _slow_player: AudioStreamPlayer = null
var _slow_playback: AudioStreamGeneratorPlayback = null
var _slow_cursor: int = 0
var _slow_active: bool = false


func setup(p_clock: MusicClock, accent_every: int = 4) -> void:
	clock = p_clock
	_accent_every = maxi(accent_every, 1)
	_sample_cursor = 0
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = SAMPLE_RATE_FALLBACK
	generator.buffer_length = 0.4
	_mix_rate = float(generator.mix_rate)
	_player = AudioStreamPlayer.new()
	_player.name = "MetronomePlayer"
	_player.stream = generator
	add_child(_player)
	_player.play()
	var playback: AudioStreamGeneratorPlayback = _player.get_stream_playback()
	if playback == null:
		push_warning("Metronome：拿不到 AudioStreamGeneratorPlayback，本机无法播放临时节拍音")
		_active = false
		return
	_playback = playback
	_active = true
	# 补救慢鼓这一路：一直挂着，只在补救冻结期间出声（stream_paused 控制）。
	_slow_player = AudioStreamPlayer.new()
	_slow_player.name = "RemedySlowPlayer"
	var slow_generator := AudioStreamGenerator.new()
	slow_generator.mix_rate = SAMPLE_RATE_FALLBACK
	slow_generator.buffer_length = 0.4
	_slow_player.stream = slow_generator
	add_child(_slow_player)
	_slow_player.play()
	_slow_player.stream_paused = true


## 供 MusicClock 读取播放位置。返回 null 表示本机无法播放节拍音。
func get_player() -> AudioStreamPlayer:
	if not _active:
		return null
	return _player


func is_active() -> bool:
	return _active


func get_mix_rate() -> float:
	return _mix_rate


## 时钟重新开始（重播 / 回到 0）时对齐拍游标。
func reset() -> void:
	_sample_cursor = 0
	_slow_cursor = 0


## 有序停播并释放音频播放对象。退出前调用，避免音频线程在引擎清理时仍持有播放缓冲。
## 仅用于退出/重置，不影响正常演出。
func stop() -> void:
	_active = false
	_slow_active = false
	_playback = null
	_slow_playback = null
	if _player != null:
		_player.stop()
		_player.stream = null
	if _slow_player != null:
		_slow_player.stop()
		_slow_player.stream = null


## 每帧补齐音频缓冲。采样时间连续，因此拖帧也不会丢拍。
## 补救冻结期间改由慢鼓这一路发声；菜单暂停时两路都停。
func update() -> void:
	if not _active or clock == null or _player == null:
		return
	if clock.is_paused():
		return
	if clock.is_song_frozen():
		_begin_slow_if_needed()
		_push_slow()
		return
	_end_slow_if_needed()
	_push_main()


func _push_main() -> void:
	var current: AudioStreamGeneratorPlayback = _player.get_stream_playback()
	if current == null:
		return
	if current != _playback:
		_playback = current
		_sample_cursor = 0
	var available: int = _playback.get_frames_available()
	for _i in available:
		var sample: float = sample_at(float(_sample_cursor) / _mix_rate)
		_playback.push_frame(Vector2(sample, sample))
		_sample_cursor += 1


## 进入补救冻结：主音轨停住，慢鼓这一路开始出声。
func _begin_slow_if_needed() -> void:
	if _slow_active:
		return
	_slow_active = true
	_slow_cursor = 0
	if _slow_player == null:
		return
	_slow_player.stream_paused = false
	_slow_playback = _slow_player.get_stream_playback()


## 离开补救冻结：慢鼓静音，主音轨由 MusicClock 负责从同一拍点续播。
func _end_slow_if_needed() -> void:
	if not _slow_active:
		return
	_slow_active = false
	if _slow_player != null:
		_slow_player.stream_paused = true


func _push_slow() -> void:
	if _slow_player == null:
		return
	var current: AudioStreamGeneratorPlayback = _slow_player.get_stream_playback()
	if current == null:
		return
	if current != _slow_playback:
		_slow_playback = current
		_slow_cursor = 0
	var available: int = current.get_frames_available()
	for _i in available:
		var sample: float = sample_at_slow(float(_slow_cursor) / _mix_rate)
		current.push_frame(Vector2(sample, sample))
		_slow_cursor += 1


## 补救冻结期间的慢鼓：同一套合成内容，但内容时间只按 REMEDY_SLOW_FACTOR 前进，
## 并在一小段（SLOW_LOOP_BEATS 拍）里循环，避免内容跑出曲子末尾。
## 0.1 倍速下声音明显「拖慢」，是玩家判断「现在正在补救」的主要听觉线索。
func sample_at_slow(real_s: float) -> float:
	var beat_s: float = 60.0 / maxf(clock.bpm if clock != null else StageDef.LEVEL1_BPM, 1.0)
	var loop_s: float = beat_s * float(SLOW_LOOP_BEATS)
	return sample_at(fposmod(real_s * REMEDY_SLOW_FACTOR, loop_s))


func sample_at(song_s: float) -> float:
	var beat_s: float = 60.0 / maxf(clock.bpm if clock != null else StageDef.LEVEL1_BPM, 1.0)
	var beat_index: int = int(floor(song_s / beat_s))
	var phase: float = fposmod(song_s, beat_s)
	var note: float = NOTES[posmod(beat_index, NOTES.size())]
	var melody: float = 0.20 * (0.35 + 0.65 * exp(-phase * 3.0)) * (
		sin(TAU * note * song_s) + 0.22 * sin(TAU * note * 2.0 * song_s))
	var drone: float = 0.05 * sin(TAU * 110.0 * song_s)
	var drum: float = 0.50 * exp(-phase * 20.0) * sin(TAU * (95.0 - 30.0 * phase) * phase)
	var accent: float = 0.0
	if beat_index % _accent_every == 0:
		accent = 0.22 * exp(-phase * 35.0) * sin(TAU * 780.0 * phase)
	return clampf((melody + drone + drum + accent) * MASTER_GAIN, -PEAK_LIMIT, PEAK_LIMIT)
