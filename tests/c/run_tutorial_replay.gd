extends SceneTree
## 共用宿主的第 2 教学关仍可挂起/换头，并回放既有合成节拍。
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("TUTORIAL_REPLAY: " + label)


func _run() -> void:
	var game: Node = load("res://scenes/game_flow.tscn").instantiate()
	root.add_child(game)
	game._intro_finished()  # 跳过已独立验证的首页与片头。
	var level: Node = game._level
	level.set_process(false)
	var harness: Level1Harness = level._harness
	var stage_ok: bool = level._stage_def.id == 2
	check(stage_ok, "本测试应带 -- stage=2")
	if not stage_ok:
		# 缺参数时下面取到的全是第 1 关的东西，harness 之后会在 Nil 上崩、
		# 脚本错误后 quit() 永不执行，进程会一直挂着（实测挂满 20 分钟不退出）。
		# 提前干净退出，让调用方直接从退出码看出是「参数没带」而不是「功能坏了」。
		game.queue_free()
		await process_frame
		print("TUTORIAL_REPLAY checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	harness.clock.set_player(null)
	var controller: PuppetController = harness.runtime.puppet_controller
	check(controller.hook_current(), "教学关无法挂起")
	harness.advance_steps(1)
	check(controller.take_back(0), "教学关无法取回")
	controller.swap_head(0)
	harness.advance_steps(1)
	for _i in range(10000):
		if harness.runtime.is_over():
			break
		harness.advance_steps(1)
	level._process(0)
	var record: CPerformanceRecord = harness.capture.record
	check(record.validate_invariants().is_empty(), "教学记录无效")
	check(harness.capture.problems.is_empty(), "教学录制拒绝了真实事件")
	if game._flow == null:
		game.queue_free()
		await process_frame
		quit(1)
		return
	for kind: String in ["puppet_hook", "puppet_take_back", "head_swap"]:
		check(
			record.events.any(func(e: Variant) -> bool: return str(e.kind) == kind), "未录制 " + kind
		)
	game._choose_replay(true)
	var replay: Node = game._replay
	replay.set_process(false)
	check(replay._metronome != null, "教学关回放漏接既有节拍音源")
	replay.toggle_pause()
	check(replay._metronome.clock.is_paused(), "教学回放暂停未冻结音频")
	replay.toggle_pause()
	check(not replay._metronome.clock.is_paused(), "教学回放不能恢复音频")
	game._skip_replay()
	game.queue_free()
	await process_frame
	print("TUTORIAL_REPLAY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
