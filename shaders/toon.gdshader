// 通用卡通着色：硬边两段明暗 + 边缘光 + 可选顶部苔藓（石头/树干用）
shader_type spatial;
render_mode world_vertex_coords;

uniform vec3 albedo : source_color = vec3(0.6, 0.6, 0.6);
uniform vec3 moss_color : source_color = vec3(0.36, 0.56, 0.26);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.0;
uniform float band_threshold : hint_range(-1.0, 1.0) = 0.1;
uniform float band_softness : hint_range(0.001, 0.5) = 0.04;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.25;

varying float v_up;

void vertex() {
	v_up = NORMAL.y;
}

void fragment() {
	float moss = smoothstep(0.45, 0.75, v_up) * moss_amount;
	vec3 c = mix(albedo, moss_color, moss);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = c * rim * rim_strength;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(band_threshold - band_softness, band_threshold + band_softness, ndl);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI;
}
