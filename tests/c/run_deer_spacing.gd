extends SceneTree
## 用户契约：鹿童出山及后续自动跳跃均不跨到白素贞左边，玩家位置不被改写。
const Entrance := preload("res://scripts/act3/guard_entrance.gd")
const Fight := preload("res://scripts/act3/fight_choreography.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DEER_SPACING: " + label)


func _run() -> void:
	var actors := PuppetController.new()
	actors.setup()
	var white: PuppetState = actors.get_puppet(0)
	var deer: PuppetState = actors.get_puppet(1)
	var score: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/act3-mountain/score.json"))
	for start: float in [.56, .68, .82, .88]:
		var entrance := Entrance.new()
		entrance.setup(Rect2(66, 92, 1788, 588))
		white.stage_pos = Vector2(start, 642.0 / 1080.0)
		white.facing = 1
		white.turn_progress = 1
		var on_stage: Array[int] = [0]
		var valid: bool = true
		for tick in range(65):
			var expected: Vector2 = white.stage_pos
			entrance.update(1.0 / 60, actors, on_stage, 30000, 27560)
			valid = valid and deer.stage_pos.x >= white.stage_pos.x and deer.stage_pos.x <= .94001
			valid = valid and white.stage_pos == expected
		check(entrance.triggered and not entrance.active, "出山完整落地 " + str(start))
		check(valid, "出山全过程留在右侧且不挪玩家 " + str(start))
	var moving := Entrance.new()
	moving.setup(Rect2(66, 92, 1788, 588))
	white.stage_pos = Vector2(.56, 642.0 / 1080.0)
	var on_stage: Array[int] = [0]
	var moving_ok: bool = true
	for tick in range(65):
		white.stage_pos.x = minf(.88, .56 + tick * .006)
		moving.update(1.0 / 60, actors, on_stage, 30000, 27560)
		moving_ok = moving_ok and deer.stage_pos.x >= white.stage_pos.x
	check(moving_ok, "玩家起跳期间逼近山脚也不被鹿童越过")
	for start: float in [.20, .56, .80, .88]:
		var fight := Fight.new()
		fight.setup(score, actors)
		white.stage_pos.x = start
		deer.stage_pos.x = minf(start + 340.0 / 1920.0, .94)
		var valid: bool = true
		var jumped: bool = false
		for tick in range(1030):
			# 中途玩家右移，验证三种招式及收势；玩家变化只由本测试写入。
			white.stage_pos.x = minf(.88, start + maxf(tick - 350, 0) * .0005)
			var expected: Vector2 = white.stage_pos
			fight._duel(deer, white, roundi(tick * 1000.0 / 60), 1.0 / 60, true)
			valid = valid and deer.stage_pos.x >= white.stage_pos.x and deer.stage_pos.x <= .94001
			valid = valid and white.stage_pos == expected
			jumped = jumped or deer.air_height > .02
		check(valid and jumped, "三种打戏动作全过程在玩家右侧 " + str(start))
	print("DEER_SPACING checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
