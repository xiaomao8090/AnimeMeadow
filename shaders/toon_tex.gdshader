// 带贴图的卡通着色（AI 生成的模型用）：贴图颜色 + 硬边两段明暗 + 边缘光
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform vec3 albedo : source_color = vec3(1.0);
uniform float band_threshold : hint_range(-1.0, 1.0) = 0.0;
uniform float band_softness : hint_range(0.001, 0.5) = 0.05;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.15;

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * albedo;
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = c * rim * rim_strength;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	DIFFUSE_LIGHT += smoothstep(band_threshold - band_softness, band_threshold + band_softness, ndl) * ATTENUATION * LIGHT_COLOR / PI;
}
