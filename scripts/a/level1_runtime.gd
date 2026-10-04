extends RefCounted
class_name Level1Runtime
## A 侧运行编排。时钟由场景驱动；本类只消费同一歌曲时间。
##
## 名字沿用第一关，但**编排本身与关卡无关**：`setup(clock, stage_id)` 用
## `StageDef.make_stage(stage_id)` 取任意一关的数据，四关共用这一套接线。
## 保留文件名与类名是为了不动 `tests/a/`、`scripts/a_test/` 里对它的引用。

const StageDefScript := preload("res://scripts/a/stage_def.gd")
const PuppetControllerScript := preload("res://scripts/a/puppet_controller.gd")
const StageDirectorScript := preload("res://scripts/a/stage_director.gd")
const LampControllerScript := preload("res://scripts/a/lamp_controller.gd")

var clock: MusicClock = null
var stage_def: StageDef = null
var puppet_controller: PuppetController = null
var director: StageDirector = null
var lamp_controller: LampController = null

var _started: bool = false
var _events: Array[Dictionary] = []


func setup(p_clock: MusicClock, p_stage_id: int = 1) -> bool:
	if p_clock == null:
		push_error("Level1Runtime.setup 缺少 MusicClock")
		return false
	clock = p_clock
	stage_def = StageDefScript.make_stage(p_stage_id)
	if stage_def == null:
		push_error("Level1Runtime.setup 收到未知关卡编号：%d" % p_stage_id)
		return false
	var problems: Array[String] = stage_def.validate()
	if not problems.is_empty():
		for problem in problems:
			push_error("第 %d 关数据校验失败：%s" % [stage_def.id, problem])
		return false
	puppet_controller = PuppetControllerScript.new()
	puppet_controller.clock = clock
	puppet_controller.setup(3)
	# 油灯必须先建：判定系统要拿它的 LampState 读灯位/倾灯类落点的读数。
	lamp_controller = LampControllerScript.new()
	lamp_controller.clock = clock
	lamp_controller.setup()
	director = StageDirectorScript.new()
	director.setup(stage_def, clock, puppet_controller.puppets, lamp_controller.lamp)
	_events.clear()
	_started = false
	return true


func start() -> void:
	if _started or director == null:
		return
	_started = true
	director.start()
	_events.append_array(director.take_events())


## 调用方先推进 MusicClock，再传入同帧 delta；状态和事件都在本次调用内完成。
##
## 顺序说明：判定（director.update）读的是**本帧**的影人状态与**上一帧**的灯状态。
## 灯油/火苗反馈依赖判定结果，而判定又读灯位读数，两者互为输入，无法在同一帧内互相看见。
## 这里选择让灯滞后一帧（60 Hz 下 17 ms，远小于 ±250 ms 的判定容差），
## 而不是让判定结果滞后一帧——后者会把「命中/错拍」晚一帧报给显示与录制。
func tick(delta: float) -> void:
	if not _started or is_over() or clock.is_paused():
		return
	puppet_controller.tick(delta)
	var controller_events: Array[Dictionary] = puppet_controller.take_events()
	director.update(controller_events)
	var director_events: Array[Dictionary] = director.take_events()
	_queue_events(controller_events)
	_queue_events(director_events)
	_queue_events(lamp_controller.update(delta, director_events))
	if director.is_over():
		lamp_controller.finish_show()
		_queue_events(lamp_controller.take_events())


func set_paused(value: bool) -> void:
	if clock == null or is_over():
		return
	if value:
		clock.pause()
		puppet_controller.set_input_map({})
		lamp_controller.set_input_map({})
	else:
		clock.resume()


func is_over() -> bool:
	return director != null and director.is_over()


## A 的对外事件出口：B/C 在本帧读取状态后取走，取走即清空。
func take_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_events)
	_events.clear()
	return out


func _queue_events(events: Array[Dictionary]) -> void:
	for source in events:
		var event: Dictionary = source.duplicate(true)
		event["time_ms"] = mini(int(event["time_ms"]), stage_def.duration_ms)
		if event["kind"] == "stage_end":
			event["payload"]["song_time_ms"] = event["time_ms"]
		_events.append(event)
