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

const SAMPLE_RATE_FALLBACK: float = 44100.0
const NOTES: Array[float] = [220.0, 247.0, 294.0, 330.0, 294.0, 247.0, 196.0, 220.0]
## 总音量增益。合成音轨的峰值本来就偏低，若不提升，实际听起来会以为「没有音乐」。
const MASTER_GAIN: float = 1.45
const PEAK_LIMIT: float = 0.92

var clock: MusicClock = null

var _player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _mix_rate: float = SAMPLE_RATE_FALLBACK
var _active: bool = false
var _accent_every: int = 4
var _sample_cursor: int = 0


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


## 有序停播并释放音频播放对象。退出前调用，避免音频线程在引擎清理时仍持有播放缓冲。
## 仅用于退出/重置，不影响正常演出。
func stop() -> void:
	_active = false
	_playback = null
	if _player != null:
		_player.stop()
		_player.stream = null


## 每帧补齐音频缓冲。采样时间连续，因此拖帧也不会丢拍。
func update() -> void:
	if not _active or clock == null or _player == null:
		return
	if clock.is_paused():
		return
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
