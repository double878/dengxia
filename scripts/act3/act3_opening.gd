extends Node2D
## 正式第三关幕后山景；后续盗草操演从此场景继续。

const CLOTH := CStageBinding.CLOTH

var _surface: StageSurface
var _binding: CStageBinding
var _lamp: PlaceholderLamp
var _lamp_state := LampState.new()


func _ready() -> void:
	var backdrop := StageBackdrop.new()
	backdrop.name = "StageBackdrop"
	backdrop.z_index = -2
	add_child(backdrop)
	_surface = StageSurface.new()
	_surface.name = "StageSurface"
	_surface.z_index = -1
	add_child(_surface)
	_surface.configure(CLOTH)
	_surface.sync_puppets([], [])
	_surface.update_light(_lamp_state, 0, 0, 96.0)
	_binding = CStageBinding.new()
	_binding.name = "CStageBinding"
	_binding.stage_id = 3
	_binding.enable_rain = false
	add_child(_binding)
	_lamp = PlaceholderLamp.new()
	_lamp.name = "OilLamp"
	_lamp.lamp = _lamp_state
	_lamp.cloth_rect = CLOTH
	_lamp.z_index = 30
	add_child(_lamp)
	_build_hud()


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "Hud"
	add_child(hud)
	var title := Label.new()
	title.text = "第三关 · 盗仙草"
	title.position = Vector2(84, 18)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("#e7c590"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(title)
	var detail := Label.new()
	detail.text = "为救官人，白素贞奔赴仙山。"
	detail.position = Vector2(84, 724)
	detail.add_theme_font_size_override("font_size", 24)
	detail.add_theme_color_override("font_color", Color("#cbb894"))
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(detail)
