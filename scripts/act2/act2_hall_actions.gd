extends RefCounted
## 第二幕动作许可与短字幕。只用唯一时钟，不以超时替演。

const CUP_POSITION := Vector2(1035, 415)
const DARK_LIMIT: float = 0.20
const REVEAL_LIMIT: float = 0.65
const LINES: Array[Dictionary] = [
	{"role": "许仙", "text": "娘子，今日端阳，陪我饮一杯吧。", "ms": 2800},
	{"role": "小青", "text": "官人，姐姐不善饮酒，莫再劝了。", "ms": 2800},
	{"role": "许仙", "text": "我想与娘子单独说说话，小青，你去多买些酒菜吧。", "ms": 4000},
	{"role": "白素贞", "text": "小青，你就去吧。", "ms": 2600},
	{"role": "许仙", "text": "娘子，就饮这一杯吧。", "ms": 3000},
	{"role": "白素贞", "text": "官人……我身子有些不适。", "ms": 3000},
	{"role": "许仙", "text": "娘子稍候，我去取些药来。", "ms": 3000},
]

var clock: MusicClock
var phase: String = "dialogue"
var line_index: int = 0
var cup_owner: int = -1
var cup_hand: String = ""
var qing_departed: bool = false
var drunk: bool = false
var medicine_departed: bool = false
var white_removed: bool = false
var returned: bool = false
var collapse_progress: float = 0.0
var _since_song: int = 0
var _since_real: int = 0
var _drink_since: int = -1
var _exposure: float = 1.0


func setup(value: MusicClock) -> void:
	clock = value
	_set_phase("dialogue")


func _set_phase(value: String) -> void:
	phase = value
	_since_song = clock.get_song_time_ms()
	_since_real = clock.get_real_time_ms()
	clock.set_song_frozen(value not in ["dialogue", "startled"])


func update(on_stage: Array[int], hands: Array[Dictionary], mouths: Array[Vector2], positions: Array[Vector2], exposure: float, snake_position: Vector2 = Vector2.ZERO, xu_facing: float = -1.0) -> void:
	_exposure = exposure
	if hands.size() < 3 or mouths.size() < 3 or positions.size() < 3:
		push_error("第二幕动作输入缺少三人几何")
		clock.set_song_frozen(true)
		return
	match phase:
		"dialogue":
			var ready: bool = on_stage.has(0) and on_stage.has(1) and (qing_departed or on_stage.has(2))
			clock.set_song_frozen(not ready)
			if ready and clock.get_song_time_ms() - _since_song >= int(LINES[line_index].ms):
				if line_index == 3:
					_set_phase("qing_exit")
				elif line_index == 4:
					_set_phase("cup")
				elif line_index == 6:
					_set_phase("medicine_exit")
				else:
					line_index += 1
					_set_phase("dialogue")
		"cup":
			if not on_stage.has(0) or not on_stage.has(1):
				return
			if cup_owner == -1:
				var pick: String = _near_hand(hands[1], CUP_POSITION, 26.0)
				if not pick.is_empty():
					cup_owner = 1
					cup_hand = pick
			elif cup_owner == 1:
				var receive: String = _near_hand(hands[0], hands[1][cup_hand], 26.0)
				if not receive.is_empty():
					cup_owner = 0
					cup_hand = receive
					_set_phase("drink")
		"drink":
			if on_stage.has(0) and on_stage.has(1) and hands[0][cup_hand].distance_to(mouths[0]) <= 24.0:
				if _drink_since < 0:
					_drink_since = clock.get_real_time_ms()
				if clock.get_real_time_ms() - _drink_since >= 550:
					drunk = true
					line_index = 5
					_set_phase("dialogue")
			else:
				_drink_since = -1
		"darken":
			if exposure <= DARK_LIMIT:
				_set_phase("replace")
		"reveal":
			if on_stage.has(3) and exposure >= REVEAL_LIMIT:
				_set_phase("return")
		"return":
			var gap: float = positions[1].x - snake_position.x
			if returned and on_stage.has(1) and on_stage.has(3) and exposure >= REVEAL_LIMIT and absf(gap) <= 340.0 and xu_facing * gap < 0.0:
				_set_phase("startled")
		"startled":
			collapse_progress = clampf(float(clock.get_real_time_ms() - _since_real) / 1500.0, 0.0, 1.0)
			if collapse_progress >= 1.0:
				_set_phase("finished")


func _near_hand(hands: Dictionary, target: Vector2, radius: float) -> String:
	var result: String = ""
	var closest: float = radius
	for hand: String in ["left", "right"]:
		var point: Vector2 = hands.get(hand, Vector2.INF)
		if point.is_finite() and point.distance_to(target) <= closest:
			closest = point.distance_to(target)
			result = hand
	return result


func leave(id: int, at_edge: bool) -> void:
	if id == 2 and phase == "qing_exit" and at_edge:
		qing_departed = true
		line_index = 4
		_set_phase("dialogue")
	elif id == 1 and phase == "medicine_exit" and at_edge:
		medicine_departed = true
		_set_phase("darken")
	elif id == 0 and phase == "replace" and _exposure <= DARK_LIMIT:
		white_removed = true
		cup_owner = -1
		cup_hand = ""
		_set_phase("snake_entry")


func can_enter(id: int) -> bool:
	if phase in ["startled", "finished"]:
		return false
	if id == 0:
		return not white_removed
	if id == 2:
		return not qing_departed
	if id == 1:
		return not medicine_departed or phase == "return"
	return id == 3 and can_enter_snake()


func can_enter_snake() -> bool:
	return drunk and medicine_departed and white_removed and phase == "snake_entry" and _exposure <= DARK_LIMIT


func snake_entered() -> void:
	if can_enter_snake():
		_set_phase("reveal")


func enter_return() -> void:
	if phase == "return" and medicine_departed:
		returned = true


func subtitle() -> String:
	if phase == "dialogue":
		return "%s：%s" % [LINES[line_index].role, LINES[line_index].text]
	if phase == "qing_exit":
		return "白素贞：小青，你就去吧。"
	if phase in ["cup", "drink"]:
		return "许仙：娘子，就饮这一杯吧。"
	if phase == "medicine_exit":
		return "许仙：娘子稍候，我去取些药来。"
	if phase in ["startled", "finished"]:
		return "许仙见白蛇，惊退倒地。" if phase == "startled" else "许仙惊死 · 第二幕动作结束"
	return ""


func hint() -> String:
	match phase:
		"dialogue": return "身段自由发挥 · 空格换人 · 拖手、拖头、Alt 拖躯干"
		"qing_exit": return "接手小青，向左走到台边，再右键点影人退场买酒菜"
		"cup": return "接手许仙，拖手到桌上红杯；持杯走近白素贞，双手靠近递酒" if cup_owner < 0 else "许仙已持杯 · 接手两人，让白素贞的手靠近酒杯接过"
		"drink": return "接手白素贞，把持杯手拖到嘴边，保持片刻饮酒"
		"medicine_exit": return "白素贞的不适身段自由发挥 · 接手许仙，走到右台边后退场取药"
		"darken": return "许仙已去取药 · 按住 Q 压暗灯影，再收走白素贞"
		"replace": return "灯已压暗 · 右键点白素贞收走，准备完整白蛇替身"
		"snake_entry": return "保持暗灯 · 按 4 上完整白蛇，空格接手可拖头和躯干"
		"reveal": return "白蛇已上场 · 按住 E 调亮灯影显形"
		"return": return "按 2 让许仙从右台边回来，空格接手后向白蛇走近"
		"startled": return "许仙见白蛇，惊退、仰倒"
		"finished": return "第二幕动作完成 · ESC 可暂停 · 本幕暂无整关录放"
	return ""
