// 飘落的花瓣（粒子用）：每片花瓣自己翻滚
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 light_tint : source_color = vec3(1.0, 1.0, 1.0);

void vertex() {
	float r = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	float a = TIME * (1.5 + r * 2.5) + r * 40.0;
	float b = TIME * (1.0 + r * 1.7) + r * 17.0;
	vec3 p = VERTEX;
	p = vec3(p.x, p.y * cos(a) - p.z * sin(a), p.y * sin(a) + p.z * cos(a));
	p = vec3(p.x * cos(b) + p.z * sin(b), p.y, -p.x * sin(b) + p.z * cos(b));
	VERTEX = p;
}

void fragment() {
	vec2 c = (UV - 0.5) * 2.0;
	float w = 0.8 * sqrt(clamp(1.0 - c.y * c.y, 0.0, 1.0)) * (0.7 + 0.3 * c.y);
	if (abs(c.x) > w) {
		discard;
	}
	ALBEDO = COLOR.rgb * light_tint * mix(0.82, 1.0, UV.y);
	ALPHA = COLOR.a;
}
