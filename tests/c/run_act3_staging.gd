extends SceneTree
## 用户确认的舞台构图：山外落点、固定山脚顺序、自由玩家及无灵芝。
const Entrance := preload("res://scripts/act3/guard_entrance.gd")
const Finale := preload("res://scripts/act3/finale_choreography.gd")
var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ACT3_STAGING: " + label)


func _initialize() -> void:
	var score: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/audio/act3-mountain/score.json")
	)
	var crane_end: int = 0
	for line: Dictionary in score.lines:
		if line.role_name == "鹤童":
			crane_end = int(line.end_ms)
	check(int(score.finale.start_ms) >= crane_end, "仙翁不得在鹤童整句结束前出场")
	for x: float in [.56, .65, .82]:
		var actors := PuppetController.new()
		actors.setup(3)
		var white: PuppetState = actors.get_puppet(0)
		white.stage_pos = Vector2(x, Entrance.GROUND_Y / 1080.0)
		white.facing = 1
		white.turn_progress = 1
		var entrance := Entrance.new()
		entrance.setup(CStageBinding.CLOTH)
		var on_stage: Array[int] = [0]
		entrance.update(1.0, actors, on_stage, 28000, 27560)
		var deer: PuppetState = actors.get_puppet(1)
		check(deer.stage_pos.x * 1920 < entrance._edge_x - 100, "鹿童身体留出山缘余量：%s" % x)
		check(absf(deer.stage_pos.x - white.stage_pos.x) * 1920 >= 135, "落点避开白素贞身体：%s" % x)
		check(deer.facing * (white.stage_pos.x - deer.stage_pos.x) > 0, "落地面朝白素贞：%s" % x)
	for x: float in [.12, .30, .56, .87]:
		var actors := PuppetController.new()
		actors.setup(3)
		actors.get_puppet(0).stage_pos.x = x
		var original: Dictionary = actors.get_puppet(0).to_dict()
		var finale := Finale.new()
		finale.setup(score)
		var on_stage: Array[int] = [0, 2]
		for tick in range(1000):
			finale.update(
				1.0 / 60, int(score.finale.start_ms) + roundi(tick * 1000.0 / 60), actors, on_stage
			)
			if tick in [0, 300, 600, 999]:
				check(finale.herb_owner == -1 and finale.gift_progress == 0, "结尾全程不演递草")
		var elder_x: float = finale.elder.stage_pos.x
		var crane_x: float = actors.get_puppet(2).stage_pos.x
		var deer_x: float = actors.get_puppet(1).stage_pos.x
		check(elder_x < crane_x and crane_x < deer_x, "固定仙翁、鹤童、鹿童左右顺序：%s" % x)
		check(crane_x - elder_x >= .095 and deer_x - crane_x >= .095, "三人不挤在一起：%s" % x)
		check(elder_x > .48 and deer_x < .76, "三人在山脚前景保留左侧操作空间：%s" % x)
		check(not finale.elder_behind and not finale.deer_behind, "就位后处于山前完整显示：%s" % x)
		check(actors.get_puppet(0).to_dict() == original, "自动站位不接管白素贞：%s" % x)
	print("ACT3_STAGING checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
