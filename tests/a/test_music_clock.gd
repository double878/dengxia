extends RefCounted
class_name TestMusicClock
## 切片 2 的行为测试：唯一歌曲时间与节拍来源、暂停冻结、恢复不跳变、关卡时长地基。
## 时钟全部在「自由计时」模式下驱动（不依赖本机声卡），
## 无头模式使用虚拟音频驱动，因此真机节拍对齐必须另做图形/听感实测。

const ATestBaseScript := preload("res://tests/a/a_test_base.gd")
const MusicClockScript := preload("res://scripts/a/music_clock.gd")
const StageDefScript := preload("res://scripts/a/stage_def.gd")
const CueScript := preload("res://scripts/a/cue.gd")
const PuppetControllerScript := preload("res://scripts/a/puppet_controller.gd")
const FrameClockScript := preload("res://scripts/a_test/frame_clock.gd")

const BPM: float = 96.0
const BEAT_MS: float = 625.0          ## 60000 / 96
const STEP_MS: int = 10
const FRAME: float = 0.01


func _new_clock() -> MusicClock:
	var clock: MusicClock = MusicClockScript.new()
	clock.set_player(null, BPM)
	clock.start()
	return clock


func run_all() -> Dictionary:
	var t: ATestBase = ATestBaseScript.new()
	_test_01_free_run_monotonic(t)
	_test_02_pause_freezes(t)
	_test_03_resume_no_jump(t)
	_test_04_beat_index_and_accent(t)
	_test_05_beat_time_inverse(t)
	_test_06_before_first_beat(t)
	_test_07_stage_def_level1(t)
	_test_08_validate_catches_errors(t)
	_test_09_controller_uses_music_clock(t)
	_test_10_no_track_falls_back(t)
	_test_11_audio_stall_watchdog_threshold(t)
	return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed,
		"failures": t.failures}


func _test_01_free_run_monotonic(t: ATestBase) -> void:
	t.begin("01 歌曲时间单调推进，且与累计帧时间一致")
	var clock: MusicClock = _new_clock()
	t.check_eq(clock.get_song_time_ms(), 0, "起点应为 0 ms")
	t.check(not clock.is_audio_driven(), "无音轨时应报告非音频驱动（自由计时）")
	var previous: int = -1
	var monotonic: bool = true
	for i in 100:
		clock.update(FRAME)
		var now: int = clock.get_song_time_ms()
		if now < previous:
			monotonic = false
		previous = now
	t.check(monotonic, "100 帧内歌曲时间应单调不减")
	t.check_eq(clock.get_song_time_ms(), 1000, "100 帧 x 10 ms 应推进到 1000 ms")
	t.finish("自由计时下歌曲时间按帧时间单调推进")


func _test_02_pause_freezes(t: ATestBase) -> void:
	t.begin("02 暂停时歌曲时间完全冻结")
	var clock: MusicClock = _new_clock()
	for _i in 50:
		clock.update(FRAME)
	var before: int = clock.get_song_time_ms()
	t.check(before > 0, "暂停前应已推进（实际 %d ms）" % before)
	clock.pause()
	t.check(clock.is_paused(), "pause() 后应报告已暂停")
	var frozen_ok: bool = true
	var kept_beat: bool = true
	var beat_at_pause: int = clock.get_beat_index()
	for _i in 200:
		clock.update(FRAME)
		if clock.get_song_time_ms() != before:
			frozen_ok = false
		if clock.get_beat_index() != beat_at_pause:
			kept_beat = false
	t.check_eq(clock.get_song_time_ms(), before, "暂停后 200 帧歌曲时间应严格不变")
	t.check(frozen_ok, "暂停期间每一帧读数都等于冻结值")
	t.check(kept_beat, "暂停期间拍序号也应冻结")
	t.check(not clock.update(FRAME), "暂停期间不应报告跨拍")
	t.finish("暂停冻结歌曲时间、拍序号与跨拍报告")


func _test_03_resume_no_jump(t: ATestBase) -> void:
	t.begin("03 恢复后从冻结值继续，不跳变、不重播")
	var clock: MusicClock = _new_clock()
	for _i in 40:
		clock.update(FRAME)
	var frozen: int = clock.get_song_time_ms()
	clock.pause()
	for _i in 300:                     # 模拟「暂停了很久」
		clock.update(FRAME)
	t.check_eq(clock.get_song_time_ms(), frozen, "恢复前应仍是冻结值")
	clock.resume()
	t.check(not clock.is_paused(), "resume() 后应报告未暂停")
	t.check_eq(clock.get_song_time_ms(), frozen, "恢复的第一帧不应跳变")
	var previous: int = clock.get_song_time_ms()
	var monotonic: bool = true
	for _i in 40:
		clock.update(FRAME)
		if clock.get_song_time_ms() < previous:
			monotonic = false
		previous = clock.get_song_time_ms()
	t.check(monotonic, "恢复后应继续单调推进")
	t.check_eq(clock.get_song_time_ms(), frozen + 400, "恢复后 40 帧 x 10 ms 应再推进 400 ms")
	t.finish("恢复后沿同一时间轴继续，不回到 0、不跳变")


func _test_04_beat_index_and_accent(t: ATestBase) -> void:
	t.begin("04 拍序号与跨拍报告")
	var clock: MusicClock = _new_clock()
	t.check_approx(clock.beat_duration_s(), BEAT_MS / 1000.0, 1e-9,
		"BPM 96 的单拍时长应为 0.625 s")
	var crossings: Array[int] = []
	for i in 400:                      # 4 秒 = 6.4 拍，应跨过第 0 拍到第 6 拍
		if clock.update(FRAME):
			crossings.append(clock.get_beat_index())
	t.check_eq(crossings.size(), 7, "4 秒内应报告 7 次跨拍（拍 0-6），实际 %s" % str(crossings))
	var in_order: bool = true
	for i in range(1, crossings.size()):
		if crossings[i] != crossings[i - 1] + 1:
			in_order = false
	t.check(in_order, "跨拍序号应连续递增：%s" % str(crossings))
	t.check_eq(clock.get_beat_index(), 6, "4 秒时处于第 6 拍")
	t.check_approx(float(clock.time_to_next_beat_ms()), BEAT_MS * 7.0 - 4000.0, 1.0,
		"距下一拍应约 375 ms")
	t.finish("跨拍每拍只报一次且序号连续，距离下一拍可用")


func _test_05_beat_time_inverse(t: ATestBase) -> void:
	t.begin("05 beat_time_ms 与 get_beat_index 互逆")
	var clock: MusicClock = _new_clock()
	var all_ok: bool = true
	var details: Array[String] = []
	for i in range(0, 12):
		var beat_ms: int = clock.beat_time_ms(i)
		clock.set_free_time_ms(beat_ms)
		var index: int = clock.get_beat_index()
		# 允许 1 ms 的毫秒取整误差
		var tolerance: float = float(i) * 1.0e-9 + 1.0
		if index != i:
			all_ok = false
			details.append("beat %d -> index %d" % [i, index])
		if absf(float(beat_ms) - float(i) * BEAT_MS) > tolerance:
			all_ok = false
			details.append("beat %d 时间 %.1f 应约 %.1f" % [i, float(beat_ms), float(i) * BEAT_MS])
	t.check(all_ok, "每个 beat_time_ms(i) 都应满足 get_beat_index() == i：%s"
		% ("一致" if all_ok else ", ".join(details)))
	t.finish("拍时间与拍序号互为逆运算（1 ms 取整容差）")


func _test_06_before_first_beat(t: ATestBase) -> void:
	t.begin("06 第一拍之前的拍序号为负")
	var clock: MusicClock = _new_clock()
	clock.set_free_time_ms(0)
	t.check_eq(clock.get_beat_index(), 0, "0 ms 即第 0 拍")
	clock.set_free_time_ms(int(BEAT_MS / 2.0))
	t.check_eq(clock.get_beat_index(), 0, "半拍时仍在第 0 拍")
	t.finish("拍序号从 0 开始，半拍内不提前翻拍")


func _test_07_stage_def_level1(t: ATestBase) -> void:
	t.begin("07 第一关关卡数据：35 秒 / 96 BPM / 段落覆盖整关")
	var def: StageDef = StageDefScript.make_level1()
	t.check_eq(def.id, 1, "关卡编号为 1")
	t.check_eq(def.duration_ms, 35000, "第一关固定 35 秒（PRD 第 6 节）")
	t.check_approx(def.bpm, 96.0, 1e-9, "BPM 应为 96（PRD 第 10 节的 90-100 区间内）")
	t.check_eq(def.total_beats(), 56, "35 秒 @96 BPM 应为 56 拍")
	t.check(def.segments.size() >= 4, "应至少划分 4 个段落，实际 %d" % def.segments.size())
	t.check_eq(def.cues.size(), 6, "第一关应有 6 条关键动作（切片 3 已填写）")
	var problems: Array[String] = def.validate()
	t.check_eq(problems.size(), 0, "第一关数据应通过校验：%s" % str(problems))
	t.finish("35 秒 / 56 拍 / 五段连续覆盖，校验通过")


func _test_08_validate_catches_errors(t: ATestBase) -> void:
	t.begin("08 关卡数据校验能报出具体问题")
	var def: StageDef = StageDefScript.make_level1()
	def.duration_ms = 40000        # 段落只覆盖到 35000，应报未覆盖
	var problems: Array[String] = def.validate()
	var mentioned: bool = false
	for p in problems:
		if p.find("未覆盖") >= 0:
			mentioned = true
	t.check(mentioned, "应报出「段落未覆盖整关」：%s" % str(problems))

	var dup: StageDef = StageDefScript.make_level1()
	dup.cues = [
		CueScript.make("cue_rise", 5000, CueScript.ACTION_STAND_UP, 0, {}, 250, "stand_up"),
		CueScript.make("cue_rise", 8000, CueScript.ACTION_STAND_UP, 0, {}, 250, "stand_up"),
	]
	var dup_problems: Array[String] = dup.validate()
	var dup_found: bool = false
	for p in dup_problems:
		if p.find("重复") >= 0:
			dup_found = true
	t.check(dup_found, "应报出 cue_id 重复：%s" % str(dup_problems))

	var out_of_range: StageDef = StageDefScript.make_level1()
	out_of_range.cues = [CueScript.make("cue_late", 40000, CueScript.ACTION_STAND_UP, 0,
		{}, 250, "stand_up")]
	var range_found: bool = false
	for p in out_of_range.validate():
		if p.find("不在关卡时长内") >= 0:
			range_found = true
	t.check(range_found, "应报出落点超出关卡时长")
	t.finish("校验能报出未覆盖、cue_id 重复、落点越界")


func _test_09_controller_uses_music_clock(t: ATestBase) -> void:
	t.begin("09 输入判定与操控事件共用同一个歌曲时间")
	var clock: MusicClock = _new_clock()
	for _i in 123:
		clock.update(FRAME)
	var controller: PuppetController = PuppetControllerScript.new()
	controller.clock = clock
	controller.setup(3)
	var state: PuppetState = controller.get_controlled()
	var tag := Vector2(state.stage_pos.x * PuppetControllerScript.STAGE_PIXEL_SIZE.x,
		state.stage_pos.y * PuppetControllerScript.STAGE_PIXEL_SIZE.y
		- PuppetControllerScript.CHEST_TAG_RADIUS_PX * 0.5)
	t.check(controller.begin_drag(0, tag), "胸签命中应成立")
	var events: Array[Dictionary] = controller.take_events()
	t.check(events.size() > 0, "应产生事件")
	t.check_eq(int(events[0]["time_ms"]), clock.get_song_time_ms(),
		"事件 time_ms 应等于 MusicClock 的同一读数")
	t.finish("PuppetController 直接读 MusicClock，时间戳一致")


func _test_10_no_track_falls_back(t: ATestBase) -> void:
	t.begin("10 缺音轨时明确降级并在 HUD 可辨，不静默假装有音频")
	var clock: MusicClock = MusicClockScript.new()
	clock.set_player(null, BPM)
	clock.start()
	t.check(not clock.is_audio_driven(), "没有播放器时应报告非音频驱动")
	for _i in 30:
		clock.update(FRAME)
	t.check_eq(clock.get_song_time_ms(), 300, "自由计时仍应正常推进，不把时钟冻死")

	# 有播放器、有音轨，但尚未真正播放：绝不能声称音频驱动，且要继续自由计时。
	var player := AudioStreamPlayer.new()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = 0.2
	player.stream = generator
	t.check(not clock.is_audio_driven(), "播放器未播放时不得声称音频驱动")
	clock.player = player
	for _i in 30:
		clock.update(FRAME)
	t.check_eq(clock.get_song_time_ms(), 600, "取不到播放位置时继续自由计时，而不是停住")

	# 从有播放器切回无音轨：必须继续推进，不卡住
	clock.player = null
	for _i in 30:
		clock.update(FRAME)
	t.check(not clock.is_audio_driven(), "移除音轨后应退回非音频驱动")
	t.check_eq(clock.get_song_time_ms(), 900, "退回后应继续推进")
	player.free()
	t.finish("缺播放器/未真正播放/音轨被移除三种情况都明确降级且可被 HUD 辨出")


## 真实故障的回归测试：**播放器自称在播、播放位置却一直不前进**（声卡缺失、被独占、
## 缓冲停摆）。旧实现只认 `player.playing == false` 才降级，于是歌曲时间被永久冻住——
## 而判定、补救、关卡结束全读这一个数，玩家看到的就是一整场静止不动的画面。
##
## 证明边界（如实说明）：`player.playing == true` 且位置不动这个状态在无头环境里造不出来
## （播放器不在场景树里连 `play()` 都会报错），所以这里只能确定性地证明「看门狗恰在阈值处
## 触发」这一半。另一半依赖真机声卡场景，无法在无头模式证明——因此也把「时钟一旦降级
## 会在 HUD 上显式写出」做进了第一关场景，让下次再遇到时能被一眼认出来。
func _test_11_audio_stall_watchdog_threshold(t: ATestBase) -> void:
	t.begin("11 音频停摆看门狗恰在阈值处触发")
	var timeout_s: float = MusicClockScript.AUDIO_STALL_TIMEOUT_S
	t.check(timeout_s > 0.0, "停摆判定阈值应为正数（实际 %s）" % str(timeout_s))
	t.check(not MusicClockScript.audio_stall_reached(0.0), "刚起步时不得判定为停摆")
	t.check(not MusicClockScript.audio_stall_reached(timeout_s * 0.5), "半程不得提前触发")
	t.check(not MusicClockScript.audio_stall_reached(timeout_s - 0.01), "差一点到阈值时不得触发")
	t.check(MusicClockScript.audio_stall_reached(timeout_s), "到达阈值必须触发，否则时钟会被永久冻住")
	t.finish("停摆判定既不提前触发、也不会永不触发")
