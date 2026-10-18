extends Control
## 复用第三关的演前戏单；只展示说明，开始信号不触碰演出时钟。

signal start_requested

const BRIEFINGS := {
	1: {
		"title": "许仙借伞",
		"story": "西湖骤雨，白素贞与小青巧遇许仙，借伞结缘。\n你操演白素贞：走近许仙，待对唱结束后抬左手接伞。\n持伞走到小青身旁，再返回许仙处还伞，让对白自然收束。",
		"controls": "拖胸签走位 · A 抬左手接伞 · Shift + A 落手 · 拖手签调整姿势\n拖头调俯仰 · Alt 拖躯干前倾 · R 复位 · 滚轮推拉灯 · Q / E 调灯 · ESC 暂停",
		"audio": "声音：角色对白与对唱 · 雨声与锣鼓"
	},
	2: {
		"title": "端阳惊变",
		"story": "端阳将至，法海登门劝酒，许仙应允，转入厅堂。\n对唱结束后，操演许仙取杯递酒，再让白素贞将杯抬至头旁，稍停饮下。\n待她弯腰诉说不适、许仙离场取药后，压暗灯影换上白蛇；许仙返回见蛇惊倒。",
		"controls": "劝酒：1 法海 / 2 许仙上场 · 空格接手 · 法海走出柳树，许仙出门迎接\n厅堂：拖手取杯递杯 · Alt 前倾 · 右键退场 · 4 白蛇上场 · Q / E 调灯 · ESC 暂停",
		"audio": "声音：角色对白与对唱 · 开场音乐"
	},
	3: {
		"title": "盗仙草",
		"story": "为救许郎，白素贞奔赴仙山，遇双童拦路，拔剑交锋。\n仙翁出山止战，赠草相助，嘱她速回镇江救夫。\n你操演白素贞；末尾谢别后，可跃起并右键退场，完成这一幕。",
		"controls": "1 白素贞上场 · 鹿童近山随重音出场 · 空格接手\n拖签走位摆剑 · W 张腿短跳 · S 压身后撤 · Alt 前倾 · R 复位 · Q / E 调灯 · ESC 暂停",
		"audio": "声音：视频原声"
	}
}

var stage_id: int = 1
var audio_note: Label
var _starting: bool = false


func _ready() -> void:
	size = Vector2(1920, 1080)
	name = "StageBriefing"
	var background := ColorRect.new()
	background.size = size
	background.color = Color("#1d2422")
	add_child(background)
	if not BRIEFINGS.has(stage_id):
		push_error("演前简介未定义关号：%d" % stage_id)
		return
	var content: Dictionary = BRIEFINGS[stage_id]
	_label("Title", Vector2(290, 220), Vector2(1340, 100), 48, content.title)
	_label("Story", Vector2(300, 365), Vector2(1320, 210), 30, content.story)
	_label("Controls", Vector2(240, 600), Vector2(1440, 110), 23, content.controls)
	audio_note = _label("AudioNote", Vector2(310, 725), Vector2(1300, 70), 23, content.audio)
	var start := Button.new()
	start.name = "StartScene"
	start.position = Vector2(740, 825)
	start.size = Vector2(440, 80)
	start.text = "开演"
	start.add_theme_font_size_override("font_size", 30)
	start.pressed.connect(_start.bind(start))
	add_child(start)


func _label(node_name: String, at: Vector2, area: Vector2, font_size: int, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = at
	label.size = area
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#e7c590"))
	add_child(label)
	return label


func _start(button: Button) -> void:
	if _starting:
		return
	_starting = true
	button.disabled = true
	start_requested.emit()
