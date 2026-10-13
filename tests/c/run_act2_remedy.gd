extends SceneTree
## 第二幕真实动作的补救，不允许示范手替玩家完成剧情。

const ActionsInput := preload("res://tests/c/run_act2_actions.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ACT2_REMEDY: " + label)


func _run() -> void:
	var hall: Node = load("res://scenes/act2/hall.tscn").instantiate()
	root.add_child(hall)
	hall.set_process(false)
	await process_frame
	ActionsInput.advance(hall, 14.0)
	check(hall.actions.phase == "qing_exit", "先出现小青离场的自然目标")
	var help: Variant = hall.get("remedy")
	check(help != null, "正式第二幕应接入第一关补救系统")
	if help != null:
		ActionsInput.advance(hall, 2.0)
		check(not help.active(), "正常准备期不立刻示范")
		ActionsInput.advance(hall, 6.0)
		check(help.active(), "目标未完成后出现师父补救")
		check(hall._remedy_banner.visible, "补救有可见提示")
		check(hall._remedy_audio.playing, "补救复用第一关慢锣鼓")
		var song: int = hall.clock.get_song_time_ms()
		var oil: float = hall.lamp_controller.lamp.oil
		var remaining: int = help.remaining_ms()
		ActionsInput.key(hall, KEY_ESCAPE)
		ActionsInput.advance(hall, 4.0)
		check(help.remaining_ms() == remaining, "菜单暂停冻结补救倒计时")
		check(not hall._remedy_banner.visible and hall._remedy_audio.stream_paused, "暂停隐藏示范并暂停声音")
		ActionsInput.key(hall, KEY_ESCAPE)
		ActionsInput.advance(hall, 1.0)
		check(
			hall.clock.get_song_time_ms() == song and hall.lamp_controller.lamp.oil == oil,
			"补救不消耗歌曲时间与灯油"
		)
		ActionsInput.take(hall, 2)
		ActionsInput.drag(hall, hall._views[2].torso_screen_position(), Vector2(-430, 0))
		ActionsInput.right(hall, 2)
		check(hall.actions.qing_departed and not help.active(), "玩家真正走边退场后结束补救")
		check(
			(
				help.system.records[0].close_reason == RemedySystem.CLOSE_SUCCESS
				and help.system.records[0].missed
			),
			"成功仍保留原补救失误"
		)
		ActionsInput.advance(hall, 4.0)
		ActionsInput.advance(hall, 9.0)
		check(help.active(), "下一项取杯漏做可独立补救")
		ActionsInput.advance(hall, 9.0)
		check(
			not help.active() and hall.actions.phase == "cup" and hall.actions.cup_owner == -1,
			"补救超时不取杯、不跳剧情"
		)
		var count: int = help.system.records.size()
		ActionsInput.advance(hall, 20.0)
		check(help.system.records.size() == count, "同一步超时后不重复开窗")
		ActionsInput.take(hall, 1)
		ActionsInput.drag(
			hall,
			hall._views[1].hand_screen_position("right"),
			Vector2(1035, 415) - hall._views[1].hand_screen_position("right")
		)
		check(hall.actions.cup_owner == 1, "超时后仍可真实取杯")
		ActionsInput.advance(hall, 9.0)
		check(help.active() and help.current_step == "cup_pass", "递杯与取杯为不同恢复目标")
		var pose: Vector2 = hall.controller.get_puppet(0).stage_pos
		ActionsInput.right(hall, 0)
		check(
			help.instruction(hall.actions).contains("按 1") and help.guide_step() == "restore_0",
			"补救期间误退演员改提示恢复原角色"
		)
		ActionsInput.key(hall, KEY_1)
		check(
			hall.controller.get_puppet(0).stage_pos == pose and hall.actions.cup_owner == 1,
			"恢复不改姿态和道具归属"
		)
	hall.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("ACT2_REMEDY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
