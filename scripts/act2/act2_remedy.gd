extends RefCounted
## 第一关补救的剧情动作适配。只读真实动作，不改演员、道具或阶段。

const PREPARE_MS: int = 8000
const STEPS: Dictionary = {
	"qing_exit": 2,
	"cup_take": 1,
	"cup_pass": 0,
	"drink": 0,
	"bend": 0,
	"medicine_exit": 1,
	"darken": 0,
	"replace": 0,
	"snake_entry": 3,
	"reveal": 3,
	"return": 1,
	"restore_0": 0,
	"restore_1": 1,
	"restore_2": 2,
	"restore_3": 3,
}
var system := RemedySystem.new()
var clock: MusicClock
var current_step: String = ""
var _since_real: int = 0
var _attempted: Dictionary = {}
var _events: Array[Dictionary] = []


func setup(value: MusicClock) -> void:
	clock = value
	var cues: Array = []
	for id: String in STEPS:
		cues.append({"cue_id": id, "action": id, "target_object": STEPS[id]})
	system.setup(cues, clock)
	current_step = ""
	_attempted.clear()
	_events.clear()


func active() -> bool:
	return system.has_open_windows()


func remaining_ms() -> int:
	return system.remaining_ms(system.current_demo_cue_id, clock.get_real_time_ms())


func update(actions: RefCounted, on_stage: Array[int], exposure: float) -> void:
	if clock.is_paused():
		return
	var completed: Array[String] = []
	if actions.qing_departed:
		completed.append("qing_exit")
	if actions.cup_owner >= 0 or actions.drunk:
		completed.append("cup_take")
	if actions.cup_owner == 0 or actions.drunk:
		completed.append("cup_pass")
	if actions.drunk:
		completed.append("drink")
	if actions.bent:
		completed.append("bend")
	if actions.medicine_departed:
		completed.append("medicine_exit")
	if exposure <= actions.DARK_LIMIT or actions.white_removed:
		completed.append("darken")
	if actions.white_removed:
		completed.append("replace")
	if actions.phase in ["reveal", "return", "startled", "finished"]:
		completed.append("snake_entry")
	if (
		on_stage.has(3)
		and exposure >= actions.REVEAL_LIMIT
		and actions.phase in ["return", "startled", "finished"]
	):
		completed.append("reveal")
	if actions.phase in ["startled", "finished"]:
		completed.append("return")
	for id: int in on_stage:
		completed.append("restore_%d" % id)
	var now: int = clock.get_real_time_ms()
	system.update_actions(clock.get_song_time_ms(), now, completed, actions.phase == "finished")
	var step: String = _step(actions, on_stage, exposure)
	if step != current_step:
		current_step = step
		_since_real = now
	if (
		not step.is_empty()
		and not _attempted.has(step)
		and not active()
		and now - _since_real >= PREPARE_MS
	):
		_attempted[step] = true
		if system.open(step, RemedySystem.REASON_MISSED, clock.get_song_time_ms(), now):
			_events.append(
				{
					"time_ms": clock.get_song_time_ms(),
					"kind": "cue_miss",
					"cue_id": step,
					"payload": {"action": step}
				}
			)
	_events.append_array(system.take_events())
	if active():
		clock.set_song_frozen(true)


func _step(actions: RefCounted, on_stage: Array[int], exposure: float) -> String:
	match actions.phase:
		"dialogue", "duet", "qing_exit", "cup", "drink", "bend", "medicine_exit":
			for id: int in [0, 1, 2]:
				if id == 2 and actions.qing_departed:
					continue
				if not on_stage.has(id):
					return "restore_%d" % id
		"replace":
			if not on_stage.has(0):
				return "restore_0"
		"reveal", "return":
			if not on_stage.has(3):
				return "restore_3"
			if exposure < actions.REVEAL_LIMIT:
				return "reveal"
			if actions.phase == "return" and not on_stage.has(1):
				return "restore_1"
	if actions.phase == "cup":
		return "cup_take" if actions.cup_owner < 0 else "cup_pass"
	return actions.phase if STEPS.has(actions.phase) else ""


func take_events() -> Array[Dictionary]:
	var result := _events
	_events = []
	return result


func instruction(actions: RefCounted) -> String:
	var id: String = guide_step()
	if id.begins_with("restore_"):
		var actor: int = int(id.trim_prefix("restore_"))
		return "按 %d 让%s上场，再按空格接手" % [actor + 1, ["白素贞", "许仙", "小青", "白蛇"][actor]]
	return actions.hint()


func guide_step() -> String:
	return current_step if current_step.begins_with("restore_") else system.current_demo_cue_id
