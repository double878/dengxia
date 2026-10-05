extends RefCounted
class_name ClockCheck
## 音乐时钟的「真实时间」验证序列。
##
## 为什么单独写它：同步探针（controls_probe）在 _ready() 里一口气跑完，
## 期间没有任何真实时间流逝，因此无法证明「歌曲时间确实随音频播放推进」。
## 本序列由测试场景的 _process 逐帧驱动，用真实墙钟做对照，验证：
##   1. 时钟确实由音频播放位置驱动（is_audio_driven）；
##   2. 歌曲时间推进速度与真实时间一致（不漂移）；
##   3. 暂停期间音频与歌曲时间一起冻结；
##   4. 恢复后从冻结值继续、不跳变、不重播。
##
## 听感（是否真的听见鼓点）无法由代码证明，必须人工听。

const SETTLE_FRAMES: int = 30
const MEASURE_FRAMES: int = 90
const PAUSE_FRAMES: int = 60
const RESUME_FRAMES: int = 30
const DRIFT_TOLERANCE: float = 0.15        ## 允许的相对漂移（音频缓冲与调度抖动）
const RESUME_JUMP_TOLERANCE_MS: int = 200  ## 恢复后允许的读数偏差
const MIN_PAUSE_REAL_S: float = 0.3        ## 暂停要真的持续一段真实时间，检验才有意义

const PHASE_SETTLE: int = 0
const PHASE_MEASURE: int = 1
const PHASE_PAUSED: int = 2
const PHASE_RESUME: int = 3
const PHASE_DONE: int = 4

var clock: MusicClock = null

var failures: Array[String] = []

var _phase: int = PHASE_SETTLE
var _frames: int = 0
var _wall_s: float = 0.0
var _song_start_ms: int = 0
var _frozen_ms: int = 0
var _resumed_ms: int = 0
var _resume_elapsed_s: float = 0.0
var _pause_started_us: int = 0
var _pause_real_s: float = 0.0


func start(p_clock: MusicClock) -> void:
	clock = p_clock
	_phase = PHASE_SETTLE
	_frames = 0
	_wall_s = 0.0
	_pause_real_s = 0.0
	failures.clear()
	print("")
	print("[7] 音乐时钟真实时间测量：音频驱动 / 无漂移 / 暂停冻结 / 恢复不跳变")


func is_done() -> bool:
	return _phase >= PHASE_DONE


## 每帧调用一次，delta 为真实帧间隔。必须同时推进音频节拍与时钟，否则测的不是同一条时间轴。
func step(delta: float) -> void:
	if is_done():
		return
	match _phase:
		PHASE_SETTLE:
			_step_settle()
		PHASE_MEASURE:
			_step_measure(delta)
		PHASE_PAUSED:
			_step_paused()
		PHASE_RESUME:
			_step_resume(delta)


## 打印结论并返回失败条数。
func report() -> int:
	print("")
	print("时钟实测结论：%s" % ("全部符合预期" if failures.is_empty()
		else "%d 项不符合预期" % failures.size()))
	for line in failures:
		print("  不符合预期：%s" % line)
	return failures.size()


func _step_settle() -> void:
	if _frames == 0:
		var latency_ms: float = clock.get_output_latency_s() * 1000.0
		_expect(clock.is_audio_driven(),
			"歌曲时间来自真实音频播放位置（output_latency=%.1f ms）" % latency_ms)
	_frames += 1
	if _frames >= SETTLE_FRAMES:
		_phase = PHASE_MEASURE
		_frames = 0
		_wall_s = 0.0
		_song_start_ms = clock.get_song_time_ms()


func _step_measure(delta: float) -> void:
	_wall_s += delta
	_frames += 1
	if _frames < MEASURE_FRAMES:
		return
	var song_delta_ms: int = clock.get_song_time_ms() - _song_start_ms
	var wall_ms: float = _wall_s * 1000.0
	var relative: float = absf(float(song_delta_ms) - wall_ms) / maxf(wall_ms, 1.0)
	print("  测速 %d 帧：歌曲时间推进 %d ms，真实时间 %.0f ms，相对偏差 %.2f%%"
		% [MEASURE_FRAMES, song_delta_ms, wall_ms, relative * 100.0])
	_expect(relative <= DRIFT_TOLERANCE,
		"歌曲时间推进与真实时间一致（偏差 %.2f%% ≤ %.0f%%）"
		% [relative * 100.0, DRIFT_TOLERANCE * 100.0])
	_expect(clock.is_audio_driven(), "测量期间始终由音频播放位置驱动")
	_phase = PHASE_PAUSED
	_frames = 0
	_frozen_ms = clock.get_song_time_ms()
	_pause_started_us = Time.get_ticks_usec()
	clock.pause()
	_expect(clock.is_paused(), "pause() 后时钟报告已暂停")


func _step_paused() -> void:
	_frames += 1
	var now_ms: int = clock.get_song_time_ms()
	if now_ms != _frozen_ms:
		_expect(false, "暂停期间歌曲时间被推进到 %d ms（应冻结在 %d ms）" % [now_ms, _frozen_ms])
		_phase = PHASE_RESUME
		_frames = 0
		_pause_real_s = float(Time.get_ticks_usec() - _pause_started_us) / 1000000.0
		clock.resume()
		_resumed_ms = clock.get_song_time_ms()
		return
	if _frames < PAUSE_FRAMES:
		return
	_pause_real_s = float(Time.get_ticks_usec() - _pause_started_us) / 1000000.0
	print("  暂停 %d 帧（真实 %.2f s）：歌曲时间冻结在 %d ms" % [PAUSE_FRAMES, _pause_real_s, _frozen_ms])
	_expect(_pause_real_s >= MIN_PAUSE_REAL_S,
		"暂停确实持续了一段真实时间（%.2f s ≥ %.2f s），因此「恢复不跳变」是有意义的检验"
		% [_pause_real_s, MIN_PAUSE_REAL_S])
	clock.resume()
	_expect(not clock.is_paused(), "resume() 后时钟报告未暂停")
	_resumed_ms = clock.get_song_time_ms()
	_expect(absf(float(_resumed_ms - _frozen_ms)) <= RESUME_JUMP_TOLERANCE_MS,
		"恢复瞬间读数 %d ms 贴近冻结值 %d ms（不跳变、不重播）" % [_resumed_ms, _frozen_ms])
	_phase = PHASE_RESUME
	_frames = 0
	_resume_elapsed_s = 0.0


func _step_resume(delta: float) -> void:
	_resume_elapsed_s += delta
	_frames += 1
	if _frames < RESUME_FRAMES:
		return
	var after_ms: int = clock.get_song_time_ms()
	var expected_ms: int = _frozen_ms + int(round(_resume_elapsed_s * 1000.0))
	var error_ms: int = after_ms - expected_ms
	print("  恢复后 %d 帧（真实 %.0f ms）：歌曲时间 %d ms，期望约 %d ms，误差 %d ms"
		% [RESUME_FRAMES, _resume_elapsed_s * 1000.0, after_ms, expected_ms, error_ms])
	_expect(absf(float(error_ms)) <= RESUME_JUMP_TOLERANCE_MS,
		"恢复后继续按真实速度推进（误差 %d ms ≤ %d ms），暂停时长没有被算进歌曲时间"
		% [error_ms, RESUME_JUMP_TOLERANCE_MS])
	_expect(after_ms > _frozen_ms, "恢复后歌曲时间确实继续推进：%d -> %d ms" % [_frozen_ms, after_ms])
	_expect(clock.is_audio_driven(), "恢复后仍由音频播放位置驱动")
	_phase = PHASE_DONE


func _expect(condition: bool, message: String) -> void:
	var mark: String = "OK  " if condition else "BAD "
	if not condition:
		failures.append(message)
	print("  %s %s" % [mark, message])
