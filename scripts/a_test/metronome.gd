extends Node
class_name Metronome
## 仅用于 A 测试目录的临时节拍音。
##
## B 的正式锣鼓音轨尚未交付，按范围限定：不改 B 的正式音频目录、
## 不引用任何素材文件，而是用 AudioStreamGenerator 现场合成短促脉冲，
## 供 MusicClock 有一个真实的音频播放位置可读。
## 每 accent_every 拍加重音，其余轻音，便于人耳确认拍点。

const SAMPLE_RATE_FALLBACK: float = 44100.0
const ACCENT_HZ: float = 1320.0
const NORMAL_HZ: float = 880.0
const CLICK_SECONDS: float = 0.06
const ACCENT_GAIN: float = 0.5
const NORMAL_GAIN: float = 0.3

var clock: MusicClock = null

var _player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _mix_rate: float = SAMPLE_RATE_FALLBACK
var _active: bool = false
var _beat_cursor: int = -1
var _accent_every: int = 4


func setup(p_clock: MusicClock, accent_every: int = 4) -> void:
	clock = p_clock
	_accent_every = maxi(accent_every, 1)
	_beat_cursor = -1
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
	_beat_cursor = -1


## 有序停播并释放音频播放对象。退出前调用，避免音频线程在引擎清理时仍持有播放缓冲。
## 仅用于退出/重置，不影响正常演出。
func stop() -> void:
	_active = false
	_playback = null
	if _player != null:
		_player.stop()
		_player.stream = null


## 每帧调用：clock 跨过新拍时往缓冲里写入一个脉冲。
func update() -> void:
	if not _active or clock == null or _playback == null:
		return
	if clock.is_paused():
		return
	var beat_index: int = clock.get_beat_index()
	if beat_index < _beat_cursor:
		_beat_cursor = beat_index        # 时钟回退时重新对齐
	if beat_index <= _beat_cursor and _beat_cursor >= 0:
		return
	_beat_cursor = beat_index
	_push_click((beat_index % _accent_every) == 0)


## 把一个衰减脉冲写进音频缓冲。缓冲不足时整拍跳过，不阻塞主线程。
func _push_click(accent: bool) -> void:
	if _playback == null:
		return
	var total: int = int(CLICK_SECONDS * _mix_rate)
	if _playback.get_frames_available() < total:
		return
	var f: float = ACCENT_HZ if accent else NORMAL_HZ
	var gain: float = ACCENT_GAIN if accent else NORMAL_GAIN
	for i in total:
		var t: float = float(i) / _mix_rate
		var envelope: float = exp(-t * 55.0)
		var value: float = sin(TAU * f * t) * gain * envelope
		_playback.push_frame(Vector2(value, value))
