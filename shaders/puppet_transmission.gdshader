shader_type canvas_item;
render_mode unshaded, blend_mul;

void fragment() {
	// Godot fragment 输入 COLOR 已含一次默认贴图采样。
	vec4 ink = COLOR;
	// 原稿颜色是颜料提示，alpha 是轮廓/镂空；二者不是同一个物理量。
	vec3 leather = vec3(0.045) + pow(ink.rgb, vec3(1.10)) * 0.83;
	vec3 encoded = pow(leather, vec3(1.0 / 2.2));
	// 透明孔完全透光；重叠皮片的透射率相乘，不出现叠色变亮。
	COLOR = vec4(mix(vec3(1.0), encoded, ink.a), 1.0);
}
