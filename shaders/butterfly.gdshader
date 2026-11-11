// 蝴蝶：两片翅膀绕身体扇动，颜色来自实例颜色
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 light_tint : source_color = vec3(1.0, 1.0, 1.0);

void vertex() {
	float ang = sin(TIME * 17.0 + INSTANCE_CUSTOM.x * 6.2832) * 0.95 + 0.25;
	float side = sign(VERTEX.x);
	float ax = abs(VERTEX.x);
	VERTEX.x = side * ax * cos(ang);
	VERTEX.y += ax * sin(ang);
}

void fragment() {
	float edge = smoothstep(0.62, 0.78, UV.x + (UV.y - 0.5) * 0.15);
	vec3 c = mix(COLOR.rgb, COLOR.rgb * 0.12, edge);
	ALBEDO = c * light_tint;
}
