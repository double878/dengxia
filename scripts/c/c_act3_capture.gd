extends RefCounted
## 第三幕连续演出的只读采集；四人、拔剑、实际交锋和赠草原样保存。
var record := CPerformanceRecord.new(3, 1)
var finished: bool = false
var problems: Array[String] = []
var _previous: Dictionary = {}


func capture(host: Node, events: Array = []) -> void:
	if finished or host.clock.is_paused():
		return
	var now: int = host.clock.get_real_time_ms()
	record.duration_ms = maxi(now, 1)
	var actors: Array = []
	for state: PuppetState in host.controller.puppets:
		actors.append(state.to_dict())
	while actors.size() < CSnapshot.PUPPET_COUNT:
		actors.append(PuppetState.new(actors.size()).to_dict())
	var has_audio: bool = host.audio.player != null
	var view := {
		"scene_id": 31,
		"scene_real_ms": now,
		"song_ms": host.clock.get_song_time_ms(),
		"bpm": host.clock.bpm,
		"frozen": host.clock.is_song_frozen(),
		"phase": host.actions.phase,
		"departure_requested": host.actions.departure_requested,
		"on_stage": host.on_stage.duplicate(),
		"guard_behind_mountain":
		(
			host.guard_entrance.behind_mountain
			or host.fight.phase == "deer_retreat"
			or host.finale.deer_behind
		),
		"crane_behind_mountain": host.fight.crane_behind_mountain,
		"subtitle": host.actions.subtitle(),
		"audio_version": host.audio.config.audio_version,
		"audio_available": has_audio,
		"sword_progress": host.fight.sword_progress(),
		"fight_phase": host.fight.phase,
		"finale": host.finale.recorded_view(),
		"clash_point": {"x": host.fight.flash_point.x, "y": host.fight.flash_point.y},
		"clash_strength": host.fight.flash_strength(host.clock.get_song_time_ms()),
		"audio":
		{
			"main":
			{
				"playing":
				has_audio and host.clock.get_song_time_ms() < int(host.audio.config.duration_ms),
				"paused": host.clock.is_song_frozen(),
				"position_ms": float(host.clock.get_song_time_ms())
			}
		}
	}
	var snapshot: CSnapshot = CSnapshot.from_views(
		now, actors, host.lamp_controller.lamp.to_dict(), view
	)
	if record.should_sample(now, snapshot):
		record.append_snapshot(snapshot)
	for source: Dictionary in events:
		var payload: Dictionary = source.get("payload", {}).duplicate(true)
		payload.scene_id = 31
		payload.song_time_ms = int(source.get("time_ms", view.song_ms))
		if not record.append_event(
			CTimedEvent.new(
				now,
				StringName(source.kind),
				source.get("object_id", 0),
				str(source.get("cue_id", "")),
				payload
			)
		):
			problems.append("第三幕无法录制：%s" % source.kind)
	if _previous.get("subtitle") != view.subtitle:
		record.append_event(
			CTimedEvent.new(
				now,
				&"dialogue_line_changed",
				"performance_audio",
				"",
				{"scene_id": 31, "song_time_ms": view.song_ms, "subtitle": view.subtitle}
			)
		)
	_previous = view


func finish() -> bool:
	if finished:
		return problems.is_empty()
	finished = true
	record.finish(record.duration_ms)
	problems.append_array(record.validate_invariants())
	if not problems.is_empty():
		push_error("第三幕记录不完整：" + "; ".join(problems))
	return problems.is_empty()
