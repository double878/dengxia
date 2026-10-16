extends RefCounted
## 第二关两场的只读适配；时间来自宿主唯一 MusicClock，不推进剧情。
var record := CPerformanceRecord.new(2, 1)
var finished: bool = false
var _offset_ms: int = 0
var _scene_id: int = 0
var _previous: Dictionary = {}
var problems: Array[String] = []


func begin_scene(host: Node, scene_id: int) -> void:
	if _scene_id != 0:
		_offset_ms = record.duration_ms + 1
	_scene_id = scene_id
	_previous.clear()
	capture(host)


func capture(host: Node, events: Array = []) -> void:
	if finished or host.clock.is_paused():
		return
	var local_ms: int = host.clock.get_real_time_ms()
	var now: int = _offset_ms + local_ms
	record.duration_ms = maxi(now, 1)
	var views: Array = []
	for puppet: PuppetState in host.controller.puppets:
		views.append(puppet.to_dict())
	# 第一场只有两人；第三具只作固定长度记录槽，on_stage 保证它不被显示。
	while views.size() < CSnapshot.PUPPET_COUNT:
		views.append(PuppetState.new(views.size()).to_dict())
	var performance: Dictionary = _view(host)
	var snap: CSnapshot = CSnapshot.from_views(
		now, views, host.lamp_controller.lamp.to_dict(), performance
	)
	if record.should_sample(now, snap):
		record.append_snapshot(snap)
	for source: Dictionary in events:
		var payload: Dictionary = source.get("payload", {}).duplicate(true)
		payload.scene_id = _scene_id
		payload.song_time_ms = int(source.get("time_ms", performance.song_ms))
		var event := CTimedEvent.new(
			_offset_ms + int(payload.get("real_time_ms", local_ms)),
			StringName(source.kind),
			source.get("object_id", 0),
			str(source.get("cue_id", "")),
			payload
		)
		if not record.append_event(event):
			problems.append("无法录制 %s@%d" % [source.kind, now])
	for pair: Array in [["phase", "opera_phase_changed"], ["subtitle", "dialogue_line_changed"]]:
		if _previous.get(pair[0]) != performance[pair[0]]:
			var payload := {"scene_id": _scene_id, "song_time_ms": performance.song_ms}
			payload[pair[0]] = performance[pair[0]]
			if not record.append_event(
				CTimedEvent.new(now, StringName(pair[1]), "performance_audio", "", payload)
			):
				problems.append("无法录制第二关阶段/字幕")
	_previous = performance


func finish() -> bool:
	if finished:
		return problems.is_empty()
	finished = true
	record.finish(record.duration_ms)
	problems.append_array(record.validate_invariants())
	if not problems.is_empty():
		push_error("第二关回放记录不完整：%s" % "; ".join(problems))
	return problems.is_empty()


func _view(host: Node) -> Dictionary:
	var opening: bool = _scene_id == 2
	var phase: String = host.dialogue.phase if opening else host.actions.phase
	var main: AudioStreamPlayer = host.dialogue.player if opening else host.audio.player
	var subtitle: String = ""
	if opening:
		var line: Dictionary = host.dialogue.get_line()
		if not line.is_empty():
			subtitle = "%s：%s" % [line.role_name, line.text]
	else:
		subtitle = host.actions.subtitle()
	var main_view: Dictionary = player_view(main)
	# 主轨的播放头与暂停语义来自唯一时钟；测试自由计时也走相同记录契约。
	main_view.playing = phase != "finished" if opening else true
	main_view.paused = host.clock.is_song_frozen()
	main_view.position_ms = float(host.clock.get_song_time_ms())
	var value := {
		"scene_id": _scene_id,
		"scene_real_ms": host.clock.get_real_time_ms(),
		"song_ms": host.clock.get_song_time_ms(),
		"frozen": host.clock.is_song_frozen(),
		"phase": phase,
		"on_stage": host.on_stage.duplicate(),
		"bpm": host.clock.bpm,
		"subtitle": subtitle,
		"audio_version":
		host.dialogue.config.audio_version if opening else host.audio.config.audio_version,
		"audio":
		{
			"main": main_view,
			"entry": player_view(host.music_cues.entry),
			"hit": player_view(host.music_cues.hit)
		}
	}
	if opening:
		value["entrance_complete"] = host._entrance_complete.duplicate()
		value["fade"] = host.dialogue.fade_amount()
		value["transition_title"] = phase == "finished"
	else:
		value["seated"] = host.seated.duplicate()
		value["fall_angle"] = host._views[1].fall_angle
		value["cup"] = {"owner": host.actions.cup_owner, "hand": host.actions.cup_hand}
		value["snake"] = host.snake.recorded_view()
		value.audio["slow"] = player_view(host._remedy_audio)
	return value


static func player_view(player: AudioStreamPlayer) -> Dictionary:
	if player == null:
		return {"playing": false, "paused": false, "position_ms": 0.0}
	return {
		"playing": player.playing or player.stream_paused,
		"paused": player.stream_paused,
		"position_ms": player.get_playback_position() * 1000.0,
		"volume_db": player.volume_db
	}
