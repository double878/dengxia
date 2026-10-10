shader_type canvas_item;
render_mode unshaded;

uniform sampler2D weave : repeat_enable, filter_linear_mipmap;
uniform sampler2D transmission : filter_linear;
uniform vec2 cloth_origin = vec2(66.0, 92.0);
uniform vec2 cloth_size = vec2(1788.0, 588.0);
uniform vec2 projection_size = vec2(1920.0, 1080.0);
uniform float exposure = 1.0;
uniform float oil = 1.0;
uniform float distance = 0.5;
uniform float flicker = 1.0;
uniform float visual_seconds = 0.0;
uniform float softness = 0.9;
uniform bool front_view = false;

void fragment() {
	vec2 face_uv = UV;
	if (front_view) { face_uv.x = 1.0 - face_uv.x; }
	vec2 projected_uv = (cloth_origin + face_uv * cloth_size) / projection_size;
	vec2 step_uv = vec2(softness, softness * 1.24) / projection_size;
	vec3 transmitted = texture(transmission, projected_uv).rgb * 0.40;
	transmitted += texture(transmission, projected_uv + vec2(step_uv.x, 0.0)).rgb * 0.12;
	transmitted += texture(transmission, projected_uv - vec2(step_uv.x, 0.0)).rgb * 0.12;
	transmitted += texture(transmission, projected_uv + vec2(0.0, step_uv.y)).rgb * 0.12;
	transmitted += texture(transmission, projected_uv - vec2(0.0, step_uv.y)).rgb * 0.12;
	transmitted += texture(transmission, projected_uv + step_uv).rgb * 0.03;
	transmitted += texture(transmission, projected_uv - step_uv).rgb * 0.03;
	transmitted += texture(transmission, projected_uv + vec2(step_uv.x, -step_uv.y)).rgb * 0.03;
	transmitted += texture(transmission, projected_uv + vec2(-step_uv.x, step_uv.y)).rgb * 0.03;
	// 透射率在离屏纹理中以 sRGB 编码相乘，幕面在线性空间调制光。
	transmitted = pow(max(transmitted, vec3(0.0)), vec3(2.2));
	float grey = dot(transmitted, vec3(0.2126, 0.7152, 0.0722));
	transmitted = mix(vec3(grey), transmitted, front_view ? 1.0 : 0.72);
	transmitted = mix(vec3(1.0), transmitted, mix(0.10, 1.0, exposure));
	float fibres = (texture(weave, UV * cloth_size / 512.0).r - 0.502) * 0.42;
	vec2 edge_px = min(UV, 1.0 - UV) * cloth_size;
	float edge = min(edge_px.x, edge_px.y);
	float hem = 0.90 + 0.10 * smoothstep(3.0, 14.0, edge);
	float seam = exp(-abs(edge - 6.0) * 1.7) * 0.022;
	float tension = sin((edge_px.x + edge_px.y * 0.7) * 0.20) * exp(-edge_px.x / 50.0 - edge_px.y / 42.0) * 0.017;
	float light = (0.70 + 0.17 * UV.y) * (0.65 + 0.35 * oil) * flicker;
	light *= 0.93 + 0.07 * (1.0 - pow(abs(UV.x - 0.5) * 2.0, 2.0));
	light *= 0.97 + 0.03 * distance;
	vec3 cloth = mix(vec3(0.82, 0.80, 0.73), vec3(0.95, 0.90, 0.77), 0.38 + 0.12 * UV.y);
	vec3 linear_color = pow(cloth, vec3(2.2)) * light * transmitted * (hem + fibres + tension - seam);
	vec3 display = pow(max(linear_color, vec3(0.0)), vec3(1.0 / 2.2));
	float grain = fract(sin(dot(floor(UV * cloth_size), vec2(12.9898, 78.233)) + visual_seconds * 0.11) * 43758.5453) - 0.5;
	COLOR = vec4(display + grain * 0.002, 1.0);
}
