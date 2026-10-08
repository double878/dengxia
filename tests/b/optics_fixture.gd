extends Node2D
## 真正经过 blend_mul 与幕面 shader 的色片、孔和重叠，不是公式的镜像测试。
var sample_texture: ImageTexture


func _ready() -> void:
	var sample := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	sample.fill(Color(204.0 / 255.0, 46.0 / 255.0, 26.0 / 255.0, 128.0 / 255.0))
	sample_texture = ImageTexture.create_from_image(sample)

func _draw() -> void:
	var red := Color(0.80, 0.18, 0.10, 1.0)
	draw_rect(Rect2(300, 160, 120, 40), red)
	draw_rect(Rect2(300, 240, 120, 40), red)
	draw_rect(Rect2(300, 200, 40, 40), red)
	draw_rect(Rect2(380, 200, 40, 40), red)
	draw_rect(Rect2(540, 160, 100, 120), red)
	draw_rect(Rect2(580, 160, 100, 120), red)
	# 在幕面外的样本只能进入离屏纹理，不得污染边框或后台。
	draw_rect(Rect2(4, 28, 30, 15), red)
	draw_texture_rect(sample_texture, Rect2(800, 160, 120, 120), false)
	draw_rect(Rect2(960, 160, 120, 120), Color(204.0 / 255.0, 46.0 / 255.0, 26.0 / 255.0, 128.0 / 255.0))
