extends RefCounted
class_name CLiveCapture
## 接在正式 Harness 固定步末尾。只读状态及统一事件，不推进 Runtime 或时钟。

const Record := preload("res://scripts/c/c_performance_record.gd")
const Snapshot := preload("res://scripts/c/c_snapshot.gd")
const Event := preload("res://scripts/c/c_timed_event.gd")
var record: CPerformanceRecord
var on_stage: Array = []
var finished: bool = false
var problems: Array[String] = []


func _init(stage_id: int, visible_ids: Array) -> void:
	record = Record.new(stage_id, 1)
	on_stage = visible_ids.duplicate()


func capture(harness: Object, events: Array) -> void:
	if finished or harness.paused:
		return
	var now: int = harness.clock.get_real_time_ms()
	record.duration_ms = maxi(now, 1)
	var runtime: Level1Runtime = harness.runtime
	var puppets: Array = []
	for state: PuppetState in runtime.puppet_controller.puppets:
		puppets.append(state.to_dict())
	var performance := {
		"song_ms": harness.clock.get_song_time_ms(),
		"frozen": harness.clock.is_song_frozen(),
		"waiting": harness.opera_flow != null and harness.opera_flow.is_waiting(),
		"on_stage": on_stage.duplicate(),
		"bpm": harness.clock.bpm,
		"umbrella": {},
		"audio": {}
	}
	if runtime.director.umbrella != null:
		performance.umbrella = runtime.director.umbrella.recorded_view()
	if harness.opera_audio != null:
		performance.audio = harness.opera_audio.recorded_view()
	var snap: CSnapshot = Snapshot.from_views(
		now, puppets, runtime.lamp_controller.lamp.to_dict(), performance
	)
	if record.should_sample(now, snap) or runtime.is_over():
		record.append_snapshot(snap)
	for source: Dictionary in events:
		var payload: Dictionary = source.get("payload", {}).duplicate(true)
		payload["song_time_ms"] = int(source.time_ms)
		var event: CTimedEvent = Event.new(
			int(payload.get("real_time_ms", now)),
			StringName(source.kind),
			source.object_id,
			str(source.get("cue_id", "")),
			payload
		)
		if not record.append_event(event):
			problems.append("无法录制 %s@%d" % [source.kind, now])
	if runtime.is_over():
		finished = true
		record.finish(now)
		for problem: String in record.validate_invariants():
			problems.append(problem)
		if not problems.is_empty():
			push_error("正式演出记录不完整：%s" % "; ".join(problems))
