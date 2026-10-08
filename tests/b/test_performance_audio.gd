extends RefCounted

const TestBase := preload("res://tests/a/a_test_base.gd")
const SCORE_PATH := "res://scripts/b/audio_score.gd"
const AUDIO_PATH := "res://scripts/b/performance_audio.gd"


func run_all() -> Dictionary:
	var t := TestBase.new()
	t.begin("唱腔音频接入模块可用")
	if not ResourceLoader.exists(SCORE_PATH) or not ResourceLoader.exists(AUDIO_PATH):
		t.check(false, "缺少 AudioScore / PerformanceAudio，尚不能同步真人分轨")
		return _result(t)
	var score: RefCounted = load(SCORE_PATH).make_act1()
	_test_timeline(t, score)
	_test_validation(t, score)
	_test_states(t, score)
	return _result(t)


func _result(t: ATestBase) -> Dictionary:
	return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed}


func _test_timeline(t: ATestBase, score: RefCounted) -> void:
	t.begin("剧情字幕按歌曲时间推进，过门无台词")
	for pair in [[4999, ""], [5000, "xiaoqing_01"], [9999, "xiaoqing_01"],
			[10000, ""], [12500, "xuxian_01"], [20000, ""],
			[22500, "baisuzhen_01"], [30000, ""], [37500, "baisuzhen_02"],
			[45000, ""], [47500, "xuxian_02"], [52500, ""], [55000, ""]]:
		t.check_eq(str(score.line_at(pair[0]).get("line_id", "")), pair[1],
			"字幕边界 %d ms" % pair[0])
	t.check_eq(score.validate().size(), 0, "配置合法")
	t.finish("五句轮唱与过门连续推进")


func _test_validation(t: ATestBase, score: RefCounted) -> void:
	t.begin("拒绝错位或缺失正式音源")
	var missing: RefCounted = load(SCORE_PATH).make_act1()
	missing.tracks[0]["path"] = "res://assets/audio/does-not-exist.wav"
	var bundle: Dictionary = missing.load_bundle()
	t.check(not bundle["problems"].is_empty(), "未交付录音应明确列出缺轨")
	var streams: Dictionary = _streams(score)
	t.check_eq(score.validate_streams(streams).size(), 0, "同起点同长度的 PCM 分轨可接入")
	streams.erase("vocal_xuxian")
	t.check(not score.validate_streams(streams).is_empty(), "缺男声不得伪装为完整素材")
	streams = _streams(score)
	streams["vocal_xuxian"] = _wav(54.0)
	t.check(not score.validate_streams(streams).is_empty(), "男声短一秒应报错")
	streams = _streams(score)
	streams["drums"].loop_mode = AudioStreamWAV.LOOP_FORWARD
	t.check(not score.validate_streams(streams).is_empty(), "主锣鼓循环会破坏幕末，必须拒绝")
	var broken: RefCounted = load(SCORE_PATH).make_act1()
	broken.lines[1]["start_ms"] = 9000
	t.check(not broken.validate().is_empty(), "拒绝重叠轮唱")
	broken = load(SCORE_PATH).make_act1()
	broken.lines[0]["role_id"] = "unknown"
	t.check(not broken.validate().is_empty(), "拒绝无声轨的角色")
	t.finish("缺轨、长度、循环与角色错误可发现")


func _test_states(t: ATestBase, score: RefCounted) -> void:
	t.begin("补救、嵌套菜单暂停、字幕与音频事件")
	var audio: Node = load(AUDIO_PATH).new()
	Engine.get_main_loop().root.add_child(audio)
	var clock := MusicClock.new()
	t.check(audio.setup(score, clock, _streams(score)), "真实 WAV 分轨应建立同步播放器")
	clock.set_player(audio.get_player(), 96.0)
	clock.start()
	audio.start()
	for pair in [[12000, 0.0], [12250, -4.5], [12500, -9.0],
			[20000, -9.0], [20300, -4.5], [20600, 0.0]]:
		clock.set_free_time_ms(pair[0])
		audio.update(0.02, 0.5)
		t.check_approx(audio.get_player().stream.get_sync_stream_volume(1), pair[1], 0.01,
			"器乐入唱与尾腔处平滑让位：%d ms" % pair[0])
		t.check_approx(audio.get_player().stream.get_sync_stream_volume(0), 0.0, 0.001,
			"锣鼓不随器乐让位")
	audio.take_events()
	clock.set_free_time_ms(12500)
	audio.update(0.02, 0.5)
	t.check_eq(audio.current_line()["role_id"], "xuxian", "男声由剧情角色决定")
	t.check(audio.get_player().stream is AudioStreamSynchronized, "五轨用同一宿主")
	t.check_eq(audio.get_player().stream.stream_count, 5, "正式五轨齐全")
	var changed: Array = audio.take_events()
	audio.update(0.02, 0.5)
	t.check_eq(audio.take_events().size(), 0, "同一唱句不反复触发事件")
	t.check(not changed.is_empty(), "唱句变化可由记录端消费")
	for e in changed:
		t.check(e.has("time_ms") and e.has("kind") and e.has("object_id")
			and e.has("cue_id") and e.has("payload"), "沿用 TimedEvent 外壳")
		t.check(e["payload"].has("real_time_ms") and e["payload"].has("sequence")
			and e["payload"].has("audio_version"), "事件保留真实时钟、顺序和版本")
	audio.update(0.5, 0.0)
	t.check(audio.vocal_gain_db() < -2.0 and audio.vocal_gain_db() >= -6.0,
		"唱腔随表现转弱但保留可懂度")
	clock.set_song_frozen(true)
	audio.update(0.2, 0.0)
	t.check(audio.get_player().stream_paused, "补救真正暂停全部主分轨")
	t.check(audio.get_slow_player().playing, "慢鼓接管，不拉低真人声调")
	t.check_eq(audio.current_line()["line_id"], "xuxian_01", "冻结时保留当前句")
	clock.pause()
	audio.update(0.2, 0.0)
	t.check(audio.get_slow_player().stream_paused, "菜单暂停也暂停慢鼓")
	clock.resume()
	audio.update(0.2, 0.0)
	t.check(audio.get_player().stream_paused and not audio.get_slow_player().stream_paused,
		"菜单恢复时先继续补救")
	clock.set_song_frozen(false)
	audio.update(0.5, 1.0)
	t.check(not audio.get_player().stream_paused, "解冻原位置续播")
	t.check(not audio.get_slow_player().playing, "过渡后慢鼓不遗留")
	t.check_approx(audio.vocal_gain_db(), 0.0, 0.001, "补救结束恢复唱腔增益")
	audio.stop()
	t.check(not audio.get_player().playing and not audio.get_slow_player().playing,
		"收场全部停声")
	t.check(audio.current_line().is_empty(), "收场清空字幕")
	clock.start()
	audio.start()
	audio.update(0.02, 0.5)
	t.check(audio.current_line().is_empty(), "重开回到器乐开场")
	audio.stop()
	clock.set_player(null)
	audio.free()
	t.finish("暂停、补救、续播、事件与重开正确")


static func _wav(seconds: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 48000
	var samples := PackedByteArray()
	samples.resize(int(seconds * 48000.0) * 2)
	stream.data = samples
	return stream


static func _streams(score: RefCounted) -> Dictionary:
	var out := {}
	for track in score.tracks:
		out[track["asset_id"]] = _wav(55.0)
	out["remedy_slow"] = _wav(5.0)
	return out
