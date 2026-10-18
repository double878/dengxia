extends RefCounted
## 出山前等实际靠山；鹿童跳出后自由操演，唱腔不再受姿态、退场或灯光限制。
var clock: MusicClock
var controller: PuppetController
var config: Dictionary = {}
var gates: Array = []
var index: int = 0
var phase: String = "ready"
var waiting: bool = false
var wait_step: String = ""
var completed: Array[String] = []
var free_performance: bool = false
var departure_requested: bool = false
var remedy := RemedySystem.new()
var _wait_since: int = 0
var _attempted: Dictionary = {}
var _events: Array[Dictionary] = []


func setup(time: MusicClock, actors: PuppetController, score: Dictionary) -> void:
	clock = time
	controller = actors
	config = score
	gates = config.gates
	var cues: Array = []
	for gate: Dictionary in gates:
		cues.append({"cue_id": gate.id, "action": gate.id, "target_object": gate.actor})
	for id in range(2):
		cues.append({"cue_id": "restore_%d" % id, "action": "restore", "target_object": id})
	remedy.setup(cues, clock)


func start() -> void:
	phase = str(gates[0].id)
	clock.start()


func update(on_stage: Array[int], exposure: float, guard_triggered: bool = false) -> void:
	if phase in ["ready", "error", "finished", "awaiting_material"] or clock.is_paused():
		return
	var now: int = clock.get_song_time_ms()
	if guard_triggered and not free_performance:
		free_performance = true
		phase = "free_performance"
		if not wait_step.is_empty():
			_emit("opera_wait_end", {"step": wait_step})
		wait_step = ""
		waiting = false
		# 关闭出山前已有的示范，保留其原记录；自由操演不再开启补救。
		var entrance_done: Array[String] = ["entrance", "challenge", "restore_0", "restore_1"]
		remedy.update_actions(now, clock.get_real_time_ms(), entrance_done)
		_events.append_array(remedy.take_events())
		_emit("opera_phase_changed", {"phase": phase})
	if free_performance:
		clock.set_song_frozen(now >= int(config.duration_ms))
		if departure_requested and on_stage.has(0):
			departure_requested = false
			phase = "free_performance"
		if now >= int(config.duration_ms):
			var next: String = "awaiting_material"
			if bool(config.get("complete", false)):
				next = (
					"finished" if departure_requested and not on_stage.has(0) else "awaiting_exit"
				)
			if phase != next:
				phase = next
				_emit("opera_phase_changed", {"phase": phase})
		return
	var hold: bool = false
	var step: String = ""
	if index > 0 and not on_stage.has(0):
		hold = true
		step = "restore_0"
	elif index > 0 and exposure < 0.30:
		hold = true
		step = str(gates[mini(index, gates.size() - 1)].id)
	elif index < gates.size() and now >= int(gates[index].at_ms):
		if _satisfied(str(gates[index].id), on_stage, exposure):
			completed.append(str(gates[index].id))
			index += 1
			phase = str(gates[index].id) if index < gates.size() else "closing"
			_emit("opera_phase_changed", {"phase": phase})
		elif index != 0 or now >= int(gates[1].at_ms):
			# 空山前奏从开演即播；到拦路字头前才等待实际走近山脚。
			hold = true
			step = str(gates[index].id)
	if step != wait_step:
		if not wait_step.is_empty():
			_emit("opera_wait_end", {"step": wait_step})
		wait_step = step
		_wait_since = clock.get_real_time_ms()
		if not step.is_empty():
			_emit("opera_wait_begin", {"step": step})
	waiting = hold
	var done: Array[String] = completed.duplicate()
	for id: int in on_stage:
		done.append("restore_%d" % id)
	remedy.update_actions(now, clock.get_real_time_ms(), done)
	if hold and clock.get_real_time_ms() - _wait_since >= 8000 and not _attempted.has(step):
		_attempted[step] = true
		remedy.open(step, RemedySystem.REASON_MISSED, now, clock.get_real_time_ms())
	_events.append_array(remedy.take_events())
	clock.set_song_frozen(hold)


func _satisfied(id: String, on_stage: Array[int], exposure: float) -> bool:
	if not on_stage.has(0) or exposure < 0.30:
		return false
	var white: PuppetState = controller.get_puppet(0)
	var ground: float = white.stage_pos.y * 1080.0
	if absf(ground - 642.0) > 25.0:
		return false
	if id == "entrance":
		return white.stage_pos.x >= 0.24 and white.facing > 0 and white.turn_progress >= 0.99
	return false


func subtitle() -> String:
	var now: int = clock.get_song_time_ms()
	for line: Dictionary in config.get("lines", []):
		if now >= int(line.start_ms) and now < int(line.end_ms):
			return "%s：%s" % [line.role_name, line.text]
	return ""


func intent() -> String:
	if wait_step.begins_with("restore_"):
		return "请%s回到幕上，再续演。" % ["白素贞", "鹿童"][int(wait_step.trim_prefix("restore_"))]
	if phase == "finished":
		return "盗仙草 · 收势。"
	if phase == "awaiting_material":
		return "本段原声已播完，可继续自由操演。"
	if phase == "awaiting_exit":
		return "谢别离场 · 可按 W 跃起，再右键白素贞退场。"
	if departure_requested:
		return "白素贞已离场 · 原声收尾。"
	if free_performance:
		if clock.get_song_time_ms() >= int(config.get("finale", {}).get("farewell_ms", 2147483647)):
			return "谢别离场 · 可按 W 跃起，再右键白素贞退场。"
		return "自由操演 · 随唱腔发挥身段。"
	return str(gates[mini(index, gates.size() - 1)].intent) if not gates.is_empty() else ""


func actor_exited(id: int) -> void:
	if (
		id != 0
		or not free_performance
		or not bool(config.get("complete", false))
		or clock.get_song_time_ms() < int(config.get("finale", {}).get("farewell_ms", 2147483647))
	):
		return
	departure_requested = true
	_emit("opera_phase_changed", {"phase": "departure"})


func _emit(kind: String, payload: Dictionary) -> void:
	_events.append(
		{
			"kind": kind,
			"time_ms": clock.get_song_time_ms(),
			"object_id": "performance_audio",
			"cue_id": "",
			"payload": payload
		}
	)


func take_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out
