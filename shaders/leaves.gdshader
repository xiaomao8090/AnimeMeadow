// 树冠里填缝的"芯"：只从叶片之间的缝里看得到，所以画成没有高光、没有明暗分界的一团深色树叶，
// 不能像实心的球（以前有边缘光和硬的明暗线，看起来像树里塞了块石头）
shader_type spatial;
render_mode world_vertex_coords;

uniform vec2 wind_dir = vec2(1.0, 0.35);
uniform float sway = 0.12;
uniform float wind_speed = 1.0;
uniform vec3 shade_tint : source_color = vec3(0.55, 0.72, 0.80);

varying float v_up;

void vertex() {
	vec2 d = normalize(wind_dir);
	float t = TIME * wind_speed;
	float s = sin(t * 1.3 + VERTEX.x * 0.35 + VERTEX.z * 0.3)
			+ 0.3 * sin(t * 3.4 + VERTEX.x * 1.9 + VERTEX.y * 1.6 + VERTEX.z * 1.3);
	VERTEX.xz += d * s * sway;
	VERTEX.y += 0.25 * sway * sin(t * 2.1 + VERTEX.x * 1.2 + VERTEX.z * 1.5);
	v_up = NORMAL.y;
}

void fragment() {
	vec3 base = COLOR.rgb;
	// 下暗上亮，模拟树冠内部的遮挡
	float g = smoothstep(-0.6, 0.8, v_up);
	vec3 c = mix(base * shade_tint * 0.8, base * 0.92, g * 0.6);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	// 很平的受光：几乎不分亮面暗面，看不出是个球
	float ndl = dot(NORMAL, LIGHT);
	float lit = 0.45 + 0.25 * smoothstep(-0.4, 0.6, ndl);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI;
}
