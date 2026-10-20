extends Control
## 首页与过场共用的独立媒体页；播放期间不创建演出场景。

signal finished

var image: Texture2D
var stream: VideoStream
var end_image: Texture2D
var _player: VideoStreamPlayer
var _image: TextureRect
var _hint: Label
var _waiting: bool = false
var _leaving: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_image = TextureRect.new()
	_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.texture = image
	add_child(_image)
	if stream == null:
		_waiting = true
		return
	_player = VideoStreamPlayer.new()
	_player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_player.expand = true
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player.stream = stream
	_player.finished.connect(_clip_finished)
	add_child(_player)
	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -62
	_hint.offset_bottom = -20
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("font_size", 24)
	_hint.add_theme_color_override("font_color", Color("#e7d5b4"))
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.text = "空格 暂停 / 继续    Esc 跳过"
	add_child(_hint)
	_player.play()
	if not _player.is_playing():
		push_error("过场视频无法播放：" + stream.resource_path)
		_clip_finished.call_deferred()


func _input(event: InputEvent) -> void:
	if _leaving:
		return
	get_viewport().set_input_as_handled()
	var clicked: bool = (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]
	)
	if _waiting:
		var key_pressed: bool = event is InputEventKey and event.pressed and not event.echo
		if clicked or (stream == null and key_pressed):
			_leave()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_player.paused = not _player.paused
			_hint.text = "已暂停 · 空格 继续    Esc 跳过" if _player.paused else "空格 暂停 / 继续    Esc 跳过"
		elif event.keycode == KEY_ESCAPE:
			_clip_finished()


func _clip_finished() -> void:
	if _leaving or _waiting:
		return
	_player.stop()
	if end_image == null:
		_leave()
		return
	_player.hide()
	_image.texture = end_image
	_hint.text = "点击任意处回到首页"
	_waiting = true


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	set_process_input(false)
	finished.emit()


func _exit_tree() -> void:
	if _player != null:
		_player.stop()
