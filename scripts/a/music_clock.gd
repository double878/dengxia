extends RefCounted
class_name MusicClock
## A 范围唯一的歌曲时间与节拍来源。供输入判定、关卡结束和 8 秒补救共用。
##
## 估算方式依 TECH_DESIGN.md 第 2.1 节与 Godot 官方音乐同步方案：
## 以 AudioStreamPlayer.get_playback_position() 为唯一时间源，按**增量**累计歌曲时间
## （官方示例里的 song_position += delta 做法）；玩家听到的位置相对该读数还差一个
## AudioServer.get_output_latency()，作为常量偏移结算一次。
##
## 为什么用增量累计而不是「位置 + 自上次混音以来 − 延迟」的绝对算式：
## 实测中播放位置在暂停/恢复边界不保证按预期前进，绝对算式一旦算错就会过冲，
## 让恢复瞬间的读数倒退（把暂停时长多减了一次）。增量方案下：
## 播放位置前进多少，歌曲时间就前进多少；位置停顿就不推进；位置倒退（不期望）按 0 计，
## 因此暂停、恢复、音轨结束都天然安全，也不会漂移。
##
## 目标不是「与墙钟一致」，而是所有消费者（判定、关卡结束、补救、录制）
## 都读同一个数，使它们在玩家真正听到的位置上对齐。
##
## 暂停约定：pause() 冻结返回值，resume() 从冻结值继续同一时间轴，期间音频真的被暂停/续播。
## 绝不另开一个独立的游戏计时器。
##
## 补救冻结（set_song_frozen）与暂停**不是**一回事：
## - 补救窗口开启期间，歌曲时间与判定冻结（补救因此不吃掉关卡固定时长），
##   但**真实时间照走**——8 秒补救窗口按真实时间计时，结算后恢复 1 倍速继续。
## - 主音轨在冻结期间被暂停，解冻时与 resume() 走同一套对齐，读数不跳变。
## - 菜单暂停（pause()）连真实时间一起冻结，补救倒计时因此也跟着停（PRD 第 8 节）。
## 所有消费者仍然只读同一个歌曲时间；补救冻结的意义只是「这段时间不计入关卡」。

const DEFAULT_BPM: float = 96.0
const POSITION_EPSILON_S: float = 1.0e-6
## 音频播放位置连续多久没有前进，就判定为「音频线程没在吃数据」（声卡缺失、
## 被独占、缓冲停摆），并降级为自由计时。
## 取 0.6 s：远大于正常的混音抖动与首次填充缓冲的时间，又短到不至于让玩家
## 看到一整套冻结的画面。降级只影响时间来源，不改变任何判定规则。
const AUDIO_STALL_TIMEOUT_S: float = 0.6

var player: AudioStreamPlayer = null   ## 主音轨播放器；为 null 时退化为自由计时
var bpm: float = DEFAULT_BPM

var _active: bool = false              ## 是否以音频时钟为准
var _paused: bool = false
var _pause_song_ms: int = 0
var _free_s: float = 0.0               ## 歌曲时间累计（有音轨时由播放位置增量驱动）
var _position_s: float = 0.0           ## 上一次读到的播放位置
var _last_beat_index: int = -1
var _latency_s: float = 0.0
var _stall_s: float = 0.0                ## 音频位置停止前进的累计时长，用于判定停摆
var _song_frozen: bool = false           ## 补救冻结：只冻结歌曲时间，真实时间照走
var _real_s: float = 0.0                 ## 真实时间累计，补救窗口按它计时


## 设置主音轨播放器与 BPM。本方法不启动播放；随后必须调用 start() 才会进入音频时钟模式。
func set_player(value: AudioStreamPlayer, track_bpm: float = DEFAULT_BPM) -> void:
	player = value
	bpm = maxf(track_bpm, 1.0)


## 从 song_start_ms 开始播放主音轨并重置时间轴。同时用于「重播」与「跳到某个歌曲时间」。
## player 为 null 时只跑自由计时，is_audio_driven() 会返回 false。
func start(song_start_ms: int = 0) -> void:
	_paused = false
	_song_frozen = false
	_real_s = 0.0
	_last_beat_index = -1
	_stall_s = 0.0
	_latency_s = maxf(AudioServer.get_output_latency(), 0.0)
	var start_s: float = float(maxi(song_start_ms, 0)) / 1000.0
	var position_now: float = 0.0
	if player != null:
		player.stream_paused = false
		if start_s > 0.0:
			player.play(start_s)
		else:
			player.play()
		position_now = maxf(player.get_playback_position(), 0.0)
		_active = true
	else:
		_active = false
	_position_s = position_now
	_free_s = maxf(position_now - _latency_s, start_s)


## 每帧一次。返回本帧是否跨过了新的拍点。
func update(delta: float) -> bool:
	if _paused:
		return false
	# 真实时间与歌曲时间的区别：菜单暂停时两者一起停，补救冻结时只有歌曲时间停。
	_real_s += maxf(delta, 0.0)
	if _song_frozen:
		# 补救冻结：歌曲时间与拍点都停住，但真实时间继续走（8 秒窗口按真实时间计时）。
		# 主音轨已被暂停、播放位置不动；这里再同步一次读数，
		# 解冻时不会把冻结时长算成一次大跳。
		if _active and player != null:
			_position_s = maxf(player.get_playback_position(), 0.0)
		return false
	if _active and player != null and player.playing:
		var position_now: float = maxf(player.get_playback_position(), 0.0)
		var advanced: float = position_now - _position_s
		if advanced > POSITION_EPSILON_S:
			_free_s += advanced
			_stall_s = 0.0
		else:
			# 播放器自称在播、播放位置却不前进：音频线程没有在消费数据。
			# 这种情况下继续读播放位置会把歌曲时间永久冻住，而判定、补救、关卡结束
			# 全都读这一个数——玩家看到的就是一整场静止不动的画面。
			# 因此超时后改用自由计时，让演出照常推进，并明确报警。
			_stall_s += maxf(delta, 0.0)
			if audio_stall_reached(_stall_s):
				_active = false
				_stall_s = 0.0
				push_warning("MusicClock：音频播放位置已 %.2f s 没有前进，判定为音频停摆，改用自由计时（本轮演出不会冻结）" % AUDIO_STALL_TIMEOUT_S)
				_free_s += maxf(delta, 0.0)
		_position_s = position_now
	else:
		# 没有音轨、播放器未真正播放、或音轨已结束：退化为自由计时。
		# 明确降级而不是继续读一个不会前进的播放位置，
		# 避免音频设备缺失时把时钟冻死；is_audio_driven() 会让消费者看出当前不是音频驱动。
		# 不从播放位置重新起算，保证降级瞬间读数连续、不倒退。
		_active = false
		_stall_s = 0.0
		_free_s += maxf(delta, 0.0)
	return _detect_beat_crossing()


func pause() -> void:
	if _paused:
		return
	_pause_song_ms = get_song_time_ms()
	_paused = true
	if player != null:
		player.stream_paused = true


func resume() -> void:
	if not _paused:
		return
	_paused = false
	# 播放位置在暂停期间可能前进过（取决于混音线程何时真正停住）。
	# 把它对齐回冻结时的歌曲时间，使恢复后从冻结值继续、不把暂停时长算进歌曲时间。
	if player != null:
		_position_s = maxf(float(_pause_song_ms) / 1000.0 + _latency_s, 0.0)
		# 若补救窗口仍开着，主音轨要保持暂停，由慢鼓接管（等解冻再续播）
		player.stream_paused = _song_frozen


## 补救冻结：只冻结歌曲时间与拍点，真实时间照常推进（与 pause() 的区别见文件头）。
## 重复设置同值不做事，方便每帧按「有没有补救窗口」直接调用。
func set_song_frozen(value: bool) -> void:
	if _song_frozen == value:
		return
	_song_frozen = value
	if player == null:
		return
	if value:
		player.stream_paused = true
		return
	# 解冻：与 resume() 同一套对齐，从冻结的歌曲时间继续，不把冻结时长算进歌曲时间
	_position_s = maxf(float(get_song_time_ms()) / 1000.0 + _latency_s, 0.0)
	if not _paused:
		player.stream_paused = false


func is_song_frozen() -> bool:
	return _song_frozen


## 音频播放位置停摆是否已到判定阈值。
## 抽成静态函数有两个理由：一是让「看门狗真的会在阈值处触发」这件事能被无头测试
## 直接证明，而不是只写在注释里；二是 `player.playing == true` 却位置不动的场景
## 在无头环境造不出来，把判定与「读声卡」分开后至少这一半是可验证的。
static func audio_stall_reached(stall_s: float) -> bool:
	return stall_s >= AUDIO_STALL_TIMEOUT_S


func is_paused() -> bool:
	return _paused


## 供测试/诊断读取内部音频时钟标志。
func is_active_flag() -> bool:
	return _active


## true 表示歌曲时间来自真实音频播放位置；false 表示自由计时（无声卡或无音轨）
func is_audio_driven() -> bool:
	return _active and player != null and player.playing


func get_song_time_s() -> float:
	if _paused:
		return float(_pause_song_ms) / 1000.0
	return maxf(_free_s, 0.0)


## 唯一的歌曲时间读数，整数毫秒。
func get_song_time_ms() -> int:
	return int(round(get_song_time_s() * 1000.0))


## 真实时间。菜单暂停时不推进；补救冻结时照常推进——8 秒补救窗口按它计时。
func get_real_time_s() -> float:
	return maxf(_real_s, 0.0)


func get_real_time_ms() -> int:
	return int(round(get_real_time_s() * 1000.0))


func beat_duration_s() -> float:
	return 60.0 / maxf(bpm, 1.0)


## 当前拍序号，从 0 开始。
func get_beat_index() -> int:
	return int(floor(get_song_time_s() / beat_duration_s()))


## 第 beat_index 拍的歌曲时间（毫秒）。与 get_beat_index() 互逆。
func beat_time_ms(beat_index: int) -> int:
	return int(round(float(beat_index) * beat_duration_s() * 1000.0))


## 距离下一拍的时间，用于 HUD 与调试，不参与判定。
func time_to_next_beat_ms() -> int:
	var beat_ms: int = beat_time_ms(get_beat_index() + 1)
	return maxi(beat_ms - get_song_time_ms(), 0)


func get_output_latency_s() -> float:
	return _latency_s


## 跳到指定歌曲时间并续播。用于「重播本关」与预听某个落点。
func seek_ms(song_ms: int) -> void:
	start(song_ms)


## 剧情兜底只允许前向跳段，保留真实时间、暂停与冻结状态。
func advance_to_ms(song_ms: int) -> void:
	if song_ms < get_song_time_ms():
		push_error("MusicClock.advance_to_ms 不允许倒退")
		return
	_free_s = float(song_ms) / 1000.0
	_pause_song_ms = song_ms
	_last_beat_index = get_beat_index()
	_stall_s = 0.0
	if player != null:
		player.seek(_free_s)
		_position_s = _free_s


## 仅供测试注入：把自由计时模式的歌曲时间设为确定值，
## 用于验证 beat_time_ms 与 get_beat_index 的互逆关系。
func set_free_time_ms(value_ms: int) -> void:
	_free_s = float(maxi(value_ms, 0)) / 1000.0


func _detect_beat_crossing() -> bool:
	var index: int = get_beat_index()
	if index > _last_beat_index:
		_last_beat_index = index
		return true
	return false
