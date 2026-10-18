// 默认为关闭；第二关实体与投影使用同一 1920×1080 舞台坐标遮罩。
uniform bool entrance_active = false;
uniform sampler2D entrance_mask : filter_nearest, repeat_disable;
varying vec2 entrance_position;

void vertex() {
	entrance_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

bool entrance_hidden() {
	return entrance_active && texture(entrance_mask, entrance_position / vec2(1920.0, 1080.0)).r > 0.5;
}
