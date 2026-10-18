shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/puppet_entrance.gdshaderinc"

uniform float environment = 1.0;
void fragment() {
	if (entrance_hidden()) { discard; }
	vec4 ink = COLOR;
	float grey = dot(ink.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 leather = mix(vec3(grey), ink.rgb, 0.72) * vec3(0.87, 0.81, 0.69);
	COLOR = vec4(leather * environment, ink.a);
}
